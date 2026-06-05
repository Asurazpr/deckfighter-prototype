class_name HitboxSystem
extends RefCounted

const PHASE_DONE := "DONE"
const PHASE_STARTUP := "STARTUP"
const PHASE_ACTIVE := "ACTIVE"
const PHASE_RECOVERY := "RECOVERY"

var manager: Node
var player: Node2D
var enemy: Node2D
var movement

var last_player_attack_hitbox := Rect2()
var last_enemy_attack_hitbox := Rect2()
var player_attack_hitbox_lifetime := 0.0
var enemy_attack_hitbox_lifetime := 0.0

var player_move: MoveDefinition
var enemy_move: MoveDefinition
var player_move_phase := PHASE_DONE
var enemy_move_phase := PHASE_DONE
var _sprite_alpha_bounds_cache := {}
var _last_check := {}

func setup(manager_ref: Node, player_ref: Node2D, enemy_ref: Node2D, movement_ref) -> void:
	manager = manager_ref
	player = player_ref
	enemy = enemy_ref
	movement = movement_ref
	_sync_attack_area(player, Rect2(), false)
	_sync_attack_area(enemy, Rect2(), false)
	_sync_manager()

func begin_player_move(card: Resource) -> MoveDefinition:
	player_move = MoveDefinition.from_card(card)
	player_move_phase = PHASE_STARTUP
	_deactivate_player_attack_area()
	_trace_move_definition(player_move)
	_sync_manager()
	return player_move

func begin_enemy_move(attack_id: String, attack_data: Dictionary, effective_startup := -1) -> MoveDefinition:
	enemy_move = MoveDefinition.from_enemy_attack(attack_id, attack_data, effective_startup)
	enemy_move_phase = PHASE_STARTUP
	_deactivate_enemy_attack_area()
	_trace_move_definition(enemy_move)
	_sync_manager()
	return enemy_move

func begin_enemy_punish() -> MoveDefinition:
	enemy_move = MoveDefinition.from_punish()
	enemy_move_phase = PHASE_ACTIVE
	var rect := _move_rect_for_actor(enemy_move, enemy, _direction_to_player())
	_set_enemy_active_rect(rect)
	_trace_move_definition(enemy_move)
	return enemy_move

func enter_player_recovery() -> void:
	player_move_phase = PHASE_RECOVERY if player_move != null else PHASE_DONE
	_deactivate_player_attack_area()
	_sync_manager()

func enter_enemy_recovery() -> void:
	enemy_move_phase = PHASE_RECOVERY if enemy_move != null else PHASE_DONE
	_deactivate_enemy_attack_area()
	_sync_manager()

func finish_player_move() -> void:
	player_move = null
	player_move_phase = PHASE_DONE
	_deactivate_player_attack_area()
	_sync_manager()

func finish_enemy_move() -> void:
	enemy_move = null
	enemy_move_phase = PHASE_DONE
	_deactivate_enemy_attack_area()
	_sync_manager()

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
	var rect := _sprite_based_hurtbox(player, fallback)
	if _player_is_crouching():
		rect = _crouch_hurtbox_from(rect)
	rect.position += _player_hurtbox_offset()
	return rect

func enemy_hurtbox() -> Rect2:
	var size := Vector2(enemy.hurtbox_width, enemy.hurtbox_height)
	var fallback := Rect2(Vector2(enemy.global_position.x - size.x * 0.5, enemy.global_position.y - size.y), size)
	return _sprite_based_hurtbox(enemy, fallback)

func player_active_attack_hitbox() -> Rect2:
	return _active_attack_rect(player)

func enemy_active_attack_hitbox() -> Rect2:
	return _active_attack_rect(enemy)

func player_debug_attack_hitbox() -> Rect2:
	return _move_rect_for_actor(player_move, player, _direction_to_enemy())

func enemy_debug_attack_hitbox() -> Rect2:
	return _move_rect_for_actor(enemy_move, enemy, _direction_to_player())

func player_debug_phase() -> String:
	return player_move_phase

func enemy_debug_phase() -> String:
	return enemy_move_phase

func player_sprite_bounds() -> Rect2:
	return _sprite_visible_bounds(player)

