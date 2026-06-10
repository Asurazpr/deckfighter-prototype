class_name RunState
extends RefCounted

const META_RUN_STARTED := "deckfighter_run_started"
const META_ROOM_INDEX := "deckfighter_room_index"
const META_SELECTED_ROOM_TYPE := "deckfighter_selected_room_type"
const META_SELECTED_ROOM_ID := "deckfighter_selected_room_id"
const META_SELECTED_COMBAT_MODE := "deckfighter_selected_combat_mode"
const META_PLAYER_CURRENT_HP := "deckfighter_player_current_hp"
const META_PREVIOUS_EXIT_DIRECTION := "deckfighter_previous_exit_direction"
const META_NEXT_ENTRY_SIDE := "deckfighter_next_entry_side"
const META_UNLOCKED_SKILLS := "deckfighter_unlocked_skills"
const META_MEMORY_THREADS := "deckfighter_memory_threads"
const META_TECHNIQUES := "deckfighter_techniques"
const META_REWARD_CARDS := "deckfighter_reward_cards"
const META_POWER_REWARDS := "deckfighter_power_rewards"

const ROOM_TYPE_COMBAT := "combat"
const ROOM_TYPE_ELITE := "elite"
const ROOM_TYPE_REST := "rest"
const ROOM_TYPE_MERCHANT := "merchant"
const ROOM_TYPE_BOSS := "boss"
const ACT_NUMBER := 1
const ACT_ROOM_COUNT := 12

const SIDE_LEFT := "LEFT"
const SIDE_RIGHT := "RIGHT"
const SIDE_UP := "UP"
const SIDE_DOWN := "DOWN"

const TECHNIQUE_DEFINITIONS := {
	"strike_a": {
		"id": "strike_a",
		"display_name": "Strike A",
		"tactical_description": "Add a fast strike card concept to the run pool.",
		"power_description": "Train a quick forward strike concept for direct action mode.",
		"preview_text": "Quick forward strike."
	},
	"guard_b": {
		"id": "guard_b",
		"display_name": "Guard B",
		"tactical_description": "Add a defensive guard card concept to the run pool.",
		"power_description": "Train a sturdier guard technique for pressure defense.",
		"preview_text": "Defensive guard technique."
	},
	"dash_c": {
		"id": "dash_c",
		"display_name": "Dash C",
		"tactical_description": "Add a fast movement card concept to the run pool.",
		"power_description": "Train a fast movement dash technique.",
		"preview_text": "Fast movement dash."
	},
	"focus_d": {
		"id": "focus_d",
		"display_name": "Focus D",
		"tactical_description": "Add a focus/resource control card concept to the run pool.",
		"power_description": "Train a timing and resource-control technique.",
		"preview_text": "Focus and resource control."
	}
}

static func is_run_started(tree: SceneTree) -> bool:
	return tree != null and bool(tree.get_meta(META_RUN_STARTED, false))

static func set_run_started(tree: SceneTree, selected_combat_mode: String) -> void:
	if tree == null:
		return
	tree.set_meta(META_RUN_STARTED, true)
	tree.set_meta(META_SELECTED_COMBAT_MODE, selected_combat_mode)

static func selected_combat_mode(tree: SceneTree, fallback := "TIME_TACTICAL") -> String:
	if tree == null:
		return fallback
	return String(tree.get_meta(META_SELECTED_COMBAT_MODE, fallback))

static func has_selected_combat_mode(tree: SceneTree) -> bool:
	return tree != null and tree.has_meta(META_SELECTED_COMBAT_MODE)

static func room_index(tree: SceneTree) -> int:
	if tree == null:
		return 0
	return int(tree.get_meta(META_ROOM_INDEX, 0))

static func room_number_for_index(index: int) -> int:
	return maxi(1, index + 1)

static func current_room_number(tree: SceneTree) -> int:
	return room_number_for_index(room_index(tree))

static func selected_room_type(tree: SceneTree) -> String:
	if tree == null:
		return ROOM_TYPE_COMBAT
	return String(tree.get_meta(META_SELECTED_ROOM_TYPE, ROOM_TYPE_COMBAT))

static func selected_room_id(tree: SceneTree) -> String:
	if tree == null:
		return "debug_start"
	return String(tree.get_meta(META_SELECTED_ROOM_ID, "debug_start"))

static func previous_exit_direction(tree: SceneTree) -> String:
	if tree == null:
		return SIDE_LEFT
	return String(tree.get_meta(META_PREVIOUS_EXIT_DIRECTION, SIDE_LEFT))

static func next_entry_side(tree: SceneTree) -> String:
	if tree == null:
		return SIDE_LEFT
	return String(tree.get_meta(META_NEXT_ENTRY_SIDE, SIDE_LEFT))

static func player_starts_left(tree: SceneTree) -> bool:
	return next_entry_side(tree) == SIDE_LEFT

static func exit_direction_to_next_entry_side(exit_direction: String, fallback_entry_side := SIDE_LEFT) -> String:
	match exit_direction:
		SIDE_LEFT:
			return SIDE_RIGHT
		SIDE_RIGHT:
			return SIDE_LEFT
		SIDE_UP, SIDE_DOWN:
			return fallback_entry_side
		_:
			return fallback_entry_side

static func set_next_room(tree: SceneTree, next_room_index: int, room_type: String, room_id: String, previous_exit_direction_value: String, next_entry_side_value: String) -> void:
	if tree == null:
		return
	tree.set_meta(META_ROOM_INDEX, next_room_index)
	tree.set_meta(META_SELECTED_ROOM_TYPE, room_type)
	tree.set_meta(META_SELECTED_ROOM_ID, room_id)
	tree.set_meta(META_PREVIOUS_EXIT_DIRECTION, previous_exit_direction_value)
	tree.set_meta(META_NEXT_ENTRY_SIDE, next_entry_side_value)

