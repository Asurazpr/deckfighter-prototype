class_name CharacterRig2D
extends Node2D

@export var facing := 1.0
@export var body_color := Color(0.25, 0.75, 1.0)
@export var active_hitbox_color := Color(1.0, 0.85, 0.18, 0.28)

var pose_key := "idle"
var phase := "DONE"
var phase_progress := 0.0
var hit_level := ""
var hitbox_active := false
var impact_pulse := 0.0
var _shake_offset := Vector2.ZERO
var _sockets := {}

func _ready() -> void:
	_ensure_socket("hip_socket")
	_ensure_socket("hand_socket")
	_ensure_socket("foot_socket")
	_ensure_socket("weapon_socket")
	_ensure_socket("body_socket")
	queue_redraw()

func apply_combat_phase(animation_key: String, phase_name: String, progress: float, incoming_hit_level := "", active_hitbox := false) -> void:
	pose_key = animation_key
	phase = phase_name
	phase_progress = clampf(progress, 0.0, 1.0)
	hit_level = incoming_hit_level
	hitbox_active = active_hitbox
	_update_sockets()
	queue_redraw()

func play_impact() -> void:
	impact_pulse = 1.0
	var tween := create_tween()
	tween.tween_method(_set_impact_pulse, 1.0, 0.0, 0.14)

func clear_pose() -> void:
	pose_key = "idle"
	phase = "DONE"
	phase_progress = 0.0
	hitbox_active = false
	hit_level = ""
	impact_pulse = 0.0
	_update_sockets()
	queue_redraw()

func _draw() -> void:
	var points := _pose_points()
	var color := body_color.lerp(Color.WHITE, impact_pulse * 0.55)
	var width := 5.0 + impact_pulse * 2.0
	var offset := _shake_offset

	_draw_limb(points["hip"] + offset, points["torso"] + offset, color, width)
	_draw_limb(points["torso"] + offset, points["head"] + offset, color, width)
	_draw_limb(points["torso"] + offset, points["front_hand"] + offset, color, width)
	_draw_limb(points["torso"] + offset, points["back_hand"] + offset, color.darkened(0.18), width)
	_draw_limb(points["hip"] + offset, points["front_foot"] + offset, color, width)
	_draw_limb(points["hip"] + offset, points["back_foot"] + offset, color.darkened(0.18), width)

	draw_circle(points["head"] + offset, 13.0 + impact_pulse * 2.0, color)
	draw_circle(points["hand_socket"] + offset, 4.0, Color.WHITE)
	draw_circle(points["foot_socket"] + offset, 4.0, Color.WHITE)

	if hitbox_active:
		var hitbox_rect := _socket_hitbox_rect(points)
		draw_rect(hitbox_rect, active_hitbox_color, true)
		draw_rect(hitbox_rect, active_hitbox_color.lightened(0.45), false, 2.0)

	if hit_level != "":
		draw_string(ThemeDB.fallback_font, Vector2(-42.0, -132.0), hit_level, HORIZONTAL_ALIGNMENT_CENTER, 84.0, 20, Color.WHITE)

func _draw_limb(from_point: Vector2, to_point: Vector2, color: Color, width: float) -> void:
	draw_line(from_point, to_point, color, width, true)

