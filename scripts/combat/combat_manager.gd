class_name CombatManagerCore
extends Node

signal frame_advantage_changed(value: int)
signal log_message(message: String)

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
const ReactionWindowSystemScript := preload("res://scripts/combat/reaction_window_system.gd")
const MovementFlowSystemScript := preload("res://scripts/combat/movement_flow_system.gd")
const CombatStateMachineScript := preload("res://scripts/combat/combat_state_machine.gd")
const CombatInputRouterScript := preload("res://scripts/combat/combat_input_router.gd")
const ActorCombatStateScript := preload("res://scripts/combat/actor_combat_state.gd")
const ActionRequestScript := preload("res://scripts/combat/action_request.gd")
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
@export var defensive_reaction_wait_frames := 20
@export var max_defensive_reaction_retries := 3

var frame_advantage := 0
var last_defense := ""
var attack_in_progress := false
var waiting_for_defense := false
var combat_over := false
var fight_started := false
var punish_in_progress := false
var enemy_intent_scheduled := false
var combat_state := 0
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
var combat_frame_context := ""
var combat_trace_events: Array[Dictionary] = []
var defensive_reaction_retry_count := 0
var defensive_reaction_wait_remaining := 0.0
var defensive_reaction_fallback := "None"
var last_no_attack_reaches_reason := "None"
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
var reaction_window_system
var movement_flow_system
var combat_state_machine
var combat_input_router
var player_actor_state
var enemy_actor_state
var current_player_action_request
var current_enemy_action_request
var queued_action_in_progress := false
var last_state_repair_warning := ""
var player_trade_recovery_frames_remaining := 0.0
var enemy_trade_recovery_frames_remaining := 0.0
var pending_trade_followup_window := false

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
	reaction_window_system = ReactionWindowSystemScript.new()
	reaction_window_system.setup(self, player, PERFECT_BLOCK_REACTION_PROGRESS, REACTION_GUARD_STARTUP_FRAMES)
	movement_flow_system = MovementFlowSystemScript.new()
	movement_flow_system.setup(self, player, enemy, movement_system, NEUTRAL_SLOW_TIME_SCALE, live_neutral_player_speed, live_neutral_enemy_speed, enemy_intent_range, slow_neutral_intent_delay)
	combat_state_machine = CombatStateMachineScript.new()
	combat_state_machine.setup(CombatStateMachineScript.State.PRE_FIGHT)
	combat_input_router = CombatInputRouterScript.new()
	player_actor_state = ActorCombatStateScript.new()
	player_actor_state.setup("player")
	enemy_actor_state = ActorCombatStateScript.new()
	enemy_actor_state.setup("enemy")

func _begin_combat() -> void:
	deck_manager.start_combat()
	frame_advantage_changed.emit(frame_advantage)
	_log_architecture_validation()
	log_message.emit("Pre-fight. Inspect your deck, then press Start Fight.")

func start_fight() -> void:
	if fight_started or combat_over:
		return
	fight_started = true
	_transition_combat_state(CombatStateMachineScript.State.SLOW_NEUTRAL, "start fight")
	_enter_slow_neutral("Slow neutral movement started.")
	frame_advantage_changed.emit(frame_advantage)
	log_message.emit("Duel start. Read the enemy intent.")

func is_fight_started() -> bool:
	return fight_started

func _log_architecture_validation() -> void:
	var active_path: String = get_script().resource_path
	var legacy_present := ResourceLoader.exists("res://scripts/combat_manager.gd")
	log_message.emit("Active combat manager: %s (CombatManagerCore)." % active_path)
	log_message.emit("Loaded combat systems: CombatClock, CombatTimeline, FrameSystem, QueueResolver, RouteSystem, MovementSystem, MovementFlowSystem, HitboxSystem, TradeSystem, StanceSystem, EnemyAISystem, ReactionWindowSystem, CombatStateMachine, CombatInputRouter.")
	log_message.emit("Legacy combat manager present: %s." % str(legacy_present))

func _process(_delta: float) -> void:
	if combat_over:
		return
	_update_actor_combat_states()
	_repair_invalid_combat_state()
	_tick_trade_recovery(_delta)
	_execute_ready_queue_after_movement()
	_clamp_duel_distance()
	_tick_debug_hitboxes(_delta)
	_tick_reaction_window(_delta)
	_tick_slow_neutral(_delta)

	if player.hp <= 0:
		_end_combat("Player defeated.")
	elif enemy.hp <= 0:
		_end_combat("Enemy defeated.")

func get_debug_text() -> String:
	return "Distance: %.0f\nEnemy intent: %s\nEnemy base startup: %d\nEnemy effective startup: %d\nEnemy remaining startup: %d\nLast player startup: %d\nEnemy vulnerable frames: %d\nInitiative Offset: %s\nStance State: %s\nStance Recovery Frames: %d\nStance Break Stun Remaining: %d\nStance Protected: %s\n%s\n%s\nMode: %s\nPlayer: %s\nEnemy: %s\nLast Transition: %s" % [
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
		_current_mode(),
		player_actor_state.to_debug_text() if player_actor_state != null else "None",
		enemy_actor_state.to_debug_text() if enemy_actor_state != null else "None",
		combat_state_machine.last_transition if combat_state_machine != null else "None"
	]

func get_main_hud_debug_text() -> String:
	return "Distance: %.0f\nMode: %s\nPhase: %s\nActor: %s\n%s" % [
		_distance_between_fighters(),
		_current_mode(),
		combat_state_machine.current_phase_name(),
		combat_state_machine.current_actor(),
		get_queue_text()
	]

func get_timing_debug_text() -> String:
	return "Enemy base startup: %d\nEnemy effective startup: %d\nEnemy remaining startup: %d\nLast player startup: %d\nEnemy vulnerable frames: %d\nInitiative Offset: %s\nStance State: %s\nStance Recovery Frames: %d\nStance Break Stun Remaining: %d\nStance Protected: %s\nMovement Mode: %s\nTime Mode: %s\nCurrent Time Scale: %.2f\nPlayer Live Movement Active: %s\nEnemy Approach Active: %s\nDistance Change Rate: %.1f px/s\nCurrent Movement Phase: %s\nMovement Frames Remaining: %d\nMovement Direction: %s\nMovement Locked: %s\nCurrent Animation Pose: %s\nReaction Defense Mode: LIVE\nReaction Choice: %s\nReaction Window Active: %s\nReaction Total Seconds: %.2f\nReaction Remaining Seconds: %.2f\nReaction Progress: %d%%\nCurrent Guard Input: %s\nGuard Startup Frames Remaining: %d\nGuard Active: %s\nJump Startup Frames Remaining: %d\nJump Airborne: %s\nCorrect Defense Became Active At: %s\nDefense Input Progress: %s\nPerfect Window Active: %s\nImpact Resolution: %s\n%s\nEnemy incoming hit level: %s\nGlobal State: %s\nPlayer Actor: %s\nEnemy Actor: %s\nLast Transition: %s" % [
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
		str(movement_flow_system.player_live_movement_active),
		str(movement_flow_system.enemy_approach_active),
		movement_flow_system.distance_change_rate,
		movement_flow_system.movement_phase,
		int(ceil(movement_flow_system.movement_frames_remaining)),
		_movement_direction_text(movement_flow_system.movement_direction),
		str(movement_flow_system.movement_locked),
		movement_flow_system.movement_pose,
		reaction_window_system.reaction_choice,
		str(reaction_window_system.active),
		reaction_window_system.total_seconds,
		reaction_window_system.remaining_seconds,
		int(round(_reaction_progress() * 100.0)),
		_defense_display_name(reaction_window_system.current_guard_input) if reaction_window_system.current_guard_input != "" else "None",
		int(ceil(reaction_window_system.guard_startup_frames_remaining)),
		str(reaction_window_system.guard_active),
		int(ceil(reaction_window_system.jump_startup_frames_remaining)),
		str(reaction_window_system.jump_active),
		("%d%%" % int(round(reaction_window_system.correct_defense_became_active_progress * 100.0))) if reaction_window_system.correct_defense_became_active_progress >= 0.0 else "None",
		("%d%%" % int(round(reaction_window_system.defense_input_progress * 100.0))) if reaction_window_system.defense_input_progress >= 0.0 else "None",
		str(_perfect_block_window_active()),
		reaction_window_system.impact_resolution_text,
		combat_timeline.debug_text(remaining_startup_frames),
		current_enemy_intent if current_enemy_intent != "" else "None",
		_current_mode(),
		player_actor_state.to_debug_text() if player_actor_state != null else "None",
		enemy_actor_state.to_debug_text() if enemy_actor_state != null else "None",
		combat_state_machine.last_transition
	]

func get_enemy_ai_debug_text() -> String:
	return "%s\nEnemy Approach Target: %.0f\nClosest Move Range: %.0f\nNo-Reach Reason: %s\nDefensive Retries: %d/%d\nFallback: %s" % [
		enemy_ai_system.debug_text(),
		get_enemy_approach_target_distance(),
		_closest_enemy_attack_max_range(),
		last_no_attack_reaches_reason,
		defensive_reaction_retry_count,
		max_defensive_reaction_retries,
		defensive_reaction_fallback
	]

