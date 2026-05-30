class_name CharacterRig2D
extends Node2D

@export var facing := 1.0
@export var body_color := Color(0.25, 0.75, 1.0)
@export var active_hitbox_color := Color(1.0, 0.85, 0.18, 0.28)
@export var show_anchor_debug := false
@export var show_joint_debug := true
@export var show_socket_hitbox_debug := false

const PROPORTION_SCALE := 0.72
const HEAD_RADIUS := 18.0
const NECK_LENGTH := 6.0
const TORSO_LENGTH := 80.0
const SHOULDER_WIDTH := 48.0
const HIP_WIDTH := 36.0
const UPPER_ARM_LENGTH := 42.0
const FOREARM_LENGTH := 38.0
const HAND_RADIUS := 7.0
const THIGH_LENGTH := 52.0
const SHIN_LENGTH := 50.0
const FOOT_LENGTH := 18.0
const JOINT_RADIUS := 6.0
const LIMB_THICKNESS := 9.0
const TORSO_THICKNESS := 12.0

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
	var width := _rig_units(LIMB_THICKNESS) + impact_pulse * 2.0
	var torso_width := _rig_units(TORSO_THICKNESS) + impact_pulse * 2.0
	var offset := _shake_offset

	_draw_body_mass(points, color, offset)
	_draw_limb(points["hip"] + offset, points["torso"] + offset, color, torso_width)
	_draw_limb(points["torso"] + offset, points["neck"] + offset, color, width)
	_draw_segmented_limb(points["front_shoulder"] + offset, points["front_elbow"] + offset, points["front_hand"] + offset, color, width)
	_draw_segmented_limb(points["back_shoulder"] + offset, points["back_elbow"] + offset, points["back_hand"] + offset, color.darkened(0.18), width)
	_draw_segmented_limb(points["front_hip"] + offset, points["front_knee"] + offset, points["front_foot"] + offset, color, width)
	_draw_segmented_limb(points["back_hip"] + offset, points["back_knee"] + offset, points["back_foot"] + offset, color.darkened(0.18), width)
	_draw_foot(points["front_foot"] + offset, color)
	_draw_foot(points["back_foot"] + offset, color.darkened(0.18))

	draw_circle(points["head"] + offset, _rig_units(HEAD_RADIUS) + impact_pulse * 2.0, color)
	if show_joint_debug:
		_draw_joint(points["front_shoulder"] + offset, color.lightened(0.16))
		_draw_joint(points["back_shoulder"] + offset, color.darkened(0.08))
		_draw_joint(points["front_elbow"] + offset, color.lightened(0.18))
		_draw_joint(points["back_elbow"] + offset, color.darkened(0.05))
		_draw_joint(points["front_hip"] + offset, color.lightened(0.12))
		_draw_joint(points["back_hip"] + offset, color.darkened(0.08))
		_draw_joint(points["front_knee"] + offset, color.lightened(0.18))
		_draw_joint(points["back_knee"] + offset, color.darkened(0.05))
		draw_circle(points["hand_socket"] + offset, _rig_units(HAND_RADIUS), Color.WHITE)
		draw_circle(points["foot_socket"] + offset, _rig_units(JOINT_RADIUS) * 0.85, Color.WHITE)

	if hitbox_active and show_socket_hitbox_debug:
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
	if show_anchor_debug:
		_draw_anchor_debug(points, offset)

func _draw_limb(from_point: Vector2, to_point: Vector2, color: Color, width: float) -> void:
	draw_line(from_point, to_point, color, width, true)
	draw_circle(from_point, width * 0.45, color)
	draw_circle(to_point, width * 0.45, color)

func _draw_segmented_limb(root: Vector2, joint: Vector2, end: Vector2, color: Color, width: float) -> void:
	_draw_limb(root, joint, color, width)
	_draw_limb(joint, end, color, width * 0.9)

func _draw_body_mass(points: Dictionary, color: Color, offset: Vector2) -> void:
	var chest: Vector2 = points["chest"] + Vector2(-2.0 * _facing_sign(), 12.0) + offset
	var pelvis: Vector2 = points["hip"] + Vector2(0.0, 1.0) + offset
	draw_circle(chest, _rig_units(15.0), color.darkened(0.08))
	draw_circle(pelvis, _rig_units(10.0), color.darkened(0.12))
	draw_line(chest, pelvis, color.darkened(0.1), _rig_units(18.0), true)

