class_name CombatManagerCore
extends Node

signal frame_advantage_changed(value: int)
signal log_message(message: String)

const ATTACK_RECOVERY := 0.35
const PLAYER_CHOICE_TIME_SCALE := 0.2
const ENEMY_INTENT_TIME_SCALE := 0.15
const PERFECT_BLOCK_HITSTOP := 0.12
const HitboxDebugDrawScript := preload("res://scripts/hitbox_debug_draw.gd")
const CombatClockScript := preload("res://scripts/combat/combat_clock.gd")
const FrameSystemScript := preload("res://scripts/combat/frame_system.gd")
const QueueResolverScript := preload("res://scripts/combat/queue_resolver.gd")
const RouteSystemScript := preload("res://scripts/combat/route_system.gd")
const MovementSystemScript := preload("res://scripts/combat/movement_system.gd")
const HitboxSystemScript := preload("res://scripts/combat/hitbox_system.gd")
const TradeSystemScript := preload("res://scripts/combat/trade_system.gd")
const StanceSystemScript := preload("res://scripts/combat/stance_system.gd")
const DEBUG_ATTACK_HITBOX_LIFETIME := 0.25

@export var starting_frame_advantage := 0
@export var punish_threshold := 10
@export var enemy_punish_startup := 5
@export var enemy_punish_range := 120.0
@export var stance_break_frame_bonus := 6
@export var max_duel_distance := 260.0
@export var min_duel_distance := 55.0
@export var show_debug_hitboxes := true
@export var show_prediction_assist := true
@export var perfect_block_window_frames := 1
@export var max_queue_size := 3
@export var trade_player_recovery_frames := 18
@export var trade_enemy_recovery_frames := 26

var frame_advantage := 0
var last_defense := ""
var attack_in_progress := false
var waiting_for_defense := false
var combat_over := false
var punish_in_progress := false
var enemy_intent_scheduled := false
var current_enemy_intent := ""
var enemy_base_startup_frame := 0
var enemy_effective_startup_frame := 0
var remaining_startup_frames := 0
var last_player_action_startup := 0
var initiative_offset := 0
var enemy_vulnerable_frames_remaining := 0
var last_player_attack_hitbox := Rect2()
var last_enemy_attack_hitbox := Rect2()
var player_attack_hitbox_lifetime := 0.0
var enemy_attack_hitbox_lifetime := 0.0
var combat_clock
var frame_system
var queue_resolver
var route_system
var movement_system
var hitbox_system
var trade_system
var stance_system

@onready var player = $"../Player"
@onready var enemy = $"../Enemy"
@onready var deck_manager = $"../DeckManager"

func _ready() -> void:
	frame_advantage = starting_frame_advantage
	enemy.punish_startup = enemy_punish_startup
	enemy.punish_range = enemy_punish_range
	_setup_combat_systems()
	_create_hitbox_debug_drawer()
	player.defense_performed.connect(_on_player_defense)
	enemy.break_started.connect(_on_enemy_break_started)
	enemy.break_ended.connect(_on_enemy_break_ended)
	deck_manager.follow_up_drawn.connect(_on_follow_up_drawn)
	deck_manager.follow_up_skipped.connect(_on_follow_up_skipped)
	call_deferred("_begin_combat")

func _setup_combat_systems() -> void:
	combat_clock = CombatClockScript.new()
	combat_clock.setup(self, enemy)
	frame_system = FrameSystemScript.new()
	frame_system.setup(self, enemy)
	queue_resolver = QueueResolverScript.new()
	queue_resolver.setup(self, deck_manager, max_queue_size)
	route_system = RouteSystemScript.new()
	route_system.setup(self, deck_manager)
	movement_system = MovementSystemScript.new()
	movement_system.setup(self, player, enemy, max_duel_distance, min_duel_distance)
	hitbox_system = HitboxSystemScript.new()
	hitbox_system.setup(self, player, enemy, movement_system)
	trade_system = TradeSystemScript.new()
	trade_system.setup(self, trade_player_recovery_frames, trade_enemy_recovery_frames)
	stance_system = StanceSystemScript.new()
	stance_system.setup(enemy)

func _begin_combat() -> void:
	deck_manager.start_combat()
	player.set_free_movement_enabled(false)
	frame_advantage_changed.emit(frame_advantage)
	log_message.emit("Duel start. Read the enemy intent.")
	_schedule_enemy_if_needed()

func _process(_delta: float) -> void:
	if combat_over:
		return
	_clamp_duel_distance()
	_tick_debug_hitboxes(_delta)

	if player.hp <= 0:
		_end_combat("Player defeated.")
	elif enemy.hp <= 0:
		_end_combat("Enemy defeated.")

func get_debug_text() -> String:
	return "Distance: %.0f\nEnemy intent: %s\nEnemy base startup: %d\nEnemy effective startup: %d\nEnemy remaining startup: %d\nLast player startup: %d\nEnemy vulnerable frames: %d\nInitiative Offset: %s\nStance State: %s\nStance Recovery Frames: %d\nStance Break Stun Remaining: %d\nStance Protected: %s\n%s\nMode: %s" % [
		_distance_between_fighters(),
		current_enemy_intent if current_enemy_intent != "" else "None",
		enemy_base_startup_frame,
		enemy_effective_startup_frame,
		remaining_startup_frames,
		last_player_action_startup,
		enemy_vulnerable_frames_remaining,
		_signed_int(initiative_offset),
		stance_system.state_name(),
		stance_system.recovery_frames(),
		stance_system.break_stun_frames(),
		str(stance_system.protected()),
		get_queue_text(),
		_current_mode()
	]

func can_play_cards() -> bool:
	return (waiting_for_defense or ((frame_advantage > 0 or _enemy_break_frames_remaining() > 0) and not attack_in_progress)) and not combat_over

func is_hand_card_playable(index: int) -> bool:
	if waiting_for_defense:
		return index >= 0 and index < deck_manager.hand.size() and not _is_card_instance_queued(deck_manager.hand[index])
	return can_play_cards() and index >= 0 and index < deck_manager.hand.size() and not _is_card_instance_queued(deck_manager.hand[index])

func get_card_prediction(index: int) -> String:
	if not show_prediction_assist:
		return "normal"
	if index < 0 or index >= deck_manager.hand.size():
		return "normal"
	if waiting_for_defense:
		return _predict_enemy_intent_card_outcome(deck_manager.hand[index])
	if frame_advantage > 0 and not attack_in_progress:
		return _predict_pressure_card_outcome(index, deck_manager.hand[index])
	return "normal"