func get_combat_log_export_context() -> Dictionary:
	return {
		"timestamp": Time.get_datetime_string_from_system(),
		"combat_state": _current_mode(),
		"frame_advantage": frame_advantage,
		"distance": _distance_between_fighters(),
		"input_lock_state": _input_lock_state(),
		"input_rejected_reason": get_card_input_rejection_reason(0),
		"player_actor_state": player_actor_state.to_dict() if player_actor_state != null else {},
		"enemy_actor_state": enemy_actor_state.to_dict() if enemy_actor_state != null else {},
		"last_state_transition": combat_state_machine.last_transition,
		"player_animation": _animation_debug_for(player, "player"),
		"enemy_animation": _animation_debug_for(enemy, "enemy"),
		"reaction": _reaction_export_data(),
		"movement": _movement_export_data(),
		"enemy_ai": enemy_ai_system.debug_text(),
		"enemy_ai_state": enemy_ai_system.last_state,
		"enemy_ai_action": enemy_ai_system.last_chosen_action,
		"enemy_ai_reason": enemy_ai_system.last_reason,
		"enemy_ai_score": enemy_ai_system.last_score,
		"enemy_approach_end_reason": "reached_range" if movement_flow_system.last_distance <= enemy_intent_range else "approaching",
		"enemy_next_intent_evaluation": enemy_ai_system.last_reason,
		"enemy_approach_target_distance": get_enemy_approach_target_distance(),
		"closest_usable_move_range": _closest_enemy_attack_max_range(),
		"reason_no_attack_reaches": last_no_attack_reaches_reason,
		"defensive_reaction_retry_count": defensive_reaction_retry_count,
		"defensive_reaction_fallback": defensive_reaction_fallback,
		"stance_state": stance_system.state_name(),
		"stance_recovery_frames": stance_system.recovery_frames(),
		"stance_break_stun_frames": stance_system.break_stun_frames(),
		"stance_protected": stance_system.protected(),
		"reaction_window_active": reaction_window_system.active,
		"reaction_progress": reaction_window_system.progress(),
		"reaction_choice": reaction_window_system.reaction_choice,
		"reaction_remaining_seconds": reaction_window_system.remaining_seconds,
		"enemy_intent": current_enemy_intent,
		"enemy_remaining_startup": remaining_startup_frames,
		"queue": get_queue_text()
	}

func _input_lock_state() -> String:
	_repair_invalid_combat_state()
	if combat_over:
		return "game_over"
	if combat_state_machine != null and not combat_state_machine.can_accept_action_request(_player_card_action_request(), frame_advantage, not _player_action_locked()):
		return "state_machine:%s" % combat_state_machine.state_name()
	if _queue_is_resolving():
		return "queue_executing"
	if _is_reaction_window_state():
		return "live_defense_only"
	if _is_enemy_intent_state():
		return "enemy_intent"
	if _is_slow_neutral_state():
		return "slow_neutral_cards_allowed"
	if can_play_cards():
		return "cards_allowed"
	return "locked"

func get_combat_trace_events() -> Array:
	return combat_trace_events.duplicate(true)

func _record_combat_event(event_type: String, message := "", data := {}) -> void:
	var event: Dictionary = data.duplicate(true)
	event["event_type"] = event_type
	event["timestamp"] = Time.get_datetime_string_from_system()
	if message != "":
		event["message"] = message
	combat_trace_events.append(event)

func _animation_debug_for(actor: Node, actor_name: String) -> Dictionary:
	var data := {}
	if actor != null and actor.has_method("get_animation_debug"):
		data = actor.get_animation_debug()
	else:
		data = {
			"animation_key": "unknown",
			"pose_key": "unknown",
			"action_name": "unknown",
			"phase": "unknown",
			"phase_progress": null,
			"phase_frames_remaining": null,
			"active_frame_window": "unknown",
			"hitbox_active": null,
			"current_pose_name": "unknown",
			"movement_phase": "unknown",
			"movement_direction": "unknown",
			"rig_scale": null,
			"facing": "unknown"
		}
	data["actor"] = actor_name
	if actor_name == "player":
		data["movement_phase"] = movement_flow_system.movement_phase
		data["movement_direction"] = _movement_direction_text(movement_flow_system.movement_direction)
	elif actor_name == "enemy":
		data["movement_phase"] = movement_flow_system.enemy_movement_phase
		data["movement_direction"] = _movement_direction_text(_direction_to_player()) if movement_flow_system.enemy_approach_active else "None"
	if combat_timeline != null and combat_timeline.actor.to_lower() == actor_name:
		data["action_name"] = combat_timeline.action_name
		data["animation_key"] = combat_timeline.animation_key
		data["phase"] = combat_timeline.phase_name()
		data["phase_progress"] = combat_timeline.phase_progress()
		data["phase_frames_remaining"] = combat_timeline.phase_frames_remaining()
		data["active_frame_window"] = combat_timeline.active_window_text()
		data["hitbox_active"] = combat_timeline.hitbox_active()
	return _json_safe(data)

func _reaction_export_data() -> Dictionary:
	return {
		"active": reaction_window_system.active,
		"hit_level": current_enemy_intent if current_enemy_intent != "" else "None",
		"total_seconds": reaction_window_system.total_seconds,
		"remaining_seconds": reaction_window_system.remaining_seconds,
		"progress": reaction_window_system.progress(),
		"impact_bar_progress": 1.0 - reaction_window_system.progress(),
		"selected_defense": reaction_window_system.resolved_defense_type() if reaction_window_system.has_active_defense() else reaction_window_system.reaction_choice.to_lower(),
		"guard_startup_remaining": reaction_window_system.guard_startup_frames_remaining,
		"guard_active": reaction_window_system.guard_active,
		"defense_input_progress": reaction_window_system.defense_input_progress,
		"correct_defense_became_active_progress": reaction_window_system.correct_defense_became_active_progress,
		"perfect_window_active": _perfect_block_window_active(),
		"resolution": reaction_window_system.impact_resolution_text
	}

func _movement_export_data() -> Dictionary:
	return _json_safe({
		"time_mode": _time_mode_text(),
		"current_time_scale": Engine.time_scale,
		"player_live_movement_active": movement_flow_system.player_live_movement_active,
		"enemy_approach_active": movement_flow_system.enemy_approach_active,
		"distance": _distance_between_fighters(),
		"distance_change_rate": movement_flow_system.distance_change_rate,
		"enemy_approach_target_distance": movement_flow_system.approach_target_distance,
		"enemy_approach_end_reason": movement_flow_system.enemy_approach_end_reason,
		"defensive_reaction_retry_count": defensive_reaction_retry_count,
		"defensive_reaction_fallback": defensive_reaction_fallback,
		"player_movement_phase": movement_flow_system.movement_phase,
		"enemy_movement_phase": movement_flow_system.enemy_movement_phase,
		"player_position": player.global_position,
		"enemy_position": enemy.global_position
	})

func _json_safe(value):
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Dictionary:
		var output := {}
		for key in value.keys():
			output[str(key)] = _json_safe(value[key])
		return output
	if value is Array:
		var output_array := []
		for item in value:
			output_array.append(_json_safe(item))
		return output_array
	return value

func get_impact_bar_data() -> Dictionary:
	if not _is_enemy_intent_state() or current_enemy_intent == "":
		return {"visible": false, "progress": 0.0, "hit_level": "None", "action": "None"}
	var progress := _reaction_progress() if _is_reaction_window_state() else 0.0
	if not _is_reaction_window_state() and enemy_effective_startup_frame > 0:
		progress = clampf(1.0 - (float(maxi(0, remaining_startup_frames)) / float(enemy_effective_startup_frame)), 0.0, 1.0)
	return {
		"visible": true,
		"progress": progress,
		"hit_level": current_enemy_intent,
		"action": combat_timeline.action_name,
		"perfect_window": progress >= PERFECT_BLOCK_REACTION_PROGRESS
	}

func can_play_cards() -> bool:
	_repair_invalid_combat_state()
	if not fight_started:
		return false
	if _is_reaction_window_state():
		return false
	var state_allows: bool = combat_state_machine.can_accept_action_request(_player_card_action_request(), frame_advantage, not _player_action_locked()) if combat_state_machine != null else true
	return state_allows and (_is_enemy_intent_state() or _can_take_pressure_movement()) and not combat_over

func is_hand_card_playable(index: int) -> bool:
	_repair_invalid_combat_state()
	if not fight_started:
		return false
	if _player_action_locked():
		return false
	if combat_state_machine != null and not combat_state_machine.can_accept_action_request(_player_card_action_request(index), frame_advantage, true):
		return false
	if _is_reaction_window_state():
		return index >= 0 and index < deck_manager.hand.size() and not _is_card_instance_queued(deck_manager.hand[index])
	if _is_slow_neutral_state():
		return index >= 0 and index < deck_manager.hand.size() and not _is_card_instance_queued(deck_manager.hand[index])
	if _is_enemy_intent_state():
		return index >= 0 and index < deck_manager.hand.size() and not _is_card_instance_queued(deck_manager.hand[index])
	return can_play_cards() and index >= 0 and index < deck_manager.hand.size() and not _is_card_instance_queued(deck_manager.hand[index])

func get_card_input_rejection_reason(index: int) -> String:
	_repair_invalid_combat_state()
	if index < 0 or index >= deck_manager.hand.size():
		return "no hand card at index %d" % index
	if _is_card_instance_queued(deck_manager.hand[index]):
		return "card instance already queued"
	if combat_over:
		return "combat over"
	if not fight_started:
		return "fight has not started"
	if _queue_is_resolving():
		return "queue is already executing"
	if _player_action_locked():
		return "player action is still recovering (%s)" % _player_action_lock_reason()
	if combat_state_machine != null and not combat_state_machine.can_accept_action_request(_player_card_action_request(index), frame_advantage, true):
		return "state machine locked input: state=%s phase=%s actor=%s transition=%s frame_advantage=%d" % [
			combat_state_machine.state_name(),
			combat_state_machine.current_phase_name(),
			combat_state_machine.current_actor(),
			combat_state_machine.last_transition,
			frame_advantage
		]
	if _is_reaction_window_state():
		return ""
	if _is_slow_neutral_state():
		return ""
	if _is_enemy_intent_state():
		return ""
	if can_play_cards():
		return ""
	return "current state does not accept card input (%s frame_advantage=%d)" % [_player_action_lock_reason(), frame_advantage]

func get_card_prediction(index: int) -> String:
	if not show_prediction_assist:
		return "normal"
	if index < 0 or index >= deck_manager.hand.size():
		return "normal"
	if _is_enemy_intent_state():
		return _predict_enemy_intent_card_outcome(deck_manager.hand[index])
	if frame_advantage > 0 and _can_take_pressure_movement():
		return _predict_pressure_card_outcome(index, deck_manager.hand[index])
	return "normal"

