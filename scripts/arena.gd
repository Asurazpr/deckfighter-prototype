extends Node2D

const RunStateScript := preload("res://scripts/run/run_state.gd")

@export var stage_center_x := 800.0
@export var desired_start_distance := 220.0
@export var show_combat_geometry_debug := false
@export var arena_left_x := 0.0
@export var arena_right_x := 1600.0
@export var fighter_wall_margin := 90.0
@export var arena_top_y := 120.0
@export var arena_bottom_y := 820.0
@export var camera_baseline_y := 560.0
@export var camera_distance_padding := 1120.0
@export var camera_jump_vertical_padding := 260.0
@export var camera_jump_pan_strength := 0.35
@export var camera_jump_zoom_out_strength := 0.7
@export var min_visible_width_ratio := 0.80
@export var max_visible_width_ratio := 1.00
@export var combat_clear_visible_width_ratio := 1.0
@export var combat_clear_camera_y := 470.0
@export var camera_position_lerp_speed := 8.0
@export var camera_zoom_lerp_speed := 6.0
@export var camera_debug_enabled := false
@export var camera_debug_log_interval := 0.35
@export var min_room_gate_choices := 2
@export var max_room_gate_choices := 3
@export var rest_heal_ratio := 0.20

@onready var player = $Player
@onready var enemy = $Enemy
@onready var deck_manager = $DeckManager
@onready var combat_manager = $CombatManager
@onready var ui_manager = $UI

var center_axis_debug: Line2D
var left_wall_debug: Line2D
var right_wall_debug: Line2D
var fight_camera: Camera2D
var camera_debug_timer := 0.0
var player_round_start_y := 0.0
var enemy_round_start_y := 0.0
var room_gate_layer: Node2D
var room_gate_path_layer: Node2D
var room_gate_choices: Array[Dictionary] = []
var room_gates_revealed := false
var room_gate_selection_locked := false
var room_transition_in_progress := false
var non_combat_room_active := false
var non_combat_interaction_available := false
var non_combat_interaction_complete := false
var rest_interaction_used := false
var merchant_interaction_opened := false
var non_combat_interaction_layer: Node2D
var non_combat_interact_area: Area2D
var non_combat_prompt_label: Label
var non_combat_feedback_label: Label
var shop_canvas: CanvasLayer
var shop_overlay: Control
var shop_threads_label: Label
var shop_feedback_label: Label
var shop_skill_buttons: Dictionary = {}
var current_room_index := 0
var selected_room_type := "combat"
var selected_room_id := "debug_start"
var previous_exit_direction := "LEFT"
var next_entry_side := "LEFT"
var player_starts_left := true

const ROOM_TYPE_COMBAT := "combat"
const ROOM_TYPE_ELITE := RunStateScript.ROOM_TYPE_ELITE
const ROOM_TYPE_REST := "rest"
const ROOM_TYPE_MERCHANT := "merchant"
const ROOM_TYPE_BOSS := RunStateScript.ROOM_TYPE_BOSS
const FORCED_MERCHANT_ROOM_INDEX := 5
const EXIT_LEFT := "LEFT"
const EXIT_RIGHT := "RIGHT"
const EXIT_UP := "UP"
const EXIT_DOWN := "DOWN"
const MERCHANT_SKILLS: Array[Dictionary] = [
	{"id": "dash", "label": "Dash", "cost": 20},
	{"id": "air_dash", "label": "Air Dash", "cost": 20},
	{"id": "quick_rise", "label": "Quick Rise", "cost": 30},
	{"id": "back_roll", "label": "Back Roll", "cost": 30}
]

func _ready() -> void:
	_load_run_room_metadata()
	player_round_start_y = player.global_position.y
	enemy_round_start_y = enemy.global_position.y
	_apply_round_start_positions()
	_apply_combat_arena_bounds()
	_create_center_axis_debug()
	_create_wall_debug()
	_create_room_gate_layer()
	_create_fight_camera()
	_set_combat_geometry_debug_visible(show_combat_geometry_debug, false)
	ui_manager.bind(player, enemy, deck_manager, combat_manager)
	_apply_persisted_player_hp()
	_apply_hud_side()
	_record_encounter_side_assigned()
	_setup_selected_room_behavior()

func _process(delta: float) -> void:
	_update_fight_camera(delta)
	_update_room_gate_reveal()
	_clamp_player_to_arena_bounds()

func _input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE and _merchant_shop_open():
		_close_merchant_shop()
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_F and non_combat_room_active:
		_try_interact_non_combat_room()
		get_viewport().set_input_as_handled()

func _clamp_player_to_arena_bounds() -> void:
	if player == null or not _room_traversal_active():
		return
	var min_x: float = arena_left_x + fighter_wall_margin
	var max_x: float = arena_right_x - fighter_wall_margin
	player.global_position.x = clampf(player.global_position.x, min_x, max_x)

func _apply_round_start_positions() -> void:
	var spawn_gap := desired_start_distance * 0.5
	if player_starts_left:
		player.global_position = Vector2(stage_center_x - spawn_gap, player_round_start_y)
		enemy.global_position = Vector2(stage_center_x + spawn_gap, enemy_round_start_y)
	else:
		player.global_position = Vector2(stage_center_x + spawn_gap, player_round_start_y)
		enemy.global_position = Vector2(stage_center_x - spawn_gap, enemy_round_start_y)

func reset_round_start_positions() -> void:
	_apply_round_start_positions()
	_reset_actor_for_round_start(player)
	_reset_actor_for_round_start(enemy)
	_apply_combat_arena_bounds()
	if combat_manager != null and combat_manager.has_method("refresh_actor_facing"):
		combat_manager.refresh_actor_facing()
	_apply_hud_side()
	_record_encounter_side_assigned()
	_snap_fight_camera_to_target()

func _reset_actor_for_round_start(actor: Node) -> void:
	if actor == null:
		return
	if actor.has_method("reset_for_round_start"):
		actor.reset_for_round_start()
	elif actor is CharacterBody2D:
		(actor as CharacterBody2D).velocity = Vector2.ZERO
	if actor.has_method("clear_timeline_visual"):
		actor.clear_timeline_visual()

