class_name EnemyAISystem
extends RefCounted

enum DecisionState { NEUTRAL, BLOCKING, PUNISHING, PRESSURING, MASHING, RECOVERING, STUNNED, STANCE_BROKEN, DEFENSIVE_REACTION }

const INTENT_PROFILES := {
	"NORMAL": {
		"tier": "NORMAL",
		"punish_weight": 0.5,
		"block_weight": 0.6,
		"mash_weight": 0.4,
		"perfect_block_chance": 0.03,
		"reaction_delay_min": 4,
		"reaction_delay_max": 8,
		"randomness": 0.35,
		"allowed_use_cases": ["poke", "fast_punish", "block", "wait", "low_check"]
	},
	"ELITE": {
		"tier": "ELITE",
		"punish_weight": 1.0,
		"block_weight": 0.9,
		"mash_weight": 0.8,
		"perfect_block_chance": 0.08,
		"reaction_delay_min": 1,
		"reaction_delay_max": 3,
		"randomness": 0.18,
		"allowed_use_cases": ["poke", "fast_punish", "block", "wait", "low_check", "pressure_starter", "anti_air", "overhead"]
	},
	"BOSS": {
		"tier": "BOSS",
		"punish_weight": 1.2,
		"block_weight": 0.85,
		"mash_weight": 0.7,
		"perfect_block_chance": 0.05,
		"reaction_delay_min": 0,
		"reaction_delay_max": 2,
		"randomness": 0.08,
		"allowed_use_cases": ["poke", "fast_punish", "block", "wait", "low_check", "pressure_starter", "anti_air", "overhead", "stance_breaker"],
		"phase_id": "phase_1",
		"phase_thresholds": {"phase_1": 0.65, "phase_2": 0.3},
		"phase_move_pool": {
			"phase_1": ["MID", "LOW", "HIGH"],
			"phase_2": ["MID", "LOW", "OVERHEAD", "HIGH"],
			"rage": ["OVERHEAD", "HIGH", "LOW"]
		},
		"special_intent_cooldowns": {},
		"scripted_sequences": [],
		"rage_modifiers": {"punish_weight": 1.35, "randomness": 0.04},
		"boss_only_tags": ["boss_pattern"]
	}
}

var manager: Node
var enemy: Node
var frame_system
var intent_profile: Dictionary = {}
var last_state := "NEUTRAL"
var last_reason := "Ready."
var last_chosen_action := "None"
var last_score := 0.0
var last_effective_startup := 0
var last_spacing_result := "Unchecked"
var last_punish_candidates: Array[String] = []
var last_profile_modifiers := "Profile unset."
var boss_phase_id := "none"

func setup(manager_ref: Node, enemy_ref: Node, frame_system_ref) -> void:
	manager = manager_ref
	enemy = enemy_ref
	frame_system = frame_system_ref
	set_intent_tier(String(enemy.get("intent_tier")) if enemy != null else "NORMAL")

func set_intent_tier(tier: String) -> void:
	var profile_key := tier if INTENT_PROFILES.has(tier) else "NORMAL"
	intent_profile = (INTENT_PROFILES[profile_key] as Dictionary).duplicate(true)
	boss_phase_id = String(intent_profile.get("phase_id", "none")) if profile_key == "BOSS" else "none"

func _refresh_profile() -> void:
	var tier := String(enemy.get("intent_tier")) if enemy != null else String(intent_profile.get("tier", "NORMAL"))
	if String(intent_profile.get("tier", "")) != tier:
		set_intent_tier(tier)
	if tier == "BOSS":
		_update_boss_phase()

