class_name CombatStateMachine
extends RefCounted

const ActionRequestScript := preload("res://scripts/combat/action_request.gd")

enum State { PRE_FIGHT, NEUTRAL, SLOW_NEUTRAL, PLANNING, EXECUTING_QUEUE, EXECUTING_PLAYER_ACTION, PLAYER_PRESSURE, PLAYER_RECOVERY, ENEMY_INTENT, REACTION_WINDOW, ENEMY_ACTIVE, ENEMY_RECOVERY, DEFENSE_REACTION, STANCE_BREAK, PUNISH, HITSTOP, GAME_OVER }

var current_state := State.NEUTRAL
var previous_state := State.NEUTRAL
var transition_log: Array[String] = []
var last_transition := "None"
var state_started_at_msec := 0

func setup(initial_state := State.PRE_FIGHT) -> void:
	current_state = initial_state
	previous_state = initial_state
	state_started_at_msec = Time.get_ticks_msec()
	last_transition = "Init -> %s" % state_name(current_state)

func transition_to(next_state: int, reason := "") -> void:
	if not _can_transition_to(next_state):
		push_warning("Invalid combat state transition %s -> %s (%s)" % [state_name(current_state), state_name(next_state), reason])
		return
	_set_state(next_state, reason)

func enter_state(next_state: int, reason := "") -> void:
	transition_to(next_state, reason)

func exit_state(reason := "") -> void:
	transition_to(State.NEUTRAL, reason)

func current_phase_name() -> String:
	match current_state:
		State.EXECUTING_PLAYER_ACTION:
			return "PLAYER_ACTION"
		State.PLAYER_RECOVERY:
			return "PLAYER_RECOVERY"
		State.ENEMY_INTENT:
			return "ENEMY_STARTUP"
		State.REACTION_WINDOW:
			return "REACTION"
		State.ENEMY_ACTIVE:
			return "ENEMY_ACTIVE"
		State.ENEMY_RECOVERY:
			return "ENEMY_RECOVERY"
		State.HITSTOP:
			return "HITSTOP"
		_:
			return state_name(current_state).to_upper().replace(" ", "_")

func current_actor() -> String:
	match current_state:
		State.EXECUTING_QUEUE, State.EXECUTING_PLAYER_ACTION, State.PLAYER_PRESSURE, State.PLAYER_RECOVERY:
			return "player"
		State.ENEMY_INTENT, State.REACTION_WINDOW, State.ENEMY_ACTIVE, State.ENEMY_RECOVERY:
			return "enemy"
		_:
			return "none"

func can_accept_action_request(action_request, frame_advantage := 0, actor_action_ready := true) -> bool:
	if action_request == null:
		return false
	if not actor_action_ready:
		return false
	var actor_id := String(action_request.actor_id) if action_request is ActionRequestScript else String(action_request.get("actor_id", "player"))
	if is_actor_locked(actor_id):
		return false
	match current_state:
		State.SLOW_NEUTRAL, State.PLANNING, State.ENEMY_INTENT, State.REACTION_WINDOW:
			return true
		State.PLAYER_PRESSURE, State.PLAYER_RECOVERY:
			return actor_id == "player" and frame_advantage > 0
		State.STANCE_BREAK:
			return actor_id == "player" and frame_advantage > 0
		_:
			return false

func can_accept_card_input(frame_advantage := 0, player_action_ready := true) -> bool:
	var request = ActionRequestScript.new()
	request.actor_id = "player"
	request.action_id = "card"
	request.source_type = ActionRequestScript.SourceType.CARD
	return can_accept_action_request(request, frame_advantage, player_action_ready)

func can_accept_direct_input(actor_id: String, action_id: String, frame_advantage := 0, actor_action_ready := true) -> bool:
	var request = ActionRequestScript.new()
	request.actor_id = actor_id
	request.action_id = action_id
	request.source_type = ActionRequestScript.SourceType.DIRECT_INPUT
	return can_accept_action_request(request, frame_advantage, actor_action_ready)

func can_accept_ai_action(actor_id: String, action_id: String, frame_advantage := 0, actor_action_ready := true) -> bool:
	var request = ActionRequestScript.new()
	request.actor_id = actor_id
	request.action_id = action_id
	request.source_type = ActionRequestScript.SourceType.AI
	return can_accept_action_request(request, frame_advantage, actor_action_ready)

func _legacy_can_accept_player_action(frame_advantage := 0, player_action_ready := true) -> bool:
	if not player_action_ready:
		return false
	match current_state:
		State.SLOW_NEUTRAL, State.PLANNING, State.ENEMY_INTENT, State.REACTION_WINDOW:
			return true
		State.PLAYER_PRESSURE, State.PLAYER_RECOVERY:
			return frame_advantage > 0
		State.STANCE_BREAK:
			return frame_advantage > 0
		_:
			return false

