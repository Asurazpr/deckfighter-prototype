class_name ReactionWindowSystem
extends RefCounted

var manager: Node
var player: Node
var active := false
var resolving := false
var total_seconds := 0.0
var remaining_seconds := 0.0
var selected_defense_type := ""
var defense_input_progress := -1.0
var current_guard_input := ""
var guard_start_elapsed_frame := -1
var guard_startup_frames_remaining := 0.0
var guard_active := false
var correct_defense_became_active_progress := -1.0
var impact_resolution_text := "None"
var perfect_block_reaction_progress := 0.85
var guard_startup_frames := 4
var jump_startup_frames := 4
var reaction_choice := "NONE"
var jump_started := false
var jump_active := false
var jump_start_elapsed_frame := -1
var jump_startup_frames_remaining := 0.0
var jump_input_progress := -1.0

func setup(manager_ref: Node, player_ref: Node, perfect_window_start: float, guard_startup: int) -> void:
	manager = manager_ref
	player = player_ref
	perfect_block_reaction_progress = perfect_window_start
	guard_startup_frames = guard_startup

func startup_frames_to_reaction_seconds(startup_frames: int) -> float:
	return clampf(0.45 + float(startup_frames) * 0.28, 1.0, 5.0)

func start(intent: String, startup_frames: int) -> void:
	active = true
	resolving = false
	total_seconds = startup_frames_to_reaction_seconds(startup_frames)
	remaining_seconds = total_seconds
	reset_reaction_choice_state()
	impact_resolution_text = "Pending"
	manager.log_message.emit("Reaction window started: %s, %.1fs." % [intent, total_seconds])

func tick(delta: float, waiting_for_defense: bool, effective_startup_frames: int, current_intent: String) -> Dictionary:
	if not active or resolving or not waiting_for_defense:
		return {"should_resolve": false}
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	remaining_seconds = maxf(0.0, remaining_seconds - real_delta)
	var current_progress := progress()
	var elapsed_startup_frames := int(floor(float(effective_startup_frames) * current_progress))
	var remaining_startup := maxi(0, effective_startup_frames - elapsed_startup_frames)
	_update_reaction_choice(elapsed_startup_frames, real_delta, current_intent)
	if remaining_seconds <= 0.0:
		resolving = true
		return {
			"should_resolve": true,
			"remaining_startup_frames": remaining_startup,
			"progress": current_progress
		}
	return {
		"should_resolve": false,
		"remaining_startup_frames": remaining_startup,
		"progress": current_progress
	}

func progress() -> float:
	if total_seconds <= 0.0:
		return 0.0
	return clampf(1.0 - (remaining_seconds / total_seconds), 0.0, 1.0)

func perfect_block_window_active() -> bool:
	return active and progress() >= perfect_block_reaction_progress

func deactivate() -> void:
	active = false
	resolving = false

func reset_guard_state() -> void:
	selected_defense_type = ""
	defense_input_progress = -1.0
	current_guard_input = ""
	guard_start_elapsed_frame = -1
	guard_startup_frames_remaining = 0.0
	guard_active = false
	correct_defense_became_active_progress = -1.0

func reset_reaction_choice_state() -> void:
	reset_guard_state()
	reaction_choice = "NONE"
	jump_started = false
	jump_active = false
	jump_start_elapsed_frame = -1
	jump_startup_frames_remaining = 0.0
	jump_input_progress = -1.0

func has_active_defense() -> bool:
	return jump_active or (guard_active and selected_defense_type != "")

func resolved_defense_type() -> String:
	if jump_active:
		return "jump"
	return selected_defense_type

func resolved_input_progress() -> float:
	if jump_active:
		return jump_input_progress
	return defense_input_progress

func start_challenge() -> void:
	reaction_choice = "CHALLENGE"
	reset_guard_state()
	jump_started = false
	jump_active = false