func _player_card_action_request(index := -1):
	var card: Resource = null
	if index >= 0 and index < deck_manager.hand.size():
		card = deck_manager.hand[index]
	return ActionRequestScript.from_card("player", card, index, Engine.get_process_frames())

func _enemy_ai_action_request(action_id: String):
	var request := ActionRequestScript.new()
	request.actor_id = "enemy"
	request.action_id = action_id
	request.source_type = ActionRequestScript.SourceType.AI
	request.input_frame = Engine.get_process_frames()
	return request

func play_card(index: int) -> void:
	_repair_invalid_combat_state()
	if _player_action_locked():
		log_message.emit("Card input rejected: %s." % _player_action_lock_reason())
		return
	if _is_reaction_window_state():
		log_message.emit("Challenge attempt started.")
		await _try_interrupt_with_card(index)
		return

	if _is_slow_neutral_state() and not _queue_is_resolving():
		_queue_tactical_action(_make_card_queue_action(index))
		log_message.emit("Player queued action during movement.")
		return

	if _is_tactical_mode() and not _queue_is_resolving():
		_queue_tactical_action(_make_card_queue_action(index))
		return

	if _is_enemy_intent_state():
		await _try_interrupt_with_card(index)
		return

	if not can_play_cards():
		_change_frame_advantage(-1)
		log_message.emit("Bad timing. Dropped tempo.")
		return
	var route_valid: bool = deck_manager.is_card_route_valid(index, _is_enemy_broken())
	var preview_card: Resource = deck_manager.hand[index]
	var starts_new_route: bool = not route_valid and _card_has_tag(preview_card, "starter")
	await _resolve_pressure_card(index, route_valid, starts_new_route)

func _on_player_defense(defense_type: String) -> void:
	last_defense = defense_type
	if _is_enemy_intent_state():
		_resolve_enemy_intent(defense_type)

func _unhandled_key_input(event: InputEvent) -> void:
	combat_input_router.route_key_event(event, self, get_viewport())

func _run_enemy_attack(start_reaction := true) -> void:
	if combat_over or frame_advantage > 0 or combat_state_machine.is_enemy_flow_state():
		return
	if not fight_started:
		return

	_exit_slow_neutral()
	_transition_combat_state(CombatStateMachineScript.State.ENEMY_INTENT, "enemy intent selected")
	var approach_end_reason := "Enemy reached range" if _distance_between_fighters() <= enemy_intent_range else "Enemy evaluating from spacing"
	var ai_context := _enemy_ai_context(initiative_offset)
	var ai_decision: Dictionary = enemy_ai_system.choose_intent(ai_context)
	_log_enemy_ai_decision(ai_decision)
	if ai_decision.is_empty():
		if enemy.can_act() and enemy_ai_system.last_state == "DEFENSIVE_REACTION":
			var fallback_decision := _enemy_no_attack_fallback(approach_end_reason)
			if fallback_decision.is_empty():
				_enemy_approach_or_wait()
				return
			ai_decision = fallback_decision
		else:
			return

	defensive_reaction_retry_count = 0
	defensive_reaction_wait_remaining = 0.0
	defensive_reaction_fallback = "attack"
	attack_in_progress = true
	waiting_for_defense = true
	last_defense = ""
	if start_reaction:
		queue_resolver.clear()
	_reset_pressure_sequence()
	enemy.start_attack(String(ai_decision.get("action_id", "")))
	current_enemy_intent = enemy.current_attack
	current_enemy_action_request = _enemy_ai_action_request(current_enemy_intent)
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
		_transition_combat_state(CombatStateMachineScript.State.REACTION_WINDOW, "reaction window started")
	last_player_action_startup = 0
	_clear_attack_hitboxes()
	player.set_free_movement_enabled(false)
	log_message.emit("Enemy intent: %s." % enemy.current_attack)
	log_message.emit("%s; starting %s." % [approach_end_reason, enemy.current_attack])
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
		"queue_resolving": _queue_is_resolving(),
		"stance_state": stance_system.state_name(),
		"stance_protected": stance_system.protected(),
		"stance_recovery_frames": stance_system.recovery_frames(),
		"enemy_in_recovery": _enemy_has_active_recovery(),
		"enemy_recovery_frames": _enemy_recovery_frames_remaining(),
		"enemy_current_action": current_enemy_intent if current_enemy_intent != "" else "None",
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

func _enemy_no_attack_fallback(approach_end_reason: String) -> Dictionary:
	var distance := _distance_between_fighters()
	var closest_range := _closest_enemy_attack_max_range()
	last_no_attack_reaches_reason = "distance %.0f, closest usable move range %.0f" % [distance, closest_range]
	if distance > closest_range and defensive_reaction_retry_count < max_defensive_reaction_retries:
		defensive_reaction_retry_count += 1
		defensive_reaction_fallback = "continue_approach"
		log_message.emit("%s; no attack reaches. Continuing approach. Retry %d/%d." % [approach_end_reason, defensive_reaction_retry_count, max_defensive_reaction_retries])
		return {}

	var fallback_attack := _fallback_reachable_enemy_attack_id()
	if fallback_attack != "" and defensive_reaction_retry_count >= max_defensive_reaction_retries:
		defensive_reaction_fallback = "force_basic_poke:%s" % fallback_attack
		log_message.emit("Enemy defensive retries exhausted; forcing %s." % fallback_attack)
		var startup: int = frame_system.effective_startup(int(Enemy.ATTACKS[fallback_attack]["startup_frame"]), initiative_offset)
		return {
			"action_id": fallback_attack,
			"action": Enemy.ATTACKS[fallback_attack],
			"score": 1.0,
			"effective_startup": startup,
			"state": "PRESSURING",
			"reason": "fallback basic poke after defensive reaction retries",
			"spacing": last_no_attack_reaches_reason,
			"punish_candidates": []
		}

	defensive_reaction_retry_count += 1
	defensive_reaction_wait_remaining = float(defensive_reaction_wait_frames)
	defensive_reaction_fallback = "guard_wait"
	log_message.emit("%s; choosing guard wait for %df. Retry %d/%d." % [approach_end_reason, defensive_reaction_wait_frames, defensive_reaction_retry_count, max_defensive_reaction_retries])
	return {}

func _fallback_reachable_enemy_attack_id() -> String:
	var distance := _distance_between_fighters()
	for action_id in ["MID", "HIGH", "LOW", "OVERHEAD"]:
		if not Enemy.ATTACKS.has(action_id):
			continue
		var action: Dictionary = Enemy.ATTACKS[action_id]
		var range_min := float(action.get("range_min", 0.0))
		var range_max := float(action.get("range_max", action.get("range", 0.0)))
		if distance >= range_min and distance <= range_max:
			return action_id
	return ""

func _enemy_approach_or_wait() -> void:
	_enter_slow_neutral("Slow neutral movement started.")

func _enter_slow_neutral(message := "") -> void:
	if not fight_started:
		return
	if combat_over or combat_state_machine.is_enemy_flow_state() or _is_punish_state() or frame_advantage > 0:
		return
	_transition_combat_state(CombatStateMachineScript.State.SLOW_NEUTRAL, message)
	movement_flow_system.enter(message)

func _exit_slow_neutral() -> void:
	movement_flow_system.exit()

func _tick_slow_neutral(delta: float) -> void:
	if not _is_slow_neutral_state() or not _movement_flow_active() or combat_over:
		return
	if combat_state_machine.is_enemy_flow_state() or _is_punish_state() or frame_advantage > 0:
		_exit_slow_neutral()
		return

	var result: Dictionary = movement_flow_system.tick(delta)
	if bool(result.get("should_start_intent", false)):
		if defensive_reaction_wait_remaining > 0.0:
			defensive_reaction_wait_remaining = maxf(0.0, defensive_reaction_wait_remaining - delta * 60.0)
			return
		_run_enemy_attack()

func _movement_mode_text() -> String:
	return movement_flow_system.movement_mode_text(_is_reaction_window_state(), _queue_is_resolving(), frame_advantage)

func _time_mode_text() -> String:
	return movement_flow_system.time_mode_text(_is_reaction_window_state(), can_play_cards())

func _player_action_locked() -> bool:
	if player_trade_recovery_frames_remaining > 0.0:
		return true
	if player == null or not player.has_method("can_start_card_action"):
		return false
	if bool(player.can_start_card_action()):
		return false
	if not _player_has_real_action_lifecycle():
		_clear_stale_player_action()
		return false
	return true

func _player_action_lock_reason() -> String:
	if player_trade_recovery_frames_remaining > 0.0:
		return "trade recovery remaining=%df frame_advantage=%d" % [int(ceil(player_trade_recovery_frames_remaining)), frame_advantage]
	if player != null and player.has_method("card_action_rejection_reason"):
		return "%s frame_advantage=%d" % [String(player.card_action_rejection_reason()), frame_advantage]
	return "player action is still recovering"

func _open_player_followup_window(reason := "") -> void:
	if _player_has_stale_idle_lock():
		_clear_stale_player_action()
	if player != null and player.has_method("open_followup_window"):
		player.open_followup_window()
	_transition_combat_state(CombatStateMachineScript.State.PLAYER_RECOVERY, reason if reason != "" else "follow-up window")
	if reason != "":
		log_message.emit(reason)

func _begin_player_commitment() -> void:
	Engine.time_scale = 1.0

func _start_player_card_action(card: Resource) -> void:
	current_player_action_request = ActionRequestScript.from_card("player", card, -1, Engine.get_process_frames())
	if player != null and player.has_method("perform_card_action"):
		player.perform_card_action(card)

func _wait_for_player_hit_confirm(card: Resource) -> void:
	if player != null and player.has_method("wait_for_action_hit_confirm"):
		await player.wait_for_action_hit_confirm(card)

func get_enemy_approach_target_distance() -> float:
	var usable_range := _closest_enemy_attack_max_range()
	if usable_range <= 0.0:
		return enemy_intent_range
	return minf(enemy_intent_range, maxf(min_duel_distance, usable_range - 2.0))

