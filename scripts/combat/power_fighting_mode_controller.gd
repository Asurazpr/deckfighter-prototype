class_name PowerFightingModeController
extends RefCounted

const ActionRequestScript := preload("res://scripts/combat/action_request.gd")
const CombatStateMachineScript := preload("res://scripts/combat/combat_state_machine.gd")

var manager
var direct_input_map := {
	"J": "light_punch",
	"K": "light_kick",
	"U": "heavy_punch",
	"I": "heavy_kick"
}

const TICK_PROCESS_PRE := "process_pre"
const TICK_PROCESS_FLOW := "process_flow"
const TICK_PHYSICS := "physics"

func setup(manager_ref) -> void:
	manager = manager_ref

func tick_power_mode(delta: float, tick_stage := TICK_PHYSICS) -> void:
	if manager == null or manager.combat_over or not manager.is_power_action_mode():
		return
	match tick_stage:
		TICK_PROCESS_PRE:
			manager._tick_power_action_neutral_crouch()
			manager._log_power_action_movement_gate()
		TICK_PROCESS_FLOW:
			manager._tick_slow_neutral(delta)
			manager._tick_power_action_live_movement(delta)
		TICK_PHYSICS:
			manager._tick_power_action_block(delta)
			manager._tick_power_action_enemy_intent(delta)
			manager._tick_power_action_enemy_active(delta)
			manager._tick_power_action_enemy_recovery(delta)
			manager._tick_power_action_enemy_decision_cooldown(delta)
			manager._tick_power_action_enemy_hitstun(delta)
			manager._tick_power_action_player_recovery(delta)
			manager._update_power_action_live_frame_advantage()

func move_for_input(input_name: String) -> String:
	return String(direct_input_map.get(input_name, ""))

func action_request_for_input(input_name: String, move_id: String, input_frame := 0, payload := {}) -> ActionRequest:
	var request_payload := payload.duplicate(true) if payload is Dictionary else {}
	request_payload["input_name"] = input_name
	request_payload["control_mode"] = "POWER_ACTION"
	return ActionRequestScript.from_direct_input("player", move_id, input_name, input_frame, 0, request_payload)

func request_direct_action(input_name: String, move_id: String) -> ActionRequest:
	return action_request_for_input(input_name, move_id, Engine.get_process_frames(), {
		"source_controller": "PowerFightingModeController"
	})

func player_reject_reason() -> String:
	if manager == null:
		return "missing_manager"
	if manager.combat_over:
		return "combat_over"
	if not manager.fight_started:
		return "fight_not_started"
	if manager._queue_is_resolving() or manager.queued_action_in_progress:
		return "queue_executing"
	if manager._player_action_locked():
		return manager._player_action_lock_reason()
	if manager.player_trade_recovery_frames_remaining > 0.0:
		return "player_trade_recovery"
	if manager.combat_state_machine != null:
		if manager.combat_state_machine.current_state == CombatStateMachineScript.State.ENEMY_ACTIVE:
			return "enemy_active"
		if manager.combat_state_machine.current_state == CombatStateMachineScript.State.HITSTOP:
			return "hitstop"
		if manager.combat_state_machine.current_state == CombatStateMachineScript.State.GAME_OVER:
			return "game_over"
	return ""

func player_can_act() -> bool:
	return manager != null and manager.is_power_action_mode() and player_reject_reason() == ""

func enemy_can_act() -> bool:
	return manager != null and manager.is_power_action_mode() and enemy_reject_reason() == ""

