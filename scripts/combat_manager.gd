class_name CombatManager
extends Node

signal frame_advantage_changed(value: int)
signal log_message(message: String)

const ATTACK_RECOVERY := 0.35
const PLAYER_CHOICE_TIME_SCALE := 0.2
const ENEMY_INTENT_TIME_SCALE := 0.15
const PERFECT_BLOCK_HITSTOP := 0.12

@export var starting_frame_advantage := 0
@export var punish_threshold := 10
@export var enemy_punish_startup := 5
@export var enemy_punish_range := 120.0
@export var stance_break_frame_bonus := 6

var frame_advantage := 0
var last_defense := ""
var attack_in_progress := false
var waiting_for_defense := false
var combat_over := false
var current_enemy_intent := ""
var current_enemy_startup_frame := 0
var repeated_card_uses: Dictionary = {}

@onready var player = $"../Player"
@onready var enemy = $"../Enemy"
@onready var deck_manager = $"../DeckManager"

func _ready() -> void:
	frame_advantage = starting_frame_advantage
	enemy.punish_startup = enemy_punish_startup
	enemy.punish_range = enemy_punish_range
	player.defense_performed.connect(_on_player_defense)
	enemy.break_started.connect(_on_enemy_break_started)
	enemy.break_ended.connect(_on_enemy_break_ended)
	call_deferred("_begin_combat")

func _begin_combat() -> void:
	deck_manager.start_combat()
	frame_advantage_changed.emit(frame_advantage)
	log_message.emit("Duel start. Read the enemy intent.")
	_schedule_enemy_if_needed()

func _process(_delta: float) -> void:
	if combat_over:
		return

	if player.hp <= 0:
		_end_combat("Player defeated.")
	elif enemy.hp <= 0:
		_end_combat("Enemy defeated.")

func get_debug_text() -> String:
	return "Distance: %.0f\nEnemy intent: %s\nEnemy startup frame: %d\nCurrent mode: %s" % [
		_distance_between_fighters(),
		current_enemy_intent if current_enemy_intent != "" else "None",
		current_enemy_startup_frame,
		_current_mode()
	]

func can_play_cards() -> bool:
	return (waiting_for_defense or (frame_advantage > 0 and not attack_in_progress)) and not combat_over

func is_hand_card_playable(index: int) -> bool:
	if waiting_for_defense:
		return deck_manager.is_card_playable(index, _is_enemy_broken()) and _is_interrupt_card_index(index)
	return can_play_cards() and deck_manager.is_card_playable(index, _is_enemy_broken())

func play_card(index: int) -> void:
	if waiting_for_defense:
		_try_interrupt_with_card(index)
		return

	if not can_play_cards():
		_change_frame_advantage(-1)
		log_message.emit("Bad timing. Dropped tempo.")
		return
	if not deck_manager.is_card_playable(index, _is_enemy_broken()):
		_change_frame_advantage(-1)
		log_message.emit("Invalid follow-up. Combo route dropped.")
		_check_combo_route_drying_out()
		return

	var card: Resource = deck_manager.play_card(index, _is_enemy_broken())
	if card == null:
		return

	_resolve_player_card(card)

func _on_player_defense(defense_type: String) -> void:
	last_defense = defense_type
	if waiting_for_defense:
		_resolve_enemy_intent(defense_type)

func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo or not waiting_for_defense:
		return

	var defense_type := _defense_from_key(key_event.keycode)
	if defense_type == "":
		return

	get_viewport().set_input_as_handled()
	_resolve_enemy_intent(defense_type)

func _run_enemy_attack() -> void:
	if combat_over or frame_advantage > 0 or attack_in_progress or not enemy.can_act():
		return

	attack_in_progress = true
	waiting_for_defense = true
	last_defense = ""
	_reset_pressure_sequence()
	enemy.start_attack()
	current_enemy_intent = enemy.current_attack
	current_enemy_startup_frame = int(Enemy.ATTACKS[current_enemy_intent]["startup_frame"])
	log_message.emit("Enemy intent: %s." % enemy.current_attack)
	log_message.emit("Bullet time: choose defense.")
	frame_advantage_changed.emit(frame_advantage)
	_update_time_scale()

