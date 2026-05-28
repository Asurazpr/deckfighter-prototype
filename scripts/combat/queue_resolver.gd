class_name QueueResolver
extends RefCounted

var manager: Node
var deck_manager: Node
var queue: Array[Dictionary] = []
var max_queue_size := 2
var resolving := false
var interrupted_by_trade := false

func setup(manager_ref: Node, deck_manager_ref: Node, max_size: int) -> void:
	manager = manager_ref
	deck_manager = deck_manager_ref
	max_queue_size = max_size

func clear() -> void:
	queue.clear()

func is_empty() -> bool:
	return queue.is_empty()

func size() -> int:
	return queue.size()

func pop_front() -> Dictionary:
	return queue.pop_front()

func pop_back() -> Dictionary:
	return queue.pop_back()

func append(action: Dictionary) -> bool:
	if action.is_empty():
		return false
	if queue.size() >= max_queue_size:
		manager.log_message.emit("Action queue full.")
		return false
	if action.get("type", "") == "CARD":
		for queued_action in queue:
			if queued_action.get("type", "") == "CARD" and int(queued_action.get("instance_id", 0)) == int(action.get("instance_id", -1)):
				manager.log_message.emit("Card already queued: %s #%d." % [action.get("display_name", "Card"), int(action.get("instance_id", 0))])
				return false
	queue.append(action)
	return true

func is_card_instance_queued(card: Resource) -> bool:
	for action in queue:
		if action.get("type", "") == "CARD" and int(action.get("instance_id", 0)) == card.instance_id:
			return true
	return false

func card_snapshot(index: int, allow_break_launcher: bool) -> Dictionary:
	if index < 0 or index >= deck_manager.hand.size():
		return {}
	var card: Resource = deck_manager.hand[index]
	var route_valid: bool = deck_manager.is_card_route_valid(index, allow_break_launcher)
	var starts_new_route: bool = not route_valid and card.tags.has("starter")
	return {
		"type": "CARD",
		"queued_index": index,
		"instance_id": card.instance_id,
		"card_instance_id": card.instance_id,
		"original_id": card.id,
		"original_display_name": card.display_name,
		"id": card.id,
		"display_name": card.display_name,
		"tag": card.tag,
		"description": card.description,
		"damage": card.damage,
		"stance_damage": card.stance_damage,
		"frame_cost": card.frame_cost,
		"frame_gain": card.frame_gain,
		"startup_frame": card.startup_frame,
		"range": card.range,
		"movement_delta": card.movement_delta,
		"whiff_frame_penalty": card.whiff_frame_penalty,
		"hit_frame": card.hit_frame,
		"active_start_frame": card.active_start_frame,
		"active_end_frame": card.active_end_frame,
		"hitbox_width": card.hitbox_width,
		"hitbox_height": card.hitbox_height,
		"hitbox_offset_x": card.hitbox_offset_x,
		"hitbox_offset_y": card.hitbox_offset_y,
		"tags": card.tags.duplicate(),
		"allowed_follow_up_card_ids": card.allowed_follow_up_card_ids.duplicate(),
		"route_valid_at_queue": route_valid,
		"starts_new_route_at_queue": starts_new_route
	}

func snapshot_debug_text(snapshot: Dictionary) -> String:
	return "%s(%s #%d) start %df dmg %d st %d hit +%d whiff %d route %s tags %s" % [
		snapshot.get("display_name", "Card"),
		snapshot.get("id", ""),
		int(snapshot.get("card_instance_id", snapshot.get("instance_id", 0))),
		int(snapshot.get("startup_frame", 0)),
		int(snapshot.get("damage", 0)),
		int(snapshot.get("stance_damage", 0)),
		int(snapshot.get("frame_gain", 0)),
		int(snapshot.get("whiff_frame_penalty", 0)),
		", ".join(snapshot.get("allowed_follow_up_card_ids", []) as Array),
		", ".join(snapshot.get("tags", []) as Array)
	]

func warning_if_snapshot_changed(snapshot: Dictionary) -> bool:
	return snapshot.get("id", "") != snapshot.get("original_id", "") or snapshot.get("display_name", "") != snapshot.get("original_display_name", "")

func queue_text() -> String:
	if queue.is_empty():
		return "Queue: Empty"
	var names: Array[String] = []
	for action in queue:
		names.append(queued_action_display_name(action))
	return "Queue: %s" % " -> ".join(names)

func queued_action_display_name(action: Dictionary) -> String:
	if action.get("type", "") == "CARD":
		return String(action.get("display_name", "Card"))
	match String(action.get("type", "")):
		"STEP_FORWARD":
			return "Step Forward"
		"STEP_BACK":
			return "Step Back"
		"JUMP_FORWARD":
			return "Jump Forward"
		"JUMP_BACK":
			return "Jump Back"
		"NEUTRAL_JUMP":
			return "Neutral Jump"
		"BACKSTEP":
			return "Backstep"
		"BLOCK":
			return "Block"
		"CROUCH_BLOCK":
			return "Crouch Block"
		_:
			return String(action.get("type", "")).capitalize()
