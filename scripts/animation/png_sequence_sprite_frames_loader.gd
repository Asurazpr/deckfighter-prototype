class_name PngSequenceSpriteFramesLoader
extends RefCounted

static var _cache: Dictionary = {}

static func build_sprite_frames(renders_root: String, animations: Dictionary, default_fps := 30, fps_overrides := {}, loop_overrides := {}) -> SpriteFrames:
	var cache_key := "%s|%s|%s|%s" % [renders_root, JSON.stringify(animations), JSON.stringify(fps_overrides), JSON.stringify(loop_overrides)]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var started_at := Time.get_ticks_msec()
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for animation_name in animations.keys():
		var animation_started_at := Time.get_ticks_msec()
		var folder_name := String(animations[animation_name])
		var folder_path := "%s/%s" % [renders_root.trim_suffix("/"), folder_name]
		var files := _png_files(folder_path)
		if files.is_empty():
			push_warning("No PNG frames found for animation %s at %s" % [animation_name, folder_path])
			continue
		frames.add_animation(animation_name)
		frames.set_animation_speed(animation_name, float(fps_overrides.get(animation_name, default_fps)))
		frames.set_animation_loop(animation_name, bool(loop_overrides.get(animation_name, _default_loop(animation_name))))
		for file_name in files:
			var texture := _load_png_texture("%s/%s" % [folder_path, file_name])
			if texture != null:
				frames.add_frame(animation_name, texture)
		print("Loaded animation %s: %d frames at %.1f FPS in %dms" % [animation_name, frames.get_frame_count(animation_name), frames.get_animation_speed(animation_name), Time.get_ticks_msec() - animation_started_at])
	print("Built SpriteFrames from %s in %dms" % [renders_root, Time.get_ticks_msec() - started_at])
	_cache[cache_key] = frames
	return frames

static func _png_files(folder_path: String) -> Array[String]:
	var output: Array[String] = []
	var dir := DirAccess.open(folder_path)
	if dir == null:
		push_warning("Could not open PNG sequence folder: %s" % folder_path)
		return output
	for file_name in dir.get_files():
		if file_name.get_extension().to_lower() == "png":
			output.append(file_name)
	output.sort()
	return output

static func _default_loop(animation_name: String) -> bool:
	return animation_name == "idle" or animation_name == "run_forward" or animation_name == "run_backward" or animation_name == "block"

static func _load_png_texture(resource_path: String) -> Texture2D:
	var image := Image.new()
	var err := image.load(ProjectSettings.globalize_path(resource_path))
	if err != OK:
		push_warning("Could not load PNG frame %s: %s" % [resource_path, error_string(err)])
		return null
	return ImageTexture.create_from_image(image)
