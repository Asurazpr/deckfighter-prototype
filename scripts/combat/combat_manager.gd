class_name CombatManagerCore
extends Node

signal frame_advantage_changed(value: int)
signal log_message(message: String)
signal player_action_lifecycle_released(reason: String)

const ATTACK_RECOVERY := 0.35
const PLAYER_CHOICE_TIME_SCALE := 0.2
const NEUTRAL_SLOW_TIME_SCALE := 0.35
const ENEMY_INTENT_TIME_SCALE := 0.15
const PERFECT_BLOCK_HITSTOP := 0.12
const PERFECT_BLOCK_REACTION_PROGRESS := 0.85
const REACTION_GUARD_STARTUP_FRAMES := 4
const PLAYER_ACTION_TIMELINE_FPS := 30.0
const HitboxDebugDrawScript := preload("res://scripts/hitbox_debug_draw.gd")
const CombatClockScript := preload("res://scripts/combat/combat_clock.gd")
const FrameSystemScript := preload("res://scripts/combat/frame_system.gd")
const QueueResolverScript := preload("res://scripts/combat/queue_resolver.gd")
const RouteSystemScript := preload("res://scripts/combat/route_system.gd")
const MovementSystemScript := preload("res://scripts/combat/movement_system.gd")
const HitboxSystemScript := preload("res://scripts/combat/hitbox_system.gd")
const TradeSystemScript := preload("res://scripts/combat/trade_system.gd")
const StanceSystemScript := preload("res://scripts/combat/stance_system.gd")
const StanceDamageResolverScript := preload("res://scripts/combat/stance_damage_resolver.gd")
const EnemyAISystemScript := preload("res://scripts/combat/enemy_ai_system.gd")
const CombatTimelineScript := preload("res://scripts/combat/combat_timeline.gd")
const ReactionWindowSystemScript := preload("res://scripts/combat/reaction_window_system.gd")
const MovementFlowSystemScript := preload("res://scripts/combat/movement_flow_system.gd")
const CombatStateMachineScript := preload("res://scripts/combat/combat_state_machine.gd")
const CombatInputRouterScript := preload("res://scripts/combat/combat_input_router.gd")
const ActorCombatStateScript := preload("res://scripts/combat/actor_combat_state.gd")
const ActionRequestScript := preload("res://scripts/combat/action_request.gd")
const CombatCoreScript := preload("res://scripts/combat/combat_core.gd")
const TacticalModeControllerScript := preload("res://scripts/combat/tactical_mode_controller.gd")
const PowerFightingModeControllerScript := preload("res://scripts/combat/power_fighting_mode_controller.gd")
const CombatAnimationControllerScript := preload("res://scripts/combat/animation_controller.gd")
const DEBUG_ATTACK_HITBOX_LIFETIME := 0.25

enum ControlMode { TIME_TACTICAL, POWER_ACTION }

@export_enum("TIME_TACTICAL", "POWER_ACTION") var control_mode: int = ControlMode.TIME_TACTICAL
@export var starting_frame_advantage := 0
@export var punish_threshold := 10
@export var enemy_punish_startup := 5
@export var enemy_punish_range := 120.0
@export var stance_break_frame_bonus := 6
@export var max_duel_distance := 260.0
@export var min_duel_distance := 55.0
@export var show_debug_hitboxes := false
@export var show_hitbox_calibration := false
@export var show_sprite_bounds_debug := false
@export var enable_hitbox_trace_log := true
@export var sprite_hurtbox_inset_ratio := Vector4(0.05, 0.02, 0.05, 0.0)
@export var crouch_hurtbox_width_scale := 0.82
@export var crouch_hurtbox_height_scale := 0.58
@export var show_prediction_assist := true
@export var perfect_block_window_frames := 1
@export var max_queue_size := 3
@export var trade_player_recovery_frames := 18
@export var trade_enemy_recovery_frames := 26
@export var live_neutral_player_speed := 140.0
@export var live_neutral_enemy_speed := 70.0
@export var reaction_player_move_speed := 180.0
@export var reaction_jump_horizontal_speed := 620.0
@export var reaction_jump_hurtbox_lift := 220.0
@export var reaction_jump_arc_frames := 42
@export var arena_left_x := 0.0
@export var arena_right_x := 1600.0
@export var arena_wall_margin := 90.0
@export var enemy_intent_range := 95.0
@export var slow_neutral_intent_delay := 1.2
@export var defensive_reaction_wait_frames := 20
@export var max_defensive_reaction_retries := 3
@export var power_action_enemy_startup_multiplier := 1.5
@export var power_action_enemy_recovery_multiplier := 2.0
@export var power_action_enemy_decision_cooldown_frames := 24
@export var power_action_enemy_hitstun_frames := 18
@export var power_action_block_startup_frames := 4

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
var reaction_jump_motion_active := false
var reaction_jump_ground_y := 0.0
var reaction_jump_elapsed_frames := 0.0
var reaction_jump_direction := 0.0
var reaction_jump_landing_requested := false
var last_no_attack_reaches_reason := "None"
var combat_clock
var frame_system
var queue_resolver
var route_system
var movement_system
var hitbox_system
var trade_system
var stance_system
var stance_damage_resolver
var enemy_ai_system
var combat_timeline
var reaction_window_system
var movement_flow_system
var combat_state_machine
var combat_input_router
var combat_core
var tactical_mode_controller
var power_fighting_mode_controller
var combat_animation_controller
var player_actor_state
var enemy_actor_state
var current_player_action_request
var current_enemy_action_request
var pending_player_action_request_override
var queued_action_in_progress := false
var last_state_repair_warning := ""
var player_trade_recovery_frames_remaining := 0.0
var enemy_trade_recovery_frames_remaining := 0.0
var enemy_action_recovery_frames_remaining := 0.0
var pending_trade_followup_window := false
var player_action_lifecycle_active := false
var player_action_lifecycle_done := true
var player_action_lifecycle_release_authorized := false
var player_action_lifecycle_release_reason := ""
var player_action_lifecycle_action_id := ""
var player_action_lifecycle_card_name := ""
var player_action_lifecycle_phase := "DONE"
var player_action_lifecycle_token := 0
var player_action_lifecycle_recovery_frames_remaining := 0.0
var player_action_lifecycle_recovery_running := false
var power_action_player_recovery_frame_accumulator := 0.0
var power_action_enemy_startup_frame_accumulator := 0.0
var enemy_action_recovery_frame_accumulator := 0.0
var power_action_enemy_recovery_frame_accumulator := 0.0
var power_action_enemy_active_frame_accumulator := 0.0
var power_action_enemy_impact_resolving := false
var power_action_enemy_decision_cooldown_remaining := 0.0
var power_action_enemy_hitstun_frame_accumulator := 0.0
var power_action_enemy_active_frames_remaining := 0.0
var power_action_enemy_active_result: Dictionary = {}
var power_action_enemy_active_resolved := false
var power_action_enemy_recovery_frames_elapsed := 0.0
var power_action_block_held := false
var power_action_block_defense_type := ""
var power_action_block_startup_frames_remaining := 0.0
var power_action_block_startup_accumulator := 0.0
var last_power_action_enemy_reject_reason := ""
var last_enemy_action_done_frame := -1
var last_enemy_action_done_msec := -1
var last_enemy_decision_frame := -1
var last_enemy_decision_msec := -1
var last_power_action_crouching := false
var last_power_action_crouch_reject_reason := ""
var last_power_action_movement_gate := ""

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
	if player.has_signal("defensive_input_rejected"):
		player.defensive_input_rejected.connect(_on_player_defensive_input_rejected)
	enemy.break_started.connect(_on_enemy_break_started)
	enemy.break_ended.connect(_on_enemy_break_ended)
	deck_manager.follow_up_drawn.connect(_on_follow_up_drawn)
	deck_manager.follow_up_skipped.connect(_on_follow_up_skipped)
	if player.has_signal("action_animation_finished"):
		player.action_animation_finished.connect(_on_player_visual_action_finished)
	call_deferred("_begin_combat")

func _setup_combat_systems() -> void:
	combat_clock = CombatClockScript.new()
	combat_clock.setup(self, player, enemy)
	frame_system = FrameSystemScript.new()
	frame_system.setup(self, enemy)
	queue_resolver = QueueResolverScript.new()
	queue_resolver.setup(self, deck_manager, max_queue_size)
	route_system = RouteSystemScript.new()
	route_system.setup(self, deck_manager)
	movement_system = MovementSystemScript.new()
	movement_system.setup(self, player, enemy, max_duel_distance, min_duel_distance, arena_left_x, arena_right_x, arena_wall_margin)
	hitbox_system = HitboxSystemScript.new()
	hitbox_system.setup(self, player, enemy, movement_system)
	trade_system = TradeSystemScript.new()
	trade_system.setup(self, trade_player_recovery_frames, trade_enemy_recovery_frames)
	stance_system = StanceSystemScript.new()
	stance_system.setup(enemy)
	stance_damage_resolver = StanceDamageResolverScript.new()
	enemy_ai_system = EnemyAISystemScript.new()
	enemy_ai_system.setup(self, enemy, frame_system)
	combat_timeline = CombatTimelineScript.new()
	reaction_window_system = ReactionWindowSystemScript.new()
	reaction_window_system.setup(self, player, PERFECT_BLOCK_REACTION_PROGRESS, REACTION_GUARD_STARTUP_FRAMES)
	movement_flow_system = MovementFlowSystemScript.new()
	movement_flow_system.setup(self, player, enemy, movement_system, NEUTRAL_SLOW_TIME_SCALE, live_neutral_player_speed, live_neutral_enemy_speed, enemy_intent_range, slow_neutral_intent_delay)
	combat_state_machine = CombatStateMachineScript.new()
	combat_state_machine.setup(CombatStateMachineScript.State.PRE_FIGHT)
	combat_core = CombatCoreScript.new()
	combat_core.setup(combat_state_machine, hitbox_system, stance_damage_resolver)
	tactical_mode_controller = TacticalModeControllerScript.new()
	tactical_mode_controller.setup(self, deck_manager, queue_resolver)
	power_fighting_mode_controller = PowerFightingModeControllerScript.new()
	power_fighting_mode_controller.setup(self)
	combat_animation_controller = CombatAnimationControllerScript.new()
	combat_animation_controller.setup(self, player, enemy)
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
	_reset_round_start_from_scene()
	fight_started = true
	_transition_combat_state(CombatStateMachineScript.State.SLOW_NEUTRAL, "start fight")
	_enter_slow_neutral("Slow neutral movement started.")
	frame_advantage_changed.emit(frame_advantage)
	log_message.emit("Duel start. Read the enemy intent.")

func is_fight_started() -> bool:
	return fight_started

func get_control_mode_name() -> String:
	match control_mode:
		ControlMode.POWER_ACTION:
			return "POWER_ACTION"
		_:
			return "TIME_TACTICAL"

func is_power_action_mode() -> bool:
	return control_mode == ControlMode.POWER_ACTION

func is_time_tactical_mode() -> bool:
	return control_mode == ControlMode.TIME_TACTICAL

func toggle_control_mode() -> void:
	var next_mode := ControlMode.POWER_ACTION if control_mode == ControlMode.TIME_TACTICAL else ControlMode.TIME_TACTICAL
	set_control_mode(next_mode)

func set_control_mode(next_mode: int) -> void:
	var old_mode := get_control_mode_name()
	control_mode = clampi(next_mode, ControlMode.TIME_TACTICAL, ControlMode.POWER_ACTION)
	var new_mode := get_control_mode_name()
	if old_mode == new_mode:
		return
	log_message.emit("Control mode changed: %s -> %s." % [old_mode, new_mode])
	_record_combat_event("control_mode_changed", "Control mode changed.", {
		"old_mode": old_mode,
		"new_mode": new_mode
	})
	frame_advantage_changed.emit(frame_advantage)

func set_enemy_intent_ui_visible(visible: bool) -> void:
	if enemy != null and enemy.has_method("set_intent_ui_visible"):
		enemy.set_intent_ui_visible(visible)

func refresh_actor_facing() -> void:
	_update_actor_facing()

func _reset_round_start_from_scene() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("reset_round_start_positions"):
		scene.reset_round_start_positions()

func _log_architecture_validation() -> void:
	var active_path: String = get_script().resource_path
	var legacy_present := ResourceLoader.exists("res://scripts/combat_manager.gd")
	log_message.emit("Active combat manager: %s (CombatManagerCore)." % active_path)
	log_message.emit("Loaded combat systems: CombatCore, CombatClock, CombatTimeline, FrameSystem, QueueResolver, RouteSystem, MovementSystem, MovementFlowSystem, HitboxSystem, TradeSystem, StanceSystem, StanceDamageResolver, EnemyAISystem, ReactionWindowSystem, CombatStateMachine, CombatInputRouter, TacticalModeController, PowerFightingModeController, CombatAnimationController.")
	log_message.emit("CombatCore gameplay clock: %d FPS." % int(CombatCoreScript.GAMEPLAY_FPS))
	log_message.emit("Legacy combat manager present: %s." % str(legacy_present))

func _process(_delta: float) -> void:
	if combat_over:
		return
	_tick_power_action_neutral_crouch()
	_log_power_action_movement_gate()
	_tick_enemy_action_recovery(_delta)
	_update_actor_combat_states()
	_repair_invalid_combat_state()
	_tick_trade_recovery(_delta)
	_execute_ready_queue_after_movement()
	_clamp_duel_for_current_motion()
	_update_actor_facing()
	_tick_debug_hitboxes(_delta)
	_tick_reaction_window(_delta)
	_tick_slow_neutral(_delta)
	_tick_power_action_live_movement(_delta)
	_tick_reaction_jump_arc(_delta)

	if player.hp <= 0:
		_end_combat("Player defeated.")
	elif enemy.hp <= 0:
		_end_combat("Enemy defeated.")