func play_card(index: int) -> void:
	if _is_tactical_mode() and not queue_resolver.resolving:
		_queue_tactical_action(_make_card_queue_action(index))
		return

	if waiting_for_defense:
		_try_interrupt_with_card(index)
		return

	if not can_play_cards():
		_change_frame_advantage(-1)
		log_message.emit("Bad timing. Dropped tempo.")
		return
	var route_valid: bool = deck_manager.is_card_route_valid(index, _is_enemy_broken())
	var preview_card: Resource = deck_manager.hand[index]
	var starts_new_route: bool = not route_valid and _card_has_tag(preview_card, "starter")
	_resolve_pressure_card(index, route_valid, starts_new_route)

func _on_player_defense(defense_type: String) -> void:
	last_defense = defense_type
	if waiting_for_defense:
		_resolve_enemy_intent(defense_type)

func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return

	if _is_tactical_mode():
		if key_event.keycode == KEY_E:
			get_viewport().set_input_as_handled()
			_execute_or_wait_tactical_queue()
			return
		if key_event.keycode == KEY_BACKSPACE:
			get_viewport().set_input_as_handled()
			_pop_tactical_action()
			return
		if key_event.keycode == KEY_C:
			get_viewport().set_input_as_handled()
			_clear_tactical_queue()
			return
		if key_event.keycode == KEY_U:
			get_viewport().set_input_as_handled()
			if queue_resolver.is_empty():
				_execute_or_wait_tactical_queue()
			return

		var queued_action := _queued_action_from_key(key_event.keycode)
		if not queued_action.is_empty():
			get_viewport().set_input_as_handled()
			_queue_tactical_action(queued_action)
			return

	if waiting_for_defense:
		var defense_type := _defense_from_key(key_event.keycode)
		if defense_type == "":
			return

		get_viewport().set_input_as_handled()
		_resolve_enemy_intent(defense_type)
		return

	if _can_take_pressure_movement():
		var pressure_action := _pressure_movement_from_key(key_event.keycode)
		if pressure_action == "":
			return

		get_viewport().set_input_as_handled()
		_apply_pressure_movement(pressure_action)

func _run_enemy_attack() -> void:
	if combat_over or frame_advantage > 0 or attack_in_progress or not enemy.can_act():
		return

	attack_in_progress = true
	waiting_for_defense = true
	last_defense = ""
	queue_resolver.clear()
	_reset_pressure_sequence()
	enemy.start_attack()
	current_enemy_intent = enemy.current_attack
	enemy_base_startup_frame = int(Enemy.ATTACKS[current_enemy_intent]["startup_frame"])
	enemy_effective_startup_frame = frame_system.effective_startup(enemy_base_startup_frame, initiative_offset)
	if initiative_offset != 0:
		log_message.emit("Enemy next startup modified by %s." % _signed_int(initiative_offset))
	initiative_offset = 0
	remaining_startup_frames = enemy_effective_startup_frame
	last_player_action_startup = 0
	_clear_attack_hitboxes()
	player.set_free_movement_enabled(false)
	log_message.emit("Enemy intent: %s." % enemy.current_attack)
	log_message.emit("Bullet time: choose defense.")
	frame_advantage_changed.emit(frame_advantage)
	_update_time_scale()

func _resolve_enemy_intent(defense_type: String) -> void:
	if combat_over or not waiting_for_defense:
		return

	last_player_action_startup = _action_startup(defense_type)
	log_message.emit("Player chose %s." % _defense_display_name(defense_type))

	if defense_type == "wait":
		_advance_enemy_startup(1)
		log_message.emit("Player waited. Enemy startup now %d." % remaining_startup_frames)
		if remaining_startup_frames <= 0:
			await _resolve_enemy_impact_after_countdown("wait")
		return

	if defense_type == "step_back" or defense_type == "step_forward":
		_apply_intent_action_movement(defense_type)
		_clamp_duel_distance()
		_advance_enemy_startup(_action_startup(defense_type))
		if remaining_startup_frames <= 0:
			await _resolve_enemy_impact_after_countdown(defense_type)
		else:
			frame_advantage_changed.emit(frame_advantage)
		return

	if defense_type == "backstep" or _is_jump_action(defense_type):
		_apply_intent_action_movement(defense_type)
		_clamp_duel_distance()
		_advance_enemy_startup(_action_startup(defense_type))
		if remaining_startup_frames <= 0:
			await _resolve_enemy_impact_after_countdown(defense_type)
		else:
			frame_advantage_changed.emit(frame_advantage)
		return

	var block_input_startup := remaining_startup_frames
	var block_startup := _action_startup(defense_type)
	var startup_after_block := block_input_startup - block_startup
	log_message.emit("Block input at enemy startup %d." % block_input_startup)
	log_message.emit("Block startup %d." % block_startup)
	log_message.emit("Block became active at enemy startup %d." % startup_after_block)
	_advance_enemy_startup(block_startup)
	await _resolve_block_after_startup(defense_type, startup_after_block)

func _resolve_enemy_impact_after_countdown(defense_type: String) -> void:
	_begin_enemy_resolution()
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		_finish_enemy_resolution()
		return

	_set_enemy_attack_hitbox(_make_enemy_attack_hitbox(result))
	var enemy_attack_hits := last_enemy_attack_hitbox.intersects(get_player_hurtbox())
	if defense_type == "wait":
		if not enemy_attack_hits:
			log_message.emit("Enemy whiffed after wait.")
			_reset_pressure_sequence()
			_change_frame_advantage(1)
		else:
			player.take_damage(result["damage"])
			_set_frame_advantage_to_neutral()
			log_message.emit("Wait failed: enemy was in range.")
	elif not enemy_attack_hits or _enemy_attack_whiffs_against_defense(defense_type, result):
		log_message.emit("Enemy attack whiffed due to spacing.")
		_reset_pressure_sequence()
		_change_frame_advantage(1)
	elif _defense_answers_attack(defense_type, result):
		_reset_pressure_sequence()
		_change_frame_advantage(2)
		log_message.emit("Normal defense success.")
	else:
		player.take_damage(result["damage"])
		_set_frame_advantage_to_neutral()
		log_message.emit("Defense failed.")

	await _finish_enemy_resolution_after_recovery()

