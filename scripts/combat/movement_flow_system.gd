class_name MovementFlowSystem
extends RefCounted

const BASIC_STEP_STARTUP_FRAMES := 3.0
const BASIC_STEP_TRAVEL_FRAMES := 8.0
const BASIC_STEP_RECOVERY_FRAMES := 4.0
const BASIC_JUMP_STARTUP_FRAMES := 4.0
const BASIC_JUMP_TRAVEL_FRAMES := 42.0
const BASIC_JUMP_RECOVERY_FRAMES := 6.0
const BASIC_JUMP_HEIGHT := 220.0
const BASIC_JUMP_HORIZONTAL_SPEED := 560.0
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
var jump_phase := STEP_PHASE_IDLE
var jump_frames_remaining := 0.0
var jump_direction := 0.0
var jump_ground_y := 0.0
var jump_elapsed_frames := 0.0
var _frame_accumulator := 0.0
var _logged_travel := false
var _logged_jump_travel := false
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
	Engine.time_scale = 1.0 if _power_action_mode() else neutral_time_scale
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
		_reset_player_jump()
		_reset_enemy_step()
		_clear_player_locomotion_visual()
	player.set_free_movement_enabled(false)

func tick(delta: float) -> Dictionary:
	if not active:
		return {"should_start_intent": false}
	elapsed += delta
	_advance_combat_time(delta)
	approach_target_distance = _current_approach_target_distance()
	var previous_distance := movement_system.distance_between_fighters()
	player_live_movement_active = _input_direction() != 0.0
	if _player_jump_active():
		player_live_movement_active = true
		_tick_player_jump(delta)
	else:
		_tick_player_step(delta)
	_tick_enemy_approach_step(delta)
	if _player_jump_active():
		movement_system.clamp_duel_max_distance()
	else:
		movement_system.clamp_duel_distance()
	var current_distance := movement_system.distance_between_fighters()
	distance_change_rate = (current_distance - previous_distance) / maxf(delta, 0.001)
	last_distance = current_distance
	_log_state_changes()
	var reached_intent_range := current_distance <= approach_target_distance and not _player_jump_active()
	if reached_intent_range and not _enemy_reached_range_logged:
		enemy_approach_end_reason = "distance %.0f <= target %.0f" % [current_distance, approach_target_distance]
		manager.log_message.emit("Enemy reached range; evaluating intent.")
		_enemy_reached_range_logged = true
	elif _player_jump_active():
		enemy_approach_end_reason = "waiting: player airborne"
		_enemy_reached_range_logged = false
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

func request_player_jump() -> void:
	if not active or _player_jump_active() or _player_is_crouching():
		return
	jump_direction = _input_direction()
	jump_phase = STEP_PHASE_STARTUP
	jump_frames_remaining = BASIC_JUMP_STARTUP_FRAMES
	jump_ground_y = player.global_position.y
	jump_elapsed_frames = 0.0
	_logged_jump_travel = false
	var action_name := _jump_action_name()
	manager.log_message.emit("%s started." % action_name.capitalize().replace("_", " "))
	_show_player_jump_pose()

func _apply_enemy_movement(real_delta: float) -> void:
	enemy_approach_active = movement_system.distance_between_fighters() > approach_target_distance
	if not enemy_approach_active:
		return
	enemy.global_position.x += movement_system.direction_to_player() * enemy_speed * real_delta

func _tick_player_step(real_delta: float) -> void:
	if _player_jump_active():
		return
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

func _tick_player_jump(real_delta: float) -> void:
	var frames := real_delta * 60.0
	jump_elapsed_frames += frames
	if jump_phase == STEP_PHASE_TRAVEL:
		player.global_position.x += jump_direction * BASIC_JUMP_HORIZONTAL_SPEED * real_delta
	jump_frames_remaining = maxf(0.0, jump_frames_remaining - frames)
	_apply_jump_vertical_position()
	_show_player_jump_pose()
	if jump_frames_remaining > 0.0:
		return

	match jump_phase:
		STEP_PHASE_STARTUP:
			jump_phase = STEP_PHASE_TRAVEL
			jump_frames_remaining = BASIC_JUMP_TRAVEL_FRAMES
			_logged_jump_travel = false
			manager.log_message.emit("Jump travel.")
		STEP_PHASE_TRAVEL:
			jump_phase = STEP_PHASE_RECOVERY
			jump_frames_remaining = BASIC_JUMP_RECOVERY_FRAMES
		STEP_PHASE_RECOVERY:
			manager.log_message.emit("Jump landed.")
			_reset_player_jump()

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
	if player != null and player.has_method("is_crouching") and player.is_crouching():
		return 0.0
	var direction := 0.0
	if Input.is_key_pressed(KEY_A):
		direction -= 1.0
	if Input.is_key_pressed(KEY_D):
		direction += 1.0
	return clampf(direction, -1.0, 1.0)

