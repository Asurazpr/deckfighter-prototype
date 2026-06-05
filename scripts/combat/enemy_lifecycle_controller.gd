class_name EnemyLifecycleController
extends RefCounted

const CombatStateMachineScript := preload("res://scripts/combat/combat_state_machine.gd")

var manager

func setup(manager_ref) -> void:
	manager = manager_ref

func tick_tactical_recovery(delta: float) -> void:
	if manager == null or manager.is_power_action_mode():
		return
	_tick_recovery(delta, false)

func tick_power_recovery(delta: float) -> void:
	if manager == null or not manager.is_power_action_mode():
		return
	_tick_recovery(delta, true)

func tick_power_decision_cooldown(delta: float) -> void:
	if manager == null or not manager.is_power_action_mode() or manager.power_action_enemy_decision_cooldown_remaining <= 0.0:
		return
	var frames: float = float(manager._frames_for_delta(delta))
	manager.power_action_enemy_decision_cooldown_remaining = maxf(0.0, manager.power_action_enemy_decision_cooldown_remaining - frames)
	if manager.power_action_enemy_decision_cooldown_remaining <= 0.0:
		manager.last_power_action_enemy_reject_reason = ""

func tick_power_hitstun(delta: float) -> void:
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

func lock_frames() -> int:
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

func can_act_for_power() -> bool:
	return manager != null and manager.is_power_action_mode() and reject_reason_for_power() == ""

func locked_for_power() -> bool:
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

func reject_reason_for_power() -> String:
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

func _tick_recovery(delta: float, power_mode: bool) -> void:
	if manager == null or manager.combat_over:
		return
	if manager.combat_state_machine == null or manager.combat_state_machine.current_state != CombatStateMachineScript.State.ENEMY_RECOVERY:
		return
	if manager.enemy_action_recovery_frames_remaining <= 0.0:
		return
	var accumulator: float = manager.power_action_enemy_recovery_frame_accumulator if power_mode else manager.enemy_action_recovery_frame_accumulator
	var tick: Dictionary = manager._consume_gameplay_frames(delta, accumulator)
	if power_mode:
		manager.power_action_enemy_recovery_frame_accumulator = float(tick.get("accumulator", manager.power_action_enemy_recovery_frame_accumulator))
	else:
		manager.enemy_action_recovery_frame_accumulator = float(tick.get("accumulator", manager.enemy_action_recovery_frame_accumulator))
	var frames: int = int(tick.get("frames", 0))
	if frames <= 0:
		return
	manager.enemy_action_recovery_frames_remaining = maxf(0.0, manager.enemy_action_recovery_frames_remaining - float(frames))
	if power_mode:
		manager.power_action_enemy_recovery_frames_elapsed += float(frames)
	if manager.combat_timeline != null and manager.combat_timeline.actor == "ENEMY":
		manager.combat_timeline.advance_frames(frames)
		manager._show_enemy_timeline_phase()
	if manager.enemy_action_recovery_frames_remaining <= 0.0:
		manager._finish_enemy_resolution("recovery_complete")