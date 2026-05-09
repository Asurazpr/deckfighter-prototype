class_name DeckManager
extends Node

signal hand_changed(hand: Array)
signal deck_changed(draw_pile_count: int, discard_count: int)

const HAND_SIZE := 4
const CardDataScript := preload("res://scripts/card_data.gd")

var draw_pile: Array = []
var discard_pile: Array = []
var hand: Array = []
var card_library: Dictionary = {}
var combo_route_active := false
var current_follow_up_card_ids: Array[String] = []

func _ready() -> void:
	_build_starter_deck()

func start_combat() -> void:
	draw_pile.shuffle()
	discard_pile.clear()
	hand.clear()
	_reset_combo_route_state()
	draw_to_hand()
	_emit_all()

func play_card(index: int, allow_break_launcher := false) -> Resource:
	if index < 0 or index >= hand.size():
		return null
	if not is_card_playable(index, allow_break_launcher):
		return null

	var card: Resource = hand[index]
	hand.remove_at(index)
	discard_pile.append(card)

	_set_combo_route(card.allowed_follow_up_card_ids)
	_draw_one_allowed_follow_up(card.allowed_follow_up_card_ids)

	draw_to_hand()
	_emit_all()
	return card

func reset_combo_route() -> void:
	_reset_combo_route_state()
	hand_changed.emit(hand)

func is_card_playable(index: int, allow_break_launcher := false) -> bool:
	if index < 0 or index >= hand.size():
		return false
	var card: Resource = hand[index]
	if not combo_route_active:
		return card.id == "launcher" if allow_break_launcher else true

	if current_follow_up_card_ids.has(card.id):
		return true
	return allow_break_launcher and card.id == "launcher" and not has_route_valid_playable_card()

func has_valid_playable_card() -> bool:
	for i in range(hand.size()):
		if is_card_playable(i):
			return true
	return false

func has_break_playable_card() -> bool:
	for i in range(hand.size()):
		if is_card_playable(i, true):
			return true
	return false

func has_route_valid_playable_card() -> bool:
	for i in range(hand.size()):
		if i < 0 or i >= hand.size():
			continue
		if not combo_route_active:
			return true
		var card: Resource = hand[i]
		if current_follow_up_card_ids.has(card.id):
			return true
	return false

func get_follow_up_tags(card: Resource) -> String:
	if card == null or card.allowed_follow_up_card_ids.is_empty():
		return "None"

	var tags: Array[String] = []
	for card_id in card.allowed_follow_up_card_ids:
		tags.append(_tag_for_card_id(card_id))
	return " / ".join(tags)

func draw_to_hand() -> void:
	while hand.size() < HAND_SIZE:
		var card: Resource = _draw_card()
		if card == null:
			break
		hand.append(card)

func draw_specific_card(card_id: String) -> void:
	var card := card_library.get(card_id) as Resource
	if card != null and hand.size() < HAND_SIZE:
		hand.append(card.duplicate())

func _draw_card() -> Resource:
	if draw_pile.is_empty():
		if discard_pile.is_empty():
			return null
		draw_pile = discard_pile.duplicate()
		discard_pile.clear()
		draw_pile.shuffle()

	return draw_pile.pop_back()

func _build_starter_deck() -> void:
	card_library = {
		"jab": CardDataScript.make("jab", "Jab", "Jab", "Fast starter that branches into pressure.", 6, 8, 1, 1, 5, 70.0, 0.0, -2, ["starter", "interrupt"], ["heavy_slash", "step_slash", "guard_break"]),
		"heavy_slash": CardDataScript.make("heavy_slash", "Heavy Slash", "Heavy", "Heavy finisher with real damage.", 16, 12, 6, 0, 12, 85.0, 0.0, -5, ["attack"]),
		"step_slash": CardDataScript.make("step_slash", "Step Slash", "Step", "Forward slash that keeps the route alive.", 10, 10, 1, 1, 8, 85.0, 60.0, -3, ["starter", "movement", "interrupt"], ["launcher", "jab"]),
		"guard_break": CardDataScript.make("guard_break", "Guard Break", "Break", "Heavy stance pressure into launcher routes.", 7, 26, 2, 1, 13, 75.0, 0.0, -4, ["pressure"], ["launcher", "heavy_slash"]),
		"launcher": CardDataScript.make("launcher", "Launcher", "Launch", "Pops the enemy into an air follow.", 9, 12, 1, 2, 10, 70.0, 0.0, -4, ["launcher"], ["air_follow"]),
		"air_follow": CardDataScript.make("air_follow", "Air Follow", "Air", "Airborne continuation.", 8, 8, 1, 1, 8, 90.0, 0.0, -3, ["air"], ["ground_smash", "gunshot"]),
		"ground_smash": CardDataScript.make("ground_smash", "Ground Smash", "Smash", "Big knockdown with huge pushback, but very unsafe up close.", 26, 34, 8, 0, 14, 90.0, 0.0, -6, ["finisher"], ["reset_step"]),
		"gunshot": CardDataScript.make("gunshot", "Gunshot", "Shot", "Quick ranged juggle extension.", 6, 6, 1, 1, 7, 220.0, 0.0, -1, ["ranged", "interrupt"], ["air_follow", "reset_step"]),
		"reset_step": CardDataScript.make("reset_step", "Reset Step", "Reset", "Creates distance and safely exits pressure.", 0, 0, 1, 0, 0, 0.0, -100.0, 0, ["movement", "finisher"])
	}

	var ids := [
		"jab", "jab", "heavy_slash", "step_slash", "guard_break",
		"launcher", "air_follow", "ground_smash", "gunshot", "reset_step"
	]

	draw_pile.clear()
	for id in ids:
		draw_pile.append((card_library[id] as Resource).duplicate())

func _emit_all() -> void:
	hand_changed.emit(hand)
	deck_changed.emit(draw_pile.size(), discard_pile.size())

func _set_combo_route(follow_up_card_ids: Array[String]) -> void:
	combo_route_active = true
	current_follow_up_card_ids = follow_up_card_ids.duplicate()

func _reset_combo_route_state() -> void:
	combo_route_active = false
	current_follow_up_card_ids.clear()

func _draw_one_allowed_follow_up(follow_up_card_ids: Array[String]) -> Resource:
	if follow_up_card_ids.is_empty() or hand.size() >= HAND_SIZE:
		return null

	var ids := follow_up_card_ids.duplicate()
	ids.shuffle()
	for card_id in ids:
		var card := _remove_card_from_pile(draw_pile, card_id)
		if card == null:
			card = _remove_card_from_pile(discard_pile, card_id)
		if card == null:
			var template := card_library.get(card_id) as Resource
			if template != null:
				card = template.duplicate()
		if card != null:
			hand.append(card)
			return card
	return null

func _remove_card_from_pile(pile: Array, card_id: String) -> Resource:
	for i in range(pile.size()):
		var card: Resource = pile[i]
		if card.id == card_id:
			pile.remove_at(i)
			return card
	return null

func _tag_for_card_id(card_id: String) -> String:
	var card := card_library.get(card_id) as Resource
	if card == null:
		return card_id.capitalize()
	return card.tag if card.tag != "" else card.display_name