func _create_center_axis_debug() -> void:
	var axis := Line2D.new()
	axis.name = "CenterAxisDebug"
	axis.points = PackedVector2Array([Vector2(stage_center_x, 180.0), Vector2(stage_center_x, 690.0)])
	axis.width = 1.0
	axis.default_color = Color(0.7, 0.85, 1.0, 0.22)
	axis.z_index = 1
	axis.visible = false
	add_child(axis)
	center_axis_debug = axis

func _create_wall_debug() -> void:
	left_wall_debug = _make_wall_debug_line("LeftArenaWallDebug", arena_left_x + fighter_wall_margin)
	right_wall_debug = _make_wall_debug_line("RightArenaWallDebug", arena_right_x - fighter_wall_margin)

func _make_wall_debug_line(line_name: String, x_position: float) -> Line2D:
	var line := Line2D.new()
	line.name = line_name
	line.points = PackedVector2Array([Vector2(x_position, 170.0), Vector2(x_position, 720.0)])
	line.width = 2.0
	line.default_color = Color(1.0, 0.75, 0.25, 0.35)
	line.z_index = 2
	line.visible = false
	add_child(line)
	return line

func _create_room_gate_layer() -> void:
	room_gate_layer = Node2D.new()
	room_gate_layer.name = "RoomGateLayer"
	room_gate_layer.visible = false
	room_gate_layer.z_index = 12
	add_child(room_gate_layer)
	room_gate_path_layer = Node2D.new()
	room_gate_path_layer.name = "PathPreview"
	room_gate_path_layer.z_index = 11
	room_gate_layer.add_child(room_gate_path_layer)

func _setup_selected_room_behavior() -> void:
	if selected_room_type == ROOM_TYPE_COMBAT:
		non_combat_room_active = false
		return
	_setup_non_combat_room()

func _setup_non_combat_room() -> void:
	non_combat_room_active = true
	non_combat_interaction_complete = false
	non_combat_interaction_available = false
	rest_interaction_used = false
	merchant_interaction_opened = false
	_hide_room_gates()
	if combat_manager != null and combat_manager.has_method("enter_non_combat_room"):
		combat_manager.enter_non_combat_room(selected_room_type, selected_room_id)
	_hide_enemy_for_non_combat_room()
	if player != null:
		if player.has_method("set_input_enabled"):
			player.set_input_enabled(true)
		if player.has_method("set_free_movement_enabled"):
			player.set_free_movement_enabled(true)
	_create_non_combat_interaction_layer()
	_create_non_combat_interact_point()
	if selected_room_type == ROOM_TYPE_MERCHANT:
		_create_merchant_shop_overlay()
	_record_room_event("NON_COMBAT_ROOM_READY", {
		"room_index": current_room_index,
		"room_type": selected_room_type,
		"room_id": selected_room_id
	})

func _hide_enemy_for_non_combat_room() -> void:
	if enemy == null:
		return
	if enemy.has_method("enter_non_combat_hidden_state"):
		enemy.enter_non_combat_hidden_state()
	else:
		enemy.hide()
		enemy.set_process(false)
		enemy.set_physics_process(false)

func _create_non_combat_interaction_layer() -> void:
	non_combat_interaction_layer = Node2D.new()
	non_combat_interaction_layer.name = "NonCombatInteractionLayer"
	non_combat_interaction_layer.z_index = 18
	add_child(non_combat_interaction_layer)

	non_combat_feedback_label = Label.new()
	non_combat_feedback_label.name = "RoomFeedback"
	non_combat_feedback_label.position = Vector2(stage_center_x - 240.0, 260.0)
	non_combat_feedback_label.size = Vector2(480.0, 38.0)
	non_combat_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	non_combat_feedback_label.add_theme_font_size_override("font_size", 22)
	non_combat_feedback_label.add_theme_color_override("font_color", Color(0.94, 0.98, 1.0))
	non_combat_feedback_label.text = ""
	non_combat_interaction_layer.add_child(non_combat_feedback_label)

