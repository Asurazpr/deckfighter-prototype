class_name CombatManagerCore
extends Node

signal frame_advantage_changed(value: int)
signal log_message(message: String)

enum CombatFlowState { NEUTRAL, SLOW_NEUTRAL, PLANNING, EXECUTING_QUEUE, PLAYER_PRESSURE, ENEMY_INTENT, REACTION_WINDOW, DEFENSE_REACTION, STANCE_BREAK, PUNISH, GAME_OVER }

const ATTACK_RECOVERY := 0.35
const PLAYER_CHOICE_TIME_SCALE := 0.2
const NEUTRAL_SLOW_TIME_SCALE := 0.35
const ENEMY_INTENT_TIME_SCALE := 0.15
const PERFECT_BLOCK_HITSTOP := 0.12
const PERFECT_BLOCK_REACTION_PROGRESS := 0.85
const REACTION_GUARD_STARTUP_FRAMES := 4
const HitboxDebugDrawScript := preload("res://scripts/hitbox_debug_draw.gd")
const CombatClockScript := preload("res://scripts/combat/combat_clock.gd")
const FrameSystemScript := preload("res://scripts/combat/frame_system.gd")
const QueueResolverScript := preload("res://scripts/combat/queue_resolver.gd")
const RouteSystemScript := preload("res://scripts/combat/route_system.gd")
const MovementSystemScript := preload("res://scripts/combat/movement_system.gd")
const HitboxSystemScript := preload("res://scripts/combat/hitbox_system.gd")
const TradeSystemScript := preload("res://scripts/combat/trade_system.gd")
const StanceSystemScript := preload("res://scripts/combat/stance_system.gd")
const EnemyAISystemScript := preload("res://scripts/combat/enemy_ai_system.gd")
const CombatTimelineScript := preload("res://scripts/combat/combat_timeline.gd")
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
@export var live_neutral_player_speed := 140.0
@export var live_neutral_enemy_speed := 70.0
@export var enemy_intent_range := 95.0
@export var slow_neutral_intent_delay := 1.2

var frame_advantage := 0
var last_defense := ""
var attack_in_progress := false
var waiting_for_defense := false
var combat_over := false
var punish_in_progress := false
var enemy_intent_scheduled := false
var combat_state := CombatFlowState.NEUTRAL
var reaction_window_active := false
var reaction_window_resolving := false
var reaction_total_seconds := 0.0
var reaction_remaining_seconds := 0.0
var selected_defense_type := ""
var defense_input_progress := -1.0
var current_guard_input := ""
var guard_start_elapsed_frame := -1
var guard_startup_frames_remaining := 0
var guard_active := false
var correct_defense_became_active_progress := -1.0
var impact_resolution_text := "None"
var slow_neutral_active := false
var enemy_approach_active := false
var player_live_movement_active := false
var last_player_live_movement_active := false
var last_enemy_approach_active := false
var slow_neutral_elapsed := 0.0
var last_distance := 0.0
var distance_change_rate := 0.0
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
var enemy_ai_system
var combat_timeline

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
	enemy_ai_system = EnemyAISystemScript.new()
	enemy_ai_system.setup(self, enemy, frame_system)
	combat_timeline = CombatTimelineScript.new()

func _begin_combat() -> void:
	deck_manager.start_combat()
	last_distance = _distance_between_fighters()
	_enter_slow_neutral("Slow neutral movement started.")
	frame_advantage_changed.emit(frame_advantage)
	_log_architecture_validation()
	log_message.emit("Duel start. Read the enemy intent.")

func _log_architecture_validation() -> void:
	var active_path: String = get_script().resource_path
	var legacy_present := ResourceLoader.exists("res://scripts/combat_manager.gd")
	log_message.emit("Active combat manager: %s (CombatManagerCore)." % active_path)
	log_message.emit("Loaded combat systems: CombatClock, CombatTimeline, FrameSystem, QueueResolver, RouteSystem, MovementSystem, HitboxSystem, TradeSystem, StanceSystem, EnemyAISystem.")
	log_message.emit("Legacy combat manager present: %s." % str(legacy_present))

func _process(_delta: float) -> void:
	if combat_over:
		return
	_clamp_duel_distance()
	_tick_debug_hitboxes(_delta)
	_tick_reaction_window(_delta)
	_tick_slow_neutral(_delta)

	if player.hp <= 0:
		_end_combat("Player defeated.")
	elif enemy.hp <= 0:
		_end_combat("Enemy defeated.")

