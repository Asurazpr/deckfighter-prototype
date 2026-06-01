class_name UIManager
extends CanvasLayer

@onready var player_hp_bar: ProgressBar = %PlayerHPBar
@onready var enemy_hp_bar: ProgressBar = %EnemyHPBar
@onready var stance_bar: ProgressBar = %StanceBar
@onready var frame_label: Label = %FrameLabel
@onready var log_label: Label = %LogLabel
@onready var combat_log_label: Label = %CombatLogLabel
@onready var hand_container: HBoxContainer = %HandContainer
@onready var root: Control = $Root
@onready var top_panel: PanelContainer = $Root/TopPanel
@onready var combat_log_panel: PanelContainer = $Root/CombatLogPanel
@onready var hand_panel: PanelContainer = $Root/HandPanel

const HUD_MARGIN := 88.0
const HUD_WIDTH := 360.0
const HUD_HEIGHT := 118.0
const MAX_COMBAT_LOG_EVENTS := 8
const DETAIL_FONT_SIZE := 13
const HEADER_FONT_SIZE := 15
const PRIMARY_FONT_SIZE := 16
const CARD_FONT_SIZE := 17
const CombatDebugExporterScript := preload("res://scripts/combat/combat_debug_exporter.gd")
const PREDICTION_COLORS := {
	"interrupt": Color(0.55, 1.0, 0.62),
	"trade": Color(1.0, 0.9, 0.35),
	"too_slow": Color(1.0, 0.45, 0.42),
	"whiff": Color(0.62, 0.62, 0.62),
	"normal": Color.WHITE
}

var combat_manager: Node
var deck_manager_ref: Node
var player_ref: Node2D
var enemy_ref: Node2D
var full_combat_log_events: Array[String] = []
var combat_log_events: Array[String] = []
var card_buttons: Array[Button] = []
var player_hud_panel: PanelContainer
var enemy_hud_panel: PanelContainer
var status_hud_panel: PanelContainer
var player_stance_label: Label
var player_stance_bar: ProgressBar
var player_hud_on_left := true
var hud_side_locked := false
var main_debug_label: Label
var main_debug_panel: PanelContainer
var enemy_ai_panel: PanelContainer
var enemy_ai_label: Label
var timing_panel: PanelContainer
var timing_label: Label
var queue_label: Label
var impact_panel: PanelContainer
var impact_label: Label
var impact_bar: ProgressBar
var start_fight_button: Button
var debug_hint_label: Label
var debug_panels_visible := false
var enemy_ai_visible := true
var timing_visible := true
var combat_log_visible := false
var readability_mode_enabled := false
var combat_debug_exporter = CombatDebugExporterScript.new()

func _ready() -> void:
	_remove_space_from_ui_accept()
	_configure_static_layout()
	_build_debug_panels()
	_apply_debug_visibility()

func _process(_delta: float) -> void:
	if combat_manager == null:
		return
	_refresh_hud_side()
	if main_debug_label != null and combat_manager.has_method("get_main_hud_debug_text"):
		main_debug_label.text = combat_manager.get_main_hud_debug_text()
	if queue_label != null and combat_manager.has_method("get_queue_text"):
		queue_label.text = combat_manager.get_queue_text()
	if enemy_ai_label != null and combat_manager.has_method("get_enemy_ai_debug_text"):
		enemy_ai_label.text = combat_manager.get_enemy_ai_debug_text()
	if timing_label != null and combat_manager.has_method("get_timing_debug_text"):
		timing_label.text = combat_manager.get_timing_debug_text()
	if start_fight_button != null and combat_manager.has_method("is_fight_started"):
		start_fight_button.visible = not bool(combat_manager.is_fight_started())
	_refresh_impact_bar()
	_refresh_queue_label()

