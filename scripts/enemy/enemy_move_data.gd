class_name EnemyMoveData
extends RefCounted

# TODO: Convert this data-shaped config into resources or external data files so
# normal, elite, boss, and modded enemies can override move pools safely.

const ATTACKS := {
	"HIGH": {"id": "HIGH", "name": "High Check", "damage": 14, "stance_damage": 0, "startup": 6, "startup_frame": 6, "active": 3, "recovery": 14, "range_min": 0.0, "range_max": 80.0, "range": 80.0, "counter_damage": 18, "hit_level": "HIGH", "on_hit_adv": 1, "on_block_adv": -2, "hitbox_width": 85.0, "hitbox_height": 45.0, "hitbox_offset_x": 42.5, "hitbox_offset_y": -65.0, "tags": ["fast", "anti_air"], "ai_use_case": ["fast_punish", "anti_air", "mash"]},
	"MID": {"id": "MID", "name": "Mid Strike", "damage": 12, "stance_damage": 0, "startup": 9, "startup_frame": 9, "active": 3, "recovery": 16, "range_min": 0.0, "range_max": 90.0, "range": 90.0, "counter_damage": 16, "hit_level": "MID", "on_hit_adv": 1, "on_block_adv": -1, "hitbox_width": 95.0, "hitbox_height": 55.0, "hitbox_offset_x": 47.5, "hitbox_offset_y": -40.0, "tags": ["poke"], "ai_use_case": ["poke", "pressure_starter", "fast_punish"]},
	"LOW": {"id": "LOW", "name": "Low Check", "damage": 10, "stance_damage": 0, "startup": 10, "startup_frame": 10, "active": 3, "recovery": 17, "range_min": 0.0, "range_max": 75.0, "range": 75.0, "counter_damage": 14, "hit_level": "LOW", "on_hit_adv": 1, "on_block_adv": -3, "hitbox_width": 85.0, "hitbox_height": 35.0, "hitbox_offset_x": 42.5, "hitbox_offset_y": -15.0, "tags": ["low"], "ai_use_case": ["low_check", "pressure_starter"]},
	"OVERHEAD": {"id": "OVERHEAD", "name": "Overhead Starter", "damage": 16, "stance_damage": 0, "startup": 15, "startup_frame": 15, "active": 4, "recovery": 22, "range_min": 0.0, "range_max": 85.0, "range": 85.0, "counter_damage": 22, "hit_level": "OVERHEAD", "on_hit_adv": 3, "on_block_adv": -6, "hitbox_width": 100.0, "hitbox_height": 75.0, "hitbox_offset_x": 50.0, "hitbox_offset_y": -70.0, "tags": ["slow", "starter"], "ai_use_case": ["overhead", "pressure_starter", "stance_breaker"]}
}

static func default_moves() -> Dictionary:
	return ATTACKS.duplicate(true)