func get_debug_text() -> String:
	return "Distance: %.0f\nEnemy intent: %s\nEnemy base startup: %d\nEnemy effective startup: %d\nEnemy remaining startup: %d\nLast player startup: %d\nEnemy vulnerable frames: %d\nInitiative Offset: %s\nStance State: %s\nStance Recovery Frames: %d\nStance Break Stun Remaining: %d\nStance Protected: %s\n%s\n%s\nMode: %s" % [
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
		enemy_ai_system.debug_text(),
		_current_mode()
	]

func get_main_hud_debug_text() -> String:
	return "Distance: %.0f\nMode: %s\n%s" % [
		_distance_between_fighters(),
		_current_mode(),
		get_queue_text()
	]

func get_timing_debug_text() -> String:
	return "Enemy base startup: %d\nEnemy effective startup: %d\nEnemy remaining startup: %d\nLast player startup: %d\nEnemy vulnerable frames: %d\nInitiative Offset: %s\nStance State: %s\nStance Recovery Frames: %d\nStance Break Stun Remaining: %d\nStance Protected: %s\nMovement Mode: %s\nTime Mode: %s\nCurrent Time Scale: %.2f\nPlayer Live Movement Active: %s\nEnemy Approach Active: %s\nDistance Change Rate: %.1f px/s\nReaction Defense Mode: LIVE\nReaction Window Active: %s\nReaction Total Seconds: %.2f\nReaction Remaining Seconds: %.2f\nReaction Progress: %d%%\nCurrent Guard Input: %s\nGuard Startup Frames Remaining: %d\nGuard Active: %s\nCorrect Defense Became Active At: %s\nDefense Input Progress: %s\nPerfect Window Active: %s\nImpact Resolution: %s\n%s\nEnemy incoming hit level: %s" % [
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
		_movement_mode_text(),
		_time_mode_text(),
		Engine.time_scale,
		str(player_live_movement_active),
		str(enemy_approach_active),
		distance_change_rate,
		str(reaction_window_active),
		reaction_total_seconds,
		reaction_remaining_seconds,
		int(round(_reaction_progress() * 100.0)),
		_defense_display_name(current_guard_input) if current_guard_input != "" else "None",
		int(ceil(guard_startup_frames_remaining)),
		str(guard_active),
		("%d%%" % int(round(correct_defense_became_active_progress * 100.0))) if correct_defense_became_active_progress >= 0.0 else "None",
		("%d%%" % int(round(defense_input_progress * 100.0))) if defense_input_progress >= 0.0 else "None",
		str(_perfect_block_window_active()),
		impact_resolution_text,
		combat_timeline.debug_text(remaining_startup_frames),
		current_enemy_intent if current_enemy_intent != "" else "None"
	]

func get_enemy_ai_debug_text() -> String:
	return enemy_ai_system.debug_text()

func get_impact_bar_data() -> Dictionary:
	if not waiting_for_defense or current_enemy_intent == "":
		return {"visible": false, "progress": 0.0, "hit_level": "None", "action": "None"}
	var progress := _reaction_progress() if reaction_window_active else 0.0
	if not reaction_window_active and enemy_effective_startup_frame > 0:
		progress = clampf(1.0 - (float(maxi(0, remaining_startup_frames)) / float(enemy_effective_startup_frame)), 0.0, 1.0)
	return {
		"visible": true,
		"progress": progress,
		"hit_level": current_enemy_intent,
		"action": combat_timeline.action_name,
		"perfect_window": progress >= PERFECT_BLOCK_REACTION_PROGRESS
	}

func can_play_cards() -> bool:
	if reaction_window_active:
		return false
	return (waiting_for_defense or ((frame_advantage > 0 or _enemy_break_frames_remaining() > 0) and not attack_in_progress)) and not combat_over

func is_hand_card_playable(index: int) -> bool:
	if reaction_window_active:
		return false
	if slow_neutral_active:
		return index >= 0 and index < deck_manager.hand.size() and not _is_card_instance_queued(deck_manager.hand[index])
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
	if reaction_window_active:
		log_message.emit("Defense is live input during reaction window.")
		return

	if slow_neutral_active and not queue_resolver.resolving:
		_queue_tactical_action(_make_card_queue_action(index))
		log_message.emit("Player queued action during movement.")
		return

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

	if slow_neutral_active:
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

	if reaction_window_active:
		if key_event.keycode == KEY_F1 or key_event.keycode == KEY_F2 or key_event.keycode == KEY_F3 or key_event.keycode == KEY_F4:
			return
		get_viewport().set_input_as_handled()
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

