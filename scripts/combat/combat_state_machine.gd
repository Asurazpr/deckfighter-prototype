class_name CombatStateMachine
extends RefCounted

enum State { PRE_FIGHT, NEUTRAL, SLOW_NEUTRAL, PLANNING, EXECUTING_QUEUE, PLAYER_PRESSURE, ENEMY_INTENT, REACTION_WINDOW, DEFENSE_REACTION, STANCE_BREAK, PUNISH, GAME_OVER }

var current_state := State.NEUTRAL
var previous_state := State.NEUTRAL
var transition_log: Array[String] = []

func derive_from_manager(manager: Node) -> int:
	var next_state := State.NEUTRAL
	if manager.combat_over:
		next_state = State.GAME_OVER
	elif not manager.fight_started:
		next_state = State.PRE_FIGHT
	elif manager.punish_in_progress:
		next_state = State.PUNISH
	elif manager._is_enemy_broken():
		next_state = State.STANCE_BREAK
	elif manager.reaction_window_system.active:
		next_state = State.REACTION_WINDOW
	elif manager.waiting_for_defense:
		next_state = State.EXECUTING_QUEUE if manager.queue_resolver != null and manager.queue_resolver.resolving else State.ENEMY_INTENT
	elif manager.frame_advantage > 0:
		next_state = State.EXECUTING_QUEUE if manager.queue_resolver != null and manager.queue_resolver.resolving else State.PLAYER_PRESSURE
	elif manager.movement_flow_system.active:
		next_state = State.SLOW_NEUTRAL
	_set_state(next_state)
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
		State.PLAYER_PRESSURE:
			return "Player Pressure"
		State.ENEMY_INTENT:
			return "Enemy Intent"
		State.REACTION_WINDOW:
			return "Reaction Window"
		State.DEFENSE_REACTION:
			return "Defense Reaction"
		State.STANCE_BREAK:
			return "Stance Break"
		State.PUNISH:
			return "Punish"
		State.GAME_OVER:
			return "Game Over"
		_:
			return "Unknown"

func is_reaction_window() -> bool:
	return current_state == State.REACTION_WINDOW

func is_queue_executing() -> bool:
	return current_state == State.EXECUTING_QUEUE

func is_slow_neutral() -> bool:
	return current_state == State.SLOW_NEUTRAL

func can_accept_queue_input() -> bool:
	return current_state == State.SLOW_NEUTRAL or current_state == State.ENEMY_INTENT or current_state == State.PLAYER_PRESSURE

func can_accept_live_defense() -> bool:
	return current_state == State.REACTION_WINDOW

func can_accept_live_movement() -> bool:
	return current_state == State.SLOW_NEUTRAL

func _set_state(next_state: int) -> void:
	if next_state == current_state:
		return
	previous_state = current_state
	current_state = next_state
	transition_log.append("%s -> %s" % [state_name(previous_state), state_name(current_state)])
	if transition_log.size() > 32:
		transition_log.pop_front()