func _create_non_combat_interact_point() -> void:
	if non_combat_interaction_layer == null:
		return
	var interact_position := Vector2(stage_center_x, player_round_start_y - 84.0)
	non_combat_interact_area = Area2D.new()
	non_combat_interact_area.name = "RestInteractPoint" if selected_room_type == ROOM_TYPE_REST else "MerchantInteractPoint"
	non_combat_interact_area.global_position = interact_position
	non_combat_interact_area.monitoring = true
	non_combat_interact_area.monitorable = false
	non_combat_interact_area.z_index = 18
	non_combat_interaction_layer.add_child(non_combat_interact_area)

	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = Vector2(150.0, 140.0)
	shape.shape = rect_shape
	non_combat_interact_area.add_child(shape)

	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([
		Vector2(-64.0, -58.0),
		Vector2(64.0, -58.0),
		Vector2(64.0, 58.0),
		Vector2(-64.0, 58.0)
	])
	visual.color = _room_type_color(selected_room_type)
	visual.z_index = 18
	non_combat_interact_area.add_child(visual)

	var title := Label.new()
	title.position = Vector2(-88.0, -22.0)
	title.size = Vector2(176.0, 44.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.text = "REST" if selected_room_type == ROOM_TYPE_REST else "SHOP"
	title.z_index = 19
	non_combat_interact_area.add_child(title)

	non_combat_prompt_label = Label.new()
	non_combat_prompt_label.position = Vector2(-130.0, 70.0)
	non_combat_prompt_label.size = Vector2(260.0, 34.0)
	non_combat_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	non_combat_prompt_label.add_theme_font_size_override("font_size", 18)
	non_combat_prompt_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	non_combat_prompt_label.text = "Press F to rest" if selected_room_type == ROOM_TYPE_REST else "Press F to shop"
	non_combat_prompt_label.visible = false
	non_combat_prompt_label.z_index = 19
	non_combat_interact_area.add_child(non_combat_prompt_label)

	non_combat_interact_area.body_entered.connect(_on_non_combat_interact_body_entered)
	non_combat_interact_area.body_exited.connect(_on_non_combat_interact_body_exited)
	_record_room_event("ROOM_MARKER_CREATED", {
		"room_index": current_room_index,
		"room_type": selected_room_type,
		"room_id": selected_room_id,
		"marker_kind": "interact",
		"label": _room_type_label(selected_room_type, selected_room_id),
		"color": _color_to_dict(_room_type_color(selected_room_type)),
		"position": _vector_to_dict(interact_position)
	})

func _create_merchant_shop_overlay() -> void:
	shop_canvas = CanvasLayer.new()
	shop_canvas.name = "MerchantShopCanvas"
	add_child(shop_canvas)

	var overlay := ColorRect.new()
	overlay.name = "MerchantShopOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.0, 0.0, 0.0, 0.56)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	shop_canvas.add_child(overlay)
	shop_overlay = overlay

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "MerchantShopPanel"
	panel.custom_minimum_size = Vector2(500.0, 400.0)
	panel.add_theme_stylebox_override("panel", _room_panel_style(Color(0.035, 0.048, 0.07, 0.96), Color(0.36, 0.62, 1.0, 0.82)))
	center.add_child(panel)

	shop_overlay = overlay
	var shop_panel := panel
	shop_panel.name = "MerchantShopPanel"
	shop_panel.custom_minimum_size = Vector2(500.0, 400.0)
	shop_panel.add_theme_stylebox_override("panel", _room_panel_style(Color(0.035, 0.048, 0.07, 0.96), Color(0.36, 0.62, 1.0, 0.82)))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	shop_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Merchant"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Prototype movement skills"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.66, 0.76, 0.86))
	box.add_child(subtitle)

	shop_threads_label = Label.new()
	shop_threads_label.text = "Threads: 0"
	shop_threads_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_threads_label.add_theme_font_size_override("font_size", 18)
	shop_threads_label.add_theme_color_override("font_color", Color(0.96, 0.88, 0.56))
	box.add_child(shop_threads_label)

	shop_feedback_label = Label.new()
	shop_feedback_label.text = ""
	shop_feedback_label.custom_minimum_size = Vector2(420.0, 28.0)
	shop_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_feedback_label.add_theme_font_size_override("font_size", 16)
	shop_feedback_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.42))
	box.add_child(shop_feedback_label)

	for skill in MERCHANT_SKILLS:
		var skill_id: String = String(skill.get("id", ""))
		var skill_label: String = String(skill.get("label", skill_id))
		var button := Button.new()
		button.custom_minimum_size = Vector2(420.0, 42.0)
		button.text = skill_label
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(_on_shop_skill_pressed.bind(skill_id))
		box.add_child(button)
		shop_skill_buttons[skill_id] = button

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(420.0, 42.0)
	close_button.add_theme_font_size_override("font_size", 18)
	close_button.pressed.connect(_close_merchant_shop)
	box.add_child(close_button)

func _room_panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style

func _on_non_combat_interact_body_entered(body: Node) -> void:
	if body != player:
		return
	non_combat_interaction_available = true
	if non_combat_prompt_label != null:
		non_combat_prompt_label.visible = true

func _on_non_combat_interact_body_exited(body: Node) -> void:
	if body != player:
		return
	non_combat_interaction_available = false
	if non_combat_prompt_label != null:
		non_combat_prompt_label.visible = false

func _try_interact_non_combat_room() -> void:
	if not non_combat_room_active or not non_combat_interaction_available:
		return
	if _merchant_shop_open():
		return
	if selected_room_type == ROOM_TYPE_REST:
		_use_rest_interaction()
	elif selected_room_type == ROOM_TYPE_MERCHANT:
		_open_merchant_shop()

func _use_rest_interaction() -> void:
	if rest_interaction_used:
		_set_non_combat_feedback("Already rested. Choose a gate.")
		return
	rest_interaction_used = true
	var max_hp: int = int(player.max_hp) if player != null and "max_hp" in player else 100
	var hp_before: int = int(player.hp) if player != null and "hp" in player else max_hp
	var heal_amount: int = maxi(1, int(ceil(float(max_hp) * rest_heal_ratio)))
	var hp_after: int = clampi(hp_before + heal_amount, 0, max_hp)
	if player != null and "hp" in player:
		player.hp = hp_after
		if player.has_signal("hp_changed"):
			player.hp_changed.emit(hp_after, max_hp)
	RunStateScript.set_player_current_hp(get_tree(), hp_after)
	_set_non_combat_feedback("Restored %d HP. Choose your next room." % (hp_after - hp_before))
	_mark_non_combat_interaction_complete("rest_used")
	_record_room_event("REST_INTERACTION_USED", {
		"room_index": current_room_index,
		"room_type": selected_room_type,
		"room_id": selected_room_id,
		"hp_before": hp_before,
		"hp_after": hp_after,
		"heal_amount": hp_after - hp_before,
		"player_max_hp": max_hp
	})
	_record_room_event("RUN_STATE_UPDATED", {
		"room_index": current_room_index,
		"selected_room_type": selected_room_type,
		"selected_room_id": selected_room_id,
		"player_current_hp": hp_after
	})

func _open_merchant_shop() -> void:
	if shop_overlay == null:
		return
	if _merchant_shop_open():
		return
	merchant_interaction_opened = true
	_refresh_shop_skill_buttons()
	_set_shop_feedback("")
	shop_overlay.visible = true
	if player != null and player.has_method("set_free_movement_enabled"):
		player.set_free_movement_enabled(false)
	_set_non_combat_feedback("Merchant opened. Placeholder skills have no gameplay effect yet.")
	_record_room_event("MERCHANT_SHOP_OPENED", {
		"room_index": current_room_index,
		"room_type": selected_room_type,
		"room_id": selected_room_id,
		"unlocked_skills": RunStateScript.unlocked_skills(get_tree())
	})