func bind(player: Node, enemy: Node, deck_manager: Node, manager: Node) -> void:
	combat_manager = manager
	deck_manager_ref = deck_manager
	player_ref = player as Node2D
	enemy_ref = enemy as Node2D
	player.hp_changed.connect(_on_player_hp_changed)
	if player.has_signal("stance_changed"):
		player.stance_changed.connect(_on_player_stance_changed)
	enemy.hp_changed.connect(_on_enemy_hp_changed)
	enemy.stance_changed.connect(_on_stance_changed)
	deck_manager.hand_changed.connect(_on_hand_changed)
	manager.frame_advantage_changed.connect(_on_frame_advantage_changed)
	manager.log_message.connect(_on_log_message)
	_lock_hud_side_from_round_start()
	_on_player_hp_changed(player.hp, player.max_hp)
	if "stance" in player and "max_stance" in player:
		_on_player_stance_changed(int(player.stance), int(player.max_stance))
	_on_enemy_hp_changed(enemy.hp, enemy.max_hp)
	_on_stance_changed(enemy.stance, enemy.max_stance)
	_on_frame_advantage_changed(manager.frame_advantage)
	_on_hand_changed(deck_manager.hand)

func _on_player_hp_changed(current_hp: int, max_hp: int) -> void:
	player_hp_bar.max_value = max_hp
	player_hp_bar.value = current_hp

func _on_player_stance_changed(current_stance: int, max_stance: int) -> void:
	if player_stance_bar == null:
		return
	player_stance_bar.max_value = max_stance
	player_stance_bar.value = current_stance

func _on_enemy_hp_changed(current_hp: int, max_hp: int) -> void:
	enemy_hp_bar.max_value = max_hp
	enemy_hp_bar.value = current_hp

func _on_stance_changed(current_stance: int, max_stance: int) -> void:
	stance_bar.max_value = max_stance
	stance_bar.value = current_stance

func _on_frame_advantage_changed(value: int) -> void:
	frame_label.text = "Frame Advantage: %d" % value
	_refresh_card_enabled_state()

func _on_log_message(message: String) -> void:
	log_label.text = message
	full_combat_log_events.append(message)
	combat_log_events.append(message)
	while combat_log_events.size() > MAX_COMBAT_LOG_EVENTS:
		combat_log_events.pop_front()
	_refresh_combat_log()

func _on_hand_changed(hand: Array) -> void:
	card_buttons.clear()
	for child in hand_container.get_children():
		child.queue_free()

	for i in range(hand.size()):
		var card: Resource = hand[i]
		var button := Button.new()
		button.custom_minimum_size = Vector2(248, 154)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_ALL
		button.text = _format_card_text(card, i)
		button.tooltip_text = _format_card_tooltip(card)
		button.add_theme_font_size_override("font_size", CARD_FONT_SIZE)
		button.mouse_entered.connect(_show_card_debug.bind(card))
		button.pressed.connect(_on_card_pressed.bind(i))
		hand_container.add_child(button)
		card_buttons.append(button)

	_refresh_card_enabled_state()

