class_name CombatCore
extends RefCounted

const ActionRequestScript := preload("res://scripts/combat/action_request.gd")

const GAMEPLAY_FPS := 30.0

var state_machine
var hitbox_system
var stance_damage_resolver
var last_accepted_action_request
var last_rejected_action_request
var last_rejection_reason := ""
var actor_block_states := {}

func setup(state_machine_ref, hitbox_system_ref = null, stance_damage_resolver_ref = null) -> void:
	state_machine = state_machine_ref
	hitbox_system = hitbox_system_ref
	stance_damage_resolver = stance_damage_resolver_ref
	actor_block_states = {
		"player": _new_block_state(),
		"enemy": _new_block_state()
	}

func submit_action_request(action_request, frame_advantage := 0, actor_action_ready := true) -> bool:
	last_rejection_reason = ""
	if not (action_request is ActionRequestScript):
		last_rejected_action_request = action_request
		last_rejection_reason = "invalid_action_request"
		return false
	if action_request.actor_id == "" or action_request.action_id == "":
		last_rejected_action_request = action_request
		last_rejection_reason = "missing_actor_or_action"
		return false
	if state_machine != null and not state_machine.can_accept_action_request(action_request, frame_advantage, actor_action_ready):
		last_rejected_action_request = action_request
		last_rejection_reason = "state_machine:%s" % state_machine.state_name()
		return false
	last_accepted_action_request = action_request
	last_rejected_action_request = null
	return true

func can_submit_action_request(action_request, frame_advantage := 0, actor_action_ready := true) -> bool:
	if not (action_request is ActionRequestScript):
		return false
	if action_request.actor_id == "" or action_request.action_id == "":
		return false
	if state_machine == null:
		return actor_action_ready
	return state_machine.can_accept_action_request(action_request, frame_advantage, actor_action_ready)

func begin_block(actor_id: String, defense_type: String, startup_frames: int) -> void:
	var block_state := _block_state_for(actor_id)
	block_state["held"] = true
	block_state["defense_type"] = defense_type
	block_state["startup_frames"] = maxi(0, startup_frames)
	block_state["startup_remaining"] = maxi(0, startup_frames)
	block_state["active"] = startup_frames <= 0
	block_state["startup_complete_logged"] = startup_frames <= 0
	actor_block_states[actor_id] = block_state

func release_block(actor_id: String) -> void:
	var block_state := _block_state_for(actor_id)
	block_state["held"] = false
	block_state["active"] = false
	block_state["defense_type"] = ""
	block_state["startup_frames"] = 0
	block_state["startup_remaining"] = 0
	block_state["startup_complete_logged"] = false
	actor_block_states[actor_id] = block_state

func clear_block(actor_id: String) -> void:
	release_block(actor_id)

func tick_block(actor_id: String, frames: int) -> bool:
	var block_state := _block_state_for(actor_id)
	if not bool(block_state.get("held", false)):
		return false
	if bool(block_state.get("active", false)):
		return false
	var remaining := int(block_state.get("startup_remaining", 0))
	if remaining <= 0:
		block_state["active"] = true
		actor_block_states[actor_id] = block_state
		return true
	remaining = maxi(0, remaining - maxi(0, frames))
	block_state["startup_remaining"] = remaining
	if remaining <= 0:
		block_state["active"] = true
		actor_block_states[actor_id] = block_state
		return true
	actor_block_states[actor_id] = block_state
	return false

func is_block_active(actor_id: String) -> bool:
	var block_state := _block_state_for(actor_id)
	return bool(block_state.get("held", false)) and bool(block_state.get("active", false))

func is_block_held(actor_id: String) -> bool:
	return bool(_block_state_for(actor_id).get("held", false))

func block_defense_type(actor_id: String) -> String:
	if not is_block_active(actor_id):
		return ""
	return String(_block_state_for(actor_id).get("defense_type", ""))

func block_startup_remaining(actor_id: String) -> int:
	return int(_block_state_for(actor_id).get("startup_remaining", 0))

func block_progress(actor_id: String) -> float:
	var block_state := _block_state_for(actor_id)
	var startup := int(block_state.get("startup_frames", 0))
	if startup <= 0:
		return 1.0
	var remaining := int(block_state.get("startup_remaining", 0))
	return clampf(1.0 - (float(remaining) / float(startup)), 0.0, 1.0)

func seconds_to_frames(seconds: float) -> int:
	return maxi(0, int(round(seconds * GAMEPLAY_FPS)))

func delta_to_frames(delta: float, accumulator: float) -> Dictionary:
	var next_accumulator := accumulator + (delta * GAMEPLAY_FPS)
	var frames := int(floor(next_accumulator))
	next_accumulator -= float(frames)
	return {
		"frames": frames,
		"accumulator": next_accumulator
	}

func _block_state_for(actor_id: String) -> Dictionary:
	if not actor_block_states.has(actor_id):
		actor_block_states[actor_id] = _new_block_state()
	return actor_block_states[actor_id]

func _new_block_state() -> Dictionary:
	return {
		"held": false,
		"active": false,
		"defense_type": "",
		"startup_frames": 0,
		"startup_remaining": 0,
		"startup_complete_logged": false
	}