func _pose_points() -> Dictionary:
	var f := 1.0 if facing >= 0.0 else -1.0
	var windup := phase == "STARTUP"
	var active := phase == "ACTIVE" or phase == "IMPACT"
	var recovery := phase == "RECOVERY"
	var crouch := pose_key == "block_low"
	var hitstun := pose_key == "hitstun"
	var broken := pose_key == "stance_break"

	var hip := Vector2(0.0, -38.0)
	var torso := Vector2(0.0, -82.0)
	var head := Vector2(0.0, -108.0)
	var front_hand := Vector2(24.0 * f, -78.0)
	var back_hand := Vector2(-18.0 * f, -76.0)
	var front_foot := Vector2(18.0 * f, -2.0)
	var back_foot := Vector2(-18.0 * f, -2.0)

	if crouch:
		hip.y += 18.0
		torso.y += 18.0
		head.y += 16.0
		front_hand = Vector2(28.0 * f, -54.0)
		back_hand = Vector2(-16.0 * f, -52.0)
	if hitstun:
		torso.x -= 18.0 * f
		head.x -= 24.0 * f
		front_hand = Vector2(-18.0 * f, -68.0)
		back_hand = Vector2(-34.0 * f, -72.0)
	if broken:
		hip.x -= 10.0 * f
		torso.x -= 24.0 * f
		head.x -= 30.0 * f
		front_hand = Vector2(-26.0 * f, -44.0)
		back_hand = Vector2(-38.0 * f, -50.0)
		front_foot = Vector2(8.0 * f, -2.0)
		back_foot = Vector2(-30.0 * f, -2.0)

	if pose_key.begins_with("jab") or pose_key == "gunshot":
		if windup:
			front_hand = Vector2(-18.0 * f, -80.0)
		elif active:
			front_hand = Vector2(64.0 * f, -78.0)
		elif recovery:
			front_hand = Vector2(24.0 * f, -78.0)
	if pose_key.begins_with("launcher"):
		if windup:
			front_hand = Vector2(14.0 * f, -42.0)
		elif active:
			front_hand = Vector2(50.0 * f, -112.0)
			torso.y -= 8.0
		elif recovery:
			front_hand = Vector2(26.0 * f, -94.0)
	if pose_key.begins_with("kick") or pose_key == "air_follow" or pose_key == "ground_smash":
		if windup:
			front_foot = Vector2(-8.0 * f, -8.0)
		elif active:
			front_foot = Vector2(66.0 * f, -28.0)
		elif recovery:
			front_foot = Vector2(28.0 * f, -6.0)
	if pose_key == "step_forward" or pose_key == "walk_forward":
		hip.x += 8.0 * f
		torso.x += 12.0 * f
		front_foot = Vector2(30.0 * f, -2.0)
		back_foot = Vector2(-26.0 * f, -2.0)
	if pose_key == "backstep":
		hip.x -= 14.0 * f
		torso.x -= 18.0 * f
		front_foot = Vector2(8.0 * f, -2.0)
		back_foot = Vector2(-42.0 * f, -2.0)
	if pose_key == "block_high":
		front_hand = Vector2(28.0 * f, -100.0)
		back_hand = Vector2(18.0 * f, -76.0)

	var socket := front_hand
	if pose_key.begins_with("kick") or pose_key == "air_follow" or pose_key == "ground_smash":
		socket = front_foot

	return {
		"hip": hip,
		"torso": torso,
		"head": head,
		"front_hand": front_hand,
		"back_hand": back_hand,
		"front_foot": front_foot,
		"back_foot": back_foot,
		"hip_socket": hip,
		"hand_socket": front_hand,
		"foot_socket": front_foot,
		"weapon_socket": socket,
		"body_socket": torso
	}

func _socket_hitbox_rect(points: Dictionary) -> Rect2:
	var socket: Vector2 = points["weapon_socket"]
	var size := Vector2(58.0, 34.0)
	if hit_level == "LOW":
		size = Vector2(64.0, 24.0)
	elif hit_level == "OVERHEAD":
		size = Vector2(62.0, 56.0)
	elif hit_level == "HIGH":
		size = Vector2(58.0, 30.0)
	return Rect2(socket - size * 0.5, size)

func _update_sockets() -> void:
	var points := _pose_points()
	for socket_name in ["hip_socket", "hand_socket", "foot_socket", "weapon_socket", "body_socket"]:
		var socket := _sockets.get(socket_name) as Node2D
		if socket != null:
			socket.position = points[socket_name]

func _ensure_socket(socket_name: String) -> void:
	var socket := get_node_or_null(socket_name) as Node2D
	if socket == null:
		socket = Node2D.new()
		socket.name = socket_name
		add_child(socket)
	_sockets[socket_name] = socket

func _set_impact_pulse(value: float) -> void:
	impact_pulse = value
	_shake_offset = Vector2(randf_range(-3.0, 3.0), randf_range(-2.0, 2.0)) * value
	queue_redraw()
