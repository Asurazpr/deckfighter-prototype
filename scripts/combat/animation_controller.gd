class_name CombatAnimationController
extends RefCounted

var manager: Node
var player: Node
var enemy: Node

func setup(manager_ref, player_ref, enemy_ref) -> void:
	manager = manager_ref
	player = player_ref
	enemy = enemy_ref

func present_action_phase(actor_id: String, action_id: String, phase: String, progress: float, hitbox_active := false) -> void:
	var actor: Node = player if actor_id == "player" else enemy
	if actor != null and actor.has_method("show_timeline_phase"):
		actor.show_timeline_phase(action_id, phase, progress, "", hitbox_active)

func release_block_visual(actor_id: String) -> void:
	var actor: Node = player if actor_id == "player" else enemy
	if actor != null and actor.has_method("release_block_action"):
		actor.release_block_action()
