class_name MovementFlowSystem
extends RefCounted

const BASIC_STEP_STARTUP_FRAMES := 3.0
const BASIC_STEP_TRAVEL_FRAMES := 8.0
const BASIC_STEP_RECOVERY_FRAMES := 4.0
const STEP_PHASE_IDLE := "DONE"
const STEP_PHASE_STARTUP := "STARTUP"
const STEP_PHASE_TRAVEL := "TRAVEL"
const STEP_PHASE_RECOVERY := "RECOVERY"

var manager: Node
var player: Node2D
var enemy: Node2D
var movement_system: MovementSystem
var neutral_time_scale := 0.35
var player_speed := 140.0
var enemy_speed := 70.0
var intent_range := 95.0
var intent_delay := 1.2
var approach_target_distance := 95.0

var active := false
var enemy_approach_active := false
var player_live_movement_active := false
var last_player_live_movement_active := false
var last_enemy_approach_active := false
var elapsed := 0.0
var last_distance := 0.0
var distance_change_rate := 0.0
var movement_phase := STEP_PHASE_IDLE
var movement_frames_remaining := 0.0
var movement_direction := 0.0
var movement_locked := false
var movement_pose := "idle"
var enemy_movement_phase := STEP_PHASE_IDLE
var enemy_movement_frames_remaining := 0.0
var _frame_accumulator := 0.0
var _logged_travel := false
var _enemy_movement_logged := false
var _enemy_reached_range_logged := false
var enemy_approach_end_reason := "none"

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
	player.set_free_movement_enabled(false)
	if player is CharacterBody2D:
		player.velocity.x = 0.0
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
		_reset_player_step()
		_reset_enemy_step()
	player.set_free_movement_enabled(false)

