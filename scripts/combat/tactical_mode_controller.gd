class_name TacticalModeController
extends RefCounted

const ActionRequestScript := preload("res://scripts/combat/action_request.gd")

var manager
var deck_manager
var queue_resolver

const TICK_PROCESS_RECOVERY := "process_recovery"
const TICK_PROCESS_QUEUE := "process_queue"
const TICK_PROCESS_FLOW := "process_flow"

func setup(manager_ref, deck_manager_ref, queue_resolver_ref) -> void:
	manager = manager_ref
	deck_manager = deck_manager_ref
	queue_resolver = queue_resolver_ref

func tick_tactical_mode(delta: float, tick_stage := TICK_PROCESS_FLOW) -> void:
	if manager == null or manager.combat_over or not manager.is_time_tactical_mode():
		return
	match tick_stage:
		TICK_PROCESS_RECOVERY:
			manager._tick_enemy_action_recovery(delta)
		TICK_PROCESS_QUEUE:
			manager._execute_ready_queue_after_movement()
		TICK_PROCESS_FLOW:
			manager._tick_reaction_window(delta)
			manager._tick_slow_neutral(delta)
			manager._tick_reaction_jump_arc(delta)

func action_request_from_card(card: Resource, queued_index := -1, input_frame := 0) -> ActionRequest:
	return ActionRequestScript.from_card("player", card, queued_index, input_frame)

func action_request_from_hand_index(index: int, input_frame := 0) -> ActionRequest:
	if deck_manager == null or not ("hand" in deck_manager):
		return null
	if index < 0 or index >= deck_manager.hand.size():
		return null
	return action_request_from_card(deck_manager.hand[index], index, input_frame)

func is_queue_empty() -> bool:
	return queue_resolver == null or queue_resolver.is_empty()

func queue_text() -> String:
	if queue_resolver == null:
		return "Queue: Empty"
	return queue_resolver.queue_text()


func can_play_cards() -> bool:
	if manager == null:
		return false
	if manager.is_power_action_mode():
		return false
	if not manager.fight_started:
		return false
	if manager._is_reaction_window_state():
		return false
	var state_allows: bool = manager._combat_core_allows_action_request(manager._player_card_action_request(), not manager._player_action_locked())
	return state_allows and (manager._is_enemy_intent_state() or pressure_movement_allowed()) and not manager.combat_over

func is_hand_card_playable(index: int) -> bool:
	if manager == null or deck_manager == null or not ("hand" in deck_manager):
		return false
	if manager.is_power_action_mode():
		return false
	if not manager.fight_started:
		return false
	if manager._player_action_locked():
		return false
	if not manager._combat_core_allows_action_request(manager._player_card_action_request(index), true):
		return false
	if not _has_hand_card(index):
		return false
	if manager._is_reaction_window_state() or manager._is_slow_neutral_state() or manager._is_enemy_intent_state():
		return not manager._is_card_instance_queued(deck_manager.hand[index])
	return can_play_cards() and not manager._is_card_instance_queued(deck_manager.hand[index])

func card_input_rejection_reason(index: int) -> String:
	if manager == null:
		return "missing tactical manager"
	if manager.is_power_action_mode():
		return "POWER_ACTION uses direct inputs J/K/U/I; cards do not mutate the deck"
	if deck_manager == null or not ("hand" in deck_manager) or index < 0 or index >= deck_manager.hand.size():
		return "no hand card at index %d" % index
	if manager._is_card_instance_queued(deck_manager.hand[index]):
		return "card instance already queued"
	if manager.combat_over:
		return "combat over"
	if not manager.fight_started:
		return "fight has not started"
	if manager._queue_is_resolving():
		return "queue is already executing"
	if manager._player_action_locked():
		return "player action is still recovering (%s)" % manager._player_action_lock_reason()
	if not manager._combat_core_allows_action_request(manager._player_card_action_request(index), true):
		return "state machine locked input: state=%s phase=%s actor=%s transition=%s reward_value=%d" % [
			manager.combat_state_machine.state_name(),
			manager.combat_state_machine.current_phase_name(),
			manager.combat_state_machine.current_actor(),
			manager.combat_state_machine.last_transition,
			player_reward_frame_value()
		]
	if manager._is_reaction_window_state():
		return ""
	if manager._is_slow_neutral_state():
		return ""
	if manager._is_enemy_intent_state():
		return ""
	if can_play_cards():
		return ""
	return "current state does not accept card input (%s frame_advantage=%d)" % [manager._player_action_lock_reason(), manager.frame_advantage]

