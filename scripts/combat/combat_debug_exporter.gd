class_name CombatDebugExporter
extends RefCounted

const EXPORT_VERSION := 1
const PROJECT_NAME := "deckfighter-prototype"

func export_jsonl(path: String, context: Dictionary, trace_events: Array, human_log_events: Array[String], scene_path := "unknown") -> Error:
	var directory := path.get_base_dir()
	var err := DirAccess.make_dir_recursive_absolute(directory)
	if err != OK:
		return err

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	var export_timestamp := Time.get_datetime_string_from_system()
	file.store_line(JSON.stringify({
		"event_type": "export_metadata",
		"export_version": EXPORT_VERSION,
		"timestamp": export_timestamp,
		"project": PROJECT_NAME,
		"engine": "Godot",
		"scene": scene_path,
		"commit_hint": "unknown",
		"notes": "F5 combat log export"
	}))
	file.store_line(JSON.stringify({"event_type": "snapshot", "data": context}))
	for event in trace_events:
		file.store_line(JSON.stringify({"event_type": "combat_event", "data": event}))
	for i in range(human_log_events.size()):
		file.store_line(JSON.stringify({
			"event_type": "combat_event",
			"kind": "human_log",
			"index": i,
			"message": human_log_events[i]
		}))
	file.close()
	return OK
