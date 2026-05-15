class_name Player
extends CharacterBody2D

signal hp_changed(current_hp: int, max_hp: int)
signal defense_performed(defense_type: String)

const CombatAnimationDriver := preload("res://scripts/animation/combat_animation_driver.gd")
const SPEED := 250.0
const JUMP_VELOCITY := -500.0
const GRAVITY := 1300.0

@export var max_hp := 100
@export var hurtbox_width := 50.0
@export var hurtbox_height := 90.0

var hp := max_hp
var input_enabled := true
var free_movement_enabled := true
var current_animation_action := "None"
var current_animation_phase := "DONE"
var current_animation_progress := 0.0
var current_animation_hit_level := ""
var current_animation_hitbox_active := false
var _card_visual_tween: Tween

@onready var body: ColorRect = $Body
@onready var state_label: Label = $StateLabel
@onready var rig: Node = $Rig

func _ready() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)
	_set_state("READY")

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	var direction := 0.0
	if input_enabled and free_movement_enabled:
		direction = Input.get_axis("move_left", "move_right")
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
			defense_performed.emit("jump")
			_flash(Color.SKY_BLUE, "JUMP")
		if Input.is_action_just_pressed("block"):
			var defense_type := "crouch_block" if Input.is_key_pressed(KEY_S) else "block"
			defense_performed.emit(defense_type)
			_flash(Color.CORNFLOWER_BLUE if defense_type == "crouch_block" else Color.DODGER_BLUE, "LOW BLOCK" if defense_type == "crouch_block" else "BLOCK")
		if Input.is_action_just_pressed("backstep"):
			velocity.x = -SPEED * 2.2
			defense_performed.emit("backstep")
			_flash(Color.LIGHT_BLUE, "BACKSTEP")

	if absf(velocity.x) < SPEED * 1.8:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, direction * SPEED, SPEED * delta * 5.0)

	move_and_slide()

func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	hp = maxi(0, hp - amount)
	hp_changed.emit(hp, max_hp)
	CombatAnimationDriver.drive_rig(rig, "hitstun", "IMPACT", 1.0, "", false)
	CombatAnimationDriver.play_impact(rig)
	_flash(Color.INDIAN_RED, "HIT")

func perform_card_action(card: Resource) -> void:
	_flash(Color.GOLD, card.display_name.to_upper())
	_play_readable_card_sequence(card)

func show_state(label: String, color: Color) -> void:
	_flash(color, label)

func show_timeline_phase(action_name: String, phase_name: String, phase_progress := 0.0, hit_level := "", hitbox_active := false) -> void:
	current_animation_action = action_name
	current_animation_phase = phase_name
	current_animation_progress = phase_progress
	current_animation_hit_level = hit_level
	current_animation_hitbox_active = hitbox_active
	CombatAnimationDriver.drive_rig(rig, action_name, phase_name, phase_progress, hit_level, hitbox_active)
	match phase_name:
		"STARTUP":
			body.color = Color(0.35, 0.62, 1.0)
			body.scale = Vector2(0.92, 1.04)
		"ACTIVE", "IMPACT":
			body.color = Color.GOLD
			body.scale = Vector2(1.08, 0.96)
		"RECOVERY":
			body.color = Color(0.55, 0.82, 1.0)
			body.scale = Vector2(0.98, 1.0)
		_:
			body.color = Color(0.25, 0.75, 1.0)
			body.scale = Vector2.ONE
	_set_state("%s\n%s" % [action_name.to_upper(), phase_name])

func clear_timeline_visual() -> void:
	if _card_visual_tween != null and _card_visual_tween.is_running():
		_card_visual_tween.kill()
	body.color = Color(0.25, 0.75, 1.0)
	body.scale = Vector2.ONE
	current_animation_action = "None"
	current_animation_phase = "DONE"
	current_animation_progress = 0.0
	current_animation_hit_level = ""
	current_animation_hitbox_active = false
	CombatAnimationDriver.clear(rig)

func _play_readable_card_sequence(card: Resource) -> void:
	if rig == null:
		return
	if _card_visual_tween != null and _card_visual_tween.is_running():
		_card_visual_tween.kill()
	var action_name := String(card.display_name)
	var startup_seconds := clampf(float(card.startup_frame) / 60.0, 0.08, 0.22)
	var active_seconds := 0.08
	var recovery_seconds := clampf(float(maxi(1, int(card.frame_cost))) / 60.0, 0.08, 0.18)
	_card_visual_tween = create_tween()
	_card_visual_tween.tween_method(_drive_card_visual.bind(action_name, "STARTUP", false), 0.0, 1.0, startup_seconds)
	_card_visual_tween.tween_method(_drive_card_visual.bind(action_name, "ACTIVE", true), 0.0, 1.0, active_seconds)
	_card_visual_tween.tween_method(_drive_card_visual.bind(action_name, "RECOVERY", false), 0.0, 1.0, recovery_seconds)

func _drive_card_visual(progress: float, action_name: String, phase_name: String, hitbox_active: bool) -> void:
	current_animation_action = action_name
	current_animation_phase = phase_name
	current_animation_progress = progress
	current_animation_hit_level = ""
	current_animation_hitbox_active = hitbox_active
	CombatAnimationDriver.drive_rig(rig, action_name, phase_name, progress, "", hitbox_active)

func get_animation_debug() -> Dictionary:
	return {
		"animation_key": rig.pose_key if rig != null and "pose_key" in rig else "unknown",
		"pose_key": rig.pose_key if rig != null and "pose_key" in rig else "unknown",
		"action_name": current_animation_action,
		"phase": current_animation_phase,
		"phase_progress": current_animation_progress,
		"phase_frames_remaining": null,
		"active_frame_window": "unknown",
		"hitbox_active": current_animation_hitbox_active,
		"current_pose_name": rig.pose_key if rig != null and "pose_key" in rig else "unknown",
		"movement_phase": "unknown",
		"movement_direction": "unknown",
		"rig_scale": rig.scale if rig != null else Vector2.ONE,
		"facing": "right" if rig == null or float(rig.facing) >= 0.0 else "left",
		"hit_level": current_animation_hit_level
	}

func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled

func set_free_movement_enabled(enabled: bool) -> void:
	free_movement_enabled = enabled
	if not enabled:
		velocity.x = 0.0

func _flash(color: Color, label: String) -> void:
	body.color = color
	_set_state(label)
	var tween := create_tween()
	tween.tween_property(body, "color", Color(0.25, 0.75, 1.0), 0.18)

func _set_state(text: String) -> void:
	state_label.text = text