func tick(delta: float) -> Dictionary:
	if not active:
		return {"should_start_intent": false}
	elapsed += delta
	_advance_combat_time(delta)
	approach_target_distance = _current_approach_target_distance()
	var previous_distance := movement_system.distance_between_fighters()
	player_live_movement_active = Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D)
	_tick_player_step(delta)
	_tick_enemy_approach_step(delta)
	movement_system.clamp_duel_distance()
	var current_distance := movement_system.distance_between_fighters()
	distance_change_rate = (current_distance - previous_distance) / maxf(delta, 0.001)
	last_distance = current_distance
	_log_state_changes()
	var reached_intent_range := current_distance <= approach_target_distance
	if reached_intent_range and not _enemy_reached_range_logged:
		enemy_approach_end_reason = "distance %.0f <= target %.0f" % [current_distance, approach_target_distance]
		manager.log_message.emit("Enemy reached range; evaluating intent.")
		_enemy_reached_range_logged = true
	elif not reached_intent_range:
		enemy_approach_end_reason = "approaching: distance %.0f > target %.0f" % [current_distance, approach_target_distance]
		_enemy_reached_range_logged = false
	return {
		"should_start_intent": reached_intent_range,
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
	var direction := _input_direction()
	if direction == 0.0:
		return
	player.global_position.x += direction * player_speed * real_delta

func _apply_enemy_movement(real_delta: float) -> void:
	enemy_approach_active = movement_system.distance_between_fighters() > approach_target_distance
	if not enemy_approach_active:
		return
	enemy.global_position.x += movement_system.direction_to_player() * enemy_speed * real_delta

func _tick_player_step(real_delta: float) -> void:
	var held_direction := _input_direction()
	if movement_phase == STEP_PHASE_IDLE:
		if held_direction != 0.0:
			_start_player_step(held_direction)
		else:
			_show_player_idle_pose()
		return

	var frames := real_delta * 60.0
	if movement_phase == STEP_PHASE_TRAVEL:
		player.global_position.x += movement_direction * player_speed * real_delta
	movement_frames_remaining = maxf(0.0, movement_frames_remaining - frames)
	_show_player_step_pose()
	if movement_frames_remaining > 0.0:
		return

	match movement_phase:
		STEP_PHASE_STARTUP:
			movement_phase = STEP_PHASE_TRAVEL
			movement_frames_remaining = BASIC_STEP_TRAVEL_FRAMES
			_logged_travel = false
			manager.log_message.emit("Step travel.")
		STEP_PHASE_TRAVEL:
			movement_phase = STEP_PHASE_RECOVERY
			movement_frames_remaining = BASIC_STEP_RECOVERY_FRAMES
		STEP_PHASE_RECOVERY:
			manager.log_message.emit("Step recovered.")
			_reset_player_step()
			if held_direction != 0.0:
				_start_player_step(held_direction)

func _start_player_step(direction: float) -> void:
	movement_direction = direction
	movement_phase = STEP_PHASE_STARTUP
	movement_frames_remaining = BASIC_STEP_STARTUP_FRAMES
	movement_locked = true
	_logged_travel = false
	movement_pose = _movement_pose_for_direction(direction)
	manager.log_message.emit("%s started." % ("Step forward" if movement_pose == "step_forward" else "Step back"))
	_show_player_step_pose()

func _tick_enemy_approach_step(real_delta: float) -> void:
	approach_target_distance = _current_approach_target_distance()
	enemy_approach_active = movement_system.distance_between_fighters() > approach_target_distance
	if not enemy_approach_active:
		if _enemy_movement_logged:
			manager.log_message.emit("Enemy movement animation stopped.")
			manager.log_message.emit("Enemy returned to guard pose.")
			if enemy != null and enemy.has_method("clear_timeline_visual"):
				enemy.clear_timeline_visual()
			_enemy_movement_logged = false
		_reset_enemy_step()
		return
	if enemy_movement_phase == STEP_PHASE_IDLE:
		enemy_movement_phase = STEP_PHASE_TRAVEL
		enemy_movement_frames_remaining = BASIC_STEP_TRAVEL_FRAMES
		if not _enemy_movement_logged:
			manager.log_message.emit("Enemy movement animation started.")
			_enemy_movement_logged = true
	var frames := real_delta * 60.0
	if enemy_movement_phase == STEP_PHASE_TRAVEL:
		enemy.global_position.x += movement_system.direction_to_player() * enemy_speed * real_delta
		_show_actor_pose(enemy, "walk_forward", "ACTIVE", 1.0 - enemy_movement_frames_remaining / BASIC_STEP_TRAVEL_FRAMES)
	enemy_movement_frames_remaining = maxf(0.0, enemy_movement_frames_remaining - frames)
	if enemy_movement_frames_remaining <= 0.0:
		enemy_movement_frames_remaining = BASIC_STEP_TRAVEL_FRAMES

func _input_direction() -> float:
	var direction := 0.0
	if Input.is_key_pressed(KEY_A):
		direction -= 1.0
	if Input.is_key_pressed(KEY_D):
		direction += 1.0
	return clampf(direction, -1.0, 1.0)

func _movement_pose_for_direction(direction: float) -> String:
	return "step_forward" if signf(direction) == signf(movement_system.direction_to_enemy()) else "backstep"

func _show_player_step_pose() -> void:
	var phase_name := "STARTUP"
	var phase_total := BASIC_STEP_STARTUP_FRAMES
	if movement_phase == STEP_PHASE_TRAVEL:
		phase_name = "ACTIVE"
		phase_total = BASIC_STEP_TRAVEL_FRAMES
	elif movement_phase == STEP_PHASE_RECOVERY:
		phase_name = "RECOVERY"
		phase_total = BASIC_STEP_RECOVERY_FRAMES
	var progress := 1.0 - movement_frames_remaining / maxf(1.0, phase_total)
	_show_actor_pose(player, movement_pose, phase_name, progress)

func _show_player_idle_pose() -> void:
	if player != null and player.has_method("clear_timeline_visual"):
		player.clear_timeline_visual()

func _show_actor_pose(actor: Node, action_name: String, phase_name: String, progress: float) -> void:
	if actor != null and actor.has_method("show_timeline_phase"):
		actor.show_timeline_phase(action_name, phase_name, clampf(progress, 0.0, 1.0), "", false)

func _reset_player_step() -> void:
	movement_phase = STEP_PHASE_IDLE
	movement_frames_remaining = 0.0
	movement_direction = 0.0
	movement_locked = false
	movement_pose = "idle"

func _reset_enemy_step() -> void:
	enemy_movement_phase = STEP_PHASE_IDLE
	enemy_movement_frames_remaining = 0.0

func _advance_combat_time(delta: float) -> void:
	_frame_accumulator += delta * 60.0
	var whole_frames := int(floor(_frame_accumulator))
	if whole_frames <= 0:
		return
	_frame_accumulator -= float(whole_frames)
	if manager != null and manager.has_method("advance_combat_frames"):
		manager.advance_combat_frames(whole_frames, false, true)

func _log_state_changes() -> void:
	if player_live_movement_active != last_player_live_movement_active:
		if player_live_movement_active:
			manager.log_message.emit("Player live movement started.")
		last_player_live_movement_active = player_live_movement_active
	if enemy_approach_active != last_enemy_approach_active:
		if enemy_approach_active:
			manager.log_message.emit("Enemy approaching.")
		last_enemy_approach_active = enemy_approach_active

func _current_approach_target_distance() -> float:
	if manager != null and manager.has_method("get_enemy_approach_target_distance"):
		return float(manager.get_enemy_approach_target_distance())
	return intent_range
