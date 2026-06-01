class_name Enemy
extends Node2D

signal hp_changed(current_hp: int, max_hp: int)
signal stance_changed(current_stance: int, max_stance: int)
signal attack_telegraphed(attack_type: String)
signal attack_resolved(attack_type: String)
signal break_started
signal break_ended

const CombatAnimationDriver := preload("res://scripts/animation/combat_animation_driver.gd")
const EnemyMoveData := preload("res://scripts/enemy/enemy_move_data.gd")
const EnemyStanceConfig := preload("res://scripts/enemy/enemy_stance_config.gd")

enum State { IDLE, TELEGRAPH, ATTACK, BREAK }
enum StanceState { NORMAL, BROKEN_HITSTUN, BROKEN_BLOCKSTUN, RECOVERING_PROTECTED }
enum DecisionState { NEUTRAL, BLOCKING, PUNISHING, PRESSURING, MASHING, RECOVERING, STUNNED, STANCE_BROKEN, DEFENSIVE_REACTION }

const STANCE_BREAK_HITSTUN_FRAMES := EnemyStanceConfig.BREAK_HITSTUN_FRAMES
const STANCE_BREAK_BLOCK_RECOVERY_FRAMES := EnemyStanceConfig.BREAK_BLOCK_RECOVERY_FRAMES
const STANCE_PROTECTION_RECOVERY_FRAMES := EnemyStanceConfig.PROTECTION_RECOVERY_FRAMES
const ATTACKS := EnemyMoveData.ATTACKS

@export var max_hp := 120
@export var max_stance := EnemyStanceConfig.MAX_STANCE
@export var hurtbox_width := 50.0
@export var hurtbox_height := 90.0
@export var punish_startup := 5
@export var punish_range := 120.0
@export var punish_damage := 18
@export var punish_stance_damage := 12
@export_enum("NORMAL", "ELITE", "BOSS") var intent_tier := "NORMAL"

var hp := max_hp
var stance := 0
var state := State.IDLE
var stance_state := StanceState.NORMAL
var stance_recovery_frames_remaining := 0
var stance_break_stun_frames_remaining := 0
var stance_protection_frames_remaining := 0
var current_attack := ""
var current_animation_action := "None"
var current_animation_phase := "DONE"
var current_animation_progress := 0.0
var current_animation_hit_level := ""
var current_animation_hitbox_active := false
var decision_state := DecisionState.NEUTRAL
var last_decision_reason := "Ready."
var last_action_score := 0.0
var boss_phase_id := "phase_1"

@onready var body: ColorRect = $Body
@onready var rig: Node = $Rig
@onready var telegraph_label: Label = $TelegraphLabel
@onready var stance_break_bar: ProgressBar = $StanceBreakBar

func _ready() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)
	stance_changed.emit(stance, max_stance)
	telegraph_label.add_theme_font_size_override("font_size", 20)
	stance_break_bar.visible = false
	_set_idle()

func can_act() -> bool:
	return state == State.IDLE and stance_state == StanceState.NORMAL

func get_attacks() -> Dictionary:
	return ATTACKS

func start_attack(attack_id := "") -> void:
	if not can_act():
		return
	state = State.TELEGRAPH
	var attacks := get_attacks()
	current_attack = attack_id if attacks.has(attack_id) else _fallback_attack_id()
	telegraph_label.text = current_attack
	telegraph_label.modulate = _attack_color(current_attack)
	body.color = _attack_color(current_attack)
	attack_telegraphed.emit(current_attack)

func resolve_attack() -> Dictionary:
	if state != State.TELEGRAPH:
		return {}
	state = State.ATTACK
	body.color = Color.CRIMSON
	attack_resolved.emit(current_attack)
	var attacks := get_attacks()
	if not attacks.has(current_attack):
		return {}
	var data := attacks[current_attack] as Dictionary
	var hit_level := String(data.get("hit_level", data.get("type", current_attack)))
	return {
		"type": String(data.get("type", hit_level)),
		"id": data.get("id", current_attack),
		"name": data.get("name", current_attack),
		"damage": data["damage"],
		"stance_damage": data.get("stance_damage", 0),
		"startup": data.get("startup", data["startup_frame"]),
		"startup_frame": data["startup_frame"],
		"active": data.get("active", 0),
		"recovery": data.get("recovery", 0),
		"range": data["range"],
		"range_min": data.get("range_min", 0.0),
		"range_max": data.get("range_max", data["range"]),
		"counter_damage": data["counter_damage"],
		"hit_level": hit_level,
		"on_hit_adv": data.get("on_hit_adv", 0),
		"on_block_adv": data.get("on_block_adv", 0),
		"hitbox_width": data["hitbox_width"],
		"hitbox_height": data["hitbox_height"],
		"hitbox_offset_x": data.get("hitbox_offset_x", float(data["hitbox_width"]) * 0.5),
		"hitbox_offset_y": data["hitbox_offset_y"],
		"animation_key": data.get("animation_key", data.get("id", current_attack)),
		"tags": data.get("tags", []),
		"ai_use_case": data.get("ai_use_case", [])
	}

