class_name RouteSystem
extends RefCounted

var manager: Node
var deck_manager: Node
var repeated_card_uses: Dictionary = {}

# TODO: Move card definitions, route tables, generated follow-ups, and repeat
# decay tuning into data assets so mods/character kits can replace them safely.
func setup(manager_ref: Node, deck_manager_ref: Node) -> void:
	manager = manager_ref
	deck_manager = deck_manager_ref

func reset_pressure_sequence() -> void:
	deck_manager.reset_combo_route()
	repeated_card_uses.clear()

func repeated_card_decay(card: Resource) -> Dictionary:
	var previous_count := int(repeated_card_uses.get(card.id, 0))
	var use_count := previous_count + 1
	repeated_card_uses[card.id] = use_count
	var penalty := 0
	var suppress_follow_up := false
	var force_end := false
	if use_count == 2:
		penalty = -3
	elif use_count == 3:
		penalty = -6
		suppress_follow_up = true
	elif use_count >= 4:
		penalty = -12
		suppress_follow_up = true
		force_end = true
	if penalty < 0:
		manager.log_message.emit("Repeated move decay applied.")
	return {
		"penalty": penalty,
		"use_count": use_count,
		"suppress_follow_up": suppress_follow_up,
		"force_end": force_end
	}

func card_has_tag(card: Resource, tag_name: String) -> bool:
	return card.tags.has(tag_name)

func has_valid_card(enemy_broken: bool) -> bool:
	return deck_manager.has_break_playable_card() if enemy_broken else deck_manager.has_valid_playable_card()