func _run_enemy_attack(start_reaction := true) -> void:
	if combat_over or frame_advantage > 0 or attack_in_progress:
		return

	_exit_slow_neutral()
	var ai_context := _enemy_ai_context(initiative_offset)
	var ai_decision: Dictionary = enemy_ai_system.choose_intent(ai_context)
	_log_enemy_ai_decision(ai_decision)
	if ai_decision.is_empty():
		if enemy.can_act() and enemy_ai_system.last_state == "DEFENSIVE_REACTION":
			_enemy_approach_or_wait()
		return

	attack_in_progress = true
	waiting_for_defense = true
	last_defense = ""
	if start_reaction:
		queue_resolver.clear()
	_reset_pressure_sequence()
	enemy.start_attack(String(ai_decision.get("action_id", "")))
	current_enemy_intent = enemy.current_attack
	enemy_base_startup_frame = int(Enemy.ATTACKS[current_enemy_intent]["startup_frame"])
	enemy_effective_startup_frame = int(ai_decision.get("effective_startup", frame_system.effective_startup(enemy_base_startup_frame, initiative_offset)))
	if initiative_offset != 0:
		log_message.emit("Enemy next startup modified by %s." % _signed_int(initiative_offset))
	initiative_offset = 0
	remaining_startup_frames = enemy_effective_startup_frame
	combat_timeline.begin_from_enemy_attack(current_enemy_intent, Enemy.ATTACKS[current_enemy_intent], enemy_effective_startup_frame)
	_show_enemy_timeline_phase()
	if start_reaction:
		_start_reaction_window(current_enemy_intent, enemy_effective_startup_frame)
	last_player_action_startup = 0
	_clear_attack_hitboxes()
	player.set_free_movement_enabled(false)
	log_message.emit("Enemy intent: %s." % enemy.current_attack)
	log_message.emit("Slow time: react before impact." if start_reaction else "Enemy intent opened for queued action.")
	frame_advantage_changed.emit(frame_advantage)
	_update_time_scale()

func _enemy_ai_context(pending_initiative_offset: int) -> Dictionary:
	return {
		"combat_over": combat_over,
		"distance": _distance_between_fighters(),
		"initiative_offset": pending_initiative_offset,
		"player_frame_delta": pending_initiative_offset,
		"frame_advantage": frame_advantage,
		"player_has_pressure": frame_advantage > 0,
		"queue_resolving": queue_resolver.resolving,
		"stance_state": stance_system.state_name(),
		"stance_protected": stance_system.protected(),
		"stance_recovery_frames": stance_system.recovery_frames(),
		"enemy_in_recovery": attack_in_progress or punish_in_progress,
		"player_airborne": player.global_position.y < 588.0
	}

func _pressure_ai_context(extra := {}) -> Dictionary:
	var context := _enemy_ai_context(initiative_offset)
	context["player_has_pressure"] = true
	for key in extra.keys():
		context[key] = extra[key]
	return context

func _log_enemy_ai_decision(decision: Dictionary) -> void:
	log_message.emit("Enemy state: %s." % enemy_ai_system.last_state)
	if decision.is_empty():
		log_message.emit("Enemy cannot act: %s." % enemy_ai_system.last_reason)
		return
	var punish_candidates: Array = decision.get("punish_candidates", []) as Array
	log_message.emit("Enemy AI player frame delta: %s." % _signed_int(initiative_offset))
	log_message.emit("Enemy AI punish candidates: %s." % (", ".join(punish_candidates) if not punish_candidates.is_empty() else "None"))
	log_message.emit("Enemy chose %s: score %.1f." % [decision.get("action_id", "None"), float(decision.get("score", 0.0))])
	log_message.emit("Enemy effective startup: %df. Spacing: %s." % [int(decision.get("effective_startup", 0)), decision.get("spacing", "unchecked")])
	log_message.emit("Enemy AI reason: %s." % decision.get("reason", "No reason."))
	log_message.emit("Enemy profile: %s phase %s; %s." % [enemy_ai_system.intent_profile.get("tier", "NORMAL"), enemy_ai_system.boss_phase_id, enemy_ai_system.last_profile_modifiers])

func _enemy_approach_or_wait() -> void:
	_enter_slow_neutral("Slow neutral movement started.")

func _enter_slow_neutral(message := "") -> void:
	if combat_over or attack_in_progress or waiting_for_defense or punish_in_progress or frame_advantage > 0:
		return
	var was_active := slow_neutral_active
	slow_neutral_active = true
	slow_neutral_elapsed = 0.0 if not was_active else slow_neutral_elapsed
	last_distance = _distance_between_fighters()
	player.set_free_movement_enabled(true)
	Engine.time_scale = NEUTRAL_SLOW_TIME_SCALE
	if message != "" and not was_active:
		log_message.emit(message)

func _exit_slow_neutral() -> void:
	if slow_neutral_active:
		slow_neutral_active = false
		player_live_movement_active = false
		enemy_approach_active = false
		last_player_live_movement_active = false
		last_enemy_approach_active = false
	player.set_free_movement_enabled(false)

