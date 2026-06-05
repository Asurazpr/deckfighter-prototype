class_name PowerFightingModeController
extends RefCounted

const ActionRequestScript := preload("res://scripts/combat/action_request.gd")

var manager
var direct_input_map := {
	"J": "light_punch",
	"K": "light_kick",
	"U": "heavy_punch",
	"I": "heavy_kick"
}

func setup(manager_ref) -> void:
	manager = manager_ref

func move_for_input(input_name: String) -> String:
	return String(direct_input_map.get(input_name, ""))

func action_request_for_input(input_name: String, move_id: String, input_frame := 0, payload := {}) -> ActionRequest:
	var request_payload := payload.duplicate(true) if payload is Dictionary else {}
	request_payload["input_name"] = input_name
	request_payload["control_mode"] = "POWER_ACTION"
	return ActionRequestScript.from_direct_input("player", move_id, input_name, input_frame, 0, request_payload)

func request_direct_action(input_name: String, move_id: String) -> ActionRequest:
	return action_request_for_input(input_name, move_id, Engine.get_process_frames(), {
		"source_controller": "PowerFightingModeController"
	})
