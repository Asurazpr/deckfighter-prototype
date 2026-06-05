class_name CombatInputRouter
extends RefCounted

# TODO: Move key bindings into configurable input/action data when control schemes
# and modded character kits become data-driven.

func route_key_event(event: InputEvent, manager: Node, viewport: Viewport) -> bool:
	var key_event := event as InputEventKey
	if key_event == null or key_event.echo:
		return false

	if manager.has_method("is_power_action_mode") and manager.is_power_action_mode() and key_event.keycode == KEY_L and manager.has_method("request_power_action_block"):
		manager.request_power_action_block(key_event.pressed)
		viewport.set_input_as_handled()
		return true

	if not key_event.pressed:
		return false

	if key_event.keycode == KEY_F9 and manager.has_method("toggle_control_mode"):
		manager.toggle_control_mode()
		viewport.set_input_as_handled()
		return true

	if manager.has_method("is_power_action_mode") and manager.is_power_action_mode():
		if _handle_power_action_controls(key_event.keycode, manager, viewport):
			return true

	if manager.can_accept_live_movement():
		if key_event.keycode == KEY_W and manager.has_method("request_live_neutral_jump"):
			manager.request_live_neutral_jump()
			viewport.set_input_as_handled()
			return true
		if _handle_queue_controls(key_event.keycode, manager, viewport, true):
			return true

	if manager.can_accept_live_defense():
		if _is_debug_toggle(key_event.keycode):
			return false
		if key_event.keycode == KEY_W:
			manager.reaction_window_system.request_jump_evade()
			viewport.set_input_as_handled()
			return true
		return false

	if manager.can_accept_tactical_queue_input():
		if _handle_queue_controls(key_event.keycode, manager, viewport, false):
			return true
		if key_event.keycode == KEY_U:
			viewport.set_input_as_handled()
			if manager.queue_resolver.is_empty():
				manager._execute_or_wait_tactical_queue()
			return true

		var queued_action: Dictionary = manager._queued_action_from_key(key_event.keycode)
		if not queued_action.is_empty():
			viewport.set_input_as_handled()
			manager._queue_tactical_action(queued_action)
			return true

	if manager.can_accept_live_defense():
		var defense_type: String = manager._defense_from_key(key_event.keycode)
		if defense_type == "":
			return false
		viewport.set_input_as_handled()
		manager._resolve_enemy_intent(defense_type)
		return true

	if manager._can_take_pressure_movement():
		var pressure_action: String = manager._pressure_movement_from_key(key_event.keycode)
		if pressure_action == "":
			return false
		viewport.set_input_as_handled()
		manager._apply_pressure_movement(pressure_action)
		return true

	return false

func _handle_queue_controls(keycode: Key, manager: Node, viewport: Viewport, slow_neutral_only := false) -> bool:
	match keycode:
		KEY_E:
			viewport.set_input_as_handled()
			manager._execute_or_wait_tactical_queue()
			return true
		KEY_BACKSPACE:
			viewport.set_input_as_handled()
			manager._pop_tactical_action()
			return true
		KEY_C:
			viewport.set_input_as_handled()
			manager._clear_tactical_queue()
			return true
		_:
			return false

func _is_debug_toggle(keycode: Key) -> bool:
	return keycode == KEY_F1 or keycode == KEY_F2 or keycode == KEY_F3 or keycode == KEY_F4 or keycode == KEY_F5 or keycode == KEY_F6 or keycode == KEY_F7 or keycode == KEY_F9

func _handle_power_action_controls(keycode: Key, manager: Node, viewport: Viewport) -> bool:
	var move_id := ""
	var input_name := ""
	match keycode:
		KEY_J:
			move_id = "light_punch"
			input_name = "J"
		KEY_K:
			move_id = "light_kick"
			input_name = "K"
		KEY_U:
			move_id = "heavy_punch"
			input_name = "U"
		KEY_I:
			move_id = "heavy_kick"
			input_name = "I"
		_:
			return false
	if manager.has_method("request_direct_action"):
		viewport.set_input_as_handled()
		manager.request_direct_action(input_name, move_id)
		return true
	return false
