class_name UIManager
extends CanvasLayer

@onready var player_hp_bar: ProgressBar = %PlayerHPBar
@onready var enemy_hp_bar: ProgressBar = %EnemyHPBar
@onready var stance_bar: ProgressBar = %StanceBar
@onready var frame_label: Label = %FrameLabel
@onready var log_label: Label = %LogLabel
@onready var combat_log_label: Label = %CombatLogLabel
@onready var hand_container: HBoxContainer = %HandContainer

const MAX_COMBAT_LOG_EVENTS := 8

var combat_manager: Node
var deck_manager_ref: Node
var combat_log_events: Array[String] = []

func bind(player: Node, enemy: Node, deck_manager: Node, manager: Node) -> void:
	combat_manager = manager
	deck_manager_ref = deck_manager
	player.hp_changed.connect(_on_player_hp_changed)
	enemy.hp_changed.connect(_on_enemy_hp_changed)
	enemy.stance_changed.connect(_on_stance_changed)
	deck_manager.hand_changed.connect(_on_hand_changed)
	manager.frame_advantage_changed.connect(_on_frame_advantage_changed)
	manager.log_message.connect(_on_log_message)
	_on_player_hp_changed(player.hp, player.max_hp)
	_on_enemy_hp_changed(enemy.hp, enemy.max_hp)
	_on_stance_changed(enemy.stance, enemy.max_stance)
	_on_frame_advantage_changed(manager.frame_advantage)
	_on_hand_changed(deck_manager.hand)

func _on_player_hp_changed(current_hp: int, max_hp: int) -> void:
	player_hp_bar.max_value = max_hp
	player_hp_bar.value = current_hp

func _on_enemy_hp_changed(current_hp: int, max_hp: int) -> void:
	enemy_hp_bar.max_value = max_hp
	enemy_hp_bar.value = current_hp

func _on_stance_changed(current_stance: int, max_stance: int) -> void:
	stance_bar.max_value = max_stance
	stance_bar.value = current_stance

func _on_frame_advantage_changed(value: int) -> void:
	frame_label.text = "Frame Advantage: %d" % value
	_refresh_card_enabled_state()

func _on_log_message(message: String) -> void:
	log_label.text = message
	combat_log_events.append(message)
	while combat_log_events.size() > MAX_COMBAT_LOG_EVENTS:
		combat_log_events.pop_front()
	_refresh_combat_log()

func _on_hand_changed(hand: Array) -> void:
	for child in hand_container.get_children():
		child.queue_free()

	for i in range(hand.size()):
		var card: Resource = hand[i]
		var button := Button.new()
		button.custom_minimum_size = Vector2(170, 116)
		button.text = "%s\nFrame: -%d / +%d\nStance: %d\nNext: %s" % [
			card.display_name,
			card.frame_cost,
			card.frame_gain,
			card.stance_damage,
			deck_manager_ref.get_follow_up_tags(card)
		]
		button.tooltip_text = card.description
		button.pressed.connect(_on_card_pressed.bind(i))
		hand_container.add_child(button)

	_refresh_card_enabled_state()

func _on_card_pressed(index: int) -> void:
	if combat_manager != null:
		combat_manager.play_card(index)

func _refresh_card_enabled_state() -> void:
	if combat_manager == null:
		return
	var children := hand_container.get_children()
	for i in range(children.size()):
		var child := children[i]
		if child is Button:
			child.disabled = not combat_manager.is_hand_card_playable(i)

func _refresh_combat_log() -> void:
	var text := ""
	for event in combat_log_events:
		if text != "":
			text += "\n"
		text += "- %s" % event
	combat_log_label.text = text