func _close_merchant_shop() -> void:
	if not _merchant_shop_open():
		return
	if shop_overlay != null:
		shop_overlay.visible = false
	if player != null and player.has_method("set_free_movement_enabled"):
		player.set_free_movement_enabled(true)
	_set_shop_feedback("")
	_set_non_combat_feedback("Choose a gate when ready.")
	_mark_non_combat_interaction_complete("merchant_shop_closed")
	_record_room_event("MERCHANT_SHOP_CLOSED", {
		"room_index": current_room_index,
		"room_type": selected_room_type,
		"room_id": selected_room_id,
		"unlocked_skills": RunStateScript.unlocked_skills(get_tree())
	})

func _merchant_shop_open() -> bool:
	return shop_overlay != null and shop_overlay.visible

func _on_shop_skill_pressed(skill_id: String) -> void:
	if skill_id == "":
		return
	var already_unlocked: bool = RunStateScript.has_unlocked_skill(get_tree(), skill_id)
	var cost: int = _skill_cost(skill_id)
	var current_threads: int = RunStateScript.memory_threads(get_tree())
	if not already_unlocked and current_threads < cost:
		_set_shop_feedback("Not enough Threads for %s." % _skill_label(skill_id))
		_record_room_event("MERCHANT_PURCHASE_FAILED_INSUFFICIENT_THREADS", {
			"room_index": current_room_index,
			"room_type": selected_room_type,
			"room_id": selected_room_id,
			"skill_id": skill_id,
			"skill_label": _skill_label(skill_id),
			"cost": cost,
			"memory_threads": current_threads
		})
		return
	if not already_unlocked:
		RunStateScript.spend_memory_threads(get_tree(), cost)
	RunStateScript.unlock_skill(get_tree(), skill_id)
	_refresh_shop_skill_buttons()
	_set_shop_feedback("%s unlocked." % _skill_label(skill_id))
	_record_room_event("MERCHANT_PURCHASE_SUCCESS", {
		"room_index": current_room_index,
		"room_type": selected_room_type,
		"room_id": selected_room_id,
		"skill_id": skill_id,
		"skill_label": _skill_label(skill_id),
		"already_unlocked": already_unlocked,
		"cost": cost,
		"memory_threads": RunStateScript.memory_threads(get_tree()),
		"unlocked_skills": RunStateScript.unlocked_skills(get_tree())
	})
	_record_room_event("MERCHANT_SKILL_PURCHASED", {
		"room_index": current_room_index,
		"skill_id": skill_id,
		"skill_label": _skill_label(skill_id),
		"cost": cost
	})
	_record_room_event("RUN_STATE_UPDATED", {
		"room_index": current_room_index,
		"selected_room_type": selected_room_type,
		"selected_room_id": selected_room_id,
		"memory_threads": RunStateScript.memory_threads(get_tree()),
		"unlocked_skills": RunStateScript.unlocked_skills(get_tree())
	})

func _refresh_shop_skill_buttons() -> void:
	if shop_threads_label != null:
		shop_threads_label.text = "Threads: %d" % RunStateScript.memory_threads(get_tree())
	for skill in MERCHANT_SKILLS:
		var skill_id: String = String(skill.get("id", ""))
		var button := shop_skill_buttons.get(skill_id, null) as Button
		if button == null:
			continue
		var unlocked: bool = RunStateScript.has_unlocked_skill(get_tree(), skill_id)
		var cost: int = _skill_cost(skill_id)
		button.disabled = unlocked
		button.text = "%s - %d Threads%s" % [_skill_label(skill_id), cost, " (Unlocked)" if unlocked else ""]

func _skill_label(skill_id: String) -> String:
	for skill in MERCHANT_SKILLS:
		if String(skill.get("id", "")) == skill_id:
			return String(skill.get("label", skill_id))
	return skill_id.capitalize()

func _skill_cost(skill_id: String) -> int:
	for skill in MERCHANT_SKILLS:
		if String(skill.get("id", "")) == skill_id:
			return int(skill.get("cost", 0))
	return 0

func _mark_non_combat_interaction_complete(reason: String) -> void:
	if non_combat_interaction_complete:
		return
	non_combat_interaction_complete = true
	_record_room_event("NON_COMBAT_ROOM_INTERACTION_COMPLETE", {
		"room_index": current_room_index,
		"room_type": selected_room_type,
		"room_id": selected_room_id,
		"reason": reason
	})
	_update_room_gate_reveal()

func _set_non_combat_feedback(message: String) -> void:
	if non_combat_feedback_label != null:
		non_combat_feedback_label.text = message
	_emit_arena_log(message)

func _set_shop_feedback(message: String) -> void:
	if shop_feedback_label != null:
		shop_feedback_label.text = message

func _create_fight_camera() -> void:
	fight_camera = Camera2D.new()
	fight_camera.name = "FightCamera"
	fight_camera.enabled = true
	add_child(fight_camera)
	fight_camera.make_current()
	var camera_target := _calculate_camera_target()
	fight_camera.global_position = camera_target["position"]
	var target_zoom := float(camera_target["zoom"])
	fight_camera.zoom = Vector2(target_zoom, target_zoom)

func _snap_fight_camera_to_target() -> void:
	if fight_camera == null:
		return
	var camera_target := _calculate_camera_target()
	fight_camera.global_position = camera_target["position"]
	var target_zoom := float(camera_target["zoom"])
	fight_camera.zoom = Vector2(target_zoom, target_zoom)

func toggle_combat_geometry_debug() -> void:
	_set_combat_geometry_debug_visible(not show_combat_geometry_debug, true)

func set_combat_geometry_debug_visible(visible: bool) -> void:
	_set_combat_geometry_debug_visible(visible, true)

func toggle_camera_debug() -> void:
	camera_debug_enabled = not camera_debug_enabled
	camera_debug_timer = 0.0
	_emit_arena_log("Camera debug %s." % ("enabled" if camera_debug_enabled else "disabled"))

func _set_combat_geometry_debug_visible(visible: bool, log_change: bool) -> void:
	show_combat_geometry_debug = visible
	if center_axis_debug != null:
		center_axis_debug.visible = visible
	if left_wall_debug != null:
		left_wall_debug.visible = visible
	if right_wall_debug != null:
		right_wall_debug.visible = visible
	if combat_manager != null and combat_manager.has_method("set_combat_geometry_debug_visible"):
		combat_manager.set_combat_geometry_debug_visible(visible, log_change)