func _movement_pose_for_direction(direction: float) -> String:
	return "step_forward" if signf(direction) == signf(movement_system.direction_to_enemy()) else "backstep"

func _show_player_step_pose() -> void:
	if _player_action_visual_locked():
		return
	var phase_name := "STARTUP"
	var phase_total := BASIC_STEP_STARTUP_FRAMES
	if movement_phase == STEP_PHASE_TRAVEL:
		phase_name = "ACTIVE"
		phase_total = BASIC_STEP_TRAVEL_FRAMES
	elif movement_phase == STEP_PHASE_RECOVERY:
		phase_name = "RECOVERY"
		phase_total = BASIC_STEP_RECOVERY_FRAMES
	var progress := 1.0 - movement_frames_remaining / maxf(1.0, phase_total)
	if player != null and player.has_method("show_live_locomotion"):
		player.show_live_locomotion(movement_direction, movement_pose == "step_forward", phase_name, progress)
	else:
		_show_actor_pose(player, movement_pose, phase_name, progress)

func _show_player_jump_pose() -> void:
	if _player_action_visual_locked():
		return
	var phase_name := "STARTUP"
	var phase_total := BASIC_JUMP_STARTUP_FRAMES
	if jump_phase == STEP_PHASE_TRAVEL:
		phase_name = "ACTIVE"
		phase_total = BASIC_JUMP_TRAVEL_FRAMES
	elif jump_phase == STEP_PHASE_RECOVERY:
		phase_name = "RECOVERY"
		phase_total = BASIC_JUMP_RECOVERY_FRAMES
	var progress := 1.0 - jump_frames_remaining / maxf(1.0, phase_total)
	_show_actor_pose(player, _jump_action_name(), phase_name, progress)

func _show_player_idle_pose() -> void:
	if _player_jump_active():
		return
	if _player_action_visual_locked():
		return
	if player != null and player.has_method("clear_live_locomotion_visual"):
		player.clear_live_locomotion_visual()
		return
	if player != null and player.has_method("clear_timeline_visual"):
		player.clear_timeline_visual()

func _show_actor_pose(actor: Node, action_name: String, phase_name: String, progress: float) -> void:
	if actor != null and actor.has_method("show_timeline_phase"):
		actor.show_timeline_phase(action_name, phase_name, clampf(progress, 0.0, 1.0), "", false)

func _player_action_visual_locked() -> bool:
	return manager != null and manager.has_method("player_action_visual_locked") and manager.player_action_visual_locked()

func _power_action_mode() -> bool:
	return manager != null and manager.has_method("is_power_action_mode") and manager.is_power_action_mode()

func _reset_player_step() -> void:
	movement_phase = STEP_PHASE_IDLE
	movement_frames_remaining = 0.0
	movement_direction = 0.0
	movement_locked = false
	movement_pose = "idle"

func _reset_player_jump() -> void:
	if jump_ground_y != 0.0:
		player.global_position.y = jump_ground_y
	jump_phase = STEP_PHASE_IDLE
	jump_frames_remaining = 0.0
	jump_direction = 0.0
	jump_ground_y = 0.0
	jump_elapsed_frames = 0.0
	_logged_jump_travel = false

func _player_jump_active() -> bool:
	return jump_phase != STEP_PHASE_IDLE

func player_jump_active() -> bool:
	return _player_jump_active()

func _jump_action_name() -> String:
	if jump_direction == 0.0:
		return "neutral_jump"
	if signf(jump_direction) == signf(movement_system.direction_to_enemy()):
		return "jump_forward"
	return "jump_back"

func _apply_jump_vertical_position() -> void:
	var total_frames := BASIC_JUMP_STARTUP_FRAMES + BASIC_JUMP_TRAVEL_FRAMES + BASIC_JUMP_RECOVERY_FRAMES
	var jump_progress := clampf(jump_elapsed_frames / total_frames, 0.0, 1.0)
	player.global_position.y = jump_ground_y - sin(jump_progress * PI) * BASIC_JUMP_HEIGHT

func _player_is_crouching() -> bool:
	return player != null and player.has_method("is_crouching") and player.is_crouching()

func _reset_enemy_step() -> void:
	enemy_movement_phase = STEP_PHASE_IDLE
	enemy_movement_frames_remaining = 0.0

func _clear_player_locomotion_visual() -> void:
	if player != null and player.has_method("clear_live_locomotion_visual"):
		player.clear_live_locomotion_visual()

func _advance_combat_time(delta: float) -> void:
	if _power_action_mode():
		return
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
