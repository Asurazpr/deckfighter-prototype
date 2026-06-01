class_name MovementSystem
extends RefCounted

var manager: Node
var player: Node2D
var enemy: Node2D
var max_duel_distance := 260.0
var min_duel_distance := 55.0
var arena_left_x := 0.0
var arena_right_x := 1600.0
var arena_wall_margin := 90.0

func setup(
	manager_ref: Node,
	player_ref: Node2D,
	enemy_ref: Node2D,
	max_distance: float,
	min_distance: float,
	left_bound := 0.0,
	right_bound := 1600.0,
	wall_margin := 90.0
) -> void:
	manager = manager_ref
	player = player_ref
	enemy = enemy_ref
	max_duel_distance = max_distance
	min_duel_distance = min_distance
	set_arena_bounds(left_bound, right_bound, wall_margin)

func set_arena_bounds(left_bound: float, right_bound: float, wall_margin: float) -> void:
	arena_left_x = left_bound
	arena_right_x = right_bound
	arena_wall_margin = maxf(0.0, wall_margin)

func distance_between_fighters() -> float:
	return absf(player.global_position.x - enemy.global_position.x)

func direction_to_enemy() -> float:
	var direction := signf(enemy.global_position.x - player.global_position.x)
	return 1.0 if direction == 0.0 else direction

func direction_to_player() -> float:
	var direction := signf(player.global_position.x - enemy.global_position.x)
	return -1.0 if direction == 0.0 else direction

func clamp_duel_distance() -> void:
	var direction := direction_to_enemy()
	var distance := distance_between_fighters()
	if distance > max_duel_distance:
		player.global_position.x = enemy.global_position.x - max_duel_distance * direction
	elif distance < min_duel_distance:
		player.global_position.x = enemy.global_position.x - min_duel_distance * direction
	clamp_arena_bounds()
	update_facing()

func clamp_duel_max_distance() -> void:
	var direction := direction_to_enemy()
	var distance := distance_between_fighters()
	if distance > max_duel_distance:
		player.global_position.x = enemy.global_position.x - max_duel_distance * direction
	clamp_arena_bounds()
	update_facing()

func clamped_player_x(player_x: float) -> float:
	var direction := signf(enemy.global_position.x - player_x)
	if direction == 0.0:
		direction = 1.0
	var distance := absf(player_x - enemy.global_position.x)
	if distance > max_duel_distance:
		return clampf(enemy.global_position.x - max_duel_distance * direction, _left_wall_x(), _right_wall_x())
	if distance < min_duel_distance:
		return clampf(enemy.global_position.x - min_duel_distance * direction, _left_wall_x(), _right_wall_x())
	return clampf(player_x, _left_wall_x(), _right_wall_x())

func clamp_arena_bounds() -> void:
	if player != null:
		player.global_position.x = clampf(player.global_position.x, _left_wall_x(), _right_wall_x())
	if enemy != null:
		enemy.global_position.x = clampf(enemy.global_position.x, _left_wall_x(), _right_wall_x())

func update_facing() -> void:
	if player != null and player.has_method("set_facing_direction"):
		player.set_facing_direction(direction_to_enemy())
	if enemy != null and enemy.has_method("set_facing_direction"):
		enemy.set_facing_direction(direction_to_player())

func _left_wall_x() -> float:
	return arena_left_x + arena_wall_margin

func _right_wall_x() -> float:
	return arena_right_x - arena_wall_margin

func action_startup(action: String) -> int:
	match action:
		"block":
			return 4
		"crouch_block":
			return 4
		"jump", "jump_forward", "jump_back", "neutral_jump":
			return 4
		"backstep":
			return 5
		"step_back", "step_forward":
			return 2
		"wait":
			return 1
		_:
			return 0

func apply_intent_action_movement(action: String) -> void:
	match action:
		"step_back":
			move_player_away_from_enemy(35.0)
		"step_forward":
			move_player_toward_enemy(35.0)
		"backstep":
			move_player_away_from_enemy(80.0)
		"jump":
			apply_jump_in_movement()
		"jump_forward":
			player.global_position.y -= 45.0
			move_player_toward_enemy(55.0)
			manager.log_message.emit("Player jumped forward.")
		"jump_back":
			player.global_position.y -= 45.0
			move_player_away_from_enemy(55.0)
			manager.log_message.emit("Player jumped back.")
		"neutral_jump":
			player.global_position.y -= 45.0
			manager.log_message.emit("Player neutral jumped.")

func apply_jump_in_movement() -> void:
	player.global_position.y -= 45.0
	if Input.is_key_pressed(KEY_D):
		move_player_toward_enemy(55.0)
		manager.log_message.emit("Player jumped forward.")
	elif Input.is_key_pressed(KEY_A):
		move_player_away_from_enemy(55.0)
		manager.log_message.emit("Player jumped back.")
	else:
		manager.log_message.emit("Player neutral jumped.")

func move_player_by_card(card: Resource) -> void:
	if card.movement_delta == 0.0:
		return
	player.global_position.x += card.movement_delta * direction_to_enemy()
	clamp_arena_bounds()
	update_facing()

func move_player_toward_enemy(amount: float) -> void:
	player.global_position.x += amount * direction_to_enemy()
	clamp_arena_bounds()
	update_facing()

func move_player_away_from_enemy(amount: float) -> void:
	player.global_position.x -= amount * direction_to_enemy()
	clamp_arena_bounds()
	update_facing()

func apply_card_spacing(card: Resource) -> void:
	match card.id:
		"reset_step":
			pass
		"ground_smash":
			enemy.global_position.x += 180.0 * direction_to_enemy()
	clamp_arena_bounds()
	update_facing()
