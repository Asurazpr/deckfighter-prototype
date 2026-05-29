class_name RenkaPlayer
extends Player

signal action_animation_finished(animation_name: String, action_state_name: String)

const SpriteFramesLoader := preload("res://scripts/animation/png_sequence_sprite_frames_loader.gd")
const TexturePackerSpriteFramesLoader := preload("res://scripts/animation/texture_packer_sprite_frames_loader.gd")
const Manifest := preload("res://scripts/characters/renka_animation_manifest.gd")

enum RenkaState { IDLE, RUNNING, ATTACKING, BLOCKING, HITSTUN }
enum ActionState { NEUTRAL, ATTACK_STARTUP, ATTACK_ACTIVE, ATTACK_RECOVERY, BLOCK_START, BLOCK_HOLD, BLOCK_RECOVERY, HITSTUN }

const HITBOX_PROFILES := {
	"light_punch": {"position": Vector2(58.0, -82.0), "size": Vector2(84.0, 42.0)},
	"heavy_punch": {"position": Vector2(68.0, -82.0), "size": Vector2(112.0, 54.0)},
	"light_kick": {"position": Vector2(62.0, -38.0), "size": Vector2(96.0, 38.0)},
	"heavy_kick": {"position": Vector2(76.0, -42.0), "size": Vector2(124.0, 48.0)},
	"uppercut": {"position": Vector2(48.0, -88.0), "size": Vector2(78.0, 108.0)}
}

@export var sprite_scale := Vector2(0.22, 0.22)
@export var sprite_pivot := Vector2(902.0, 1052.0)
@export var cancel_window_progress := 0.82
@export var block_hold_frame := 40
@export var use_spritesheets := Manifest.USE_SPRITESHEETS
@export var default_facing_sign := -1.0

var renka_state := RenkaState.IDLE
var action_state := ActionState.NEUTRAL
var _current_renka_animation := ""
var _animation_backend := "png_sequence"
var _facing_sign := -1.0
var is_action_locked := false
var _cancel_window_open := false
var followup_window_active := false
var _active_card: Resource
var _hit_confirm_token := 0
var _block_release_requested := false
var _visual_return_pending := false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var hurtbox: Area2D = $Hurtbox
@onready var attack_hitbox_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D

func _ready() -> void:
	super._ready()
	if body != null:
		body.visible = false
	if rig != null:
		rig.visible = false
	_configure_sprite()
	_enter_renka_state(RenkaState.IDLE, "idle")

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_block_clip_phase()
	if renka_state == RenkaState.ATTACKING or renka_state == RenkaState.BLOCKING or renka_state == RenkaState.HITSTUN:
		return
	_update_locomotion_animation()

func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	hp = maxi(0, hp - amount)
	hp_changed.emit(hp, max_hp)
	force_finish_action()
	action_state = ActionState.HITSTUN
	_lock_action()
	_enter_renka_state(RenkaState.HITSTUN, "light_hitstun")
	_flash(Color.INDIAN_RED, "HIT")

func perform_card_action(card: Resource) -> void:
	_active_card = card
	_hit_confirm_token += 1
	_cancel_window_open = false
	followup_window_active = false
	action_state = ActionState.ATTACK_STARTUP
	_lock_action()
	var animation_name := _animation_for_card(card)
	print("Renka action requested: %s -> playing animation: %s" % [String(card.id), animation_name])
	_enter_renka_state(RenkaState.ATTACKING, animation_name)
	_configure_attack_hitbox(_current_renka_animation)
	_flash(Color.GOLD, card.display_name.to_upper())

func wait_for_action_hit_confirm(card: Resource) -> void:
	var token := _hit_confirm_token
	var hit_frame := int(card.hit_frame) if card != null else 0
	var active_end_frame := int(card.active_end_frame) if card != null else hit_frame
	var fps := _animation_fps(_animation_for_card(card))
	await get_tree().create_timer(maxf(0.01, float(hit_frame) / fps), false, true).timeout
	if token != _hit_confirm_token:
		return
	action_state = ActionState.ATTACK_ACTIVE
	var active_duration := maxf(0.01, float(maxi(1, active_end_frame - hit_frame + 1)) / fps)
	_disable_attack_hitbox_after(token, active_duration)