func enemy_sprite_bounds() -> Rect2:
	return _sprite_visible_bounds(enemy)

func card_hitbox(card: Resource) -> Rect2:
	return card_hitbox_at(card, player.global_position)

func card_hitbox_at(card: Resource, origin: Vector2) -> Rect2:
	var move_def := MoveDefinition.from_card(card)
	return move_def.hitbox.rect_at(origin, _direction_to_enemy(), _actor_hitbox_definition_scale(player))

func enemy_attack_hitbox(attack_data: Dictionary) -> Rect2:
	var move_def := MoveDefinition.from_enemy_attack(String(attack_data.get("id", "")), attack_data)
	return move_def.hitbox.rect_at(enemy.global_position, _direction_to_player(), _actor_hitbox_definition_scale(enemy))

func punish_hitbox() -> Rect2:
	return MoveDefinition.from_punish().hitbox.rect_at(enemy.global_position, _direction_to_player(), _actor_hitbox_definition_scale(enemy))

func card_needs_hitbox(card: Resource) -> bool:
	return not MoveDefinition.from_card(card).hitbox.is_empty()

func card_hitbox_hits_enemy(card: Resource) -> bool:
	if not card_needs_hitbox(card):
		return true
	return player_attack_overlaps_enemy()

func card_would_hit_enemy_after_movement(card: Resource) -> bool:
	if not card_needs_hitbox(card):
		return true
	var predicted_position: Vector2 = player.global_position
	predicted_position.x += card.movement_delta * _direction_to_enemy()
	predicted_position.x = movement.clamped_player_x(predicted_position.x)
	return card_hitbox_at(card, predicted_position).intersects(enemy_hurtbox())

func activate_player_card(card: Resource) -> Dictionary:
	if player_move == null or player_move.id != String(card.id):
		begin_player_move(card)
	player_move_phase = PHASE_ACTIVE
	var rect := _move_rect_for_actor(player_move, player, _direction_to_enemy())
	_set_player_active_rect(rect)
	var defender_hurtbox := enemy_hurtbox()
	var overlaps := rect.size == Vector2.ZERO or rect.intersects(defender_hurtbox)
	var defender_state := _defender_state(enemy)
	if overlaps and _move_evaded_by_defender_state(player_move, defender_state):
		overlaps = false
	var result := _resolution("player", player_move, rect, overlaps, defender_hurtbox)
	_last_check = _build_check_trace(player, enemy, player_move, player_move_phase, rect, defender_hurtbox, overlaps, result)
	return result

func activate_enemy_attack(attack_data: Dictionary) -> Dictionary:
	var attack_id := String(attack_data.get("id", ""))
	if enemy_move == null or enemy_move.id != attack_id:
		begin_enemy_move(attack_id, attack_data)
	enemy_move_phase = PHASE_ACTIVE
	var rect := _move_rect_for_actor(enemy_move, enemy, _direction_to_player())
	_set_enemy_active_rect(rect)
	var defender_hurtbox := player_hurtbox()
	var overlaps := rect.size != Vector2.ZERO and rect.intersects(defender_hurtbox)
	var defender_state := _defender_state(player)
	if overlaps and _move_evaded_by_defender_state(enemy_move, defender_state):
		overlaps = false
	var result := _resolution("enemy", enemy_move, rect, overlaps, defender_hurtbox)
	_last_check = _build_check_trace(enemy, player, enemy_move, enemy_move_phase, rect, defender_hurtbox, overlaps, result)
	return result

func set_player_attack_hitbox(hitbox: Rect2) -> void:
	if hitbox.size == Vector2.ZERO:
		_deactivate_player_attack_area()
		_sync_manager()
		return
	player_move_phase = PHASE_ACTIVE
	_set_player_active_rect(hitbox)

func set_enemy_attack_hitbox(hitbox: Rect2) -> void:
	if hitbox.size == Vector2.ZERO:
		_deactivate_enemy_attack_area()
		_sync_manager()
		return
	enemy_move_phase = PHASE_ACTIVE
	_set_enemy_active_rect(hitbox)

