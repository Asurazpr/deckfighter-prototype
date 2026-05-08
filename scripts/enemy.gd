class_name Enemy
extends Node2D

signal hp_changed(current_hp: int, max_hp: int)
signal stance_changed(current_stance: int, max_stance: int)
signal attack_telegraphed(attack_type: String)
signal attack_resolved(attack_type: String)
signal break_started
signal break_ended

enum State { IDLE, TELEGRAPH, ATTACK, BREAK }

const ATTACKS := {
	"HIGH": {"damage": 14, "answer": "block", "alt_answer": "backstep"},
	"MID": {"damage": 12, "answer": "block", "alt_answer": ""},
	"LOW": {"damage": 10, "answer": "crouch_block", "alt_answer": "jump"}
}

@export var max_hp := 120
@export var max_stance := 100

var hp := max_hp
var stance := 0
var state := State.IDLE
var current_attack := ""

@onready var body: ColorRect = $Body
@onready var telegraph_label: Label = $TelegraphLabel

func _ready() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)
	stance_changed.emit(stance, max_stance)
	_set_idle()

func can_act() -> bool:
	return state == State.IDLE

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
		"answer": data["answer"],
		"alt_answer": data["alt_answer"]
	}

func finish_attack() -> void:
	if state == State.ATTACK:
		_set_idle()

func take_hit(damage: int, stance_damage: int) -> void:
	if state == State.BREAK:
		damage = int(ceil(damage * 1.5))

	hp = maxi(0, hp - damage)
	hp_changed.emit(hp, max_hp)
	add_stance_damage(stance_damage)
	_flash_hit()

func add_stance_damage(amount: int) -> void:
	if state == State.BREAK or amount <= 0:
		return
	stance = mini(max_stance, stance + amount)
	stance_changed.emit(stance, max_stance)
	if stance >= max_stance:
		enter_break()

func enter_break() -> void:
	state = State.BREAK
	current_attack = ""
	telegraph_label.text = "BREAK"
	body.color = Color.ORANGE
	break_started.emit()
	await get_tree().create_timer(3.0, true, false, true).timeout
	stance = 0
	stance_changed.emit(stance, max_stance)
	break_ended.emit()
	_set_idle()

func _set_idle() -> void:
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