func block_reject_reason() -> String:
	if manager == null:
		return "missing_manager"
	if manager.combat_over:
		return "combat_over"
	if not manager.fight_started:
		return "fight_not_started"
	if manager.player_trade_recovery_frames_remaining > 0.0:
		return "player_trade_recovery"
	if manager._queue_is_resolving() or manager.queued_action_in_progress:
		return "queue_executing"
	if manager.player != null and manager.player.has_method("get_stance_state_name") and String(manager.player.get_stance_state_name()) != "NORMAL":
		return "broken"
	var debug: Dictionary = manager._player_debug()
	var logic_state: String = String(debug.get("logic_state", debug.get("action_state", "NEUTRAL"))).to_lower()
	if logic_state.find("hitstun") != -1:
		return "hitstun"
	if logic_state.find("blockstun") != -1:
		return "blockstun"
	if logic_state.find("attack_startup") != -1 or logic_state.find("attack_active") != -1 or logic_state.find("attack_recovery") != -1:
		return "action_locked"
	if manager._player_action_locked():
		return manager._player_action_lock_reason()
	return ""

func crouch_reject_reason() -> String:
	if manager == null:
		return "missing_manager"
	if manager.combat_over:
		return "combat_over"
	if not manager.fight_started:
		return "fight_not_started"
	if manager.player_trade_recovery_frames_remaining > 0.0:
		return "player_trade_recovery"
	if manager._queue_is_resolving() or manager.queued_action_in_progress:
		return "queue_executing"
	if manager.combat_state_machine != null:
		if manager.combat_state_machine.current_state == CombatStateMachineScript.State.HITSTOP:
			return "hitstop"
		if manager.combat_state_machine.current_state == CombatStateMachineScript.State.GAME_OVER:
			return "game_over"
	if manager.player != null and manager.player.has_method("get_stance_state_name") and String(manager.player.get_stance_state_name()) != "NORMAL":
		return "broken"
	var debug: Dictionary = manager._player_debug()
	var logic_state: String = String(debug.get("logic_state", debug.get("action_state", "NEUTRAL"))).to_lower()
	if logic_state.find("hitstun") != -1:
		return "hitstun"
	if logic_state.find("blockstun") != -1:
		return "blockstun"
	if logic_state.find("attack_startup") != -1 or logic_state.find("attack_active") != -1 or logic_state.find("attack_recovery") != -1:
		return "action_locked"
	if manager._player_action_locked():
		return manager._player_action_lock_reason()
	return ""

func movement_allowed() -> bool:
	return manager != null and manager.is_power_action_mode() and movement_reject_reason() == ""

func movement_reject_reason() -> String:
	if manager == null:
		return "missing_manager"
	if manager.combat_over:
		return "combat_over"
	if not manager.fight_started:
		return "fight_not_started"
	if manager.combat_state_machine == null:
		return "missing_state_machine"
	var reject_reason: String = player_reject_reason()
	if reject_reason != "":
		return reject_reason
	return ""

func enemy_locked() -> bool:
	if manager == null:
		return true
	return manager.attack_in_progress \
		or manager.waiting_for_defense \
		or manager.current_enemy_intent != "" \
		or manager.power_action_enemy_decision_cooldown_remaining > 0.0 \
		or manager._enemy_recovery_frames_remaining() > 0 \
		or manager.enemy_vulnerable_frames_remaining > 0 \
		or manager._enemy_break_frames_remaining() > 0 \
		or (manager.enemy != null and not manager.enemy.can_act())

func enemy_reject_reason() -> String:
	if manager == null:
		return "missing_manager"
	if manager.combat_state_machine != null and manager.combat_state_machine.current_state == CombatStateMachineScript.State.ENEMY_ACTIVE:
		return "already_active"
	if manager._enemy_recovery_frames_remaining() > 0:
		return "recovery"
	if manager.waiting_for_defense or manager.current_enemy_intent != "":
		return "startup"
	if manager.power_action_enemy_decision_cooldown_remaining > 0.0:
		return "decision_cooldown"
	if manager.attack_in_progress:
		return "already_active"
	if manager.enemy_vulnerable_frames_remaining > 0:
		return "enemy_hitstun"
	if manager._enemy_break_frames_remaining() > 0:
		return "blockstun"
	if manager.enemy != null and not manager.enemy.can_act():
		return "interrupted"
	return ""
