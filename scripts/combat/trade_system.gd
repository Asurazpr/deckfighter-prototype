class_name TradeSystem
extends RefCounted

var manager: Node
var player_recovery_frames := 18
var enemy_recovery_frames := 26

func setup(manager_ref: Node, player_recovery: int, enemy_recovery: int) -> void:
	manager = manager_ref
	player_recovery_frames = player_recovery
	enemy_recovery_frames = enemy_recovery

func resolve_post_trade(card: Resource) -> Dictionary:
	var player_recovery := player_recovery_frames + maxi(0, int(card.startup_frame) - 8)
	var enemy_recovery := enemy_recovery_frames
	return {
		"player_recovery": player_recovery,
		"enemy_recovery": enemy_recovery,
		"post_trade_frame_advantage": enemy_recovery - player_recovery,
		"total_recovery": maxi(player_recovery, enemy_recovery)
	}

