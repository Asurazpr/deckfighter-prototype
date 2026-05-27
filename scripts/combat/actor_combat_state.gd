class_name ActorCombatState
extends RefCounted

const ActionRequestScript := preload("res://scripts/combat/action_request.gd")

var actor_id := ""
var current_action_id := "None"
var current_action_source := "none"
var current_action_request := {}
var combat_state := "NEUTRAL"
var facing := 1
var locked := false
var can_act := true
var recovery_frames_remaining := 0
var hitstun_frames_remaining := 0
var blockstun_frames_remaining := 0
var airborne := false
var animation_key := "idle"
var phase := "DONE"
var phase_progress := 0.0

func setup(_actor_id: String) -> void:
	actor_id = _actor_id

func update_from_actor(actor: Node, state_name: String, action_id := "None", action_request = null) -> void:
	combat_state = state_name
	current_action_id = action_id
	if action_request is ActionRequestScript:
		current_action_source = action_request.source_type_name()
		current_action_request = action_request.to_dict()
	elif action_request is Dictionary:
		current_action_source = String(action_request.get("source_type", "unknown"))
		current_action_request = action_request.duplicate(true)
	can_act = not locked
	if actor == null:
		return
	if actor.has_method("get_animation_debug"):
		var debug: Dictionary = actor.get_animation_debug()
		animation_key = String(debug.get("animation_key", animation_key))
		phase = String(debug.get("phase", debug.get("action_state", phase)))
		phase_progress = float(debug.get("phase_progress", debug.get("phase_progress_percent", phase_progress)))
		locked = bool(debug.get("is_action_locked", locked))
		can_act = not locked
		if debug.has("facing"):
			facing = -1 if String(debug.get("facing")) == "left" else 1
	if actor is Node2D:
		airborne = (actor as Node2D).global_position.y < 588.0

func to_debug_text() -> String:
	return "%s state=%s action=%s source=%s anim=%s phase=%s progress=%d%% locked=%s recovery=%d hitstun=%d blockstun=%d airborne=%s" % [
		actor_id,
		combat_state,
		current_action_id,
		current_action_source,
		animation_key,
		phase,
		int(round(phase_progress * 100.0)),
		str(locked),
		recovery_frames_remaining,
		hitstun_frames_remaining,
		blockstun_frames_remaining,
		str(airborne)
	]

func to_dict() -> Dictionary:
	return {
		"actor_id": actor_id,
		"current_action_id": current_action_id,
		"current_action_source": current_action_source,
		"current_action_request": current_action_request,
		"combat_state": combat_state,
		"facing": facing,
		"locked": locked,
		"can_act": can_act,
		"recovery_frames_remaining": recovery_frames_remaining,
		"hitstun_frames_remaining": hitstun_frames_remaining,
		"blockstun_frames_remaining": blockstun_frames_remaining,
		"airborne": airborne,
		"animation_key": animation_key,
		"phase": phase,
		"phase_progress": phase_progress
	}