func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return

	if key_event.ctrl_pressed and key_event.keycode == KEY_F1:
		_toggle_readability_mode()
		get_viewport().set_input_as_handled()
		return

	match key_event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			var focused_index := _get_focused_card_index()
			if focused_index != -1:
				_try_play_card(focused_index)
				get_viewport().set_input_as_handled()
		KEY_1, KEY_KP_1:
			_try_play_card_from_number(0)
			get_viewport().set_input_as_handled()
		KEY_2, KEY_KP_2:
			_try_play_card_from_number(1)
			get_viewport().set_input_as_handled()
		KEY_3, KEY_KP_3:
			_try_play_card_from_number(2)
			get_viewport().set_input_as_handled()
		KEY_4, KEY_KP_4:
			_try_play_card_from_number(3)
			get_viewport().set_input_as_handled()
		KEY_F1:
			debug_panels_visible = not debug_panels_visible
			_apply_debug_visibility()
			get_viewport().set_input_as_handled()
		KEY_F2:
			enemy_ai_visible = not enemy_ai_visible
			_apply_debug_visibility()
			get_viewport().set_input_as_handled()
		KEY_F3:
			timing_visible = not timing_visible
			_apply_debug_visibility()
			get_viewport().set_input_as_handled()
		KEY_F4:
			combat_log_visible = not combat_log_visible
			_apply_debug_visibility()
			get_viewport().set_input_as_handled()
		KEY_F5:
			_export_combat_log()
			get_viewport().set_input_as_handled()
		KEY_F6:
			var scene := get_tree().current_scene
			if scene != null and scene.has_method("toggle_combat_geometry_debug"):
				scene.toggle_combat_geometry_debug()
			elif combat_manager != null and combat_manager.has_method("toggle_combat_geometry_debug"):
				combat_manager.toggle_combat_geometry_debug()
			get_viewport().set_input_as_handled()
		KEY_F7:
			var scene := get_tree().current_scene
			if scene != null and scene.has_method("toggle_camera_debug"):
				scene.toggle_camera_debug()
				get_viewport().set_input_as_handled()

func _remove_space_from_ui_accept() -> void:
	if not InputMap.has_action("ui_accept"):
		return
	for event in InputMap.action_get_events("ui_accept"):
		var key_event := event as InputEventKey
		if key_event != null and key_event.keycode == KEY_SPACE:
			InputMap.action_erase_event("ui_accept", event)

func _configure_static_layout() -> void:
	top_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_panel.position = Vector2(24, 18)
	top_panel.size = Vector2(418, 138)
	top_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.055, 0.065, 0.08, 0.88), Color(0.25, 0.34, 0.42, 0.65)))

	var stats_grid := $Root/TopPanel/TopMargin/StatsGrid as GridContainer
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 12)
	stats_grid.add_theme_constant_override("v_separation", 5)
	for child in stats_grid.get_children():
		if child is Label:
			(child as Label).add_theme_font_size_override("font_size", PRIMARY_FONT_SIZE)
		if child is ProgressBar:
			var bar := child as ProgressBar
			bar.custom_minimum_size = Vector2(245, 16)
			bar.show_percentage = false
	_style_progress_bar(player_hp_bar, Color(0.28, 0.64, 1.0))
	_style_progress_bar(enemy_hp_bar, Color(1.0, 0.34, 0.28))
	_style_progress_bar(stance_bar, Color(1.0, 0.76, 0.26))
	frame_label.add_theme_font_size_override("font_size", 14)
	frame_label.modulate = Color(0.78, 0.9, 1.0)
	log_label.add_theme_font_size_override("font_size", 13)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.clip_text = true
	_build_side_hud_panels(stats_grid)

	combat_log_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	combat_log_panel.position = Vector2(1130, 18)
	combat_log_panel.size = Vector2(446, 218)
	combat_log_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.045, 0.05, 0.06, 0.93), Color(0.24, 0.28, 0.33, 0.8)))
	combat_log_label.clip_text = true
	combat_log_label.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)

	hand_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hand_panel.offset_left = 24.0
	hand_panel.offset_top = -208.0
	hand_panel.offset_right = -24.0
	hand_panel.offset_bottom = -18.0
	hand_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.055, 0.045, 0.04, 0.92), Color(0.34, 0.26, 0.18, 0.72)))
	hand_container.add_theme_constant_override("separation", 14)