func _resolve_block_after_startup(defense_type: String, startup_after_block: int) -> void:
	_begin_enemy_resolution()
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		_finish_enemy_resolution()
		return

	_set_enemy_attack_hitbox(_make_enemy_attack_hitbox(result))
	var enemy_attack_hits := last_enemy_attack_hitbox.intersects(get_player_hurtbox())
	if not enemy_attack_hits or _enemy_attack_whiffs_against_defense(defense_type, result):
		log_message.emit("Enemy attack whiffed due to spacing.")
		_reset_pressure_sequence()
		_change_frame_advantage(1)
	elif startup_after_block < 0:
		player.take_damage(result["counter_damage"])
		_set_frame_advantage_to_neutral()
		log_message.emit("Defense failed: too late.")
	elif _defense_answers_attack(defense_type, result):
		if startup_after_block <= perfect_block_window_frames:
			_reset_pressure_sequence()
			_change_frame_advantage(4)
			_log_stance_protection(15)
			enemy.add_block_stance_damage(15)
			log_message.emit("Perfect block window hit.")
			log_message.emit("PERFECT BLOCK")
			log_message.emit("Stance damage dealt: 15.")
			player.show_state("PERFECT BLOCK", Color.GOLD)
			await _run_perfect_block_hitstop()
		else:
			_reset_pressure_sequence()
			_change_frame_advantage(2)
			log_message.emit("Normal block: too early for perfect.")
	else:
		player.take_damage(result["damage"])
		_set_frame_advantage_to_neutral()
		log_message.emit("Defense failed.")

	await _finish_enemy_resolution_after_recovery()

func _begin_enemy_resolution() -> void:
	waiting_for_defense = false
	Engine.time_scale = 1.0
	frame_advantage_changed.emit(frame_advantage)

func _finish_enemy_resolution() -> void:
	enemy.finish_attack()
	attack_in_progress = false
	player.set_free_movement_enabled(false)
	current_enemy_intent = ""
	enemy_base_startup_frame = 0
	enemy_effective_startup_frame = 0
	remaining_startup_frames = 0
	_update_time_scale()
	_schedule_enemy_if_needed()

func _finish_enemy_resolution_after_recovery() -> void:
	advance_combat_frames(int(round(ATTACK_RECOVERY * 60.0)))
	await get_tree().create_timer(ATTACK_RECOVERY).timeout
	_finish_enemy_resolution()

func _defense_answers_attack(defense_type: String, attack_data: Dictionary) -> bool:
	match String(attack_data["type"]):
		"HIGH":
			return defense_type == "block"
		"MID":
			return defense_type == "block" or defense_type == "crouch_block"
		"LOW":
			return defense_type == "crouch_block" or _is_jump_action(defense_type)
		"OVERHEAD":
			return defense_type == "block"
		_:
			return false

func _change_frame_advantage(delta: int) -> void:
	var previous := frame_advantage
	frame_advantage = clampi(frame_advantage + delta, -3, 6)
	if frame_advantage < 0:
		frame_advantage = 0
	enemy_vulnerable_frames_remaining = maxi(0, frame_advantage)
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
	enemy_vulnerable_frames_remaining = 0
	_reset_pressure_sequence()
	frame_advantage_changed.emit(frame_advantage)
	_update_time_scale()

func end_player_pressure(reason: String, initiative_result := 0) -> void:
	initiative_offset = initiative_result
	if initiative_result < 0:
		log_message.emit("Player ended unsafe at %d." % initiative_result)
		log_message.emit("Enemy next startup modified by %d." % initiative_result)
	frame_advantage = 0
	enemy_vulnerable_frames_remaining = 0
	queue_resolver.clear()
	waiting_for_defense = false
	attack_in_progress = false
	current_enemy_intent = ""
	enemy_base_startup_frame = 0
	enemy_effective_startup_frame = 0
	remaining_startup_frames = 0
	last_player_action_startup = 0
	if not _is_enemy_broken() and enemy.has_method("clear_intent"):
		enemy.clear_intent()
	_reset_pressure_sequence()
	Engine.time_scale = 1.0
	player.set_free_movement_enabled(false)
	frame_advantage_changed.emit(frame_advantage)
	if reason != "":
		log_message.emit(reason)
	_schedule_enemy_if_needed()

func _run_perfect_block_hitstop() -> void:
	Engine.time_scale = 0.03
	await get_tree().create_timer(PERFECT_BLOCK_HITSTOP, true, false, true).timeout
	Engine.time_scale = 1.0
	_update_time_scale()

func _try_interrupt_with_card(index: int) -> void:
	if index < 0 or index >= deck_manager.hand.size():
		log_message.emit("Card not playable.")
		return

	var card: Resource = deck_manager.hand[index]
	last_player_action_startup = int(card.startup_frame)
	var card_hits := _card_would_hit_enemy_after_movement(card)
	var enemy_startup_after_card := remaining_startup_frames - int(card.startup_frame)
	advance_combat_frames(int(card.startup_frame), false, false)

	if card_hits and absi(int(card.startup_frame) - remaining_startup_frames) <= 2:
		_move_player_by_card(card)
		_clamp_duel_distance()
		_set_player_attack_hitbox(_make_card_hitbox(card))
		_resolve_intent_trade(index, card, enemy_startup_after_card)
		return

	if int(card.startup_frame) > remaining_startup_frames:
		log_message.emit("Interrupt failed: too slow.")
		log_message.emit("No follow-up draw: card did not connect.")
		deck_manager.discard_card_unrestricted(index)
		_resolve_enemy_counter_hit(true)
		return
	if not card_hits:
		_move_player_by_card(card)
		_clamp_duel_distance()
		_set_player_attack_hitbox(_make_card_hitbox(card))
		log_message.emit("Interrupt failed: out of range.")
		log_message.emit("Card whiffed: hitbox missed.")
		log_message.emit("No follow-up draw: card did not connect.")
		remaining_startup_frames = enemy_startup_after_card
		deck_manager.discard_card_unrestricted(index)
		if remaining_startup_frames <= 0:
			await _resolve_enemy_impact_after_countdown("card_whiff")
		else:
			frame_advantage_changed.emit(frame_advantage)
			_update_time_scale()
		return

	waiting_for_defense = false
	attack_in_progress = false
	remaining_startup_frames = enemy_startup_after_card
	_move_player_by_card(card)
	_clamp_duel_distance()
	_set_player_attack_hitbox(_make_card_hitbox(card))
	Engine.time_scale = 1.0
	frame_advantage_changed.emit(frame_advantage)
	player.set_free_movement_enabled(false)
	var interrupted_intent := current_enemy_intent
	current_enemy_intent = ""
	enemy_base_startup_frame = 0
	enemy_effective_startup_frame = 0
	remaining_startup_frames = 0
	if enemy.has_method("clear_intent"):
		enemy.clear_intent()
	card = deck_manager.play_card_unrestricted(index)
	if card == null:
		_update_time_scale()
		return
	log_message.emit("%s interrupted %s." % [card.display_name, interrupted_intent])
	_resolve_player_card(card, 2, false)

