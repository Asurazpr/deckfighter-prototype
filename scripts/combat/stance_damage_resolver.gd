class_name StanceDamageResolver
extends RefCounted

const RAW_HIT := "RAW_HIT"
const NORMAL_BLOCK := "NORMAL_BLOCK"
const PERFECT_BLOCK := "PERFECT_BLOCK"
const COUNTER_HIT := "COUNTER_HIT"
const WHIFF := "WHIFF"
const EVADED := "EVADED"
const PERFECT_BLOCK_REWARD := "PERFECT_BLOCK_REWARD"

const MULTIPLIERS := {
	RAW_HIT: 1.0,
	NORMAL_BLOCK: 0.5,
	PERFECT_BLOCK: 0.0,
	COUNTER_HIT: 1.5,
	WHIFF: 0.0,
	EVADED: 0.0,
	PERFECT_BLOCK_REWARD: 1.0
}

func apply_stance_damage(defender: Node, base_stance_damage: int, hit_result: String) -> Dictionary:
	var normalized_result := normalize_result(hit_result)
	var multiplier := float(MULTIPLIERS.get(normalized_result, 1.0))
	var attempted := maxi(0, int(round(float(maxi(0, base_stance_damage)) * multiplier)))
	var before := _stance_value(defender)
	var protected := _stance_protected(defender)

	if attempted > 0 and defender != null and not protected:
		if normalized_result == NORMAL_BLOCK and defender.has_method("add_block_stance_damage"):
			defender.add_block_stance_damage(attempted)
		elif defender.has_method("add_stance_damage"):
			defender.add_stance_damage(attempted)

	var after := _stance_value(defender)
	var applied := 0 if protected else maxi(0, after - before)
	return {
		"defender": _defender_name(defender),
		"hit_result": normalized_result,
		"base_stance_damage": base_stance_damage,
		"multiplier": multiplier,
		"stance_before": before,
		"stance_after": after,
		"stance_damage_attempted": attempted,
		"stance_damage_applied": applied,
		"stance_protected": protected,
		"stance_state": _stance_state_name(defender),
		"recovery_frames_remaining": _stance_recovery_frames(defender)
	}

func normalize_result(hit_result: String) -> String:
	var normalized := hit_result.to_upper()
	normalized = normalized.replace(" ", "_")
	match normalized:
		RAW_HIT, NORMAL_BLOCK, PERFECT_BLOCK, COUNTER_HIT, WHIFF, EVADED, PERFECT_BLOCK_REWARD:
			return normalized
		"HIT":
			return RAW_HIT
		"BLOCK":
			return NORMAL_BLOCK
		"COUNTER":
			return COUNTER_HIT
		_:
			return RAW_HIT

func _stance_value(defender: Node) -> int:
	return int(defender.get("stance")) if defender != null else 0

func _stance_protected(defender: Node) -> bool:
	return defender != null and defender.has_method("is_stance_protected") and bool(defender.is_stance_protected())

func _stance_state_name(defender: Node) -> String:
	return String(defender.get_stance_state_name()) if defender != null and defender.has_method("get_stance_state_name") else "UNKNOWN"

func _stance_recovery_frames(defender: Node) -> int:
	return int(defender.get("stance_recovery_frames_remaining")) if defender != null else 0

func _defender_name(defender: Node) -> String:
	if defender == null:
		return "Unknown"
	if defender is RenkaPlayer:
		return "Player"
	if defender is Player:
		return "Player"
	if defender is Enemy:
		return "Enemy"
	return defender.name