func _build_debug_panels() -> void:
	main_debug_panel = _create_debug_panel("Combat State", Vector2(24, 172), Vector2(430, 152))
	main_debug_label = main_debug_panel.get_node("Margin/Box/Body") as Label
	main_debug_label.text = "Distance: 0\nMode: Neutral\nQueue: Empty"

	enemy_ai_panel = _create_debug_panel("Enemy AI", Vector2(1130, 252), Vector2(446, 198))
	enemy_ai_label = enemy_ai_panel.get_node("Margin/Box/Body") as Label
	enemy_ai_label.text = "Enemy Tier: NORMAL\nEnemy AI State: NEUTRAL"

	timing_panel = _create_debug_panel("Frame / Timing", Vector2(1130, 466), Vector2(446, 210))
	timing_label = timing_panel.get_node("Margin/Box/Body") as Label
	timing_label.text = "Enemy base startup: 0\nEnemy effective startup: 0\nEnemy remaining startup: 0"

	queue_label = Label.new()
	queue_label.position = Vector2(330, 656)
	queue_label.size = Vector2(940, 34)
	queue_label.text = "Queue: Empty"
	queue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	queue_label.add_theme_font_size_override("font_size", 18)
	queue_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.72))
	root.add_child(queue_label)

	impact_panel = PanelContainer.new()
	impact_panel.position = Vector2(474, 118)
	impact_panel.size = Vector2(652, 118)
	impact_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.07, 0.055, 0.94), Color(0.95, 0.66, 0.2, 0.8)))
	root.add_child(impact_panel)

	var impact_margin := MarginContainer.new()
	impact_margin.add_theme_constant_override("margin_left", 18)
	impact_margin.add_theme_constant_override("margin_top", 12)
	impact_margin.add_theme_constant_override("margin_right", 18)
	impact_margin.add_theme_constant_override("margin_bottom", 12)
	impact_panel.add_child(impact_margin)

	var impact_box := VBoxContainer.new()
	impact_box.add_theme_constant_override("separation", 6)
	impact_margin.add_child(impact_box)

	impact_label = Label.new()
	impact_label.text = "Incoming: None"
	impact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	impact_label.add_theme_font_size_override("font_size", 26)
	impact_box.add_child(impact_label)

	impact_bar = ProgressBar.new()
	impact_bar.max_value = 100.0
	impact_bar.value = 0.0
	impact_bar.show_percentage = false
	impact_bar.custom_minimum_size = Vector2(580, 18)
	_style_progress_bar(impact_bar, Color(1.0, 0.62, 0.24))
	impact_box.add_child(impact_bar)

	start_fight_button = Button.new()
	start_fight_button.text = "Start Fight"
	start_fight_button.position = Vector2(690, 160)
	start_fight_button.size = Vector2(220, 54)
	start_fight_button.add_theme_font_size_override("font_size", 22)
	start_fight_button.add_theme_stylebox_override("normal", _button_style(Color(0.12, 0.22, 0.16, 0.96), Color(0.34, 0.86, 0.48, 0.86)))
	start_fight_button.add_theme_stylebox_override("hover", _button_style(Color(0.16, 0.31, 0.22, 0.98), Color(0.42, 1.0, 0.58, 0.95)))
	start_fight_button.pressed.connect(_on_start_fight_pressed)
	root.add_child(start_fight_button)

	debug_hint_label = Label.new()
	debug_hint_label.position = Vector2(934, 130)
	debug_hint_label.size = Vector2(510, 24)
	debug_hint_label.text = "F1 Debug  Ctrl+F1 Readability  F4 Log  F5 Export  F6 Boxes  F7 Cam"
	debug_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	debug_hint_label.add_theme_font_size_override("font_size", 12)
	debug_hint_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.84, 0.82))
	root.add_child(debug_hint_label)

