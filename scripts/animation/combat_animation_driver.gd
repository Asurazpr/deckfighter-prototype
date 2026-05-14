class_name CombatAnimationDriver
extends RefCounted

# TODO: Move these pose mappings into character kit / move data so skins and mods
# can override animation keys without changing combat code.

static func drive_rig(rig: Node, action_name: String, phase_name: String, phase_progress: float, hit_level := "", hitbox_active := false) -> void:
	if rig == null or not rig.has_method("apply_combat_phase"):
		return
	var animation_key := animation_key_for_action(action_name, phase_name, hit_level)
	rig.apply_combat_phase(animation_key, phase_name, phase_progress, hit_level, hitbox_active)

static func animation_key_for_action(action_name: String, phase_name: String, hit_level := "") -> String:
	var normalized := action_name.to_lower().replace(" ", "_")
	if normalized == "" or normalized == "none":
		return "idle"
	match hit_level:
		"HIGH":
			return "high_hook"
		"MID":
			return "mid_punch"
		"LOW":
			return "low_sweep"
		"OVERHEAD":
			return "overhead_smash"
	if normalized.find("jab") != -1 or normalized.find("high_check") != -1:
		return "jab_%s" % phase_name.to_lower()
	if normalized.find("step_forward") != -1 or normalized.find("walk_forward") != -1 or normalized.find("step_slash") != -1:
		return "step_forward"
	if normalized.find("backstep") != -1 or normalized.find("step_back") != -1:
		return "backstep"
	if normalized.find("launcher") != -1 or normalized.find("overhead") != -1:
		return "launcher_%s" % phase_name.to_lower()
	if normalized.find("air_follow") != -1:
		return "air_follow_%s" % phase_name.to_lower()
	if normalized.find("ground_smash") != -1:
		return "ground_smash_%s" % phase_name.to_lower()
	if normalized.find("heavy_slash") != -1:
		return "heavy_slash_%s" % phase_name.to_lower()
	if normalized.find("guard_break") != -1:
		return "guard_break_%s" % phase_name.to_lower()
	if normalized.find("low") != -1:
		return "kick_%s" % phase_name.to_lower()
	if normalized.find("block") != -1:
		return "block_low" if hit_level == "LOW" or normalized.find("crouch") != -1 else "block_high"
	if normalized.find("hitstun") != -1 or normalized.find("hit") != -1:
		return "hitstun"
	if normalized.find("break") != -1:
		return "stance_break"
	return normalized

static func play_impact(rig: Node) -> void:
	if rig != null and rig.has_method("play_impact"):
		rig.play_impact()

static func clear(rig: Node) -> void:
	if rig != null and rig.has_method("clear_pose"):
		rig.clear_pose()