func _try_interrupt_with_card_snapshot(snapshot: Dictionary) -> void:
	var card: Resource = _card_from_snapshot(snapshot)
	last_player_action_startup = int(card.startup_frame)
	var card_hits := _card_would_hit_enemy_after_movement(card)
	var enemy_startup_after_card := remaining_startup_frames - int(card.startup_frame)
	advance_combat_frames(int(card.startup_frame), false, false)

	if card_hits and absi(int(card.startup_frame) - remaining_startup_frames) <= 2:
		_move_player_by_card(card)
		_clamp_duel_distance()
		_set_player_attack_hitbox(_make_card_hitbox(card))
		_resolve_intent_trade_snapshot(snapshot, card, enemy_startup_after_card)
		return

	if int(card.startup_frame) > remaining_startup_frames:
		log_message.emit("Interrupt failed: too slow.")
		log_message.emit("No follow-up draw: card did not connect.")
		deck_manager.discard_queued_card_snapshot(snapshot)
		_resolve_enemy_counter_hit(true)
		return
	if not card_hits:
		_move_player_by_card(card)
		_clamp_duel_distance()
		_set_player_attack_hitbox(_make_card_hitbox(card))
		log_message.emit("Interrupt failed: out of range.")
		log_message.emit("Card whiffed: hitbox missed.")
		log_message.emit("No follow-up draw: card did not connect.")
		remaining_startup_frames = enemy_startup_after_card
		deck_manager.discard_queued_card_snapshot(snapshot)
		if remaining_startup_frames <= 0:
			await _resolve_enemy_impact_after_countdown("card_whiff")
		else:
			frame_advantage_changed.emit(frame_advantage)
			_update_time_scale()
		return

	waiting_for_defense = false
	attack_in_progress = false
	remaining_startup_frames = enemy_startup_after_card
	_move_player_by_card(card)
	_clamp_duel_distance()
	_set_player_attack_hitbox(_make_card_hitbox(card))
	Engine.time_scale = 1.0
	frame_advantage_changed.emit(frame_advantage)
	player.set_free_movement_enabled(false)
	var interrupted_intent := current_enemy_intent
	current_enemy_intent = ""
	enemy_base_startup_frame = 0
	enemy_effective_startup_frame = 0
	remaining_startup_frames = 0
	if enemy.has_method("clear_intent"):
		enemy.clear_intent()
	var played_card: Resource = deck_manager.play_queued_card_snapshot(snapshot, true, false)
	log_message.emit("%s interrupted %s." % [played_card.display_name, interrupted_intent])
	_resolve_player_card(played_card, 2, false)

func _resolve_intent_trade(index: int, preview_card: Resource, enemy_startup_after_card: int) -> void:
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		return

	waiting_for_defense = false
	attack_in_progress = false
	remaining_startup_frames = maxi(0, enemy_startup_after_card)
	Engine.time_scale = 1.0
	_set_enemy_attack_hitbox(_make_enemy_attack_hitbox(result))
	player.take_damage(result["damage"])
	_log_stance_protection(preview_card.stance_damage)
	enemy.take_hit(preview_card.damage, preview_card.stance_damage)
	player.set_free_movement_enabled(false)
	var traded_intent := current_enemy_intent
	current_enemy_intent = ""
	enemy_base_startup_frame = 0
	enemy_effective_startup_frame = 0
	remaining_startup_frames = 0
	if enemy.has_method("clear_intent"):
		enemy.clear_intent()
	var card: Resource = deck_manager.play_card_unrestricted(index)
	if card == null:
		_update_time_scale()
		return
	log_message.emit("Trade occurred.")
	log_message.emit("%s traded with %s." % [card.display_name, traded_intent])
	_apply_trade_frame_result(card)

func _resolve_intent_trade_snapshot(snapshot: Dictionary, preview_card: Resource, enemy_startup_after_card: int) -> void:
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		return

	waiting_for_defense = false
	attack_in_progress = false
	remaining_startup_frames = maxi(0, enemy_startup_after_card)
	Engine.time_scale = 1.0
	_set_enemy_attack_hitbox(_make_enemy_attack_hitbox(result))
	player.take_damage(result["damage"])
	_log_stance_protection(preview_card.stance_damage)
	enemy.take_hit(preview_card.damage, preview_card.stance_damage)
	player.set_free_movement_enabled(false)
	var traded_intent := current_enemy_intent
	current_enemy_intent = ""
	enemy_base_startup_frame = 0
	enemy_effective_startup_frame = 0
	remaining_startup_frames = 0
	if enemy.has_method("clear_intent"):
		enemy.clear_intent()
	var card: Resource = deck_manager.play_queued_card_snapshot(snapshot, true, false)
	log_message.emit("Trade occurred.")
	log_message.emit("%s traded with %s." % [card.display_name, traded_intent])
	_apply_trade_frame_result(card)

func _resolve_enemy_counter_hit(counter_hit := true) -> void:
	waiting_for_defense = false
	Engine.time_scale = 1.0
	frame_advantage_changed.emit(frame_advantage)
	if remaining_startup_frames > 0:
		remaining_startup_frames = 0
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		attack_in_progress = false
		player.set_free_movement_enabled(false)
		_update_time_scale()
		_schedule_enemy_if_needed()
		return
	var damage := int(result["counter_damage"])
	_set_enemy_attack_hitbox(_make_enemy_attack_hitbox(result))
	if not last_enemy_attack_hitbox.intersects(get_player_hurtbox()):
		log_message.emit("Enemy attack whiffed due to spacing.")
		_change_frame_advantage(1)
	else:
		player.take_damage(damage if counter_hit else int(result["damage"]))
		_set_frame_advantage_to_neutral()
		log_message.emit("Defense failed.")
	enemy.finish_attack()
	attack_in_progress = false
	player.set_free_movement_enabled(false)
	current_enemy_intent = ""
	enemy_base_startup_frame = 0
	enemy_effective_startup_frame = 0
	remaining_startup_frames = 0
	_update_time_scale()
	_schedule_enemy_if_needed()

