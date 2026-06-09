class_name PowerFightingModeController
extends RefCounted

const ActionRequestScript := preload("res://scripts/combat/action_request.gd")
const CombatStateMachineScript := preload("res://scripts/combat/combat_state_machine.gd")

var manager
var enemy_lifecycle_controller
var player_action_lifecycle_controller
var direct_input_map := {
	"J": "light_punch",
	"K": "light_kick",
	"U": "heavy_punch",
	"I": "heavy_kick"
}

const TICK_PROCESS_PRE := "process_pre"
const TICK_PROCESS_FLOW := "process_flow"
const TICK_PHYSICS := "physics"

func setup(manager_ref, enemy_lifecycle_controller_ref = null, player_action_lifecycle_controller_ref = null) -> void:
	manager = manager_ref
	enemy_lifecycle_controller = enemy_lifecycle_controller_ref
	player_action_lifecycle_controller = player_action_lifecycle_controller_ref

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
			var enemy_lifecycle = _enemy_lifecycle()
			if enemy_lifecycle != null:
				enemy_lifecycle.tick_power_recovery(delta)
				enemy_lifecycle.tick_power_decision_cooldown(delta)
				enemy_lifecycle.tick_power_hitstun(delta)
			manager._tick_power_action_player_hitstun(delta)
			tick_player_recovery(delta)
			tick_live_frame_advantage()

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
func _enemy_lifecycle():
	if enemy_lifecycle_controller != null:
		return enemy_lifecycle_controller
	if manager != null:
		return manager.enemy_lifecycle_controller
	return null
func _player_lifecycle():
	if player_action_lifecycle_controller != null:
		return player_action_lifecycle_controller
	if manager != null:
		return manager.player_action_lifecycle_controller
	return null

func tick_enemy_recovery(delta: float) -> void:
	var enemy_lifecycle = _enemy_lifecycle()
	if enemy_lifecycle != null:
		enemy_lifecycle.tick_power_recovery(delta)

func tick_enemy_decision_cooldown(delta: float) -> void:
	var enemy_lifecycle = _enemy_lifecycle()
	if enemy_lifecycle != null:
		enemy_lifecycle.tick_power_decision_cooldown(delta)

func tick_enemy_hitstun(delta: float) -> void:
	var enemy_lifecycle = _enemy_lifecycle()
	if enemy_lifecycle != null:
		enemy_lifecycle.tick_power_hitstun(delta)

func tick_player_recovery(delta: float) -> void:
	var player_lifecycle = _player_lifecycle()
	if player_lifecycle != null:
		player_lifecycle.tick_power_recovery(delta)

func tick_live_frame_advantage() -> void:
	if manager == null or not manager.is_power_action_mode() or manager.combat_over:
		return
	var player_frames: int = player_lock_frames()
	var enemy_frames: int = enemy_lock_frames()
	var live_advantage: int = 0
	if player_frames > 0 or enemy_frames > 0:
		live_advantage = enemy_frames - player_frames
	if live_advantage == manager.frame_advantage:
		return
	var previous: int = manager.frame_advantage
	manager.frame_advantage = live_advantage
	manager.frame_advantage_changed.emit(manager.frame_advantage)
	manager._record_combat_event("POWER_ACTION_FRAME_ADVANTAGE", "POWER_ACTION live frame advantage updated.", {
		"previous": previous,
		"frame_advantage": manager.frame_advantage,
		"player_lock_frames": player_frames,
		"enemy_lock_frames": enemy_frames,
		"player_phase": manager._player_phase_for_log(),
		"enemy_phase": manager._enemy_phase_for_log(),
		"combat_state": manager._current_mode()
	})

func player_lock_frames() -> int:
	if manager == null:
		return 0
	var player_lifecycle = _player_lifecycle()
	var lifecycle_recovery: float = player_lifecycle.recovery_frames_remaining if player_lifecycle != null else 0.0
	var remaining: int = int(ceil(maxf(maxf(manager.player_trade_recovery_frames_remaining, lifecycle_recovery), manager.power_action_player_hitstun_frames_remaining)))
	if player_lifecycle != null and player_lifecycle.active and not player_lifecycle.done and remaining <= 0:
		remaining = 1
	var debug: Dictionary = manager._player_debug()
	var logic_state: String = String(debug.get("logic_state", debug.get("action_state", "NEUTRAL"))).to_lower()
	if logic_state.find("hitstun") != -1 or logic_state.find("blockstun") != -1:
		remaining = maxi(remaining, 1)
	return remaining

func enemy_lock_frames() -> int:
	var enemy_lifecycle = _enemy_lifecycle()
	if enemy_lifecycle != null:
		return enemy_lifecycle.lock_frames()
	return 0

func player_reject_reason() -> String:
	if manager == null:
		return "missing_manager"
	if manager.combat_over:
		return "combat_over"
	if not manager.fight_started:
		return "fight_not_started"
	if manager.power_action_player_hitstun_frames_remaining > 0.0:
		return "hitstun"
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
	var enemy_lifecycle = _enemy_lifecycle()
	return enemy_lifecycle != null and enemy_lifecycle.can_act_for_power()

func block_reject_reason() -> String:
	if manager == null:
		return "missing_manager"
	if manager.combat_over:
		return "combat_over"
	if not manager.fight_started:
		return "fight_not_started"
	if manager.power_action_player_hitstun_frames_remaining > 0.0:
		return "hitstun"
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
	if manager.power_action_player_hitstun_frames_remaining > 0.0:
		return "hitstun"
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
	var enemy_lifecycle = _enemy_lifecycle()
	return enemy_lifecycle == null or enemy_lifecycle.locked_for_power()

func enemy_reject_reason() -> String:
	var enemy_lifecycle = _enemy_lifecycle()
	if enemy_lifecycle != null:
		return enemy_lifecycle.reject_reason_for_power()
	return "missing_manager"
