class_name HitboxDefinition
extends RefCounted

var size := Vector2.ZERO
var offset := Vector2.ZERO

static func from_values(hitbox_size: Vector2, hitbox_offset: Vector2) -> HitboxDefinition:
	var definition := HitboxDefinition.new()
	definition.size = hitbox_size
	definition.offset = hitbox_offset
	return definition

func is_empty() -> bool:
	return size.x <= 0.0 or size.y <= 0.0

func rect_at(origin: Vector2, facing_direction: float, definition_scale := Vector2.ONE) -> Rect2:
	if is_empty():
		return Rect2()
	var facing := -1.0 if facing_direction < 0.0 else 1.0
	var scaled_size := Vector2(size.x * absf(definition_scale.x), size.y * absf(definition_scale.y))
	var scaled_offset := Vector2(offset.x * absf(definition_scale.x), offset.y * absf(definition_scale.y))
	var center := origin + Vector2(scaled_offset.x * facing, scaled_offset.y)
	return Rect2(center - scaled_size * 0.5, scaled_size)
