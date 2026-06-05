class_name TacticalModeController
extends RefCounted

const ActionRequestScript := preload("res://scripts/combat/action_request.gd")

var manager
var deck_manager
var queue_resolver

func setup(manager_ref, deck_manager_ref, queue_resolver_ref) -> void:
	manager = manager_ref
	deck_manager = deck_manager_ref
	queue_resolver = queue_resolver_ref

func action_request_from_card(card: Resource, queued_index := -1, input_frame := 0) -> ActionRequest:
	return ActionRequestScript.from_card("player", card, queued_index, input_frame)

func action_request_from_hand_index(index: int, input_frame := 0) -> ActionRequest:
	if deck_manager == null or not ("hand" in deck_manager):
		return null
	if index < 0 or index >= deck_manager.hand.size():
		return null
	return action_request_from_card(deck_manager.hand[index], index, input_frame)

func is_queue_empty() -> bool:
	return queue_resolver == null or queue_resolver.is_empty()

func queue_text() -> String:
	if queue_resolver == null:
		return "Queue: Empty"
	return queue_resolver.queue_text()