func _apply_trade_frame_result(card: Resource) -> void:
	queue_resolver.interrupted_by_trade = true
	queue_resolver.clear()
	var trade_result: Dictionary = trade_system.resolve_post_trade(card)
	var player_recovery := int(trade_result["player_recovery"])
	var enemy_recovery := int(trade_result["enemy_recovery"])
	var post_trade_frame_advantage := int(trade_result["post_trade_frame_advantage"])
	advance_combat_frames(int(trade_result["total_recovery"]))
	log_message.emit("Trade recovery: player %df, enemy %df." % [player_recovery, enemy_recovery])
	log_message.emit("Post-trade frame advantage: %d." % post_trade_frame_advantage)
	if post_trade_frame_advantage > 0:
		frame_advantage = post_trade_frame_advantage
		enemy_vulnerable_frames_remaining = post_trade_frame_advantage
		frame_advantage_changed.emit(frame_advantage)
		_update_time_scale()
	else:
		end_player_pressure("Trade recovery favored enemy.", post_trade_frame_advantage)

func _resolve_pressure_card(index: int, route_valid: bool, starts_new_route: bool) -> void:
	if index < 0 or index >= deck_manager.hand.size():
		log_message.emit("Card not playable.")
		return

	var preview_card: Resource = deck_manager.hand[index]
	log_message.emit("Card played: %s." % preview_card.display_name)
	player.perform_card_action(preview_card)
	_move_player_by_card(preview_card)
	_clamp_duel_distance()
	advance_combat_frames(int(preview_card.startup_frame))

	var repeat_info := _repeated_card_decay(preview_card)
	var frame_delta: int = int(preview_card.frame_gain) - int(preview_card.frame_cost) + int(repeat_info["penalty"])
	_set_player_attack_hitbox(_make_card_hitbox(preview_card))
	if _card_needs_hitbox(preview_card) and not _card_hitbox_hits_enemy(preview_card):
		log_message.emit("Card whiffed: hitbox missed.")
		log_message.emit("No follow-up draw: card did not connect.")
		deck_manager.discard_card_unrestricted(index)
		_resolve_card_frame_advantage(preview_card.whiff_frame_penalty)
		return

	var allow_follow_up := (route_valid or starts_new_route) and not bool(repeat_info["suppress_follow_up"])
	if (route_valid or starts_new_route) and not allow_follow_up:
		log_message.emit("No follow-up draw: repeated route decay.")
	var card: Resource = deck_manager.play_card_with_route_result(index, allow_follow_up and route_valid, allow_follow_up and starts_new_route)
	if card == null:
		return

	_log_stance_protection(card.stance_damage)
	enemy.take_hit(card.damage, card.stance_damage)
	_apply_card_spacing(card)
	_clamp_duel_distance()
	if card.id == "ground_smash":
		_set_player_attack_hitbox(Rect2())
	if card.stance_damage > 0:
		log_message.emit("Stance damage dealt: %d." % card.stance_damage)
	if allow_follow_up:
		log_message.emit("Follow-up draw triggered.")
	else:
		log_message.emit("Combo route broken.")
	log_message.emit("%s hits for %d and deals %d stance." % [card.display_name, card.damage, card.stance_damage])
	if bool(repeat_info["force_end"]):
		end_player_pressure("Repeated route exhausted.", mini(frame_delta, -1))
		return
	_resolve_card_frame_advantage(frame_delta)

func _resolve_pressure_card_snapshot(snapshot: Dictionary) -> void:
	var preview_card: Resource = _card_from_snapshot(snapshot)
	var route_valid := bool(snapshot.get("route_valid_at_queue", false))
	var starts_new_route := bool(snapshot.get("starts_new_route_at_queue", false))
	log_message.emit("Card played: %s." % preview_card.display_name)
	player.perform_card_action(preview_card)
	_move_player_by_card(preview_card)
	_clamp_duel_distance()
	advance_combat_frames(int(preview_card.startup_frame))

	var repeat_info := _repeated_card_decay(preview_card)
	var frame_delta: int = int(preview_card.frame_gain) - int(preview_card.frame_cost) + int(repeat_info["penalty"])
	_set_player_attack_hitbox(_make_card_hitbox(preview_card))
	if _card_needs_hitbox(preview_card) and not _card_hitbox_hits_enemy(preview_card):
		log_message.emit("Card whiffed: hitbox missed.")
		log_message.emit("No follow-up draw: card did not connect.")
		deck_manager.discard_queued_card_snapshot(snapshot)
		_resolve_card_frame_advantage(preview_card.whiff_frame_penalty)
		return

	var allow_follow_up := (route_valid or starts_new_route) and not bool(repeat_info["suppress_follow_up"])
	if (route_valid or starts_new_route) and not allow_follow_up:
		log_message.emit("No follow-up draw: repeated route decay.")
	var card: Resource = deck_manager.play_queued_card_snapshot(snapshot, allow_follow_up and route_valid, allow_follow_up and starts_new_route)
	_log_stance_protection(card.stance_damage)
	enemy.take_hit(card.damage, card.stance_damage)
	_apply_card_spacing(card)
	_clamp_duel_distance()
	if card.id == "ground_smash":
		_set_player_attack_hitbox(Rect2())
	if card.stance_damage > 0:
		log_message.emit("Stance damage dealt: %d." % card.stance_damage)
	if allow_follow_up:
		log_message.emit("Follow-up draw triggered.")
	else:
		log_message.emit("Combo route broken.")
	log_message.emit("%s hits for %d and deals %d stance." % [card.display_name, card.damage, card.stance_damage])
	if bool(repeat_info["force_end"]):
		end_player_pressure("Repeated route exhausted.", mini(frame_delta, -1))
		return
	_resolve_card_frame_advantage(frame_delta)

