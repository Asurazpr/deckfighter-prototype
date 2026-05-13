class_name MovementFlowSystem
extends RefCounted

var manager: Node
var player: Node2D
var enemy: Node2D
var movement_system: MovementSystem
var neutral_time_scale := 0.35
var player_speed := 140.0
var enemy_speed := 70.0
var intent_range := 95.0
var intent_delay := 1.2

var active := false
var enemy_approach_active := false
var player_live_movement_active := false
var last_player_live_movement_active := false
var last_enemy_approach_active := false
var elapsed := 0.0
var last_distance := 0.0
var distance_change_rate := 0.0

func setup(
	manager_ref: Node,
	player_ref: Node2D,
	enemy_ref: Node2D,
	movement_system_ref: MovementSystem,
	time_scale: float,
	player_move_speed: float,
	enemy_move_speed: float,
	enemy_intent_range: float,
	intent_delay_seconds: float
) -> void:
	manager = manager_ref
	player = player_ref
	enemy = enemy_ref
	movement_system = movement_system_ref
	neutral_time_scale = time_scale
	player_speed = player_move_speed
	enemy_speed = enemy_move_speed
	intent_range = enemy_intent_range
	intent_delay = intent_delay_seconds

func enter(message := "") -> void:
	var was_active := active
	active = true
	elapsed = elapsed if was_active else 0.0
	last_distance = movement_system.distance_between_fighters()
	player.set_free_movement_enabled(true)
	Engine.time_scale = neutral_time_scale
	if message != "" and not was_active:
		manager.log_message.emit(message)

func exit() -> void:
	if active:
		active = false
		player_live_movement_active = false
		enemy_approach_active = false
		last_player_live_movement_active = false
		last_enemy_approach_active = false
	player.set_free_movement_enabled(false)

func tick(delta: float) -> Dictionary:
	if not active:
		return {"should_start_intent": false}
	elapsed += delta
	var previous_distance := movement_system.distance_between_fighters()
	player_live_movement_active = Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D)
	_apply_player_movement(delta)
	_apply_enemy_movement(delta)
	movement_system.clamp_duel_distance()
	var current_distance := movement_system.distance_between_fighters()
	distance_change_rate = (current_distance - previous_distance) / maxf(delta, 0.001)
	last_distance = current_distance
	_log_state_changes()
	return {
		"should_start_intent": current_distance <= intent_range and elapsed >= intent_delay,
		"distance": current_distance
	}

func movement_mode_text(reaction_active: bool, queue_resolving: bool, frame_advantage: int) -> String:
	if reaction_active:
		return "Reaction Locked"
	if queue_resolving:
		return "Committed Queue"
	if active:
		return "Live Slow Neutral"
	if frame_advantage > 0:
		return "Frame-Costed Pressure"
	return "Locked"

func time_mode_text(reaction_active: bool, can_play_cards_now: bool) -> String:
	if reaction_active:
		return "Reaction Slow"
	if active:
		return "Slow Neutral"
	if can_play_cards_now:
		return "Player Choice Slow"
	return "Normal"

func _apply_player_movement(real_delta: float) -> void:
	var direction := 0.0
	if Input.is_key_pressed(KEY_A):
		direction -= 1.0
	if Input.is_key_pressed(KEY_D):
		direction += 1.0
	if direction == 0.0:
		return
	player.global_position.x += direction * player_speed * real_delta

func _apply_enemy_movement(real_delta: float) -> void:
	enemy_approach_active = movement_system.distance_between_fighters() > intent_range
	if not enemy_approach_active:
		return
	enemy.global_position.x += movement_system.direction_to_player() * enemy_speed * real_delta

func _log_state_changes() -> void:
	if player_live_movement_active != last_player_live_movement_active:
		if player_live_movement_active:
			manager.log_message.emit("Player live movement started.")
		last_player_live_movement_active = player_live_movement_active
	if enemy_approach_active != last_enemy_approach_active:
		if enemy_approach_active:
			manager.log_message.emit("Enemy approaching.")
		last_enemy_approach_active = enemy_approach_active