func _closest_enemy_attack_max_range() -> float:
	var max_range := 0.0
	if enemy == null:
		return max_range
	for action_id in Enemy.ATTACKS.keys():
		var action: Dictionary = Enemy.ATTACKS[action_id]
		max_range = maxf(max_range, float(action.get("range_max", action.get("range", 0.0))))
	return max_range

func _movement_direction_text(direction: float) -> String:
	if direction > 0.0:
		return "Right"
	if direction < 0.0:
		return "Left"
	return "None"

func startup_frames_to_reaction_seconds(startup_frames: int) -> float:
	return reaction_window_system.startup_frames_to_reaction_seconds(startup_frames)

func _start_reaction_window(intent: String, startup_frames: int) -> void:
	reaction_window_system.start(intent, startup_frames)

func _tick_reaction_window(delta: float) -> void:
	if not _can_tick_reaction_window() or reaction_window_system.resolving:
		return
	var result: Dictionary = reaction_window_system.tick(delta, combat_state_machine.can_tick_reaction_window(), enemy_effective_startup_frame, current_enemy_intent)
	var progress := _reaction_progress()
	remaining_startup_frames = int(result.get("remaining_startup_frames", remaining_startup_frames))
	if combat_timeline != null:
		combat_timeline.set_startup_progress(progress)
		_show_enemy_timeline_phase()
	if bool(result.get("should_resolve", false)):
		call_deferred("_resolve_reaction_impact")

func _reaction_progress() -> float:
	return reaction_window_system.progress()

func _perfect_block_window_active() -> bool:
	return reaction_window_system.perfect_block_window_active()

func _reset_reaction_guard_state() -> void:
	reaction_window_system.reset_guard_state()

func _resolve_reaction_impact() -> void:
	if combat_over or not _is_reaction_window_state():
		reaction_window_system.deactivate()
		return
	reaction_window_system.deactivate()
	remaining_startup_frames = 0
	if not reaction_window_system.has_active_defense():
		await _resolve_reaction_no_defense()
	else:
		await _resolve_reaction_block(reaction_window_system.resolved_defense_type(), reaction_window_system.resolved_input_progress())
	reaction_window_system.resolving = false

func _resolve_enemy_intent(defense_type: String) -> void:
	if combat_over or not _is_enemy_intent_state():
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
			var stance_protected := _apply_block_stance_damage(15, "perfect_block")
			log_message.emit("Perfect block window hit.")
			log_message.emit("PERFECT BLOCK")
			if not stance_protected:
				log_message.emit("Stance damage dealt: 15.")
			else:
				log_message.emit("Perfect block dealt no stance damage due to protection.")
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

	_release_player_block_if_needed(defense_type)
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
		reaction_window_system.set_impact_resolution("Whiff")
		_reset_pressure_sequence()
		_change_frame_advantage(1)
	else:
		player.take_damage(result["damage"])
		_set_frame_advantage_to_neutral()
		log_message.emit("Impact resolved: hit.")
		reaction_window_system.set_impact_resolution("Hit")
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
		if String(result["type"]) == "LOW" and _is_jump_action(defense_type):
			log_message.emit("LOW sweep whiffed due to jump.")
		else:
			log_message.emit("Enemy attack whiffed due to spacing.")
		log_message.emit("Impact resolved: whiff.")
		reaction_window_system.set_impact_resolution("Whiff")
		_reset_pressure_sequence()
		_change_frame_advantage(1)
	elif _defense_answers_attack(defense_type, result):
		if input_progress >= PERFECT_BLOCK_REACTION_PROGRESS:
			_reset_pressure_sequence()
			_change_frame_advantage(4)
			var stance_protected := _apply_block_stance_damage(15, "perfect_block")
			log_message.emit("Perfect block window hit.")
			log_message.emit("PERFECT BLOCK")
			if not stance_protected:
				log_message.emit("Stance damage dealt: 15.")
			else:
				log_message.emit("Perfect block dealt no stance damage due to protection.")
			log_message.emit("Impact resolved: perfect block.")
			reaction_window_system.set_impact_resolution("Perfect Block")
			player.show_state("PERFECT BLOCK", Color.GOLD)
			await _run_perfect_block_hitstop()
		else:
			_reset_pressure_sequence()
			_change_frame_advantage(2)
			log_message.emit("Normal block: too early for perfect.")
			log_message.emit("Impact resolved: normal block.")
			reaction_window_system.set_impact_resolution("Normal Block")
	else:
		if String(result["type"]) == "LOW" and reaction_window_system.jump_started and not reaction_window_system.jump_active:
			log_message.emit("Jump too late; sweep hit.")
		player.take_damage(result["damage"])
		_set_frame_advantage_to_neutral()
		log_message.emit("Defense failed.")
		log_message.emit("Impact resolved: hit.")
		reaction_window_system.set_impact_resolution("Hit")

	_release_player_block_if_needed(defense_type)
	await _finish_enemy_resolution_after_recovery()

func _begin_enemy_resolution() -> void:
	_transition_combat_state(CombatStateMachineScript.State.ENEMY_ACTIVE, "enemy impact")
	waiting_for_defense = false
	reaction_window_system.deactivate()
	Engine.time_scale = 1.0
	combat_timeline.mark_active()
	_show_enemy_timeline_phase()
	frame_advantage_changed.emit(frame_advantage)

func _finish_enemy_resolution() -> void:
	enemy.finish_attack()
	current_enemy_action_request = null
	combat_timeline.finish_action()
	enemy.clear_timeline_visual()
	attack_in_progress = false
	player.set_free_movement_enabled(false)
	current_enemy_intent = ""
	enemy_base_startup_frame = 0
	enemy_effective_startup_frame = 0
	remaining_startup_frames = 0
	_update_time_scale()
	_transition_combat_state(CombatStateMachineScript.State.SLOW_NEUTRAL, "enemy recovery complete")
	_enter_slow_neutral("Slow neutral movement started.")

func _finish_enemy_resolution_after_recovery() -> void:
	_transition_combat_state(CombatStateMachineScript.State.ENEMY_RECOVERY, "enemy recovery")
	combat_timeline.mark_recovery()
	_show_enemy_timeline_phase()
	advance_combat_frames(int(round(ATTACK_RECOVERY * 60.0)))
	await get_tree().create_timer(ATTACK_RECOVERY).timeout
	_finish_enemy_resolution()

func _release_player_block_if_needed(defense_type: String) -> void:
	if defense_type != "block" and defense_type != "crouch_block":
		return
	if player != null and player.has_method("release_block_action"):
		player.release_block_action()

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
	_transition_combat_state(CombatStateMachineScript.State.NEUTRAL, "player pressure ended")
	current_player_action_request = null
	initiative_offset = initiative_result
	if initiative_result < 0:
		log_message.emit("Player ended unsafe at %d." % initiative_result)
		log_message.emit("Enemy next startup modified by %d." % initiative_result)
	frame_advantage = 0
	enemy_vulnerable_frames_remaining = 0
	player_trade_recovery_frames_remaining = 0.0
	enemy_trade_recovery_frames_remaining = 0.0
	pending_trade_followup_window = false
	queue_resolver.clear()
	waiting_for_defense = false
	reaction_window_system.deactivate()
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
	var return_state: int = combat_state_machine.current_state
	_transition_combat_state(CombatStateMachineScript.State.HITSTOP, "perfect block")
	Engine.time_scale = 0.03
	await get_tree().create_timer(PERFECT_BLOCK_HITSTOP, true, false, true).timeout
	Engine.time_scale = 1.0
	_transition_combat_state(return_state, "hitstop ended")
	_update_time_scale()

func _try_interrupt_with_card(index: int) -> void:
	_begin_player_commitment()
	if index < 0 or index >= deck_manager.hand.size():
		log_message.emit("Card not playable.")
		return

	reaction_window_system.start_challenge()
	reaction_window_system.deactivate()
	var card: Resource = deck_manager.hand[index]
	last_player_action_startup = int(card.startup_frame)
	log_message.emit("Player challenge startup: %d." % last_player_action_startup)
	log_message.emit("Enemy impact remaining: %d." % remaining_startup_frames)
	_start_player_card_action(card)
	_begin_player_card_timeline(card)
	var card_hits := _card_would_hit_enemy_after_movement(card)
	var enemy_startup_after_card := remaining_startup_frames - int(card.startup_frame)
	_advance_player_action_frames(int(card.startup_frame), false, false)

	if card_hits and absi(int(card.startup_frame) - remaining_startup_frames) <= 2:
		log_message.emit("Challenge trades.")
		_move_player_by_card(card)
		_clamp_duel_distance()
		await _wait_for_player_hit_confirm(card)
		_set_player_attack_hitbox(_make_card_hitbox(card))
		_resolve_intent_trade(index, card, enemy_startup_after_card)
		return

	if int(card.startup_frame) > remaining_startup_frames:
		log_message.emit("Challenge loses.")
		log_message.emit("Interrupt failed: too slow.")
		log_message.emit("No follow-up draw: card did not connect.")
		deck_manager.discard_card_unrestricted(index)
		_resolve_enemy_counter_hit(true)
		return
	if not card_hits:
		log_message.emit("Challenge loses.")
		_move_player_by_card(card)
		_clamp_duel_distance()
		await _wait_for_player_hit_confirm(card)
		_set_player_attack_hitbox(_make_card_hitbox(card))
		_complete_player_card_timeline(card)
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
	await _wait_for_player_hit_confirm(card)
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
	log_message.emit("Challenge wins.")
	await _resolve_player_card(card, 2, false, true, false, false, false)