func _draw_joint(position: Vector2, color: Color) -> void:
	draw_circle(position, _rig_units(JOINT_RADIUS), color)

func _draw_foot(position: Vector2, color: Color) -> void:
	var f := _facing_sign()
	var foot_length := _rig_units(FOOT_LENGTH)
	draw_line(position - Vector2(foot_length * 0.25 * f, 0.0), position + Vector2(foot_length * 0.75 * f, 0.0), color, _rig_units(LIMB_THICKNESS) * 0.8, true)

func _draw_anchor_debug(points: Dictionary, offset: Vector2) -> void:
	var names := [
		"hip", "chest", "neck", "head",
		"left_shoulder", "right_shoulder", "left_elbow", "right_elbow", "left_hand", "right_hand",
		"left_hip", "right_hip", "left_knee", "right_knee", "left_foot", "right_foot"
	]
	for anchor_name in names:
		if not points.has(anchor_name):
			continue
		var anchor: Vector2 = points[anchor_name] + offset
		draw_circle(anchor, 2.0, Color(1.0, 0.95, 0.2, 0.9))
		draw_string(ThemeDB.fallback_font, anchor + Vector2(4.0, -4.0), anchor_name, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 9, Color(1.0, 0.95, 0.2, 0.9))

func _pose_points() -> Dictionary:
	var f := _facing_sign()
	var windup := phase == "STARTUP"
	var active := phase == "ACTIVE" or phase == "IMPACT"
	var recovery := phase == "RECOVERY"
	var p := _phase_eased()
	var crouch := false
	var hitstun := pose_key == "hitstun"
	var broken := pose_key == "stance_break"

	var hip := Vector2(0.0, -56.0)
	var torso := Vector2(5.0 * f, -88.0)
	var neck := Vector2(4.0 * f, -101.0)
	var head := Vector2(4.0 * f, -113.0)
	var front_shoulder := Vector2(18.0 * f, -90.0)
	var back_shoulder := Vector2(-16.0 * f, -88.0)
	var front_elbow := Vector2(21.0 * f, -77.0)
	var back_elbow := Vector2(-10.0 * f, -77.0)
	var front_hand := Vector2(31.0 * f, -93.0)
	var back_hand := Vector2(8.0 * f, -94.0)
	var front_hip := Vector2(12.0 * f, -56.0)
	var back_hip := Vector2(-12.0 * f, -55.0)
	var front_knee := Vector2(16.0 * f, -27.0)
	var back_knee := Vector2(-17.0 * f, -25.0)
	var front_foot := Vector2(25.0 * f, 0.0)
	var back_foot := Vector2(-25.0 * f, 0.0)
	var guard_hip := hip
	var guard_torso := torso
	var guard_neck := neck
	var guard_head := head
	var guard_front_shoulder := front_shoulder
	var guard_back_shoulder := back_shoulder
	var guard_front_elbow := front_elbow
	var guard_back_elbow := back_elbow
	var guard_front_hand := front_hand
	var guard_back_hand := back_hand
	var guard_front_hip := front_hip
	var guard_back_hip := back_hip
	var guard_front_knee := front_knee
	var guard_back_knee := back_knee
	var guard_front_foot := front_foot
	var guard_back_foot := back_foot

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
		torso.x -= 16.0 * f
		neck.x -= 16.0 * f
		head.x -= 15.0 * f
		front_elbow = guard_front_elbow + Vector2(-22.0 * f, 8.0)
		back_elbow = guard_back_elbow + Vector2(-22.0 * f, 6.0)
		front_hand = guard_front_hand + Vector2(-38.0 * f, 8.0)
		back_hand = guard_back_hand + Vector2(-36.0 * f, 6.0)
	if broken:
		hip.x -= 10.0 * f
		torso.x -= 22.0 * f
		neck.x -= 22.0 * f
		head.x -= 21.0 * f
		front_elbow = Vector2(-12.0 * f, -52.0)
		back_elbow = Vector2(-28.0 * f, -54.0)
		front_hand = Vector2(-22.0 * f, -46.0)
		back_hand = Vector2(-36.0 * f, -50.0)
		front_knee = Vector2(4.0 * f, -20.0)
		back_knee = Vector2(-24.0 * f, -18.0)
		front_foot = Vector2(8.0 * f, 0.0)
		back_foot = Vector2(-30.0 * f, 0.0)

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
			torso.x -= 5.0 * f * p
			front_shoulder.x += 6.0 * f * p
			front_elbow = guard_front_elbow.lerp(Vector2(30.0 * f, -84.0), p)
			front_hand = guard_front_hand.lerp(Vector2(54.0 * f, -84.0), p)
			back_hand = guard_back_hand.lerp(Vector2(-4.0 * f, -94.0), p)
		elif active:
			torso.x += 6.0 * f
			front_shoulder.x += 8.0 * f
			front_elbow = Vector2(46.0 * f, -84.0)
			front_hand = Vector2(82.0 * f, -84.0)
			back_hand = Vector2(-6.0 * f, -94.0)
		elif recovery:
			front_elbow = Vector2(46.0 * f, -84.0).lerp(guard_front_elbow, p)
			front_hand = Vector2(82.0 * f, -84.0).lerp(guard_front_hand, p)
	if pose_key.begins_with("jab"):
		if windup:
			torso.x -= 6.0 * f * p
			front_shoulder.x -= 5.0 * f * p
			front_elbow = guard_front_elbow.lerp(Vector2(-2.0 * f, -86.0), p)
			front_hand = guard_front_hand.lerp(Vector2(-16.0 * f, -88.0), p)
		elif active:
			torso.x += 10.0 * f
			front_shoulder.x += 12.0 * f
			front_elbow = Vector2(38.0 * f, -84.0)
			front_hand = Vector2(72.0 * f, -84.0)
			back_hand = guard_back_hand + Vector2(4.0 * f, -4.0)
		elif recovery:
			torso.x += lerpf(8.0, 0.0, p) * f
			front_elbow = Vector2(38.0 * f, -84.0).lerp(guard_front_elbow, p)
			front_hand = Vector2(72.0 * f, -84.0).lerp(guard_front_hand, p)
	if pose_key.begins_with("launcher"):
		if windup:
			hip.y += 12.0 * p
			torso.y += 9.0 * p
			head.y += 8.0 * p
			front_elbow = guard_front_elbow.lerp(Vector2(12.0 * f, -64.0), p)
			front_hand = guard_front_hand.lerp(Vector2(16.0 * f, -44.0), p)
			front_knee = guard_front_knee + Vector2(5.0 * f, 4.0 * p)
		elif active:
			hip.y -= 6.0 * p
			front_elbow = Vector2(34.0 * f, -90.0)
			front_hand = Vector2(52.0 * f, -118.0)
			torso.y -= 8.0
		elif recovery:
			front_elbow = Vector2(34.0 * f, -90.0).lerp(guard_front_elbow, p)
			front_hand = Vector2(52.0 * f, -118.0).lerp(guard_front_hand, p)
	if pose_key.begins_with("air_follow"):
		torso.x += 16.0 * f * p
		torso.y -= 8.0
		head.x += 12.0 * f * p
		front_elbow = Vector2(28.0 * f, -92.0)
		front_hand = Vector2(lerpf(32.0, 84.0, p) * f, lerpf(-92.0, -98.0, p))
		back_hand = guard_back_hand + Vector2(-8.0 * f, -6.0)
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
		torso.x += lerpf(0.0, 16.0, stride) * f
		neck.x += lerpf(0.0, 10.0, stride) * f
		head.x += lerpf(0.0, 8.0, stride) * f
		front_elbow = guard_front_elbow + Vector2(2.0 * f, -2.0)
		front_hand = guard_front_hand + Vector2(4.0 * f, -2.0)
		back_elbow = guard_back_elbow + Vector2(-2.0 * f, 1.0)
		back_hand = guard_back_hand + Vector2(-3.0 * f, 1.0)
		front_knee = guard_front_knee.lerp(Vector2(34.0 * f, -28.0), stride)
		front_foot = guard_front_foot.lerp(Vector2(48.0 * f, -1.0), stride)
		back_knee = guard_back_knee.lerp(Vector2(-24.0 * f, -18.0), stride)
		back_foot = guard_back_foot.lerp(Vector2(-36.0 * f, -1.0), stride)
	if pose_key == "backstep":
		var retreat := 1.0 if active else p
		hip.x -= lerpf(0.0, 14.0, retreat) * f
		torso.x -= lerpf(0.0, 18.0, retreat) * f
		neck.x -= lerpf(0.0, 10.0, retreat) * f
		head.x -= lerpf(0.0, 8.0, retreat) * f
		front_elbow = guard_front_elbow + Vector2(-3.0 * f, -2.0)
		front_hand = guard_front_hand + Vector2(-4.0 * f, -2.0)
		front_knee = guard_front_knee.lerp(Vector2(8.0 * f, -22.0), retreat)
		front_foot = guard_front_foot.lerp(Vector2(6.0 * f, -1.0), retreat)
		back_knee = guard_back_knee.lerp(Vector2(-36.0 * f, -18.0), retreat)
		back_foot = guard_back_foot.lerp(Vector2(-56.0 * f, -1.0), retreat)
	if pose_key == "block_high":
		hip.x -= 4.0 * f * p
		torso.x -= 8.0 * f * p
		neck.x -= 3.0 * f * p
		head.x -= 2.0 * f * p
		front_elbow = guard_front_elbow.lerp(Vector2(23.0 * f, -89.0), p)
		front_hand = guard_front_hand.lerp(Vector2(22.0 * f, -104.0), p)
		back_elbow = guard_back_elbow.lerp(Vector2(3.0 * f, -82.0), p)
		back_hand = guard_back_hand.lerp(Vector2(12.0 * f, -96.0), p)
	if pose_key == "block_low":
		hip.y += 14.0 * p
		torso.y += 12.0 * p
		neck.y += 11.0 * p
		head.y += 11.0 * p
		torso.x -= 4.0 * f * p
		front_knee = guard_front_knee.lerp(Vector2(19.0 * f, -18.0), p)
		back_knee = guard_back_knee.lerp(Vector2(-20.0 * f, -17.0), p)
		front_foot = guard_front_foot
		back_foot = guard_back_foot
		front_elbow = guard_front_elbow.lerp(Vector2(24.0 * f, -61.0), p)
		front_hand = guard_front_hand.lerp(Vector2(27.0 * f, -55.0), p)
		back_elbow = guard_back_elbow.lerp(Vector2(-8.0 * f, -63.0), p)
		back_hand = guard_back_hand.lerp(Vector2(-4.0 * f, -56.0), p)
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

	if recovery and pose_key != "hitstun" and pose_key != "stance_break":
		var return_to_guard := clampf(p * 0.9, 0.0, 1.0)
		hip = hip.lerp(guard_hip, return_to_guard)
		torso = torso.lerp(guard_torso, return_to_guard)
		neck = neck.lerp(guard_neck, return_to_guard)
		head = head.lerp(guard_head, return_to_guard)
		front_shoulder = front_shoulder.lerp(guard_front_shoulder, return_to_guard)
		back_shoulder = back_shoulder.lerp(guard_back_shoulder, return_to_guard)
		front_elbow = front_elbow.lerp(guard_front_elbow, return_to_guard)
		back_elbow = back_elbow.lerp(guard_back_elbow, return_to_guard)
		front_hand = front_hand.lerp(guard_front_hand, return_to_guard)
		back_hand = back_hand.lerp(guard_back_hand, return_to_guard)
		front_hip = front_hip.lerp(guard_front_hip, return_to_guard)
		back_hip = back_hip.lerp(guard_back_hip, return_to_guard)
		front_knee = front_knee.lerp(guard_front_knee, return_to_guard)
		back_knee = back_knee.lerp(guard_back_knee, return_to_guard)
		front_foot = front_foot.lerp(guard_front_foot, return_to_guard)
		back_foot = back_foot.lerp(guard_back_foot, return_to_guard)

	var socket := front_hand
	if pose_key.begins_with("kick") or pose_key.begins_with("air_follow") or pose_key.begins_with("ground_smash") or pose_key == "low_sweep":
		socket = front_foot

	var points := {
		"hip": hip,
		"torso": torso,
		"chest": torso,
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
	_add_named_side_anchors(points, f)
	return points

func _add_named_side_anchors(points: Dictionary, f: float) -> void:
	var front_side := "right" if f >= 0.0 else "left"
	var back_side := "left" if f >= 0.0 else "right"
	for joint_name in ["shoulder", "elbow", "hand", "hip", "knee", "foot"]:
		points["%s_%s" % [front_side, joint_name]] = points["front_%s" % joint_name]
		points["%s_%s" % [back_side, joint_name]] = points["back_%s" % joint_name]

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

func _rig_units(value: float) -> float:
	return value * PROPORTION_SCALE

func _facing_sign() -> float:
	return 1.0 if facing >= 0.0 else -1.0

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
