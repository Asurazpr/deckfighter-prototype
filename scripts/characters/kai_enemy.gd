class_name KaiEnemy
extends Enemy

const SpriteFramesLoader := preload("res://scripts/animation/png_sequence_sprite_frames_loader.gd")
const Manifest := preload("res://scripts/characters/kai_animation_manifest.gd")

const KAI_ATTACKS := {
	"light_punch": {"id": "light_punch", "name": "Kai Light Punch", "type": "MID", "attack_level": "MID", "damage": 12, "stance_damage": 8, "startup": 12, "startup_frame": 12, "active": 3, "recovery": 20, "range_min": 0.0, "range_max": 60.0, "range": 60.0, "counter_damage": 16, "hit_level": "MID", "on_hit_adv": 1, "on_block_adv": -1, "hitbox_width": 38.0, "hitbox_height": 22.0, "hitbox_offset_x": 31.0, "hitbox_offset_y": -72.0, "animation_key": "light_punch", "tags": ["poke"], "ai_use_case": ["poke", "pressure_starter", "fast_punish"]},
	"light_kick": {"id": "light_kick", "name": "Kai Light Kick", "type": "MID", "attack_level": "MID", "damage": 12, "stance_damage": 8, "startup": 14, "startup_frame": 14, "active": 3, "recovery": 22, "range_min": 0.0, "range_max": 66.0, "range": 66.0, "counter_damage": 16, "hit_level": "MID", "on_hit_adv": 1, "on_block_adv": -1, "hitbox_width": 46.0, "hitbox_height": 24.0, "hitbox_offset_x": 36.0, "hitbox_offset_y": -42.0, "animation_key": "light_kick", "tags": ["poke"], "ai_use_case": ["poke", "pressure_starter"]},
	"heavy_kick": {"id": "heavy_kick", "name": "Kai Heavy Kick", "type": "HIGH", "attack_level": "HIGH", "damage": 14, "stance_damage": 10, "startup": 20, "startup_frame": 20, "active": 4, "recovery": 30, "range_min": 0.0, "range_max": 70.0, "range": 70.0, "counter_damage": 18, "hit_level": "HIGH", "on_hit_adv": 1, "on_block_adv": -2, "hitbox_width": 42.0, "hitbox_height": 24.0, "hitbox_offset_x": 38.0, "hitbox_offset_y": -102.0, "animation_key": "heavy_kick", "tags": ["fast", "anti_air"], "ai_use_case": ["fast_punish", "anti_air", "mash"]},
	"heavy_punch": {"id": "heavy_punch", "name": "Kai Heavy Punch", "type": "OVERHEAD", "attack_level": "OVERHEAD", "damage": 16, "stance_damage": 14, "startup": 26, "startup_frame": 26, "active": 4, "recovery": 36, "range_min": 0.0, "range_max": 64.0, "range": 64.0, "counter_damage": 22, "hit_level": "OVERHEAD", "on_hit_adv": 3, "on_block_adv": -6, "hitbox_width": 44.0, "hitbox_height": 46.0, "hitbox_offset_x": 32.0, "hitbox_offset_y": -92.0, "animation_key": "heavy_punch", "tags": ["slow", "starter"], "ai_use_case": ["overhead", "pressure_starter", "stance_breaker"]}
}
const DEBUG_ATTACK_CYCLE := ["light_punch", "light_kick", "heavy_kick", "heavy_punch"]

@export var sprite_scale := Vector2(0.22, 0.22)
@export var sprite_pivot := Vector2(970.0, 984.0)
@export var source_faces_left := true
@export var use_debug_attack_cycle := true
@export var debug_cycle_ignores_range := true
@export var hitbox_definition_scale := Vector2.ONE

var _current_kai_animation := ""
var _facing_sign := 1.0
var _animation_backend := "png_sequence"
var _debug_attack_cycle_index := 0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	_configure_sprite()
	super._ready()
	if body != null:
		body.visible = false
	if rig != null:
		rig.visible = false
	_play_kai_animation("idle")

func get_attacks() -> Dictionary:
	return KAI_ATTACKS