func _try_interrupt_with_card_snapshot(snapshot: Dictionary) -> void:
	_begin_player_commitment()
	reaction_window_system.start_challenge()
	reaction_window_system.deactivate()
	var card: Resource = _card_from_snapshot(snapshot)
	last_player_action_startup = int(card.startup_frame)
	log_message.emit("Player challenge startup: %d." % last_player_action_startup)
	log_message.emit("Enemy impact remaining: %d." % remaining_startup_frames)
	_start_player_card_action(card)
	_begin_player_card_timeline(card)
	var card_hits := _card_would_hit_enemy_after_movement(card)
	var enemy_startup_after_card := remaining_startup_frames - int(card.startup_frame)
	_advance_player_action_frames(int(card.startup_frame), false, false)

	if card_hits and absi(int(card.startup_frame) - remaining_startup_frames) <= 2:
		log_message.emit("Challenge trades.")
		_move_player_by_card(card)
		_clamp_duel_distance()
		await _wait_for_player_hit_confirm(card)
		_set_player_attack_hitbox(_make_card_hitbox(card))
		_resolve_intent_trade_snapshot(snapshot, card, enemy_startup_after_card)
		return

	if int(card.startup_frame) > remaining_startup_frames:
		log_message.emit("Challenge loses.")
		log_message.emit("Interrupt failed: too slow.")
		log_message.emit("No follow-up draw: card did not connect.")
		deck_manager.discard_queued_card_snapshot(snapshot)
		_resolve_enemy_counter_hit(true)
		return
	if not card_hits:
		log_message.emit("Challenge loses.")
		_move_player_by_card(card)
		_clamp_duel_distance()
		await _wait_for_player_hit_confirm(card)
		_set_player_attack_hitbox(_make_card_hitbox(card))
		_complete_player_card_timeline(card)
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
	await _wait_for_player_hit_confirm(card)
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
	log_message.emit("Challenge wins.")
	await _resolve_player_card(played_card, 2, false, true, false, false, false)

func _resolve_intent_trade(index: int, preview_card: Resource, enemy_startup_after_card: int) -> void:
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		return

	waiting_for_defense = false
	attack_in_progress = false
	remaining_startup_frames = maxi(0, enemy_startup_after_card)
	Engine.time_scale = 1.0
	_set_enemy_attack_hitbox(_make_enemy_attack_hitbox(result))
	_apply_hit_stance_damage(preview_card, "trade")
	_complete_player_card_timeline(preview_card)
	player.take_damage(result["damage"])
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
	_apply_hit_stance_damage(preview_card, "trade_snapshot")
	_complete_player_card_timeline(preview_card)
	player.take_damage(result["damage"])
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
	reaction_window_system.deactivate()
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
	player_trade_recovery_frames_remaining = float(player_recovery)
	enemy_trade_recovery_frames_remaining = float(enemy_recovery)
	pending_trade_followup_window = post_trade_frame_advantage > 0
	log_message.emit("Trade recovery: player %df, enemy %df." % [player_recovery, enemy_recovery])
	log_message.emit("Post-trade frame advantage: %d." % post_trade_frame_advantage)
	_record_combat_event("trade", "Trade occurred.", {
		"player_recovery": player_recovery,
		"enemy_recovery": enemy_recovery,
		"post_trade_frame_advantage": post_trade_frame_advantage
	})
	if post_trade_frame_advantage > 0:
		frame_advantage = post_trade_frame_advantage
		enemy_vulnerable_frames_remaining = post_trade_frame_advantage
		frame_advantage_changed.emit(frame_advantage)
		_transition_combat_state(CombatStateMachineScript.State.PLAYER_RECOVERY, "trade recovery")
		_update_time_scale()
	else:
		pending_trade_followup_window = false
		end_player_pressure("Trade recovery favored enemy.", post_trade_frame_advantage)

func _resolve_pressure_card(index: int, route_valid: bool, starts_new_route: bool) -> void:
	_begin_player_commitment()
	if index < 0 or index >= deck_manager.hand.size():
		log_message.emit("Card not playable.")
		return

	var preview_card: Resource = deck_manager.hand[index]
	log_message.emit("Card played: %s." % preview_card.display_name)
	_start_player_card_action(preview_card)
	_begin_player_card_timeline(preview_card)
	_move_player_by_card(preview_card)
	_clamp_duel_distance()
	_advance_player_action_frames(int(preview_card.startup_frame))
	await _wait_for_player_hit_confirm(preview_card)

	var repeat_info := _repeated_card_decay(preview_card)
	_log_enemy_pressure_reaction(preview_card, repeat_info)
	var frame_delta: int = int(preview_card.frame_gain) - int(preview_card.frame_cost) + int(repeat_info["penalty"])
	_set_player_attack_hitbox(_make_card_hitbox(preview_card))
	if _card_needs_hitbox(preview_card) and not _card_hitbox_hits_enemy(preview_card):
		log_message.emit("Card whiffed: hitbox missed.")
		log_message.emit("No follow-up draw: card did not connect.")
		_record_card_action_event(preview_card, "whiff", "pressure_card")
		_complete_player_card_timeline(preview_card)
		deck_manager.discard_card_unrestricted(index)
		_resolve_card_frame_advantage(preview_card.whiff_frame_penalty)
		return

	var allow_follow_up := (route_valid or starts_new_route) and not bool(repeat_info["suppress_follow_up"])
	if (route_valid or starts_new_route) and not allow_follow_up:
		log_message.emit("No follow-up draw: repeated route decay.")
	var card: Resource = deck_manager.play_card_with_route_result(index, allow_follow_up and route_valid, allow_follow_up and starts_new_route)
	if card == null:
		return

	var stance_protected := _apply_hit_stance_damage(card, "pressure_card")
	_apply_card_spacing(card)
	_clamp_duel_distance()
	if card.id == "ground_smash":
		_set_player_attack_hitbox(Rect2())
	if allow_follow_up:
		log_message.emit("Follow-up draw triggered.")
	else:
		log_message.emit("Combo route broken.")
	_log_card_hit_summary(card, stance_protected)
	_record_card_action_event(card, "hit", "pressure_card")
	_complete_player_card_timeline(card)
	if bool(repeat_info["force_end"]):
		end_player_pressure("Repeated route exhausted.", mini(frame_delta, -1))
		return
	_resolve_card_frame_advantage(frame_delta)

func _resolve_pressure_card_snapshot(snapshot: Dictionary) -> void:
	_begin_player_commitment()
	var preview_card: Resource = _card_from_snapshot(snapshot)
	var route_valid := bool(snapshot.get("route_valid_at_queue", false))
	var starts_new_route := bool(snapshot.get("starts_new_route_at_queue", false))
	log_message.emit("Card played: %s." % preview_card.display_name)
	_start_player_card_action(preview_card)
	_begin_player_card_timeline(preview_card)
	_move_player_by_card(preview_card)
	_clamp_duel_distance()
	_advance_player_action_frames(int(preview_card.startup_frame))
	await _wait_for_player_hit_confirm(preview_card)

	var repeat_info := _repeated_card_decay(preview_card)
	_log_enemy_pressure_reaction(preview_card, repeat_info)
	var frame_delta: int = int(preview_card.frame_gain) - int(preview_card.frame_cost) + int(repeat_info["penalty"])
	_set_player_attack_hitbox(_make_card_hitbox(preview_card))
	if _card_needs_hitbox(preview_card) and not _card_hitbox_hits_enemy(preview_card):
		log_message.emit("Card whiffed: hitbox missed.")
		log_message.emit("No follow-up draw: card did not connect.")
		_record_card_action_event(preview_card, "whiff", "pressure_card_snapshot")
		_complete_player_card_timeline(preview_card)
		deck_manager.discard_queued_card_snapshot(snapshot)
		_resolve_card_frame_advantage(preview_card.whiff_frame_penalty)
		return

	var allow_follow_up := (route_valid or starts_new_route) and not bool(repeat_info["suppress_follow_up"])
	if (route_valid or starts_new_route) and not allow_follow_up:
		log_message.emit("No follow-up draw: repeated route decay.")
	var card: Resource = deck_manager.play_queued_card_snapshot(snapshot, allow_follow_up and route_valid, allow_follow_up and starts_new_route)
	var stance_protected := _apply_hit_stance_damage(card, "pressure_card_snapshot")
	_apply_card_spacing(card)
	_clamp_duel_distance()
	if card.id == "ground_smash":
		_set_player_attack_hitbox(Rect2())
	if allow_follow_up:
		log_message.emit("Follow-up draw triggered.")
	else:
		log_message.emit("Combo route broken.")
	_log_card_hit_summary(card, stance_protected)
	_record_card_action_event(card, "hit", "pressure_card_snapshot")
	_complete_player_card_timeline(card)
	if bool(repeat_info["force_end"]):
		end_player_pressure("Repeated route exhausted.", mini(frame_delta, -1))
		return
	_resolve_card_frame_advantage(frame_delta)

func _resolve_player_card(card: Resource, bonus_frame_advantage := 0, apply_movement := true, route_valid := true, starts_new_route := false, start_animation := true, wait_for_hit_confirm := true) -> void:
	_begin_player_commitment()
	log_message.emit("Card played: %s." % card.display_name)
	if start_animation:
		_start_player_card_action(card)
		_begin_player_card_timeline(card)
	if apply_movement:
		_move_player_by_card(card)
	_clamp_duel_distance()
	if apply_movement:
		_advance_player_action_frames(int(card.startup_frame))
	if wait_for_hit_confirm:
		await _wait_for_player_hit_confirm(card)

	var repeat_info := _repeated_card_decay(card)
	_log_enemy_pressure_reaction(card, repeat_info)
	var frame_delta: int = int(card.frame_gain) - int(card.frame_cost) + bonus_frame_advantage + int(repeat_info["penalty"])
	_set_player_attack_hitbox(_make_card_hitbox(card))
	if _card_needs_hitbox(card) and not _card_hitbox_hits_enemy(card):
		log_message.emit("Card whiffed: hitbox missed.")
		log_message.emit("No follow-up draw: card did not connect.")
		_record_card_action_event(card, "whiff", "player_card")
		_complete_player_card_timeline(card)
		_resolve_card_frame_advantage(card.whiff_frame_penalty)
		return

	var stance_protected := _apply_hit_stance_damage(card, "player_card")
	_apply_card_spacing(card)
	_clamp_duel_distance()
	if card.id == "ground_smash":
		_set_player_attack_hitbox(Rect2())
	if route_valid or starts_new_route:
		log_message.emit("Follow-up draw triggered.")
	else:
		log_message.emit("Combo route broken.")
	_log_card_hit_summary(card, stance_protected)
	_record_card_action_event(card, "hit", "player_card")
	_complete_player_card_timeline(card)
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
			if final_frame_advantage > 0:
				_open_player_followup_window("Follow-up window opened.")
			_update_time_scale()
			return
		if final_frame_advantage > 0 and _has_valid_card_for_current_state():
			_open_player_followup_window("Follow-up window opened.")
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
		_transition_combat_state(CombatStateMachineScript.State.PUNISH, "enemy punish")
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