func player_attack_overlaps_enemy() -> bool:
	return last_player_attack_hitbox.size != Vector2.ZERO and last_player_attack_hitbox.intersects(enemy_hurtbox())

func enemy_attack_overlaps_player() -> bool:
	return last_enemy_attack_hitbox.size != Vector2.ZERO and last_enemy_attack_hitbox.intersects(player_hurtbox())

func clear_attack_hitboxes() -> void:
	player_move = null
	enemy_move = null
	player_move_phase = PHASE_DONE
	enemy_move_phase = PHASE_DONE
	_deactivate_player_attack_area()
	_deactivate_enemy_attack_area()
	_sync_manager()

func tick_debug_hitboxes(_delta: float) -> void:
	_sync_manager()

func trace_last_check(result_label: String) -> void:
	if not _trace_enabled() or _last_check.is_empty():
		return
	_last_check["result"] = _normalized_trace_result(result_label)
	_emit_trace("HITBOX_CHECK", _last_check)
	_last_check = {}

func _normalized_trace_result(result_label: String) -> String:
	var normalized := result_label.to_lower().replace(" ", "_")
	if normalized != "whiff":
		return normalized
	var defender_state := String(_last_check.get("defender_state", ""))
	var attack_level := String(_last_check.get("attack_level", ""))
	var raw_gap_x: Variant = _last_check.get("gap_x", 0.0)
	var gap_x := float(raw_gap_x) if raw_gap_x is int or raw_gap_x is float else 0.0
	if gap_x > 0.0:
		return normalized
	if attack_level == "HIGH" and (defender_state == "crouching" or defender_state == "crouch_blocking"):
		return "crouch_evade"
	if attack_level == "LOW" and (defender_state == "jumping" or defender_state == "airborne"):
		return "jump_evade"
	return normalized

func _move_evaded_by_defender_state(move_def: MoveDefinition, defender_state: String) -> bool:
	if move_def == null:
		return false
	var attack_level := move_def.attack_level
	if attack_level == "HIGH" and (defender_state == "crouching" or defender_state == "crouch_blocking"):
		return not _move_hits_crouching(move_def)
	if attack_level == "LOW" and (defender_state == "jumping" or defender_state == "airborne"):
		return true
	return false

func _move_hits_crouching(move_def: MoveDefinition) -> bool:
	if move_def == null:
		return false
	if bool(move_def.source_data.get("hits_crouching", false)):
		return true
	for tag in move_def.tags:
		var normalized := String(tag).to_lower()
		if normalized == "hits_crouching" or normalized == "crouch_hitting":
			return true
	return false

func _move_rect_for_actor(move_def: MoveDefinition, actor: Node2D, facing_direction: float) -> Rect2:
	if move_def == null or actor == null:
		return Rect2()
	return move_def.hitbox.rect_at(actor.global_position, facing_direction, _actor_hitbox_definition_scale(actor))

func _resolution(actor_id: String, move_def: MoveDefinition, attack_rect: Rect2, overlaps: bool, defender_hurtbox: Rect2) -> Dictionary:
	return {
		"actor": actor_id,
		"move_id": move_def.id if move_def != null else "",
		"move_name": move_def.display_name if move_def != null else "",
		"phase": PHASE_ACTIVE,
		"attack_level": move_def.attack_level if move_def != null else "MID",
		"damage": move_def.damage if move_def != null else 0,
		"stance_damage": move_def.stance_damage if move_def != null else 0,
		"attack_rect": attack_rect,
		"defender_hurtbox": defender_hurtbox,
		"overlaps": overlaps,
		"result": "hit_or_block" if overlaps else "whiff"
	}