static func has_player_hp(tree: SceneTree) -> bool:
	return tree != null and tree.has_meta(META_PLAYER_CURRENT_HP)

static func player_current_hp(tree: SceneTree, fallback: int) -> int:
	if tree == null:
		return fallback
	return int(tree.get_meta(META_PLAYER_CURRENT_HP, fallback))

static func set_player_current_hp(tree: SceneTree, hp: int) -> void:
	if tree == null:
		return
	tree.set_meta(META_PLAYER_CURRENT_HP, hp)

static func memory_threads(tree: SceneTree) -> int:
	if tree == null:
		return 0
	return int(tree.get_meta(META_MEMORY_THREADS, 0))

static func set_memory_threads(tree: SceneTree, amount: int) -> void:
	if tree == null:
		return
	tree.set_meta(META_MEMORY_THREADS, maxi(0, amount))

static func add_memory_threads(tree: SceneTree, amount: int) -> int:
	var total: int = memory_threads(tree) + maxi(0, amount)
	set_memory_threads(tree, total)
	return total

static func spend_memory_threads(tree: SceneTree, amount: int) -> bool:
	var cost: int = maxi(0, amount)
	var current: int = memory_threads(tree)
	if current < cost:
		return false
	set_memory_threads(tree, current - cost)
	return true

static func unlocked_skills(tree: SceneTree) -> Array[String]:
	if tree == null:
		return []
	var raw_skills: Variant = tree.get_meta(META_UNLOCKED_SKILLS, [])
	var result: Array[String] = []
	if raw_skills is Array:
		for skill in raw_skills:
			result.append(String(skill))
	return result

static func has_unlocked_skill(tree: SceneTree, skill_id: String) -> bool:
	return unlocked_skills(tree).has(skill_id)

static func unlock_skill(tree: SceneTree, skill_id: String) -> void:
	if tree == null or skill_id == "":
		return
	var skills: Array[String] = unlocked_skills(tree)
	if not skills.has(skill_id):
		skills.append(skill_id)
	tree.set_meta(META_UNLOCKED_SKILLS, skills)

static func technique_ids() -> Array[String]:
	return ["strike_a", "guard_b", "dash_c", "focus_d"]

static func technique_data(technique_id: String) -> Dictionary:
	var raw_definition: Variant = TECHNIQUE_DEFINITIONS.get(technique_id, {})
	if raw_definition is Dictionary:
		return (raw_definition as Dictionary).duplicate(true)
	return {
		"id": technique_id,
		"display_name": technique_id.capitalize(),
		"tactical_description": "Prototype tactical technique.",
		"power_description": "Prototype power technique.",
		"preview_text": "Prototype technique preview."
	}

static func technique_display_name(technique_id: String) -> String:
	return String(technique_data(technique_id).get("display_name", technique_id.capitalize()))

static func technique_description(technique_id: String, control_mode: String) -> String:
	var data: Dictionary = technique_data(technique_id)
	if control_mode == "POWER_ACTION":
		return String(data.get("power_description", "Prototype power technique."))
	return String(data.get("tactical_description", "Prototype tactical technique."))

static func technique_preview_text(technique_id: String) -> String:
	return String(technique_data(technique_id).get("preview_text", "Prototype technique preview."))

static func techniques(tree: SceneTree) -> Array[String]:
	if tree == null:
		return []
	var result: Array[String] = _string_array_from_meta(tree, META_TECHNIQUES)
	if result.is_empty():
		result = _string_array_from_meta(tree, META_REWARD_CARDS)
	return result

static func add_technique(tree: SceneTree, technique_id: String) -> int:
	if tree == null or technique_id == "":
		return techniques(tree).size()
	var owned_techniques: Array[String] = techniques(tree)
	owned_techniques.append(technique_id)
	tree.set_meta(META_TECHNIQUES, owned_techniques)
	return owned_techniques.size()

static func reward_card_ids() -> Array[String]:
	return technique_ids()

static func reward_card_display_name(reward_id: String) -> String:
	return technique_display_name(reward_id)

static func reward_cards(tree: SceneTree) -> Array[String]:
	return techniques(tree)

static func add_reward_card(tree: SceneTree, reward_id: String) -> int:
	return add_technique(tree, reward_id)

static func power_reward_ids() -> Array[String]:
	return technique_ids()

static func power_reward_display_name(reward_id: String) -> String:
	return technique_display_name(reward_id)

static func power_rewards(tree: SceneTree) -> Array[String]:
	return techniques(tree)

static func add_power_reward(tree: SceneTree, reward_id: String) -> int:
	return add_technique(tree, reward_id)

static func _string_array_from_meta(tree: SceneTree, metadata_key: String) -> Array[String]:
	var raw_values: Variant = tree.get_meta(metadata_key, [])
	var result: Array[String] = []
	if raw_values is Array:
		for raw_value in raw_values:
			result.append(String(raw_value))
	return result

static func reset(tree: SceneTree) -> void:
	if tree == null:
		return
	var metadata_keys: Array[String] = [
		META_RUN_STARTED,
		META_ROOM_INDEX,
		META_SELECTED_ROOM_TYPE,
		META_SELECTED_ROOM_ID,
		META_SELECTED_COMBAT_MODE,
		META_PLAYER_CURRENT_HP,
		META_PREVIOUS_EXIT_DIRECTION,
		META_NEXT_ENTRY_SIDE,
		META_UNLOCKED_SKILLS,
		META_MEMORY_THREADS,
		META_TECHNIQUES,
		META_REWARD_CARDS,
		META_POWER_REWARDS
	]
	for key: String in metadata_keys:
		if tree.has_meta(key):
			tree.remove_meta(key)
