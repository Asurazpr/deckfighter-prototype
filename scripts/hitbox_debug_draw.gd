class_name HitboxDebugDraw
extends Node2D

var combat_manager: Node

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if combat_manager == null or not combat_manager.show_debug_hitboxes:
		return

	draw_rect(combat_manager.get_player_pushbox(), Color(0.25, 0.7, 1.0, 0.35), false, 1.0)
	draw_rect(combat_manager.get_enemy_pushbox(), Color(1.0, 0.25, 0.25, 0.35), false, 1.0)
	draw_rect(combat_manager.get_player_hurtbox(), Color(0.25, 0.7, 1.0, 0.9), false, 2.0)
	draw_rect(combat_manager.get_enemy_hurtbox(), Color(1.0, 0.25, 0.25, 0.9), false, 2.0)
	var player_attack_hitbox: Rect2 = combat_manager.get_player_attack_hitbox()
	var enemy_attack_hitbox: Rect2 = combat_manager.get_enemy_attack_hitbox()
	if player_attack_hitbox.size != Vector2.ZERO:
		draw_rect(player_attack_hitbox, Color(1.0, 0.9, 0.2, 0.95), false, 2.0)
	if enemy_attack_hitbox.size != Vector2.ZERO:
		draw_rect(enemy_attack_hitbox, Color(1.0, 0.2, 1.0, 0.95), false, 2.0)
