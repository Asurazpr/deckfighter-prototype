class_name Player
extends CharacterBody2D

signal hp_changed(current_hp: int, max_hp: int)
signal stance_changed(current_stance: int, max_stance: int)
signal defense_performed(defense_type: String)
signal defensive_input_rejected(input_name: String, reason: String)

const CombatAnimationDriver := preload("res://scripts/animation/combat_animation_driver.gd")
const StanceConfig := preload("res://scripts/enemy/enemy_stance_config.gd")
const SPEED := 250.0
const JUMP_VELOCITY := -650.0
const GRAVITY := 1300.0

enum StanceState { NORMAL, BROKEN_HITSTUN, BROKEN_BLOCKSTUN, RECOVERING_PROTECTED }

@export var max_hp := 100
@export var max_stance := StanceConfig.MAX_STANCE
@export var hurtbox_width := 50.0
@export var hurtbox_height := 90.0
@export var crouch_hurtbox_width := 50.0
@export var crouch_hurtbox_height := 40.0

var hp := max_hp
var stance := 0
var stance_state := StanceState.NORMAL
var stance_recovery_frames_remaining := 0
var stance_break_stun_frames_remaining := 0
var stance_protection_frames_remaining := 0
var input_enabled := true
var free_movement_enabled := true
var crouching := false
var current_animation_action := "None"
var current_animation_phase := "DONE"
var current_animation_progress := 0.0
var current_animation_hit_level := ""
var current_animation_hitbox_active := false
var _card_visual_tween: Tween
var _base_hurtbox_shape_size := Vector2.ZERO
var _base_hurtbox_shape_position := Vector2.ZERO
var _crouch_reject_latched := false

@onready var body: ColorRect = $Body
@onready var state_label: Label = $StateLabel
@onready var rig: Node = $Rig
@onready var hurtbox_shape: CollisionShape2D = get_node_or_null("Hurtbox/CollisionShape2D") as CollisionShape2D

func _ready() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)
	stance = 0
	stance_changed.emit(stance, max_stance)
	_cache_hurtbox_shape()
	_set_state("READY")

func _physics_process(delta: float) -> void:
	_update_neutral_crouch()
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	var direction := 0.0
	if input_enabled and free_movement_enabled:
		direction = 0.0 if crouching else Input.get_axis("move_left", "move_right")
		if not crouching and Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
			defense_performed.emit("jump")
			_flash(Color.SKY_BLUE, "JUMP")
		if Input.is_action_just_pressed("block"):
			var defense_type := "crouch_block" if Input.is_key_pressed(KEY_S) else "block"
			defense_performed.emit(defense_type)
			_flash(Color.CORNFLOWER_BLUE if defense_type == "crouch_block" else Color.DODGER_BLUE, "LOW BLOCK" if defense_type == "crouch_block" else "BLOCK")
		if not crouching and Input.is_action_just_pressed("backstep"):
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

func add_stance_damage(amount: int) -> void:
	if is_stance_protected():
		if amount > 0:
			print("Player stance protected: ignored %d stance damage" % amount)
		return
	if amount <= 0:
		return
	stance = mini(max_stance, stance + amount)
	stance_changed.emit(stance, max_stance)
	if stance >= max_stance:
		enter_stance_break(false)

func add_block_stance_damage(amount: int) -> void:
	if is_stance_protected():
		if amount > 0:
			print("Player stance protected: ignored %d stance damage" % amount)
		return
	if amount <= 0:
		return
	stance = mini(max_stance, stance + amount)
	stance_changed.emit(stance, max_stance)
	if stance >= max_stance:
		enter_stance_break(true)

func enter_stance_break(from_block := false) -> void:
	if stance_state != StanceState.NORMAL:
		return
	stance_state = StanceState.BROKEN_BLOCKSTUN if from_block else StanceState.BROKEN_HITSTUN
	stance_break_stun_frames_remaining = StanceConfig.BREAK_BLOCK_RECOVERY_FRAMES if from_block else StanceConfig.BREAK_HITSTUN_FRAMES
	stance_protection_frames_remaining = StanceConfig.PROTECTION_RECOVERY_FRAMES
	_update_stance_recovery_total()
	if has_method("force_finish_action"):
		call("force_finish_action")
	CombatAnimationDriver.drive_rig(rig, "stance_break", "IMPACT", 1.0, "", false)
	_flash(Color.ORANGE, "STANCE BREAK")