func _build_side_hud_panels(stats_grid: GridContainer) -> void:
	top_panel.visible = false
	player_hud_panel = _create_primary_hud_panel("PlayerHUD", "PLAYER")
	enemy_hud_panel = _create_primary_hud_panel("EnemyHUD", "ENEMY")
	status_hud_panel = _create_status_hud_panel()

	var player_grid := player_hud_panel.get_node("Margin/Box/Grid") as GridContainer
	var enemy_grid := enemy_hud_panel.get_node("Margin/Box/Grid") as GridContainer
	var status_box := status_hud_panel.get_node("Margin/Box") as VBoxContainer

	_reparent_to_container(stats_grid.get_node("PlayerHPLabel"), player_grid)
	_reparent_to_container(player_hp_bar, player_grid)
	player_stance_label = Label.new()
	player_stance_label.text = "Player Stance"
	player_stance_label.add_theme_font_size_override("font_size", PRIMARY_FONT_SIZE)
	player_grid.add_child(player_stance_label)
	player_stance_bar = ProgressBar.new()
	player_stance_bar.custom_minimum_size = Vector2(245, 16)
	player_stance_bar.show_percentage = false
	_style_progress_bar(player_stance_bar, Color(0.4, 0.86, 1.0))
	player_grid.add_child(player_stance_bar)
	_reparent_to_container(stats_grid.get_node("EnemyHPLabel"), enemy_grid)
	_reparent_to_container(enemy_hp_bar, enemy_grid)
	_reparent_to_container(stats_grid.get_node("StanceLabel"), enemy_grid)
	_reparent_to_container(stance_bar, enemy_grid)
	_reparent_to_container(frame_label, status_box)
	_reparent_to_container(log_label, status_box)
	_refresh_hud_side()

func _create_primary_hud_panel(panel_name: String, title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.custom_minimum_size = Vector2(HUD_WIDTH, HUD_HEIGHT)
	panel.size = Vector2(HUD_WIDTH, HUD_HEIGHT)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.045, 0.052, 0.064, 0.9), Color(0.26, 0.34, 0.42, 0.72)))
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 5)
	margin.add_child(box)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color(0.78, 0.87, 0.95))
	box.add_child(title_label)

	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 5)
	box.add_child(grid)
	return panel

func _create_status_hud_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "StatusHUD"
	panel.position = Vector2(520, 18)
	panel.size = Vector2(560, 72)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.04, 0.05, 0.82), Color(0.22, 0.28, 0.34, 0.55)))
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 9)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)
	return panel

func _refresh_hud_side() -> void:
	if player_hud_panel == null or enemy_hud_panel == null:
		return
	if not hud_side_locked:
		_lock_hud_side_from_round_start()

	var viewport_width := _viewport_width()
	var left_position := Vector2(HUD_MARGIN, 18.0)
	var right_position := Vector2(maxf(HUD_MARGIN, viewport_width - HUD_WIDTH - HUD_MARGIN), 18.0)
	player_hud_panel.position = left_position if player_hud_on_left else right_position
	enemy_hud_panel.position = right_position if player_hud_on_left else left_position
	if status_hud_panel != null:
		status_hud_panel.position = Vector2((viewport_width - status_hud_panel.size.x) * 0.5, 18.0)

func set_round_start_hud_side(player_starts_left: bool) -> void:
	player_hud_on_left = player_starts_left
	hud_side_locked = true
	_refresh_hud_side()

func _lock_hud_side_from_round_start() -> void:
	if player_ref == null or enemy_ref == null:
		return
	player_hud_on_left = player_ref.global_position.x <= enemy_ref.global_position.x
	hud_side_locked = true

func _viewport_width() -> float:
	var visible_rect := get_viewport().get_visible_rect()
	if visible_rect.size.x > 0.0:
		return visible_rect.size.x
	if root != null and root.size.x > 0.0:
		return root.size.x
	return 1600.0

func _reparent_to_container(node: Node, container: Node) -> void:
	if node == null or container == null:
		return
	var old_parent := node.get_parent()
	if old_parent != null:
		old_parent.remove_child(node)
	container.add_child(node)

func _create_debug_panel(title: String, position: Vector2, size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = position
	panel.size = size
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.04, 0.05, 0.94), Color(0.22, 0.28, 0.36, 0.7)))
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	var header := _make_section_label(title)
	box.add_child(header)

	var body := Label.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)
	box.add_child(body)
	return panel

func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	label.add_theme_color_override("font_color", Color(0.72, 0.86, 1.0))
	return label