func _complete_player_card_timeline(card: Resource) -> void:
	if combat_timeline == null or combat_timeline.actor != "PLAYER" or combat_timeline.phase == CombatTimelineScript.Phase.DONE:
		return
	var active_remaining := maxi(0, combat_timeline.hitbox_off_frame - combat_timeline.elapsed_frames)
	if active_remaining > 0:
		combat_timeline.advance_frames(active_remaining)
		_apply_timeline_visual()
	hitbox_system.clear_attack_hitboxes()
	var recovery_remaining := maxi(0, combat_timeline.total_frames() - combat_timeline.elapsed_frames)
	if recovery_remaining > 0:
		combat_timeline.advance_frames(recovery_remaining)
		if combat_timeline.phase != CombatTimelineScript.Phase.DONE:
			_apply_timeline_visual()
	if combat_timeline.phase == CombatTimelineScript.Phase.DONE:
		combat_timeline.finish_action()
		if player != null and player.has_method("clear_timeline_visual"):
			player.clear_timeline_visual()

func _tick_debug_hitboxes(delta: float) -> void:
	hitbox_system.tick_debug_hitboxes(delta)

func _create_hitbox_debug_drawer() -> void:
	var debug_drawer := HitboxDebugDrawScript.new()
	debug_drawer.set("combat_manager", self)
	get_parent().call_deferred("add_child", debug_drawer)

func _begin_player_card_timeline(card: Resource) -> void:
	_transition_combat_state(CombatStateMachineScript.State.EXECUTING_PLAYER_ACTION, "player action: %s" % card.id)
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
	_spend_pressure_frames(cost, _queued_followup_card_pending())

func _action_startup(action: String) -> int:
	return movement_system.action_startup(action)

func _advance_enemy_startup(cost: int) -> void:
	advance_combat_frames(cost, true, false)

func advance_combat_frames(frames: int, tick_enemy_startup := false, tick_enemy_vulnerability := true) -> void:
	var previous_stance_recovery: int = stance_system.recovery_frames()
	combat_clock.advance_combat_frames(frames, tick_enemy_startup, tick_enemy_vulnerability)
	_tick_trade_recovery_frames(float(frames))
	var current_stance_recovery: int = stance_system.recovery_frames()
	if combat_frame_context != "" and previous_stance_recovery > 0 and current_stance_recovery < previous_stance_recovery:
		log_message.emit("Stance recovery ticked by %d during %s." % [previous_stance_recovery - current_stance_recovery, combat_frame_context])
	if combat_timeline != null:
		combat_timeline.advance_frames(frames)
		_apply_timeline_visual()

func _tick_trade_recovery(delta: float) -> void:
	if player_trade_recovery_frames_remaining <= 0.0 and enemy_trade_recovery_frames_remaining <= 0.0:
		return
	_tick_trade_recovery_frames(delta * 60.0)

func _tick_trade_recovery_frames(frames: float) -> void:
	if frames <= 0.0:
		return
	var had_player_recovery := player_trade_recovery_frames_remaining > 0.0
	player_trade_recovery_frames_remaining = maxf(0.0, player_trade_recovery_frames_remaining - frames)
	enemy_trade_recovery_frames_remaining = maxf(0.0, enemy_trade_recovery_frames_remaining - frames)
	if had_player_recovery and player_trade_recovery_frames_remaining <= 0.0:
		log_message.emit("Player trade recovery complete.")
		current_player_action_request = null
		if pending_trade_followup_window and frame_advantage > 0:
			pending_trade_followup_window = false
			_open_player_followup_window("Follow-up window opened after trade recovery.")
		elif combat_state_machine != null and combat_state_machine.current_state == CombatStateMachineScript.State.PLAYER_RECOVERY:
			_transition_combat_state(_state_after_queue_resolution(), "trade recovery complete")

func _advance_player_action_frames(frames: int, tick_enemy_startup := false, tick_enemy_vulnerability := true) -> void:
	var previous_context := combat_frame_context
	combat_frame_context = "player action"
	advance_combat_frames(frames, tick_enemy_startup, tick_enemy_vulnerability)
	combat_frame_context = previous_context

func _spend_pressure_frames(cost: int, defer_pressure_end_for_queued_card := false) -> void:
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
		if defer_pressure_end_for_queued_card:
			log_message.emit("Movement spent available frames; resolving queued card before ending pressure.")
			_update_time_scale()
			return
		if final_frame_advantage < 0:
			_resolve_negative_pressure(final_frame_advantage)
		else:
			end_player_pressure("Pressure ended after movement.", final_frame_advantage)
		return

	_update_time_scale()

func _enemy_attack_whiffs_against_defense(defense_type: String, attack_data: Dictionary) -> bool:
	var attack_type := String(attack_data["type"])
	return (attack_type == "HIGH" and defense_type == "crouch_block") or (attack_type == "LOW" and _is_jump_action(defense_type))

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
	_transition_combat_state(CombatStateMachineScript.State.STANCE_BREAK, "stance break")
	frame_advantage = maxi(frame_advantage + stance_break_frame_bonus, stance_break_frame_bonus)
	enemy_vulnerable_frames_remaining = maxi(enemy_vulnerable_frames_remaining + stance_break_frame_bonus, stance_break_frame_bonus)
	frame_advantage_changed.emit(frame_advantage)
	log_message.emit("Stance break! Punish window opened: +%d frame advantage." % stance_break_frame_bonus)
	_update_time_scale()

func _on_enemy_break_ended() -> void:
	log_message.emit("Stance recovery complete; state NORMAL")
	if frame_advantage <= 0:
		frame_advantage = 0
		enemy_vulnerable_frames_remaining = 0
		_reset_pressure_sequence()
		frame_advantage_changed.emit(frame_advantage)
		log_message.emit("Enemy recovered from stance break. Reset to neutral.")
		_enter_slow_neutral("Slow neutral movement started.")
	else:
		log_message.emit("Enemy recovered from stance break. Pressure continues.")
		_transition_combat_state(CombatStateMachineScript.State.PLAYER_PRESSURE, "stance break recovery")
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
		log_message.emit("Stance protected: ignored %d stance damage." % amount)

func _apply_hit_stance_damage(card: Resource, event_source := "card_hit") -> bool:
	var before := int(enemy.stance)
	var protected: bool = stance_system.should_log_protected_damage(card.stance_damage)
	_log_stance_protection(card.stance_damage)
	stance_system.apply_hit(card.damage, card.stance_damage)
	var after := int(enemy.stance)
	var applied: int = 0 if protected else card.stance_damage
	_record_combat_event("stance_update", "", {
		"source": event_source,
		"stance_before": before,
		"stance_after": after,
		"stance_damage_attempted": card.stance_damage,
		"stance_damage_applied": applied,
		"stance_protected": protected,
		"stance_state": stance_system.state_name(),
		"recovery_frames_remaining": stance_system.recovery_frames()
	})
	return protected

func _apply_block_stance_damage(amount: int, event_source := "block") -> bool:
	var before := int(enemy.stance)
	var protected: bool = stance_system.should_log_protected_damage(amount)
	_log_stance_protection(amount)
	stance_system.apply_block_stance_damage(amount)
	var after := int(enemy.stance)
	_record_combat_event("stance_update", "", {
		"source": event_source,
		"stance_before": before,
		"stance_after": after,
		"stance_damage_attempted": amount,
		"stance_damage_applied": 0 if protected else amount,
		"stance_protected": protected,
		"stance_state": stance_system.state_name(),
		"recovery_frames_remaining": stance_system.recovery_frames()
	})
	return protected

func _log_card_hit_summary(card: Resource, stance_protected: bool) -> void:
	if card.stance_damage > 0 and stance_protected:
		log_message.emit("%s hits for %d. No stance damage due to protection." % [card.display_name, card.damage])
	elif card.stance_damage > 0:
		log_message.emit("Stance damage dealt: %d." % card.stance_damage)
		log_message.emit("%s hits for %d and deals %d stance." % [card.display_name, card.damage, card.stance_damage])
	else:
		log_message.emit("%s hits for %d." % [card.display_name, card.damage])

func _record_card_action_event(card: Resource, result: String, event_source := "card") -> void:
	_record_combat_event("action_executed", "", {
		"source": event_source,
		"actor": "player",
		"action_id": card.id,
		"action_name": card.display_name,
		"card_instance_id": card.instance_id,
		"startup": card.startup_frame,
		"damage": card.damage,
		"stance_damage": card.stance_damage,
		"hit_adv": card.frame_gain,
		"whiff_adv": card.whiff_frame_penalty,
		"tags": card.tags,
		"route": card.allowed_follow_up_card_ids,
		"animation_key": combat_timeline.animation_key if combat_timeline != null else "unknown",
		"phase_at_resolution": combat_timeline.phase_name() if combat_timeline != null else "unknown",
		"distance_at_resolution": _distance_between_fighters(),
		"hitbox_active": combat_timeline.hitbox_active() if combat_timeline != null else false,
		"result": result
	})

func _is_interrupt_card_index(index: int) -> bool:
	if index < 0 or index >= deck_manager.hand.size():
		return false
	var card: Resource = deck_manager.hand[index]
	return _card_has_tag(card, "interrupt") or _card_has_tag(card, "starter")

func _current_mode() -> String:
	_refresh_combat_state()
	return combat_state_machine.state_name(combat_state)

