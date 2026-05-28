class_name TexturePackerSpriteFramesLoader
extends RefCounted

static var _cache: Dictionary = {}

static func build_sprite_frames(sheet_root: String, animations: Dictionary, default_fps := 30, fps_overrides := {}, loop_overrides := {}):
	var cache_key := "%s|%s|%s|%s" % [sheet_root, JSON.stringify(animations), JSON.stringify(fps_overrides), JSON.stringify(loop_overrides)]
	if _cache.has(cache_key):
		return _cache[cache_key]

	var started_at := Time.get_ticks_msec()
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	for animation_name in animations.keys():
		var animation_started_at := Time.get_ticks_msec()
		var sheet_name := String(animations[animation_name])
		var sheet_path := "%s/%s.tpsheet" % [sheet_root.trim_suffix("/"), sheet_name]
		if not FileAccess.file_exists(sheet_path):
			push_warning("TexturePacker sheet missing for animation %s at %s" % [animation_name, sheet_path])
			return null

		var metadata := _load_json(sheet_path)
		if metadata.is_empty():
			return null

		var textures: Array = metadata.get("textures", []) as Array
		if textures.is_empty():
			push_warning("TexturePacker sheet has no textures: %s" % sheet_path)
			return null

		frames.add_animation(animation_name)
		frames.set_animation_speed(animation_name, float(fps_overrides.get(animation_name, default_fps)))
		frames.set_animation_loop(animation_name, bool(loop_overrides.get(animation_name, _default_loop(animation_name))))

		for texture_block in textures:
			var block := texture_block as Dictionary
			var image_name := String(block.get("image", ""))
			var atlas_texture := _load_atlas_texture("%s/%s" % [sheet_root.trim_suffix("/"), image_name])
			if atlas_texture == null:
				return null
			var sprites: Array = block.get("sprites", []) as Array
			sprites.sort_custom(_sort_sprite_entries)
			for sprite_entry in sprites:
				var frame_texture := _make_atlas_frame(atlas_texture, sprite_entry as Dictionary)
				if frame_texture != null:
					frames.add_frame(animation_name, frame_texture)

		var frame_count := frames.get_frame_count(animation_name)
		if frame_count <= 0:
			push_warning("TexturePacker animation has no frames: %s" % animation_name)
			return null
		print("Loaded spritesheet animation %s: %d frames at %.1f FPS in %dms" % [animation_name, frame_count, frames.get_animation_speed(animation_name), Time.get_ticks_msec() - animation_started_at])

	print("Built SpriteFrames from TexturePacker sheets at %s in %dms" % [sheet_root, Time.get_ticks_msec() - started_at])
	_cache[cache_key] = frames
	return frames

static func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not open TexturePacker metadata: %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_warning("Could not parse TexturePacker metadata: %s" % path)
	return {}

static func _load_atlas_texture(resource_path: String) -> Texture2D:
	var image := Image.new()
	var err := image.load(ProjectSettings.globalize_path(resource_path))
	if err != OK:
		push_warning("Could not load TexturePacker atlas %s: %s" % [resource_path, error_string(err)])
		return null
	return ImageTexture.create_from_image(image)

static func _make_atlas_frame(atlas_texture: Texture2D, sprite_entry: Dictionary) -> AtlasTexture:
	var region_data: Dictionary = sprite_entry.get("region", {}) as Dictionary
	if region_data.is_empty():
		return null
	var texture := AtlasTexture.new()
	texture.atlas = atlas_texture
	texture.region = Rect2(
		float(region_data.get("x", 0.0)),
		float(region_data.get("y", 0.0)),
		float(region_data.get("w", 0.0)),
		float(region_data.get("h", 0.0))
	)
	var margin_data: Dictionary = sprite_entry.get("margin", {}) as Dictionary
	if not margin_data.is_empty():
		texture.margin = Rect2(
			float(margin_data.get("x", 0.0)),
			float(margin_data.get("y", 0.0)),
			float(margin_data.get("w", 0.0)),
			float(margin_data.get("h", 0.0))
		)
	return texture

static func _sort_sprite_entries(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("filename", "")) < String(b.get("filename", ""))

static func _default_loop(animation_name: String) -> bool:
	return animation_name == "idle" or animation_name == "run_forward" or animation_name == "run_backward" or animation_name == "block"