func _build_check_trace(attacker: Node2D, defender: Node2D, move_def: MoveDefinition, phase_name: String, attack_rect: Rect2, defender_hurtbox: Rect2, overlaps: bool, resolution: Dictionary) -> Dictionary:
	var attacker_name := _actor_display_name(attacker)
	var defender_name := _actor_display_name(defender)
	var facing := _direction_to_enemy() if attacker == player else _direction_to_player()
	return {
		"attacker": attacker_name,
		"attacker_type": "player" if attacker == player else "enemy",
		"move_id": move_def.id if move_def != null else "",
		"move_name": move_def.display_name if move_def != null else "",
		"attack_level": move_def.attack_level if move_def != null else "MID",
		"phase": phase_name.to_lower(),
		"facing": facing,
		"global_position": _vector_payload(attacker.global_position if attacker != null else Vector2.ZERO),
		"attacker_position": _vector_payload(attacker.global_position if attacker != null else Vector2.ZERO),
		"defender_position": _vector_payload(defender.global_position if defender != null else Vector2.ZERO),
		"node_scale": _vector_payload(_node_scale(attacker)),
		"sprite_scale": _vector_payload(_sprite_scale(attacker)),
		"hitbox_enabled": attack_rect.size != Vector2.ZERO,
		"attack_rect": _rect_payload(attack_rect),
		"defender_hurtbox_rect": _rect_payload(defender_hurtbox),
		"attack_hitbox": {
			"enabled": attack_rect.size != Vector2.ZERO,
			"rect": _rect_payload(attack_rect),
			"center": _vector_payload(_rect_center(attack_rect)),
			"source_offset": _vector_payload(move_def.hitbox.offset if move_def != null else Vector2.ZERO),
			"source_size": _vector_payload(move_def.hitbox.size if move_def != null else Vector2.ZERO)
		},
		"defender": defender_name,
		"defender_type": "player" if defender == player else "enemy",
		"defender_state": _defender_state(defender),
		"hurtbox": {
			"rect": _rect_payload(defender_hurtbox),
			"center": _vector_payload(_rect_center(defender_hurtbox))
		},
		"overlap": overlaps,
		"gap_x": _horizontal_gap(attack_rect, defender_hurtbox),
		"gap_y": _vertical_gap(attack_rect, defender_hurtbox),
		"result": String(resolution.get("result", "unknown"))
	}

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

func _set_player_active_rect(hitbox: Rect2) -> void:
	last_player_attack_hitbox = hitbox
	player_attack_hitbox_lifetime = 1.0 if hitbox.size != Vector2.ZERO else 0.0
	_sync_attack_area(player, hitbox, hitbox.size != Vector2.ZERO)
	_sync_manager()

func _set_enemy_active_rect(hitbox: Rect2) -> void:
	last_enemy_attack_hitbox = hitbox
	enemy_attack_hitbox_lifetime = 1.0 if hitbox.size != Vector2.ZERO else 0.0
	_sync_attack_area(enemy, hitbox, hitbox.size != Vector2.ZERO)
	_sync_manager()

func _deactivate_player_attack_area() -> void:
	last_player_attack_hitbox = Rect2()
	player_attack_hitbox_lifetime = 0.0
	_sync_attack_area(player, Rect2(), false)

func _deactivate_enemy_attack_area() -> void:
	last_enemy_attack_hitbox = Rect2()
	enemy_attack_hitbox_lifetime = 0.0
	_sync_attack_area(enemy, Rect2(), false)

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

func _sprite_based_hurtbox(actor: Node2D, fallback: Rect2) -> Rect2:
	var sprite_bounds := _sprite_visible_bounds(actor)
	if sprite_bounds.size == Vector2.ZERO:
		return fallback
	return _apply_hurtbox_inset(sprite_bounds)

func _apply_hurtbox_inset(rect: Rect2) -> Rect2:
	var inset_ratio := _hurtbox_inset_ratio()
	var left := rect.size.x * clampf(inset_ratio.x, 0.0, 0.45)
	var top := rect.size.y * clampf(inset_ratio.y, 0.0, 0.45)
	var right := rect.size.x * clampf(inset_ratio.z, 0.0, 0.45)
	var bottom := rect.size.y * clampf(inset_ratio.w, 0.0, 0.45)
	var position := rect.position + Vector2(left, top)
	var size := Vector2(maxf(1.0, rect.size.x - left - right), maxf(1.0, rect.size.y - top - bottom))
	return Rect2(position, size)