func _apply_combat_arena_bounds() -> void:
	if combat_manager != null and combat_manager.has_method("set_arena_bounds"):
		combat_manager.set_arena_bounds(arena_left_x, arena_right_x, fighter_wall_margin)

func _update_fight_camera(delta: float) -> void:
	if fight_camera == null or player == null or enemy == null:
		return
	var camera_target := _calculate_camera_target()
	var target_position: Vector2 = camera_target["position"]
	var target_zoom := float(camera_target["zoom"])
	var position_alpha := 1.0 - exp(-camera_position_lerp_speed * delta)
	var zoom_alpha := 1.0 - exp(-camera_zoom_lerp_speed * delta)
	fight_camera.global_position = fight_camera.global_position.lerp(target_position, position_alpha)
	fight_camera.zoom = fight_camera.zoom.lerp(Vector2(target_zoom, target_zoom), zoom_alpha)
	_log_camera_debug(delta, camera_target)

func _calculate_camera_target() -> Dictionary:
	var viewport_size := _viewport_size()
	if _combat_clear_camera_active():
		return _calculate_combat_clear_camera_target(viewport_size)
	var player_bounds := _fighter_bounds(player, true)
	var enemy_bounds := _fighter_bounds(enemy, false)
	var player_center := player_bounds.get_center()
	var enemy_center := enemy_bounds.get_center()
	var fighter_distance := absf(player_center.x - enemy_center.x)
	var min_visible_width := (arena_right_x - arena_left_x) * min_visible_width_ratio
	var max_visible_width := (arena_right_x - arena_left_x) * max_visible_width_ratio
	var highest_fighter_y := minf(player_bounds.position.y, enemy_bounds.position.y)
	var jump_lift := maxf(0.0, (camera_baseline_y - camera_jump_vertical_padding) - highest_fighter_y)
	var target_visible_width := clampf(
		fighter_distance + camera_distance_padding + jump_lift * camera_jump_zoom_out_strength,
		min_visible_width,
		max_visible_width
	)
	var target_zoom := viewport_size.x / target_visible_width
	var target_x := (player_center.x + enemy_center.x) * 0.5
	var target_y := camera_baseline_y - jump_lift * camera_jump_pan_strength
	var visible_width := viewport_size.x / target_zoom
	var visible_height := viewport_size.y / target_zoom
	var target_position := Vector2(
		_clamp_camera_axis(target_x, arena_left_x, arena_right_x, visible_width),
		_clamp_camera_axis(target_y, arena_top_y, arena_bottom_y, visible_height)
	)
	return {
		"position": target_position,
		"zoom": target_zoom,
		"fighter_distance": fighter_distance,
		"target_visible_width": target_visible_width
	}

func _calculate_combat_clear_camera_target(viewport_size: Vector2) -> Dictionary:
	var arena_width := arena_right_x - arena_left_x
	var target_visible_width := clampf(
		arena_width * combat_clear_visible_width_ratio,
		arena_width * 0.5,
		arena_width
	)
	var target_zoom := viewport_size.x / target_visible_width
	var visible_width := viewport_size.x / target_zoom
	var visible_height := viewport_size.y / target_zoom
	var target_position := Vector2(
		_clamp_camera_axis(stage_center_x, arena_left_x, arena_right_x, visible_width),
		_clamp_camera_axis(combat_clear_camera_y, arena_top_y, arena_bottom_y, visible_height)
	)
	return {
		"position": target_position,
		"zoom": target_zoom,
		"fighter_distance": 0.0,
		"target_visible_width": target_visible_width
	}

func _combat_clear_camera_active() -> bool:
	return _room_traversal_active()

func _update_room_gate_reveal() -> void:
	if _room_gates_should_be_available():
		if not room_gates_revealed:
			_reveal_room_gates()
	elif room_gates_revealed:
		_hide_room_gates()

func _room_traversal_active() -> bool:
	if selected_room_type != ROOM_TYPE_COMBAT:
		return true
	return combat_manager != null and bool(combat_manager.get("combat_cleared"))

func _room_gates_should_be_available() -> bool:
	if selected_room_type != ROOM_TYPE_COMBAT:
		return non_combat_interaction_complete and not _merchant_shop_open()
	return combat_manager != null and bool(combat_manager.get("combat_cleared"))

func _viewport_size() -> Vector2:
	var size := get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2(1600.0, 900.0)
	return size

func _fighter_bounds(actor: Node2D, is_player: bool) -> Rect2:
	var sprite_bounds := Rect2()
	if combat_manager != null:
		if is_player and combat_manager.has_method("get_player_sprite_bounds"):
			sprite_bounds = combat_manager.get_player_sprite_bounds()
		elif not is_player and combat_manager.has_method("get_enemy_sprite_bounds"):
			sprite_bounds = combat_manager.get_enemy_sprite_bounds()
	if sprite_bounds.size != Vector2.ZERO:
		return sprite_bounds
	return Rect2(actor.global_position - Vector2(40.0, 140.0), Vector2(80.0, 160.0))

func _clamp_camera_axis(value: float, min_edge: float, max_edge: float, visible_span: float) -> float:
	var min_center := min_edge + visible_span * 0.5
	var max_center := max_edge - visible_span * 0.5
	if min_center > max_center:
		return (min_edge + max_edge) * 0.5
	return clampf(value, min_center, max_center)

func _log_camera_debug(delta: float, camera_target: Dictionary) -> void:
	if not camera_debug_enabled:
		return
	camera_debug_timer -= delta
	if camera_debug_timer > 0.0:
		return
	camera_debug_timer = camera_debug_log_interval
	_emit_arena_log("Camera debug: distance %.1f, visible_width %.1f, zoom %.2f, target %s." % [
		float(camera_target["fighter_distance"]),
		float(camera_target["target_visible_width"]),
		fight_camera.zoom.x,
		str(camera_target["position"])
	])

func _emit_arena_log(message: String) -> void:
	if combat_manager != null and combat_manager.has_signal("log_message"):
		combat_manager.log_message.emit(message)
	else:
		print(message)