func _disable_attack_hitbox_after(token: int, duration: float) -> void:
	await get_tree().create_timer(duration, false, true).timeout
	if token == _hit_confirm_token:
		if action_state == ActionState.ATTACK_ACTIVE:
			action_state = ActionState.ATTACK_RECOVERY

func show_timeline_phase(action_name: String, phase_name: String, phase_progress := 0.0, hit_level := "", hitbox_active := false) -> void:
	current_animation_action = action_name
	current_animation_phase = phase_name
	current_animation_progress = phase_progress
	current_animation_hit_level = hit_level
	current_animation_hitbox_active = hitbox_active
	_set_state("%s\n%s" % [action_name.to_upper(), phase_name])
	var animation_name := _animation_for_timeline(action_name, hit_level)
	var state := _state_for_timeline(animation_name, phase_name)
	_update_action_state_from_timeline(animation_name, phase_name, phase_progress)
	_enter_renka_state(state, animation_name)

func clear_timeline_visual() -> void:
	var previous_action := current_animation_action
	var attack_visual_continues := action_state == ActionState.ATTACK_STARTUP \
		or action_state == ActionState.ATTACK_ACTIVE \
		or action_state == ActionState.ATTACK_RECOVERY \
		or (_visual_return_pending and renka_state == RenkaState.ATTACKING and animated_sprite != null and animated_sprite.is_playing())
	current_animation_action = "None"
	current_animation_phase = "DONE"
	current_animation_progress = 0.0
	current_animation_hit_level = ""
	current_animation_hitbox_active = false
	_set_attack_hitbox_active(false)
	if attack_visual_continues:
		_set_state("%s\nRECOVERY" % (previous_action.to_upper() if previous_action != "" and previous_action != "None" else "ACTION"))
		return
	if action_state == ActionState.BLOCK_START or action_state == ActionState.BLOCK_HOLD:
		release_block_action()
	else:
		_finish_action_to_neutral()
	if action_state == ActionState.NEUTRAL:
		_update_locomotion_animation()

func clear_stale_defense_action() -> void:
	if action_state != ActionState.BLOCK_START and action_state != ActionState.BLOCK_HOLD and action_state != ActionState.BLOCK_RECOVERY:
		return
	force_finish_action()

func get_animation_debug() -> Dictionary:
	var base := super.get_animation_debug()
	base["animation_key"] = _current_renka_animation
	base["pose_key"] = _current_renka_animation
	base["current_pose_name"] = _current_renka_animation
	base["rig_scale"] = animated_sprite.scale if animated_sprite != null else Vector2.ONE
	base["facing"] = "right" if _facing_sign < 0.0 else "left"
	base["renka_state"] = _state_name()
	base["action_state"] = _action_state_name()
	base["is_action_locked"] = is_action_locked
	base["cancel_window_open"] = _cancel_window_open
	base["followup_window_active"] = followup_window_active
	base["visual_return_pending"] = _visual_return_pending
	return base

func can_start_card_action() -> bool:
	return action_state == ActionState.NEUTRAL or _cancel_window_open or followup_window_active

func card_action_rejection_reason() -> String:
	return "state=%s current_action=%s action_locked=%s recovering=%s followup_window_active=%s cancel_window_active=%s animation=%s frame=%d" % [
		_action_state_name(),
		_current_renka_animation,
		str(is_action_locked),
		str(action_state == ActionState.ATTACK_RECOVERY or action_state == ActionState.BLOCK_RECOVERY),
		str(followup_window_active),
		str(_cancel_window_open),
		_current_renka_animation,
		animated_sprite.frame if animated_sprite != null else -1
	]

func open_followup_window() -> void:
	if action_state == ActionState.HITSTUN or action_state == ActionState.BLOCK_START or action_state == ActionState.BLOCK_HOLD or action_state == ActionState.BLOCK_RECOVERY:
		return
	followup_window_active = true
	_unlock_action()