func _crouch_hurtbox_from(standing_rect: Rect2) -> Rect2:
	var width_scale := clampf(_manager_float("crouch_hurtbox_width_scale", 0.82), 0.2, 1.0)
	var height_scale := clampf(_manager_float("crouch_hurtbox_height_scale", 0.58), 0.2, 1.0)
	var crouch_size := Vector2(standing_rect.size.x * width_scale, standing_rect.size.y * height_scale)
	var bottom_y := standing_rect.position.y + standing_rect.size.y
	var center_x := standing_rect.position.x + standing_rect.size.x * 0.5
	return Rect2(Vector2(center_x - crouch_size.x * 0.5, bottom_y - crouch_size.y), crouch_size)

func _sprite_visible_bounds(actor: Node2D) -> Rect2:
	if actor == null:
		return Rect2()
	var sprite := actor.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null or sprite.animation == "":
		return Rect2()
	if not sprite.sprite_frames.has_animation(sprite.animation):
		return Rect2()
	var frame_count := sprite.sprite_frames.get_frame_count(sprite.animation)
	if frame_count <= 0:
		return Rect2()
	var frame_index := clampi(sprite.frame, 0, frame_count - 1)
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, frame_index)
	if texture == null:
		return Rect2()
	var local_rect := _sprite_alpha_local_rect(sprite, texture)
	if local_rect.size == Vector2.ZERO:
		return Rect2()
	return _transformed_rect(sprite.global_transform, local_rect)

func _sprite_alpha_local_rect(sprite: AnimatedSprite2D, texture: Texture2D) -> Rect2:
	var alpha_rect := _texture_alpha_bounds(texture)
	var texture_size := texture.get_size()
	var texture_origin := sprite.offset
	if sprite.centered:
		texture_origin -= texture_size * 0.5
	return Rect2(texture_origin + alpha_rect.position, alpha_rect.size)

func _texture_alpha_bounds(texture: Texture2D) -> Rect2:
	var cache_key := str(texture.get_rid())
	if _sprite_alpha_bounds_cache.has(cache_key):
		return _sprite_alpha_bounds_cache[cache_key]
	var texture_size := texture.get_size()
	var fallback := Rect2(Vector2.ZERO, texture_size)
	var image := texture.get_image()
	if image == null or image.is_empty():
		_sprite_alpha_bounds_cache[cache_key] = fallback
		return fallback
	var used_rect: Rect2i = image.get_used_rect()
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		_sprite_alpha_bounds_cache[cache_key] = fallback
		return fallback
	var alpha_bounds := Rect2(Vector2(used_rect.position), Vector2(used_rect.size))
	_sprite_alpha_bounds_cache[cache_key] = alpha_bounds
	return alpha_bounds

func _transformed_rect(transform: Transform2D, rect: Rect2) -> Rect2:
	var points := [
		transform * rect.position,
		transform * (rect.position + Vector2(rect.size.x, 0.0)),
		transform * (rect.position + rect.size),
		transform * (rect.position + Vector2(0.0, rect.size.y))
	]
	var min_point: Vector2 = points[0]
	var max_point: Vector2 = points[0]
	for point in points:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)
	return Rect2(min_point, max_point - min_point)

func _actor_hitbox_definition_scale(actor: Node2D) -> Vector2:
	if actor == null:
		return Vector2.ONE
	if actor.has_method("get_hitbox_definition_scale"):
		return actor.get_hitbox_definition_scale()
	var scale := actor.global_transform.get_scale()
	return Vector2(absf(scale.x), absf(scale.y))

func _trace_move_definition(move_def: MoveDefinition) -> void:
	if not _trace_enabled() or move_def == null:
		return
	_emit_trace("MOVE_DEF", {
		"id": move_def.id,
		"name": move_def.display_name,
		"startup": move_def.startup_frames,
		"active": move_def.active_frames,
		"recovery": move_def.recovery_frames,
		"attack_level": move_def.attack_level,
		"damage": move_def.damage,
		"stance_damage": move_def.stance_damage,
		"knockback": move_def.knockback,
		"hitbox_offset": _vector_payload(move_def.hitbox.offset),
		"hitbox_size": _vector_payload(move_def.hitbox.size)
	})

func _trace_enabled() -> bool:
	return manager != null and bool(manager.get("enable_hitbox_trace_log"))

