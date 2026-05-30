class_name MoveDefinition
extends RefCounted

const DEFAULT_ATTACK_LEVEL := "MID"

var id := ""
var display_name := ""
var startup_frames := 0
var active_frames := 0
var recovery_frames := 0
var hit_frame := 0
var active_start_frame := 0
var active_end_frame := 0
var attack_level := DEFAULT_ATTACK_LEVEL
var damage := 0
var stance_damage := 0
var knockback := 0.0
var animation_key := ""
var hitbox := HitboxDefinition.new()
var tags: Array[String] = []
var source_kind := ""
var source_data := {}

static func from_card(card: Resource) -> MoveDefinition:
	var definition := MoveDefinition.new()
	definition.source_kind = "card"
	if card == null:
		return definition
	definition.id = String(card.id)
	definition.display_name = String(card.display_name)
	definition.startup_frames = maxi(0, int(card.startup_frame))
	definition.hit_frame = maxi(0, int(card.hit_frame))
	definition.active_start_frame = maxi(0, int(card.active_start_frame))
	definition.active_end_frame = maxi(definition.active_start_frame, int(card.active_end_frame))
	definition.active_frames = definition.active_end_frame - definition.active_start_frame + 1
	definition.recovery_frames = maxi(0, int(card.frame_cost))
	definition.attack_level = _normalize_attack_level(String(card.attack_level))
	definition.damage = int(card.damage)
	definition.stance_damage = int(card.stance_damage)
	definition.knockback = float(card.knockback)
	definition.animation_key = definition.id
	definition.hitbox = HitboxDefinition.from_values(
		Vector2(float(card.hitbox_width), float(card.hitbox_height)),
		Vector2(float(card.hitbox_offset_x), float(card.hitbox_offset_y))
	)
	definition.tags = card.tags.duplicate()
	definition.source_data = {
		"id": definition.id,
		"display_name": definition.display_name,
		"source": definition.source_kind
	}
	return definition

static func from_enemy_attack(attack_id: String, attack_data: Dictionary, effective_startup := -1) -> MoveDefinition:
	var definition := MoveDefinition.new()
	definition.source_kind = "enemy_attack"
	definition.id = String(attack_data.get("id", attack_id))
	definition.display_name = String(attack_data.get("name", definition.id))
	var startup: int = int(attack_data.get("startup_frame", attack_data.get("startup", 0)))
	if effective_startup >= 0:
		startup = effective_startup
	definition.startup_frames = maxi(0, startup)
	definition.active_frames = maxi(1, int(attack_data.get("active", 3)))
	definition.recovery_frames = maxi(0, int(attack_data.get("recovery", 0)))
	definition.hit_frame = definition.startup_frames
	definition.active_start_frame = definition.startup_frames
	definition.active_end_frame = definition.active_start_frame + definition.active_frames - 1
	var raw_attack_level: String = String(attack_data.get("attack_level", attack_data.get("hit_level", attack_data.get("type", DEFAULT_ATTACK_LEVEL))))
	definition.attack_level = _normalize_attack_level(String(raw_attack_level))
	definition.damage = int(attack_data.get("damage", 0))
	definition.stance_damage = int(attack_data.get("stance_damage", 0))
	definition.knockback = float(attack_data.get("knockback", 0.0))
	definition.animation_key = String(attack_data.get("animation_key", definition.id))
	var width: float = float(attack_data.get("hitbox_width", 0.0))
	var height: float = float(attack_data.get("hitbox_height", 0.0))
	definition.hitbox = HitboxDefinition.from_values(
		Vector2(width, height),
		Vector2(float(attack_data.get("hitbox_offset_x", width * 0.5)), float(attack_data.get("hitbox_offset_y", -40.0)))
	)
	definition.tags = _string_array(attack_data.get("tags", []))
	definition.source_data = attack_data.duplicate(true)
	return definition

static func from_punish() -> MoveDefinition:
	var definition := MoveDefinition.new()
	definition.source_kind = "punish"
	definition.id = "punish"
	definition.display_name = "Punish"
	definition.startup_frames = 0
	definition.active_frames = 1
	definition.recovery_frames = 0
	definition.hit_frame = 0
	definition.active_start_frame = 0
	definition.active_end_frame = 0
	definition.attack_level = "MID"
	definition.hitbox = HitboxDefinition.from_values(Vector2(120.0, 60.0), Vector2(60.0, -40.0))
	return definition

func active_window_text() -> String:
	if hitbox.is_empty():
		return "None"
	return "%d-%d" % [active_start_frame, active_end_frame]

func timeline_data() -> Dictionary:
	return {
		"startup_frames": startup_frames,
		"active_frames": active_frames,
		"recovery_frames": recovery_frames,
		"impact_frame": hit_frame,
		"hitbox_on_frame": active_start_frame,
		"hitbox_off_frame": active_end_frame + 1,
		"animation_key": animation_key
	}

static func _normalize_attack_level(level: String) -> String:
	var normalized := level.to_upper()
	if normalized == "HIGH" or normalized == "MID" or normalized == "LOW" or normalized == "OVERHEAD":
		return normalized
	return DEFAULT_ATTACK_LEVEL

static func _string_array(values: Variant) -> Array[String]:
	var output: Array[String] = []
	if values is Array:
		for value in values:
			output.append(String(value))
	return output
