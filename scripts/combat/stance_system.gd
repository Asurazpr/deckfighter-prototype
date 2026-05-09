class_name StanceSystem
extends RefCounted

var enemy: Node

func setup(enemy_ref: Node) -> void:
	enemy = enemy_ref

func advance_frames(frames: int) -> void:
	if enemy != null and enemy.has_method("advance_stance_recovery_frames"):
		enemy.advance_stance_recovery_frames(frames)

func is_broken() -> bool:
	return enemy != null and int(enemy.state) == 3

func protected() -> bool:
	return enemy != null and enemy.has_method("is_stance_protected") and enemy.is_stance_protected()

func state_name() -> String:
	return enemy.get_stance_state_name() if enemy != null and enemy.has_method("get_stance_state_name") else "UNKNOWN"

func recovery_frames() -> int:
	return int(enemy.get("stance_recovery_frames_remaining")) if enemy != null else 0

func break_stun_frames() -> int:
	return int(enemy.get("stance_break_stun_frames_remaining")) if enemy != null else 0