func _resolve_player_card(card: Resource, bonus_frame_advantage := 0, apply_movement := true, route_valid := true, starts_new_route := false) -> void:
	log_message.emit("Card played: %s." % card.display_name)
	player.perform_card_action(card)
	if apply_movement:
		_move_player_by_card(card)
	_clamp_duel_distance()
	if apply_movement:
		advance_combat_frames(int(card.startup_frame))

	var repeat_info := _repeated_card_decay(card)
	var frame_delta: int = int(card.frame_gain) - int(card.frame_cost) + bonus_frame_advantage + int(repeat_info["penalty"])
	_set_player_attack_hitbox(_make_card_hitbox(card))
	if _card_needs_hitbox(card) and not _card_hitbox_hits_enemy(card):
		log_message.emit("Card whiffed: hitbox missed.")
		log_message.emit("No follow-up draw: card did not connect.")
		_resolve_card_frame_advantage(card.whiff_frame_penalty)
		return

	_log_stance_protection(card.stance_damage)
	enemy.take_hit(card.damage, card.stance_damage)
	_apply_card_spacing(card)
	_clamp_duel_distance()
	if card.id == "ground_smash":
		_set_player_attack_hitbox(Rect2())
	if card.stance_damage > 0:
		log_message.emit("Stance damage dealt: %d." % card.stance_damage)
	if route_valid or starts_new_route:
		log_message.emit("Follow-up draw triggered.")
	else:
		log_message.emit("Combo route broken.")
	log_message.emit("%s hits for %d and deals %d stance." % [card.display_name, card.damage, card.stance_damage])
	if bool(repeat_info["force_end"]):
		end_player_pressure("Repeated route exhausted.", mini(frame_delta, -1))
		return
	_resolve_card_frame_advantage(frame_delta)

func _repeated_card_decay(card: Resource) -> Dictionary:
	return route_system.repeated_card_decay(card)

func _resolve_card_frame_advantage(delta: int) -> void:
	var previous := frame_advantage
	var final_frame_advantage: int = frame_system.apply_advantage_delta(delta, frame_advantage)
	frame_advantage = final_frame_advantage
	enemy_vulnerable_frames_remaining = maxi(0, frame_advantage)
	frame_advantage_changed.emit(frame_advantage)

	if frame_advantage > previous:
		log_message.emit("Frame advantage gained: %d -> %d." % [previous, frame_advantage])
	elif frame_advantage < previous:
		log_message.emit("Frame advantage lost: %d -> %d." % [previous, frame_advantage])

	if final_frame_advantage >= 0:
		if _enemy_break_frames_remaining() > 0:
			_update_time_scale()
			return
		if final_frame_advantage > 0 and _has_valid_card_for_current_state():
			_update_time_scale()
			_schedule_enemy_if_needed()
			return
		if final_frame_advantage > 0:
			log_message.emit("Combo route drying out.")
		end_player_pressure("Pressure ended safely. Reset to neutral.", final_frame_advantage)
		return

	_resolve_negative_pressure(final_frame_advantage)

func _resolve_negative_pressure(final_frame_advantage: int) -> void:
	if _is_enemy_broken():
		end_player_pressure("Pressure ended safely. Reset to neutral.", final_frame_advantage)
		return

	if _enemy_can_punish(final_frame_advantage):
		log_message.emit("Enemy punished unsafe pressure.")
		punish_in_progress = true
		enemy.perform_punish_combo()
		player.take_damage(enemy.punish_damage)
		punish_in_progress = false
		end_player_pressure("", 0)
		return
	else:
		if _distance_between_fighters() > enemy.punish_range:
			end_player_pressure("Pressure ended safely due to spacing.", final_frame_advantage)
		else:
			end_player_pressure("Pressure ended safely. Reset to neutral.", final_frame_advantage)
		return

	end_player_pressure("", final_frame_advantage)

func _enemy_can_punish(final_frame_advantage: int) -> bool:
	if _is_enemy_broken() or not enemy.can_act():
		return false
	_set_enemy_attack_hitbox(_make_punish_hitbox())
	return frame_system.enemy_can_punish(final_frame_advantage, punish_threshold, last_enemy_attack_hitbox, get_player_hurtbox())

func _predict_enemy_intent_card_outcome(card: Resource) -> String:
	var card_startup := int(card.startup_frame)
	var startup_difference := absi(card_startup - remaining_startup_frames)
	var would_hit := _card_would_hit_enemy_after_movement(card)

	if would_hit and startup_difference <= 2:
		return "trade"
	if card_startup > remaining_startup_frames:
		return "too_slow"
	if not would_hit:
		return "whiff"
	return "interrupt"

func _predict_pressure_card_outcome(index: int, card: Resource) -> String:
	if not _card_would_hit_enemy_after_movement(card):
		return "whiff"

	var frame_delta: int = int(card.frame_gain) - int(card.frame_cost)
	if int(card.startup_frame) > frame_advantage or frame_advantage + frame_delta < 0:
		return "too_slow"

	if deck_manager.is_card_route_valid(index, _is_enemy_broken()):
		return "interrupt"
	return "trade"

func _distance_between_fighters() -> float:
	return movement_system.distance_between_fighters()

func _signed_int(value: int) -> String:
	return frame_system.signed_int(value)

func get_player_hurtbox() -> Rect2:
	return hitbox_system.player_hurtbox()

func get_enemy_hurtbox() -> Rect2:
	return hitbox_system.enemy_hurtbox()

func _make_card_hitbox(card: Resource) -> Rect2:
	return hitbox_system.card_hitbox(card)

func _make_card_hitbox_at(card: Resource, origin: Vector2) -> Rect2:
	return hitbox_system.card_hitbox_at(card, origin)

func _make_enemy_attack_hitbox(attack_data: Dictionary) -> Rect2:
	return hitbox_system.enemy_attack_hitbox(attack_data)

func _make_punish_hitbox() -> Rect2:
	return hitbox_system.punish_hitbox()

func _card_needs_hitbox(card: Resource) -> bool:
	return hitbox_system.card_needs_hitbox(card)

func _card_hitbox_hits_enemy(card: Resource) -> bool:
	return hitbox_system.card_hitbox_hits_enemy(card)

func _card_would_hit_enemy_after_movement(card: Resource) -> bool:
	return hitbox_system.card_would_hit_enemy_after_movement(card)

func _set_player_attack_hitbox(hitbox: Rect2) -> void:
	hitbox_system.set_player_attack_hitbox(hitbox)

func _set_enemy_attack_hitbox(hitbox: Rect2) -> void:
	hitbox_system.set_enemy_attack_hitbox(hitbox)

func _clear_attack_hitboxes() -> void:
	hitbox_system.clear_attack_hitboxes()

func _tick_debug_hitboxes(delta: float) -> void:
	hitbox_system.tick_debug_hitboxes(delta)

func _create_hitbox_debug_drawer() -> void:
	var debug_drawer := HitboxDebugDrawScript.new()
	debug_drawer.set("combat_manager", self)
	get_parent().call_deferred("add_child", debug_drawer)

func _clamp_duel_distance() -> void:
	movement_system.clamp_duel_distance()

func _clamped_player_x(player_x: float) -> float:
	return movement_system.clamped_player_x(player_x)