func choose_intent(context: Dictionary) -> Dictionary:
	last_punish_candidates.clear()
	_refresh_profile()
	var cannot_act_reason := _cannot_act_reason(context)
	if cannot_act_reason != "":
		_set_state(DecisionState.STANCE_BROKEN if String(context.get("stance_state", "")) != "NORMAL" else DecisionState.RECOVERING, cannot_act_reason, "None", 0.0, 0)
		return {}

	var best_action := {}
	var best_score := -99999.0
	var best_effective_startup := 0
	var best_reason := ""
	var best_spacing := ""
	for action_id in enemy.ATTACKS.keys():
		var action: Dictionary = enemy.ATTACKS[action_id]
		if not _profile_allows_action(action):
			continue
		var evaluation := _score_action(action, context)
		if bool(evaluation.get("rejected", false)):
			continue
		var score := float(evaluation["score"])
		var tie_randomness := clampf(float(intent_profile.get("randomness", 0.2)), 0.02, 0.5)
		if score > best_score or (is_equal_approx(score, best_score) and randf() < tie_randomness):
			best_action = action
			best_score = score
			best_effective_startup = int(evaluation["effective_startup"])
			best_reason = String(evaluation["reason"])
			best_spacing = String(evaluation["spacing"])

	if best_action.is_empty():
		_set_state(DecisionState.DEFENSIVE_REACTION, "No usable attack at current spacing; enemy waits/guards.", "None", 0.0, 0)
		last_spacing_result = "No attack reaches."
		return {}

	var decision_state := _state_for_action(best_action, context)
	_set_state(decision_state, best_reason, String(best_action["id"]), best_score, best_effective_startup)
	last_spacing_result = best_spacing
	return {
		"action_id": String(best_action["id"]),
		"action": best_action,
		"score": best_score,
		"effective_startup": best_effective_startup,
		"state": last_state,
		"reason": best_reason,
		"spacing": best_spacing,
		"punish_candidates": last_punish_candidates.duplicate()
	}

func evaluate_pressure_reaction(card: Resource, context: Dictionary) -> Dictionary:
	_refresh_profile()
	if _cannot_act_reason(context) != "":
		_set_state(DecisionState.STUNNED, "Enemy cannot react during pressure: %s." % _cannot_act_reason(context), "None", 0.0, 0)
		return {"state": last_state, "reason": last_reason}

	var repeated := int(context.get("move_use_count", 1)) >= 2
	var player_advantage := int(context.get("frame_advantage", 0))
	var card_level := _card_hit_level(card)
	var mash_score := 25.0 * float(intent_profile.get("mash_weight", 1.0))
	var block_score := 18.0 * float(intent_profile.get("block_weight", 1.0))
	var perfect_roll := randf() < float(intent_profile.get("perfect_block_chance", 0.0))
	var delay := _reaction_delay()
	if (player_advantage <= 1 or repeated) and mash_score >= 10.0:
		_set_state(DecisionState.MASHING, "Enemy sees a pressure gap/repeated move and considers mashing. Profile %s, delay %df." % [intent_profile.get("tier", "NORMAL"), delay], "HIGH", mash_score, int(enemy.ATTACKS["HIGH"]["startup_frame"]) + delay)
	elif card_level == "LOW":
		_set_state(DecisionState.BLOCKING, "%sEnemy guards low against incoming pressure. Profile %s." % ["Perfect block read: " if perfect_roll else "", intent_profile.get("tier", "NORMAL")], "CROUCH_BLOCK", block_score, delay)
	elif card_level == "OVERHEAD":
		_set_state(DecisionState.BLOCKING, "%sEnemy stands to block overhead pressure. Profile %s." % ["Perfect block read: " if perfect_roll else "", intent_profile.get("tier", "NORMAL")], "STAND_BLOCK", block_score, delay)
	else:
		_set_state(DecisionState.BLOCKING, "%sEnemy blocks stable mid/high pressure. Profile %s." % ["Perfect block read: " if perfect_roll else "", intent_profile.get("tier", "NORMAL")], "BLOCK", block_score, delay)
	return {"state": last_state, "reason": last_reason}

func debug_text() -> String:
	return "Enemy Tier: %s\nBoss Phase: %s\nEnemy AI State: %s\nEnemy AI Reason: %s\nEnemy AI Action: %s\nEnemy AI Score: %.1f\nEnemy AI Effective Startup: %d\nEnemy AI Spacing: %s\nEnemy AI Profile Mods: %s\nEnemy Punish Candidates: %s" % [
		intent_profile.get("tier", "NORMAL"),
		boss_phase_id,
		last_state,
		last_reason,
		last_chosen_action,
		last_score,
		last_effective_startup,
		last_spacing_result,
		last_profile_modifiers,
		", ".join(last_punish_candidates) if not last_punish_candidates.is_empty() else "None"
	]