func _tick_slow_neutral(delta: float) -> void:
	if not slow_neutral_active or combat_over:
		return
	if attack_in_progress or waiting_for_defense or reaction_window_active or punish_in_progress or frame_advantage > 0:
		_exit_slow_neutral()
		return

	var combat_delta := delta
	slow_neutral_elapsed += combat_delta
	var previous_distance := _distance_between_fighters()
	player_live_movement_active = Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D)
	_apply_live_neutral_player_movement(combat_delta)
	_apply_live_neutral_enemy_movement(combat_delta)
	_clamp_duel_distance()
	var current_distance := _distance_between_fighters()
	distance_change_rate = (current_distance - previous_distance) / maxf(combat_delta, 0.001)
	last_distance = current_distance
	_log_slow_neutral_state_changes()

	if current_distance <= enemy_intent_range and slow_neutral_elapsed >= slow_neutral_intent_delay:
		_run_enemy_attack()

func _apply_live_neutral_player_movement(real_delta: float) -> void:
	var direction := 0.0
	if Input.is_key_pressed(KEY_A):
		direction -= 1.0
	if Input.is_key_pressed(KEY_D):
		direction += 1.0
	if direction == 0.0:
		return
	player.global_position.x += direction * live_neutral_player_speed * real_delta

func _apply_live_neutral_enemy_movement(real_delta: float) -> void:
	enemy_approach_active = _distance_between_fighters() > enemy_intent_range
	if not enemy_approach_active:
		return
	enemy.global_position.x += _direction_to_player() * live_neutral_enemy_speed * real_delta

func _log_slow_neutral_state_changes() -> void:
	if player_live_movement_active != last_player_live_movement_active:
		if player_live_movement_active:
			log_message.emit("Player live movement started.")
		last_player_live_movement_active = player_live_movement_active
	if enemy_approach_active != last_enemy_approach_active:
		if enemy_approach_active:
			log_message.emit("Enemy approaching.")
		last_enemy_approach_active = enemy_approach_active

func _movement_mode_text() -> String:
	if reaction_window_active:
		return "Reaction Locked"
	if queue_resolver != null and queue_resolver.resolving:
		return "Committed Queue"
	if slow_neutral_active:
		return "Live Slow Neutral"
	if frame_advantage > 0:
		return "Frame-Costed Pressure"
	return "Locked"

func _time_mode_text() -> String:
	if reaction_window_active:
		return "Reaction Slow"
	if slow_neutral_active:
		return "Slow Neutral"
	if can_play_cards():
		return "Player Choice Slow"
	return "Normal"

func startup_frames_to_reaction_seconds(startup_frames: int) -> float:
	return clampf(0.45 + float(startup_frames) * 0.28, 1.0, 5.0)

func _start_reaction_window(intent: String, startup_frames: int) -> void:
	reaction_window_active = true
	reaction_window_resolving = false
	reaction_total_seconds = startup_frames_to_reaction_seconds(startup_frames)
	reaction_remaining_seconds = reaction_total_seconds
	_reset_reaction_guard_state()
	impact_resolution_text = "Pending"
	log_message.emit("Reaction window started: %s, %.1fs." % [intent, reaction_total_seconds])

func _tick_reaction_window(delta: float) -> void:
	if not reaction_window_active or reaction_window_resolving or not waiting_for_defense:
		return
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	reaction_remaining_seconds = maxf(0.0, reaction_remaining_seconds - real_delta)
	var progress := _reaction_progress()
	var elapsed_startup_frames := int(floor(float(enemy_effective_startup_frame) * progress))
	remaining_startup_frames = maxi(0, enemy_effective_startup_frame - elapsed_startup_frames)
	_update_live_reaction_guard(elapsed_startup_frames, real_delta)
	if combat_timeline != null:
		combat_timeline.set_startup_progress(progress)
		_show_enemy_timeline_phase()
	if reaction_remaining_seconds <= 0.0:
		reaction_window_resolving = true
		call_deferred("_resolve_reaction_impact")

func _reaction_progress() -> float:
	if reaction_total_seconds <= 0.0:
		return 0.0
	return clampf(1.0 - (reaction_remaining_seconds / reaction_total_seconds), 0.0, 1.0)

func _perfect_block_window_active() -> bool:
	return reaction_window_active and _reaction_progress() >= PERFECT_BLOCK_REACTION_PROGRESS

func _reset_reaction_guard_state() -> void:
	selected_defense_type = ""
	defense_input_progress = -1.0
	current_guard_input = ""
	guard_start_elapsed_frame = -1
	guard_startup_frames_remaining = 0
	guard_active = false
	correct_defense_became_active_progress = -1.0