func finish_action_from_combat_manager(reason := "") -> void:
	_active_card = null
	_hit_confirm_token += 1
	_cancel_window_open = false
	followup_window_active = false
	_block_release_requested = false
	_set_attack_hitbox_active(false)
	if renka_state == RenkaState.ATTACKING and animated_sprite != null and animated_sprite.is_playing():
		action_state = ActionState.NEUTRAL
		current_animation_action = "None"
		current_animation_phase = "DONE"
		current_animation_progress = 0.0
		current_animation_hit_level = ""
		current_animation_hitbox_active = false
		_unlock_action()
		_visual_return_pending = true
		_set_state("READY")
		return
	_finish_action_to_neutral()

func release_block_action() -> void:
	if action_state != ActionState.BLOCK_START and action_state != ActionState.BLOCK_HOLD:
		return
	_block_release_requested = true
	action_state = ActionState.BLOCK_RECOVERY
	_lock_action()
	if animated_sprite != null and animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation("block"):
		animated_sprite.animation = "block"
		animated_sprite.frame = mini(block_hold_frame + 1, animated_sprite.sprite_frames.get_frame_count("block") - 1)
		animated_sprite.play("block")

func force_finish_action() -> void:
	_hit_confirm_token += 1
	_active_card = null
	_cancel_window_open = false
	followup_window_active = false
	_block_release_requested = false
	_visual_return_pending = false
	_set_attack_hitbox_active(false)
	_finish_action_to_neutral()

func _configure_sprite() -> void:
	_facing_sign = -1.0 if default_facing_sign < 0.0 else 1.0
	var sprite_frames
	var backend := "png_sequence"
	if use_spritesheets:
		sprite_frames = TexturePackerSpriteFramesLoader.build_sprite_frames(
			Manifest.SPRITESHEET_ROOT,
			Manifest.ANIMATIONS,
			Manifest.FPS,
			Manifest.FPS_OVERRIDES,
			Manifest.LOOP_OVERRIDES
		)
		if sprite_frames != null:
			backend = "spritesheet"
	if sprite_frames == null:
		sprite_frames = SpriteFramesLoader.build_sprite_frames(
			Manifest.RENDERS_ROOT,
			Manifest.ANIMATIONS,
			Manifest.FPS,
			Manifest.FPS_OVERRIDES,
			Manifest.LOOP_OVERRIDES
		)
		backend = "png_sequence"
	print("Renka animation backend loaded: %s" % backend)
	_animation_backend = backend
	animated_sprite.sprite_frames = sprite_frames
	animated_sprite.centered = false
	animated_sprite.offset = -sprite_pivot
	_apply_animation_visual_scale("idle")
	animated_sprite.animation_finished.connect(_on_animation_finished)
	_set_attack_hitbox_active(false)

func _update_locomotion_animation() -> void:
	if crouching:
		_set_state("CROUCH")
		_enter_renka_state(RenkaState.IDLE, "idle")
		return
	if input_enabled and free_movement_enabled and absf(velocity.x) > 4.0:
		var moving_forward := signf(velocity.x) >= 0.0
		_enter_renka_state(RenkaState.RUNNING, "run_forward" if moving_forward else "run_backward")
	else:
		_enter_renka_state(RenkaState.IDLE, "idle")

func can_enter_neutral_crouch() -> bool:
	return input_enabled \
		and action_state == ActionState.NEUTRAL \
		and not _visual_return_pending \
		and renka_state != RenkaState.ATTACKING \
		and renka_state != RenkaState.BLOCKING \
		and renka_state != RenkaState.HITSTUN

func _enter_renka_state(next_state: int, animation_name: String) -> void:
	renka_state = next_state
	if animated_sprite == null or animation_name == "" or not animated_sprite.sprite_frames.has_animation(animation_name):
		return
	if animation_name == "block" and (action_state == ActionState.BLOCK_HOLD or action_state == ActionState.BLOCK_RECOVERY):
		_current_renka_animation = animation_name
		return
	if _current_renka_animation == animation_name and animated_sprite.is_playing():
		return
	_current_renka_animation = animation_name
	_apply_animation_visual_scale(animation_name)
	animated_sprite.play(animation_name)

