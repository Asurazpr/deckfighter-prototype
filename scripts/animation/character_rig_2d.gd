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

	_draw_limb(points["hip"] + offset, points["torso"] + offset, color, width + 2.0)
	_draw_limb(points["torso"] + offset, points["neck"] + offset, color, width)
	_draw_segmented_limb(points["front_shoulder"] + offset, points["front_elbow"] + offset, points["front_hand"] + offset, color, width)
	_draw_segmented_limb(points["back_shoulder"] + offset, points["back_elbow"] + offset, points["back_hand"] + offset, color.darkened(0.18), width)
	_draw_segmented_limb(points["front_hip"] + offset, points["front_knee"] + offset, points["front_foot"] + offset, color, width)
	_draw_segmented_limb(points["back_hip"] + offset, points["back_knee"] + offset, points["back_foot"] + offset, color.darkened(0.18), width)

	draw_circle(points["head"] + offset, 13.0 + impact_pulse * 2.0, color)
	draw_circle(points["front_elbow"] + offset, 4.5, color.lightened(0.18))
	draw_circle(points["back_elbow"] + offset, 4.0, color.darkened(0.05))
	draw_circle(points["front_knee"] + offset, 4.5, color.lightened(0.18))
	draw_circle(points["back_knee"] + offset, 4.0, color.darkened(0.05))
	draw_circle(points["hand_socket"] + offset, 4.0, Color.WHITE)
	draw_circle(points["foot_socket"] + offset, 4.0, Color.WHITE)

	if hitbox_active:
		var hitbox_rect := _socket_hitbox_rect(points)
		draw_rect(hitbox_rect, active_hitbox_color, true)
		draw_rect(hitbox_rect, active_hitbox_color.lightened(0.45), false, 2.0)
	if pose_key == "gunshot" and (phase == "ACTIVE" or phase == "IMPACT"):
		var muzzle: Vector2 = points["hand_socket"] + offset
		var f := 1.0 if facing >= 0.0 else -1.0
		draw_line(muzzle, muzzle + Vector2(96.0 * f, 0.0), Color(1.0, 0.95, 0.25, 0.75), 3.0, true)
		draw_circle(muzzle + Vector2(18.0 * f, 0.0), 8.0, Color(1.0, 0.7, 0.18, 0.65))

	if hit_level != "":
		draw_string(ThemeDB.fallback_font, Vector2(-42.0, -132.0), hit_level, HORIZONTAL_ALIGNMENT_CENTER, 84.0, 20, Color.WHITE)

func _draw_limb(from_point: Vector2, to_point: Vector2, color: Color, width: float) -> void:
	draw_line(from_point, to_point, color, width, true)
	draw_circle(from_point, width * 0.45, color)
	draw_circle(to_point, width * 0.45, color)

func _draw_segmented_limb(root: Vector2, joint: Vector2, end: Vector2, color: Color, width: float) -> void:
	_draw_limb(root, joint, color, width)
	_draw_limb(joint, end, color, width * 0.9)

