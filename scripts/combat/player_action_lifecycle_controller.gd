class_name PlayerActionLifecycleController
extends RefCounted

const ActionRequestScript := preload("res://scripts/combat/action_request.gd")

var manager

var active := false
var done := true
var release_authorized := false
var release_reason := ""
var action_id := ""
var card_name := ""
var phase := "DONE"
var token := 0
var recovery_frames_remaining := 0.0
var recovery_running := false
var power_recovery_frame_accumulator := 0.0

func setup(manager_ref) -> void:
	manager = manager_ref

func begin(card: Resource) -> void:
	token += 1
	active = true
	done = false
	release_authorized = false
	release_reason = ""
	action_id = String(card.id) if card != null else "unknown"
	card_name = String(card.display_name) if card != null else "Unknown"
	phase = "STARTUP"
	recovery_frames_remaining = 0.0
	recovery_running = false
	power_recovery_frame_accumulator = 0.0
	manager.log_message.emit("Player action lifecycle start: %s (%s)." % [action_id, card_name])
	manager._record_combat_event("player_action_lifecycle", "Player action lifecycle start.", {
		"action_id": action_id,
		"card_name": card_name,
		"phase": phase,
		"authorized_by": "CombatManager"
	})

func begin_trade_recovery(card: Resource, recovery_frames: int, action_request = null) -> void:
	token += 1
	active = true
	done = false
	release_authorized = false
	release_reason = ""
	action_id = String(card.id) if card != null else "trade"
	card_name = String(card.display_name) if card != null else "Trade"
	phase = "TRADE_RECOVERY"
	recovery_frames_remaining = float(maxi(0, recovery_frames))
	recovery_running = true
	power_recovery_frame_accumulator = 0.0
	manager.current_player_action_request = action_request if action_request != null else (ActionRequestScript.from_card("player", card, -1, Engine.get_process_frames()) if card != null else null)
	manager.hitbox_system.enter_player_recovery()
	manager.log_message.emit("Player trade recovery lifecycle started: action=%s card=%s recovery_frames=%d." % [
		action_id,
		card_name,
		recovery_frames
	])
	manager._record_combat_event("player_action_lifecycle", "Player trade recovery lifecycle started.", {
		"action_id": action_id,
		"card_name": card_name,
		"phase": phase,
		"recovery_frames": recovery_frames,
		"authorized_by": "CombatManager"
	})

func set_phase(phase_name: String, reason := "") -> void:
	if phase == phase_name:
		return
	phase = phase_name
	var detail: String = " (%s)" % reason if reason != "" else ""
	manager.log_message.emit("Player action lifecycle phase: %s -> %s%s." % [action_id, phase_name, detail])
	manager._record_combat_event("player_action_lifecycle", "Player action lifecycle phase changed.", {
		"action_id": action_id,
		"card_name": card_name,
		"phase": phase_name,
		"reason": reason,
		"authorized_by": "CombatManager"
	})

func blocks_card_input() -> bool:
	return active and not done and not release_authorized

func visual_locked(player_trade_recovery_frames: float) -> bool:
	return (active and not done) or player_trade_recovery_frames > 0.0

func authorize_release(reason: String) -> void:
	if not active or done:
		return
	if release_authorized:
		return
	release_authorized = true
	release_reason = reason
	manager.log_message.emit("Player action lifecycle release authorized: %s (%s)." % [action_id, reason])
	manager._record_combat_event("player_action_lifecycle", "Player action lifecycle release authorized.", {
		"action_id": action_id,
		"card_name": card_name,
		"phase": phase,
		"release_reason": reason,
		"authorized_by": "CombatManager"
	})
	manager.player_action_lifecycle_released.emit(reason)

func finish(expected_token: int, reason := "recovery_complete") -> void:
	if expected_token != token:
		return
	if not active:
		return
	set_phase("DONE", reason)
	active = false
	done = true
	release_authorized = true
	release_reason = reason
	recovery_frames_remaining = 0.0
	recovery_running = false
	power_recovery_frame_accumulator = 0.0
	manager.current_player_action_request = null
	manager.hitbox_system.finish_player_move()
	if manager.combat_timeline != null and manager.combat_timeline.actor == "PLAYER":
		manager.combat_timeline.finish_action()
	if manager.player != null and manager.player.has_method("finish_action_from_combat_manager"):
		manager.player.finish_action_from_combat_manager(reason)
	manager.log_message.emit("Player action lifecycle done authorized by CombatManager: %s (%s)." % [action_id, reason])
	manager._record_combat_event("player_action_lifecycle", "Player action lifecycle done.", {
		"action_id": action_id,
		"card_name": card_name,
		"phase": "DONE",
		"reason": reason,
		"authorized_by": "CombatManager"
	})
	manager._record_action_lifecycle_event("ACTION_DONE", {
		"actor": "player",
		"move_id": action_id
	})
	manager.player_action_lifecycle_released.emit(reason)
	manager._handle_power_action_player_lifecycle_done(reason)

func cancel(reason := "cancelled", finish_visual := false) -> void:
	if not active and done:
		return
	token += 1
	active = false
	done = true
	release_authorized = true
	release_reason = reason
	phase = "DONE"
	recovery_frames_remaining = 0.0
	recovery_running = false
	power_recovery_frame_accumulator = 0.0
	manager.current_player_action_request = null
	manager.hitbox_system.finish_player_move()
	manager.log_message.emit("Player action lifecycle cancelled: %s." % reason)
	if finish_visual and manager.player != null and manager.player.has_method("finish_action_from_combat_manager"):
		manager.player.finish_action_from_combat_manager(reason)
	manager.player_action_lifecycle_released.emit(reason)

func start_recovery(card: Resource) -> void:
	if not active or recovery_running:
		return
	var expected_token := token
	var recovery_frames: int = maxi(0, int(card.frame_cost)) if card != null else 0
	recovery_running = true
	recovery_frames_remaining = float(recovery_frames)
	power_recovery_frame_accumulator = 0.0
	manager.log_message.emit("Player action recovery started: %s %df." % [action_id, recovery_frames])
	if recovery_frames <= 0:
		finish(expected_token, "zero_recovery")
		return
	await manager.get_tree().create_timer(manager._player_action_frames_to_seconds(recovery_frames), false, true).timeout
	if expected_token != token or not active:
		return
	if manager.is_power_action_mode():
		recovery_frames_remaining = 0.0
		finish(expected_token, "recovery_complete")
		return
	manager.advance_combat_frames(recovery_frames)
	finish(expected_token, "recovery_complete")

func tick_power_recovery(delta: float) -> void:
	if manager == null or not manager.is_power_action_mode() or manager.combat_over:
		return
	if not active or not recovery_running:
		return
	if recovery_frames_remaining <= 0.0:
		return
	var tick: Dictionary = manager._consume_gameplay_frames(delta, power_recovery_frame_accumulator)
	power_recovery_frame_accumulator = float(tick.get("accumulator", power_recovery_frame_accumulator))
	var frames: int = int(tick.get("frames", 0))
	if frames <= 0:
		return
	recovery_frames_remaining = maxf(0.0, recovery_frames_remaining - float(frames))
	if recovery_frames_remaining <= 0.0:
		finish(token, "recovery_complete")