func _apply_animation_visual_scale(animation_name: String) -> void:
	if animated_sprite == null:
		return
	var visual_scale := 1.0
	if _animation_backend == "spritesheet":
		visual_scale = float(Manifest.SPRITESHEET_VISUAL_SCALES.get(animation_name, 1.0))
	animated_sprite.centered = false
	animated_sprite.offset = -sprite_pivot
	animated_sprite.scale = Vector2(_facing_sign * absf(sprite_scale.x) * visual_scale, absf(sprite_scale.y) * visual_scale)

func set_facing_direction(direction: float) -> void:
	if direction == 0.0:
		return
	_facing_sign = -1.0 if direction > 0.0 else 1.0
	_apply_animation_visual_scale(_current_renka_animation if _current_renka_animation != "" else "idle")

func _animation_for_card(card: Resource) -> String:
	var id := String(card.id)
	var display_name := String(card.display_name).to_lower()
	if id == "uppercut" or id == "launcher" or display_name.find("launcher") != -1 or display_name.find("uppercut") != -1:
		return "uppercut"
	if id == "heavy_punch" or id == "heavy_slash" or id == "guard_break" or display_name.find("heavy punch") != -1 or display_name.find("break") != -1:
		return "heavy_punch"
	if id == "heavy_kick" or id == "ground_smash":
		return "heavy_kick"
	if id == "light_kick" or id == "air_follow" or id == "step_slash" or display_name.find("kick") != -1:
		return "light_kick"
	return "light_punch"

func _animation_for_timeline(action_name: String, hit_level: String) -> String:
	var normalized := action_name.to_lower().replace(" ", "_")
	if normalized.find("block") != -1:
		return "block"
	if normalized.find("hitstun") != -1 or normalized.find("hit") != -1:
		return "light_hitstun"
	if normalized.find("run_forward") != -1 or normalized.find("walk_forward") != -1 or normalized.find("step_forward") != -1:
		return "run_forward"
	if normalized.find("run_backward") != -1 or normalized.find("backstep") != -1 or normalized.find("step_back") != -1:
		return "run_backward"
	if normalized.find("launcher") != -1 or normalized.find("uppercut") != -1:
		return "uppercut"
	if normalized.find("heavy_kick") != -1:
		return "heavy_kick"
	if normalized.find("heavy_punch") != -1 or normalized.find("heavy") != -1 or normalized.find("guard_break") != -1:
		return "heavy_punch"
	if normalized.find("light_kick") != -1 or normalized.find("kick") != -1 or hit_level == "LOW":
		return "light_kick"
	if normalized.find("light_punch") != -1 or normalized.find("jab") != -1 or normalized.find("punch") != -1:
		return "light_punch"
	return _current_renka_animation if _current_renka_animation != "" else "idle"

func _state_for_timeline(animation_name: String, phase_name: String) -> int:
	if animation_name == "block":
		return RenkaState.BLOCKING
	if animation_name.ends_with("hitstun"):
		return RenkaState.HITSTUN
	if animation_name == "run_forward" or animation_name == "run_backward":
		return RenkaState.RUNNING
	if phase_name == "STARTUP" or phase_name == "ACTIVE" or phase_name == "IMPACT" or phase_name == "RECOVERY":
		return RenkaState.ATTACKING
	return RenkaState.IDLE

func _on_animation_finished() -> void:
	if _visual_return_pending:
		_visual_return_pending = false
		_finish_action_to_neutral()
		action_animation_finished.emit(_current_renka_animation, _action_state_name())
		return
	if action_state == ActionState.BLOCK_START:
		_hold_block_frame()
		action_animation_finished.emit(_current_renka_animation, _action_state_name())
		return
	if action_state == ActionState.ATTACK_STARTUP or action_state == ActionState.ATTACK_ACTIVE or action_state == ActionState.ATTACK_RECOVERY or action_state == ActionState.BLOCK_RECOVERY or action_state == ActionState.HITSTUN:
		_set_attack_hitbox_active(false)
		action_animation_finished.emit(_current_renka_animation, _action_state_name())

func _state_name() -> String:
	match renka_state:
		RenkaState.RUNNING:
			return "running"
		RenkaState.ATTACKING:
			return "attacking"
		RenkaState.BLOCKING:
			return "blocking"
		RenkaState.HITSTUN:
			return "hitstun"
		_:
			return "idle"