func finish_attack() -> void:
	if state == State.ATTACK:
		_set_idle()

func clear_intent() -> void:
	if state == State.TELEGRAPH or state == State.ATTACK or state == State.IDLE:
		_set_idle()

func perform_punish_combo() -> int:
	state = State.ATTACK
	current_attack = "PUNISH"
	telegraph_label.text = "PUNISH"
	telegraph_label.modulate = Color.WHITE
	body.color = Color.CRIMSON
	await get_tree().create_timer(0.25, true, false, true).timeout
	_set_idle()
	return punish_damage

func take_hit(damage: int, stance_damage: int) -> void:
	if stance_state == StanceState.BROKEN_HITSTUN:
		damage = int(ceil(damage * 1.5))

	hp = maxi(0, hp - damage)
	hp_changed.emit(hp, max_hp)
	add_stance_damage(stance_damage)
	CombatAnimationDriver.drive_rig(rig, "hitstun", "IMPACT", 1.0, "", false)
	CombatAnimationDriver.play_impact(rig)
	_flash_hit()

func add_stance_damage(amount: int) -> void:
	if _stance_damage_is_protected():
		if amount > 0:
			print("Stance protected: ignored %d stance damage" % amount)
		return
	if amount <= 0:
		return
	stance = mini(max_stance, stance + amount)
	stance_changed.emit(stance, max_stance)
	if stance >= max_stance:
		enter_break(false)

func add_block_stance_damage(amount: int) -> void:
	if _stance_damage_is_protected():
		if amount > 0:
			print("Stance protected: ignored %d stance damage" % amount)
		return
	if amount <= 0:
		return
	stance = mini(max_stance, stance + amount)
	stance_changed.emit(stance, max_stance)
	if stance >= max_stance:
		enter_break(true)

func enter_break(from_block := false) -> void:
	if stance_state != StanceState.NORMAL:
		return
	state = State.BREAK
	stance_state = StanceState.BROKEN_BLOCKSTUN if from_block else StanceState.BROKEN_HITSTUN
	current_attack = ""
	telegraph_label.text = "BREAK"
	telegraph_label.modulate = Color.ORANGE
	body.color = Color.ORANGE
	CombatAnimationDriver.drive_rig(rig, "stance_break", "IMPACT", 1.0, "", false)
	var break_frames := STANCE_BREAK_BLOCK_RECOVERY_FRAMES if from_block else STANCE_BREAK_HITSTUN_FRAMES
	stance_break_stun_frames_remaining = break_frames
	stance_protection_frames_remaining = STANCE_PROTECTION_RECOVERY_FRAMES
	_update_stance_recovery_total()
	break_started.emit()

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
			telegraph_label.text = "PROTECTED"

	if remaining_frames > 0 and stance_protection_frames_remaining > 0:
		var spent_protection := mini(stance_protection_frames_remaining, remaining_frames)
		stance_protection_frames_remaining -= spent_protection

	_update_stance_recovery_total()
	_update_stance_break_bar()
	if stance_break_stun_frames_remaining <= 0 and stance_protection_frames_remaining <= 0:
		_finish_stance_recovery()

func _finish_stance_recovery() -> void:
	stance = 0
	stance_changed.emit(stance, max_stance)
	stance_state = StanceState.NORMAL
	stance_break_stun_frames_remaining = 0
	stance_protection_frames_remaining = 0
	stance_recovery_frames_remaining = 0
	_update_stance_break_bar()
	break_ended.emit()
	_set_idle()

func set_decision_state(new_state: int, reason := "", score := 0.0) -> void:
	decision_state = new_state
	last_decision_reason = reason
	last_action_score = score

func get_decision_state_name() -> String:
	match decision_state:
		DecisionState.NEUTRAL:
			return "NEUTRAL"
		DecisionState.BLOCKING:
			return "BLOCKING"
		DecisionState.PUNISHING:
			return "PUNISHING"
		DecisionState.PRESSURING:
			return "PRESSURING"
		DecisionState.MASHING:
			return "MASHING"
		DecisionState.RECOVERING:
			return "RECOVERING"
		DecisionState.STUNNED:
			return "STUNNED"
		DecisionState.STANCE_BROKEN:
			return "STANCE_BROKEN"
		DecisionState.DEFENSIVE_REACTION:
			return "DEFENSIVE_REACTION"
		_:
			return "UNKNOWN"

