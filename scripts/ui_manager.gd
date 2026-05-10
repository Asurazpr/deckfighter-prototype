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

const MAX_COMBAT_LOG_EVENTS := 12
const DETAIL_FONT_SIZE := 13
const HEADER_FONT_SIZE := 15
const PREDICTION_COLORS := {
	"interrupt": Color(0.55, 1.0, 0.62),
	"trade": Color(1.0, 0.9, 0.35),
	"too_slow": Color(1.0, 0.45, 0.42),
	"whiff": Color(0.62, 0.62, 0.62),
	"normal": Color.WHITE
}

var combat_manager: Node
var deck_manager_ref: Node
var full_combat_log_events: Array[String] = []
var combat_log_events: Array[String] = []
var card_buttons: Array[Button] = []
var main_debug_label: Label
var enemy_ai_panel: PanelContainer
var enemy_ai_label: Label
var timing_panel: PanelContainer
var timing_label: Label
var queue_label: Label
var debug_panels_visible := true
var enemy_ai_visible := true
var timing_visible := true
var combat_log_visible := true

func _ready() -> void:
	_remove_space_from_ui_accept()
	_configure_static_layout()
	_build_debug_panels()
	_apply_debug_visibility()

func _process(_delta: float) -> void:
	if combat_manager == null:
		return
	if main_debug_label != null and combat_manager.has_method("get_main_hud_debug_text"):
		main_debug_label.text = combat_manager.get_main_hud_debug_text()
	if queue_label != null and combat_manager.has_method("get_queue_text"):
		queue_label.text = combat_manager.get_queue_text()
	if enemy_ai_label != null and combat_manager.has_method("get_enemy_ai_debug_text"):
		enemy_ai_label.text = combat_manager.get_enemy_ai_debug_text()
	if timing_label != null and combat_manager.has_method("get_timing_debug_text"):
		timing_label.text = combat_manager.get_timing_debug_text()

func bind(player: Node, enemy: Node, deck_manager: Node, manager: Node) -> void:
	combat_manager = manager
	deck_manager_ref = deck_manager
	player.hp_changed.connect(_on_player_hp_changed)
	enemy.hp_changed.connect(_on_enemy_hp_changed)
	enemy.stance_changed.connect(_on_stance_changed)
	deck_manager.hand_changed.connect(_on_hand_changed)
	manager.frame_advantage_changed.connect(_on_frame_advantage_changed)
	manager.log_message.connect(_on_log_message)
	_on_player_hp_changed(player.hp, player.max_hp)
	_on_enemy_hp_changed(enemy.hp, enemy.max_hp)
	_on_stance_changed(enemy.stance, enemy.max_stance)
	_on_frame_advantage_changed(manager.frame_advantage)
	_on_hand_changed(deck_manager.hand)

func _on_player_hp_changed(current_hp: int, max_hp: int) -> void:
	player_hp_bar.max_value = max_hp
	player_hp_bar.value = current_hp

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
		button.custom_minimum_size = Vector2(230, 168)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = _format_card_text(card)
		button.tooltip_text = _format_card_tooltip(card)
		button.mouse_entered.connect(_show_card_debug.bind(card))
		button.pressed.connect(_on_card_pressed.bind(i))
		hand_container.add_child(button)
		card_buttons.append(button)

	_refresh_card_enabled_state()

func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
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
	top_panel.size = Vector2(520, 188)

	combat_log_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	combat_log_panel.position = Vector2(1184, 18)
	combat_log_panel.size = Vector2(392, 330)
	combat_log_label.clip_text = true
	combat_log_label.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)

	hand_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hand_panel.offset_left = 24.0
	hand_panel.offset_top = -206.0
	hand_panel.offset_right = -24.0
	hand_panel.offset_bottom = -18.0

func _build_debug_panels() -> void:
	main_debug_label = Label.new()
	main_debug_label.text = "Distance: 0\nMode: Neutral\nQueue: Empty"
	main_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_debug_label.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)
	$Root/TopPanel/TopMargin/StatsGrid.add_child(_make_section_label("Combat"))
	$Root/TopPanel/TopMargin/StatsGrid.add_child(main_debug_label)

	enemy_ai_panel = _create_debug_panel("Enemy AI", Vector2(24, 224), Vector2(500, 258))
	enemy_ai_label = enemy_ai_panel.get_node("Margin/Box/Body") as Label
	enemy_ai_label.text = "Enemy Tier: NORMAL\nEnemy AI State: NEUTRAL"

	timing_panel = _create_debug_panel("Frame/Timing", Vector2(24, 496), Vector2(500, 218))
	timing_label = timing_panel.get_node("Margin/Box/Body") as Label
	timing_label.text = "Enemy base startup: 0\nEnemy effective startup: 0\nEnemy remaining startup: 0"

	queue_label = Label.new()
	queue_label.position = Vector2(552, 812)
	queue_label.size = Vector2(720, 32)
	queue_label.text = "Queue: Empty"
	queue_label.add_theme_font_size_override("font_size", 18)
	root.add_child(queue_label)

func _create_debug_panel(title: String, position: Vector2, size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = position
	panel.size = size
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
	return label

func _apply_debug_visibility() -> void:
	if enemy_ai_panel != null:
		enemy_ai_panel.visible = debug_panels_visible and enemy_ai_visible
	if timing_panel != null:
		timing_panel.visible = debug_panels_visible and timing_visible
	if queue_label != null:
		queue_label.visible = debug_panels_visible
	if combat_log_panel != null:
		combat_log_panel.visible = combat_log_visible

func _on_card_pressed(index: int) -> void:
	_try_play_card(index)

func _try_play_card_from_number(index: int) -> void:
	if index >= card_buttons.size():
		return
	if not _try_play_card(index):
		_on_log_message("Card not playable.")

func _try_play_card(index: int) -> bool:
	if combat_manager == null or not combat_manager.is_hand_card_playable(index):
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

func _prediction_color_for_card(index: int) -> Color:
	if combat_manager == null or not combat_manager.has_method("get_card_prediction"):
		return Color.WHITE
	var prediction := String(combat_manager.get_card_prediction(index))
	return PREDICTION_COLORS.get(prediction, Color.WHITE)

func _format_card_text(card: Resource) -> String:
	return "%s\nDMG %d | ST %d\nStart %df\nHit +%d | Whiff %s%d\nNext: %s" % [
		card.display_name,
		card.damage,
		card.stance_damage,
		card.startup_frame,
		card.frame_gain,
		"+" if int(card.whiff_frame_penalty) >= 0 else "",
		card.whiff_frame_penalty,
		deck_manager_ref.get_follow_up_tags(card)
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