func _update_live_reaction_guard(elapsed_startup_frames: int, real_delta: float) -> void:
	var live_guard := _current_live_guard_input()
	if live_guard == "":
		if current_guard_input != "":
			log_message.emit("Guard released.")
		current_guard_input = ""
		selected_defense_type = ""
		defense_input_progress = -1.0
		guard_start_elapsed_frame = -1
		guard_startup_frames_remaining = 0
		guard_active = false
		correct_defense_became_active_progress = -1.0
		return

	if live_guard != current_guard_input:
		current_guard_input = live_guard
		selected_defense_type = live_guard
		defense_input_progress = _reaction_progress()
		guard_start_elapsed_frame = elapsed_startup_frames
		guard_startup_frames_remaining = REACTION_GUARD_STARTUP_FRAMES
		guard_active = false
		correct_defense_became_active_progress = -1.0
		log_message.emit("Guard startup began.")
		log_message.emit("Defense selected: %s at %d%%." % [_defense_display_name(live_guard), int(round(defense_input_progress * 100.0))])

	if guard_start_elapsed_frame >= 0:
		guard_startup_frames_remaining = maxf(0.0, guard_startup_frames_remaining - real_delta * 60.0)
		if not guard_active and guard_startup_frames_remaining <= 0:
			guard_active = true
			correct_defense_became_active_progress = _reaction_progress()
			log_message.emit("%s active." % ("Low block" if current_guard_input == "crouch_block" else "Stand block"))

	if guard_active:
		player.show_timeline_phase(current_guard_input, "ACTIVE", 1.0, current_enemy_intent, false)
	elif current_guard_input != "":
		var startup_progress := 1.0 - (float(guard_startup_frames_remaining) / float(REACTION_GUARD_STARTUP_FRAMES))
		player.show_timeline_phase(current_guard_input, "STARTUP", startup_progress, current_enemy_intent, false)

func _current_live_guard_input() -> String:
	if not Input.is_key_pressed(KEY_J):
		return ""
	return "crouch_block" if Input.is_key_pressed(KEY_S) else "block"

func _resolve_reaction_impact() -> void:
	if combat_over or not waiting_for_defense:
		reaction_window_active = false
		reaction_window_resolving = false
		return
	reaction_window_active = false
	remaining_startup_frames = 0
	if not guard_active or selected_defense_type == "":
		await _resolve_reaction_no_defense()
	else:
		await _resolve_reaction_block(selected_defense_type, defense_input_progress)
	reaction_window_resolving = false

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
		_begin_player_movement_timeline(defense_type, _action_startup(defense_type))
		_apply_intent_action_movement(defense_type)
		_clamp_duel_distance()
		_advance_enemy_startup(_action_startup(defense_type))
		if remaining_startup_frames <= 0:
			await _resolve_enemy_impact_after_countdown(defense_type)
		else:
			frame_advantage_changed.emit(frame_advantage)
		return

	if defense_type == "backstep" or _is_jump_action(defense_type):
		_begin_player_movement_timeline(defense_type, _action_startup(defense_type))
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
	_begin_player_movement_timeline(defense_type, block_startup)
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
			stance_system.apply_block_stance_damage(15)
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

func _resolve_reaction_no_defense() -> void:
	_begin_enemy_resolution()
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		_finish_enemy_resolution()
		return

	_set_enemy_attack_hitbox(_make_enemy_attack_hitbox(result))
	var enemy_attack_hits := last_enemy_attack_hitbox.intersects(get_player_hurtbox())
	if not enemy_attack_hits:
		log_message.emit("Enemy attack whiffed due to spacing.")
		log_message.emit("Impact resolved: whiff.")
		impact_resolution_text = "Whiff"
		_reset_pressure_sequence()
		_change_frame_advantage(1)
	else:
		player.take_damage(result["damage"])
		_set_frame_advantage_to_neutral()
		log_message.emit("Impact resolved: hit.")
		impact_resolution_text = "Hit"
	await _finish_enemy_resolution_after_recovery()

