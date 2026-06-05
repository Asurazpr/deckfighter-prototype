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
			tick_enemy_recovery(delta)
			manager._tick_power_action_enemy_decision_cooldown(delta)
			tick_enemy_hitstun(delta)
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

func tick_enemy_recovery(delta: float) -> void:
	if manager == null or not manager.is_power_action_mode() or manager.combat_over:
		return
	if manager.combat_state_machine == null or manager.combat_state_machine.current_state != CombatStateMachineScript.State.ENEMY_RECOVERY:
		return
	if manager.enemy_action_recovery_frames_remaining <= 0.0:
		return
	var tick: Dictionary = manager._consume_gameplay_frames(delta, manager.power_action_enemy_recovery_frame_accumulator)
	manager.power_action_enemy_recovery_frame_accumulator = float(tick.get("accumulator", manager.power_action_enemy_recovery_frame_accumulator))
	var frames: int = int(tick.get("frames", 0))
	if frames <= 0:
		return
	manager.enemy_action_recovery_frames_remaining = maxf(0.0, manager.enemy_action_recovery_frames_remaining - float(frames))
	manager.power_action_enemy_recovery_frames_elapsed += float(frames)
	if manager.combat_timeline != null and manager.combat_timeline.actor == "ENEMY":
		manager.combat_timeline.advance_frames(frames)
		manager._show_enemy_timeline_phase()
	if manager.enemy_action_recovery_frames_remaining <= 0.0:
		manager._finish_enemy_resolution("recovery_complete")

func tick_enemy_hitstun(delta: float) -> void:
	if manager == null or not manager.is_power_action_mode() or manager.enemy_vulnerable_frames_remaining <= 0:
		return
	var tick: Dictionary = manager._consume_gameplay_frames(delta, manager.power_action_enemy_hitstun_frame_accumulator)
	manager.power_action_enemy_hitstun_frame_accumulator = float(tick.get("accumulator", manager.power_action_enemy_hitstun_frame_accumulator))
	var frames: int = int(tick.get("frames", 0))
	if frames <= 0:
		return
	manager.enemy_vulnerable_frames_remaining = maxi(0, manager.enemy_vulnerable_frames_remaining - frames)
	if manager.enemy_vulnerable_frames_remaining <= 0:
		manager.last_power_action_enemy_reject_reason = ""

func tick_player_recovery(delta: float) -> void:
	if manager == null or not manager.is_power_action_mode() or manager.combat_over:
		return
	if not manager.player_action_lifecycle_active or not manager.player_action_lifecycle_recovery_running:
		return
	if manager.player_action_lifecycle_recovery_frames_remaining <= 0.0:
		return
	var tick: Dictionary = manager._consume_gameplay_frames(delta, manager.power_action_player_recovery_frame_accumulator)
	manager.power_action_player_recovery_frame_accumulator = float(tick.get("accumulator", manager.power_action_player_recovery_frame_accumulator))
	var frames: int = int(tick.get("frames", 0))
	if frames <= 0:
		return
	manager.player_action_lifecycle_recovery_frames_remaining = maxf(0.0, manager.player_action_lifecycle_recovery_frames_remaining - float(frames))
	if manager.player_action_lifecycle_recovery_frames_remaining <= 0.0:
		manager._finish_player_action_lifecycle(manager.player_action_lifecycle_token, "recovery_complete")

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
	var remaining: int = int(ceil(maxf(manager.player_trade_recovery_frames_remaining, manager.player_action_lifecycle_recovery_frames_remaining)))
	if manager.player_action_lifecycle_active and not manager.player_action_lifecycle_done and remaining <= 0:
		remaining = 1
	var debug: Dictionary = manager._player_debug()
	var logic_state: String = String(debug.get("logic_state", debug.get("action_state", "NEUTRAL"))).to_lower()
	if logic_state.find("hitstun") != -1 or logic_state.find("blockstun") != -1:
		remaining = maxi(remaining, 1)
	return remaining

func enemy_lock_frames() -> int:
	if manager == null:
		return 0
	var remaining: int = 0
	if manager.current_enemy_intent != "" and manager.remaining_startup_frames > 0:
		remaining = maxi(remaining, manager.remaining_startup_frames)
	if manager.power_action_enemy_active_frames_remaining > 0.0:
		remaining = maxi(remaining, int(ceil(manager.power_action_enemy_active_frames_remaining)))
	if manager.enemy_action_recovery_frames_remaining > 0.0:
		remaining = maxi(remaining, int(ceil(manager.enemy_action_recovery_frames_remaining)))
	if manager.enemy_vulnerable_frames_remaining > 0:
		remaining = maxi(remaining, manager.enemy_vulnerable_frames_remaining)
	if manager.enemy_trade_recovery_frames_remaining > 0.0:
		remaining = maxi(remaining, int(ceil(manager.enemy_trade_recovery_frames_remaining)))
	if manager._enemy_break_frames_remaining() > 0:
		remaining = maxi(remaining, manager._enemy_break_frames_remaining())
	return remaining

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