func card_playability_snapshot(index: int) -> Dictionary:
	if manager == null:
		return {}
	var player_can_act: bool = not manager._player_action_locked()
	var request = manager._player_card_action_request(index)
	var core_can_accept: bool = manager._combat_core_allows_action_request(request, player_can_act)
	var tactical_can_play: bool = tactical_card_gate_allows(index, core_can_accept, player_can_act)
	return {
		"control_mode": manager.get_control_mode_name(),
		"combat_state": manager.combat_state_machine.state_name() if manager.combat_state_machine != null else "None",
		"combat_phase": manager.combat_state_machine.current_phase_name() if manager.combat_state_machine != null else "None",
		"frame_advantage": manager.frame_advantage,
		"reward_value": player_reward_frame_value(),
		"reward_window_active": player_reward_window_active(),
		"player_phase": manager._player_phase_for_log(),
		"player_can_act": player_can_act,
		"player_action_locked": not player_can_act,
		"player_lock_reason": manager._player_action_lock_reason() if not player_can_act else "",
		"enemy_phase": manager._enemy_phase_for_log(),
		"queue_empty": queue_resolver == null or queue_resolver.is_empty(),
		"queue_resolving": manager._queue_is_resolving(),
		"core_can_accept": core_can_accept,
		"tactical_can_play": tactical_can_play,
		"action_request": request.to_dict() if request != null and request.has_method("to_dict") else {}
	}

func tactical_card_gate_allows(index: int, core_can_accept: bool, player_can_act: bool) -> bool:
	if manager == null or deck_manager == null or not ("hand" in deck_manager):
		return false
	if manager.is_power_action_mode() or not manager.fight_started or manager.combat_over:
		return false
	if index < 0 or index >= deck_manager.hand.size():
		return false
	if manager._is_card_instance_queued(deck_manager.hand[index]):
		return false
	if not player_can_act or not core_can_accept:
		return false
	if manager._is_reaction_window_state() or manager._is_slow_neutral_state() or manager._is_enemy_intent_state():
		return true
	return can_play_cards()

func player_reward_frame_value() -> int:
	if manager == null:
		return 0
	return maxi(manager.frame_advantage, manager._enemy_break_frames_remaining())

func player_reward_window_active() -> bool:
	if manager == null:
		return false
	if not manager.is_time_tactical_mode():
		return false
	if manager.combat_over or not manager.fight_started:
		return false
	if manager.player_trade_recovery_frames_remaining > 0.0 or manager._player_action_lifecycle_blocks_card_input():
		return false
	return player_reward_frame_value() > 0

func pressure_movement_allowed() -> bool:
	if manager == null:
		return false
	if manager.combat_over or manager._is_enemy_intent_state():
		return false
	if manager.combat_state_machine != null:
		return manager.combat_state_machine.can_take_pressure_movement(player_reward_frame_value(), manager._enemy_break_frames_remaining(), not manager._player_action_locked()) or (player_reward_window_active() and not manager._player_action_locked())
	return player_reward_window_active()

func can_execute_queue() -> bool:
	return manager != null and manager.combat_state_machine != null and (manager.combat_state_machine.can_execute_queue() or player_reward_window_active()) and not manager._queue_is_resolving()

func can_accept_queue_input() -> bool:
	if manager == null:
		return false
	if manager._is_stale_executing_queue_state():
		return true
	return manager.combat_state_machine != null and (manager.combat_state_machine.can_accept_queue_input() or player_reward_window_active()) and not manager.combat_over

func tactical_input_mode_active() -> bool:
	return manager != null and not manager.combat_over and manager.combat_state_machine != null and (manager.combat_state_machine.can_accept_queue_input() or player_reward_window_active() or manager._is_stale_executing_queue_state())

func has_valid_card_for_current_state() -> bool:
	return manager != null and manager.route_system != null and manager.route_system.has_valid_card(manager._is_enemy_broken())

func _has_hand_card(index: int) -> bool:
	return deck_manager != null and ("hand" in deck_manager) and index >= 0 and index < deck_manager.hand.size()