func request_jump_evade() -> void:
	if active and not resolving and not jump_started and reaction_choice != "CHALLENGE":
		var elapsed_startup_frames := 0
		if manager.enemy_effective_startup_frame > 0:
			elapsed_startup_frames = int(floor(float(manager.enemy_effective_startup_frame) * progress()))
		_start_jump_evade(elapsed_startup_frames)

func set_impact_resolution(text: String) -> void:
	impact_resolution_text = text

func _update_reaction_choice(elapsed_startup_frames: int, real_delta: float, current_intent: String) -> void:
	if reaction_choice == "CHALLENGE":
		return
	if jump_started:
		_update_jump_evade(real_delta, current_intent)
		return
	_update_live_guard(elapsed_startup_frames, real_delta, current_intent)

func _start_jump_evade(elapsed_startup_frames: int) -> void:
	reset_guard_state()
	reaction_choice = "JUMP EVADE"
	jump_started = true
	jump_active = false
	jump_start_elapsed_frame = elapsed_startup_frames
	jump_startup_frames_remaining = jump_startup_frames
	jump_input_progress = progress()
	manager.log_message.emit("Jump evade started.")
	manager.log_message.emit("Defense selected: jump evade at %d%%." % int(round(jump_input_progress * 100.0)))

func _update_jump_evade(real_delta: float, current_intent: String) -> void:
	jump_startup_frames_remaining = maxf(0.0, jump_startup_frames_remaining - real_delta * 60.0)
	var startup_progress := 1.0 - (jump_startup_frames_remaining / float(maxi(1, jump_startup_frames)))
	player.show_timeline_phase("jump", "STARTUP" if not jump_active else "ACTIVE", startup_progress, current_intent, false)
	if not jump_active and jump_startup_frames_remaining <= 0.0:
		jump_active = true
		manager.log_message.emit("Player airborne before impact.")

func _update_live_guard(elapsed_startup_frames: int, real_delta: float, current_intent: String) -> void:
	var live_guard := _current_live_guard_input()
	if live_guard == "":
		if current_guard_input != "":
			manager.log_message.emit("Guard released.")
			if player != null and player.has_method("release_block_action"):
				player.release_block_action()
		reset_guard_state()
		reaction_choice = "NONE"
		return

	if live_guard != current_guard_input:
		reaction_choice = "LOW BLOCK" if live_guard == "crouch_block" else "BLOCK"
		current_guard_input = live_guard
		selected_defense_type = live_guard
		defense_input_progress = progress()
		guard_start_elapsed_frame = elapsed_startup_frames
		guard_startup_frames_remaining = guard_startup_frames
		guard_active = false
		correct_defense_became_active_progress = -1.0
		manager.log_message.emit("Guard startup began.")
		manager.log_message.emit("Defense selected: %s at %d%%." % [_defense_display_name(live_guard), int(round(defense_input_progress * 100.0))])

	if guard_start_elapsed_frame >= 0:
		guard_startup_frames_remaining = maxf(0.0, guard_startup_frames_remaining - real_delta * 60.0)
		if not guard_active and guard_startup_frames_remaining <= 0:
			guard_active = true
			correct_defense_became_active_progress = progress()
			manager.log_message.emit("%s active." % ("Low block" if current_guard_input == "crouch_block" else "Stand block"))

	if guard_active:
		player.show_timeline_phase(current_guard_input, "ACTIVE", 1.0, current_intent, false)
	elif current_guard_input != "":
		var startup_progress := 1.0 - (guard_startup_frames_remaining / float(maxi(1, guard_startup_frames)))
		player.show_timeline_phase(current_guard_input, "STARTUP", startup_progress, current_intent, false)

func _current_live_guard_input() -> String:
	if not Input.is_key_pressed(KEY_J):
		return ""
	return "crouch_block" if Input.is_key_pressed(KEY_S) else "block"

func _defense_display_name(defense_type: String) -> String:
	match defense_type:
		"crouch_block":
			return "crouch block"
		"block":
			return "block"
		_:
			return defense_type
