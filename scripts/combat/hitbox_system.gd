class_name HitboxSystem
extends RefCounted

const DEBUG_ATTACK_HITBOX_LIFETIME := 0.25

var manager: Node
var player: Node2D
var enemy: Node2D
var movement

var last_player_attack_hitbox := Rect2()
var last_enemy_attack_hitbox := Rect2()
var player_attack_hitbox_lifetime := 0.0
var enemy_attack_hitbox_lifetime := 0.0

func setup(manager_ref: Node, player_ref: Node2D, enemy_ref: Node2D, movement_ref) -> void:
	manager = manager_ref
	player = player_ref
	enemy = enemy_ref
	movement = movement_ref
	_sync_attack_area(player, Rect2(), false)
	_sync_attack_area(enemy, Rect2(), false)

func player_pushbox() -> Rect2:
	var fallback_size := Vector2(player.hurtbox_width, player.hurtbox_height)
	var fallback := Rect2(Vector2(player.global_position.x - fallback_size.x * 0.5, player.global_position.y - fallback_size.y), fallback_size)
	return _shape_rect(player, "Pushbox/CollisionShape2D", _shape_rect(player, "CollisionShape2D", fallback))

func enemy_pushbox() -> Rect2:
	var fallback_size := Vector2(enemy.hurtbox_width, enemy.hurtbox_height)
	var fallback := Rect2(Vector2(enemy.global_position.x - fallback_size.x * 0.5, enemy.global_position.y - fallback_size.y), fallback_size)
	return _shape_rect(enemy, "Pushbox/CollisionShape2D", fallback)

func player_hurtbox() -> Rect2:
	var size := Vector2(player.hurtbox_width, player.hurtbox_height)
	var fallback := Rect2(Vector2(player.global_position.x - size.x * 0.5, player.global_position.y - size.y), size)
	var rect := _shape_rect(player, "Hurtbox/CollisionShape2D", fallback)
	rect.position += _player_hurtbox_offset()
	return rect

func enemy_hurtbox() -> Rect2:
	var size := Vector2(enemy.hurtbox_width, enemy.hurtbox_height)
	var fallback := Rect2(Vector2(enemy.global_position.x - size.x * 0.5, enemy.global_position.y - size.y), size)
	return _shape_rect(enemy, "Hurtbox/CollisionShape2D", fallback)

func player_active_attack_hitbox() -> Rect2:
	return _active_attack_rect(player)

func enemy_active_attack_hitbox() -> Rect2:
	return _active_attack_rect(enemy)

func card_hitbox(card: Resource) -> Rect2:
	return card_hitbox_at(card, player.global_position)

func card_hitbox_at(card: Resource, origin: Vector2) -> Rect2:
	if card.hitbox_width <= 0.0 or card.hitbox_height <= 0.0:
		return Rect2()
	var size := Vector2(card.hitbox_width, card.hitbox_height)
	var center: Vector2 = origin + Vector2(card.hitbox_offset_x * movement.direction_to_enemy(), card.hitbox_offset_y)
	return Rect2(center - size * 0.5, size)

func enemy_attack_hitbox(attack_data: Dictionary) -> Rect2:
	var width := float(attack_data.get("hitbox_width", 0.0))
	var height := float(attack_data.get("hitbox_height", 0.0))
	if width <= 0.0 or height <= 0.0:
		return Rect2()
	var size := Vector2(width, height)
	var offset_x := float(attack_data.get("hitbox_offset_x", width * 0.5))
	var center: Vector2 = enemy.global_position + Vector2(offset_x * movement.direction_to_player(), float(attack_data.get("hitbox_offset_y", -40.0)))
	return Rect2(center - size * 0.5, size)

func punish_hitbox() -> Rect2:
	var size := Vector2(120.0, 60.0)
	var center: Vector2 = enemy.global_position + Vector2(60.0 * movement.direction_to_player(), -40.0)
	return Rect2(center - size * 0.5, size)

func card_needs_hitbox(card: Resource) -> bool:
	return card.hitbox_width > 0.0 and card.hitbox_height > 0.0

func card_hitbox_hits_enemy(card: Resource) -> bool:
	if not card_needs_hitbox(card):
		return true
	return player_attack_overlaps_enemy()

func card_would_hit_enemy_after_movement(card: Resource) -> bool:
	if not card_needs_hitbox(card):
		return true
	var predicted_position: Vector2 = player.global_position
	predicted_position.x += card.movement_delta * movement.direction_to_enemy()
	predicted_position.x = movement.clamped_player_x(predicted_position.x)
	return card_hitbox_at(card, predicted_position).intersects(enemy_hurtbox())

