class_name Enemy
extends Node2D

signal hp_changed(current_hp: int, max_hp: int)
signal stance_changed(current_stance: int, max_stance: int)
signal attack_telegraphed(attack_type: String)
signal attack_resolved(attack_type: String)
signal break_started
signal break_ended

enum State { IDLE, TELEGRAPH, ATTACK, BREAK }
enum StanceState { NORMAL, BROKEN_HITSTUN, BROKEN_BLOCKSTUN, RECOVERING_PROTECTED }

const STANCE_BREAK_HITSTUN_FRAMES := 45
const STANCE_BREAK_BLOCK_RECOVERY_FRAMES := 30
const STANCE_PROTECTION_RECOVERY_FRAMES := 30

const ATTACKS := {
	"HIGH": {"damage": 14, "startup_frame": 6, "range": 80.0, "counter_damage": 18, "hitbox_width": 85.0, "hitbox_height": 45.0, "hitbox_offset_y": -65.0},
	"MID": {"damage": 12, "startup_frame": 9, "range": 90.0, "counter_damage": 16, "hitbox_width": 95.0, "hitbox_height": 55.0, "hitbox_offset_y": -40.0},
	"LOW": {"damage": 10, "startup_frame": 10, "range": 75.0, "counter_damage": 14, "hitbox_width": 85.0, "hitbox_height": 35.0, "hitbox_offset_y": -15.0},
	"OVERHEAD": {"damage": 16, "startup_frame": 15, "range": 85.0, "counter_damage": 22, "hitbox_width": 100.0, "hitbox_height": 75.0, "hitbox_offset_y": -70.0}
}

@export var max_hp := 120
@export var max_stance := 100
@export var hurtbox_width := 50.0
@export var hurtbox_height := 90.0
@export var punish_startup := 5
@export var punish_range := 120.0
@export var punish_damage := 18

var hp := max_hp
var stance := 0
var state := State.IDLE
var stance_state := StanceState.NORMAL
var stance_recovery_frames_remaining := 0
var stance_break_stun_frames_remaining := 0
var stance_protection_frames_remaining := 0
var current_attack := ""

@onready var body: ColorRect = $Body
@onready var telegraph_label: Label = $TelegraphLabel

func _ready() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)
	stance_changed.emit(stance, max_stance)
	telegraph_label.add_theme_font_size_override("font_size", 42)
	_set_idle()

func can_act() -> bool:
	return state == State.IDLE and stance_state == StanceState.NORMAL

func start_attack() -> void:
	if not can_act():
		return
	state = State.TELEGRAPH
	var keys := ATTACKS.keys()
	current_attack = keys.pick_random()
	telegraph_label.text = current_attack
	body.color = _attack_color(current_attack)
	attack_telegraphed.emit(current_attack)

func resolve_attack() -> Dictionary:
	if state != State.TELEGRAPH:
		return {}
	state = State.ATTACK
	body.color = Color.CRIMSON
	attack_resolved.emit(current_attack)
	var data := ATTACKS[current_attack] as Dictionary
	return {
		"type": current_attack,
		"damage": data["damage"],
		"startup_frame": data["startup_frame"],
		"range": data["range"],
		"counter_damage": data["counter_damage"],
		"hitbox_width": data["hitbox_width"],
		"hitbox_height": data["hitbox_height"],
		"hitbox_offset_y": data["hitbox_offset_y"]
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
	body.color = Color.ORANGE
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
	if stance_break_stun_frames_remaining <= 0 and stance_protection_frames_remaining <= 0:
		_finish_stance_recovery()

func _finish_stance_recovery() -> void:
	stance = 0
	stance_changed.emit(stance, max_stance)
	stance_state = StanceState.NORMAL
	stance_break_stun_frames_remaining = 0
	stance_protection_frames_remaining = 0
	stance_recovery_frames_remaining = 0
	break_ended.emit()
	_set_idle()

func _update_stance_recovery_total() -> void:
	stance_recovery_frames_remaining = stance_break_stun_frames_remaining + stance_protection_frames_remaining

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
	current_attack = ""
	telegraph_label.text = "READY"
	body.color = Color(1.0, 0.28, 0.22)

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
