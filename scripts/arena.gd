extends Node2D

@onready var player = $Player
@onready var enemy = $Enemy
@onready var deck_manager = $DeckManager
@onready var combat_manager = $CombatManager
@onready var ui_manager = $UI

func _ready() -> void:
	ui_manager.bind(player, enemy, deck_manager, combat_manager)