func _score_action(action: Dictionary, context: Dictionary) -> Dictionary:
	var distance := float(context.get("distance", 9999.0))
	var initiative_offset := int(context.get("initiative_offset", 0))
	var player_delta := int(context.get("player_frame_delta", 0))
	var player_has_pressure := bool(context.get("player_has_pressure", false))
	var queue_resolving := bool(context.get("queue_resolving", false))
	var effective_startup: int = frame_system.effective_startup(int(action["startup_frame"]), initiative_offset)
	effective_startup += _reaction_delay()
	var range_min := float(action.get("range_min", 0.0))
	var range_max := float(action.get("range_max", action.get("range", 0.0)))
	var reaches: bool = distance >= range_min and distance <= range_max
	var use_cases: Array = action.get("ai_use_case", [])
	var score := 0.0
	var reasons: Array[String] = []
	var spacing: String = "distance %.0f within %.0f-%.0f: %s" % [distance, range_min, range_max, str(reaches)]

	if not reaches:
		return {"rejected": true, "reason": "out of range", "spacing": spacing, "effective_startup": effective_startup}

	score += 20.0
	reasons.append("reaches current spacing")

	if player_delta < 0:
		var punish_window: int = absi(player_delta)
		if effective_startup <= max(1, punish_window + int(enemy.punish_startup)):
			score += 100.0 * float(intent_profile.get("punish_weight", 1.0))
			last_punish_candidates.append("%s %df" % [action["id"], effective_startup])
			reasons.append("punish candidate")
		if use_cases.has("fast_punish"):
			score += 30.0 * float(intent_profile.get("punish_weight", 1.0))
			reasons.append("fast punish use case")
		if effective_startup <= 6:
			score += 20.0
			reasons.append("fast startup while player negative")
	else:
		if use_cases.has("pressure_starter"):
			score += 20.0
			reasons.append("pressure starter")
		if distance > 75.0 and use_cases.has("poke"):
			score += 15.0
			reasons.append("poke at mid spacing")

	if player_has_pressure or queue_resolving:
		score -= 25.0
		reasons.append("player pressure active")
		if effective_startup <= 6:
			score += 15.0 * float(intent_profile.get("mash_weight", 1.0))
			reasons.append("reasonable mash speed")
		else:
			score -= 20.0
			reasons.append("too slow to mash")

	if action.get("hit_level", "") == "OVERHEAD" and not player_has_pressure and player_delta >= 0:
		score += 10.0
		reasons.append("mixup threat")
	if action.get("hit_level", "") == "LOW" and not player_has_pressure:
		score += 8.0
		reasons.append("low check")
	if use_cases.has("anti_air") and bool(context.get("player_airborne", false)):
		score += 60.0
		reasons.append("anti-air read")
	if player_delta < -8 and not use_cases.has("fast_punish"):
		score -= 35.0
		reasons.append("unsafe slow choice while punishing")

	var randomness := float(intent_profile.get("randomness", 0.2))
	score += randf_range(-20.0 * randomness, 20.0 * randomness)
	last_profile_modifiers = "punish %.2f block %.2f mash %.2f pb %.2f delay %d-%d rand %.2f" % [
		float(intent_profile.get("punish_weight", 1.0)),
		float(intent_profile.get("block_weight", 1.0)),
		float(intent_profile.get("mash_weight", 1.0)),
		float(intent_profile.get("perfect_block_chance", 0.0)),
		int(intent_profile.get("reaction_delay_min", 0)),
		int(intent_profile.get("reaction_delay_max", 0)),
		randomness
	]
	return {
		"rejected": false,
		"score": score,
		"effective_startup": effective_startup,
		"reason": "; ".join(reasons),
		"spacing": spacing
	}

