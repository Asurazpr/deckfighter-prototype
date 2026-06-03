class_name ActionRequest
extends RefCounted

enum SourceType { CARD, DIRECT_INPUT, AI, SCRIPTED, DEBUG }

var actor_id := ""
var action_id := ""
var source_type := SourceType.CARD
var input_frame := 0
var priority := 0
var card_instance_id := 0
var queued_index := -1
var payload := {}

static func from_card(actor_id: String, card: Resource, queued_index := -1, input_frame := 0):
	var request := new()
	request.actor_id = actor_id
	request.action_id = String(card.id) if card != null else ""
	request.source_type = SourceType.CARD
	request.input_frame = input_frame
	request.card_instance_id = int(card.instance_id) if card != null and "instance_id" in card else 0
	request.queued_index = queued_index
	request.payload = {"display_name": card.display_name if card != null else ""}
	return request

static func from_direct_input(actor_id: String, action_id: String, input_name := "", input_frame := 0, priority := 0, payload := {}):
	var request := new()
	request.actor_id = actor_id
	request.action_id = action_id
	request.source_type = SourceType.DIRECT_INPUT
	request.input_frame = input_frame
	request.priority = priority
	request.payload = payload.duplicate(true) if payload is Dictionary else {}
	request.payload["input_name"] = input_name
	return request

static func from_dictionary(data: Dictionary):
	var request := new()
	request.actor_id = String(data.get("actor_id", ""))
	request.action_id = String(data.get("action_id", data.get("id", "")))
	request.source_type = int(data.get("source_type", SourceType.CARD))
	request.input_frame = int(data.get("input_frame", 0))
	request.priority = int(data.get("priority", 0))
	request.card_instance_id = int(data.get("card_instance_id", data.get("instance_id", 0)))
	request.queued_index = int(data.get("queued_index", -1))
	request.payload = data.duplicate(true)
	return request

func source_type_name() -> String:
	match source_type:
		SourceType.DIRECT_INPUT:
			return "direct_input"
		SourceType.AI:
			return "ai"
		SourceType.SCRIPTED:
			return "scripted"
		SourceType.DEBUG:
			return "debug"
		_:
			return "card"

func to_dict() -> Dictionary:
	return {
		"actor_id": actor_id,
		"action_id": action_id,
		"source_type": source_type_name(),
		"input_frame": input_frame,
		"priority": priority,
		"card_instance_id": card_instance_id,
		"queued_index": queued_index,
		"payload": payload
	}
