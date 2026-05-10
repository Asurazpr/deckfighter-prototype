class_name FrameSystem
extends RefCounted

var manager: Node
var enemy: Node

func setup(manager_ref: Node, enemy_ref: Node) -> void:
	manager = manager_ref
	enemy = enemy_ref

func signed_int(value: int) -> String:
	return "+%d" % value if value >= 0 else "%d" % value

func effective_startup(base_startup: int, initiative_offset: int) -> int:
	return maxi(1, base_startup + initiative_offset)

func apply_advantage_delta(delta: int, current_frame_advantage: int) -> int:
	var result := clampi(current_frame_advantage + delta, -12, 6)
	return result

func apply_tempo_delta(delta: int, current_frame_advantage: int) -> int:
	return maxi(0, clampi(current_frame_advantage + delta, -3, 6))

func spend_pressure_frames(cost: int, current_frame_advantage: int) -> int:
	return current_frame_advantage - cost

func enemy_can_punish(final_frame_advantage: int, punish_threshold: int, punish_hitbox: Rect2, player_hurtbox: Rect2) -> bool:
	if enemy == null or not enemy.can_act():
		return false
	var punish_window: int = absi(final_frame_advantage) + int(enemy.punish_startup)
	return punish_window >= punish_threshold and punish_hitbox.intersects(player_hurtbox)