func _lock_action() -> void:
	is_action_locked = true

func _unlock_action() -> void:
	is_action_locked = false

func _finish_action_to_neutral() -> void:
	action_state = ActionState.NEUTRAL
	_cancel_window_open = false
	followup_window_active = false
	_block_release_requested = false
	_visual_return_pending = false
	current_animation_action = "None"
	current_animation_phase = "DONE"
	current_animation_progress = 0.0
	current_animation_hit_level = ""
	current_animation_hitbox_active = false
	_unlock_action()
	_set_state("READY")
	_enter_renka_state(RenkaState.IDLE, "idle")

func _update_action_state_from_timeline(animation_name: String, phase_name: String, phase_progress: float) -> void:
	if animation_name == "block":
		if phase_name == "STARTUP":
			action_state = ActionState.BLOCK_START
			_cancel_window_open = false
			followup_window_active = false
			_lock_action()
		elif phase_name == "ACTIVE" or phase_name == "IMPACT":
			action_state = ActionState.BLOCK_HOLD
			_cancel_window_open = false
			followup_window_active = false
			_lock_action()
		elif phase_name == "RECOVERY":
			release_block_action()
		return

	if animation_name == "light_hitstun" or animation_name == "heavy_hitstun":
		action_state = ActionState.HITSTUN
		_cancel_window_open = false
		followup_window_active = false
		_lock_action()
		return

	if animation_name == "run_forward" or animation_name == "run_backward":
		return

	if phase_name == "STARTUP":
		action_state = ActionState.ATTACK_STARTUP
		_cancel_window_open = false
		followup_window_active = false
		_lock_action()
	elif phase_name == "ACTIVE" or phase_name == "IMPACT":
		action_state = ActionState.ATTACK_ACTIVE
		_cancel_window_open = false
		_lock_action()
	elif phase_name == "RECOVERY":
		action_state = ActionState.ATTACK_RECOVERY
		_cancel_window_open = phase_progress >= cancel_window_progress
		if _cancel_window_open:
			_unlock_action()
		else:
			_lock_action()

func _update_block_clip_phase() -> void:
	if animated_sprite == null or _current_renka_animation != "block":
		return
	if action_state == ActionState.BLOCK_START and animated_sprite.frame >= block_hold_frame:
		_hold_block_frame()

func _hold_block_frame() -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null or not animated_sprite.sprite_frames.has_animation("block"):
		return
	action_state = ActionState.BLOCK_HOLD
	_lock_action()
	var last_frame := animated_sprite.sprite_frames.get_frame_count("block") - 1
	animated_sprite.frame = clampi(block_hold_frame, 0, last_frame)
	animated_sprite.pause()

func _configure_attack_hitbox(animation_name: String) -> void:
	var profile: Dictionary = HITBOX_PROFILES.get(animation_name, HITBOX_PROFILES["light_punch"])
	attack_hitbox.position = profile["position"]
	var shape := attack_hitbox_shape.shape as RectangleShape2D
	if shape != null:
		shape.size = profile["size"]

func _set_attack_hitbox_active(active: bool) -> void:
	attack_hitbox.visible = active
	if attack_hitbox_shape != null:
		attack_hitbox_shape.disabled = not active

func _animation_fps(animation_name: String) -> float:
	if animated_sprite != null and animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation(animation_name):
		return maxf(1.0, animated_sprite.sprite_frames.get_animation_speed(animation_name))
	return float(Manifest.FPS)

func _action_state_name() -> String:
	match action_state:
		ActionState.ATTACK_STARTUP:
			return "ATTACK_STARTUP"
		ActionState.ATTACK_ACTIVE:
			return "ATTACK_ACTIVE"
		ActionState.ATTACK_RECOVERY:
			return "ATTACK_RECOVERY"
		ActionState.BLOCK_START:
			return "BLOCK_START"
		ActionState.BLOCK_HOLD:
			return "BLOCK_HOLD"
		ActionState.BLOCK_RECOVERY:
			return "BLOCK_RECOVERY"
		ActionState.HITSTUN:
			return "HITSTUN"
		_:
			return "NEUTRAL"