func _load_run_room_metadata() -> void:
	var tree := get_tree()
	current_room_index = RunStateScript.room_index(tree)
	selected_room_type = RunStateScript.selected_room_type(tree)
	selected_room_id = RunStateScript.selected_room_id(tree)
	previous_exit_direction = RunStateScript.previous_exit_direction(tree)
	next_entry_side = RunStateScript.next_entry_side(tree)
	player_starts_left = RunStateScript.player_starts_left(tree)

func _apply_persisted_player_hp() -> void:
	if player == null or not RunStateScript.has_player_hp(get_tree()):
		return
	var max_hp: int = int(player.max_hp) if "max_hp" in player else 100
	var persisted_hp: int = clampi(RunStateScript.player_current_hp(get_tree(), max_hp), 1, max_hp)
	player.hp = persisted_hp
	if player.has_signal("hp_changed"):
		player.hp_changed.emit(player.hp, max_hp)
	_record_room_event("PLAYER_HP_PERSISTED", {
		"room_index": current_room_index,
		"player_hp": player.hp,
		"player_max_hp": max_hp,
		"stance_policy": "reset"
	})

func _apply_hud_side() -> void:
	if ui_manager != null and ui_manager.has_method("set_round_start_hud_side"):
		ui_manager.set_round_start_hud_side(player_starts_left)

func _record_encounter_side_assigned() -> void:
	_record_room_event("ENCOUNTER_SIDE_ASSIGNED", {
		"room_index": current_room_index,
		"room_type": selected_room_type,
		"room_id": selected_room_id,
		"previous_exit_direction": previous_exit_direction,
		"next_entry_side": next_entry_side,
		"player_side": "LEFT" if player_starts_left else "RIGHT",
		"enemy_side": "RIGHT" if player_starts_left else "LEFT",
		"player_position": _vector_to_dict(player.global_position),
		"enemy_position": _vector_to_dict(enemy.global_position)
	})

func _reveal_room_gates() -> void:
	room_gates_revealed = true
	room_gate_selection_locked = false
	_clear_room_gate_nodes()
	room_gate_choices = _generate_room_choices()
	if room_gate_layer != null:
		room_gate_layer.visible = true
	_record_room_event("ROOM_CHOICES_GENERATED", {
		"room_index": current_room_index,
		"run_progress": current_room_index,
		"choice_count": room_gate_choices.size(),
		"weights": _room_type_weights(),
		"choices": room_gate_choices.duplicate(true)
	})
	var gate_specs := _gate_specs_for_choice_count(room_gate_choices.size())
	for i in range(room_gate_choices.size()):
		var gate_data: Dictionary = room_gate_choices[i].duplicate(true)
		var gate_spec: Dictionary = gate_specs[i]
		gate_data["gate_index"] = i
		gate_data["exit_direction"] = String(gate_spec["exit_direction"])
		gate_data["gate_position"] = gate_spec["position"]
		_create_room_gate(gate_data)
		_record_room_event("ROOM_GATE_REVEALED", _gate_event_data(gate_data))

func _hide_room_gates() -> void:
	room_gates_revealed = false
	room_gate_selection_locked = false
	if room_gate_layer != null:
		room_gate_layer.visible = false
	_clear_room_gate_nodes()

func _clear_room_gate_nodes() -> void:
	if room_gate_layer == null:
		return
	for child in room_gate_layer.get_children():
		child.queue_free()
	room_gate_path_layer = Node2D.new()
	room_gate_path_layer.name = "PathPreview"
	room_gate_path_layer.z_index = 11
	room_gate_layer.add_child(room_gate_path_layer)

func _generate_room_choices() -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var next_room_index: int = current_room_index + 1
	if next_room_index == FORCED_MERCHANT_ROOM_INDEX:
		_record_room_event("ROOM_TYPE_FORCED", {
			"room_index": next_room_index,
			"room_type": ROOM_TYPE_MERCHANT
		})
		return [_make_room_choice(ROOM_TYPE_MERCHANT, "M")]
	var choice_count: int = clampi(rng.randi_range(min_room_gate_choices, max_room_gate_choices), 2, 3)
	var choices: Array[Dictionary] = []
	var used_non_combat: Dictionary = {}
	var combat_ids: Array[String] = ["C1", "C2", "C3", "C4"]
	combat_ids.shuffle()
	choices.append(_make_room_choice(ROOM_TYPE_COMBAT, combat_ids.pop_front()))
	while choices.size() < choice_count:
		var room_type: String = _pick_weighted_room_type(rng, used_non_combat)
		if room_type == ROOM_TYPE_COMBAT:
			var combat_id: String = String(combat_ids.pop_front()) if not combat_ids.is_empty() else "C%d" % rng.randi_range(1, 4)
			choices.append(_make_room_choice(ROOM_TYPE_COMBAT, combat_id))
			continue
		if used_non_combat.has(room_type):
			continue
		used_non_combat[room_type] = true
		choices.append(_make_room_choice(room_type, _room_type_label(room_type)))
	choices.shuffle()
	return choices

func _room_type_weights() -> Dictionary:
	var rest_weight: int = 10 + current_room_index * 5
	var merchant_weight: int = 0 if current_room_index <= 0 else 8 + current_room_index * 4
	return {
		ROOM_TYPE_COMBAT: 100,
		ROOM_TYPE_REST: rest_weight,
		ROOM_TYPE_MERCHANT: merchant_weight
	}

func _pick_weighted_room_type(rng: RandomNumberGenerator, used_non_combat: Dictionary) -> String:
	var weights: Dictionary = _room_type_weights()
	var candidates: Array[String] = [ROOM_TYPE_COMBAT, ROOM_TYPE_REST, ROOM_TYPE_MERCHANT]
	var total_weight := 0
	for room_type in candidates:
		if room_type != ROOM_TYPE_COMBAT and used_non_combat.has(room_type):
			continue
		var weight: int = int(weights.get(room_type, 0))
		if weight <= 0:
			continue
		total_weight += weight
	if total_weight <= 0:
		return ROOM_TYPE_COMBAT
	var roll: int = rng.randi_range(1, total_weight)
	var cursor := 0
	for room_type in candidates:
		if room_type != ROOM_TYPE_COMBAT and used_non_combat.has(room_type):
			continue
		var weight: int = int(weights.get(room_type, 0))
		if weight <= 0:
			continue
		cursor += weight
		if roll <= cursor:
			return room_type
	return ROOM_TYPE_COMBAT