func _physics_process(delta: float) -> void:
	if combat_over or not is_power_action_mode():
		return
	_tick_power_action_block(delta)
	_tick_power_action_enemy_intent(delta)
	_tick_power_action_enemy_active(delta)
	_tick_power_action_enemy_recovery(delta)
	_tick_power_action_enemy_decision_cooldown(delta)
	_tick_power_action_enemy_hitstun(delta)
	_tick_power_action_player_recovery(delta)
	_update_power_action_live_frame_advantage()

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
	return "Distance: %.0f\nControl: %s\nMode: %s\nPhase: %s\nActor: %s\n%s" % [
		_distance_between_fighters(),
		get_control_mode_name(),
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
		"control_mode": get_control_mode_name(),
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
	if is_power_action_mode():
		var power_action_reject_reason := _power_action_player_reject_reason()
		return "direct_input_ready" if power_action_reject_reason == "" else power_action_reject_reason
	if not _combat_core_allows_action_request(_player_card_action_request(), not _player_action_locked()):
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

func _record_action_lifecycle_event(event_type: String, data := {}) -> void:
	var event: Dictionary = data.duplicate(true)
	_record_combat_event(event_type, event_type, event)
	var actor := String(event.get("actor", "actor"))
	var move_id := String(event.get("move_id", "unknown"))
	log_message.emit("%s %s %s." % [actor.to_upper(), move_id, event_type])

func _record_rejected_action(actor: String, reason: String, move_id := "") -> void:
	_record_action_lifecycle_event("REJECTED_ACTION", {
		"actor": actor,
		"move_id": move_id,
		"reason": reason,
		"rejection_reason": reason,
		"global_combat_state": _current_mode(),
		"player_phase": _player_phase_for_log(),
		"enemy_phase": _enemy_phase_for_log(),
		"player_can_act": _power_action_player_can_act(),
		"enemy_can_act": _power_action_enemy_can_act()
	})

func _action_request_source_name(action_request) -> String:
	if action_request is ActionRequestScript:
		return action_request.source_type_name()
	if action_request is Dictionary:
		return String(action_request.get("source_type", "unknown"))
	return "none"

func _player_phase_for_log() -> String:
	if player_action_lifecycle_active and not player_action_lifecycle_done:
		return player_action_lifecycle_phase
	if player_trade_recovery_frames_remaining > 0.0:
		return "TRADE_RECOVERY"
	var debug := _player_debug()
	if not debug.is_empty():
		return String(debug.get("phase", "DONE"))
	return "DONE"

func _enemy_phase_for_log() -> String:
	if current_enemy_intent != "" and remaining_startup_frames > 0:
		return "STARTUP"
	if combat_state_machine != null and combat_state_machine.current_state == CombatStateMachineScript.State.ENEMY_ACTIVE:
		return "ACTIVE"
	if enemy_action_recovery_frames_remaining > 0.0 or (combat_state_machine != null and combat_state_machine.current_state == CombatStateMachineScript.State.ENEMY_RECOVERY):
		return "RECOVERY"
	if enemy_vulnerable_frames_remaining > 0:
		return "HITSTUN"
	if _enemy_break_frames_remaining() > 0:
		return "BLOCKSTUN"
	return "DONE"

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
	if is_power_action_mode():
		return false
	if not fight_started:
		return false
	if _is_reaction_window_state():
		return false
	var state_allows: bool = _combat_core_allows_action_request(_player_card_action_request(), not _player_action_locked())
	return state_allows and (_is_enemy_intent_state() or _can_take_pressure_movement()) and not combat_over

func is_hand_card_playable(index: int) -> bool:
	_repair_invalid_combat_state()
	if is_power_action_mode():
		return false
	if not fight_started:
		return false
	if _player_action_locked():
		return false
	if not _combat_core_allows_action_request(_player_card_action_request(index), true):
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
	if is_power_action_mode():
		return "POWER_ACTION uses direct inputs J/K/U/I; cards do not mutate the deck"
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
	if not _combat_core_allows_action_request(_player_card_action_request(index), true):
		return "state machine locked input: state=%s phase=%s actor=%s transition=%s reward_value=%d" % [
			combat_state_machine.state_name(),
			combat_state_machine.current_phase_name(),
			combat_state_machine.current_actor(),
			combat_state_machine.last_transition,
			_player_reward_frame_value()
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

func log_card_playability_debug(index: int, context := "card_input") -> void:
	var snapshot := _card_playability_snapshot(index)
	var reason := get_card_input_rejection_reason(index)
	snapshot["context"] = context
	snapshot["reject_reason"] = reason
	_record_combat_event("CARD_GATE_DEBUG", "Card gate debug.", snapshot)
	log_message.emit("CARD_GATE %s idx=%d mode=%s state=%s frame_adv=%d player_can_act=%s core=%s tactical=%s reject=%s." % [
		context,
		index,
		String(snapshot.get("control_mode", "UNKNOWN")),
		String(snapshot.get("combat_state", "UNKNOWN")),
		int(snapshot.get("frame_advantage", 0)),
		str(snapshot.get("player_can_act", false)),
		str(snapshot.get("core_can_accept", false)),
		str(snapshot.get("tactical_can_play", false)),
		reason if reason != "" else "None"
	])

func _card_playability_snapshot(index: int) -> Dictionary:
	var player_can_act := not _player_action_locked()
	var request = _player_card_action_request(index)
	var core_can_accept := _combat_core_allows_action_request(request, player_can_act)
	var tactical_can_play := _tactical_card_gate_allows(index, core_can_accept, player_can_act)
	return {
		"control_mode": get_control_mode_name(),
		"combat_state": combat_state_machine.state_name() if combat_state_machine != null else "None",
		"combat_phase": combat_state_machine.current_phase_name() if combat_state_machine != null else "None",
		"frame_advantage": frame_advantage,
		"reward_value": _player_reward_frame_value(),
		"reward_window_active": _player_reward_window_active(),
		"player_phase": _player_phase_for_log(),
		"player_can_act": player_can_act,
		"player_action_locked": not player_can_act,
		"player_lock_reason": _player_action_lock_reason() if not player_can_act else "",
		"enemy_phase": _enemy_phase_for_log(),
		"queue_empty": queue_resolver == null or queue_resolver.is_empty(),
		"queue_resolving": _queue_is_resolving(),
		"core_can_accept": core_can_accept,
		"tactical_can_play": tactical_can_play,
		"action_request": request.to_dict() if request != null and request.has_method("to_dict") else {}
	}

func _tactical_card_gate_allows(index: int, core_can_accept: bool, player_can_act: bool) -> bool:
	if is_power_action_mode() or not fight_started or combat_over:
		return false
	if index < 0 or index >= deck_manager.hand.size():
		return false
	if _is_card_instance_queued(deck_manager.hand[index]):
		return false
	if not player_can_act or not core_can_accept:
		return false
	if _is_reaction_window_state() or _is_slow_neutral_state() or _is_enemy_intent_state():
		return true
	return can_play_cards()

func get_card_prediction(index: int) -> String:
	if not show_prediction_assist:
		return "normal"
	if index < 0 or index >= deck_manager.hand.size():
		return "normal"
	if _is_enemy_intent_state():
		return _predict_enemy_intent_card_outcome(deck_manager.hand[index])
	if _player_reward_window_active() and _can_take_pressure_movement():
		return _predict_pressure_card_outcome(index, deck_manager.hand[index])
	return "normal"

func _player_card_action_request(index := -1):
	var card: Resource = null
	if index >= 0 and index < deck_manager.hand.size():
		card = deck_manager.hand[index]
	if card == null:
		var request = ActionRequestScript.new()
		request.actor_id = "player"
		request.action_id = "card"
		request.source_type = ActionRequestScript.SourceType.CARD
		request.input_frame = Engine.get_process_frames()
		request.queued_index = index
		return request
	if tactical_mode_controller != null:
		return tactical_mode_controller.action_request_from_card(card, index, Engine.get_process_frames())
	return ActionRequestScript.from_card("player", card, index, Engine.get_process_frames())

func _combat_core_allows_action_request(action_request, actor_action_ready := true) -> bool:
	if combat_core != null:
		return combat_core.can_submit_action_request(action_request, _player_reward_frame_value(), actor_action_ready)
	if combat_state_machine != null:
		return combat_state_machine.can_accept_action_request(action_request, _player_reward_frame_value(), actor_action_ready)
	return actor_action_ready

func _enemy_ai_action_request(action_id: String):
	var request := ActionRequestScript.new()
	request.actor_id = "enemy"
	request.action_id = action_id
	request.source_type = ActionRequestScript.SourceType.AI
	request.input_frame = Engine.get_process_frames()
	return request

func _enemy_attacks() -> Dictionary:
	if enemy != null and enemy.has_method("get_attacks"):
		return enemy.get_attacks()
	return Enemy.ATTACKS

func _enemy_attack_data(action_id: String) -> Dictionary:
	var attacks := _enemy_attacks()
	if attacks.has(action_id):
		return attacks[action_id] as Dictionary
	return {}

func _enemy_attack_hit_level(action_id: String) -> String:
	var attack := _enemy_attack_data(action_id)
	return String(attack.get("hit_level", attack.get("type", action_id))) if not attack.is_empty() else action_id

func _enemy_attack_priority_ids() -> Array[String]:
	var attacks := _enemy_attacks()
	var ids: Array[String] = []
	for action_id in ["MID", "light_punch", "light_kick", "HIGH", "heavy_kick", "OVERHEAD", "heavy_punch", "LOW"]:
		if attacks.has(action_id) and not ids.has(action_id):
			ids.append(action_id)
	for action_id in attacks.keys():
		var id := String(action_id)
		if not ids.has(id):
			ids.append(id)
	return ids

func play_card(index: int) -> void:
	_repair_invalid_combat_state()
	if is_power_action_mode():
		log_message.emit("Card input ignored in POWER_ACTION. Use direct attacks.")
		return
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

func request_direct_action(input_name: String, move_id: String) -> void:
	_repair_invalid_combat_state()
	if not is_power_action_mode():
		log_message.emit("Direct input ignored in TIME_TACTICAL: %s." % input_name)
		return
	if combat_over or not fight_started:
		log_message.emit("Direct input rejected: fight has not started.")
		_record_rejected_action("player", "fight_not_started", move_id)
		return
	var card := _direct_move_card(move_id)
	if card == null:
		log_message.emit("Direct input rejected: no move data for %s." % move_id)
		_record_rejected_action("player", "missing_move_data", move_id)
		return
	var request = _player_direct_action_request(input_name, move_id, card)
	var power_action_reject_reason := _power_action_player_reject_reason()
	if power_action_reject_reason != "":
		log_message.emit("Direct input rejected: %s." % power_action_reject_reason)
		_record_rejected_action("player", power_action_reject_reason, move_id)
		return
	if combat_core != null and not combat_core.submit_action_request(request, frame_advantage, true):
		var core_reject_reason: String = String(combat_core.last_rejection_reason)
		log_message.emit("Direct input rejected by CombatCore: %s." % core_reject_reason)
		_record_rejected_action("player", core_reject_reason, move_id)
		return
	log_message.emit("Direct input action requested: mode=%s input=%s move_id=%s source=%s state=%s." % [
		get_control_mode_name(),
		input_name,
		move_id,
		request.source_type_name(),
		combat_state_machine.state_name() if combat_state_machine != null else "Unknown"
	])
	_record_combat_event("direct_input_action_requested", "Direct input created ActionRequest.", {
		"mode": get_control_mode_name(),
		"input_name": input_name,
		"move_id": move_id,
		"action_request": request.to_dict(),
		"combat_state": combat_state_machine.state_name() if combat_state_machine != null else "Unknown"
	})
	if _is_reaction_window_state() or _is_enemy_intent_state():
		log_message.emit("Challenge attempt started.")
		await _try_interrupt_with_direct_card(card, request)
		return
	_cancel_enemy_recovery_for_power_action_punish(move_id)
	pending_player_action_request_override = request
	await _resolve_player_card(card, 0, true, false, false, true, true, "direct_input")

func _direct_move_card(move_id: String) -> Resource:
	if deck_manager == null:
		return null
	if not ("card_library" in deck_manager):
		return null
	var card_library: Dictionary = deck_manager.card_library
	if not card_library.has(move_id):
		return null
	var source_card := card_library[move_id] as Resource
	if source_card == null:
		return null
	var card := source_card.duplicate()
	card.instance_id = 0
	return card

func _player_direct_action_request(input_name: String, move_id: String, card: Resource):
	if power_fighting_mode_controller != null:
		return power_fighting_mode_controller.action_request_for_input(input_name, move_id, Engine.get_process_frames(), {
			"display_name": card.display_name if card != null else move_id,
			"move_id": move_id,
			"temporary_move_data": "renka_card_definition"
		})
	return ActionRequestScript.from_direct_input("player", move_id, input_name, Engine.get_process_frames(), 0, {
		"display_name": card.display_name if card != null else move_id,
		"move_id": move_id,
		"temporary_move_data": "renka_card_definition"
	})

func _power_action_player_reject_reason() -> String:
	if combat_over:
		return "combat_over"
	if not fight_started:
		return "fight_not_started"
	if _queue_is_resolving() or queued_action_in_progress:
		return "queue_executing"
	if _player_action_locked():
		return _player_action_lock_reason()
	if player_trade_recovery_frames_remaining > 0.0:
		return "player_trade_recovery"
	if combat_state_machine != null:
		if combat_state_machine.current_state == CombatStateMachineScript.State.ENEMY_ACTIVE:
			return "enemy_active"
		if combat_state_machine.current_state == CombatStateMachineScript.State.HITSTOP:
			return "hitstop"
		if combat_state_machine.current_state == CombatStateMachineScript.State.GAME_OVER:
			return "game_over"
	return ""

func _power_action_player_can_act() -> bool:
	return is_power_action_mode() and _power_action_player_reject_reason() == ""

func _power_action_enemy_can_act() -> bool:
	return is_power_action_mode() and _enemy_power_action_reject_reason() == ""

func _cancel_enemy_recovery_for_power_action_punish(move_id: String) -> void:
	if not is_power_action_mode() or combat_state_machine == null:
		return
	if combat_state_machine.current_state != CombatStateMachineScript.State.ENEMY_RECOVERY:
		return
	if enemy_action_recovery_frames_remaining <= 0.0:
		return
	log_message.emit("POWER_ACTION punish input during enemy recovery: %s." % move_id)
	enemy_action_recovery_frames_remaining = 0.0
	power_action_enemy_recovery_frame_accumulator = 0.0
	attack_in_progress = false
	waiting_for_defense = false
	current_enemy_action_request = null
	current_enemy_intent = ""
	remaining_startup_frames = 0
	hitbox_system.finish_enemy_move()
	if enemy != null:
		if enemy.has_method("finish_attack"):
			enemy.finish_attack()
		elif enemy.has_method("clear_intent"):
			enemy.clear_intent()

func request_power_action_block(pressed: bool) -> void:
	if not is_power_action_mode():
		return
	if pressed:
		if power_action_block_held:
			return
		var reject_reason := _power_action_block_reject_reason()
		if reject_reason != "":
			_log_defensive_input_rejected("block", reject_reason, false, _player_can_enter_neutral_crouch())
			return
		power_action_block_held = true
		power_action_block_defense_type = "crouch_block" if Input.is_key_pressed(KEY_S) else "block"
		power_action_block_startup_frames_remaining = float(power_action_block_startup_frames)
		power_action_block_startup_accumulator = 0.0
		if combat_core != null:
			combat_core.begin_block("player", power_action_block_defense_type, power_action_block_startup_frames)
		if player != null and player.has_method("show_timeline_phase"):
			player.show_timeline_phase(power_action_block_defense_type, "STARTUP", 0.0, "", false)
		log_message.emit("BLOCK_START: %s." % _defense_display_name(power_action_block_defense_type))
		_record_combat_event("BLOCK_START", "BLOCK_START", {
			"actor": "player",
			"defense_type": power_action_block_defense_type,
			"startup_frames": power_action_block_startup_frames
		})
		return
	if not power_action_block_held and power_action_block_defense_type == "":
		return
	var block_action_pressed: bool = Input.is_action_pressed("block")
	var key_l_pressed: bool = Input.is_key_pressed(KEY_L)
	if block_action_pressed or key_l_pressed:
		_record_combat_event("BLOCK_RELEASE_IGNORED", "BLOCK_RELEASE_IGNORED", {
			"actor": "player",
			"defense_type": power_action_block_defense_type,
			"source": "input_key_up",
			"input_block_pressed": block_action_pressed,
			"input_key_l_pressed": key_l_pressed,
			"held_flag_before": power_action_block_held,
			"core_block_held_before": combat_core.is_block_held("player") if combat_core != null else false,
			"core_block_active_before": combat_core.is_block_active("player") if combat_core != null else false
		})
		log_message.emit("BLOCK_RELEASE ignored: block input still held.")
		return
	var release_defense_type: String = power_action_block_defense_type
	var held_flag_before: bool = power_action_block_held
	var core_block_held_before: bool = combat_core.is_block_held("player") if combat_core != null else false
	var core_block_active_before: bool = combat_core.is_block_active("player") if combat_core != null else false
	power_action_block_held = false
	power_action_block_startup_frames_remaining = 0.0
	power_action_block_startup_accumulator = 0.0
	if combat_core != null:
		combat_core.release_block("player")
	if combat_animation_controller != null:
		combat_animation_controller.release_block_visual("player")
	elif player != null and player.has_method("release_block_action"):
		player.release_block_action()
	log_message.emit("BLOCK_RELEASE.")
	_record_combat_event("BLOCK_RELEASE", "BLOCK_RELEASE", {
		"actor": "player",
		"defense_type": release_defense_type,
		"source": "input_key_up",
		"input_block_pressed": block_action_pressed,
		"input_key_l_pressed": key_l_pressed,
		"held_flag_before": held_flag_before,
		"held_flag_after": power_action_block_held,
		"core_block_held_before": core_block_held_before,
		"core_block_active_before": core_block_active_before,
		"core_block_held_after": combat_core.is_block_held("player") if combat_core != null else false,
		"core_block_active_after": combat_core.is_block_active("player") if combat_core != null else false
	})
	power_action_block_defense_type = ""

func _power_action_block_reject_reason() -> String:
	if combat_over:
		return "combat_over"
	if not fight_started:
		return "fight_not_started"
	if player_trade_recovery_frames_remaining > 0.0:
		return "player_trade_recovery"
	if _queue_is_resolving() or queued_action_in_progress:
		return "queue_executing"
	if player != null and player.has_method("get_stance_state_name") and String(player.get_stance_state_name()) != "NORMAL":
		return "broken"
	var debug := _player_debug()
	var logic_state := String(debug.get("logic_state", debug.get("action_state", "NEUTRAL"))).to_lower()
	if logic_state.find("hitstun") != -1:
		return "hitstun"
	if logic_state.find("blockstun") != -1:
		return "blockstun"
	if logic_state.find("attack_startup") != -1 or logic_state.find("attack_active") != -1 or logic_state.find("attack_recovery") != -1:
		return "action_locked"
	if _player_action_locked():
		return _player_action_lock_reason()
	return ""

func _tick_power_action_block(delta: float) -> void:
	if not power_action_block_held or power_action_block_startup_frames_remaining <= 0.0:
		return
	var tick: Dictionary = _consume_gameplay_frames(delta, power_action_block_startup_accumulator)
	power_action_block_startup_accumulator = float(tick.get("accumulator", power_action_block_startup_accumulator))
	var frames := int(tick.get("frames", 0))
	if frames <= 0:
		return
	var became_active: bool = combat_core.tick_block("player", frames) if combat_core != null else false
	power_action_block_startup_frames_remaining = float(combat_core.block_startup_remaining("player")) if combat_core != null else maxf(0.0, power_action_block_startup_frames_remaining - float(frames))
	var progress: float = combat_core.block_progress("player") if combat_core != null else 1.0 - (power_action_block_startup_frames_remaining / maxf(1.0, float(power_action_block_startup_frames)))
	if player != null and player.has_method("show_timeline_phase"):
		player.show_timeline_phase(power_action_block_defense_type, "STARTUP", clampf(progress, 0.0, 1.0), "", false)
	if became_active or power_action_block_startup_frames_remaining <= 0.0:
		if player != null and player.has_method("show_timeline_phase"):
			player.show_timeline_phase(power_action_block_defense_type, "ACTIVE", 1.0, "", false)
		log_message.emit("BLOCK_ACTIVE: %s." % _defense_display_name(power_action_block_defense_type))
		_record_combat_event("BLOCK_ACTIVE", "BLOCK_ACTIVE", {
			"actor": "player",
			"defense_type": power_action_block_defense_type
		})

func _current_power_action_block_defense() -> String:
	if not is_power_action_mode():
		return ""
	if combat_core != null:
		return combat_core.block_defense_type("player")
	if not power_action_block_held or power_action_block_startup_frames_remaining > 0.0:
		return ""
	return power_action_block_defense_type

func _clear_power_action_block_state(reason := "internal_clear") -> void:
	var was_held: bool = power_action_block_held
	var was_core_held: bool = combat_core.is_block_held("player") if combat_core != null else false
	var was_core_active: bool = combat_core.is_block_active("player") if combat_core != null else false
	if was_held or was_core_held or power_action_block_defense_type != "":
		_record_combat_event("BLOCK_INTERNAL_CLEAR", "BLOCK_INTERNAL_CLEAR", {
			"actor": "player",
			"reason": reason,
			"defense_type": power_action_block_defense_type,
			"input_block_pressed": Input.is_action_pressed("block"),
			"input_key_l_pressed": Input.is_key_pressed(KEY_L),
			"held_flag_before": was_held,
			"core_block_held_before": was_core_held,
			"core_block_active_before": was_core_active
		})
	power_action_block_held = false
	power_action_block_defense_type = ""
	power_action_block_startup_frames_remaining = 0.0
	power_action_block_startup_accumulator = 0.0
	if combat_core != null:
		combat_core.clear_block("player")

func _on_player_defense(defense_type: String) -> void:
	last_defense = defense_type
	if _is_enemy_intent_state():
		_resolve_enemy_intent(defense_type)

func _on_player_defensive_input_rejected(input_name: String, reason: String) -> void:
	_log_defensive_input_rejected(input_name, reason, _power_action_block_reject_reason() == "", _player_can_enter_neutral_crouch())

func _log_defensive_input_rejected(input_name: String, reject_reason: String, can_block: bool, can_crouch: bool) -> void:
	var event_type := "BLOCK_REJECTED" if input_name == "block" else "DEFENSIVE_INPUT_REJECTED"
	var recovery_remaining := maxi(
		int(ceil(player_action_lifecycle_recovery_frames_remaining)),
		int(ceil(player_trade_recovery_frames_remaining))
	)
	var data: Dictionary = {
		"actor": "player",
		"input_name": input_name,
		"reason": reject_reason,
		"reject_reason": reject_reason,
		"global_combat_state": _current_mode(),
		"player_action_phase": _player_phase_for_log(),
		"player_phase": _player_phase_for_log(),
		"player_recovery_remaining": recovery_remaining,
		"can_crouch": can_crouch,
		"can_block": can_block,
		"enemy_phase": _enemy_phase_for_log(),
		"frame_advantage": frame_advantage
	}
	log_message.emit("%s: %s player_action_phase=%s recovery=%d can_crouch=%s can_block=%s." % [
		event_type,
		reject_reason,
		String(data["player_action_phase"]),
		recovery_remaining,
		str(can_crouch),
		str(can_block)
	])
	_record_combat_event(event_type, event_type, data)

func _player_can_enter_neutral_crouch() -> bool:
	return player != null and player.has_method("can_enter_neutral_crouch") and bool(player.can_enter_neutral_crouch())

func _tick_power_action_neutral_crouch() -> void:
	if not is_power_action_mode() or player == null or not player.has_method("set_combat_crouch"):
		return
	var wants_crouch := _power_action_crouch_input_pressed()
	var reject_reason := _power_action_crouch_reject_reason()
	var can_crouch := reject_reason == ""
	var should_crouch := wants_crouch and can_crouch
	if wants_crouch and not can_crouch:
		if reject_reason != last_power_action_crouch_reject_reason:
			last_power_action_crouch_reject_reason = reject_reason
			_log_defensive_input_rejected("crouch", reject_reason, false, false)
	else:
		last_power_action_crouch_reject_reason = ""
	if bool(player.is_crouching()) != should_crouch:
		player.set_combat_crouch(should_crouch)
	if should_crouch != last_power_action_crouching:
		last_power_action_crouching = should_crouch
		var defender_state := "crouching" if should_crouch else "standing"
		log_message.emit("CROUCH_STATE_CHANGED: %s." % defender_state)
		_record_combat_event("CROUCH_STATE_CHANGED", "CROUCH_STATE_CHANGED", {
			"actor": "player",
			"crouching": should_crouch,
			"defender_state": defender_state,
			"control_mode": get_control_mode_name(),
			"combat_state": _current_mode(),
			"player_phase": _player_phase_for_log(),
			"enemy_phase": _enemy_phase_for_log()
		})

func _power_action_crouch_input_pressed() -> bool:
	return Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or Input.is_action_pressed("ui_down")

func _power_action_crouch_reject_reason() -> String:
	if combat_over:
		return "combat_over"
	if not fight_started:
		return "fight_not_started"
	if player_trade_recovery_frames_remaining > 0.0:
		return "player_trade_recovery"
	if _queue_is_resolving() or queued_action_in_progress:
		return "queue_executing"
	if combat_state_machine != null:
		if combat_state_machine.current_state == CombatStateMachineScript.State.HITSTOP:
			return "hitstop"
		if combat_state_machine.current_state == CombatStateMachineScript.State.GAME_OVER:
			return "game_over"
	if player != null and player.has_method("get_stance_state_name") and String(player.get_stance_state_name()) != "NORMAL":
		return "broken"
	var debug := _player_debug()
	var logic_state := String(debug.get("logic_state", debug.get("action_state", "NEUTRAL"))).to_lower()
	if logic_state.find("hitstun") != -1:
		return "hitstun"
	if logic_state.find("blockstun") != -1:
		return "blockstun"
	if logic_state.find("attack_startup") != -1 or logic_state.find("attack_active") != -1 or logic_state.find("attack_recovery") != -1:
		return "action_locked"
	if _player_action_locked():
		return _player_action_lock_reason()
	return ""

func _log_power_action_movement_gate() -> void:
	if not is_power_action_mode():
		last_power_action_movement_gate = ""
		return
	var movement_pressed := Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_W)
	if not movement_pressed:
		last_power_action_movement_gate = ""
		return
	var allowed := _power_action_movement_allowed()
	var gate := "movement_allowed" if allowed else "movement_rejected"
	var reject_reason := "" if allowed else _power_action_movement_reject_reason()
	var gate_key := "%s:%s:%s" % [gate, _current_mode(), reject_reason]
	if gate_key == last_power_action_movement_gate:
		return
	last_power_action_movement_gate = gate_key
	log_message.emit("%s: state=%s mode=%s reason=%s." % [gate, _current_mode(), get_control_mode_name(), reject_reason if reject_reason != "" else "ok"])
	_record_combat_event(gate.to_upper(), gate.to_upper(), {
		"control_mode": get_control_mode_name(),
		"combat_state": _current_mode(),
		"movement_allowed": allowed,
		"reject_reason": reject_reason,
		"movement_flow_active": _movement_flow_active(),
		"player_phase": _player_phase_for_log(),
		"enemy_phase": _enemy_phase_for_log()
	})

func _power_action_movement_allowed() -> bool:
	return is_power_action_mode() and _power_action_movement_reject_reason() == ""

func _power_action_movement_reject_reason() -> String:
	if combat_over:
		return "combat_over"
	if not fight_started:
		return "fight_not_started"
	if combat_state_machine == null:
		return "missing_state_machine"
	if _power_action_player_reject_reason() != "":
		return _power_action_player_reject_reason()
	return ""

func _tick_power_action_live_movement(delta: float) -> void:
	if not is_power_action_mode() or combat_over or movement_flow_system == null:
		return
	if _is_slow_neutral_state():
		return
	var movement_pressed := Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D)
	var jump_active := bool(movement_flow_system.jump_phase != "DONE")
	var step_active := bool(movement_flow_system.movement_phase != "DONE")
	if not movement_pressed and not jump_active and not step_active:
		return
	if not _power_action_movement_allowed():
		return
	if not _movement_flow_active():
		movement_flow_system.enter("POWER_ACTION live movement enabled.")
	movement_flow_system.tick(delta, false)

