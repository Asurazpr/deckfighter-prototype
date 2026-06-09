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
var current_room_index := 0
var selected_room_type := "combat"
var selected_room_id := "debug_start"
var previous_exit_direction := "LEFT"
var next_entry_side := "LEFT"
var player_starts_left := true

const ROOM_TYPE_COMBAT := "combat"
const ROOM_TYPE_REST := "rest"
const ROOM_TYPE_MERCHANT := "merchant"
const EXIT_LEFT := "LEFT"
const EXIT_RIGHT := "RIGHT"
const EXIT_UP := "UP"
const EXIT_DOWN := "DOWN"

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

func _process(delta: float) -> void:
	_update_fight_camera(delta)
	_update_room_gate_reveal()

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
	return combat_manager != null and bool(combat_manager.get("combat_cleared"))

func _update_room_gate_reveal() -> void:
	if combat_manager == null:
		return
	if bool(combat_manager.get("combat_cleared")):
		if not room_gates_revealed:
			_reveal_room_gates()
	elif room_gates_revealed:
		_hide_room_gates()

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
		choices.append(_make_room_choice(room_type, "R" if room_type == ROOM_TYPE_REST else "M"))
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
		"label": room_id
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
	if room_gate_selection_locked or body != player:
		return
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
			area.monitoring = enabled

func _select_next_room(gate_data: Dictionary) -> void:
	var room_type: String = String(gate_data["room_type"])
	var room_id: String = String(gate_data["room_id"])
	var exit_direction: String = String(gate_data["exit_direction"])
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
		"placeholder_behavior": "reload_current_scene"
	})
	if room_type == ROOM_TYPE_REST:
		_emit_arena_log("REST placeholder selected; reloading debug Arena.")
	elif room_type == ROOM_TYPE_MERCHANT:
		_emit_arena_log("MERCHANT placeholder selected; reloading debug Arena.")
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
		"player_current_hp": RunStateScript.player_current_hp(get_tree(), int(player.max_hp) if player != null and "max_hp" in player else 100)
	})

func _reload_current_scene_after_gate() -> void:
	get_tree().paused = false
	var err: Error = get_tree().reload_current_scene()
	if err != OK:
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

func _room_type_color(room_type: String) -> Color:
	match room_type:
		ROOM_TYPE_REST:
			return Color(0.18, 0.78, 0.36, 0.76)
		ROOM_TYPE_MERCHANT:
			return Color(0.22, 0.48, 1.0, 0.76)
		_:
			return Color(1.0, 0.18, 0.14, 0.76)

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