func choose_debug_attack_id(context: Dictionary) -> String:
	if not use_debug_attack_cycle:
		return ""
	var distance := float(context.get("distance", 9999.0))
	var sequence_size := DEBUG_ATTACK_CYCLE.size()
	if sequence_size <= 0:
		return ""
	var next_action_id := String(DEBUG_ATTACK_CYCLE[_debug_attack_cycle_index % sequence_size])
	if debug_cycle_ignores_range:
		_debug_attack_cycle_index = (_debug_attack_cycle_index + 1) % sequence_size
		print("Kai debug attack cycle: %s -> next index %d" % [next_action_id, _debug_attack_cycle_index])
		return next_action_id
	for i in sequence_size:
		var action_id := String(DEBUG_ATTACK_CYCLE[(_debug_attack_cycle_index + i) % sequence_size])
		var action: Dictionary = KAI_ATTACKS[action_id]
		var range_min := float(action.get("range_min", 0.0))
		var range_max := float(action.get("range_max", action.get("range", 0.0)))
		if distance >= range_min and distance <= range_max:
			_debug_attack_cycle_index = (_debug_attack_cycle_index + i + 1) % sequence_size
			print("Kai debug attack cycle: %s -> next index %d" % [action_id, _debug_attack_cycle_index])
			return action_id
	return ""

func start_attack(attack_id := "") -> void:
	super.start_attack(attack_id)
	if current_attack == "":
		return
	var attack := get_attacks().get(current_attack, {}) as Dictionary
	var hit_level := String(attack.get("hit_level", current_attack))
	_set_telegraph_text("%s\n%s" % [String(attack.get("name", current_attack)).to_upper(), hit_level], "ENEMY ATTACK", _attack_color(hit_level), Color.WHITE)

func take_hit(damage: int, stance_damage: int) -> void:
	super.take_hit(damage, stance_damage)
	if is_defeated():
		return
	_play_kai_animation("heavy_hitstun" if damage >= 14 else "light_hitstun")

func enter_break(from_block := false) -> void:
	super.enter_break(from_block)
	_play_kai_animation("heavy_hitstun")

func show_timeline_phase(action_name: String, phase_name: String, phase_progress := 0.0, hit_level := "", hitbox_active := false) -> void:
	current_animation_action = action_name
	current_animation_phase = phase_name
	current_animation_progress = phase_progress
	current_animation_hit_level = _current_attack_hit_level(hit_level)
	current_animation_hitbox_active = hitbox_active
	var animation_name := _animation_for_timeline(action_name, current_animation_hit_level)
	_play_kai_animation(animation_name, phase_name, phase_progress)
	var marker_text := _current_attack_label(action_name)
	_set_telegraph_text(
		"%s %s" % [marker_text, phase_name],
		"ENEMY ATTACK %s" % phase_name,
		_attack_color(current_animation_hit_level),
		Color(1.0, 0.86, 0.56)
	)

func clear_timeline_visual() -> void:
	super.clear_timeline_visual()
	if stance_state == StanceState.NORMAL:
		current_animation_action = "None"
		current_animation_phase = "DONE"
		current_animation_progress = 0.0
		current_animation_hit_level = ""
		current_animation_hitbox_active = false
		_play_kai_animation("idle")

func get_animation_debug() -> Dictionary:
	var data := super.get_animation_debug()
	data["animation_key"] = _current_kai_animation
	data["pose_key"] = _current_kai_animation
	data["current_pose_name"] = _current_kai_animation
	data["action_name"] = current_animation_action
	data["hit_level"] = current_animation_hit_level
	data["phase"] = current_animation_phase
	data["phase_progress"] = current_animation_progress
	data["hitbox_active"] = current_animation_hitbox_active
	data["rig_scale"] = animated_sprite.scale if animated_sprite != null else Vector2.ONE
	data["facing"] = "left" if _facing_sign > 0.0 else "right"
	data["backend"] = _animation_backend
	data["debug_attack_cycle_index"] = _debug_attack_cycle_index
	data["debug_attack_cycle_next"] = DEBUG_ATTACK_CYCLE[_debug_attack_cycle_index % DEBUG_ATTACK_CYCLE.size()]
	return data

func _set_idle() -> void:
	super._set_idle()
	if body != null:
		body.visible = false
	if rig != null:
		rig.visible = false
	_play_kai_animation("idle")

func _configure_sprite() -> void:
	var sprite_frames := SpriteFramesLoader.build_sprite_frames(
		Manifest.RENDERS_ROOT,
		Manifest.ANIMATIONS,
		Manifest.FPS,
		Manifest.FPS_OVERRIDES,
		Manifest.LOOP_OVERRIDES
	)
	_animation_backend = "png_sequence"
	print("Kai animation backend loaded: %s" % _animation_backend)
	animated_sprite.sprite_frames = sprite_frames
	animated_sprite.centered = false
	animated_sprite.offset = -sprite_pivot
	_apply_sprite_scale()