func _resolve_enemy_intent(defense_type: String) -> void:
	if combat_over or not waiting_for_defense:
		return

	waiting_for_defense = false
	Engine.time_scale = 1.0
	frame_advantage_changed.emit(frame_advantage)
	log_message.emit("Player chose %s." % _defense_display_name(defense_type))
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		attack_in_progress = false
		_update_time_scale()
		_schedule_enemy_if_needed()
		return

	if defense_type == "backstep":
		_move_player_away_from_enemy(120.0)

	var distance := _distance_between_fighters()
	if distance > float(result["range"]):
		log_message.emit("Enemy attack whiffed due to spacing.")
		_reset_pressure_sequence()
		_change_frame_advantage(1)
	elif defense_type == "perfect_block":
		if result["type"] == "HIGH" or result["type"] == "MID":
			_reset_pressure_sequence()
			_change_frame_advantage(3)
			enemy.add_stance_damage(15)
			log_message.emit("Perfect block success.")
			log_message.emit("Stance damage dealt: 15.")
			player.show_state("PERFECT BLOCK", Color.GOLD)
			await _run_perfect_block_hitstop()
		elif result["type"] == "OVERHEAD":
			_reset_pressure_sequence()
			_change_frame_advantage(1)
			log_message.emit("Normal defense success.")
		else:
			player.take_damage(result["damage"])
			_set_frame_advantage_to_neutral()
			log_message.emit("Perfect block failed.")
	elif _defense_answers_attack(defense_type, result):
		_reset_pressure_sequence()
		_change_frame_advantage(1)
		log_message.emit("Normal defense success.")
	else:
		player.take_damage(result["damage"])
		_set_frame_advantage_to_neutral()
		log_message.emit("Defense failed.")

	await get_tree().create_timer(ATTACK_RECOVERY).timeout
	enemy.finish_attack()
	attack_in_progress = false
	current_enemy_intent = ""
	current_enemy_startup_frame = 0
	_update_time_scale()
	_schedule_enemy_if_needed()

func _defense_answers_attack(defense_type: String, attack_data: Dictionary) -> bool:
	match String(attack_data["type"]):
		"HIGH":
			return defense_type == "block" or defense_type == "crouch_block"
		"MID":
			return defense_type == "block" or defense_type == "crouch_block" or (defense_type == "jump" and _distance_between_fighters() > 65.0)
		"LOW":
			return defense_type == "crouch_block" or defense_type == "jump"
		"OVERHEAD":
			return defense_type == "block" or defense_type == "perfect_block"
		_:
			return false

func _change_frame_advantage(delta: int) -> void:
	var previous := frame_advantage
	frame_advantage = clampi(frame_advantage + delta, -3, 6)
	if frame_advantage < 0:
		frame_advantage = 0
	if frame_advantage == 0:
		_reset_pressure_sequence()
	frame_advantage_changed.emit(frame_advantage)
	if frame_advantage > previous:
		log_message.emit("Frame advantage gained: %d -> %d." % [previous, frame_advantage])
	elif frame_advantage < previous:
		log_message.emit("Frame advantage lost: %d -> %d." % [previous, frame_advantage])
		if frame_advantage == 0:
			log_message.emit("Combo dropped / reset to neutral.")
	_update_time_scale()

func _set_frame_advantage_to_neutral() -> void:
	frame_advantage = 0
	_reset_pressure_sequence()
	frame_advantage_changed.emit(frame_advantage)
	_update_time_scale()

func _run_perfect_block_hitstop() -> void:
	Engine.time_scale = 0.03
	await get_tree().create_timer(PERFECT_BLOCK_HITSTOP, true, false, true).timeout
	Engine.time_scale = 1.0
	_update_time_scale()

func _try_interrupt_with_card(index: int) -> void:
	if not deck_manager.is_card_playable(index, _is_enemy_broken()):
		log_message.emit("Card not playable.")
		return

	var card: Resource = deck_manager.hand[index]
	_move_player_by_card(card)
	var distance := _distance_between_fighters()
	if int(card.startup_frame) >= current_enemy_startup_frame:
		log_message.emit("Interrupt failed: too slow.")
		_resolve_enemy_counter_hit()
		return
	if distance > card.range:
		log_message.emit("Interrupt failed: out of range.")
		_resolve_enemy_counter_hit()
		return
	if not _card_has_tag(card, "interrupt") and not _card_has_tag(card, "starter"):
		log_message.emit("Interrupt failed: too slow.")
		_resolve_enemy_counter_hit()
		return

	waiting_for_defense = false
	attack_in_progress = false
	Engine.time_scale = 1.0
	frame_advantage_changed.emit(frame_advantage)
	enemy.finish_attack()
	var interrupted_intent := current_enemy_intent
	current_enemy_intent = ""
	current_enemy_startup_frame = 0
	card = deck_manager.play_card(index, _is_enemy_broken())
	if card == null:
		_update_time_scale()
		return
	log_message.emit("%s interrupted %s." % [card.display_name, interrupted_intent])
	_resolve_player_card(card, 2, false)

