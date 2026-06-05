class_name CombatTraceLogger
extends RefCounted

var manager
var combat_trace_events: Array[Dictionary] = []

func setup(manager_ref) -> void:
	manager = manager_ref

func get_combat_trace_events() -> Array:
	return combat_trace_events.duplicate(true)

func record_combat_event(event_type: String, message := "", data := {}) -> void:
	var event: Dictionary = data.duplicate(true)
	event["event_type"] = event_type
	event["timestamp"] = Time.get_datetime_string_from_system()
	if message != "":
		event["message"] = message
	combat_trace_events.append(event)

func record_action_lifecycle_event(event_type: String, data := {}) -> void:
	var event: Dictionary = data.duplicate(true)
	record_combat_event(event_type, event_type, event)
	var actor := String(event.get("actor", "actor"))
	var move_id := String(event.get("move_id", "unknown"))
	if manager != null:
		manager.log_message.emit("%s %s %s." % [actor.to_upper(), move_id, event_type])

func record_rejected_action(actor: String, reason: String, move_id := "") -> void:
	record_action_lifecycle_event("REJECTED_ACTION", {
		"actor": actor,
		"move_id": move_id,
		"reason": reason,
		"rejection_reason": reason,
		"global_combat_state": manager._current_mode() if manager != null else "unknown",
		"player_phase": manager._player_phase_for_log() if manager != null else "unknown",
		"enemy_phase": manager._enemy_phase_for_log() if manager != null else "unknown",
		"player_can_act": manager._power_action_player_can_act() if manager != null else false,
		"enemy_can_act": manager._power_action_enemy_can_act() if manager != null else false
	})

func action_request_source_name(action_request) -> String:
	if action_request is Dictionary:
		return String(action_request.get("source_type", "unknown"))
	if action_request != null and action_request.has_method("source_type_name"):
		return action_request.source_type_name()
	return "none"