func _cannot_act_reason(context: Dictionary) -> String:
	if bool(context.get("combat_over", false)):
		return "combat is over"
	if bool(context.get("stance_protected", false)) or String(context.get("stance_state", "NORMAL")) != "NORMAL":
		return "stance state %s, recovery %df" % [context.get("stance_state", "UNKNOWN"), int(context.get("stance_recovery_frames", 0))]
	if bool(context.get("enemy_in_recovery", false)):
		var recovery_frames := int(context.get("enemy_recovery_frames", 0))
		var enemy_action := String(context.get("enemy_current_action", "None"))
		if recovery_frames > 0 or enemy_action != "None":
			return "enemy is recovering"
	if enemy == null or not enemy.can_act():
		return "enemy node cannot act"
	return ""

func _profile_allows_action(action: Dictionary) -> bool:
	var tier := String(intent_profile.get("tier", "NORMAL"))
	if tier == "BOSS":
		var move_pool: Dictionary = intent_profile.get("phase_move_pool", {})
		var phase_pool: Array = move_pool.get(boss_phase_id, [])
		if not phase_pool.is_empty() and not phase_pool.has(action.get("id", "")):
			return false

	var allowed: Array = intent_profile.get("allowed_use_cases", [])
	if allowed.is_empty():
		return true
	for use_case in action.get("ai_use_case", []):
		if allowed.has(use_case):
			return true
	return false

func _reaction_delay() -> int:
	return randi_range(int(intent_profile.get("reaction_delay_min", 0)), int(intent_profile.get("reaction_delay_max", 0)))

func _update_boss_phase() -> void:
	var hp_ratio := 1.0
	if enemy != null and enemy.max_hp > 0:
		hp_ratio = float(enemy.hp) / float(enemy.max_hp)
	var thresholds: Dictionary = intent_profile.get("phase_thresholds", {})
	if thresholds.has("phase_2") and hp_ratio <= float(thresholds["phase_2"]):
		boss_phase_id = "rage"
		var rage_mods: Dictionary = intent_profile.get("rage_modifiers", {})
		for key in rage_mods.keys():
			intent_profile[key] = rage_mods[key]
	elif thresholds.has("phase_1") and hp_ratio <= float(thresholds["phase_1"]):
		boss_phase_id = "phase_2"
	else:
		boss_phase_id = "phase_1"

func _state_for_action(action: Dictionary, context: Dictionary) -> int:
	var player_delta := int(context.get("player_frame_delta", 0))
	if player_delta < 0 and last_punish_candidates.has("%s %df" % [action["id"], frame_system.effective_startup(int(action["startup_frame"]), int(context.get("initiative_offset", 0)))]):
		return DecisionState.PUNISHING
	if bool(context.get("player_has_pressure", false)):
		return DecisionState.MASHING
	if action.get("ai_use_case", []).has("pressure_starter"):
		return DecisionState.PRESSURING
	return DecisionState.NEUTRAL

func _set_state(state_id: int, reason: String, action_id: String, score: float, effective_startup: int) -> void:
	last_state = _state_name(state_id)
	last_reason = reason
	last_chosen_action = action_id
	last_score = score
	last_effective_startup = effective_startup
	if enemy != null and enemy.has_method("set_decision_state"):
		enemy.set_decision_state(state_id, reason, score)

func _state_name(state_id: int) -> String:
	match state_id:
		DecisionState.NEUTRAL:
			return "NEUTRAL"
		DecisionState.BLOCKING:
			return "BLOCKING"
		DecisionState.PUNISHING:
			return "PUNISHING"
		DecisionState.PRESSURING:
			return "PRESSURING"
		DecisionState.MASHING:
			return "MASHING"
		DecisionState.RECOVERING:
			return "RECOVERING"
		DecisionState.STUNNED:
			return "STUNNED"
		DecisionState.STANCE_BROKEN:
			return "STANCE_BROKEN"
		DecisionState.DEFENSIVE_REACTION:
			return "DEFENSIVE_REACTION"
		_:
			return "UNKNOWN"

func _card_hit_level(card: Resource) -> String:
	if card.tags.has("air"):
		return "OVERHEAD"
	if card.id == "ground_smash":
		return "LOW"
	return "MID"