func _resolve_enemy_counter_hit() -> void:
	waiting_for_defense = false
	Engine.time_scale = 1.0
	frame_advantage_changed.emit(frame_advantage)
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		attack_in_progress = false
		_update_time_scale()
		_schedule_enemy_if_needed()
		return
	var damage := int(result["counter_damage"])
	if _distance_between_fighters() > float(result["range"]):
		log_message.emit("Enemy attack whiffed due to spacing.")
		_change_frame_advantage(1)
	else:
		player.take_damage(damage)
		_set_frame_advantage_to_neutral()
		log_message.emit("Defense failed.")
	enemy.finish_attack()
	attack_in_progress = false
	current_enemy_intent = ""
	current_enemy_startup_frame = 0
	_update_time_scale()
	_schedule_enemy_if_needed()

func _resolve_player_card(card: Resource, bonus_frame_advantage := 0, apply_movement := true) -> void:
	log_message.emit("Card played: %s." % card.display_name)
	player.perform_card_action(card)
	if apply_movement:
		_move_player_by_card(card)

	var distance := _distance_between_fighters()
	var frame_delta: int = int(card.frame_gain) - int(card.frame_cost) + bonus_frame_advantage + _repeated_card_decay(card)
	if card.range > 0.0 and distance > card.range:
		log_message.emit("%s whiffed: out of range." % card.display_name)
		_resolve_card_frame_advantage(card.whiff_frame_penalty)
		return

	enemy.take_hit(card.damage, card.stance_damage)
	_apply_card_spacing(card)
	if card.stance_damage > 0:
		log_message.emit("Stance damage dealt: %d." % card.stance_damage)
	log_message.emit("%s hits for %d and deals %d stance." % [card.display_name, card.damage, card.stance_damage])
	_resolve_card_frame_advantage(frame_delta)

func _repeated_card_decay(card: Resource) -> int:
	var previous_count := int(repeated_card_uses.get(card.id, 0))
	repeated_card_uses[card.id] = previous_count + 1
	var penalty := -mini(previous_count, 3)
	if penalty < 0:
		log_message.emit("Repeated move decay applied.")
	return penalty

func _resolve_card_frame_advantage(delta: int) -> void:
	var previous := frame_advantage
	var final_frame_advantage := clampi(frame_advantage + delta, -12, 6)
	frame_advantage = final_frame_advantage
	frame_advantage_changed.emit(frame_advantage)

	if frame_advantage > previous:
		log_message.emit("Frame advantage gained: %d -> %d." % [previous, frame_advantage])
	elif frame_advantage < previous:
		log_message.emit("Frame advantage lost: %d -> %d." % [previous, frame_advantage])

	if final_frame_advantage >= 0:
		if final_frame_advantage > 0 and _has_valid_card_for_current_state():
			_update_time_scale()
			_schedule_enemy_if_needed()
			return
		if final_frame_advantage > 0:
			log_message.emit("Combo route drying out.")
		log_message.emit("Pressure ended safely. Reset to neutral.")
		frame_advantage = 0
		_reset_pressure_sequence()
		frame_advantage_changed.emit(frame_advantage)
		_update_time_scale()
		_schedule_enemy_if_needed()
		return

	_resolve_negative_pressure(final_frame_advantage)

func _resolve_negative_pressure(final_frame_advantage: int) -> void:
	if _is_enemy_broken():
		log_message.emit("Pressure ended safely. Reset to neutral.")
		frame_advantage = 0
		_reset_pressure_sequence()
		frame_advantage_changed.emit(frame_advantage)
		_update_time_scale()
		return

	if _enemy_can_punish(final_frame_advantage):
		log_message.emit("Enemy punished unsafe pressure.")
		enemy.perform_punish_combo()
		player.take_damage(enemy.punish_damage)
	else:
		if _distance_between_fighters() > enemy.punish_range:
			log_message.emit("Pressure ended safely due to spacing.")
		else:
			log_message.emit("Pressure ended safely. Reset to neutral.")

	frame_advantage = 0
	_reset_pressure_sequence()
	frame_advantage_changed.emit(frame_advantage)
	_update_time_scale()
	_schedule_enemy_if_needed()

