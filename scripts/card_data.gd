class_name CardData
extends Resource

enum Target { ENEMY, SELF }

@export var id := ""
@export var display_name := ""
@export var tag := ""
@export_multiline var description := ""
@export var damage := 0
@export var stance_damage := 0
@export var frame_cost := 1
@export var frame_gain := 0
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
	card.allowed_follow_up_card_ids = _allowed_follow_up_card_ids.duplicate()
	return card