func _make_room_choice(room_type: String, room_id: String) -> Dictionary:
	return {
		"room_type": room_type,
		"room_id": room_id,
		"label": _room_type_label(room_type, room_id)
	}

func _gate_specs_for_choice_count(choice_count: int) -> Array[Dictionary]:
	if choice_count <= 2:
		return [
			{"exit_direction": RunStateScript.SIDE_LEFT, "position": Vector2(arena_left_x + 190.0, 545.0)},
			{"exit_direction": RunStateScript.SIDE_RIGHT, "position": Vector2(arena_right_x - 190.0, 545.0)}
		]
	return [
		{"exit_direction": RunStateScript.SIDE_LEFT, "position": Vector2(arena_left_x + 190.0, 545.0)},
		{"exit_direction": RunStateScript.SIDE_UP, "position": Vector2(stage_center_x, 340.0)},
		{"exit_direction": RunStateScript.SIDE_RIGHT, "position": Vector2(arena_right_x - 190.0, 545.0)}
	]

func _create_room_gate(gate_data: Dictionary) -> void:
	if room_gate_layer == null:
		return
	var gate_position: Vector2 = gate_data["gate_position"]
	var room_type: String = String(gate_data["room_type"])
	var exit_direction: String = String(gate_data["exit_direction"])
	var gate_size: Vector2 = Vector2(112.0, 124.0)
	var gate: Area2D = Area2D.new()
	gate.name = "RoomGate_%s_%s" % [String(gate_data["room_id"]), exit_direction]
	gate.global_position = gate_position
	gate.monitoring = true
	gate.monitorable = false
	gate.z_index = 14
	room_gate_layer.add_child(gate)

	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = gate_size
	shape.shape = rect_shape
	gate.add_child(shape)

	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([
		Vector2(-gate_size.x * 0.5, -gate_size.y * 0.5),
		Vector2(gate_size.x * 0.5, -gate_size.y * 0.5),
		Vector2(gate_size.x * 0.5, gate_size.y * 0.5),
		Vector2(-gate_size.x * 0.5, gate_size.y * 0.5)
	])
	visual.color = _room_type_color(room_type)
	visual.z_index = 14
	gate.add_child(visual)

	var outline := Line2D.new()
	outline.points = PackedVector2Array([
		Vector2(-gate_size.x * 0.5, -gate_size.y * 0.5),
		Vector2(gate_size.x * 0.5, -gate_size.y * 0.5),
		Vector2(gate_size.x * 0.5, gate_size.y * 0.5),
		Vector2(-gate_size.x * 0.5, gate_size.y * 0.5),
		Vector2(-gate_size.x * 0.5, -gate_size.y * 0.5)
	])
	outline.width = 3.0
	outline.default_color = Color(1.0, 1.0, 1.0, 0.78)
	outline.z_index = 15
	gate.add_child(outline)

	var label := Label.new()
	label.text = String(gate_data["label"])
	label.position = Vector2(-54.0, -22.0)
	label.size = Vector2(108.0, 44.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.z_index = 16
	gate.add_child(label)

	var direction_label := Label.new()
	direction_label.text = exit_direction
	direction_label.position = Vector2(-58.0, 42.0)
	direction_label.size = Vector2(116.0, 24.0)
	direction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	direction_label.add_theme_font_size_override("font_size", 13)
	direction_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 0.82))
	direction_label.z_index = 16
	gate.add_child(direction_label)

	gate.body_entered.connect(_on_room_gate_body_entered.bind(gate_data))
	_create_path_preview_to_gate(gate_position, _room_type_color(room_type))
	_record_room_event("ROOM_MARKER_CREATED", {
		"room_index": current_room_index,
		"room_type": room_type,
		"room_id": String(gate_data.get("room_id", "")),
		"marker_kind": "gate",
		"label": String(gate_data.get("label", "")),
		"exit_direction": exit_direction,
		"color": _color_to_dict(_room_type_color(room_type)),
		"position": _vector_to_dict(gate_position)
	})

func _create_path_preview_to_gate(gate_position: Vector2, color: Color) -> void:
	if room_gate_path_layer == null:
		return
	var path := Line2D.new()
	path.width = 5.0
	path.default_color = Color(color.r, color.g, color.b, 0.34)
	path.points = PackedVector2Array([
		Vector2(stage_center_x, player_round_start_y - 18.0),
		gate_position
	])
	room_gate_path_layer.add_child(path)

func _on_room_gate_body_entered(body: Node, gate_data: Dictionary) -> void:
	if body != player:
		return
	if room_transition_in_progress or room_gate_selection_locked:
		_emit_arena_log("Room gate ignored: transition already in progress.")
		_record_room_event("ROOM_GATE_IGNORED", {
			"room_index": current_room_index,
			"reason": "transition_in_progress",
			"gate": _gate_event_data(gate_data)
		})
		return
	room_transition_in_progress = true
	room_gate_selection_locked = true
	_set_room_gates_enabled(false)
	var event_data: Dictionary = _gate_event_data(gate_data)
	_record_room_event("ROOM_GATE_ENTERED", event_data)
	_select_next_room(gate_data)

func _set_room_gates_enabled(enabled: bool) -> void:
	if room_gate_layer == null:
		return
	for child in room_gate_layer.get_children():
		var area := child as Area2D
		if area != null:
			area.set_deferred("monitoring", enabled)
			for area_child in area.get_children():
				var shape := area_child as CollisionShape2D
				if shape != null:
					shape.set_deferred("disabled", not enabled)

