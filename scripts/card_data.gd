class_name CardData
extends Resource

enum Target { ENEMY, SELF }

@export var id := ""
@export var display_name := ""
@export var tag := ""
@export var tags: Array[String] = []
@export_multiline var description := ""
@export var damage := 0
@export var stance_damage := 0
@export var frame_cost := 1
@export var frame_gain := 0
@export var startup_frame := 0
@export var range := 0.0
@export var movement_delta := 0.0
@export var whiff_frame_penalty := 0
@export var hitbox_width := 0.0
@export var hitbox_height := 0.0
@export var hitbox_offset_x := 0.0
@export var hitbox_offset_y := 0.0
@export var target := Target.ENEMY
@export var allowed_follow_up_card_ids: Array[String] = []

static func make(
	_id: String,
	_name: String,
	_tag: String,
	_description: String,
	_damage: int,
	_stance_damage: int,
	_frame_cost: int,
	_frame_gain: int,
	_startup_frame: int,
	_range: float,
	_movement_delta: float,
	_whiff_frame_penalty: int,
	_hitbox_width: float,
	_hitbox_height: float,
	_hitbox_offset_x: float,
	_hitbox_offset_y: float,
	_tags: Array[String] = [],
	_allowed_follow_up_card_ids: Array[String] = []
) -> Resource:
	var card := new()
	card.id = _id
	card.display_name = _name
	card.tag = _tag
	card.description = _description
	card.damage = _damage
	card.stance_damage = _stance_damage
	card.frame_cost = _frame_cost
	card.frame_gain = _frame_gain
	card.startup_frame = _startup_frame
	card.range = _range
	card.movement_delta = _movement_delta
	card.whiff_frame_penalty = _whiff_frame_penalty
	card.hitbox_width = _hitbox_width
	card.hitbox_height = _hitbox_height
	card.hitbox_offset_x = _hitbox_offset_x
	card.hitbox_offset_y = _hitbox_offset_y
	card.tags = _tags.duplicate()
	card.allowed_follow_up_card_ids = _allowed_follow_up_card_ids.duplicate()
	return card