func set_player_attack_hitbox(hitbox: Rect2) -> void:
	last_player_attack_hitbox = hitbox
	player_attack_hitbox_lifetime = DEBUG_ATTACK_HITBOX_LIFETIME if hitbox.size != Vector2.ZERO else 0.0
	_sync_attack_area(player, hitbox, hitbox.size != Vector2.ZERO)
	_sync_manager()

func set_enemy_attack_hitbox(hitbox: Rect2) -> void:
	last_enemy_attack_hitbox = hitbox
	enemy_attack_hitbox_lifetime = DEBUG_ATTACK_HITBOX_LIFETIME if hitbox.size != Vector2.ZERO else 0.0
	_sync_attack_area(enemy, hitbox, hitbox.size != Vector2.ZERO)
	_sync_manager()

func player_attack_overlaps_enemy() -> bool:
	return last_player_attack_hitbox.size != Vector2.ZERO and last_player_attack_hitbox.intersects(enemy_hurtbox())

func enemy_attack_overlaps_player() -> bool:
	return last_enemy_attack_hitbox.size != Vector2.ZERO and last_enemy_attack_hitbox.intersects(player_hurtbox())

func clear_attack_hitboxes() -> void:
	last_player_attack_hitbox = Rect2()
	last_enemy_attack_hitbox = Rect2()
	player_attack_hitbox_lifetime = 0.0
	enemy_attack_hitbox_lifetime = 0.0
	_sync_attack_area(player, Rect2(), false)
	_sync_attack_area(enemy, Rect2(), false)
	_sync_manager()

func tick_debug_hitboxes(delta: float) -> void:
	if player_attack_hitbox_lifetime > 0.0:
		player_attack_hitbox_lifetime -= delta / Engine.time_scale
		if player_attack_hitbox_lifetime <= 0.0:
			last_player_attack_hitbox = Rect2()
			_sync_attack_area(player, Rect2(), false)
	if enemy_attack_hitbox_lifetime > 0.0:
		enemy_attack_hitbox_lifetime -= delta / Engine.time_scale
		if enemy_attack_hitbox_lifetime <= 0.0:
			last_enemy_attack_hitbox = Rect2()
			_sync_attack_area(enemy, Rect2(), false)
	_sync_manager()

func _shape_rect(actor: Node2D, shape_path: String, fallback: Rect2) -> Rect2:
	if actor == null:
		return fallback
	var shape_node := actor.get_node_or_null(shape_path) as CollisionShape2D
	if shape_node == null:
		return fallback
	var rect_shape := shape_node.shape as RectangleShape2D
	if rect_shape == null:
		return fallback
	var scale := shape_node.global_transform.get_scale()
	var size := Vector2(rect_shape.size.x * absf(scale.x), rect_shape.size.y * absf(scale.y))
	return Rect2(shape_node.global_position - size * 0.5, size)

func _sync_attack_area(actor: Node2D, hitbox: Rect2, active: bool) -> void:
	if actor == null:
		return
	var area := actor.get_node_or_null("AttackHitbox") as Area2D
	if area == null:
		return
	var shape_node := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return
	var rect_shape := shape_node.shape as RectangleShape2D
	if rect_shape == null:
		return
	area.visible = active
	shape_node.disabled = not active
	if not active:
		return
	area.global_position = hitbox.position + hitbox.size * 0.5
	shape_node.position = Vector2.ZERO
	rect_shape.size = hitbox.size

func _active_attack_rect(actor: Node2D) -> Rect2:
	if actor == null:
		return Rect2()
	var area := actor.get_node_or_null("AttackHitbox") as Area2D
	if area == null or not area.visible:
		return Rect2()
	var shape_node := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.disabled:
		return Rect2()
	return _shape_rect(actor, "AttackHitbox/CollisionShape2D", Rect2())

func _player_hurtbox_offset() -> Vector2:
	if manager != null and manager.has_method("get_player_hurtbox_offset"):
		return manager.get_player_hurtbox_offset()
	return Vector2.ZERO

func _sync_manager() -> void:
	manager.last_player_attack_hitbox = last_player_attack_hitbox
	manager.last_enemy_attack_hitbox = last_enemy_attack_hitbox
	manager.player_attack_hitbox_lifetime = player_attack_hitbox_lifetime
	manager.enemy_attack_hitbox_lifetime = enemy_attack_hitbox_lifetime