func _apply_intent_action_movement(action: String) -> void:
	movement_system.apply_intent_action_movement(action)

func _apply_pressure_movement(action: String) -> void:
	var cost := _action_startup(action)
	last_player_action_startup = cost
	_apply_intent_action_movement(action)
	_clamp_duel_distance()
	log_message.emit("Player chose %s." % _defense_display_name(action))
	_spend_pressure_frames(cost)

func _action_startup(action: String) -> int:
	return movement_system.action_startup(action)

func _advance_enemy_startup(cost: int) -> void:
	advance_combat_frames(cost, true, false)

func advance_combat_frames(frames: int, tick_enemy_startup := false, tick_enemy_vulnerability := true) -> void:
	combat_clock.advance_combat_frames(frames, tick_enemy_startup, tick_enemy_vulnerability)

func _spend_pressure_frames(cost: int) -> void:
	if cost <= 0:
		frame_advantage_changed.emit(frame_advantage)
		return

	var previous := frame_advantage
	var final_frame_advantage := frame_advantage - cost
	frame_advantage = final_frame_advantage
	advance_combat_frames(cost)
	frame_advantage_changed.emit(frame_advantage)
	log_message.emit("Frame advantage spent: %d -> %d." % [previous, frame_advantage])

	if frame_advantage <= 0 or enemy_vulnerable_frames_remaining <= 0:
		if final_frame_advantage < 0:
			_resolve_negative_pressure(final_frame_advantage)
		else:
			end_player_pressure("Pressure ended after movement.", final_frame_advantage)
		return

	_update_time_scale()

func _enemy_attack_whiffs_against_defense(defense_type: String, attack_data: Dictionary) -> bool:
	var attack_type := String(attack_data["type"])
	return attack_type == "HIGH" and defense_type == "crouch_block"

func _is_jump_action(action: String) -> bool:
	return action == "jump" or action == "jump_forward" or action == "jump_back" or action == "neutral_jump"

func _apply_jump_in_movement() -> void:
	movement_system.apply_jump_in_movement()

func _move_player_by_card(card: Resource) -> void:
	movement_system.move_player_by_card(card)

func _move_player_toward_enemy(amount: float) -> void:
	movement_system.move_player_toward_enemy(amount)

func _move_player_away_from_enemy(amount: float) -> void:
	movement_system.move_player_away_from_enemy(amount)

func _direction_to_enemy() -> float:
	return movement_system.direction_to_enemy()

func _direction_to_player() -> float:
	return movement_system.direction_to_player()

func _apply_card_spacing(card: Resource) -> void:
	movement_system.apply_card_spacing(card)

func _check_combo_route_drying_out() -> void:
	if can_play_cards() and not _has_valid_card_for_current_state():
		log_message.emit("Combo route drying out.")
		_change_frame_advantage(-frame_advantage)

func _on_enemy_break_started() -> void:
	frame_advantage = maxi(frame_advantage + stance_break_frame_bonus, stance_break_frame_bonus)
	enemy_vulnerable_frames_remaining = maxi(enemy_vulnerable_frames_remaining + stance_break_frame_bonus, stance_break_frame_bonus)
	frame_advantage_changed.emit(frame_advantage)
	log_message.emit("Stance break! Punish window opened: +%d frame advantage." % stance_break_frame_bonus)
	_update_time_scale()

func _on_enemy_break_ended() -> void:
	if frame_advantage <= 0:
		frame_advantage = 0
		enemy_vulnerable_frames_remaining = 0
		_reset_pressure_sequence()
		frame_advantage_changed.emit(frame_advantage)
		log_message.emit("Enemy recovered from stance break. Reset to neutral.")
		_schedule_enemy_if_needed()
	else:
		log_message.emit("Enemy recovered from stance break. Pressure continues.")
	_update_time_scale()

func _is_enemy_broken() -> bool:
	return stance_system.is_broken()

func _enemy_break_frames_remaining() -> int:
	return stance_system.recovery_frames() if _is_enemy_broken() else 0

func _has_valid_card_for_current_state() -> bool:
	return route_system.has_valid_card(_is_enemy_broken())

func _reset_pressure_sequence() -> void:
	route_system.reset_pressure_sequence()
	_clear_attack_hitboxes()

func _card_has_tag(card: Resource, tag_name: String) -> bool:
	return route_system.card_has_tag(card, tag_name)

func _make_card_queue_action(index: int) -> Dictionary:
	return queue_resolver.card_snapshot(index, _is_enemy_broken())

func _card_from_snapshot(snapshot: Dictionary) -> Resource:
	return deck_manager.call("_card_from_snapshot", snapshot) as Resource

func _snapshot_debug_text(snapshot: Dictionary) -> String:
	return queue_resolver.snapshot_debug_text(snapshot)

func _warn_if_snapshot_changed(snapshot: Dictionary) -> void:
	if queue_resolver.warning_if_snapshot_changed(snapshot):
		log_message.emit("Warning: queued action changed name/id after being queued.")

func _is_card_instance_queued(card: Resource) -> bool:
	return queue_resolver.is_card_instance_queued(card)

func _on_follow_up_drawn(card_name: String) -> void:
	log_message.emit("Follow-up card drawn: %s." % card_name)
	log_message.emit("Queue contents after follow-up draw: %s." % get_queue_text())

func _on_follow_up_skipped(message: String) -> void:
	log_message.emit(message)
	log_message.emit("Queue contents after follow-up draw: %s." % get_queue_text())

func _log_stance_protection(amount: int) -> void:
	if amount > 0 and stance_system.protected():
		log_message.emit("Stance protected: ignored %d stance damage" % amount)

func _is_interrupt_card_index(index: int) -> bool:
	if index < 0 or index >= deck_manager.hand.size():
		return false
	var card: Resource = deck_manager.hand[index]
	return _card_has_tag(card, "interrupt") or _card_has_tag(card, "starter")

func _current_mode() -> String:
	if combat_over:
		return "Game Over"
	if punish_in_progress:
		return "Punish"
	if _is_enemy_broken():
		return "Stance Break"
	if waiting_for_defense:
		return "Enemy Intent"
	if frame_advantage > 0:
		return "Player Pressure"
	return "Neutral"

func get_queue_text() -> String:
	return queue_resolver.queue_text()

func _is_tactical_mode() -> bool:
	return not combat_over and (waiting_for_defense or _can_take_pressure_movement())