func _unhandled_key_input(event: InputEvent) -> void:
	combat_input_router.route_key_event(event, self, get_viewport())

func _run_enemy_attack(start_reaction := true) -> void:
	if combat_over:
		return
	if is_power_action_mode():
		if _enemy_power_action_locked():
			_record_power_action_enemy_rejection(_enemy_power_action_reject_reason())
			return
		_record_power_action_enemy_decision_gate("allowed", "enemy actor can start action")
	elif frame_advantage > 0 or combat_state_machine.is_enemy_flow_state():
		return
	if not fight_started:
		return

	last_power_action_enemy_reject_reason = ""
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
	var use_reaction_window := start_reaction and not is_power_action_mode()
	if use_reaction_window:
		queue_resolver.clear()
	_reset_pressure_sequence()
	enemy.start_attack(String(ai_decision.get("action_id", "")))
	current_enemy_intent = enemy.current_attack
	current_enemy_action_request = _enemy_ai_action_request(current_enemy_intent)
	var enemy_attack_data := _enemy_attack_data(current_enemy_intent)
	if enemy_attack_data.is_empty():
		log_message.emit("Enemy intent aborted: missing attack data for %s." % current_enemy_intent)
		enemy.clear_intent()
		attack_in_progress = false
		waiting_for_defense = false
		_enter_slow_neutral("Slow neutral movement started.")
		return
	enemy_base_startup_frame = int(enemy_attack_data["startup_frame"])
	enemy_effective_startup_frame = int(ai_decision.get("effective_startup", frame_system.effective_startup(enemy_base_startup_frame, initiative_offset)))
	if is_power_action_mode():
		enemy_effective_startup_frame = maxi(1, int(ceil(float(enemy_effective_startup_frame) * power_action_enemy_startup_multiplier)))
		_record_power_action_enemy_decision(ai_decision, enemy_attack_data, enemy_effective_startup_frame)
	if initiative_offset != 0:
		log_message.emit("Enemy next startup modified by %s." % _signed_int(initiative_offset))
	initiative_offset = 0
	remaining_startup_frames = enemy_effective_startup_frame
	var enemy_move_def: MoveDefinition = hitbox_system.begin_enemy_move(current_enemy_intent, enemy_attack_data, enemy_effective_startup_frame)
	combat_timeline.begin_from_move("ENEMY", enemy_move_def)
	_record_action_lifecycle_event("ACTION_STARTUP_BEGIN", {
		"actor": "enemy",
		"move_id": current_enemy_intent,
		"source_type": _action_request_source_name(current_enemy_action_request),
		"startup_frames": enemy_effective_startup_frame
	})
	_show_enemy_timeline_phase()
	if use_reaction_window:
		_start_reaction_window(_enemy_attack_hit_level(current_enemy_intent), enemy_effective_startup_frame)
		_transition_combat_state(CombatStateMachineScript.State.REACTION_WINDOW, "reaction window started")
	elif start_reaction and is_power_action_mode():
		power_action_enemy_startup_frame_accumulator = 0.0
		log_message.emit("POWER_ACTION enemy startup running in real time: %df." % enemy_effective_startup_frame)
	last_player_action_startup = 0
	player.set_free_movement_enabled(false)
	log_message.emit("Enemy intent: %s." % enemy.current_attack)
	log_message.emit("%s; starting %s." % [approach_end_reason, enemy.current_attack])
	log_message.emit("Real-time attack: defend, move, or challenge." if is_power_action_mode() and start_reaction else ("Slow time: react before impact." if start_reaction else "Enemy intent opened for queued action."))
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

func _record_power_action_enemy_decision_gate(result: String, reason: String, move_id := "") -> void:
	last_enemy_decision_frame = Engine.get_physics_frames()
	last_enemy_decision_msec = Time.get_ticks_msec()
	_record_combat_event("ENEMY_DECISION_GATE", "POWER_ACTION enemy decision gate: %s." % result, {
		"control_mode": get_control_mode_name(),
		"decision_frame": last_enemy_decision_frame,
		"decision_timestamp_msec": last_enemy_decision_msec,
		"selected_move": move_id,
		"result": result,
		"reason": reason,
		"time_since_last_enemy_action_done_frames": _frames_since_last_enemy_action_done(),
		"time_since_last_enemy_action_done_msec": _msec_since_last_enemy_action_done(),
		"enemy_recovery_frames_remaining": int(ceil(enemy_action_recovery_frames_remaining)),
		"enemy_active_frames_remaining": int(ceil(power_action_enemy_active_frames_remaining)),
		"enemy_startup_frames_remaining": remaining_startup_frames,
		"enemy_decision_cooldown_remaining": int(ceil(power_action_enemy_decision_cooldown_remaining)),
		"enemy_hitstun_frames_remaining": enemy_vulnerable_frames_remaining,
		"enemy_break_frames_remaining": _enemy_break_frames_remaining(),
		"global_combat_state": _current_mode(),
		"enemy_phase": _enemy_phase_for_log()
	})

func _record_power_action_enemy_decision(decision: Dictionary, attack_data: Dictionary, effective_startup: int) -> void:
	var selected_move := String(decision.get("action_id", attack_data.get("id", current_enemy_intent)))
	var base_recovery := int(attack_data.get("recovery", 0))
	var power_recovery := maxi(1, int(ceil(float(base_recovery) * power_action_enemy_recovery_multiplier)))
	var active_frames := int(attack_data.get("active", 1))
	var animation_debug := _animation_debug_for(enemy, "enemy")
	_record_combat_event("ENEMY_DECISION", "POWER_ACTION enemy selected %s." % selected_move, {
		"control_mode": get_control_mode_name(),
		"decision_frame": last_enemy_decision_frame,
		"decision_timestamp_msec": last_enemy_decision_msec,
		"selected_move": selected_move,
		"time_since_last_enemy_action_done_frames": _frames_since_last_enemy_action_done(),
		"time_since_last_enemy_action_done_msec": _msec_since_last_enemy_action_done(),
		"allowed_reason": "enemy actor can start action",
		"ai_reason": String(decision.get("reason", "")),
		"ai_score": float(decision.get("score", 0.0)),
		"ai_spacing": String(decision.get("spacing", "")),
		"move_data_source": "%s.get_attacks reused directly in POWER_ACTION" % [enemy.get_class() if enemy != null else "Enemy"],
		"authored_startup_frames": int(attack_data.get("startup_frame", attack_data.get("startup", 0))),
		"effective_startup_frames": effective_startup,
		"startup_multiplier": power_action_enemy_startup_multiplier,
		"active_frames": active_frames,
		"authored_recovery_frames": base_recovery,
		"power_action_recovery_frames": power_recovery,
		"recovery_multiplier": power_action_enemy_recovery_multiplier,
		"decision_cooldown_frames": power_action_enemy_decision_cooldown_frames,
		"attack_level": String(attack_data.get("attack_level", attack_data.get("hit_level", ""))),
		"animation_key": String(attack_data.get("animation_key", selected_move)),
		"animation_state_at_decision": animation_debug
	})

func _frames_since_last_enemy_action_done() -> int:
	if last_enemy_action_done_frame < 0:
		return -1
	return maxi(0, Engine.get_physics_frames() - last_enemy_action_done_frame)