func _select_next_room(gate_data: Dictionary) -> void:
	var room_type: String = String(gate_data["room_type"])
	var room_id: String = String(gate_data["room_id"])
	var exit_direction: String = String(gate_data["exit_direction"])
	var selected_gate_room_type: String = room_type
	var selected_gate_room_id: String = room_id
	var next_room_index: int = current_room_index + 1
	var assigned_next_entry_side: String = RunStateScript.exit_direction_to_next_entry_side(exit_direction, next_entry_side)
	var next_player_starts_left: bool = assigned_next_entry_side == RunStateScript.SIDE_LEFT
	_persist_player_hp_for_next_room(room_type, room_id, exit_direction, assigned_next_entry_side)
	_store_next_room_metadata(next_room_index, room_type, room_id, exit_direction, assigned_next_entry_side)
	_record_room_event("NEXT_ENTRY_SIDE_ASSIGNED", {
		"room_index": current_room_index,
		"next_room_index": next_room_index,
		"previous_exit_direction": exit_direction,
		"next_entry_side": assigned_next_entry_side,
		"next_player_side": "LEFT" if next_player_starts_left else "RIGHT"
	})
	_record_room_event("NEXT_ROOM_SELECTED", {
		"room_index": current_room_index,
		"next_room_index": next_room_index,
		"room_type": room_type,
		"room_id": room_id,
		"exit_direction": exit_direction,
		"next_entry_side": assigned_next_entry_side,
		"next_player_side": "LEFT" if next_player_starts_left else "RIGHT",
		"placeholder_behavior": "reload_arena_as_%s" % room_type,
		"selected_gate_room_type": selected_gate_room_type,
		"selected_gate_room_id": selected_gate_room_id
	})
	if room_type == ROOM_TYPE_REST:
		_emit_arena_log("Rest room selected; loading non-combat room.")
	elif room_type == ROOM_TYPE_MERCHANT:
		_emit_arena_log("Merchant room selected; loading non-combat room.")
	call_deferred("_reload_current_scene_after_gate")

func _persist_player_hp_for_next_room(room_type: String, room_id: String, exit_direction: String, assigned_next_entry_side: String) -> void:
	var max_hp: int = int(player.max_hp) if player != null and "max_hp" in player else 100
	var current_hp: int = clampi(int(player.hp) if player != null and "hp" in player else max_hp, 1, max_hp)
	RunStateScript.set_player_current_hp(get_tree(), current_hp)
	_record_room_event("PLAYER_HP_PERSISTED", {
		"room_index": current_room_index,
		"room_type": room_type,
		"room_id": room_id,
		"previous_exit_direction": exit_direction,
		"next_entry_side": assigned_next_entry_side,
		"player_hp": current_hp,
		"player_max_hp": max_hp,
		"stance_policy": "reset"
	})

func _store_next_room_metadata(next_room_index: int, room_type: String, room_id: String, exit_direction: String, assigned_next_entry_side: String) -> void:
	RunStateScript.set_next_room(get_tree(), next_room_index, room_type, room_id, exit_direction, assigned_next_entry_side)
	_record_room_event("RUN_STATE_UPDATED", {
		"room_index": current_room_index,
		"next_room_index": next_room_index,
		"selected_room_type": room_type,
		"selected_room_id": room_id,
		"previous_exit_direction": exit_direction,
		"next_entry_side": assigned_next_entry_side,
		"selected_combat_mode": RunStateScript.selected_combat_mode(get_tree(), "TIME_TACTICAL"),
		"player_current_hp": RunStateScript.player_current_hp(get_tree(), int(player.max_hp) if player != null and "max_hp" in player else 100),
		"memory_threads": RunStateScript.memory_threads(get_tree())
	})

func _reload_current_scene_after_gate() -> void:
	get_tree().paused = false
	var err: Error = get_tree().reload_current_scene()
	if err != OK:
		room_transition_in_progress = false
		room_gate_selection_locked = false
		_emit_arena_log("Room reload failed: %s." % error_string(err))

func _gate_event_data(gate_data: Dictionary) -> Dictionary:
	return {
		"room_index": current_room_index,
		"room_type": String(gate_data.get("room_type", "")),
		"room_id": String(gate_data.get("room_id", "")),
		"label": String(gate_data.get("label", "")),
		"gate_index": int(gate_data.get("gate_index", -1)),
		"gate_position": _vector_to_dict(gate_data.get("gate_position", Vector2.ZERO)),
		"exit_direction": String(gate_data.get("exit_direction", ""))
	}

func _room_type_label(room_type: String, room_id: String = "") -> String:
	match room_type:
		ROOM_TYPE_COMBAT:
			return room_id if room_id != "" else "C"
		ROOM_TYPE_ELITE:
			return "E"
		ROOM_TYPE_MERCHANT:
			return "M"
		ROOM_TYPE_REST:
			return "R"
		ROOM_TYPE_BOSS:
			return "B"
		_:
			return room_id if room_id != "" else "?"

func _room_type_color(room_type: String) -> Color:
	match room_type:
		ROOM_TYPE_COMBAT:
			return Color(1.0, 0.18, 0.14, 0.76)
		ROOM_TYPE_ELITE:
			return Color(0.78, 0.28, 1.0, 0.78)
		ROOM_TYPE_REST:
			return Color(0.18, 0.78, 0.36, 0.76)
		ROOM_TYPE_MERCHANT:
			return Color(0.22, 0.48, 1.0, 0.76)
		ROOM_TYPE_BOSS:
			return Color(0.55, 0.04, 0.04, 0.86)
		_:
			return Color(0.64, 0.64, 0.64, 0.76)

func _record_room_event(event_type: String, data: Dictionary) -> void:
	if combat_manager != null and combat_manager.has_method("record_room_event"):
		combat_manager.record_room_event(event_type, data)
	else:
		_emit_arena_log(event_type)

func _vector_to_dict(value: Variant) -> Dictionary:
	if not value is Vector2:
		return {"x": 0.0, "y": 0.0}
	var vector: Vector2 = value
	return {"x": vector.x, "y": vector.y}

func _color_to_dict(color: Color) -> Dictionary:
	return {
		"r": color.r,
		"g": color.g,
		"b": color.b,
		"a": color.a
	}