func _refresh_combat_state() -> void:
	combat_state = combat_state_machine.current_state

func _transition_combat_state(next_state: int, reason := "") -> void:
	if combat_state_machine == null:
		return
	combat_state_machine.transition_to(next_state, reason)
	combat_state = combat_state_machine.current_state
	_update_actor_combat_states()

func _update_actor_combat_states() -> void:
	if player_actor_state != null:
		player_actor_state.update_from_actor(player, combat_state_machine.state_name(combat_state), combat_timeline.action_name if combat_timeline != null and combat_timeline.actor == "PLAYER" else "None", current_player_action_request)
		player_actor_state.recovery_frames_remaining = int(ceil(player_trade_recovery_frames_remaining))
	if enemy_actor_state != null:
		enemy_actor_state.update_from_actor(enemy, combat_state_machine.state_name(combat_state), current_enemy_intent if current_enemy_intent != "" else "None", current_enemy_action_request)
		enemy_actor_state.recovery_frames_remaining = int(ceil(enemy_trade_recovery_frames_remaining)) if enemy_trade_recovery_frames_remaining > 0.0 else (remaining_startup_frames if _is_enemy_intent_state() else 0)
		enemy_actor_state.hitstun_frames_remaining = enemy_vulnerable_frames_remaining

func _queue_is_resolving() -> bool:
	return queue_resolver != null and queue_resolver.resolving

func _queue_has_pending_action() -> bool:
	return queue_resolver != null and (queued_action_in_progress or not queue_resolver.is_empty())

func _queued_followup_card_pending() -> bool:
	return queue_resolver != null and queue_resolver.resolving and not queue_resolver.is_empty() and String(queue_resolver.queue.front().get("type", "")) == "CARD"

func _is_stale_executing_queue_state() -> bool:
	return combat_state_machine != null \
		and combat_state_machine.current_state == CombatStateMachineScript.State.EXECUTING_QUEUE \
		and (not _queue_is_resolving() or not _queue_has_pending_action())

func _warn_state_repair(message: String) -> void:
	if message == last_state_repair_warning:
		return
	last_state_repair_warning = message
	log_message.emit("State repair warning: %s" % message)

func _repair_invalid_combat_state() -> void:
	if combat_state_machine == null or combat_over:
		return

	if _is_stale_executing_queue_state():
		_warn_state_repair("EXECUTING_QUEUE had no active queued action; repairing.")
		if queue_resolver != null:
			queue_resolver.resolving = false
		queued_action_in_progress = false
		_transition_combat_state(_state_after_queue_resolution(), "state repair: stale executing queue")
		return

	if combat_state_machine.current_state == CombatStateMachineScript.State.ENEMY_RECOVERY and _enemy_recovery_frames_remaining() <= 0 and current_enemy_intent == "":
		_warn_state_repair("ENEMY_RECOVERY had no recovery owner; repairing.")
		_clear_stale_enemy_recovery()
		_transition_combat_state(_state_after_queue_resolution(), "state repair: enemy recovery complete")
		_enter_slow_neutral("Slow neutral movement started.")
		return

	if enemy_ai_system != null and enemy_ai_system.last_state == "RECOVERING" and not _enemy_has_active_recovery():
		_warn_state_repair("Enemy AI RECOVERING had no recovery frames/action; clearing.")
		_clear_stale_enemy_recovery()

	if _player_has_stale_defense_visual():
		_warn_state_repair("Player defense visual/action remained active after reaction; clearing.")
		_clear_stale_player_defense()

	if _player_has_stale_action_without_request():
		_warn_state_repair("Player action state active without action request; clearing.")
		_clear_stale_player_action()

	if _player_has_stale_idle_lock():
		_warn_state_repair("Player action lock had no active action/stun/recovery; clearing.")
		_clear_stale_player_action()

	if combat_state_machine.current_state == CombatStateMachineScript.State.PLAYER_RECOVERY and _player_has_stale_player_recovery_state():
		_warn_state_repair("PLAYER_RECOVERY had no recovery frames; repairing.")
		current_player_action_request = null
		_transition_combat_state(_state_after_queue_resolution(), "state repair: player recovery complete")
		return

	if combat_state_machine.current_state == CombatStateMachineScript.State.REACTION_WINDOW and not _reaction_window_active():
		_warn_state_repair("REACTION_WINDOW inactive; repairing.")
		if current_enemy_intent != "" or waiting_for_defense:
			_transition_combat_state(CombatStateMachineScript.State.ENEMY_INTENT, "state repair: inactive reaction window")
		else:
			_transition_combat_state(_state_after_queue_resolution(), "state repair: inactive reaction window")

func _execute_ready_queue_after_movement() -> void:
	if combat_over or _queue_is_resolving() or queue_resolver == null or queue_resolver.is_empty():
		return
	if movement_flow_system == null or movement_flow_system.movement_phase != "DONE":
		return
	if _movement_flow_active() and bool(movement_flow_system.player_live_movement_active):
		return
	if _player_action_locked():
		return
	if _is_slow_neutral_state() or _can_take_pressure_movement():
		call_deferred("_execute_or_wait_tactical_queue")

func _player_has_stale_defense_visual() -> bool:
	if _reaction_window_active():
		return false
	if player == null or not player.has_method("get_animation_debug"):
		return false
	var debug: Dictionary = player.get_animation_debug()
	var action_state := String(debug.get("action_state", ""))
	var action_name := String(debug.get("action_name", ""))
	var phase := String(debug.get("phase", ""))
	return action_state.begins_with("BLOCK") or (action_name.to_lower().find("block") != -1 and phase != "DONE")

func _player_has_stale_action_without_request() -> bool:
	if current_player_action_request != null:
		return false
	if player == null or not player.has_method("get_animation_debug"):
		return false
	var debug: Dictionary = player.get_animation_debug()
	var action_state := String(debug.get("action_state", "NEUTRAL"))
	if action_state == "NEUTRAL" or action_state == "":
		return false
	if action_state.begins_with("BLOCK"):
		return false
	return not _queue_is_resolving() and not queued_action_in_progress

func _player_debug() -> Dictionary:
	if player != null and player.has_method("get_animation_debug"):
		return player.get_animation_debug()
	return {}

func _player_has_real_action_lifecycle() -> bool:
	if player_trade_recovery_frames_remaining > 0.0:
		return true
	var debug := _player_debug()
	var action_state := String(debug.get("action_state", "NEUTRAL"))
	var animation_key := String(debug.get("animation_key", "idle")).to_lower()
	var action_name := String(debug.get("action_name", "None")).to_lower()
	var phase := String(debug.get("phase", "DONE"))
	var recovering := action_state == "ATTACK_RECOVERY" or action_state == "BLOCK_RECOVERY"
	var attacking := action_state == "ATTACK_STARTUP" or action_state == "ATTACK_ACTIVE"
	var blocking := action_state == "BLOCK_START" or action_state == "BLOCK_HOLD"
	var hitstun := action_state == "HITSTUN"
	var has_named_action := animation_key != "idle" and animation_key != "none" and action_name != "none"
	if attacking or blocking or recovering:
		return has_named_action or phase != "DONE" or current_player_action_request != null
	if hitstun:
		return animation_key != "idle" and animation_key != "none"
	return false

func _player_has_stale_idle_lock() -> bool:
	if player_trade_recovery_frames_remaining > 0.0:
		return false
	var debug := _player_debug()
	if debug.is_empty():
		return false
	var action_state := String(debug.get("action_state", "NEUTRAL"))
	var animation_key := String(debug.get("animation_key", "idle")).to_lower()
	var action_name := String(debug.get("action_name", "None")).to_lower()
	var recovering := bool(String(debug.get("recovering", "false")) == "true")
	var is_locked := bool(debug.get("is_action_locked", false))
	var no_action := animation_key == "idle" or animation_key == "none" or action_name == "none"
	return is_locked and no_action and not recovering and not _queue_is_resolving() and not queued_action_in_progress

func _player_has_stale_player_recovery_state() -> bool:
	if combat_state_machine.current_state != CombatStateMachineScript.State.PLAYER_RECOVERY:
		return false
	if player_trade_recovery_frames_remaining > 0.0:
		return false
	var debug := _player_debug()
	var action_name := String(debug.get("action_name", "None")).to_lower()
	var animation_key := String(debug.get("animation_key", "idle")).to_lower()
	var no_action := action_name == "none" or animation_key == "idle" or animation_key == "none"
	return no_action and not _player_has_real_action_lifecycle()

func _clear_stale_player_defense() -> void:
	if player != null:
		if player.has_method("clear_stale_defense_action"):
			player.clear_stale_defense_action()
		elif player.has_method("clear_timeline_visual"):
			player.clear_timeline_visual()
	current_player_action_request = null
	last_player_action_startup = 0

func _clear_stale_player_action() -> void:
	if player != null:
		if player.has_method("force_finish_action"):
			player.force_finish_action()
		elif player.has_method("clear_timeline_visual"):
			player.clear_timeline_visual()
	current_player_action_request = null
	last_player_action_startup = 0

func _movement_flow_active() -> bool:
	return movement_flow_system != null and movement_flow_system.active

func _reaction_window_active() -> bool:
	return reaction_window_system != null and reaction_window_system.active

func _is_punish_state() -> bool:
	return combat_state_machine != null and combat_state_machine.is_punish_state()

func _enemy_action_flow_locked() -> bool:
	if combat_state_machine == null:
		return _enemy_has_active_recovery()
	if combat_state_machine.current_state == CombatStateMachineScript.State.PUNISH:
		return punish_in_progress
	if combat_state_machine.current_state == CombatStateMachineScript.State.STANCE_BREAK:
		return _enemy_break_frames_remaining() > 0
	if combat_state_machine.current_state == CombatStateMachineScript.State.ENEMY_RECOVERY:
		return _enemy_has_active_recovery()
	return combat_state_machine.current_state == CombatStateMachineScript.State.ENEMY_INTENT \
		or combat_state_machine.current_state == CombatStateMachineScript.State.REACTION_WINDOW \
		or combat_state_machine.current_state == CombatStateMachineScript.State.ENEMY_ACTIVE