func _queue_tactical_action(action: Dictionary) -> void:
	if not queue_resolver.append(action):
		return
	log_message.emit("Queued: %s." % _queued_action_display_name(action))
	if action.get("type", "") == "CARD":
		log_message.emit("Card queued: %s #%d." % [action.get("display_name", "Unknown"), int(action.get("instance_id", 0))])
		log_message.emit("Queued snapshot content: %s." % _snapshot_debug_text(action))
	frame_advantage_changed.emit(frame_advantage)

func _pop_tactical_action() -> void:
	if queue_resolver.is_empty():
		return
	var action: Dictionary = queue_resolver.pop_back()
	log_message.emit("Removed queued action: %s." % _queued_action_display_name(action))
	frame_advantage_changed.emit(frame_advantage)

func _clear_tactical_queue() -> void:
	if queue_resolver.is_empty():
		return
	queue_resolver.clear()
	log_message.emit("Action queue cleared.")
	frame_advantage_changed.emit(frame_advantage)

func _execute_or_wait_tactical_queue() -> void:
	if queue_resolver.resolving:
		return
	queue_resolver.resolving = true
	queue_resolver.interrupted_by_trade = false
	if queue_resolver.is_empty():
		log_message.emit("Player waited.")
		if waiting_for_defense:
			await _resolve_enemy_intent("wait")
		elif _can_take_pressure_movement():
			_spend_pressure_frames(1)
		queue_resolver.resolving = false
		return

	while not queue_resolver.is_empty() and _is_tactical_mode():
		var action: Dictionary = queue_resolver.pop_front()
		await _resolve_queued_action(action)
		frame_advantage_changed.emit(frame_advantage)
		if queue_resolver.interrupted_by_trade:
			log_message.emit("Queue stopped after trade.")
			queue_resolver.clear()
			break
		await _pause_between_queued_actions()
	queue_resolver.resolving = false
	if not _is_tactical_mode():
		queue_resolver.clear()

func _resolve_queued_action(action: Dictionary) -> void:
	if action.get("type", "") == "CARD":
		_clear_attack_hitboxes()
		log_message.emit("Action snapshot executed: %s." % _snapshot_debug_text(action))
		_warn_if_snapshot_changed(action)
		if waiting_for_defense:
			await _try_interrupt_with_card_snapshot(action)
		elif _can_take_pressure_movement():
			_resolve_pressure_card_snapshot(action)
		return

	var combat_action := _combat_action_from_queued_action(String(action.get("type", "")))
	if combat_action == "":
		return
	if waiting_for_defense:
		await _resolve_enemy_intent(combat_action)
	elif _can_take_pressure_movement():
		_apply_pressure_movement(combat_action)

func _pause_between_queued_actions() -> void:
	if queue_resolver.is_empty():
		return
	await get_tree().create_timer(0.2, true, false, true).timeout
	_clear_attack_hitboxes()

func _queued_action_from_key(keycode: Key) -> Dictionary:
	match keycode:
		KEY_A:
			return {"type": "STEP_BACK"}
		KEY_D:
			return {"type": "STEP_FORWARD"}
		KEY_L:
			return {"type": "BACKSTEP"}
		KEY_J:
			return {"type": "BLOCK"}
		KEY_K:
			return {"type": "CROUCH_BLOCK"}
		KEY_SPACE:
			if Input.is_key_pressed(KEY_D):
				return {"type": "JUMP_FORWARD"}
			if Input.is_key_pressed(KEY_A):
				return {"type": "JUMP_BACK"}
			return {"type": "NEUTRAL_JUMP"}
		_:
			return {}

func _combat_action_from_queued_action(action: String) -> String:
	match action:
		"STEP_FORWARD":
			return "step_forward"
		"STEP_BACK":
			return "step_back"
		"JUMP_FORWARD":
			return "jump_forward"
		"JUMP_BACK":
			return "jump_back"
		"NEUTRAL_JUMP":
			return "neutral_jump"
		"BACKSTEP":
			return "backstep"
		"BLOCK":
			return "block"
		"CROUCH_BLOCK":
			return "crouch_block"
		_:
			return ""

func _queued_action_display_name(action: Dictionary) -> String:
	return queue_resolver.queued_action_display_name(action)

func _can_take_pressure_movement() -> bool:
	return not combat_over and not waiting_for_defense and not attack_in_progress and (frame_advantage > 0 or _enemy_break_frames_remaining() > 0)

func _pressure_movement_from_key(keycode: Key) -> String:
	match keycode:
		KEY_A:
			return "step_back"
		KEY_D:
			return "step_forward"
		KEY_L:
			return "backstep"
		KEY_SPACE:
			return "jump"
		_:
			return ""

func _schedule_enemy_if_needed() -> void:
	if enemy_intent_scheduled or combat_over or attack_in_progress or waiting_for_defense or frame_advantage > 0 or punish_in_progress:
		return
	enemy_intent_scheduled = true
	await get_tree().create_timer(0.3, true, false, true).timeout
	enemy_intent_scheduled = false
	if combat_over or player.hp <= 0 or enemy.hp <= 0:
		return
	if _current_mode() != "Neutral":
		return
	_run_enemy_attack()

func _update_time_scale() -> void:
	if combat_over:
		Engine.time_scale = 1.0
		return

	player.set_free_movement_enabled(false)
	if waiting_for_defense:
		Engine.time_scale = ENEMY_INTENT_TIME_SCALE
	else:
		Engine.time_scale = PLAYER_CHOICE_TIME_SCALE if can_play_cards() else 1.0

func _end_combat(message: String) -> void:
	combat_over = true
	waiting_for_defense = false
	attack_in_progress = false
	punish_in_progress = false
	enemy_intent_scheduled = false
	current_enemy_intent = ""
	enemy_base_startup_frame = 0
	enemy_effective_startup_frame = 0
	remaining_startup_frames = 0
	initiative_offset = 0
	enemy_vulnerable_frames_remaining = 0
	queue_resolver.clear()
	player.set_input_enabled(true)
	player.set_free_movement_enabled(true)
	if enemy.has_method("clear_intent"):
		enemy.clear_intent()
	_clear_attack_hitboxes()
	Engine.time_scale = 1.0
	log_message.emit(message)

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _defense_display_name(defense_type: String) -> String:
	match defense_type:
		"crouch_block":
			return "crouch block"
		"step_back":
			return "step back"
		"step_forward":
			return "step forward"
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
		KEY_U:
			return "wait"
		KEY_A:
			return "step_back"
		KEY_D:
			return "step_forward"
		_:
			return ""
