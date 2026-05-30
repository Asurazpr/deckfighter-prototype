class_name HitboxDebugDraw
extends Node2D

var combat_manager: Node

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if combat_manager == null or not combat_manager.show_debug_hitboxes:
		return

	var calibration_enabled := bool(combat_manager.get("show_hitbox_calibration"))
	var sprite_bounds_enabled := bool(combat_manager.get("show_sprite_bounds_debug"))
	if calibration_enabled:
		_draw_calibration_bounds()
	draw_rect(combat_manager.get_player_pushbox(), Color(0.25, 0.7, 1.0, 0.35), false, 1.0)
	draw_rect(combat_manager.get_enemy_pushbox(), Color(1.0, 0.25, 0.25, 0.35), false, 1.0)
	draw_rect(combat_manager.get_player_hurtbox(), Color(0.25, 0.7, 1.0, 0.9), false, 2.0)
	draw_rect(combat_manager.get_enemy_hurtbox(), Color(1.0, 0.25, 0.25, 0.9), false, 2.0)
	var player_attack_hitbox: Rect2 = combat_manager.get_player_attack_hitbox()
	var enemy_attack_hitbox: Rect2 = combat_manager.get_enemy_attack_hitbox()
	if player_attack_hitbox.size != Vector2.ZERO:
		draw_rect(player_attack_hitbox, _phase_color("ACTIVE"), false, 2.0)
	if enemy_attack_hitbox.size != Vector2.ZERO:
		draw_rect(enemy_attack_hitbox, _phase_color("ACTIVE"), false, 2.0)
	if calibration_enabled:
		_draw_phase_preview_boxes()
	if sprite_bounds_enabled:
		_draw_sprite_bounds()

func _phase_color(phase: String) -> Color:
	match phase:
		"STARTUP":
			return Color(1.0, 0.85, 0.15, 0.95)
		"ACTIVE":
			return Color(1.0, 0.15, 0.12, 0.95)
		"RECOVERY":
			return Color(0.25, 0.55, 1.0, 0.95)
		_:
			return Color(1.0, 1.0, 1.0, 0.0)

func _draw_calibration_bounds() -> void:
	_draw_label(combat_manager.get_player_hurtbox().position + Vector2(0.0, -8.0), "P hurt")
	_draw_label(combat_manager.get_enemy_hurtbox().position + Vector2(0.0, -8.0), "E hurt")
	_draw_origin(combat_manager.get_player_origin(), Color(0.2, 0.9, 1.0, 0.95), "P origin")
	_draw_origin(combat_manager.get_enemy_origin(), Color(1.0, 0.55, 0.2, 0.95), "E origin")

func _draw_sprite_bounds() -> void:
	var player_sprite_bounds: Rect2 = combat_manager.get_player_sprite_bounds()
	var enemy_sprite_bounds: Rect2 = combat_manager.get_enemy_sprite_bounds()
	if player_sprite_bounds.size != Vector2.ZERO:
		draw_rect(player_sprite_bounds, Color(0.2, 0.9, 1.0, 0.7), false, 1.0)
		_draw_label(player_sprite_bounds.position + Vector2(0.0, -8.0), "P sprite")
	if enemy_sprite_bounds.size != Vector2.ZERO:
		draw_rect(enemy_sprite_bounds, Color(1.0, 0.55, 0.2, 0.7), false, 1.0)
		_draw_label(enemy_sprite_bounds.position + Vector2(0.0, -8.0), "E sprite")

func _draw_phase_preview_boxes() -> void:
	var player_preview: Rect2 = combat_manager.get_player_debug_attack_hitbox()
	var enemy_preview: Rect2 = combat_manager.get_enemy_debug_attack_hitbox()
	if player_preview.size != Vector2.ZERO:
		draw_rect(player_preview, _phase_color(combat_manager.get_player_hitbox_phase()), false, 1.0)
	if enemy_preview.size != Vector2.ZERO:
		draw_rect(enemy_preview, _phase_color(combat_manager.get_enemy_hitbox_phase()), false, 1.0)

func _draw_label(position: Vector2, text: String) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 11
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color.WHITE)

func _draw_origin(origin: Vector2, color: Color, label: String) -> void:
	draw_line(origin + Vector2(-6.0, 0.0), origin + Vector2(6.0, 0.0), color, 1.5)
	draw_line(origin + Vector2(0.0, -6.0), origin + Vector2(0.0, 6.0), color, 1.5)
	_draw_label(origin + Vector2(8.0, -8.0), label)