func _resolve_reaction_block(defense_type: String, input_progress: float) -> void:
	_begin_enemy_resolution()
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		_finish_enemy_resolution()
		return

	_set_enemy_attack_hitbox(_make_enemy_attack_hitbox(result))
	var enemy_attack_hits := last_enemy_attack_hitbox.intersects(get_player_hurtbox())
	if not enemy_attack_hits or _enemy_attack_whiffs_against_defense(defense_type, result):
		log_message.emit("Enemy attack whiffed due to spacing.")
		log_message.emit("Impact resolved: whiff.")
		impact_resolution_text = "Whiff"
		_reset_pressure_sequence()
		_change_frame_advantage(1)
	elif _defense_answers_attack(defense_type, result):
		if input_progress >= PERFECT_BLOCK_REACTION_PROGRESS:
			_reset_pressure_sequence()
			_change_frame_advantage(4)
			_log_stance_protection(15)
			stance_system.apply_block_stance_damage(15)
			log_message.emit("Perfect block window hit.")
			log_message.emit("PERFECT BLOCK")
			log_message.emit("Stance damage dealt: 15.")
			log_message.emit("Impact resolved: perfect block.")
			impact_resolution_text = "Perfect Block"
			player.show_state("PERFECT BLOCK", Color.GOLD)
			await _run_perfect_block_hitstop()
		else:
			_reset_pressure_sequence()
			_change_frame_advantage(2)
			log_message.emit("Normal block: too early for perfect.")
			log_message.emit("Impact resolved: normal block.")
			impact_resolution_text = "Normal Block"
	else:
		player.take_damage(result["damage"])
		_set_frame_advantage_to_neutral()
		log_message.emit("Defense failed.")
		log_message.emit("Impact resolved: hit.")
		impact_resolution_text = "Hit"

	await _finish_enemy_resolution_after_recovery()

func _begin_enemy_resolution() -> void:
	waiting_for_defense = false
	reaction_window_active = false
	Engine.time_scale = 1.0
	combat_timeline.mark_active()
	_show_enemy_timeline_phase()
	frame_advantage_changed.emit(frame_advantage)

func _finish_enemy_resolution() -> void:
	enemy.finish_attack()
	combat_timeline.finish_action()
	enemy.clear_timeline_visual()
	attack_in_progress = false
	player.set_free_movement_enabled(false)
	current_enemy_intent = ""
	enemy_base_startup_frame = 0
	enemy_effective_startup_frame = 0
	remaining_startup_frames = 0
	_update_time_scale()
	_enter_slow_neutral("Slow neutral movement started.")

func _finish_enemy_resolution_after_recovery() -> void:
	combat_timeline.mark_recovery()
	_show_enemy_timeline_phase()
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
	frame_advantage = frame_system.apply_tempo_delta(delta, frame_advantage)
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
	reaction_window_active = false
	reaction_window_resolving = false
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
	_enter_slow_neutral("Slow neutral movement started.")

func _run_perfect_block_hitstop() -> void:
	Engine.time_scale = 0.03
	await get_tree().create_timer(PERFECT_BLOCK_HITSTOP, true, false, true).timeout
	Engine.time_scale = 1.0
	_update_time_scale()

func _try_interrupt_with_card(index: int) -> void:
	if index < 0 or index >= deck_manager.hand.size():
		log_message.emit("Card not playable.")
		return

	reaction_window_active = false
	reaction_window_resolving = false
	var card: Resource = deck_manager.hand[index]
	last_player_action_startup = int(card.startup_frame)
	_begin_player_card_timeline(card)
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
	reaction_window_active = false
	reaction_window_resolving = false
	var card: Resource = _card_from_snapshot(snapshot)
	last_player_action_startup = int(card.startup_frame)
	_begin_player_card_timeline(card)
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
	stance_system.apply_hit(preview_card.damage, preview_card.stance_damage)
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
	stance_system.apply_hit(preview_card.damage, preview_card.stance_damage)
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
	reaction_window_active = false
	Engine.time_scale = 1.0
	frame_advantage_changed.emit(frame_advantage)
	if remaining_startup_frames > 0:
		remaining_startup_frames = 0
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		attack_in_progress = false
		player.set_free_movement_enabled(false)
		_update_time_scale()
		_enter_slow_neutral("Slow neutral movement started.")
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
	_enter_slow_neutral("Slow neutral movement started.")

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
	_begin_player_card_timeline(preview_card)
	_move_player_by_card(preview_card)
	_clamp_duel_distance()
	advance_combat_frames(int(preview_card.startup_frame))

	var repeat_info := _repeated_card_decay(preview_card)
	_log_enemy_pressure_reaction(preview_card, repeat_info)
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
	stance_system.apply_hit(card.damage, card.stance_damage)
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
	_begin_player_card_timeline(preview_card)
	_move_player_by_card(preview_card)
	_clamp_duel_distance()
	advance_combat_frames(int(preview_card.startup_frame))

	var repeat_info := _repeated_card_decay(preview_card)
	_log_enemy_pressure_reaction(preview_card, repeat_info)
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
	stance_system.apply_hit(card.damage, card.stance_damage)
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
	_begin_player_card_timeline(card)
	if apply_movement:
		_move_player_by_card(card)
	_clamp_duel_distance()
	if apply_movement:
		advance_combat_frames(int(card.startup_frame))

	var repeat_info := _repeated_card_decay(card)
	_log_enemy_pressure_reaction(card, repeat_info)
	var frame_delta: int = int(card.frame_gain) - int(card.frame_cost) + bonus_frame_advantage + int(repeat_info["penalty"])
	_set_player_attack_hitbox(_make_card_hitbox(card))
	if _card_needs_hitbox(card) and not _card_hitbox_hits_enemy(card):
		log_message.emit("Card whiffed: hitbox missed.")
		log_message.emit("No follow-up draw: card did not connect.")
		_resolve_card_frame_advantage(card.whiff_frame_penalty)
		return

	_log_stance_protection(card.stance_damage)
	stance_system.apply_hit(card.damage, card.stance_damage)
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