func _enemy_can_punish(final_frame_advantage: int) -> bool:
	if _is_enemy_broken() or not enemy.can_act():
		return false
	var punish_window: int = absi(final_frame_advantage) + int(enemy.punish_startup)
	return punish_window >= punish_threshold and _distance_between_fighters() <= enemy.punish_range

func _distance_between_fighters() -> float:
	return absf(player.global_position.x - enemy.global_position.x)

func _move_player_by_card(card: Resource) -> void:
	if card.movement_delta == 0.0:
		return
	var direction_to_enemy := signf(enemy.global_position.x - player.global_position.x)
	if direction_to_enemy == 0.0:
		direction_to_enemy = 1.0
	player.global_position.x += card.movement_delta * direction_to_enemy

func _move_player_away_from_enemy(amount: float) -> void:
	var direction_to_enemy := signf(enemy.global_position.x - player.global_position.x)
	if direction_to_enemy == 0.0:
		direction_to_enemy = 1.0
	player.global_position.x -= amount * direction_to_enemy

func _apply_card_spacing(card: Resource) -> void:
	match card.id:
		"reset_step":
			pass
		"ground_smash":
			var direction_to_enemy := signf(enemy.global_position.x - player.global_position.x)
			if direction_to_enemy == 0.0:
				direction_to_enemy = 1.0
			enemy.global_position.x += 180.0 * direction_to_enemy

func _check_combo_route_drying_out() -> void:
	if can_play_cards() and not _has_valid_card_for_current_state():
		log_message.emit("Combo route drying out.")
		_change_frame_advantage(-frame_advantage)

func _on_enemy_break_started() -> void:
	frame_advantage = maxi(frame_advantage + stance_break_frame_bonus, stance_break_frame_bonus)
	frame_advantage_changed.emit(frame_advantage)
	log_message.emit("Stance break! Punish window opened: +%d frame advantage." % stance_break_frame_bonus)
	_update_time_scale()

func _on_enemy_break_ended() -> void:
	if frame_advantage <= 0:
		frame_advantage = 0
		_reset_pressure_sequence()
		frame_advantage_changed.emit(frame_advantage)
		log_message.emit("Enemy recovered from stance break. Reset to neutral.")
		_schedule_enemy_if_needed()
	else:
		log_message.emit("Enemy recovered from stance break. Pressure continues.")
	_update_time_scale()

func _is_enemy_broken() -> bool:
	return enemy.state == Enemy.State.BREAK

func _has_valid_card_for_current_state() -> bool:
	return deck_manager.has_break_playable_card() if _is_enemy_broken() else deck_manager.has_valid_playable_card()

func _reset_pressure_sequence() -> void:
	deck_manager.reset_combo_route()
	repeated_card_uses.clear()

func _card_has_tag(card: Resource, tag_name: String) -> bool:
	return card.tags.has(tag_name)

func _is_interrupt_card_index(index: int) -> bool:
	if index < 0 or index >= deck_manager.hand.size():
		return false
	var card: Resource = deck_manager.hand[index]
	return _card_has_tag(card, "interrupt") or _card_has_tag(card, "starter")

func _current_mode() -> String:
	if _is_enemy_broken():
		return "Stance Break"
	if waiting_for_defense:
		return "Enemy Intent"
	if frame_advantage > 0:
		return "Player Pressure"
	return "Neutral"

func _schedule_enemy_if_needed() -> void:
	if combat_over or attack_in_progress or waiting_for_defense or frame_advantage > 0:
		return
	await get_tree().create_timer(0.45).timeout
	_run_enemy_attack()

func _update_time_scale() -> void:
	if combat_over:
		Engine.time_scale = 1.0
	elif waiting_for_defense:
		Engine.time_scale = ENEMY_INTENT_TIME_SCALE
	else:
		Engine.time_scale = PLAYER_CHOICE_TIME_SCALE if can_play_cards() else 1.0

func _end_combat(message: String) -> void:
	combat_over = true
	waiting_for_defense = false
	Engine.time_scale = 1.0
	log_message.emit(message)

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _defense_display_name(defense_type: String) -> String:
	match defense_type:
		"crouch_block":
			return "crouch block"
		"perfect_block":
			return "perfect block"
		_:
			return defense_type

func _defense_from_key(keycode: Key) -> String:
	match keycode:
		KEY_J:
			return "block"
		KEY_K:
			return "crouch_block"
		KEY_L:
			return "backstep"
		KEY_SPACE:
			return "jump"
		KEY_I:
			return "perfect_block"
		_:
			return ""
