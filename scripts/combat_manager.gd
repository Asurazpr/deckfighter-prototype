class_name CombatManager
extends Node

signal frame_advantage_changed(value: int)
signal log_message(message: String)

const TELEGRAPH_TIME := 1.0
const ATTACK_RECOVERY := 0.35
const PLAYER_CHOICE_TIME_SCALE := 0.2

@export var starting_frame_advantage := 0

var frame_advantage := 0
var last_defense := ""
var attack_in_progress := false
var combat_over := false

@onready var player = $"../Player"
@onready var enemy = $"../Enemy"
@onready var deck_manager = $"../DeckManager"

func _ready() -> void:
	frame_advantage = starting_frame_advantage
	player.defense_performed.connect(_on_player_defense)
	enemy.break_started.connect(_on_enemy_break_started)
	enemy.break_ended.connect(_on_enemy_break_ended)
	call_deferred("_begin_combat")

func _begin_combat() -> void:
	deck_manager.start_combat()
	frame_advantage_changed.emit(frame_advantage)
	log_message.emit("Duel start. Defend the first telegraph.")
	_schedule_enemy_if_needed()

func _process(_delta: float) -> void:
	if combat_over:
		return

	if player.hp <= 0:
		_end_combat("Player defeated.")
	elif enemy.hp <= 0:
		_end_combat("Enemy defeated.")

func can_play_cards() -> bool:
	return frame_advantage > 0 and not attack_in_progress and not combat_over

func is_hand_card_playable(index: int) -> bool:
	return can_play_cards() and deck_manager.is_card_playable(index)

func play_card(index: int) -> void:
	if not can_play_cards():
		_change_frame_advantage(-1)
		log_message.emit("Bad timing. Dropped tempo.")
		return
	if not deck_manager.is_card_playable(index):
		_change_frame_advantage(-1)
		log_message.emit("Invalid follow-up. Combo route dropped.")
		_check_combo_route_drying_out()
		return

	var card: Resource = deck_manager.play_card(index)
	if card == null:
		return

	log_message.emit("Card played: %s." % card.display_name)
	player.perform_card_action(card)
	enemy.take_hit(card.damage, card.stance_damage)
	if card.stance_damage > 0:
		log_message.emit("Stance damage dealt: %d." % card.stance_damage)
	_change_frame_advantage(card.frame_gain - card.frame_cost)
	log_message.emit("%s hits for %d and deals %d stance." % [card.display_name, card.damage, card.stance_damage])
	_check_combo_route_drying_out()
	_update_time_scale()
	_schedule_enemy_if_needed()

func _on_player_defense(defense_type: String) -> void:
	last_defense = defense_type

func _run_enemy_attack() -> void:
	if combat_over or frame_advantage > 0 or attack_in_progress or not enemy.can_act():
		return

	attack_in_progress = true
	last_defense = ""
	deck_manager.reset_combo_route()
	enemy.start_attack()
	log_message.emit("Enemy started %s attack." % enemy.current_attack)

	await get_tree().create_timer(TELEGRAPH_TIME).timeout
	if combat_over:
		return

	var result: Dictionary = enemy.resolve_attack()
	var defended := _defense_answers_attack(last_defense, result)
	if defended:
		var perfect := last_defense != "" and randf() < 0.35
		deck_manager.reset_combo_route()
		_change_frame_advantage(2 if perfect else 1)
		if perfect:
			enemy.add_stance_damage(12)
			log_message.emit("Player answered correctly: perfect %s against %s." % [last_defense, result["type"]])
			log_message.emit("Stance damage dealt: 12.")
		else:
			log_message.emit("Player answered correctly: %s defended with %s." % [result["type"], last_defense])
	else:
		player.take_damage(result["damage"])
		_change_frame_advantage(-1)
		log_message.emit("Player answered incorrectly to %s." % result["type"])
		log_message.emit("%s connects for %d." % [result["type"], result["damage"]])

	await get_tree().create_timer(ATTACK_RECOVERY).timeout
	enemy.finish_attack()
	attack_in_progress = false
	_update_time_scale()
	_schedule_enemy_if_needed()

func _defense_answers_attack(defense_type: String, attack_data: Dictionary) -> bool:
	if defense_type == "":
		return false
	return defense_type == attack_data["answer"] or (attack_data["alt_answer"] != "" and defense_type == attack_data["alt_answer"])

func _change_frame_advantage(delta: int) -> void:
	var previous := frame_advantage
	frame_advantage = clampi(frame_advantage + delta, -3, 6)
	if frame_advantage < 0:
		frame_advantage = 0
	if frame_advantage == 0:
		deck_manager.reset_combo_route()
	frame_advantage_changed.emit(frame_advantage)
	if frame_advantage > previous:
		log_message.emit("Frame advantage gained: %d -> %d." % [previous, frame_advantage])
	elif frame_advantage < previous:
		log_message.emit("Frame advantage lost: %d -> %d." % [previous, frame_advantage])
		if frame_advantage == 0:
			log_message.emit("Combo dropped / reset to neutral.")
	_update_time_scale()

func _check_combo_route_drying_out() -> void:
	if can_play_cards() and not deck_manager.has_valid_playable_card():
		log_message.emit("Combo route drying out.")
		_change_frame_advantage(-frame_advantage)

func _on_enemy_break_started() -> void:
	log_message.emit("Enemy stance broken.")

func _on_enemy_break_ended() -> void:
	log_message.emit("Enemy recovered from stance break.")

func _schedule_enemy_if_needed() -> void:
	if combat_over or attack_in_progress or frame_advantage > 0:
		return
	await get_tree().create_timer(0.45).timeout
	_run_enemy_attack()

func _update_time_scale() -> void:
	if combat_over:
		Engine.time_scale = 1.0
	else:
		Engine.time_scale = PLAYER_CHOICE_TIME_SCALE if can_play_cards() else 1.0

func _end_combat(message: String) -> void:
	combat_over = true
	Engine.time_scale = 1.0
	log_message.emit(message)

func _exit_tree() -> void:
	Engine.time_scale = 1.0