func _apply_debug_visibility() -> void:
	if main_debug_panel != null:
		main_debug_panel.visible = debug_panels_visible
	if enemy_ai_panel != null:
		enemy_ai_panel.visible = debug_panels_visible and enemy_ai_visible
	if timing_panel != null:
		timing_panel.visible = debug_panels_visible and timing_visible
	if queue_label != null:
		queue_label.visible = true
	if combat_log_panel != null:
		combat_log_panel.visible = debug_panels_visible and combat_log_visible
	if impact_panel != null:
		impact_panel.visible = false

func _refresh_impact_bar() -> void:
	if impact_panel == null or combat_manager == null or not combat_manager.has_method("get_impact_bar_data"):
		if impact_panel != null:
			impact_panel.visible = false
		return
	var data: Dictionary = combat_manager.get_impact_bar_data()
	impact_panel.visible = bool(data.get("visible", false))
	if not impact_panel.visible:
		return
	var hit_level := String(data.get("hit_level", "None"))
	var hit_color := _hit_level_color(hit_level)
	var display_color := Color(1.0, 0.72, 0.24) if readability_mode_enabled else hit_color
	impact_label.text = "INCOMING\nREACT" if readability_mode_enabled else "%s INCOMING\n%s" % [hit_level, _reaction_instruction(hit_level)]
	impact_label.add_theme_color_override("font_color", display_color)
	var progress := clampf(float(data.get("progress", 0.0)), 0.0, 1.0)
	impact_bar.value = (1.0 - progress) * 100.0
	_style_progress_bar(impact_bar, Color(1.0, 0.34, 0.22) if progress >= 0.8 else display_color)

func _on_card_pressed(index: int) -> void:
	_try_play_card(index)

func _on_start_fight_pressed() -> void:
	if combat_manager != null and combat_manager.has_method("start_fight"):
		combat_manager.start_fight()
	if start_fight_button != null:
		start_fight_button.visible = false
	_refresh_card_enabled_state()

func _try_play_card_from_number(index: int) -> void:
	if index >= card_buttons.size():
		return
	if not _try_play_card(index):
		_on_log_message("Card not playable.")

func _try_play_card(index: int) -> bool:
	if combat_manager == null or not combat_manager.is_hand_card_playable(index):
		if combat_manager != null and combat_manager.has_method("get_card_input_rejection_reason"):
			var reason := String(combat_manager.get_card_input_rejection_reason(index))
			if reason != "":
				_on_log_message("Card input rejected: %s." % reason)
		return false
	combat_manager.play_card(index)
	return true

func _get_focused_card_index() -> int:
	var focus_owner := get_viewport().gui_get_focus_owner()
	for i in range(card_buttons.size()):
		if card_buttons[i] == focus_owner:
			return i
	return -1

func _refresh_card_enabled_state() -> void:
	if combat_manager == null:
		return
	for i in range(card_buttons.size()):
		card_buttons[i].disabled = not combat_manager.is_hand_card_playable(i)
		card_buttons[i].modulate = _prediction_color_for_card(i)
		_apply_card_button_style(card_buttons[i], i)

func _toggle_readability_mode() -> void:
	readability_mode_enabled = not readability_mode_enabled
	if combat_manager != null and combat_manager.has_method("set_enemy_intent_ui_visible"):
		combat_manager.set_enemy_intent_ui_visible(not readability_mode_enabled)
	if deck_manager_ref != null and "hand" in deck_manager_ref:
		_on_hand_changed(deck_manager_ref.hand)
	_on_log_message("Debug Readability Mode %s." % ("ON" if readability_mode_enabled else "OFF"))

func _prediction_color_for_card(index: int) -> Color:
	if combat_manager == null or not combat_manager.has_method("get_card_prediction"):
		return Color.WHITE
	var prediction := String(combat_manager.get_card_prediction(index))
	return PREDICTION_COLORS.get(prediction, Color.WHITE)

