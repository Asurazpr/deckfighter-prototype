extends Node2D

@export var stage_center_x := 800.0
@export var desired_start_distance := 220.0
@export var show_combat_geometry_debug := false
@export var arena_left_x := 0.0
@export var arena_right_x := 1600.0
@export var fighter_wall_margin := 90.0
@export var arena_top_y := 120.0
@export var arena_bottom_y := 820.0
@export var camera_baseline_y := 560.0
@export var camera_distance_padding := 700.0
@export var camera_jump_vertical_padding := 210.0
@export var camera_jump_pan_strength := 0.35
@export var camera_jump_zoom_out_strength := 0.7
@export var min_visible_width_ratio := 0.50
@export var max_visible_width_ratio := 0.75
@export var camera_position_lerp_speed := 8.0
@export var camera_zoom_lerp_speed := 6.0
@export var camera_debug_enabled := false
@export var camera_debug_log_interval := 0.35

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

func _ready() -> void:
	_apply_round_start_positions()
	_apply_combat_arena_bounds()
	_create_center_axis_debug()
	_create_wall_debug()
	_create_fight_camera()
	_set_combat_geometry_debug_visible(show_combat_geometry_debug, false)
	ui_manager.bind(player, enemy, deck_manager, combat_manager)

func _process(delta: float) -> void:
	_update_fight_camera(delta)

func _apply_round_start_positions() -> void:
	var spawn_gap := desired_start_distance * 0.5
	player.global_position.x = stage_center_x - spawn_gap
	enemy.global_position.x = stage_center_x + spawn_gap

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