func get_intent_profile_overrides() -> Dictionary:
	return {
		"tier": intent_tier,
		"phase_id": boss_phase_id
	}

func _update_stance_recovery_total() -> void:
	stance_recovery_frames_remaining = stance_break_stun_frames_remaining + stance_protection_frames_remaining
	_update_stance_break_bar()

func _stance_damage_is_protected() -> bool:
	return stance_state == StanceState.BROKEN_HITSTUN or stance_state == StanceState.BROKEN_BLOCKSTUN or stance_state == StanceState.RECOVERING_PROTECTED

func is_stance_protected() -> bool:
	return _stance_damage_is_protected()

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

func _set_idle() -> void:
	if stance_state != StanceState.NORMAL:
		return
	state = State.IDLE
	decision_state = DecisionState.NEUTRAL
	current_attack = ""
	telegraph_label.text = "READY"
	telegraph_label.modulate = Color.WHITE
	body.color = Color(1.0, 0.28, 0.22)
	body.scale = Vector2.ONE
	stance_break_bar.visible = false
	CombatAnimationDriver.clear(rig)

func show_timeline_phase(action_name: String, phase_name: String, phase_progress := 0.0, hit_level := "", hitbox_active := false) -> void:
	current_animation_action = action_name
	current_animation_phase = phase_name
	current_animation_progress = phase_progress
	current_animation_hit_level = current_attack if current_attack != "" else hit_level
	current_animation_hitbox_active = hitbox_active
	CombatAnimationDriver.drive_rig(rig, action_name, phase_name, phase_progress, current_attack if current_attack != "" else hit_level, hitbox_active)
	match phase_name:
		"STARTUP":
			body.color = _attack_color(current_attack).lerp(Color.WHITE, 0.25)
			body.scale = Vector2(0.94, 1.06)
		"ACTIVE", "IMPACT":
			body.color = Color.CRIMSON
			body.scale = Vector2(1.08, 0.96)
		"RECOVERY":
			body.color = Color(1.0, 0.46, 0.34)
			body.scale = Vector2(0.98, 1.0)
		_:
			body.scale = Vector2.ONE
	var marker_text := current_attack if current_attack != "" else action_name.to_upper()
	telegraph_label.text = "%s %s" % [marker_text, phase_name]
	telegraph_label.modulate = _attack_color(current_attack if current_attack != "" else hit_level)

func clear_timeline_visual() -> void:
	if stance_state == StanceState.NORMAL:
		body.color = Color(1.0, 0.28, 0.22)
		body.scale = Vector2.ONE
		current_animation_action = "None"
		current_animation_phase = "DONE"
		current_animation_progress = 0.0
		current_animation_hit_level = ""
		current_animation_hitbox_active = false
		CombatAnimationDriver.clear(rig)

func get_animation_debug() -> Dictionary:
	return {
		"animation_key": rig.pose_key if rig != null and "pose_key" in rig else "unknown",
		"pose_key": rig.pose_key if rig != null and "pose_key" in rig else "unknown",
		"action_name": current_animation_action,
		"hit_level": current_animation_hit_level,
		"phase": current_animation_phase,
		"phase_progress": current_animation_progress,
		"phase_frames_remaining": null,
		"active_frame_window": "unknown",
		"hitbox_active": current_animation_hitbox_active,
		"current_pose_name": rig.pose_key if rig != null and "pose_key" in rig else "unknown",
		"movement_phase": "unknown",
		"movement_direction": "unknown",
		"rig_scale": rig.scale if rig != null else Vector2.ONE,
		"facing": "right" if rig == null or float(rig.facing) >= 0.0 else "left"
	}

func _update_stance_break_bar() -> void:
	if stance_break_bar == null:
		return
	stance_break_bar.visible = stance_state != StanceState.NORMAL
	stance_break_bar.max_value = STANCE_BREAK_HITSTUN_FRAMES + STANCE_PROTECTION_RECOVERY_FRAMES
	stance_break_bar.value = stance_recovery_frames_remaining

func _fallback_attack_id() -> String:
	var attacks := get_attacks()
	if attacks.has("MID"):
		return "MID"
	if attacks.has("light_punch"):
		return "light_punch"
	for action_id in attacks.keys():
		return String(action_id)
	return ""

func _flash_hit() -> void:
	var tween := create_tween()
	tween.tween_property(body, "color", Color.WHITE, 0.05)
	tween.tween_property(body, "color", Color.ORANGE if state == State.BREAK else Color(1.0, 0.28, 0.22), 0.15)

func _attack_color(attack_type: String) -> Color:
	match attack_type:
		"HIGH":
			return Color.YELLOW
		"MID":
			return Color.MAGENTA
		"LOW":
			return Color.LIME_GREEN
		_:
			return Color.WHITE
