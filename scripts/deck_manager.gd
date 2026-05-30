class_name DeckManager
extends Node

signal hand_changed(hand: Array)
signal deck_changed(draw_pile_count: int, discard_count: int)
signal follow_up_drawn(card_name: String)
signal follow_up_skipped(message: String)

const HAND_SIZE := 4
const CardDataScript := preload("res://scripts/card_data.gd")

var draw_pile: Array = []
var discard_pile: Array = []
var hand: Array = []
var card_library: Dictionary = {}
var combo_route_active := false
var current_follow_up_card_ids: Array[String] = []
var next_card_instance_id := 1

func _ready() -> void:
	_build_starter_deck()

func start_combat() -> void:
	next_card_instance_id = 1
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

func play_card_unrestricted(index: int) -> Resource:
	if index < 0 or index >= hand.size():
		return null

	var card: Resource = hand[index]
	hand.remove_at(index)
	discard_pile.append(card)

	_set_combo_route(card.allowed_follow_up_card_ids)
	_draw_one_allowed_follow_up(card.allowed_follow_up_card_ids)

	draw_to_hand()
	_emit_all()
	return card

func play_card_with_route_result(index: int, continue_route: bool, start_new_route: bool) -> Resource:
	if index < 0 or index >= hand.size():
		return null

	var card: Resource = hand[index]
	hand.remove_at(index)
	discard_pile.append(card)

	if continue_route or start_new_route:
		_set_combo_route(card.allowed_follow_up_card_ids)
		_draw_one_allowed_follow_up(card.allowed_follow_up_card_ids)
	else:
		_reset_combo_route_state()

	draw_to_hand()
	_emit_all()
	return card

func play_queued_card_snapshot(snapshot: Dictionary, continue_route: bool, start_new_route: bool) -> Resource:
	var hand_index := _find_card_index_by_instance_id(int(snapshot.get("instance_id", 0)))
	if hand_index != -1:
		hand.remove_at(hand_index)

	var card: Resource = _card_from_snapshot(snapshot)
	discard_pile.append(card)

	if continue_route or start_new_route:
		_set_combo_route(card.allowed_follow_up_card_ids)
		_draw_one_allowed_follow_up(card.allowed_follow_up_card_ids)
	else:
		_reset_combo_route_state()

	draw_to_hand()
	_emit_all()
	return card

func discard_queued_card_snapshot(snapshot: Dictionary) -> Resource:
	var hand_index := _find_card_index_by_instance_id(int(snapshot.get("instance_id", 0)))
	if hand_index != -1:
		hand.remove_at(hand_index)

	var card: Resource = _card_from_snapshot(snapshot)
	discard_pile.append(card)
	_reset_combo_route_state()
	draw_to_hand()
	_emit_all()
	return card

func discard_card_unrestricted(index: int) -> Resource:
	if index < 0 or index >= hand.size():
		return null

	var card: Resource = hand[index]
	hand.remove_at(index)
	discard_pile.append(card)
	_reset_combo_route_state()
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
		return _is_break_launcher(card) if allow_break_launcher else true

	if current_follow_up_card_ids.has(card.id):
		return true
	return allow_break_launcher and _is_break_launcher(card) and not has_route_valid_playable_card()

func is_card_route_valid(index: int, allow_break_launcher := false) -> bool:
	return is_card_playable(index, allow_break_launcher)

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
		hand.append(_with_instance_id(card.duplicate()))

func _draw_card() -> Resource:
	if draw_pile.is_empty():
		if discard_pile.is_empty():
			return null
		draw_pile = discard_pile.duplicate()
		discard_pile.clear()
		draw_pile.shuffle()

	return _with_instance_id(draw_pile.pop_back())