func _msec_since_last_enemy_action_done() -> int:
	if last_enemy_action_done_msec < 0:
		return -1
	return maxi(0, Time.get_ticks_msec() - last_enemy_action_done_msec)

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
		var fallback_data := _enemy_attack_data(fallback_attack)
		var startup: int = frame_system.effective_startup(int(fallback_data["startup_frame"]), initiative_offset)
		return {
			"action_id": fallback_attack,
			"action": fallback_data,
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
	for action_id in _enemy_attack_priority_ids():
		var action: Dictionary = _enemy_attack_data(action_id)
		if action.is_empty():
			continue
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
	if combat_over or combat_state_machine.is_enemy_flow_state() or _is_punish_state() or (is_time_tactical_mode() and frame_advantage > 0):
		return
	_transition_combat_state(CombatStateMachineScript.State.SLOW_NEUTRAL, message)
	movement_flow_system.enter(message)

func _exit_slow_neutral() -> void:
	movement_flow_system.exit()

func _tick_slow_neutral(delta: float) -> void:
	if not _is_slow_neutral_state() or not _movement_flow_active() or combat_over:
		return
	if combat_state_machine.is_enemy_flow_state() or _is_punish_state() or (is_time_tactical_mode() and frame_advantage > 0):
		_exit_slow_neutral()
		return

	var allow_enemy_approach := true
	if is_power_action_mode():
		allow_enemy_approach = _power_action_enemy_can_act()
	var result: Dictionary = movement_flow_system.tick(delta, allow_enemy_approach)
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
	if _player_action_lifecycle_blocks_card_input():
		return true
	if player == null or not player.has_method("can_start_card_action"):
		return false
	if bool(player.can_start_card_action()):
		return false
	if not _player_has_real_action_lifecycle():
		if not _player_visual_return_pending():
			_clear_stale_player_action()
		return false
	return true

func _player_action_lock_reason() -> String:
	if player_trade_recovery_frames_remaining > 0.0:
		return "trade recovery remaining=%df frame_advantage=%d" % [int(ceil(player_trade_recovery_frames_remaining)), frame_advantage]
	if _player_action_lifecycle_blocks_card_input():
		return "manager lifecycle action=%s phase=%s recovery=%df release=%s frame_advantage=%d" % [
			player_action_lifecycle_action_id,
			player_action_lifecycle_phase,
			int(ceil(player_action_lifecycle_recovery_frames_remaining)),
			str(player_action_lifecycle_release_authorized),
			frame_advantage
		]
	if player != null and player.has_method("card_action_rejection_reason"):
		return "%s frame_advantage=%d" % [String(player.card_action_rejection_reason()), frame_advantage]
	return "player action is still recovering"

func _open_player_followup_window(reason := "") -> void:
	if not is_time_tactical_mode():
		log_message.emit("POWER_ACTION suppressed tactical follow-up window: %s." % (reason if reason != "" else "follow-up window"))
		_update_time_scale()
		return
	if _player_has_stale_idle_lock():
		_clear_stale_player_action()
	_authorize_player_action_lifecycle_release("followup_window_open")
	if player != null and player.has_method("open_followup_window"):
		player.open_followup_window()
	log_message.emit("PLAYER_REWARD set for follow-up: action=%s recovery_frames=%d reward_value=%d reason=%s." % [
		player_action_lifecycle_action_id,
		int(ceil(player_action_lifecycle_recovery_frames_remaining)),
		_player_reward_frame_value(),
		reason if reason != "" else "follow-up window"
	])
	_enter_player_reward_window(reason if reason != "" else "follow-up window")
	if reason != "":
		log_message.emit(reason)

func _open_trade_followup_window(reason := "") -> void:
	if not is_time_tactical_mode():
		log_message.emit("POWER_ACTION suppressed tactical trade follow-up window: %s." % (reason if reason != "" else "trade follow-up window"))
		_update_time_scale()
		return
	if player != null and player.has_method("open_followup_window"):
		player.open_followup_window()
	log_message.emit("PLAYER_REWARD set for post-trade follow-up: action=%s recovery_frames=0 reward_value=%d reason=%s." % [
		player_action_lifecycle_action_id,
		_player_reward_frame_value(),
		reason if reason != "" else "trade follow-up window"
	])
	_enter_player_reward_window(reason if reason != "" else "trade follow-up window")
	if reason != "":
		log_message.emit(reason)

func _enter_player_reward_window(reason := "") -> void:
	if not is_time_tactical_mode():
		log_message.emit("POWER_ACTION suppressed PLAYER_REWARD window: reason=%s frame_advantage=%d stance_frames=%d reward_value=%d." % [
			reason if reason != "" else "reward",
			frame_advantage,
			_enemy_break_frames_remaining(),
			_player_reward_frame_value()
		])
		_update_time_scale()
		return
	var reward_value := _player_reward_frame_value()
	log_message.emit("PLAYER_REWARD window active: reason=%s frame_advantage=%d stance_frames=%d reward_value=%d." % [
		reason if reason != "" else "reward",
		frame_advantage,
		_enemy_break_frames_remaining(),
		reward_value
	])
	_transition_combat_state(CombatStateMachineScript.State.PLAYER_PRESSURE, reason if reason != "" else "player reward")
	_update_time_scale()

func _player_reward_frame_value() -> int:
	return maxi(frame_advantage, _enemy_break_frames_remaining())

func _player_reward_window_active() -> bool:
	if not is_time_tactical_mode():
		return false
	if combat_over or not fight_started:
		return false
	if player_trade_recovery_frames_remaining > 0.0 or _player_action_lifecycle_blocks_card_input():
		return false
	return _player_reward_frame_value() > 0

func _begin_player_commitment() -> void:
	Engine.time_scale = 1.0

func _start_player_card_action(card: Resource) -> void:
	_begin_player_action_lifecycle(card)
	if pending_player_action_request_override != null:
		current_player_action_request = pending_player_action_request_override
		pending_player_action_request_override = null
	else:
		current_player_action_request = ActionRequestScript.from_card("player", card, -1, Engine.get_process_frames())
	if player != null and player.has_method("perform_card_action"):
		player.perform_card_action(card)

func _wait_for_player_hit_confirm(card: Resource) -> void:
	if not player_action_lifecycle_active or card == null:
		return
	var token := player_action_lifecycle_token
	var hit_frame := maxi(1, int(card.hit_frame))
	log_message.emit("Player action lifecycle wait: %s hit_confirm at %df." % [String(card.id), hit_frame])
	await get_tree().create_timer(_player_action_frames_to_seconds(hit_frame), false, true).timeout
	if token != player_action_lifecycle_token or not player_action_lifecycle_active:
		return
	_set_player_action_lifecycle_phase("ACTIVE", "hit_confirm")
	if combat_timeline != null and combat_timeline.actor == "PLAYER":
		combat_timeline.mark_impact()
		_show_player_timeline_phase()
	log_message.emit("Player action hit confirm authorized by CombatManager: %s." % String(card.id))

func _begin_player_action_lifecycle(card: Resource) -> void:
	player_action_lifecycle_token += 1
	player_action_lifecycle_active = true
	player_action_lifecycle_done = false
	player_action_lifecycle_release_authorized = false
	player_action_lifecycle_release_reason = ""
	player_action_lifecycle_action_id = String(card.id) if card != null else "unknown"
	player_action_lifecycle_card_name = String(card.display_name) if card != null else "Unknown"
	player_action_lifecycle_phase = "STARTUP"
	player_action_lifecycle_recovery_frames_remaining = 0.0
	player_action_lifecycle_recovery_running = false
	power_action_player_recovery_frame_accumulator = 0.0
	log_message.emit("Player action lifecycle start: %s (%s)." % [player_action_lifecycle_action_id, player_action_lifecycle_card_name])
	_record_combat_event("player_action_lifecycle", "Player action lifecycle start.", {
		"action_id": player_action_lifecycle_action_id,
		"card_name": player_action_lifecycle_card_name,
		"phase": player_action_lifecycle_phase,
		"authorized_by": "CombatManager"
	})

func _set_player_action_lifecycle_phase(phase_name: String, reason := "") -> void:
	if player_action_lifecycle_phase == phase_name:
		return
	player_action_lifecycle_phase = phase_name
	var detail := " (%s)" % reason if reason != "" else ""
	log_message.emit("Player action lifecycle phase: %s -> %s%s." % [player_action_lifecycle_action_id, phase_name, detail])
	_record_combat_event("player_action_lifecycle", "Player action lifecycle phase changed.", {
		"action_id": player_action_lifecycle_action_id,
		"card_name": player_action_lifecycle_card_name,
		"phase": phase_name,
		"reason": reason,
		"authorized_by": "CombatManager"
	})

func _player_action_lifecycle_blocks_card_input() -> bool:
	return player_action_lifecycle_active \
		and not player_action_lifecycle_done \
		and not player_action_lifecycle_release_authorized

func player_action_visual_locked() -> bool:
	return (player_action_lifecycle_active and not player_action_lifecycle_done) or player_trade_recovery_frames_remaining > 0.0

func _authorize_player_action_lifecycle_release(reason: String) -> void:
	if not player_action_lifecycle_active or player_action_lifecycle_done:
		return
	if player_action_lifecycle_release_authorized:
		return
	player_action_lifecycle_release_authorized = true
	player_action_lifecycle_release_reason = reason
	log_message.emit("Player action lifecycle release authorized: %s (%s)." % [player_action_lifecycle_action_id, reason])
	_record_combat_event("player_action_lifecycle", "Player action lifecycle release authorized.", {
		"action_id": player_action_lifecycle_action_id,
		"card_name": player_action_lifecycle_card_name,
		"phase": player_action_lifecycle_phase,
		"release_reason": reason,
		"authorized_by": "CombatManager"
	})
	player_action_lifecycle_released.emit(reason)

func _finish_player_action_lifecycle(token: int, reason := "recovery_complete") -> void:
	if token != player_action_lifecycle_token:
		return
	if not player_action_lifecycle_active:
		return
	_set_player_action_lifecycle_phase("DONE", reason)
	player_action_lifecycle_active = false
	player_action_lifecycle_done = true
	player_action_lifecycle_release_authorized = true
	player_action_lifecycle_release_reason = reason
	player_action_lifecycle_recovery_frames_remaining = 0.0
	player_action_lifecycle_recovery_running = false
	power_action_player_recovery_frame_accumulator = 0.0
	current_player_action_request = null
	hitbox_system.finish_player_move()
	if combat_timeline != null and combat_timeline.actor == "PLAYER":
		combat_timeline.finish_action()
	if player != null and player.has_method("finish_action_from_combat_manager"):
		player.finish_action_from_combat_manager(reason)
	log_message.emit("Player action lifecycle done authorized by CombatManager: %s (%s)." % [player_action_lifecycle_action_id, reason])
	_record_combat_event("player_action_lifecycle", "Player action lifecycle done.", {
		"action_id": player_action_lifecycle_action_id,
		"card_name": player_action_lifecycle_card_name,
		"phase": "DONE",
		"reason": reason,
		"authorized_by": "CombatManager"
	})
	_record_action_lifecycle_event("ACTION_DONE", {
		"actor": "player",
		"move_id": player_action_lifecycle_action_id
	})
	player_action_lifecycle_released.emit(reason)
	_handle_power_action_player_lifecycle_done(reason)

func _cancel_player_action_lifecycle(reason := "cancelled", finish_visual := false) -> void:
	if not player_action_lifecycle_active and player_action_lifecycle_done:
		return
	player_action_lifecycle_token += 1
	player_action_lifecycle_active = false
	player_action_lifecycle_done = true
	player_action_lifecycle_release_authorized = true
	player_action_lifecycle_release_reason = reason
	player_action_lifecycle_phase = "DONE"
	player_action_lifecycle_recovery_frames_remaining = 0.0
	player_action_lifecycle_recovery_running = false
	power_action_player_recovery_frame_accumulator = 0.0
	current_player_action_request = null
	hitbox_system.finish_player_move()
	log_message.emit("Player action lifecycle cancelled: %s." % reason)
	if finish_visual and player != null and player.has_method("finish_action_from_combat_manager"):
		player.finish_action_from_combat_manager(reason)
	player_action_lifecycle_released.emit(reason)

func _handle_power_action_player_lifecycle_done(reason: String) -> void:
	if not is_power_action_mode() or combat_over or combat_state_machine == null:
		return
	if _enemy_action_flow_locked():
		_record_combat_event("POWER_ACTION_INITIATIVE_HANDOFF", "POWER_ACTION initiative handoff deferred: enemy locked.", {
			"reason": reason,
			"frame_advantage": frame_advantage,
			"enemy_reject_reason": _enemy_power_action_reject_reason(),
			"combat_state": combat_state_machine.state_name(),
			"enemy_phase": _enemy_phase_for_log()
		})
		return
	var outcome: String = "negative" if frame_advantage < 0 else ("positive" if frame_advantage > 0 else "neutral")
	_record_combat_event("POWER_ACTION_INITIATIVE_HANDOFF", "POWER_ACTION initiative handoff.", {
		"reason": reason,
		"frame_advantage": frame_advantage,
		"outcome": outcome,
		"combat_state_before": combat_state_machine.state_name(),
		"enemy_can_act": _power_action_enemy_can_act(),
		"enemy_reject_reason": _enemy_power_action_reject_reason()
	})
	log_message.emit("POWER_ACTION initiative handoff: %s frame_advantage=%d." % [outcome, frame_advantage])
	_enter_slow_neutral("POWER_ACTION real-time neutral resumed.")
	if frame_advantage < 0:
		call_deferred("_run_enemy_attack", false)

func _begin_player_trade_recovery_lifecycle(card: Resource, recovery_frames: int, action_request = null) -> void:
	player_action_lifecycle_token += 1
	player_action_lifecycle_active = true
	player_action_lifecycle_done = false
	player_action_lifecycle_release_authorized = false
	player_action_lifecycle_release_reason = ""
	player_action_lifecycle_action_id = String(card.id) if card != null else "trade"
	player_action_lifecycle_card_name = String(card.display_name) if card != null else "Trade"
	player_action_lifecycle_phase = "TRADE_RECOVERY"
	player_action_lifecycle_recovery_frames_remaining = float(maxi(0, recovery_frames))
	player_action_lifecycle_recovery_running = true
	power_action_player_recovery_frame_accumulator = 0.0
	current_player_action_request = action_request if action_request != null else (ActionRequestScript.from_card("player", card, -1, Engine.get_process_frames()) if card != null else null)
	hitbox_system.enter_player_recovery()
	log_message.emit("Player trade recovery lifecycle started: action=%s card=%s recovery_frames=%d." % [
		player_action_lifecycle_action_id,
		player_action_lifecycle_card_name,
		recovery_frames
	])
	_record_combat_event("player_action_lifecycle", "Player trade recovery lifecycle started.", {
		"action_id": player_action_lifecycle_action_id,
		"card_name": player_action_lifecycle_card_name,
		"phase": player_action_lifecycle_phase,
		"recovery_frames": recovery_frames,
		"authorized_by": "CombatManager"
	})

func _player_action_frames_to_seconds(frames: int) -> float:
	return maxf(0.01, float(maxi(1, frames)) / PLAYER_ACTION_TIMELINE_FPS)

func _wait_for_player_lifecycle_queue_release(action: Dictionary) -> void:
	if String(action.get("type", "")) != "CARD":
		return
	if queue_resolver.interrupted_by_trade:
		log_message.emit("Queue advance blocked by trade recovery for %s." % String(action.get("id", action.get("display_name", "card"))))
		return
	while player_action_lifecycle_active \
		and not player_action_lifecycle_release_authorized \
		and not player_action_lifecycle_done \
		and not queue_resolver.interrupted_by_trade \
		and not combat_over:
		await player_action_lifecycle_released
	if queue_resolver.interrupted_by_trade:
		log_message.emit("Queue advance blocked by trade recovery for %s." % String(action.get("id", action.get("display_name", "card"))))
		return
	var reason := player_action_lifecycle_release_reason if player_action_lifecycle_release_reason != "" else "lifecycle_done"
	log_message.emit("Queue advance authorized: %s for %s." % [reason, String(action.get("id", action.get("display_name", "card")))])

func _on_player_visual_action_finished(animation_name: String, action_state_name: String) -> void:
	log_message.emit("Renka animation finished report: %s state=%s." % [animation_name, action_state_name])
	if action_state_name == "HITSTUN" and player_trade_recovery_frames_remaining > 0.0:
		log_message.emit("Renka hitstun visual finished; CombatManager keeps trade recovery for %df." % int(ceil(player_trade_recovery_frames_remaining)))
		return
	if action_state_name == "BLOCK_RECOVERY" or action_state_name == "HITSTUN":
		if player != null and player.has_method("finish_action_from_combat_manager"):
			player.finish_action_from_combat_manager("visual_%s_finished" % action_state_name.to_lower())

func get_enemy_approach_target_distance() -> float:
	var usable_range := _closest_enemy_attack_max_range()
	if usable_range <= 0.0:
		return enemy_intent_range
	return minf(enemy_intent_range, maxf(min_duel_distance, usable_range - 2.0))

func _closest_enemy_attack_max_range() -> float:
	var max_range := 0.0
	if enemy == null:
		return max_range
	for action_id in _enemy_attacks().keys():
		var action: Dictionary = _enemy_attacks()[action_id]
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
	var result: Dictionary = reaction_window_system.tick(delta, combat_state_machine.can_tick_reaction_window(), enemy_effective_startup_frame, _enemy_attack_hit_level(current_enemy_intent))
	var progress := _reaction_progress()
	remaining_startup_frames = int(result.get("remaining_startup_frames", remaining_startup_frames))
	if combat_timeline != null:
		combat_timeline.set_startup_progress(progress)
		_show_enemy_timeline_phase()
	if bool(result.get("should_resolve", false)):
		call_deferred("_resolve_reaction_impact")

func _consume_gameplay_frames(delta: float, accumulator: float) -> Dictionary:
	if combat_core != null:
		return combat_core.delta_to_frames(delta, accumulator)
	var next_accumulator := accumulator + (delta * 30.0)
	var frames := int(floor(next_accumulator))
	next_accumulator -= float(frames)
	return {
		"frames": frames,
		"accumulator": next_accumulator
	}

func _frames_for_delta(delta: float) -> float:
	return delta * (CombatCoreScript.GAMEPLAY_FPS if combat_core != null else 30.0)

func _tick_power_action_enemy_intent(delta: float) -> void:
	if not is_power_action_mode() or combat_over or power_action_enemy_impact_resolving:
		return
	if not _is_enemy_intent_state() or _is_reaction_window_state() or remaining_startup_frames <= 0:
		return
	var tick: Dictionary = _consume_gameplay_frames(delta, power_action_enemy_startup_frame_accumulator)
	power_action_enemy_startup_frame_accumulator = float(tick.get("accumulator", power_action_enemy_startup_frame_accumulator))
	var frames := int(tick.get("frames", 0))
	if frames <= 0:
		return
	_advance_enemy_startup(frames)
	if remaining_startup_frames <= 0:
		_begin_power_action_enemy_active()

func _begin_power_action_enemy_active() -> void:
	if combat_over or not is_power_action_mode() or not _is_enemy_intent_state():
		return
	remaining_startup_frames = 0
	power_action_enemy_impact_resolving = true
	_begin_enemy_resolution()
	power_action_enemy_active_result = enemy.resolve_attack()
	if power_action_enemy_active_result.is_empty():
		power_action_enemy_impact_resolving = false
		_finish_enemy_resolution("resolve_attack_empty_before_active")
		return
	power_action_enemy_active_frames_remaining = float(maxi(1, int(power_action_enemy_active_result.get("active", 1))))
	power_action_enemy_active_frame_accumulator = 0.0
	power_action_enemy_active_resolved = false
	_record_action_lifecycle_event("ACTION_ACTIVE_BEGIN", {
		"actor": "enemy",
		"move_id": String(power_action_enemy_active_result.get("id", current_enemy_intent)),
		"active_frames": int(ceil(power_action_enemy_active_frames_remaining)),
		"action_active_begin_frame": Engine.get_physics_frames(),
		"animation_state_at_active_begin": _animation_debug_for(enemy, "enemy")
	})

func _tick_power_action_enemy_active(delta: float) -> void:
	if not is_power_action_mode() or combat_over:
		return
	if combat_state_machine == null or combat_state_machine.current_state != CombatStateMachineScript.State.ENEMY_ACTIVE:
		return
	if power_action_enemy_active_frames_remaining <= 0.0 or power_action_enemy_active_result.is_empty():
		return
	var tick: Dictionary = _consume_gameplay_frames(delta, power_action_enemy_active_frame_accumulator)
	power_action_enemy_active_frame_accumulator = float(tick.get("accumulator", power_action_enemy_active_frame_accumulator))
	var frames := int(tick.get("frames", 0))
	if frames <= 0:
		return
	if not power_action_enemy_active_resolved:
		power_action_enemy_active_resolved = _check_power_action_enemy_active_overlap()
	power_action_enemy_active_frames_remaining = maxf(0.0, power_action_enemy_active_frames_remaining - float(frames))
	if combat_timeline != null and combat_timeline.actor == "ENEMY":
		combat_timeline.advance_frames(frames)
		_show_enemy_timeline_phase()
	if power_action_enemy_active_frames_remaining <= 0.0:
		_finish_power_action_enemy_active_window()

func _check_power_action_enemy_active_overlap() -> bool:
	var result: Dictionary = hitbox_system.activate_enemy_attack(power_action_enemy_active_result)
	var overlaps := bool(result.get("overlaps", false))
	if combat_timeline.actor == "ENEMY":
		combat_timeline.mark_active()
		_show_enemy_timeline_phase()
	if not overlaps:
		return false
	var move_id := String(power_action_enemy_active_result.get("id", current_enemy_intent))
	var defense_type := _current_power_action_block_defense()
	if defense_type != "" and _defense_answers_attack(defense_type, power_action_enemy_active_result):
		hitbox_system.trace_last_check("block")
		_apply_player_block_stance_damage(power_action_enemy_active_result, StanceDamageResolver.NORMAL_BLOCK, "power_action_block")
		_reset_pressure_sequence()
		_change_frame_advantage(1)
		log_message.emit("POWER_ACTION enemy attack blocked.")
		_record_combat_event("ACTION_BLOCK", "ACTION_BLOCK", {
			"actor": "enemy",
			"target": "player",
			"move_id": move_id,
			"defense_type": defense_type
		})
	else:
		hitbox_system.trace_last_check("hit")
		_apply_player_damage_and_stance(power_action_enemy_active_result, StanceDamageResolver.RAW_HIT, -1, "power_action_enemy_hit")
		_record_action_lifecycle_event("ACTION_HIT", {
			"actor": "enemy",
			"target": "player",
			"move_id": move_id,
			"startup_frames": enemy_effective_startup_frame,
			"active_frame_index": 0,
			"frame_advantage": frame_advantage,
			"damage": int(power_action_enemy_active_result.get("damage", 0)),
			"stance_damage": int(power_action_enemy_active_result.get("stance_damage", 0))
		})
		_set_frame_advantage_to_neutral()
		log_message.emit("POWER_ACTION enemy hit resolved.")
	return true

func _finish_power_action_enemy_active_window() -> void:
	if not power_action_enemy_active_resolved:
		hitbox_system.trace_last_check("whiff")
		log_message.emit("Enemy attack whiffed due to spacing.")
		_record_action_lifecycle_event("ACTION_WHIFF", {
			"actor": "enemy",
			"move_id": String(power_action_enemy_active_result.get("id", current_enemy_intent))
		})
		_reset_pressure_sequence()
		_change_frame_advantage(1)
	power_action_enemy_active_result = {}
	power_action_enemy_active_resolved = false
	power_action_enemy_active_frames_remaining = 0.0
	power_action_enemy_active_frame_accumulator = 0.0
	power_action_enemy_impact_resolving = false
	_finish_enemy_resolution_after_recovery()

func _resolve_power_action_enemy_impact() -> void:
	if combat_over or not is_power_action_mode() or not _is_enemy_intent_state():
		power_action_enemy_impact_resolving = false
		return
	remaining_startup_frames = 0
	await _resolve_power_action_enemy_attack()
	power_action_enemy_impact_resolving = false

func _resolve_power_action_enemy_attack() -> void:
	_begin_enemy_resolution()
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		_finish_enemy_resolution("resolve_attack_empty")
		return

	var enemy_attack_hits := _activate_enemy_attack_hitbox(result)
	if not enemy_attack_hits:
		hitbox_system.trace_last_check("whiff")
		log_message.emit("Enemy attack whiffed due to spacing.")
		_reset_pressure_sequence()
		_change_frame_advantage(1)
	else:
		hitbox_system.trace_last_check("hit")
		_apply_player_damage_and_stance(result, StanceDamageResolver.RAW_HIT, -1, "power_action_enemy_hit")
		_record_action_lifecycle_event("ACTION_HIT", {
			"actor": "enemy",
			"target": "player",
			"move_id": String(result.get("id", current_enemy_intent)),
			"startup_frames": int(result.get("startup_frame", enemy_base_startup_frame)),
			"active_frame_index": 0,
			"frame_advantage": frame_advantage,
			"damage": int(result.get("damage", 0)),
			"stance_damage": int(result.get("stance_damage", 0))
		})
		_set_frame_advantage_to_neutral()
		log_message.emit("POWER_ACTION enemy hit resolved.")
	await _finish_enemy_resolution_after_recovery()

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
		reaction_window_system.finish_reaction_motion()
		_finish_enemy_resolution("resolve_attack_empty")
		return

	var enemy_attack_hits := _activate_enemy_attack_hitbox(result)
	if defense_type == "wait":
		if not enemy_attack_hits:
			hitbox_system.trace_last_check("whiff")
			log_message.emit("Enemy whiffed after wait.")
			_reset_pressure_sequence()
			_change_frame_advantage(1)
		else:
			hitbox_system.trace_last_check("hit")
			_apply_player_damage_and_stance(result, StanceDamageResolver.RAW_HIT, -1, "wait_raw_hit")
			_set_frame_advantage_to_neutral()
			log_message.emit("Wait failed: enemy was in range.")
	elif not enemy_attack_hits or _enemy_attack_whiffs_against_defense(defense_type, result):
		hitbox_system.trace_last_check(_hitbox_trace_avoidance_result(defense_type, result))
		log_message.emit("Enemy attack whiffed due to spacing.")
		_reset_pressure_sequence()
		_change_frame_advantage(1)
	elif _defense_answers_attack(defense_type, result):
		hitbox_system.trace_last_check("block")
		_apply_player_block_stance_damage(result, StanceDamageResolver.NORMAL_BLOCK, "normal_defense_block")
		_reset_pressure_sequence()
		_change_frame_advantage(2)
		log_message.emit("Normal defense success.")
	else:
		hitbox_system.trace_last_check("hit")
		_apply_player_damage_and_stance(result, StanceDamageResolver.RAW_HIT, -1, "defense_failed_raw_hit")
		_set_frame_advantage_to_neutral()
		log_message.emit("Defense failed.")

	await _finish_enemy_resolution_after_recovery()

func _resolve_block_after_startup(defense_type: String, startup_after_block: int) -> void:
	_begin_enemy_resolution()
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		reaction_window_system.finish_reaction_motion()
		_finish_enemy_resolution("resolve_attack_empty")
		return

	var enemy_attack_hits := _activate_enemy_attack_hitbox(result)
	if not enemy_attack_hits or _enemy_attack_whiffs_against_defense(defense_type, result):
		hitbox_system.trace_last_check(_hitbox_trace_avoidance_result(defense_type, result))
		log_message.emit("Enemy attack whiffed due to spacing.")
		_reset_pressure_sequence()
		_change_frame_advantage(1)
	elif startup_after_block < 0:
		hitbox_system.trace_last_check("hit")
		_apply_player_damage_and_stance(result, StanceDamageResolver.COUNTER_HIT, int(result["counter_damage"]), "late_block_counter_hit")
		_set_frame_advantage_to_neutral()
		log_message.emit("Defense failed: too late.")
	elif _defense_answers_attack(defense_type, result):
		if startup_after_block <= perfect_block_window_frames:
			hitbox_system.trace_last_check("perfect_block")
			_apply_player_block_stance_damage(result, StanceDamageResolver.PERFECT_BLOCK, "perfect_block_defense")
			_reset_pressure_sequence()
			_change_frame_advantage(4)
			var stance_protected := _apply_block_stance_damage(15, "perfect_block")
			log_message.emit("Perfect block window hit.")
			log_message.emit("PERFECT BLOCK")
			if stance_protected:
				log_message.emit("Perfect block dealt no stance damage due to protection.")
			player.show_state("PERFECT BLOCK", Color.GOLD)
			await _run_perfect_block_hitstop()
		else:
			hitbox_system.trace_last_check("block")
			_apply_player_block_stance_damage(result, StanceDamageResolver.NORMAL_BLOCK, "normal_block")
			_reset_pressure_sequence()
			_change_frame_advantage(2)
			log_message.emit("Normal block: too early for perfect.")
	else:
		hitbox_system.trace_last_check("hit")
		_apply_player_damage_and_stance(result, StanceDamageResolver.RAW_HIT, -1, "block_failed_raw_hit")
		_set_frame_advantage_to_neutral()
		log_message.emit("Defense failed.")

	_release_player_block_if_needed(defense_type)
	await _finish_enemy_resolution_after_recovery()

func _resolve_reaction_no_defense() -> void:
	_begin_enemy_resolution()
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		reaction_window_system.finish_reaction_motion()
		_finish_enemy_resolution("resolve_attack_empty")
		return

	var enemy_attack_hits := _activate_enemy_attack_hitbox(result)
	if not enemy_attack_hits:
		hitbox_system.trace_last_check("whiff")
		log_message.emit("Enemy attack whiffed due to spacing.")
		log_message.emit("Impact resolved: whiff.")
		reaction_window_system.set_impact_resolution("Whiff")
		_reset_pressure_sequence()
		_change_frame_advantage(1)
	else:
		hitbox_system.trace_last_check("hit")
		_apply_player_damage_and_stance(result, StanceDamageResolver.RAW_HIT, -1, "reaction_no_defense_hit")
		_set_frame_advantage_to_neutral()
		log_message.emit("Impact resolved: hit.")
		reaction_window_system.set_impact_resolution("Hit")
	reaction_window_system.finish_reaction_motion()
	await _finish_enemy_resolution_after_recovery()

func _resolve_reaction_block(defense_type: String, input_progress: float) -> void:
	_begin_enemy_resolution()
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		reaction_window_system.finish_reaction_motion()
		_finish_enemy_resolution("resolve_attack_empty")
		return

	var enemy_attack_hits := _activate_enemy_attack_hitbox(result)
	if not enemy_attack_hits or _enemy_attack_whiffs_against_defense(defense_type, result):
		hitbox_system.trace_last_check(_hitbox_trace_avoidance_result(defense_type, result))
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
			hitbox_system.trace_last_check("perfect_block")
			_apply_player_block_stance_damage(result, StanceDamageResolver.PERFECT_BLOCK, "reaction_perfect_block_defense")
			_reset_pressure_sequence()
			_change_frame_advantage(4)
			var stance_protected := _apply_block_stance_damage(15, "perfect_block")
			log_message.emit("Perfect block window hit.")
			log_message.emit("PERFECT BLOCK")
			if stance_protected:
				log_message.emit("Perfect block dealt no stance damage due to protection.")
			log_message.emit("Impact resolved: perfect block.")
			reaction_window_system.set_impact_resolution("Perfect Block")
			player.show_state("PERFECT BLOCK", Color.GOLD)
			await _run_perfect_block_hitstop()
		else:
			hitbox_system.trace_last_check("block")
			_apply_player_block_stance_damage(result, StanceDamageResolver.NORMAL_BLOCK, "reaction_normal_block")
			_reset_pressure_sequence()
			_change_frame_advantage(2)
			log_message.emit("Normal block: too early for perfect.")
			log_message.emit("Impact resolved: normal block.")
			reaction_window_system.set_impact_resolution("Normal Block")
	else:
		hitbox_system.trace_last_check("hit")
		if String(result["type"]) == "LOW" and reaction_window_system.jump_started and not reaction_window_system.jump_active:
			log_message.emit("Jump too late; sweep hit.")
		_apply_player_damage_and_stance(result, StanceDamageResolver.RAW_HIT, -1, "reaction_failed_raw_hit")
		_set_frame_advantage_to_neutral()
		log_message.emit("Defense failed.")
		log_message.emit("Impact resolved: hit.")
		reaction_window_system.set_impact_resolution("Hit")

	_release_player_block_if_needed(defense_type)
	reaction_window_system.finish_reaction_motion()
	await _finish_enemy_resolution_after_recovery()

func _begin_enemy_resolution() -> void:
	_transition_combat_state(CombatStateMachineScript.State.ENEMY_ACTIVE, "enemy impact")
	waiting_for_defense = false
	reaction_window_system.deactivate()
	Engine.time_scale = 1.0
	combat_timeline.mark_active()
	_show_enemy_timeline_phase()
	frame_advantage_changed.emit(frame_advantage)

func _finish_enemy_resolution(completion_reason := "recovery_complete") -> void:
	var completed_intent := current_enemy_intent if current_enemy_intent != "" else "unknown"
	var expected_recovery_frames := _expected_enemy_recovery_frames_for_action(completed_intent)
	var recovery_frames_elapsed := int(round(power_action_enemy_recovery_frames_elapsed)) if is_power_action_mode() else expected_recovery_frames
	var recovery_skipped := completion_reason != "recovery_complete" and expected_recovery_frames > 0 and recovery_frames_elapsed <= 0
	var early_done_reason := completion_reason if recovery_skipped else ""
	if completion_reason == "recovery_complete" and expected_recovery_frames > 0 and recovery_frames_elapsed <= 0:
		recovery_skipped = true
		early_done_reason = "unknown_recovery_skip"
	last_enemy_action_done_frame = Engine.get_physics_frames()
	last_enemy_action_done_msec = Time.get_ticks_msec()
	_record_action_lifecycle_event("ACTION_DONE", {
		"actor": "enemy",
		"move_id": completed_intent,
		"action_done_frame": last_enemy_action_done_frame,
		"action_done_timestamp_msec": last_enemy_action_done_msec,
		"completion_reason": completion_reason,
		"early_done_reason": early_done_reason,
		"recovery_skipped": recovery_skipped,
		"expected_recovery_frames": expected_recovery_frames,
		"recovery_frames_elapsed": recovery_frames_elapsed,
		"next_decision_cooldown_frames": power_action_enemy_decision_cooldown_frames if is_power_action_mode() else 0
	})
	enemy.finish_attack()
	current_enemy_action_request = null
	combat_timeline.finish_action()
	hitbox_system.finish_enemy_move()
	enemy.clear_timeline_visual()
	attack_in_progress = false
	enemy_action_recovery_frames_remaining = 0.0
	enemy_action_recovery_frame_accumulator = 0.0
	power_action_enemy_active_frames_remaining = 0.0
	power_action_enemy_active_frame_accumulator = 0.0
	power_action_enemy_active_result = {}
	power_action_enemy_active_resolved = false
	power_action_enemy_recovery_frames_elapsed = 0.0
	power_action_enemy_impact_resolving = false
	power_action_enemy_recovery_frames_elapsed = 0.0
	player.set_free_movement_enabled(false)
	current_enemy_intent = ""
	enemy_base_startup_frame = 0
	enemy_effective_startup_frame = 0
	remaining_startup_frames = 0
	if is_power_action_mode():
		power_action_enemy_decision_cooldown_remaining = float(power_action_enemy_decision_cooldown_frames)
		last_power_action_enemy_reject_reason = ""
		log_message.emit("POWER_ACTION enemy decision cooldown started: %df after %s." % [power_action_enemy_decision_cooldown_frames, completed_intent])
	_update_time_scale()
	if _player_reward_window_active():
		_enter_player_reward_window("enemy recovery complete")
	else:
		_transition_combat_state(CombatStateMachineScript.State.SLOW_NEUTRAL, "enemy recovery complete")
		_enter_slow_neutral("Slow neutral movement started.")

func _finish_enemy_resolution_after_recovery() -> void:
	_transition_combat_state(CombatStateMachineScript.State.ENEMY_RECOVERY, "enemy recovery")
	enemy_action_recovery_frames_remaining = float(_current_enemy_recovery_frames())
	enemy_action_recovery_frame_accumulator = 0.0
	if is_power_action_mode():
		enemy_action_recovery_frames_remaining = maxf(1.0, ceil(enemy_action_recovery_frames_remaining * power_action_enemy_recovery_multiplier))
		power_action_enemy_recovery_frames_elapsed = 0.0
	log_message.emit("ENEMY_RECOVERY set: recovery_frames=%d intent=%s." % [int(ceil(enemy_action_recovery_frames_remaining)), current_enemy_intent if current_enemy_intent != "" else "None"])
	hitbox_system.enter_enemy_recovery()
	combat_timeline.mark_recovery()
	_record_action_lifecycle_event("ACTION_RECOVERY_BEGIN", {
		"actor": "enemy",
		"move_id": current_enemy_intent if current_enemy_intent != "" else "unknown",
		"recovery_frames": int(ceil(enemy_action_recovery_frames_remaining))
	})
	_show_enemy_timeline_phase()
	if is_power_action_mode():
		power_action_enemy_recovery_frame_accumulator = 0.0
		_update_time_scale()
		return
	_update_time_scale()

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
	if not player_action_lifecycle_active:
		current_player_action_request = null
	initiative_offset = initiative_result
	if initiative_result < 0:
		log_message.emit("Player ended unsafe at %d." % initiative_result)
		log_message.emit("Enemy next startup modified by %d." % initiative_result)
	frame_advantage = 0
	enemy_vulnerable_frames_remaining = 0
	player_trade_recovery_frames_remaining = 0.0
	enemy_trade_recovery_frames_remaining = 0.0
	enemy_action_recovery_frames_remaining = 0.0
	enemy_action_recovery_frame_accumulator = 0.0
	power_action_enemy_active_frames_remaining = 0.0
	power_action_enemy_active_result = {}
	power_action_enemy_active_resolved = false
	power_action_enemy_recovery_frames_elapsed = 0.0
	_clear_power_action_block_state()
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
	var enemy_startup_after_card := remaining_startup_frames - int(card.startup_frame)
	_advance_player_action_frames(int(card.startup_frame), false, false)

	if absi(int(card.startup_frame) - remaining_startup_frames) <= 2:
		_move_player_by_card(card)
		_clamp_duel_distance()
		await _wait_for_player_hit_confirm(card)
		if _activate_player_card_hitbox(card):
			log_message.emit("Challenge trades.")
			_resolve_intent_trade(index, card, enemy_startup_after_card)
		else:
			_complete_player_card_timeline(card)
			log_message.emit("Interrupt failed: out of range.")
			log_message.emit("Card whiffed: no active hitbox overlap.")
			log_message.emit("No follow-up draw: card did not connect.")
			remaining_startup_frames = enemy_startup_after_card
			deck_manager.discard_card_unrestricted(index)
			if remaining_startup_frames <= 0:
				await _resolve_enemy_impact_after_countdown("card_whiff")
			else:
				frame_advantage_changed.emit(frame_advantage)
				_update_time_scale()
		return

	if int(card.startup_frame) > remaining_startup_frames:
		log_message.emit("Challenge loses.")
		log_message.emit("Interrupt failed: too slow.")
		log_message.emit("No follow-up draw: card did not connect.")
		deck_manager.discard_card_unrestricted(index)
		_cancel_player_action_lifecycle("challenge_too_slow", false)
		_resolve_enemy_counter_hit(true)
		return
	if not _card_would_hit_enemy_after_movement(card):
		log_message.emit("Challenge loses.")
		_move_player_by_card(card)
		_clamp_duel_distance()
		await _wait_for_player_hit_confirm(card)
		_activate_player_card_hitbox(card)
		_complete_player_card_timeline(card)
		log_message.emit("Interrupt failed: out of range.")
		log_message.emit("Card whiffed: no active hitbox overlap.")
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
	if not _activate_player_card_hitbox(card):
		_complete_player_card_timeline(card)
		log_message.emit("Interrupt failed: out of range.")
		log_message.emit("Card whiffed: no active hitbox overlap.")
		log_message.emit("No follow-up draw: card did not connect.")
		remaining_startup_frames = enemy_startup_after_card
		deck_manager.discard_card_unrestricted(index)
		if remaining_startup_frames <= 0:
			await _resolve_enemy_impact_after_countdown("card_whiff")
		else:
			frame_advantage_changed.emit(frame_advantage)
			_update_time_scale()
		return
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
	var enemy_startup_after_card := remaining_startup_frames - int(card.startup_frame)
	_advance_player_action_frames(int(card.startup_frame), false, false)

	if absi(int(card.startup_frame) - remaining_startup_frames) <= 2:
		_move_player_by_card(card)
		_clamp_duel_distance()
		await _wait_for_player_hit_confirm(card)
		if _activate_player_card_hitbox(card):
			log_message.emit("Challenge trades.")
			_resolve_intent_trade_snapshot(snapshot, card, enemy_startup_after_card)
		else:
			_complete_player_card_timeline(card)
			log_message.emit("Interrupt failed: out of range.")
			log_message.emit("Card whiffed: no active hitbox overlap.")
			log_message.emit("No follow-up draw: card did not connect.")
			remaining_startup_frames = enemy_startup_after_card
			deck_manager.discard_queued_card_snapshot(snapshot)
			if remaining_startup_frames <= 0:
				await _resolve_enemy_impact_after_countdown("card_whiff")
			else:
				frame_advantage_changed.emit(frame_advantage)
				_update_time_scale()
		return

	if int(card.startup_frame) > remaining_startup_frames:
		log_message.emit("Challenge loses.")
		log_message.emit("Interrupt failed: too slow.")
		log_message.emit("No follow-up draw: card did not connect.")
		deck_manager.discard_queued_card_snapshot(snapshot)
		_cancel_player_action_lifecycle("challenge_too_slow", false)
		_resolve_enemy_counter_hit(true)
		return
	if not _card_would_hit_enemy_after_movement(card):
		log_message.emit("Challenge loses.")
		_move_player_by_card(card)
		_clamp_duel_distance()
		await _wait_for_player_hit_confirm(card)
		_activate_player_card_hitbox(card)
		_complete_player_card_timeline(card)
		log_message.emit("Interrupt failed: out of range.")
		log_message.emit("Card whiffed: no active hitbox overlap.")
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
	if not _activate_player_card_hitbox(card):
		_complete_player_card_timeline(card)
		log_message.emit("Interrupt failed: out of range.")
		log_message.emit("Card whiffed: no active hitbox overlap.")
		log_message.emit("No follow-up draw: card did not connect.")
		remaining_startup_frames = enemy_startup_after_card
		deck_manager.discard_queued_card_snapshot(snapshot)
		if remaining_startup_frames <= 0:
			await _resolve_enemy_impact_after_countdown("card_whiff")
		else:
			frame_advantage_changed.emit(frame_advantage)
			_update_time_scale()
		return
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

func _try_interrupt_with_direct_card(card: Resource, request) -> void:
	_begin_player_commitment()
	if reaction_window_system.active:
		reaction_window_system.start_challenge()
		reaction_window_system.deactivate()
	last_player_action_startup = int(card.startup_frame)
	log_message.emit("Player challenge startup: %d." % last_player_action_startup)
	log_message.emit("Enemy impact remaining: %d." % remaining_startup_frames)
	pending_player_action_request_override = request
	_start_player_card_action(card)
	_begin_player_card_timeline(card)
	var enemy_startup_after_card := remaining_startup_frames - int(card.startup_frame)
	_advance_player_action_frames(int(card.startup_frame), false, false)

	if int(card.startup_frame) > remaining_startup_frames:
		log_message.emit("Challenge loses.")
		log_message.emit("Interrupt failed: too slow.")
		_cancel_player_action_lifecycle("direct_challenge_too_slow", false)
		_resolve_enemy_counter_hit(true)
		return
	if not _card_would_hit_enemy_after_movement(card):
		log_message.emit("Challenge loses.")
		_move_player_by_card(card)
		_clamp_duel_distance()
		await _wait_for_player_hit_confirm(card)
		_activate_player_card_hitbox(card)
		_complete_player_card_timeline(card)
		log_message.emit("Interrupt failed: out of range.")
		log_message.emit("Direct action whiffed: no active hitbox overlap.")
		remaining_startup_frames = enemy_startup_after_card
		if remaining_startup_frames <= 0:
			await _resolve_enemy_impact_after_countdown("direct_action_whiff")
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
	if not _activate_player_card_hitbox(card):
		_complete_player_card_timeline(card)
		log_message.emit("Interrupt failed: out of range.")
		log_message.emit("Direct action whiffed: no active hitbox overlap.")
		remaining_startup_frames = enemy_startup_after_card
		if remaining_startup_frames <= 0:
			await _resolve_enemy_impact_after_countdown("direct_action_whiff")
		else:
			frame_advantage_changed.emit(frame_advantage)
			_update_time_scale()
		return
	Engine.time_scale = 1.0
	frame_advantage_changed.emit(frame_advantage)
	player.set_free_movement_enabled(false)
	var interrupted_intent := current_enemy_intent
	_cancel_enemy_pending_attack_for_interrupt("player", "enemy", String(card.id), interrupted_intent)
	log_message.emit("%s interrupted %s." % [card.display_name, interrupted_intent])
	log_message.emit("Challenge wins.")
	pending_player_action_request_override = request
	await _resolve_player_card(card, 2, false, false, false, false, false, "direct_input")

func _cancel_enemy_pending_attack_for_interrupt(attacker_id: String, target_id: String, attacker_move_id: String, interrupted_move: String) -> void:
	_record_action_lifecycle_event("INTERRUPT", {
		"actor": attacker_id,
		"attacker": attacker_id,
		"target": target_id,
		"move_id": attacker_move_id,
		"interrupted_move": interrupted_move,
		"target_state": combat_state_machine.state_name() if combat_state_machine != null else "unknown"
	})
	attack_in_progress = false
	waiting_for_defense = false
	current_enemy_intent = ""
	current_enemy_action_request = null
	enemy_base_startup_frame = 0
	enemy_effective_startup_frame = 0
	remaining_startup_frames = 0
	enemy_action_recovery_frames_remaining = 0.0
	enemy_action_recovery_frame_accumulator = 0.0
	power_action_enemy_startup_frame_accumulator = 0.0
	power_action_enemy_recovery_frame_accumulator = 0.0
	power_action_enemy_active_frame_accumulator = 0.0
	power_action_enemy_active_frames_remaining = 0.0
	power_action_enemy_active_result = {}
	power_action_enemy_active_resolved = false
	power_action_enemy_impact_resolving = false
	power_action_enemy_decision_cooldown_remaining = 0.0
	hitbox_system.finish_enemy_move()
	if enemy.has_method("clear_intent"):
		enemy.clear_intent()

func _resolve_intent_trade(index: int, preview_card: Resource, enemy_startup_after_card: int) -> void:
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		return

	waiting_for_defense = false
	attack_in_progress = false
	remaining_startup_frames = maxi(0, enemy_startup_after_card)
	Engine.time_scale = 1.0
	var enemy_attack_hits := _activate_enemy_attack_hitbox(result)
	_apply_hit_stance_damage(preview_card, "trade")
	_complete_player_card_timeline(preview_card)
	if enemy_attack_hits:
		hitbox_system.trace_last_check("trade")
		_apply_player_damage_and_stance(result, StanceDamageResolver.RAW_HIT, -1, "trade_enemy_hit")
	else:
		hitbox_system.trace_last_check("whiff")
		log_message.emit("Enemy trade hitbox had no overlap.")
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

func _resolve_intent_trade_direct(card: Resource, enemy_startup_after_card: int) -> void:
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		return

	waiting_for_defense = false
	attack_in_progress = false
	remaining_startup_frames = maxi(0, enemy_startup_after_card)
	Engine.time_scale = 1.0
	var enemy_attack_hits := _activate_enemy_attack_hitbox(result)
	_apply_hit_stance_damage(card, "direct_trade")
	_complete_player_card_timeline(card)
	if enemy_attack_hits:
		hitbox_system.trace_last_check("trade")
		_apply_player_damage_and_stance(result, StanceDamageResolver.RAW_HIT, -1, "direct_trade_enemy_hit")
	else:
		hitbox_system.trace_last_check("whiff")
		log_message.emit("Enemy trade hitbox had no overlap.")
	player.set_free_movement_enabled(false)
	var traded_intent := current_enemy_intent
	current_enemy_intent = ""
	enemy_base_startup_frame = 0
	enemy_effective_startup_frame = 0
	remaining_startup_frames = 0
	if enemy.has_method("clear_intent"):
		enemy.clear_intent()
	log_message.emit("Trade occurred.")
	log_message.emit("%s traded with %s." % [card.display_name, traded_intent])
	_record_card_action_event(card, "trade", "direct_input")
	_apply_trade_frame_result(card, current_player_action_request)

func _resolve_intent_trade_snapshot(snapshot: Dictionary, preview_card: Resource, enemy_startup_after_card: int) -> void:
	var result: Dictionary = enemy.resolve_attack()
	if result.is_empty():
		return

	waiting_for_defense = false
	attack_in_progress = false
	remaining_startup_frames = maxi(0, enemy_startup_after_card)
	Engine.time_scale = 1.0
	var enemy_attack_hits := _activate_enemy_attack_hitbox(result)
	_apply_hit_stance_damage(preview_card, "trade_snapshot")
	_complete_player_card_timeline(preview_card)
	if enemy_attack_hits:
		hitbox_system.trace_last_check("trade")
		_apply_player_damage_and_stance(result, StanceDamageResolver.RAW_HIT, -1, "trade_snapshot_enemy_hit")
	else:
		hitbox_system.trace_last_check("whiff")
		log_message.emit("Enemy trade hitbox had no overlap.")
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
	if not _activate_enemy_attack_hitbox(result):
		hitbox_system.trace_last_check("whiff")
		log_message.emit("Enemy attack whiffed due to spacing.")
		_change_frame_advantage(1)
	else:
		hitbox_system.trace_last_check("hit")
		_apply_player_damage_and_stance(result, StanceDamageResolver.COUNTER_HIT if counter_hit else StanceDamageResolver.RAW_HIT, damage if counter_hit else int(result["damage"]), "challenge_counter_hit" if counter_hit else "challenge_raw_hit")
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

func _apply_trade_frame_result(card: Resource, action_request = null) -> void:
	queue_resolver.interrupted_by_trade = true
	queue_resolver.clear()
	var trade_result: Dictionary = trade_system.resolve_post_trade(card)
	var player_recovery := int(trade_result["player_recovery"])
	var enemy_recovery := int(trade_result["enemy_recovery"])
	var post_trade_frame_advantage := int(trade_result["post_trade_frame_advantage"])
	_begin_player_trade_recovery_lifecycle(card, player_recovery, action_request)
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
		log_message.emit("PLAYER_RECOVERY set for trade: action=%s recovery_frames=%d." % [String(card.id), player_recovery])
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
	if not _activate_player_card_hitbox(preview_card):
		log_message.emit("Card whiffed: no active hitbox overlap.")
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
	if not _activate_player_card_hitbox(preview_card):
		log_message.emit("Card whiffed: no active hitbox overlap.")
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

func _resolve_player_card(card: Resource, bonus_frame_advantage := 0, apply_movement := true, route_valid := true, starts_new_route := false, start_animation := true, wait_for_hit_confirm := true, event_source := "player_card") -> void:
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
	if not _activate_player_card_hitbox(card):
		log_message.emit("Card whiffed: no active hitbox overlap.")
		log_message.emit("No follow-up draw: card did not connect.")
		_record_card_action_event(card, "whiff", event_source)
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
	_record_card_action_event(card, "hit", event_source)
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
	var previous_enemy_vulnerable := enemy_vulnerable_frames_remaining
	var final_frame_advantage: int = frame_system.apply_advantage_delta(delta, frame_advantage)
	frame_advantage = final_frame_advantage
	enemy_vulnerable_frames_remaining = maxi(0, frame_advantage)
	if is_power_action_mode():
		enemy_vulnerable_frames_remaining = maxi(enemy_vulnerable_frames_remaining, previous_enemy_vulnerable)
	frame_advantage_changed.emit(frame_advantage)

	if frame_advantage > previous:
		log_message.emit("Frame advantage gained: %d -> %d." % [previous, frame_advantage])
	elif frame_advantage < previous:
		log_message.emit("Frame advantage lost: %d -> %d." % [previous, frame_advantage])

	if is_power_action_mode():
		log_message.emit("POWER_ACTION frame advantage updated for debug only: %d." % frame_advantage)
		_update_time_scale()
		return

	if final_frame_advantage >= 0:
		if _enemy_break_frames_remaining() > 0:
			if _player_reward_frame_value() > 0:
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
		_apply_player_damage_and_stance({
			"damage": enemy.punish_damage,
			"stance_damage": int(enemy.get("punish_stance_damage"))
		}, StanceDamageResolver.RAW_HIT, enemy.punish_damage, "enemy_punish")
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

func get_player_pushbox() -> Rect2:
	return hitbox_system.player_pushbox()

func get_enemy_pushbox() -> Rect2:
	return hitbox_system.enemy_pushbox()

func get_player_attack_hitbox() -> Rect2:
	return hitbox_system.player_active_attack_hitbox()

func get_enemy_attack_hitbox() -> Rect2:
	return hitbox_system.enemy_active_attack_hitbox()

func get_player_sprite_bounds() -> Rect2:
	return hitbox_system.player_sprite_bounds()

func get_enemy_sprite_bounds() -> Rect2:
	return hitbox_system.enemy_sprite_bounds()

func get_player_origin() -> Vector2:
	return player.global_position if player != null else Vector2.ZERO

func get_enemy_origin() -> Vector2:
	return enemy.global_position if enemy != null else Vector2.ZERO

func get_player_debug_attack_hitbox() -> Rect2:
	return hitbox_system.player_debug_attack_hitbox()

func get_enemy_debug_attack_hitbox() -> Rect2:
	return hitbox_system.enemy_debug_attack_hitbox()

func get_player_hitbox_phase() -> String:
	return hitbox_system.player_debug_phase()

func get_enemy_hitbox_phase() -> String:
	return hitbox_system.enemy_debug_phase()

func toggle_hitbox_calibration() -> void:
	toggle_combat_geometry_debug()

func toggle_combat_geometry_debug() -> void:
	set_combat_geometry_debug_visible(not show_debug_hitboxes)

func set_combat_geometry_debug_visible(visible: bool, log_change := true) -> void:
	show_debug_hitboxes = visible
	show_hitbox_calibration = visible
	show_sprite_bounds_debug = visible
	if log_change:
		log_message.emit("Combat geometry debug %s." % ("enabled" if visible else "disabled"))

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

func _player_attack_overlaps_enemy() -> bool:
	return hitbox_system.player_attack_overlaps_enemy()

func _enemy_attack_overlaps_player() -> bool:
	return hitbox_system.enemy_attack_overlaps_player()

func _card_would_hit_enemy_after_movement(card: Resource) -> bool:
	return hitbox_system.card_would_hit_enemy_after_movement(card)

func _activate_player_card_hitbox(card: Resource) -> bool:
	var result: Dictionary = hitbox_system.activate_player_card(card)
	var overlaps := bool(result.get("overlaps", false)) or not _card_needs_hitbox(card)
	if combat_timeline.actor == "PLAYER":
		combat_timeline.mark_active()
		_show_player_timeline_phase()
	_record_action_lifecycle_event("ACTION_ACTIVE_BEGIN", {
		"actor": "player",
		"move_id": String(card.id),
		"active_frames": maxi(1, int(card.active_end_frame) - int(card.active_start_frame) + 1)
	})
	var outcome := "hit" if overlaps else "whiff"
	hitbox_system.trace_last_check(outcome)
	if overlaps:
		log_message.emit("%s active hitbox overlapped enemy hurtbox." % card.display_name)
		_record_action_lifecycle_event("ACTION_HIT", {
			"actor": "player",
			"target": "enemy",
			"move_id": String(card.id),
			"startup_frames": int(card.startup_frame),
			"active_frame_index": maxi(0, int(card.hit_frame) - int(card.active_start_frame)),
			"frame_advantage": frame_advantage,
			"damage": int(card.damage),
			"stance_damage": int(card.stance_damage)
		})
	else:
		log_message.emit("%s active hitbox had no overlap." % card.display_name)
		_record_action_lifecycle_event("ACTION_WHIFF", {
			"actor": "player",
			"move_id": String(card.id)
		})
	return overlaps

func _activate_enemy_attack_hitbox(attack_data: Dictionary) -> bool:
	var result: Dictionary = hitbox_system.activate_enemy_attack(attack_data)
	var overlaps := bool(result.get("overlaps", false))
	if combat_timeline.actor == "ENEMY":
		combat_timeline.mark_active()
		_show_enemy_timeline_phase()
	_record_action_lifecycle_event("ACTION_ACTIVE_BEGIN", {
		"actor": "enemy",
		"move_id": String(attack_data.get("id", current_enemy_intent)),
		"active_frames": int(attack_data.get("active", 1))
	})
	if overlaps:
		log_message.emit("%s active hitbox overlapped player hurtbox." % String(attack_data.get("name", attack_data.get("id", "Enemy attack"))))
	else:
		log_message.emit("%s active hitbox had no overlap." % String(attack_data.get("name", attack_data.get("id", "Enemy attack"))))
		_record_action_lifecycle_event("ACTION_WHIFF", {
			"actor": "enemy",
			"move_id": String(attack_data.get("id", current_enemy_intent))
		})
	return overlaps

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
	hitbox_system.enter_player_recovery()
	combat_timeline.mark_recovery()
	_apply_timeline_visual()
	_record_action_lifecycle_event("ACTION_RECOVERY_BEGIN", {
		"actor": "player",
		"move_id": String(card.id) if card != null else "unknown",
		"recovery_frames": int(card.frame_cost) if card != null else 0
	})
	_set_player_action_lifecycle_phase("RECOVERY", "hit_resolution_complete")
	_start_player_action_recovery_lifecycle(card)

func _start_player_action_recovery_lifecycle(card: Resource) -> void:
	if not player_action_lifecycle_active or player_action_lifecycle_recovery_running:
		return
	var token := player_action_lifecycle_token
	var recovery_frames := maxi(0, int(card.frame_cost)) if card != null else 0
	player_action_lifecycle_recovery_running = true
	player_action_lifecycle_recovery_frames_remaining = float(recovery_frames)
	power_action_player_recovery_frame_accumulator = 0.0
	log_message.emit("Player action recovery started: %s %df." % [player_action_lifecycle_action_id, recovery_frames])
	if recovery_frames <= 0:
		_finish_player_action_lifecycle(token, "zero_recovery")
		return
	await get_tree().create_timer(_player_action_frames_to_seconds(recovery_frames), false, true).timeout
	if token != player_action_lifecycle_token or not player_action_lifecycle_active:
		return
	if is_power_action_mode():
		player_action_lifecycle_recovery_frames_remaining = 0.0
		_finish_player_action_lifecycle(token, "recovery_complete")
		return
	advance_combat_frames(recovery_frames)
	_finish_player_action_lifecycle(token, "recovery_complete")

func _tick_debug_hitboxes(delta: float) -> void:
	hitbox_system.tick_debug_hitboxes(delta)

func _create_hitbox_debug_drawer() -> void:
	var debug_drawer := HitboxDebugDrawScript.new()
	debug_drawer.set("combat_manager", self)
	get_parent().call_deferred("add_child", debug_drawer)

func _begin_player_card_timeline(card: Resource) -> void:
	_transition_combat_state(CombatStateMachineScript.State.EXECUTING_PLAYER_ACTION, "player action: %s" % card.id)
	var move_def: MoveDefinition = hitbox_system.begin_player_move(card)
	combat_timeline.begin_from_move("PLAYER", move_def)
	_record_action_lifecycle_event("ACTION_STARTUP_BEGIN", {
		"actor": "player",
		"move_id": String(card.id),
		"source_type": _action_request_source_name(current_player_action_request),
		"startup_frames": int(card.startup_frame)
	})
	_set_player_action_lifecycle_phase("STARTUP", "timeline_begin")
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

func _clamp_duel_max_distance() -> void:
	movement_system.clamp_duel_max_distance()

func _clamped_player_x(player_x: float) -> float:
	return movement_system.clamped_player_x(player_x)

func _clamp_duel_for_current_motion() -> void:
	if _player_airborne_movement_active():
		_clamp_duel_max_distance()
	else:
		_clamp_duel_distance()

func _player_airborne_movement_active() -> bool:
	if reaction_jump_motion_active:
		return true
	if movement_flow_system != null and movement_flow_system.has_method("player_jump_active"):
		return movement_flow_system.player_jump_active()
	return false

func set_arena_bounds(left_bound: float, right_bound: float, wall_margin: float) -> void:
	arena_left_x = left_bound
	arena_right_x = right_bound
	arena_wall_margin = wall_margin
	if movement_system != null and movement_system.has_method("set_arena_bounds"):
		movement_system.set_arena_bounds(arena_left_x, arena_right_x, arena_wall_margin)
		movement_system.clamp_arena_bounds()
		movement_system.update_facing()

func _update_actor_facing() -> void:
	if movement_system != null and movement_system.has_method("update_facing"):
		movement_system.update_facing()

func is_screen_direction_toward_enemy(direction: float) -> bool:
	if movement_system == null or direction == 0.0:
		return false
	return signf(direction) == signf(movement_system.direction_to_enemy())

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

func apply_reaction_live_movement(direction: float, real_delta: float) -> void:
	if combat_over or not _is_reaction_window_state() or is_player_crouching():
		return
	player.global_position.x += clampf(direction, -1.0, 1.0) * reaction_player_move_speed * real_delta * _reaction_movement_time_scale()
	_clamp_duel_distance()

func apply_reaction_backstep() -> void:
	if combat_over or not _is_reaction_window_state() or is_player_crouching():
		return
	movement_system.move_player_away_from_enemy(80.0 * _reaction_movement_time_scale())
	_clamp_duel_distance()

func start_reaction_jump_movement() -> void:
	if player == null:
		return
	reaction_jump_motion_active = true
	reaction_jump_ground_y = player.global_position.y
	reaction_jump_elapsed_frames = 0.0
	reaction_jump_direction = 0.0
	reaction_jump_landing_requested = false

func apply_reaction_jump_movement(direction: float, real_delta: float, lift_progress: float) -> void:
	if combat_over or not _is_reaction_window_state() or player == null:
		return
	if not reaction_jump_motion_active:
		start_reaction_jump_movement()
	reaction_jump_direction = clampf(direction, -1.0, 1.0)
	_advance_reaction_jump_arc(real_delta, _reaction_movement_time_scale())

func finish_reaction_jump_movement() -> void:
	if not reaction_jump_motion_active or player == null:
		return
	reaction_jump_landing_requested = true

func _tick_reaction_jump_arc(real_delta: float) -> void:
	if not reaction_jump_motion_active or player == null:
		return
	if _is_reaction_window_state():
		return
	_advance_reaction_jump_arc(real_delta, 1.0)

func _advance_reaction_jump_arc(real_delta: float, time_scale: float) -> void:
	if not reaction_jump_motion_active or player == null:
		return
	var scaled_delta := real_delta * clampf(time_scale, 0.0, 1.0)
	var arc_frames := maxf(1.0, float(reaction_jump_arc_frames))
	reaction_jump_elapsed_frames = minf(arc_frames, reaction_jump_elapsed_frames + scaled_delta * 60.0)
	var arc_progress := clampf(reaction_jump_elapsed_frames / arc_frames, 0.0, 1.0)
	var height := sin(arc_progress * PI) * reaction_jump_hurtbox_lift
	player.global_position.x += reaction_jump_direction * reaction_jump_horizontal_speed * scaled_delta
	player.global_position.y = reaction_jump_ground_y - height
	_clamp_duel_max_distance()
	if reaction_jump_elapsed_frames >= arc_frames:
		player.global_position.y = reaction_jump_ground_y
		reaction_jump_motion_active = false
		reaction_jump_landing_requested = false
		reaction_jump_elapsed_frames = 0.0
		reaction_jump_direction = 0.0
		if player != null and player.has_method("clear_timeline_visual"):
			player.clear_timeline_visual()

func _reaction_movement_time_scale() -> float:
	return clampf(Engine.time_scale, 0.0, 1.0)

func is_player_crouching() -> bool:
	return player != null and player.has_method("is_crouching") and player.is_crouching()

func get_player_hurtbox_offset() -> Vector2:
	if reaction_window_system != null and reaction_window_system.jump_active and not reaction_jump_motion_active:
		return Vector2(0.0, -reaction_jump_hurtbox_lift)
	return Vector2.ZERO

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

func _tick_enemy_action_recovery(delta: float) -> void:
	if is_power_action_mode():
		return
	if combat_state_machine == null or combat_state_machine.current_state != CombatStateMachineScript.State.ENEMY_RECOVERY:
		return
	if enemy_action_recovery_frames_remaining <= 0.0:
		return
	var tick: Dictionary = _consume_gameplay_frames(delta, enemy_action_recovery_frame_accumulator)
	enemy_action_recovery_frame_accumulator = float(tick.get("accumulator", enemy_action_recovery_frame_accumulator))
	var frames := int(tick.get("frames", 0))
	if frames <= 0:
		return
	enemy_action_recovery_frames_remaining = maxf(0.0, enemy_action_recovery_frames_remaining - float(frames))
	if combat_timeline != null and combat_timeline.actor == "ENEMY":
		combat_timeline.advance_frames(frames)
		_show_enemy_timeline_phase()
	if enemy_action_recovery_frames_remaining <= 0.0:
		_finish_enemy_resolution("recovery_complete")

func _tick_power_action_enemy_recovery(delta: float) -> void:
	if not is_power_action_mode() or combat_over:
		return
	if combat_state_machine == null or combat_state_machine.current_state != CombatStateMachineScript.State.ENEMY_RECOVERY:
		return
	if enemy_action_recovery_frames_remaining <= 0.0:
		return
	var tick: Dictionary = _consume_gameplay_frames(delta, power_action_enemy_recovery_frame_accumulator)
	power_action_enemy_recovery_frame_accumulator = float(tick.get("accumulator", power_action_enemy_recovery_frame_accumulator))
	var frames := int(tick.get("frames", 0))
	if frames <= 0:
		return
	enemy_action_recovery_frames_remaining = maxf(0.0, enemy_action_recovery_frames_remaining - float(frames))
	power_action_enemy_recovery_frames_elapsed += float(frames)
	if combat_timeline != null and combat_timeline.actor == "ENEMY":
		combat_timeline.advance_frames(frames)
		_show_enemy_timeline_phase()
	if enemy_action_recovery_frames_remaining <= 0.0:
		_finish_enemy_resolution("recovery_complete")

func _tick_power_action_enemy_decision_cooldown(delta: float) -> void:
	if not is_power_action_mode() or power_action_enemy_decision_cooldown_remaining <= 0.0:
		return
	var frames := float(_frames_for_delta(delta))
	power_action_enemy_decision_cooldown_remaining = maxf(0.0, power_action_enemy_decision_cooldown_remaining - frames)
	if power_action_enemy_decision_cooldown_remaining <= 0.0:
		last_power_action_enemy_reject_reason = ""

func _tick_power_action_enemy_hitstun(delta: float) -> void:
	if not is_power_action_mode() or enemy_vulnerable_frames_remaining <= 0:
		return
	var tick: Dictionary = _consume_gameplay_frames(delta, power_action_enemy_hitstun_frame_accumulator)
	power_action_enemy_hitstun_frame_accumulator = float(tick.get("accumulator", power_action_enemy_hitstun_frame_accumulator))
	var frames := int(tick.get("frames", 0))
	if frames <= 0:
		return
	enemy_vulnerable_frames_remaining = maxi(0, enemy_vulnerable_frames_remaining - frames)
	if enemy_vulnerable_frames_remaining <= 0:
		last_power_action_enemy_reject_reason = ""

func _tick_power_action_player_recovery(delta: float) -> void:
	if not is_power_action_mode() or combat_over:
		return
	if not player_action_lifecycle_active or not player_action_lifecycle_recovery_running:
		return
	if player_action_lifecycle_recovery_frames_remaining <= 0.0:
		return
	var tick: Dictionary = _consume_gameplay_frames(delta, power_action_player_recovery_frame_accumulator)
	power_action_player_recovery_frame_accumulator = float(tick.get("accumulator", power_action_player_recovery_frame_accumulator))
	var frames := int(tick.get("frames", 0))
	if frames <= 0:
		return
	player_action_lifecycle_recovery_frames_remaining = maxf(0.0, player_action_lifecycle_recovery_frames_remaining - float(frames))
	if player_action_lifecycle_recovery_frames_remaining <= 0.0:
		_finish_player_action_lifecycle(player_action_lifecycle_token, "recovery_complete")

func _update_power_action_live_frame_advantage() -> void:
	if not is_power_action_mode() or combat_over:
		return
	var player_lock_frames := _power_action_player_lock_frames()
	var enemy_lock_frames := _power_action_enemy_lock_frames()
	var live_advantage := 0
	if player_lock_frames > 0 or enemy_lock_frames > 0:
		live_advantage = enemy_lock_frames - player_lock_frames
	if live_advantage == frame_advantage:
		return
	var previous := frame_advantage
	frame_advantage = live_advantage
	frame_advantage_changed.emit(frame_advantage)
	_record_combat_event("POWER_ACTION_FRAME_ADVANTAGE", "POWER_ACTION live frame advantage updated.", {
		"previous": previous,
		"frame_advantage": frame_advantage,
		"player_lock_frames": player_lock_frames,
		"enemy_lock_frames": enemy_lock_frames,
		"player_phase": _player_phase_for_log(),
		"enemy_phase": _enemy_phase_for_log(),
		"combat_state": _current_mode()
	})

func _power_action_player_lock_frames() -> int:
	var remaining := int(ceil(maxf(player_trade_recovery_frames_remaining, player_action_lifecycle_recovery_frames_remaining)))
	if player_action_lifecycle_active and not player_action_lifecycle_done and remaining <= 0:
		remaining = 1
	var debug := _player_debug()
	var logic_state := String(debug.get("logic_state", debug.get("action_state", "NEUTRAL"))).to_lower()
	if logic_state.find("hitstun") != -1 or logic_state.find("blockstun") != -1:
		remaining = maxi(remaining, 1)
	return remaining

func _power_action_enemy_lock_frames() -> int:
	var remaining := 0
	if current_enemy_intent != "" and remaining_startup_frames > 0:
		remaining = maxi(remaining, remaining_startup_frames)
	if power_action_enemy_active_frames_remaining > 0.0:
		remaining = maxi(remaining, int(ceil(power_action_enemy_active_frames_remaining)))
	if enemy_action_recovery_frames_remaining > 0.0:
		remaining = maxi(remaining, int(ceil(enemy_action_recovery_frames_remaining)))
	if enemy_vulnerable_frames_remaining > 0:
		remaining = maxi(remaining, enemy_vulnerable_frames_remaining)
	if enemy_trade_recovery_frames_remaining > 0.0:
		remaining = maxi(remaining, int(ceil(enemy_trade_recovery_frames_remaining)))
	if _enemy_break_frames_remaining() > 0:
		remaining = maxi(remaining, _enemy_break_frames_remaining())
	return remaining

func _tick_trade_recovery_frames(frames: float) -> void:
	if frames <= 0.0:
		return
	var had_player_recovery := player_trade_recovery_frames_remaining > 0.0
	player_trade_recovery_frames_remaining = maxf(0.0, player_trade_recovery_frames_remaining - frames)
	enemy_trade_recovery_frames_remaining = maxf(0.0, enemy_trade_recovery_frames_remaining - frames)
	if player_action_lifecycle_active and player_action_lifecycle_phase == "TRADE_RECOVERY":
		player_action_lifecycle_recovery_frames_remaining = player_trade_recovery_frames_remaining
	if had_player_recovery and player_trade_recovery_frames_remaining <= 0.0:
		log_message.emit("Player trade recovery complete.")
		if player_action_lifecycle_active and player_action_lifecycle_phase == "TRADE_RECOVERY":
			_finish_player_action_lifecycle(player_action_lifecycle_token, "trade_recovery_complete")
		else:
			current_player_action_request = null
		if pending_trade_followup_window and frame_advantage > 0:
			pending_trade_followup_window = false
			_open_trade_followup_window("Follow-up window opened after trade recovery.")
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

func _hitbox_trace_avoidance_result(defense_type: String, attack_data: Dictionary) -> String:
	var attack_type := String(attack_data["type"])
	if attack_type == "HIGH" and defense_type == "crouch_block":
		return "crouch_evade"
	if attack_type == "LOW" and _is_jump_action(defense_type):
		return "jump_evade"
	return "whiff"

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
	_enter_player_reward_window("stance break")

func _on_enemy_break_ended() -> void:
	log_message.emit("Stance recovery complete; state NORMAL")
	if not is_time_tactical_mode():
		log_message.emit("POWER_ACTION stance break recovered without tactical PLAYER_REWARD state.")
		_transition_combat_state(CombatStateMachineScript.State.SLOW_NEUTRAL, "stance break recovery complete")
		_update_time_scale()
		return
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

func _apply_player_damage_and_stance(attack_result: Dictionary, hit_result: String, damage_override := -1, event_source := "enemy_attack") -> Dictionary:
	var damage := damage_override if damage_override >= 0 else int(attack_result.get("damage", 0))
	if is_power_action_mode():
		_clear_power_action_block_state("raw_hit:%s" % event_source)
	player.take_damage(damage)
	return _apply_stance_damage_to_actor(player, int(attack_result.get("stance_damage", 0)), hit_result, event_source)

func _apply_player_block_stance_damage(attack_result: Dictionary, hit_result: String, event_source := "enemy_block") -> Dictionary:
	return _apply_stance_damage_to_actor(player, int(attack_result.get("stance_damage", 0)), hit_result, event_source)

func _apply_stance_damage_to_actor(defender: Node, base_stance_damage: int, hit_result: String, event_source := "stance_damage") -> Dictionary:
	if stance_damage_resolver == null:
		return {}
	var result: Dictionary = stance_damage_resolver.apply_stance_damage(defender, base_stance_damage, hit_result)
	_log_stance_damage_result(result)
	_record_combat_event("stance_update", "", {
		"source": event_source,
		"defender": result.get("defender", "Unknown"),
		"hit_result": result.get("hit_result", hit_result),
		"stance_before": result.get("stance_before", 0),
		"stance_after": result.get("stance_after", 0),
		"stance_damage_attempted": result.get("stance_damage_attempted", 0),
		"stance_damage_applied": result.get("stance_damage_applied", 0),
		"stance_protected": result.get("stance_protected", false),
		"stance_state": result.get("stance_state", "UNKNOWN"),
		"recovery_frames_remaining": result.get("recovery_frames_remaining", 0)
	})
	return result

func _log_stance_damage_result(result: Dictionary) -> void:
	var base_damage := int(result.get("base_stance_damage", 0))
	var attempted := int(result.get("stance_damage_attempted", 0))
	var applied := int(result.get("stance_damage_applied", 0))
	var hit_result := String(result.get("hit_result", "RAW_HIT"))
	var defender_name := String(result.get("defender", "Defender"))
	if base_damage <= 0 and attempted <= 0 and hit_result != "PERFECT_BLOCK":
		return
	if bool(result.get("stance_protected", false)) and attempted > 0:
		log_message.emit("%s stance protected: ignored %d stance damage." % [defender_name, attempted])
		return
	log_message.emit("%s took %d stance damage: %s." % [defender_name, applied, hit_result])

func _apply_hit_stance_damage(card: Resource, event_source := "card_hit") -> bool:
	enemy.take_hit(card.damage, 0)
	_apply_power_action_enemy_hitstun(card)
	var result := _apply_stance_damage_to_actor(enemy, card.stance_damage, StanceDamageResolver.RAW_HIT, event_source)
	return bool(result.get("stance_protected", false))

func _apply_power_action_enemy_hitstun(card: Resource) -> void:
	if not is_power_action_mode() or card == null:
		return
	var interrupted_move := current_enemy_intent
	var should_cancel_pending := current_enemy_intent != "" or attack_in_progress or waiting_for_defense or enemy_action_recovery_frames_remaining > 0.0
	if interrupted_move == "" and enemy_action_recovery_frames_remaining > 0.0:
		interrupted_move = "enemy_recovery"
	if should_cancel_pending:
		_cancel_enemy_pending_attack_for_interrupt("player", "enemy", String(card.id), interrupted_move)
	enemy_vulnerable_frames_remaining = maxi(enemy_vulnerable_frames_remaining, power_action_enemy_hitstun_frames)
	power_action_enemy_hitstun_frame_accumulator = 0.0
	power_action_enemy_decision_cooldown_remaining = 0.0
	last_power_action_enemy_reject_reason = ""
	log_message.emit("POWER_ACTION enemy hitstun set: %df from %s." % [power_action_enemy_hitstun_frames, card.display_name])

func _apply_block_stance_damage(amount: int, event_source := "block") -> bool:
	var result := _apply_stance_damage_to_actor(enemy, amount, StanceDamageResolver.PERFECT_BLOCK_REWARD, event_source)
	return bool(result.get("stance_protected", false))

func _log_card_hit_summary(card: Resource, stance_protected: bool) -> void:
	if card.stance_damage > 0 and stance_protected:
		log_message.emit("%s hits for %d. No stance damage due to protection." % [card.display_name, card.damage])
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
		player_actor_state.recovery_frames_remaining = int(ceil(maxf(player_trade_recovery_frames_remaining, player_action_lifecycle_recovery_frames_remaining)))
	if enemy_actor_state != null:
		enemy_actor_state.update_from_actor(enemy, combat_state_machine.state_name(combat_state), current_enemy_intent if current_enemy_intent != "" else "None", current_enemy_action_request)
		enemy_actor_state.recovery_frames_remaining = int(ceil(maxf(enemy_trade_recovery_frames_remaining, enemy_action_recovery_frames_remaining))) if enemy_trade_recovery_frames_remaining > 0.0 or enemy_action_recovery_frames_remaining > 0.0 else (remaining_startup_frames if _is_enemy_intent_state() else 0)
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

	if combat_state_machine.current_state == CombatStateMachineScript.State.ENEMY_RECOVERY and _enemy_recovery_frames_remaining() <= 0 and current_enemy_intent == "" and not attack_in_progress:
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
	if combat_state_machine != null and (
		combat_state_machine.current_state == CombatStateMachineScript.State.ENEMY_ACTIVE
		or combat_state_machine.current_state == CombatStateMachineScript.State.ENEMY_RECOVERY
		or combat_state_machine.current_state == CombatStateMachineScript.State.HITSTOP
	):
		return false
	if player == null or not player.has_method("get_animation_debug"):
		return false
	var debug: Dictionary = player.get_animation_debug()
	var action_state := String(debug.get("action_state", ""))
	var action_name := String(debug.get("action_name", ""))
	var phase := String(debug.get("phase", ""))
	return action_state.begins_with("BLOCK") or (action_name.to_lower().find("block") != -1 and phase != "DONE")

func _player_has_stale_action_without_request() -> bool:
	if player_action_lifecycle_active and not player_action_lifecycle_done:
		return false
	if player_trade_recovery_frames_remaining > 0.0:
		return false
	if current_player_action_request != null:
		return false
	if player == null or not player.has_method("get_animation_debug"):
		return false
	var debug: Dictionary = player.get_animation_debug()
	if bool(debug.get("visual_return_pending", false)):
		return false
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
	if player_action_lifecycle_active and not player_action_lifecycle_done:
		return true
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

func _player_visual_return_pending() -> bool:
	var debug := _player_debug()
	return bool(debug.get("visual_return_pending", false))

func _player_has_stale_idle_lock() -> bool:
	if player_action_lifecycle_active and not player_action_lifecycle_done:
		return false
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
	if player_action_lifecycle_active and not player_action_lifecycle_done:
		return false
	if player_trade_recovery_frames_remaining > 0.0:
		return false
	if frame_advantage > 0 and _player_followup_or_cancel_window_open():
		return false
	var debug := _player_debug()
	var action_name := String(debug.get("action_name", "None")).to_lower()
	var animation_key := String(debug.get("animation_key", "idle")).to_lower()
	var no_action := action_name == "none" or animation_key == "idle" or animation_key == "none"
	return no_action and not _player_has_real_action_lifecycle()

func _player_followup_or_cancel_window_open() -> bool:
	var debug := _player_debug()
	if debug.is_empty():
		return false
	return bool(debug.get("followup_window_active", false)) or bool(debug.get("cancel_window_open", false))

func _clear_stale_player_defense() -> void:
	if player != null:
		if player.has_method("clear_stale_defense_action"):
			player.clear_stale_defense_action()
		elif player.has_method("clear_timeline_visual"):
			player.clear_timeline_visual()
	current_player_action_request = null
	last_player_action_startup = 0

func _clear_stale_player_action() -> void:
	_cancel_player_action_lifecycle("state_repair", false)
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
	if combat_state_machine.current_state == CombatStateMachineScript.State.ENEMY_RECOVERY:
		return int(ceil(enemy_action_recovery_frames_remaining))
	if combat_state_machine.current_state == CombatStateMachineScript.State.STANCE_BREAK:
		return _enemy_break_frames_remaining()
	return 0

func _enemy_has_active_recovery() -> bool:
	if punish_in_progress:
		return true
	if attack_in_progress and combat_state_machine != null and combat_state_machine.current_state == CombatStateMachineScript.State.ENEMY_RECOVERY:
		return true
	if enemy_action_recovery_frames_remaining > 0.0:
		return true
	if _enemy_break_frames_remaining() > 0:
		return true
	if current_enemy_intent != "":
		return true
	if waiting_for_defense or _reaction_window_active():
		return true
	return false

func _enemy_power_action_locked() -> bool:
	return attack_in_progress \
		or waiting_for_defense \
		or current_enemy_intent != "" \
		or power_action_enemy_decision_cooldown_remaining > 0.0 \
		or _enemy_recovery_frames_remaining() > 0 \
		or enemy_vulnerable_frames_remaining > 0 \
		or _enemy_break_frames_remaining() > 0 \
		or not enemy.can_act()

func _enemy_power_action_reject_reason() -> String:
	if combat_state_machine != null and combat_state_machine.current_state == CombatStateMachineScript.State.ENEMY_ACTIVE:
		return "already_active"
	if _enemy_recovery_frames_remaining() > 0:
		return "recovery"
	if waiting_for_defense or current_enemy_intent != "":
		return "startup"
	if power_action_enemy_decision_cooldown_remaining > 0.0:
		return "decision_cooldown"
	if attack_in_progress:
		return "already_active"
	if enemy_vulnerable_frames_remaining > 0:
		return "enemy_hitstun"
	if _enemy_break_frames_remaining() > 0:
		return "blockstun"
	if not enemy.can_act():
		return "interrupted"
	return ""

func _record_power_action_enemy_rejection(reason: String, move_id := "") -> void:
	if reason == "" or reason == last_power_action_enemy_reject_reason:
		return
	last_power_action_enemy_reject_reason = reason
	_record_power_action_enemy_decision_gate("rejected", reason, move_id)
	_record_rejected_action("enemy", reason, move_id)

func _current_enemy_recovery_frames() -> int:
	var attack_data := _enemy_attack_data(current_enemy_intent)
	if not attack_data.is_empty():
		return maxi(1, int(attack_data.get("recovery", int(round(ATTACK_RECOVERY * 60.0)))))
	return int(round(ATTACK_RECOVERY * 60.0))

func _expected_enemy_recovery_frames_for_action(action_id: String) -> int:
	var attack_data := _enemy_attack_data(action_id)
	if attack_data.is_empty():
		return 0
	var recovery_frames := maxi(0, int(attack_data.get("recovery", 0)))
	if is_power_action_mode() and recovery_frames > 0:
		return maxi(1, int(ceil(float(recovery_frames) * power_action_enemy_recovery_multiplier)))
	return recovery_frames

func _clear_stale_enemy_recovery() -> void:
	attack_in_progress = false
	punish_in_progress = false
	waiting_for_defense = false
	current_enemy_action_request = null
	enemy_action_recovery_frames_remaining = 0.0
	enemy_action_recovery_frame_accumulator = 0.0
	power_action_enemy_decision_cooldown_remaining = 0.0
	power_action_enemy_hitstun_frame_accumulator = 0.0
	power_action_enemy_active_frame_accumulator = 0.0
	power_action_enemy_active_frames_remaining = 0.0
	power_action_enemy_active_result = {}
	power_action_enemy_active_resolved = false
	power_action_enemy_impact_resolving = false
	power_action_enemy_recovery_frames_elapsed = 0.0
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
	if _player_reward_window_active():
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
	return combat_state_machine != null and (combat_state_machine.can_execute_queue() or _player_reward_window_active()) and not _queue_is_resolving()

func can_accept_tactical_queue_input() -> bool:
	if _is_stale_executing_queue_state():
		return true
	return combat_state_machine != null and (combat_state_machine.can_accept_queue_input() or _player_reward_window_active()) and not combat_over

func can_accept_live_defense() -> bool:
	return combat_state_machine != null and combat_state_machine.can_accept_live_defense()

func can_accept_live_movement() -> bool:
	if is_power_action_mode():
		return _power_action_movement_allowed()
	return combat_state_machine != null and combat_state_machine.can_accept_live_movement()

func request_live_neutral_jump() -> void:
	if is_power_action_mode() and movement_flow_system != null and not _movement_flow_active() and _power_action_movement_allowed():
		movement_flow_system.enter("POWER_ACTION live movement enabled.")
	if movement_flow_system != null and movement_flow_system.has_method("request_player_jump"):
		movement_flow_system.request_player_jump()

func get_queue_text() -> String:
	return queue_resolver.queue_text()

func _is_tactical_mode() -> bool:
	return not combat_over and combat_state_machine != null and (combat_state_machine.can_accept_queue_input() or _player_reward_window_active() or _is_stale_executing_queue_state())

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
		await _wait_for_player_lifecycle_queue_release(action)
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
		await _wait_for_player_lifecycle_queue_release(action)
		queued_action_in_progress = false
		frame_advantage_changed.emit(frame_advantage)
		if queue_resolver.interrupted_by_trade:
			log_message.emit("Queue stopped after trade.")
			queue_resolver.clear()
			break
		await _pause_between_queued_actions()
	_set_queue_resolving(false, "slow neutral queue complete")
	if _is_enemy_intent_state() and not _is_reaction_window_state() and not combat_over and not is_power_action_mode():
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
			return {"type": "CROUCH_BLOCK"} if Input.is_key_pressed(KEY_S) else {"type": "BLOCK"}
		KEY_S:
			if Input.is_key_pressed(KEY_L):
				return {"type": "CROUCH_BLOCK"}
			return {}
		KEY_W:
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
		return combat_state_machine.can_take_pressure_movement(_player_reward_frame_value(), _enemy_break_frames_remaining(), not _player_action_locked()) or (_player_reward_window_active() and not _player_action_locked())
	return _player_reward_window_active()

func _pressure_movement_from_key(keycode: Key) -> String:
	match keycode:
		KEY_A:
			return "step_back"
		KEY_D:
			return "step_forward"
		KEY_W:
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
	if is_power_action_mode():
		player.set_free_movement_enabled(false)
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
	_cancel_player_action_lifecycle("combat_end", true)
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
	enemy_action_recovery_frames_remaining = 0.0
	enemy_action_recovery_frame_accumulator = 0.0
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
		KEY_L:
			return "crouch_block" if Input.is_key_pressed(KEY_S) else "block"
		KEY_W:
			return "jump"
		KEY_U:
			return "wait"
		KEY_A:
			return "step_back"
		KEY_D:
			return "step_forward"
		_:
			return ""