func _format_card_text(card: Resource, index: int) -> String:
	if readability_mode_enabled:
		return "%d  %s\nDMG %d | ST %d\nStart %df | Hit +%d\nWhiff %s%d | Next: %s" % [
			index + 1,
			card.display_name,
			card.damage,
			card.stance_damage,
			card.startup_frame,
			card.frame_gain,
			"+" if int(card.whiff_frame_penalty) >= 0 else "",
			card.whiff_frame_penalty,
			_short_route_text(deck_manager_ref.get_follow_up_tags(card))
		]
	return "%d  %s\n%s | DMG %d | ST %d\nStart %df | Hit +%d\nWhiff %s%d | Next: %s" % [
		index + 1,
		card.display_name,
		card.attack_level,
		card.damage,
		card.stance_damage,
		card.startup_frame,
		card.frame_gain,
		"+" if int(card.whiff_frame_penalty) >= 0 else "",
		card.whiff_frame_penalty,
		_short_route_text(deck_manager_ref.get_follow_up_tags(card))
	]

func _format_card_tooltip(card: Resource) -> String:
	return "%s\nStartup: %df\nDamage: %d\nStance Damage: %d\nFrame Cost: %d\nFrame Gain: %d\nWhiff Penalty: %d\nTags: %s\nRoute IDs: %s" % [
		card.description,
		card.startup_frame,
		card.damage,
		card.stance_damage,
		card.frame_cost,
		card.frame_gain,
		card.whiff_frame_penalty,
		", ".join(card.tags) if not card.tags.is_empty() else "None",
		", ".join(card.allowed_follow_up_card_ids) if not card.allowed_follow_up_card_ids.is_empty() else "None"
	]

func _show_card_debug(card: Resource) -> void:
	log_label.text = "Card: %s | Start %df | DMG %d | ST %d | Cost %d | Hit +%d | Whiff %d | Tags: %s | Route: %s" % [
		card.display_name,
		card.startup_frame,
		card.damage,
		card.stance_damage,
		card.frame_cost,
		card.frame_gain,
		card.whiff_frame_penalty,
		", ".join(card.tags) if not card.tags.is_empty() else "None",
		", ".join(card.allowed_follow_up_card_ids) if not card.allowed_follow_up_card_ids.is_empty() else "None"
	]

func _refresh_combat_log() -> void:
	var text := ""
	var start_index := maxi(0, combat_log_events.size() - MAX_COMBAT_LOG_EVENTS)
	for i in range(start_index, combat_log_events.size()):
		var event := combat_log_events[i]
		if text != "":
			text += "\n"
		text += "- %s" % event
	combat_log_label.text = text

func _export_combat_log() -> void:
	var directory := "user://combat_logs"
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var path := "%s/combat_log_%s.jsonl" % [directory, timestamp]

	var context := {}
	if combat_manager != null and combat_manager.has_method("get_combat_log_export_context"):
		context = combat_manager.get_combat_log_export_context()
	var trace_events := []
	if combat_manager != null and combat_manager.has_method("get_combat_trace_events"):
		trace_events = combat_manager.get_combat_trace_events()
	var scene_path := get_tree().current_scene.scene_file_path if get_tree().current_scene != null else "unknown"
	var err: Error = combat_debug_exporter.export_jsonl(path, context, trace_events, full_combat_log_events, scene_path)
	if err != OK:
		_on_log_message("Combat log export failed: %s." % error_string(err))
	else:
		_on_log_message("Combat log exported to %s" % path)

func _refresh_queue_label() -> void:
	if queue_label == null:
		return
	var has_actions := not queue_label.text.to_lower().contains("empty")
	queue_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.86, 0.45) if has_actions else Color(0.74, 0.76, 0.78, 0.86)
	)