func _emit_trace(prefix: String, payload: Dictionary) -> void:
	if manager == null:
		return
	var json := JSON.stringify(payload)
	if manager.has_method("_record_combat_event"):
		manager._record_combat_event(prefix, "%s %s" % [prefix, json], payload)
	if manager.has_signal("log_message"):
		manager.log_message.emit("%s %s" % [prefix, json])

func _actor_display_name(actor: Node2D) -> String:
	if actor == null:
		return "None"
	if actor == player:
		return "Renka"
	if actor == enemy:
		return "Kai" if actor.get_script() != null and String(actor.get_script().resource_path).find("kai") != -1 else "Enemy"
	return actor.name

func _defender_state(defender: Node2D) -> String:
	if defender == player:
		return _player_defender_state()
	var actor_state: Object = _actor_state_for(defender)
	if _actor_state_int(actor_state, "hitstun_frames_remaining") > 0:
		return "hitstun"
	if _actor_state_int(actor_state, "blockstun_frames_remaining") > 0:
		return "blockstun"
	if _actor_state_bool(actor_state, "airborne"):
		return "airborne"
	if defender != null and defender.has_method("get_animation_debug"):
		var enemy_debug: Dictionary = defender.get_animation_debug()
		var phase := String(enemy_debug.get("phase", "")).to_lower()
		var action_name := String(enemy_debug.get("action_name", "")).to_lower()
		var animation_key := String(enemy_debug.get("animation_key", "")).to_lower()
		if phase.find("hitstun") != -1:
			return "hitstun"
		if action_name.find("hitstun") != -1 or animation_key.find("hitstun") != -1:
			return "hitstun"
		if phase.find("blockstun") != -1 or action_name.find("blockstun") != -1:
			return "blockstun"
		if phase.find("block") != -1 or action_name.find("block") != -1:
			return "blocking"
	if defender != null and defender.has_method("get_stance_state_name"):
		var stance_state := String(defender.get_stance_state_name())
		if stance_state == "BROKEN_HITSTUN":
			return "hitstun"
		if stance_state == "BROKEN_BLOCKSTUN":
			return "blockstun"
	return "standing"

func _player_defender_state() -> String:
	var actor_state: Object = _actor_state_for(player)
	if _actor_state_int(actor_state, "hitstun_frames_remaining") > 0:
		return "hitstun"
	if _actor_state_int(actor_state, "blockstun_frames_remaining") > 0:
		return "blockstun"
	var reaction_system: Object = _reaction_system()
	if _reaction_bool(reaction_system, "jump_started") and not _reaction_bool(reaction_system, "jump_active"):
		return "jumping"
	if _reaction_bool(reaction_system, "jump_active") or _actor_state_bool(actor_state, "airborne") or _node_airborne(player):
		return "airborne"
	if _reaction_bool(reaction_system, "guard_active"):
		var guard_type := _reaction_string(reaction_system, "selected_defense_type")
		if guard_type == "":
			guard_type = _reaction_string(reaction_system, "current_guard_input")
		return "crouch_blocking" if guard_type == "crouch_block" else "blocking"
	if _player_is_crouching():
		return "crouching"
	if player != null and player.has_method("get_animation_debug"):
		var debug: Dictionary = player.get_animation_debug()
		var logic_state := String(debug.get("logic_state", debug.get("action_state", ""))).to_lower()
		var action_name := String(debug.get("action_name", "")).to_lower()
		if logic_state.find("hitstun") != -1:
			return "hitstun"
		if logic_state.find("blockstun") != -1:
			return "blockstun"
		if logic_state.find("block") != -1:
			return "crouch_blocking" if action_name.find("crouch") != -1 or action_name.find("low") != -1 else "blocking"
	return "standing"

func _actor_state_for(actor: Node2D) -> Object:
	if manager == null:
		return null
	if actor == player:
		return manager.get("player_actor_state") as Object
	if actor == enemy:
		return manager.get("enemy_actor_state") as Object
	return null

func _actor_state_int(actor_state: Object, property_name: String) -> int:
	if actor_state == null:
		return 0
	var value: Variant = actor_state.get(property_name)
	if value is int or value is float:
		return int(value)
	return 0