func _build_starter_deck() -> void:
	card_library = {
		"light_punch": CardDataScript.make("light_punch", "Light Punch", "LP", "Fast Renka melee starter.", 6, 8, 1, 1, 5, 70.0, 0.0, -2, 36.0, 22.0, 31.0, -72.0, ["starter", "interrupt"], ["heavy_punch", "uppercut", "light_kick"], 5, 5, 8, "MID"),
		"heavy_punch": CardDataScript.make("heavy_punch", "Heavy Punch", "HP", "Committed Renka punch with strong damage.", 16, 12, 6, 0, 12, 85.0, 0.0, -5, 48.0, 32.0, 38.0, -78.0, ["attack"], ["uppercut"], 12, 12, 16, "MID"),
		"uppercut": CardDataScript.make("uppercut", "Uppercut", "Up", "Vertical launcher-style strike.", 9, 12, 1, 2, 10, 70.0, 0.0, -4, 38.0, 68.0, 24.0, -88.0, ["launcher", "interrupt"], ["heavy_kick"], 10, 10, 14, "MID"),
		"light_kick": CardDataScript.make("light_kick", "Light Kick", "LK", "Fast low-line kick for melee pressure.", 8, 8, 1, 1, 8, 82.0, 0.0, -3, 48.0, 24.0, 39.0, -38.0, ["attack", "interrupt"], ["heavy_kick", "light_punch"], 8, 8, 11, "LOW"),
		"heavy_kick": CardDataScript.make("heavy_kick", "Heavy Kick", "HK", "Committed Renka kick finisher.", 18, 14, 6, 0, 13, 92.0, 0.0, -5, 54.0, 28.0, 44.0, -86.0, ["attack", "finisher"], [], 13, 13, 18, "HIGH")
	}

	var ids := [
		"light_punch", "heavy_punch", "uppercut", "light_kick", "heavy_kick"
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
		if card_id == "reset_step" and _hand_has_card_id("reset_step"):
			follow_up_skipped.emit("Reset Step already in hand; skipped duplicate.")
			continue
		var card := _remove_card_from_pile(draw_pile, card_id)
		if card == null:
			card = _remove_card_from_pile(discard_pile, card_id)
		if card == null:
			var template := card_library.get(card_id) as Resource
			if template != null:
				card = template.duplicate()
		if card != null:
			hand.append(_with_instance_id(card))
			follow_up_drawn.emit(card.display_name)
			return card
	return null

func _hand_has_card_id(card_id: String) -> bool:
	for card in hand:
		if card.id == card_id:
			return true
	return false

func _is_break_launcher(card: Resource) -> bool:
	return card != null and (card.id == "uppercut" or card.id == "launcher" or card.tags.has("launcher"))

func _find_card_index_by_instance_id(instance_id: int) -> int:
	for i in range(hand.size()):
		var card: Resource = hand[i]
		if card.instance_id == instance_id:
			return i
	return -1

func _with_instance_id(card: Resource) -> Resource:
	card.instance_id = next_card_instance_id
	next_card_instance_id += 1
	return card

func _card_from_snapshot(snapshot: Dictionary) -> Resource:
	var card := CardDataScript.new()
	card.id = String(snapshot.get("id", ""))
	card.instance_id = int(snapshot.get("instance_id", 0))
	card.display_name = String(snapshot.get("display_name", card.id))
	card.tag = String(snapshot.get("tag", ""))
	card.description = String(snapshot.get("description", ""))
	card.damage = int(snapshot.get("damage", 0))
	card.stance_damage = int(snapshot.get("stance_damage", 0))
	card.frame_cost = int(snapshot.get("frame_cost", 0))
	card.frame_gain = int(snapshot.get("frame_gain", 0))
	card.startup_frame = int(snapshot.get("startup_frame", 0))
	card.range = float(snapshot.get("range", 0.0))
	card.movement_delta = float(snapshot.get("movement_delta", 0.0))
	card.whiff_frame_penalty = int(snapshot.get("whiff_frame_penalty", 0))
	card.hit_frame = int(snapshot.get("hit_frame", card.startup_frame))
	card.active_start_frame = int(snapshot.get("active_start_frame", card.hit_frame))
	card.active_end_frame = int(snapshot.get("active_end_frame", card.active_start_frame + 3))
	card.hitbox_width = float(snapshot.get("hitbox_width", 0.0))
	card.hitbox_height = float(snapshot.get("hitbox_height", 0.0))
	card.hitbox_offset_x = float(snapshot.get("hitbox_offset_x", 0.0))
	card.hitbox_offset_y = float(snapshot.get("hitbox_offset_y", 0.0))
	card.attack_level = String(snapshot.get("attack_level", "MID"))
	card.knockback = float(snapshot.get("knockback", 0.0))
	card.tags = (snapshot.get("tags", []) as Array).duplicate()
	card.allowed_follow_up_card_ids = (snapshot.get("allowed_follow_up_card_ids", []) as Array).duplicate()
	return card

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