func _pose_points() -> Dictionary:
	var f := 1.0 if facing >= 0.0 else -1.0
	var windup := phase == "STARTUP"
	var active := phase == "ACTIVE" or phase == "IMPACT"
	var recovery := phase == "RECOVERY"
	var p := _phase_eased()
	var crouch := false
	var hitstun := pose_key == "hitstun"
	var broken := pose_key == "stance_break"

	var hip := Vector2(0.0, -38.0)
	var torso := Vector2(0.0, -82.0)
	var neck := Vector2(0.0, -96.0)
	var head := Vector2(0.0, -108.0)
	var front_shoulder := Vector2(9.0 * f, -88.0)
	var back_shoulder := Vector2(-9.0 * f, -86.0)
	var front_elbow := Vector2(18.0 * f, -80.0)
	var back_elbow := Vector2(-14.0 * f, -78.0)
	var front_hand := Vector2(24.0 * f, -78.0)
	var back_hand := Vector2(-18.0 * f, -76.0)
	var front_hip := Vector2(9.0 * f, -38.0)
	var back_hip := Vector2(-9.0 * f, -38.0)
	var front_knee := Vector2(14.0 * f, -20.0)
	var back_knee := Vector2(-14.0 * f, -20.0)
	var front_foot := Vector2(18.0 * f, -2.0)
	var back_foot := Vector2(-18.0 * f, -2.0)

	if crouch:
		hip.y += 18.0
		torso.y += 18.0
		neck.y += 16.0
		head.y += 16.0
		front_shoulder.y += 18.0
		back_shoulder.y += 18.0
		front_elbow = Vector2(22.0 * f, -56.0)
		back_elbow = Vector2(-16.0 * f, -56.0)
		front_hand = Vector2(28.0 * f, -54.0)
		back_hand = Vector2(-16.0 * f, -52.0)
		front_knee = Vector2(22.0 * f, -14.0)
		back_knee = Vector2(-22.0 * f, -14.0)
	if hitstun:
		torso.x -= 18.0 * f
		neck.x -= 22.0 * f
		head.x -= 24.0 * f
		front_elbow = Vector2(-6.0 * f, -66.0)
		back_elbow = Vector2(-28.0 * f, -70.0)
		front_hand = Vector2(-18.0 * f, -68.0)
		back_hand = Vector2(-34.0 * f, -72.0)
	if broken:
		hip.x -= 10.0 * f
		torso.x -= 24.0 * f
		neck.x -= 28.0 * f
		head.x -= 30.0 * f
		front_elbow = Vector2(-16.0 * f, -48.0)
		back_elbow = Vector2(-30.0 * f, -52.0)
		front_hand = Vector2(-26.0 * f, -44.0)
		back_hand = Vector2(-38.0 * f, -50.0)
		front_knee = Vector2(2.0 * f, -18.0)
		back_knee = Vector2(-28.0 * f, -18.0)
		front_foot = Vector2(8.0 * f, -2.0)
		back_foot = Vector2(-30.0 * f, -2.0)

	if pose_key == "mid_punch":
		var extension := 88.0 * p
		if windup:
			torso.x += 8.0 * f * p
			front_shoulder.x += 8.0 * f * p
			front_shoulder.y -= 2.0 * p
			front_elbow = Vector2(lerpf(18.0, -10.0, p) * f, -80.0)
			front_hand = Vector2(lerpf(22.0, -26.0, p) * f, -78.0)
			back_hand = Vector2(-20.0 * f, -86.0)
		elif active:
			torso.x += 12.0 * f
			front_shoulder.x += 16.0 * f
			front_elbow = Vector2((24.0 + extension * 0.32) * f, -78.0)
			front_hand = Vector2((36.0 + extension * 0.55) * f, -78.0)
			back_hand = Vector2(-20.0 * f, -88.0)
		elif recovery:
			front_elbow = Vector2(lerpf(48.0, 18.0, p) * f, -79.0)
			front_hand = Vector2(lerpf(72.0, 24.0, p) * f, -78.0)
			torso.x += lerpf(12.0, 0.0, p) * f
	elif pose_key == "high_hook":
		if windup:
			torso.x -= 12.0 * f * p
			front_shoulder.x -= 10.0 * f * p
			front_shoulder.y -= 6.0 * p
			front_elbow = Vector2(lerpf(18.0, -24.0, p) * f, lerpf(-80.0, -104.0, p))
			front_hand = Vector2(lerpf(24.0, -42.0, p) * f, lerpf(-78.0, -108.0, p))
			back_hand = Vector2(-28.0 * f, -88.0)
		elif active:
			torso.x += 10.0 * f
			front_shoulder.x += 8.0 * f
			front_elbow = Vector2(lerpf(-18.0, 32.0, p) * f, -108.0)
			front_hand = Vector2(lerpf(-12.0, 72.0, p) * f, -108.0)
			back_hand = Vector2(-18.0 * f, -82.0)
		elif recovery:
			front_elbow = Vector2(lerpf(32.0, 18.0, p) * f, lerpf(-108.0, -80.0, p))
			front_hand = Vector2(lerpf(72.0, 24.0, p) * f, lerpf(-108.0, -82.0, p))
	elif pose_key == "low_sweep":
		hip.y += 22.0
		torso.y += 18.0
		neck.y += 16.0
		head.y += 16.0
		front_shoulder.y += 18.0
		back_shoulder.y += 18.0
		back_hand = Vector2(-20.0 * f, -50.0)
		front_knee = Vector2(16.0 * f, -12.0)
		if windup:
			back_knee = Vector2(-30.0 * f, -16.0)
			front_knee = Vector2(lerpf(14.0, -20.0, p) * f, -14.0)
			front_foot = Vector2(lerpf(18.0, -22.0, p) * f, -4.0)
			front_hand = Vector2(18.0 * f, -52.0)
		elif active:
			front_hip.x += 10.0 * f
			front_knee = Vector2(lerpf(2.0, 48.0, p) * f, -12.0)
			front_foot = Vector2(lerpf(10.0, 86.0, p) * f, -6.0)
			front_hand = Vector2(20.0 * f, -48.0)
		elif recovery:
			front_knee = Vector2(lerpf(48.0, 18.0, p) * f, -13.0)
			front_foot = Vector2(lerpf(86.0, 18.0, p) * f, -4.0)
			front_hand = Vector2(24.0 * f, -58.0)
	elif pose_key == "overhead_smash":
		if windup:
			torso.x -= 8.0 * f * p
			torso.y -= 5.0 * p
			front_shoulder.y -= 14.0 * p
			front_elbow = Vector2(lerpf(20.0, -2.0, p) * f, lerpf(-86.0, -132.0, p))
			front_hand = Vector2(lerpf(24.0, -12.0, p) * f, lerpf(-78.0, -154.0, p))
			back_hand = Vector2(8.0 * f, -122.0)
		elif active:
			torso.x += 18.0 * f
			torso.y += 8.0 * p
			front_elbow = Vector2(lerpf(-2.0, 38.0, p) * f, lerpf(-128.0, -74.0, p))
			front_hand = Vector2(lerpf(-4.0, 66.0, p) * f, lerpf(-148.0, -50.0, p))
			back_hand = Vector2(-10.0 * f, -102.0)
		elif recovery:
			front_hand = Vector2(lerpf(66.0, 24.0, p) * f, lerpf(-50.0, -78.0, p))
			torso.x += lerpf(18.0, 0.0, p) * f

	if pose_key == "gunshot":
		if windup:
			torso.x -= 4.0 * f * p
			front_shoulder.x += 4.0 * f * p
			front_elbow = Vector2(22.0 * f, -80.0)
			front_hand = Vector2(lerpf(24.0, 50.0, p) * f, -80.0)
			back_hand = Vector2(-18.0 * f, -88.0)
		elif active:
			torso.x += 6.0 * f
			front_shoulder.x += 8.0 * f
			front_elbow = Vector2(46.0 * f, -80.0)
			front_hand = Vector2(78.0 * f, -80.0)
			back_hand = Vector2(-14.0 * f, -88.0)
		elif recovery:
			front_elbow = Vector2(lerpf(46.0, 18.0, p) * f, -80.0)
			front_hand = Vector2(lerpf(78.0, 24.0, p) * f, -80.0)
	if pose_key.begins_with("jab"):
		if windup:
			torso.x -= 5.0 * f * p
			front_shoulder.x -= 4.0 * f
			front_elbow = Vector2(-4.0 * f, -80.0)
			front_hand = Vector2(-18.0 * f, -80.0)
		elif active:
			torso.x += 8.0 * f
			front_shoulder.x += 10.0 * f
			front_elbow = Vector2(36.0 * f, -78.0)
			front_hand = Vector2(64.0 * f, -78.0)
		elif recovery:
			front_elbow = Vector2(lerpf(36.0, 18.0, p) * f, -78.0)
			front_hand = Vector2(24.0 * f, -78.0)
	if pose_key.begins_with("launcher"):
		if windup:
			hip.y += 12.0 * p
			torso.y += 9.0 * p
			head.y += 8.0 * p
			front_elbow = Vector2(12.0 * f, -62.0)
			front_hand = Vector2(14.0 * f, -42.0)
		elif active:
			hip.y -= 6.0 * p
			front_elbow = Vector2(34.0 * f, -84.0)
			front_hand = Vector2(50.0 * f, -112.0)
			torso.y -= 8.0
		elif recovery:
			front_hand = Vector2(26.0 * f, -94.0)
	if pose_key.begins_with("air_follow"):
		torso.x += 16.0 * f * p
		torso.y -= 8.0
		head.x += 12.0 * f * p
		front_elbow = Vector2(24.0 * f, -88.0)
		front_hand = Vector2(lerpf(28.0, 78.0, p) * f, lerpf(-88.0, -94.0, p))
		front_knee = Vector2(24.0 * f, -34.0)
		front_foot = Vector2(lerpf(24.0, 70.0, p) * f, -42.0)
	if pose_key.begins_with("heavy_slash"):
		if windup:
			torso.x -= 18.0 * f * p
			front_shoulder.x -= 16.0 * f * p
			front_elbow = Vector2(lerpf(18.0, -34.0, p) * f, lerpf(-80.0, -108.0, p))
			front_hand = Vector2(lerpf(24.0, -58.0, p) * f, lerpf(-78.0, -112.0, p))
		elif active:
			torso.x += 22.0 * f
			front_elbow = Vector2(lerpf(-24.0, 46.0, p) * f, lerpf(-104.0, -62.0, p))
			front_hand = Vector2(lerpf(-46.0, 92.0, p) * f, lerpf(-110.0, -58.0, p))
		elif recovery:
			torso.x += lerpf(18.0, 0.0, p) * f
			front_elbow = Vector2(34.0 * f, -70.0)
			front_hand = Vector2(54.0 * f, -64.0)
	if pose_key.begins_with("guard_break"):
		if windup:
			hip.y += 8.0 * p
			torso.x -= 10.0 * f * p
			front_elbow = Vector2(-4.0 * f, -72.0)
			front_hand = Vector2(-20.0 * f, -70.0)
		elif active:
			torso.x += 14.0 * f
			front_elbow = Vector2(42.0 * f, -72.0)
			front_hand = Vector2(78.0 * f, -70.0)
			back_hand = Vector2(24.0 * f, -88.0)
		elif recovery:
			front_elbow = Vector2(28.0 * f, -76.0)
			front_hand = Vector2(40.0 * f, -76.0)
	if pose_key.begins_with("ground_smash"):
		if windup:
			torso.y -= 12.0 * p
			front_elbow = Vector2(12.0 * f, -124.0)
			front_hand = Vector2(18.0 * f, -154.0)
		elif active:
			hip.y += 14.0 * p
			torso.y += 16.0 * p
			front_elbow = Vector2(42.0 * f, -54.0)
			front_hand = Vector2(72.0 * f, -20.0)
			front_knee = Vector2(28.0 * f, -14.0)
			front_foot = Vector2(54.0 * f, -2.0)
		elif recovery:
			hip.y += 10.0
			torso.y += 10.0
			front_hand = Vector2(38.0 * f, -54.0)
	if pose_key.begins_with("kick"):
		if windup:
			front_knee = Vector2(-2.0 * f, -18.0)
			front_foot = Vector2(-8.0 * f, -8.0)
		elif active:
			front_knee = Vector2(36.0 * f, -22.0)
			front_foot = Vector2(66.0 * f, -28.0)
		elif recovery:
			front_foot = Vector2(28.0 * f, -6.0)
	if pose_key == "step_forward" or pose_key == "walk_forward":
		var stride := 1.0 if active else p
		hip.x += lerpf(0.0, 10.0, stride) * f
		torso.x += lerpf(0.0, 14.0, stride) * f
		front_knee = Vector2(lerpf(14.0, 30.0, stride) * f, lerpf(-20.0, -24.0, stride))
		front_foot = Vector2(lerpf(18.0, 42.0, stride) * f, -2.0)
		back_knee = Vector2(lerpf(-14.0, -26.0, stride) * f, lerpf(-20.0, -16.0, stride))
		back_foot = Vector2(lerpf(-18.0, -34.0, stride) * f, -2.0)
	if pose_key == "backstep":
		var retreat := 1.0 if active else p
		hip.x -= lerpf(0.0, 14.0, retreat) * f
		torso.x -= lerpf(0.0, 18.0, retreat) * f
		front_knee = Vector2(lerpf(14.0, 8.0, retreat) * f, -18.0)
		front_foot = Vector2(lerpf(18.0, 6.0, retreat) * f, -2.0)
		back_knee = Vector2(lerpf(-14.0, -34.0, retreat) * f, -18.0)
		back_foot = Vector2(lerpf(-18.0, -52.0, retreat) * f, -2.0)
	if pose_key == "block_high":
		hip.x -= 4.0 * f * p
		torso.x -= 8.0 * f * p
		front_elbow = Vector2(lerpf(18.0, 26.0, p) * f, lerpf(-80.0, -92.0, p))
		front_hand = Vector2(lerpf(24.0, 28.0, p) * f, lerpf(-78.0, -100.0, p))
		back_elbow = Vector2(lerpf(-14.0, 6.0, p) * f, lerpf(-78.0, -78.0, p))
		back_hand = Vector2(lerpf(-18.0, 18.0, p) * f, lerpf(-76.0, -76.0, p))
	if pose_key == "block_low":
		hip.y += 18.0 * p
		torso.y += 18.0 * p
		neck.y += 16.0 * p
		head.y += 16.0 * p
		front_elbow = Vector2(lerpf(18.0, 26.0, p) * f, lerpf(-80.0, -58.0, p))
		front_hand = Vector2(lerpf(24.0, 28.0, p) * f, lerpf(-78.0, -54.0, p))
		back_elbow = Vector2(lerpf(-14.0, -16.0, p) * f, lerpf(-78.0, -58.0, p))
		back_hand = Vector2(lerpf(-18.0, -16.0, p) * f, lerpf(-76.0, -52.0, p))
	if pose_key == "jump":
		var lift := 32.0 * p
		hip.y -= lift
		torso.y -= lift + 4.0
		neck.y -= lift + 5.0
		head.y -= lift + 5.0
		front_shoulder.y -= lift
		back_shoulder.y -= lift
		front_elbow = Vector2(20.0 * f, -94.0 - lift)
		back_elbow = Vector2(-18.0 * f, -92.0 - lift)
		front_hand = Vector2(28.0 * f, -106.0 - lift)
		back_hand = Vector2(-26.0 * f, -104.0 - lift)
		front_hip.y -= lift
		back_hip.y -= lift
		front_knee = Vector2(22.0 * f, -28.0 - lift)
		back_knee = Vector2(-12.0 * f, -30.0 - lift)
		front_foot = Vector2(30.0 * f, -16.0 - lift)
		back_foot = Vector2(-24.0 * f, -12.0 - lift)

	var socket := front_hand
	if pose_key.begins_with("kick") or pose_key.begins_with("air_follow") or pose_key.begins_with("ground_smash") or pose_key == "low_sweep":
		socket = front_foot

	return {
		"hip": hip,
		"torso": torso,
		"neck": neck,
		"head": head,
		"front_shoulder": front_shoulder,
		"back_shoulder": back_shoulder,
		"front_elbow": front_elbow,
		"back_elbow": back_elbow,
		"front_hand": front_hand,
		"back_hand": back_hand,
		"front_hip": front_hip,
		"back_hip": back_hip,
		"front_knee": front_knee,
		"back_knee": back_knee,
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
		socket = points["foot_socket"] + Vector2(12.0 * (1.0 if facing >= 0.0 else -1.0), 0.0)
		size = Vector2(86.0, 24.0)
	elif hit_level == "OVERHEAD":
		socket = points["hand_socket"] + Vector2(10.0 * (1.0 if facing >= 0.0 else -1.0), -8.0)
		size = Vector2(72.0, 72.0)
	elif hit_level == "HIGH":
		socket = points["hand_socket"]
		size = Vector2(78.0, 34.0)
	elif hit_level == "MID":
		socket = points["hand_socket"]
		size = Vector2(84.0, 38.0)
	return Rect2(socket - size * 0.5, size)

func _phase_eased() -> float:
	return phase_progress * phase_progress * (3.0 - 2.0 * phase_progress)

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