func _panel_style(background_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	return style

func _button_style(background_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := _panel_style(background_color, border_color)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 12.0
	style.content_margin_top = 8.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 8.0
	return style

func _style_progress_bar(bar: ProgressBar, fill_color: Color) -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.18, 0.19, 0.2, 0.92)
	background.corner_radius_top_left = 4
	background.corner_radius_top_right = 4
	background.corner_radius_bottom_right = 4
	background.corner_radius_bottom_left = 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.corner_radius_top_left = 4
	fill.corner_radius_top_right = 4
	fill.corner_radius_bottom_right = 4
	fill.corner_radius_bottom_left = 4
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)

func _apply_card_button_style(button: Button, index: int) -> void:
	var prediction_color := _prediction_color_for_card(index)
	var usable := not button.disabled
	var bg_color := Color(0.09, 0.075, 0.07, 0.96) if usable else Color(0.045, 0.045, 0.05, 0.82)
	var border_color := prediction_color if usable else Color(0.22, 0.22, 0.24, 0.8)
	var hover_color := bg_color.lightened(0.08)
	var pressed_color := bg_color.darkened(0.08)
	button.add_theme_color_override("font_color", Color(0.98, 0.94, 0.86) if usable else Color(0.5, 0.5, 0.52))
	button.add_theme_color_override("font_disabled_color", Color(0.42, 0.42, 0.44))
	button.add_theme_stylebox_override("normal", _button_style(bg_color, border_color))
	button.add_theme_stylebox_override("hover", _button_style(hover_color, border_color.lightened(0.15)))
	button.add_theme_stylebox_override("pressed", _button_style(pressed_color, border_color))
	button.add_theme_stylebox_override("disabled", _button_style(Color(0.035, 0.035, 0.04, 0.8), Color(0.16, 0.16, 0.18, 0.8)))
	button.add_theme_stylebox_override("focus", _button_style(Color(0.13, 0.12, 0.08, 0.95), Color(1.0, 0.88, 0.38, 0.95)))

func _hit_level_color(hit_level: String) -> Color:
	match hit_level.to_upper():
		"HIGH":
			return Color(0.36, 0.74, 1.0)
		"MID":
			return Color(1.0, 0.82, 0.34)
		"LOW":
			return Color(0.46, 1.0, 0.58)
		"OVERHEAD":
			return Color(1.0, 0.42, 0.36)
		_:
			return Color(0.95, 0.92, 0.84)

func _reaction_instruction(hit_level: String) -> String:
	match hit_level.to_upper():
		"HIGH":
			return "L Block | S Crouch under | Jump loses"
		"MID":
			return "L Block | S+L Low Block | Move or challenge"
		"LOW":
			return "S+L Low Block | W Jump"
		"OVERHEAD":
			return "L Stand Block | Challenge the startup"
		_:
			return "L Block | S+L Low | W Jump | Card Challenge"

func _short_route_text(raw_routes: Variant) -> String:
	var route_names: Array[String] = []
	if raw_routes is String:
		var raw_string := String(raw_routes)
		if raw_string.strip_edges() != "":
			route_names.append(raw_string)
	elif raw_routes is PackedStringArray:
		for route in raw_routes:
			route_names.append(String(route))
	elif raw_routes is Array:
		for route in raw_routes:
			route_names.append(String(route))

	var readable_names: Array[String] = []
	for route_name in route_names:
		var readable := route_name.strip_edges()
		if readable == "":
			continue
		readable = readable.replace("Light ", "L ")
		readable = readable.replace("Heavy ", "H ")
		readable = readable.replace("Punch", "P")
		readable = readable.replace("Kick", "K")
		readable_names.append(readable)

	if readable_names.is_empty():
		return "None"

	var display_count := mini(readable_names.size(), 3)
	var display_names: Array[String] = []
	for i in range(display_count):
		display_names.append(readable_names[i])
	var suffix := " ..." if readable_names.size() > display_count else ""
	return " / ".join(display_names) + suffix