func _play_kai_animation(animation_name: String, phase_name := "", phase_progress := -1.0) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if animation_name == "" or not animated_sprite.sprite_frames.has_animation(animation_name):
		return
	if _current_kai_animation != animation_name:
		_current_kai_animation = animation_name
		_apply_sprite_scale()
		animated_sprite.animation = animation_name
	if _should_sample_timeline(animation_name, phase_name, phase_progress):
		animated_sprite.frame = _timeline_frame_for_phase(animation_name, phase_name, phase_progress)
		animated_sprite.pause()
		return
	if _current_kai_animation == animation_name and animated_sprite.is_playing():
		return
	animated_sprite.play(animation_name)

func _apply_sprite_scale() -> void:
	if animated_sprite == null:
		return
	animated_sprite.centered = false
	animated_sprite.offset = -sprite_pivot
	animated_sprite.scale = Vector2(_facing_sign * absf(sprite_scale.x), absf(sprite_scale.y))

func set_facing_direction(direction: float) -> void:
	if direction == 0.0:
		return
	if source_faces_left:
		_facing_sign = 1.0 if direction < 0.0 else -1.0
	else:
		_facing_sign = 1.0 if direction > 0.0 else -1.0
	_apply_sprite_scale()

func get_hitbox_definition_scale() -> Vector2:
	var root_scale := global_transform.get_scale()
	return Vector2(absf(root_scale.x), absf(root_scale.y)) * hitbox_definition_scale

func _animation_for_timeline(action_name: String, hit_level: String) -> String:
	var normalized := action_name.to_lower().replace(" ", "_")
	if normalized.find("block") != -1:
		return "block"
	if normalized.find("hitstun") != -1 or normalized.find("hit") != -1:
		return "light_hitstun"
	if normalized.find("walk") != -1 or normalized.find("step") != -1 or normalized.find("run") != -1:
		return "walking"
	if current_attack != "" and get_attacks().has(current_attack):
		var attack := get_attacks()[current_attack] as Dictionary
		return String(attack.get("animation_key", current_attack))
	if normalized.find("light_kick") != -1:
		return "light_kick"
	if normalized.find("heavy_kick") != -1:
		return "heavy_kick"
	if normalized.find("heavy_punch") != -1 or hit_level == "OVERHEAD":
		return "heavy_punch"
	if normalized.find("light_punch") != -1 or hit_level == "MID":
		return "light_punch"
	if hit_level == "HIGH":
		return "heavy_kick"
	return "idle"

func _current_attack_hit_level(fallback := "") -> String:
	if current_attack != "" and get_attacks().has(current_attack):
		var attack := get_attacks()[current_attack] as Dictionary
		return String(attack.get("hit_level", attack.get("type", fallback)))
	return fallback

func _current_attack_label(fallback := "") -> String:
	if current_attack != "" and get_attacks().has(current_attack):
		var attack := get_attacks()[current_attack] as Dictionary
		return "%s %s" % [String(attack.get("name", current_attack)).to_upper(), String(attack.get("hit_level", ""))]
	return fallback.to_upper()

func _should_sample_timeline(animation_name: String, phase_name: String, phase_progress: float) -> bool:
	if phase_progress < 0.0:
		return false
	if animation_name == "idle" or animation_name == "walking" or animation_name.ends_with("hitstun"):
		return false
	return phase_name == "STARTUP" or phase_name == "ACTIVE" or phase_name == "IMPACT" or phase_name == "RECOVERY"

func _timeline_frame_for_phase(animation_name: String, phase_name: String, phase_progress: float) -> int:
	var frame_count := animated_sprite.sprite_frames.get_frame_count(animation_name)
	if frame_count <= 1:
		return 0
	var startup_end := clampi(int(round(float(frame_count - 1) * 0.55)), 0, frame_count - 1)
	var active_end := clampi(int(round(float(frame_count - 1) * 0.72)), startup_end, frame_count - 1)
	var recovery_start := mini(active_end + 1, frame_count - 1)
	match phase_name:
		"STARTUP":
			return clampi(int(round(lerpf(0.0, float(startup_end), phase_progress))), 0, frame_count - 1)
		"ACTIVE", "IMPACT":
			return clampi(int(round(lerpf(float(startup_end), float(active_end), phase_progress))), 0, frame_count - 1)
		"RECOVERY":
			return clampi(int(round(lerpf(float(recovery_start), float(frame_count - 1), phase_progress))), 0, frame_count - 1)
		_:
			return frame_count - 1