func can_accept_live_defense() -> bool:
	return current_state == State.REACTION_WINDOW

func can_accept_live_movement() -> bool:
	return current_state == State.SLOW_NEUTRAL

func is_actor_locked(actor_id: String) -> bool:
	if actor_id == "player":
		return current_state == State.EXECUTING_QUEUE or current_state == State.EXECUTING_PLAYER_ACTION or current_state == State.HITSTOP or current_state == State.GAME_OVER
	if actor_id == "enemy":
		return current_state == State.ENEMY_ACTIVE or current_state == State.ENEMY_RECOVERY or current_state == State.STANCE_BREAK or current_state == State.HITSTOP or current_state == State.GAME_OVER
	return current_state == State.HITSTOP or current_state == State.GAME_OVER

func sync_compatibility_mirrors(_manager: Node) -> int:
	# Compatibility mirrors are intentionally no longer allowed to derive or
	# overwrite combat flow. Callers should use explicit transition_to calls.
	return current_state

func state_name(state_id := current_state) -> String:
	match state_id:
		State.PRE_FIGHT:
			return "Pre-Fight"
		State.NEUTRAL:
			return "Neutral"
		State.SLOW_NEUTRAL:
			return "Slow Neutral"
		State.PLANNING:
			return "Planning"
		State.EXECUTING_QUEUE:
			return "Executing Queue"
		State.EXECUTING_PLAYER_ACTION:
			return "Executing Player Action"
		State.PLAYER_PRESSURE:
			return "Player Pressure"
		State.PLAYER_RECOVERY:
			return "Player Recovery"
		State.ENEMY_INTENT:
			return "Enemy Intent"
		State.REACTION_WINDOW:
			return "Reaction Window"
		State.ENEMY_ACTIVE:
			return "Enemy Active"
		State.ENEMY_RECOVERY:
			return "Enemy Recovery"
		State.DEFENSE_REACTION:
			return "Defense Reaction"
		State.STANCE_BREAK:
			return "Stance Break"
		State.PUNISH:
			return "Punish"
		State.HITSTOP:
			return "Hitstop"
		State.GAME_OVER:
			return "Game Over"
		_:
			return "Unknown"

func is_reaction_window() -> bool:
	return current_state == State.REACTION_WINDOW

func is_queue_executing() -> bool:
	return current_state == State.EXECUTING_QUEUE or current_state == State.EXECUTING_PLAYER_ACTION

func is_slow_neutral() -> bool:
	return current_state == State.SLOW_NEUTRAL

func can_accept_queue_input() -> bool:
	return current_state == State.SLOW_NEUTRAL or current_state == State.ENEMY_INTENT or current_state == State.PLAYER_PRESSURE or current_state == State.PLAYER_RECOVERY

func can_execute_queue() -> bool:
	return current_state == State.SLOW_NEUTRAL or current_state == State.ENEMY_INTENT or current_state == State.PLAYER_PRESSURE or current_state == State.PLAYER_RECOVERY

func can_take_pressure_movement(frame_advantage: int, enemy_break_frames: int, player_action_ready := true) -> bool:
	if not player_action_ready:
		return false
	return (current_state == State.PLAYER_PRESSURE or current_state == State.PLAYER_RECOVERY or current_state == State.STANCE_BREAK) and (frame_advantage > 0 or enemy_break_frames > 0)

func can_schedule_enemy_intent(frame_advantage: int) -> bool:
	return current_state == State.NEUTRAL or (current_state == State.SLOW_NEUTRAL and frame_advantage <= 0)

func can_tick_reaction_window() -> bool:
	return current_state == State.REACTION_WINDOW

func can_tick_slow_neutral() -> bool:
	return current_state == State.SLOW_NEUTRAL

func is_punish_state() -> bool:
	return current_state == State.PUNISH

func is_enemy_recovery_state() -> bool:
	return current_state == State.ENEMY_RECOVERY or current_state == State.PUNISH or current_state == State.STANCE_BREAK

func is_enemy_flow_state() -> bool:
	return current_state == State.ENEMY_INTENT or current_state == State.REACTION_WINDOW or current_state == State.ENEMY_ACTIVE or current_state == State.ENEMY_RECOVERY

func is_player_action_state() -> bool:
	return current_state == State.EXECUTING_PLAYER_ACTION or current_state == State.PLAYER_RECOVERY

func _set_state(next_state: int, reason := "") -> void:
	if next_state == current_state:
		return
	previous_state = current_state
	current_state = next_state
	state_started_at_msec = Time.get_ticks_msec()
	last_transition = "%s -> %s%s" % [state_name(previous_state), state_name(current_state), " (%s)" % reason if reason != "" else ""]
	transition_log.append(last_transition)
	if transition_log.size() > 32:
		transition_log.pop_front()

func _can_transition_to(_next_state: int) -> bool:
	return true