func _log_enemy_pressure_reaction(card: Resource, repeat_info: Dictionary) -> void:
	var reaction: Dictionary = enemy_ai_system.evaluate_pressure_reaction(card, _pressure_ai_context({
		"move_use_count": int(repeat_info.get("use_count", 1))
	}))
	log_message.emit("Enemy %s: %s" % [reaction.get("state", "DEFENSIVE_REACTION"), reaction.get("reason", "No reaction.")])

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
	if hitbox.size != Vector2.ZERO and combat_timeline.actor == "PLAYER":
		combat_timeline.mark_active()
		_show_player_timeline_phase()
	hitbox_system.set_player_attack_hitbox(hitbox)

func _set_enemy_attack_hitbox(hitbox: Rect2) -> void:
	if hitbox.size != Vector2.ZERO and combat_timeline.actor == "ENEMY":
		combat_timeline.mark_active()
		_show_enemy_timeline_phase()
	hitbox_system.set_enemy_attack_hitbox(hitbox)

func _clear_attack_hitboxes() -> void:
	if combat_timeline != null and combat_timeline.hitbox_active():
		combat_timeline.mark_recovery()
		_apply_timeline_visual()
	hitbox_system.clear_attack_hitboxes()

func _tick_debug_hitboxes(delta: float) -> void:
	hitbox_system.tick_debug_hitboxes(delta)

func _create_hitbox_debug_drawer() -> void:
	var debug_drawer := HitboxDebugDrawScript.new()
	debug_drawer.set("combat_manager", self)
	get_parent().call_deferred("add_child", debug_drawer)

func _begin_player_card_timeline(card: Resource) -> void:
	combat_timeline.begin_from_card(card)
	_show_player_timeline_phase()

func _begin_player_movement_timeline(action: String, cost: int) -> void:
	combat_timeline.begin_movement("PLAYER", _defense_display_name(action), cost)
	_show_player_timeline_phase()

func _show_player_timeline_phase() -> void:
	if player != null and player.has_method("show_timeline_phase"):
		player.show_timeline_phase(combat_timeline.action_name, combat_timeline.phase_name(), combat_timeline.phase_progress(), "", combat_timeline.hitbox_active())

func _show_enemy_timeline_phase() -> void:
	if enemy != null and enemy.has_method("show_timeline_phase"):
		enemy.show_timeline_phase(combat_timeline.action_name, combat_timeline.phase_name(), combat_timeline.phase_progress(), current_enemy_intent, combat_timeline.hitbox_active())

func _apply_timeline_visual() -> void:
	if combat_timeline == null:
		return
	if combat_timeline.actor == "PLAYER":
		_show_player_timeline_phase()
	elif combat_timeline.actor == "ENEMY":
		_show_enemy_timeline_phase()

func _clamp_duel_distance() -> void:
	movement_system.clamp_duel_distance()

func _clamped_player_x(player_x: float) -> float:
	return movement_system.clamped_player_x(player_x)

func _apply_intent_action_movement(action: String) -> void:
	movement_system.apply_intent_action_movement(action)

func _apply_pressure_movement(action: String) -> void:
	var cost := _action_startup(action)
	last_player_action_startup = cost
	_begin_player_movement_timeline(action, cost)
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
	if combat_timeline != null:
		combat_timeline.advance_frames(frames)
		_apply_timeline_visual()

func _spend_pressure_frames(cost: int) -> void:
	if cost <= 0:
		frame_advantage_changed.emit(frame_advantage)
		return

	var previous := frame_advantage
	var final_frame_advantage: int = frame_system.spend_pressure_frames(cost, frame_advantage)
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
		_enter_slow_neutral("Slow neutral movement started.")
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
	if stance_system.should_log_protected_damage(amount):
		log_message.emit("Stance protected: ignored %d stance damage" % amount)

func _is_interrupt_card_index(index: int) -> bool:
	if index < 0 or index >= deck_manager.hand.size():
		return false
	var card: Resource = deck_manager.hand[index]
	return _card_has_tag(card, "interrupt") or _card_has_tag(card, "starter")

func _current_mode() -> String:
	_refresh_combat_state()
	return _combat_state_name(combat_state)

