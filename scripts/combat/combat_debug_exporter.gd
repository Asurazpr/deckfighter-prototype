class_name CombatDebugExporter
extends RefCounted

const EXPORT_VERSION := 1
const PROJECT_NAME := "deckfighter-prototype"

static func build_export_context(manager: Node) -> Dictionary:
	return {
		"timestamp": Time.get_datetime_string_from_system(),
		"combat_state": manager._current_mode(),
		"control_mode": manager.get_control_mode_name(),
		"frame_advantage": manager.frame_advantage,
		"distance": manager._distance_between_fighters(),
		"input_lock_state": manager._input_lock_state(),
		"input_rejected_reason": manager.get_card_input_rejection_reason(0),
		"player_actor_state": manager.player_actor_state.to_dict() if manager.player_actor_state != null else {},
		"enemy_actor_state": manager.enemy_actor_state.to_dict() if manager.enemy_actor_state != null else {},
		"last_state_transition": manager.combat_state_machine.last_transition,
		"player_animation": animation_debug_for(manager, manager.player, "player"),
		"enemy_animation": animation_debug_for(manager, manager.enemy, "enemy"),
		"reaction": reaction_export_data(manager),
		"movement": movement_export_data(manager),
		"enemy_ai": manager.enemy_ai_system.debug_text(),
		"enemy_ai_state": manager.enemy_ai_system.last_state,
		"enemy_ai_action": manager.enemy_ai_system.last_chosen_action,
		"enemy_ai_reason": manager.enemy_ai_system.last_reason,
		"enemy_ai_score": manager.enemy_ai_system.last_score,
		"enemy_approach_end_reason": "reached_range" if manager.movement_flow_system.last_distance <= manager.enemy_intent_range else "approaching",
		"enemy_next_intent_evaluation": manager.enemy_ai_system.last_reason,
		"enemy_approach_target_distance": manager.get_enemy_approach_target_distance(),
		"closest_usable_move_range": manager._closest_enemy_attack_max_range(),
		"reason_no_attack_reaches": manager.last_no_attack_reaches_reason,
		"defensive_reaction_retry_count": manager.defensive_reaction_retry_count,
		"defensive_reaction_fallback": manager.defensive_reaction_fallback,
		"stance_state": manager.stance_system.state_name(),
		"stance_recovery_frames": manager.stance_system.recovery_frames(),
		"stance_break_stun_frames": manager.stance_system.break_stun_frames(),
		"stance_protected": manager.stance_system.protected(),
		"reaction_window_active": manager.reaction_window_system.active,
		"reaction_progress": manager.reaction_window_system.progress(),
		"reaction_choice": manager.reaction_window_system.reaction_choice,
		"reaction_remaining_seconds": manager.reaction_window_system.remaining_seconds,
		"enemy_intent": manager.current_enemy_intent,
		"enemy_remaining_startup": manager.remaining_startup_frames,
		"queue": manager.get_queue_text()
	}

static func animation_debug_for(manager: Node, actor: Node, actor_name: String) -> Dictionary:
	var data := {}
	if actor != null and actor.has_method("get_animation_debug"):
		data = actor.get_animation_debug()
	else:
		data = {
			"animation_key": "unknown",
			"pose_key": "unknown",
			"action_name": "unknown",
			"phase": "unknown",
			"phase_progress": null,
			"phase_frames_remaining": null,
			"active_frame_window": "unknown",
			"hitbox_active": null,
			"current_pose_name": "unknown",
			"movement_phase": "unknown",
			"movement_direction": "unknown",
			"rig_scale": null,
			"facing": "unknown"
		}
	data["actor"] = actor_name
	if actor_name == "player":
		data["movement_phase"] = manager.movement_flow_system.movement_phase
		data["movement_direction"] = manager._movement_direction_text(manager.movement_flow_system.movement_direction)
	elif actor_name == "enemy":
		data["movement_phase"] = manager.movement_flow_system.enemy_movement_phase
		data["movement_direction"] = manager._movement_direction_text(manager._direction_to_player()) if manager.movement_flow_system.enemy_approach_active else "None"
	if manager.combat_timeline != null and manager.combat_timeline.actor.to_lower() == actor_name:
		data["action_name"] = manager.combat_timeline.action_name
		data["animation_key"] = manager.combat_timeline.animation_key
		data["phase"] = manager.combat_timeline.phase_name()
		data["phase_progress"] = manager.combat_timeline.phase_progress()
		data["phase_frames_remaining"] = manager.combat_timeline.phase_frames_remaining()
		data["active_frame_window"] = manager.combat_timeline.active_window_text()
		data["hitbox_active"] = manager.combat_timeline.hitbox_active()
	return json_safe(data)

static func reaction_export_data(manager: Node) -> Dictionary:
	return {
		"active": manager.reaction_window_system.active,
		"hit_level": manager.current_enemy_intent if manager.current_enemy_intent != "" else "None",
		"total_seconds": manager.reaction_window_system.total_seconds,
		"remaining_seconds": manager.reaction_window_system.remaining_seconds,
		"progress": manager.reaction_window_system.progress(),
		"impact_bar_progress": 1.0 - manager.reaction_window_system.progress(),
		"selected_defense": manager.reaction_window_system.resolved_defense_type() if manager.reaction_window_system.has_active_defense() else manager.reaction_window_system.reaction_choice.to_lower(),
		"guard_startup_remaining": manager.reaction_window_system.guard_startup_frames_remaining,
		"guard_active": manager.reaction_window_system.guard_active,
		"defense_input_progress": manager.reaction_window_system.defense_input_progress,
		"correct_defense_became_active_progress": manager.reaction_window_system.correct_defense_became_active_progress,
		"perfect_window_active": manager._perfect_block_window_active(),
		"resolution": manager.reaction_window_system.impact_resolution_text
	}

static func movement_export_data(manager: Node) -> Dictionary:
	return json_safe({
		"time_mode": manager._time_mode_text(),
		"current_time_scale": Engine.time_scale,
		"player_live_movement_active": manager.movement_flow_system.player_live_movement_active,
		"enemy_approach_active": manager.movement_flow_system.enemy_approach_active,
		"distance": manager._distance_between_fighters(),
		"distance_change_rate": manager.movement_flow_system.distance_change_rate,
		"enemy_approach_target_distance": manager.movement_flow_system.approach_target_distance,
		"enemy_approach_end_reason": manager.movement_flow_system.enemy_approach_end_reason,
		"defensive_reaction_retry_count": manager.defensive_reaction_retry_count,
		"defensive_reaction_fallback": manager.defensive_reaction_fallback,
		"player_movement_phase": manager.movement_flow_system.movement_phase,
		"enemy_movement_phase": manager.movement_flow_system.enemy_movement_phase,
		"player_position": manager.player.global_position,
		"enemy_position": manager.enemy.global_position
	})

static func json_safe(value):
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Dictionary:
		var output := {}
		for key in value.keys():
			output[str(key)] = json_safe(value[key])
		return output
	if value is Array:
		var output_array := []
		for item in value:
			output_array.append(json_safe(item))
		return output_array
	return value

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