func advance_stance_recovery_frames(frames: int) -> void:
	if frames <= 0 or stance_state == StanceState.NORMAL:
		return

	var remaining_frames := frames
	if stance_break_stun_frames_remaining > 0:
		var spent_stun := mini(stance_break_stun_frames_remaining, remaining_frames)
		stance_break_stun_frames_remaining -= spent_stun
		remaining_frames -= spent_stun
		if stance_break_stun_frames_remaining <= 0 and stance_state != StanceState.RECOVERING_PROTECTED:
			stance_state = StanceState.RECOVERING_PROTECTED

	if remaining_frames > 0 and stance_protection_frames_remaining > 0:
		var spent_protection := mini(stance_protection_frames_remaining, remaining_frames)
		stance_protection_frames_remaining -= spent_protection

	_update_stance_recovery_total()
	if stance_break_stun_frames_remaining <= 0 and stance_protection_frames_remaining <= 0:
		_finish_stance_recovery()

func is_stance_protected() -> bool:
	return stance_state == StanceState.BROKEN_HITSTUN or stance_state == StanceState.BROKEN_BLOCKSTUN or stance_state == StanceState.RECOVERING_PROTECTED

func get_stance_state_name() -> String:
	match stance_state:
		StanceState.NORMAL:
			return "NORMAL"
		StanceState.BROKEN_HITSTUN:
			return "BROKEN_HITSTUN"
		StanceState.BROKEN_BLOCKSTUN:
			return "BROKEN_BLOCKSTUN"
		StanceState.RECOVERING_PROTECTED:
			return "RECOVERING_PROTECTED"
		_:
			return "UNKNOWN"

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
	_set_state("READY")

func clear_stale_defense_action() -> void:
	clear_timeline_visual()

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
		"hit_level": current_animation_hit_level,
		"crouching": crouching,
		"stance": stance,
		"stance_state": get_stance_state_name(),
		"stance_recovery_frames": stance_recovery_frames_remaining
	}

func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled

func set_free_movement_enabled(enabled: bool) -> void:
	free_movement_enabled = enabled
	if not enabled:
		velocity.x = 0.0

func reset_for_round_start() -> void:
	velocity = Vector2.ZERO
	crouching = false
	_apply_crouch_hurtbox(false)
	clear_timeline_visual()
	_set_state("READY")

func is_crouching() -> bool:
	return crouching

func set_combat_crouch(enabled: bool) -> void:
	if crouching == enabled:
		return
	crouching = enabled
	_apply_crouch_hurtbox(crouching)
	velocity.x = 0.0 if crouching else velocity.x
	_set_state("CROUCH" if crouching else "READY")

func can_enter_neutral_crouch() -> bool:
	return input_enabled

func _update_neutral_crouch() -> void:
	var crouch_pressed := _crouch_input_pressed()
	var can_crouch := can_enter_neutral_crouch()
	if crouch_pressed and not can_crouch and not crouching and not _crouch_reject_latched:
		_crouch_reject_latched = true
		defensive_input_rejected.emit("crouch", "player_action_locked")
	if not crouch_pressed or can_crouch:
		_crouch_reject_latched = false
	var wants_crouch := crouch_pressed and can_crouch
	set_combat_crouch(wants_crouch)

func _crouch_input_pressed() -> bool:
	return Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or Input.is_action_pressed("ui_down")

func _cache_hurtbox_shape() -> void:
	if hurtbox_shape == null:
		return
	var rect_shape := hurtbox_shape.shape as RectangleShape2D
	if rect_shape == null:
		return
	_base_hurtbox_shape_size = rect_shape.size
	_base_hurtbox_shape_position = hurtbox_shape.position

func _apply_crouch_hurtbox(enabled: bool) -> void:
	if hurtbox_shape == null:
		return
	var rect_shape := hurtbox_shape.shape as RectangleShape2D
	if rect_shape == null:
		return
	if enabled:
		rect_shape.size = Vector2(crouch_hurtbox_width, crouch_hurtbox_height)
		hurtbox_shape.position = Vector2(_base_hurtbox_shape_position.x, -crouch_hurtbox_height * 0.5)
	else:
		rect_shape.size = _base_hurtbox_shape_size
		hurtbox_shape.position = _base_hurtbox_shape_position

func _update_stance_recovery_total() -> void:
	stance_recovery_frames_remaining = stance_break_stun_frames_remaining + stance_protection_frames_remaining

func _finish_stance_recovery() -> void:
	stance = 0
	stance_changed.emit(stance, max_stance)
	stance_state = StanceState.NORMAL
	stance_break_stun_frames_remaining = 0
	stance_protection_frames_remaining = 0
	stance_recovery_frames_remaining = 0
	if not crouching:
		_set_state("READY")

func _flash(color: Color, label: String) -> void:
	body.color = color
	_set_state(label)
	var tween := create_tween()
	tween.tween_property(body, "color", Color(0.25, 0.75, 1.0), 0.18)

func _set_state(text: String) -> void:
	state_label.text = text