func _actor_state_bool(actor_state: Object, property_name: String) -> bool:
	if actor_state == null:
		return false
	var value: Variant = actor_state.get(property_name)
	if value is bool:
		return bool(value)
	return false

func _reaction_system() -> Object:
	if manager == null:
		return null
	return manager.get("reaction_window_system") as Object

func _reaction_bool(reaction_system: Object, property_name: String) -> bool:
	if reaction_system == null:
		return false
	var value: Variant = reaction_system.get(property_name)
	if value is bool:
		return bool(value)
	return false

func _reaction_string(reaction_system: Object, property_name: String) -> String:
	if reaction_system == null:
		return ""
	return String(reaction_system.get(property_name))

func _node_airborne(actor: Node2D) -> bool:
	if actor == null:
		return false
	if actor is CharacterBody2D:
		return not (actor as CharacterBody2D).is_on_floor()
	return false

func _node_scale(actor: Node2D) -> Vector2:
	if actor == null:
		return Vector2.ONE
	var scale := actor.global_transform.get_scale()
	return Vector2(absf(scale.x), absf(scale.y))

func _sprite_scale(actor: Node2D) -> Vector2:
	if actor == null:
		return Vector2.ONE
	var sprite := actor.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null:
		return Vector2.ONE
	var scale := sprite.global_transform.get_scale()
	return Vector2(scale.x, scale.y)

func _rect_payload(rect: Rect2) -> Dictionary:
	return {
		"x": _round2(rect.position.x),
		"y": _round2(rect.position.y),
		"w": _round2(rect.size.x),
		"h": _round2(rect.size.y)
	}

func _vector_payload(value: Vector2) -> Dictionary:
	return {
		"x": _round2(value.x),
		"y": _round2(value.y)
	}

func _rect_center(rect: Rect2) -> Vector2:
	return rect.position + rect.size * 0.5

func _horizontal_gap(a: Rect2, b: Rect2) -> float:
	if a.size == Vector2.ZERO or b.size == Vector2.ZERO:
		return 0.0
	var a_right := a.position.x + a.size.x
	var b_right := b.position.x + b.size.x
	if a_right < b.position.x:
		return _round2(b.position.x - a_right)
	if b_right < a.position.x:
		return _round2(a.position.x - b_right)
	return 0.0

func _vertical_gap(a: Rect2, b: Rect2) -> float:
	if a.size == Vector2.ZERO or b.size == Vector2.ZERO:
		return 0.0
	var a_bottom := a.position.y + a.size.y
	var b_bottom := b.position.y + b.size.y
	if a_bottom < b.position.y:
		return _round2(b.position.y - a_bottom)
	if b_bottom < a.position.y:
		return _round2(a.position.y - b_bottom)
	return 0.0

func _round2(value: float) -> float:
	return snappedf(value, 0.01)

func _hurtbox_inset_ratio() -> Vector4:
	if manager != null:
		var configured: Variant = manager.get("sprite_hurtbox_inset_ratio")
		if configured is Vector4:
			return configured
	return Vector4(0.05, 0.02, 0.05, 0.0)

func _manager_float(property_name: String, fallback: float) -> float:
	if manager == null:
		return fallback
	var configured: Variant = manager.get(property_name)
	if configured is float or configured is int:
		return float(configured)
	return fallback

func _player_is_crouching() -> bool:
	return manager != null and manager.has_method("is_player_crouching") and manager.is_player_crouching()

func _player_hurtbox_offset() -> Vector2:
	if manager != null and manager.has_method("get_player_hurtbox_offset"):
		return manager.get_player_hurtbox_offset()
	return Vector2.ZERO

func _direction_to_enemy() -> float:
	return movement.direction_to_enemy() if movement != null else 1.0

func _direction_to_player() -> float:
	return movement.direction_to_player() if movement != null else -1.0

func _sync_manager() -> void:
	if manager == null:
		return
	manager.last_player_attack_hitbox = last_player_attack_hitbox
	manager.last_enemy_attack_hitbox = last_enemy_attack_hitbox
	manager.player_attack_hitbox_lifetime = player_attack_hitbox_lifetime
	manager.enemy_attack_hitbox_lifetime = enemy_attack_hitbox_lifetime
