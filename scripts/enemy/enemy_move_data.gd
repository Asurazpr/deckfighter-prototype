class_name EnemyMoveData
extends RefCounted

# TODO: Convert this data-shaped config into resources or external data files so
# normal, elite, boss, and modded enemies can override move pools safely.

const ATTACKS := {
		"HIGH": {"id": "HIGH", "name": "High Check", "attack_level": "HIGH", "damage": 14, "stance_damage": 10, "startup": 6, "startup_frame": 6, "active": 3, "recovery": 14, "range_min": 0.0, "range_max": 70.0, "range": 70.0, "counter_damage": 18, "hit_level": "HIGH", "on_hit_adv": 1, "on_block_adv": -2, "hitbox_width": 42.0, "hitbox_height": 24.0, "hitbox_offset_x": 38.0, "hitbox_offset_y": -102.0, "tags": ["fast", "anti_air"], "ai_use_case": ["fast_punish", "anti_air", "mash"]},
		"MID": {"id": "MID", "name": "Mid Strike", "attack_level": "MID", "damage": 12, "stance_damage": 8, "startup": 9, "startup_frame": 9, "active": 3, "recovery": 16, "range_min": 0.0, "range_max": 60.0, "range": 60.0, "counter_damage": 16, "hit_level": "MID", "on_hit_adv": 1, "on_block_adv": -1, "hitbox_width": 38.0, "hitbox_height": 22.0, "hitbox_offset_x": 31.0, "hitbox_offset_y": -72.0, "tags": ["poke"], "ai_use_case": ["poke", "pressure_starter", "fast_punish"]},
		"LOW": {"id": "LOW", "name": "Low Check", "attack_level": "LOW", "damage": 10, "stance_damage": 8, "startup": 10, "startup_frame": 10, "active": 3, "recovery": 17, "range_min": 0.0, "range_max": 66.0, "range": 66.0, "counter_damage": 14, "hit_level": "LOW", "on_hit_adv": 1, "on_block_adv": -3, "hitbox_width": 46.0, "hitbox_height": 24.0, "hitbox_offset_x": 36.0, "hitbox_offset_y": -26.0, "tags": ["low"], "ai_use_case": ["low_check", "pressure_starter"]},
		"OVERHEAD": {"id": "OVERHEAD", "name": "Overhead Starter", "attack_level": "OVERHEAD", "damage": 16, "stance_damage": 14, "startup": 15, "startup_frame": 15, "active": 4, "recovery": 22, "range_min": 0.0, "range_max": 64.0, "range": 64.0, "counter_damage": 22, "hit_level": "OVERHEAD", "on_hit_adv": 3, "on_block_adv": -6, "hitbox_width": 44.0, "hitbox_height": 46.0, "hitbox_offset_x": 32.0, "hitbox_offset_y": -92.0, "tags": ["slow", "starter"], "ai_use_case": ["overhead", "pressure_starter", "stance_breaker"]}
}

static func default_moves() -> Dictionary:
	return ATTACKS.duplicate(true)
