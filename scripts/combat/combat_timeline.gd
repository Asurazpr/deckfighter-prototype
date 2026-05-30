class_name CombatTimeline
extends RefCounted

enum Phase { STARTUP, ACTIVE, IMPACT, RECOVERY, DONE }

const PHASE_NAMES := {
	Phase.STARTUP: "STARTUP",
	Phase.ACTIVE: "ACTIVE",
	Phase.IMPACT: "IMPACT",
	Phase.RECOVERY: "RECOVERY",
	Phase.DONE: "DONE"
}

var actor := ""
var action_name := "None"
var animation_key := "idle"
var startup_frames := 0
var active_frames := 0
var recovery_frames := 0
var movement_frames := 0
var impact_frame := 0
var hitbox_on_frame := 0
var hitbox_off_frame := 0
var elapsed_frames := 0
var phase := Phase.DONE

func begin_action(actor_id: String, display_name: String, timeline_data: Dictionary) -> void:
	actor = actor_id
	action_name = display_name
	startup_frames = maxi(0, int(timeline_data.get("startup_frames", timeline_data.get("startup_frame", 0))))
	active_frames = maxi(0, int(timeline_data.get("active_frames", timeline_data.get("active", 1))))
	recovery_frames = maxi(0, int(timeline_data.get("recovery_frames", timeline_data.get("recovery", 0))))
	movement_frames = maxi(0, int(timeline_data.get("movement_frames", 0)))
	impact_frame = maxi(0, int(timeline_data.get("impact_frame", startup_frames)))
	hitbox_on_frame = maxi(0, int(timeline_data.get("hitbox_on_frame", startup_frames)))
	hitbox_off_frame = maxi(hitbox_on_frame, int(timeline_data.get("hitbox_off_frame", hitbox_on_frame + active_frames)))
	animation_key = String(timeline_data.get("animation_key", display_name.to_lower().replace(" ", "_")))
	elapsed_frames = 0
	_update_phase()

func begin_from_card(card: Resource) -> void:
	var active_start := int(card.active_start_frame)
	var active_end := maxi(active_start, int(card.active_end_frame))
	begin_action("PLAYER", card.display_name, {
		"startup_frames": int(card.startup_frame),
		"active_frames": active_end - active_start + 1,
		"recovery_frames": maxi(0, int(card.frame_cost)),
		"movement_frames": int(card.startup_frame) if absf(float(card.movement_delta)) > 0.0 else 0,
		"impact_frame": int(card.hit_frame),
		"hitbox_on_frame": active_start,
		"hitbox_off_frame": active_end + 1,
		"animation_key": String(card.id)
	})

func begin_from_move(actor_id: String, move_def: MoveDefinition) -> void:
	if move_def == null:
		finish_action()
		return
	begin_action(actor_id, move_def.display_name, move_def.timeline_data())

func begin_from_enemy_attack(attack_id: String, attack_data: Dictionary, effective_startup := -1) -> void:
	var startup := int(attack_data.get("startup_frame", attack_data.get("startup", 0)))
	if effective_startup >= 0:
		startup = effective_startup
	begin_action("ENEMY", String(attack_data.get("name", attack_id)), {
		"startup_frames": startup,
		"active_frames": int(attack_data.get("active", 3)),
		"recovery_frames": int(attack_data.get("recovery", 0)),
		"impact_frame": startup,
		"hitbox_on_frame": startup,
		"hitbox_off_frame": startup + int(attack_data.get("active", 3)),
		"animation_key": String(attack_data.get("animation_key", attack_id))
	})

func begin_movement(actor_id: String, display_name: String, cost_frames: int) -> void:
	begin_action(actor_id, display_name, {
		"startup_frames": cost_frames,
		"active_frames": 0,
		"recovery_frames": 0,
		"movement_frames": cost_frames,
		"impact_frame": cost_frames,
		"hitbox_on_frame": cost_frames,
		"hitbox_off_frame": cost_frames
	})

func advance_frames(frames: int) -> void:
	if frames <= 0 or phase == Phase.DONE:
		return
	elapsed_frames += frames
	_update_phase()

func set_startup_progress(progress: float) -> void:
	if phase == Phase.DONE:
		return
	elapsed_frames = clampi(int(round(float(hitbox_on_frame) * clampf(progress, 0.0, 1.0))), 0, hitbox_on_frame)
	phase = Phase.STARTUP if elapsed_frames < hitbox_on_frame else Phase.IMPACT

func mark_active() -> void:
	elapsed_frames = hitbox_on_frame
	phase = Phase.ACTIVE

func mark_impact() -> void:
	elapsed_frames = impact_frame
	phase = Phase.IMPACT

func mark_recovery() -> void:
	elapsed_frames = hitbox_off_frame
	phase = Phase.RECOVERY

func finish_action() -> void:
	phase = Phase.DONE
	elapsed_frames = total_frames()

func phase_name() -> String:
	return PHASE_NAMES.get(phase, "DONE")

func phase_frames_remaining() -> int:
	match phase:
		Phase.STARTUP:
			return maxi(0, hitbox_on_frame - elapsed_frames)
		Phase.ACTIVE, Phase.IMPACT:
			return maxi(0, hitbox_off_frame - elapsed_frames)
		Phase.RECOVERY:
			return maxi(0, total_frames() - elapsed_frames)
		_:
			return 0

func phase_progress() -> float:
	var phase_total := 0
	var phase_elapsed := 0
	match phase:
		Phase.STARTUP:
			phase_total = maxi(1, hitbox_on_frame)
			phase_elapsed = elapsed_frames
		Phase.ACTIVE, Phase.IMPACT:
			phase_total = maxi(1, hitbox_off_frame - hitbox_on_frame)
			phase_elapsed = elapsed_frames - hitbox_on_frame
		Phase.RECOVERY:
			phase_total = maxi(1, total_frames() - hitbox_off_frame)
			phase_elapsed = elapsed_frames - hitbox_off_frame
		_:
			return 1.0
	return clampf(float(phase_elapsed) / float(phase_total), 0.0, 1.0)

func active_window_text() -> String:
	if hitbox_on_frame == hitbox_off_frame:
		return "None"
	return "%d-%d" % [hitbox_on_frame, hitbox_off_frame]

func hitbox_active() -> bool:
	return phase == Phase.ACTIVE or phase == Phase.IMPACT

func impact_progress(remaining_startup: int) -> float:
	if startup_frames <= 0:
		return 0.0
	return clampf(1.0 - (float(maxi(0, remaining_startup)) / float(startup_frames)), 0.0, 1.0)

func total_frames() -> int:
	return startup_frames + active_frames + recovery_frames

func debug_text(remaining_startup := 0) -> String:
	return "Current Action: %s %s\nAnimation Key: %s\nAction Phase: %s\nPhase Progress: %d%%\nPhase Frames Remaining: %d\nActive Frame Window: %s\nHitbox Active: %s\nImpact Bar Progress: %d%%" % [
		actor,
		action_name,
		animation_key,
		phase_name(),
		int(round(phase_progress() * 100.0)),
		phase_frames_remaining(),
		active_window_text(),
		str(hitbox_active()),
		int(round(impact_progress(remaining_startup) * 100.0))
	]

func _update_phase() -> void:
	if elapsed_frames < hitbox_on_frame:
		phase = Phase.STARTUP
	elif elapsed_frames == impact_frame and hitbox_on_frame < hitbox_off_frame:
		phase = Phase.IMPACT
	elif elapsed_frames < hitbox_off_frame:
		phase = Phase.ACTIVE
	elif elapsed_frames < total_frames():
		phase = Phase.RECOVERY
	else:
		phase = Phase.DONE