func _enemy_recovery_frames_remaining() -> int:
	if combat_state_machine == null:
		return 0
	if combat_state_machine.current_state == CombatStateMachineScript.State.ENEMY_INTENT or combat_state_machine.current_state == CombatStateMachineScript.State.REACTION_WINDOW:
		return maxi(0, remaining_startup_frames)
	if combat_state_machine.current_state == CombatStateMachineScript.State.STANCE_BREAK:
		return _enemy_break_frames_remaining()
	return 0

func _enemy_has_active_recovery() -> bool:
	if punish_in_progress:
		return true
	if _enemy_break_frames_remaining() > 0:
		return true
	if current_enemy_intent != "":
		return true
	if waiting_for_defense or _reaction_window_active():
		return true
	return false

func _clear_stale_enemy_recovery() -> void:
	attack_in_progress = false
	punish_in_progress = false
	waiting_for_defense = false
	current_enemy_action_request = null
	current_enemy_intent = ""
	remaining_startup_frames = 0
	enemy_base_startup_frame = 0
	enemy_effective_startup_frame = 0
	if reaction_window_system != null:
		reaction_window_system.deactivate()
	if enemy != null:
		if enemy.has_method("clear_intent"):
			enemy.clear_intent()
		if enemy.has_method("set_decision_state"):
			enemy.set_decision_state(Enemy.DecisionState.NEUTRAL, "Recovery complete.", 0.0)
	if enemy_ai_system != null:
		enemy_ai_system.last_state = "NEUTRAL"
		enemy_ai_system.last_reason = "Recovery complete."
		enemy_ai_system.last_chosen_action = "None"
		enemy_ai_system.last_score = 0.0

func _can_tick_reaction_window() -> bool:
	return combat_state_machine != null and combat_state_machine.can_tick_reaction_window() and _reaction_window_active() and not combat_over

func _state_after_queue_resolution() -> int:
	if player_trade_recovery_frames_remaining > 0.0:
		return CombatStateMachineScript.State.PLAYER_RECOVERY
	if frame_advantage > 0 or _enemy_break_frames_remaining() > 0:
		return CombatStateMachineScript.State.PLAYER_PRESSURE
	if _reaction_window_active():
		return CombatStateMachineScript.State.REACTION_WINDOW
	if current_enemy_intent != "" or waiting_for_defense:
		return CombatStateMachineScript.State.ENEMY_INTENT
	if _movement_flow_active():
		return CombatStateMachineScript.State.SLOW_NEUTRAL
	if fight_started:
		return CombatStateMachineScript.State.SLOW_NEUTRAL
	return CombatStateMachineScript.State.NEUTRAL

func _set_queue_resolving(enabled: bool, reason := "") -> void:
	if queue_resolver == null:
		return
	queue_resolver.resolving = enabled
	if enabled:
		_transition_combat_state(CombatStateMachineScript.State.EXECUTING_QUEUE, reason if reason != "" else "queue execution")
		if combat_state_machine.current_actor() == "none" or not _queue_has_pending_action():
			_warn_state_repair("EXECUTING_QUEUE entered without an active queued action.")
	else:
		queued_action_in_progress = false
		_transition_combat_state(_state_after_queue_resolution(), reason if reason != "" else "queue complete")

func _is_reaction_window_state() -> bool:
	return combat_state_machine != null and combat_state_machine.is_reaction_window()

func _is_slow_neutral_state() -> bool:
	return combat_state_machine != null and combat_state_machine.is_slow_neutral()

func _is_enemy_intent_state() -> bool:
	if combat_state_machine == null:
		return false
	return combat_state_machine.current_state == CombatStateMachineScript.State.ENEMY_INTENT or combat_state_machine.current_state == CombatStateMachineScript.State.REACTION_WINDOW

func _can_execute_queue() -> bool:
	return combat_state_machine != null and combat_state_machine.can_execute_queue() and not _queue_is_resolving()

func can_accept_tactical_queue_input() -> bool:
	if _is_stale_executing_queue_state():
		return true
	return combat_state_machine != null and combat_state_machine.can_accept_queue_input() and not combat_over

func can_accept_live_defense() -> bool:
	return combat_state_machine != null and combat_state_machine.can_accept_live_defense()

func can_accept_live_movement() -> bool:
	return combat_state_machine != null and combat_state_machine.can_accept_live_movement()

func get_queue_text() -> String:
	return queue_resolver.queue_text()

func _is_tactical_mode() -> bool:
	return not combat_over and combat_state_machine != null and (combat_state_machine.can_accept_queue_input() or _is_stale_executing_queue_state())

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
	if _queue_is_resolving():
		return
	if not _can_execute_queue():
		log_message.emit("Queue execution rejected: state=%s." % _current_mode())
		return
	if _is_slow_neutral_state() and queue_resolver.is_empty():
		log_message.emit("No queued action. Keep moving or queue a card.")
		return
	if _is_slow_neutral_state():
		log_message.emit("Queue execution started.")
		await _execute_slow_neutral_queue()
		return
	queue_resolver.interrupted_by_trade = false
	if queue_resolver.is_empty():
		log_message.emit("Player waited.")
		if _is_enemy_intent_state():
			await _resolve_enemy_intent("wait")
		elif _can_take_pressure_movement():
			_spend_pressure_frames(1)
		return

	_set_queue_resolving(true, "execute tactical queue")
	while not queue_resolver.is_empty() and _is_tactical_mode():
		var action: Dictionary = queue_resolver.pop_front()
		queued_action_in_progress = true
		await _resolve_queued_action(action)
		queued_action_in_progress = false
		frame_advantage_changed.emit(frame_advantage)
		if queue_resolver.interrupted_by_trade:
			log_message.emit("Queue stopped after trade.")
			queue_resolver.clear()
			break
		await _pause_between_queued_actions()
	_set_queue_resolving(false, "queue complete")
	if not _is_tactical_mode():
		queue_resolver.clear()

func _execute_slow_neutral_queue() -> void:
	var had_enemy_intent := _distance_between_fighters() <= enemy_intent_range
	_exit_slow_neutral()
	if had_enemy_intent:
		_run_enemy_attack(false)
	_set_queue_resolving(true, "execute slow neutral queue")
	queue_resolver.interrupted_by_trade = false
	while not queue_resolver.is_empty() and (_is_enemy_intent_state() or not had_enemy_intent) and not combat_over:
		var action: Dictionary = queue_resolver.pop_front()
		queued_action_in_progress = true
		await _resolve_queued_action(action)
		queued_action_in_progress = false
		frame_advantage_changed.emit(frame_advantage)
		if queue_resolver.interrupted_by_trade:
			log_message.emit("Queue stopped after trade.")
			queue_resolver.clear()
			break
		await _pause_between_queued_actions()
	_set_queue_resolving(false, "slow neutral queue complete")
	if _is_enemy_intent_state() and not _is_reaction_window_state() and not combat_over:
		_start_reaction_window(current_enemy_intent, remaining_startup_frames)
		_transition_combat_state(CombatStateMachineScript.State.REACTION_WINDOW, "reaction window started after queue")
		_update_time_scale()
	if not _is_enemy_intent_state():
		queue_resolver.clear()
		if frame_advantage <= 0 and not combat_over:
			_schedule_enemy_if_needed()

func _resolve_queued_action(action: Dictionary) -> void:
	if action.get("type", "") == "CARD":
		_clear_attack_hitboxes()
		log_message.emit("Action snapshot executed: %s." % _snapshot_debug_text(action))
		_warn_if_snapshot_changed(action)
		if _is_enemy_intent_state():
			await _try_interrupt_with_card_snapshot(action)
		elif _can_take_pressure_movement():
			await _resolve_pressure_card_snapshot(action)
		else:
			log_message.emit("Pre-emptive card resolved during enemy approach.")
			await _resolve_pressure_card_snapshot(action)
		return

	var combat_action := _combat_action_from_queued_action(String(action.get("type", "")))
	if combat_action == "":
		return
	if _is_enemy_intent_state():
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
	if combat_over or _is_enemy_intent_state():
		return false
	if combat_state_machine != null:
		return combat_state_machine.can_take_pressure_movement(frame_advantage, _enemy_break_frames_remaining(), not _player_action_locked())
	return frame_advantage > 0 or _enemy_break_frames_remaining() > 0

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
	if enemy_intent_scheduled or combat_over or frame_advantage > 0 or _is_punish_state():
		return
	if combat_state_machine != null and not combat_state_machine.can_schedule_enemy_intent(frame_advantage):
		return
	_enter_slow_neutral("Slow neutral movement started.")

func _update_time_scale() -> void:
	if combat_over:
		Engine.time_scale = 1.0
		return

	if _is_slow_neutral_state():
		player.set_free_movement_enabled(false)
		Engine.time_scale = NEUTRAL_SLOW_TIME_SCALE
		return

	player.set_free_movement_enabled(false)
	if _is_enemy_intent_state():
		Engine.time_scale = ENEMY_INTENT_TIME_SCALE
	else:
		Engine.time_scale = PLAYER_CHOICE_TIME_SCALE if can_play_cards() else 1.0

func _end_combat(message: String) -> void:
	_transition_combat_state(CombatStateMachineScript.State.GAME_OVER, message)
	combat_over = true
	current_player_action_request = null
	current_enemy_action_request = null
	waiting_for_defense = false
	reaction_window_system.deactivate()
	attack_in_progress = false
	punish_in_progress = false
	enemy_intent_scheduled = false
	current_enemy_intent = ""
	enemy_base_startup_frame = 0
	enemy_effective_startup_frame = 0
	remaining_startup_frames = 0
	initiative_offset = 0
	enemy_vulnerable_frames_remaining = 0
	player_trade_recovery_frames_remaining = 0.0
	enemy_trade_recovery_frames_remaining = 0.0
	pending_trade_followup_window = false
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