func _refresh_combat_state() -> void:
	# TODO: Promote this derived enum into the authoritative combat state machine
	# once the remaining legacy mode flags have been untangled.
	if combat_over:
		combat_state = CombatFlowState.GAME_OVER
		return
	if punish_in_progress:
		combat_state = CombatFlowState.PUNISH
		return
	if _is_enemy_broken():
		combat_state = CombatFlowState.STANCE_BREAK
		return
	if reaction_window_active:
		combat_state = CombatFlowState.REACTION_WINDOW
		return
	if waiting_for_defense:
		combat_state = CombatFlowState.EXECUTING_QUEUE if queue_resolver != null and queue_resolver.resolving else CombatFlowState.ENEMY_INTENT
		return
	if frame_advantage > 0:
		combat_state = CombatFlowState.EXECUTING_QUEUE if queue_resolver != null and queue_resolver.resolving else CombatFlowState.PLAYER_PRESSURE
		return
	if slow_neutral_active:
		combat_state = CombatFlowState.SLOW_NEUTRAL
		return
	combat_state = CombatFlowState.NEUTRAL

func _combat_state_name(state_id: int) -> String:
	match state_id:
		CombatFlowState.NEUTRAL:
			return "Neutral"
		CombatFlowState.SLOW_NEUTRAL:
			return "Slow Neutral"
		CombatFlowState.PLANNING:
			return "Planning"
		CombatFlowState.EXECUTING_QUEUE:
			return "Executing Queue"
		CombatFlowState.PLAYER_PRESSURE:
			return "Player Pressure"
		CombatFlowState.ENEMY_INTENT:
			return "Enemy Intent"
		CombatFlowState.REACTION_WINDOW:
			return "Reaction Window"
		CombatFlowState.DEFENSE_REACTION:
			return "Defense Reaction"
		CombatFlowState.STANCE_BREAK:
			return "Stance Break"
		CombatFlowState.PUNISH:
			return "Punish"
		CombatFlowState.GAME_OVER:
			return "Game Over"
		_:
			return "Unknown"

func get_queue_text() -> String:
	return queue_resolver.queue_text()

func _is_tactical_mode() -> bool:
	return not combat_over and not reaction_window_active and (waiting_for_defense or _can_take_pressure_movement())

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
	if slow_neutral_active and queue_resolver.is_empty():
		log_message.emit("No queued action. Keep moving or queue a card.")
		return
	if slow_neutral_active:
		log_message.emit("Queue execution started.")
		await _execute_slow_neutral_queue()
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

func _execute_slow_neutral_queue() -> void:
	_exit_slow_neutral()
	_run_enemy_attack(false)
	if not waiting_for_defense:
		queue_resolver.clear()
		return
	queue_resolver.resolving = true
	queue_resolver.interrupted_by_trade = false
	while not queue_resolver.is_empty() and waiting_for_defense and not combat_over:
		var action: Dictionary = queue_resolver.pop_front()
		await _resolve_queued_action(action)
		frame_advantage_changed.emit(frame_advantage)
		if queue_resolver.interrupted_by_trade:
			log_message.emit("Queue stopped after trade.")
			queue_resolver.clear()
			break
		await _pause_between_queued_actions()
	queue_resolver.resolving = false
	if waiting_for_defense and not reaction_window_active and not combat_over:
		_start_reaction_window(current_enemy_intent, remaining_startup_frames)
		_update_time_scale()
	if not waiting_for_defense:
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
		KEY_S:
			if Input.is_key_pressed(KEY_J):
				return {"type": "CROUCH_BLOCK"}
			return {}
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
	_enter_slow_neutral("Slow neutral movement started.")

func _update_time_scale() -> void:
	if combat_over:
		Engine.time_scale = 1.0
		return

	if slow_neutral_active:
		player.set_free_movement_enabled(true)
		Engine.time_scale = NEUTRAL_SLOW_TIME_SCALE
		return

	player.set_free_movement_enabled(false)
	if waiting_for_defense:
		Engine.time_scale = ENEMY_INTENT_TIME_SCALE
	else:
		Engine.time_scale = PLAYER_CHOICE_TIME_SCALE if can_play_cards() else 1.0

func _end_combat(message: String) -> void:
	combat_over = true
	waiting_for_defense = false
	reaction_window_active = false
	reaction_window_resolving = false
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
	if combat_timeline != null:
		combat_timeline.finish_action()
	if player.has_method("clear_timeline_visual"):
		player.clear_timeline_visual()
	if enemy.has_method("clear_timeline_visual"):
		enemy.clear_timeline_visual()
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
			return "crouch_block" if Input.is_key_pressed(KEY_S) else "block"
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
