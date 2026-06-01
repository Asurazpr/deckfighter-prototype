class_name CombatClock
extends RefCounted

var manager: Node
var player: Node
var enemy: Node

func setup(manager_ref: Node, player_ref: Node, enemy_ref: Node) -> void:
	manager = manager_ref
	player = player_ref
	enemy = enemy_ref

func advance_combat_frames(frames: int, tick_enemy_startup := false, tick_enemy_vulnerability := true) -> void:
	if frames <= 0:
		return
	if player != null and player.has_method("advance_stance_recovery_frames"):
		player.advance_stance_recovery_frames(frames)
	if enemy != null and enemy.has_method("advance_stance_recovery_frames"):
		enemy.advance_stance_recovery_frames(frames)
	if manager == null:
		return
	if tick_enemy_startup:
		manager.remaining_startup_frames -= frames
	if tick_enemy_vulnerability:
		manager.enemy_vulnerable_frames_remaining = maxi(0, manager.enemy_vulnerable_frames_remaining - frames)
	manager.frame_advantage_changed.emit(manager.frame_advantage)
