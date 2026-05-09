class_name UIManager
extends CanvasLayer

@onready var player_hp_bar: ProgressBar = %PlayerHPBar
@onready var enemy_hp_bar: ProgressBar = %EnemyHPBar
@onready var stance_bar: ProgressBar = %StanceBar
@onready var frame_label: Label = %FrameLabel
@onready var log_label: Label = %LogLabel
@onready var combat_log_label: Label = %CombatLogLabel
@onready var hand_container: HBoxContainer = %HandContainer
@onready var root: Control = $Root

const MAX_COMBAT_LOG_EVENTS := 8
const PREDICTION_COLORS := {
	"interrupt": Color(0.55, 1.0, 0.62),
	"trade": Color(1.0, 0.9, 0.35),
	"too_slow": Color(1.0, 0.45, 0.42),
	"whiff": Color(0.62, 0.62, 0.62),
	"normal": Color.WHITE
}

var combat_manager: Node
var deck_manager_ref: Node
var combat_log_events: Array[String] = []
var card_buttons: Array[Button] = []
var debug_label: Label

func _ready() -> void:
	_remove_space_from_ui_accept()
	_build_debug_label()

func _process(_delta: float) -> void:
	if combat_manager != null and debug_label != null:
		debug_label.text = combat_manager.get_debug_text()

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
	card_buttons.clear()
	for child in hand_container.get_children():
		child.queue_free()

	for i in range(hand.size()):
		var card: Resource = hand[i]
		var button := Button.new()
		button.custom_minimum_size = Vector2(190, 154)
		button.text = _format_card_text(card)
		button.tooltip_text = _format_card_tooltip(card)
		button.mouse_entered.connect(_show_card_debug.bind(card))
		button.pressed.connect(_on_card_pressed.bind(i))
		hand_container.add_child(button)
		card_buttons.append(button)

	_refresh_card_enabled_state()

func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return

	match key_event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			var focused_index := _get_focused_card_index()
			if focused_index != -1:
				_try_play_card(focused_index)
				get_viewport().set_input_as_handled()
		KEY_1, KEY_KP_1:
			_try_play_card_from_number(0)
			get_viewport().set_input_as_handled()
		KEY_2, KEY_KP_2:
			_try_play_card_from_number(1)
			get_viewport().set_input_as_handled()
		KEY_3, KEY_KP_3:
			_try_play_card_from_number(2)
			get_viewport().set_input_as_handled()
		KEY_4, KEY_KP_4:
			_try_play_card_from_number(3)
			get_viewport().set_input_as_handled()

func _remove_space_from_ui_accept() -> void:
	if not InputMap.has_action("ui_accept"):
		return
	for event in InputMap.action_get_events("ui_accept"):
		var key_event := event as InputEventKey
		if key_event != null and key_event.keycode == KEY_SPACE:
			InputMap.action_erase_event("ui_accept", event)

func _build_debug_label() -> void:
	debug_label = Label.new()
	debug_label.position = Vector2(24, 140)
	debug_label.size = Vector2(360, 150)
	debug_label.text = "Distance: 0\nEnemy intent: None\nEnemy remaining startup: 0\nLast player startup: 0\nEnemy vulnerable frames: 0\nMode: Neutral"
	debug_label.add_theme_font_size_override("font_size", 16)
	root.add_child(debug_label)

func _on_card_pressed(index: int) -> void:
	_try_play_card(index)

func _try_play_card_from_number(index: int) -> void:
	if index >= card_buttons.size():
		return
	if not _try_play_card(index):
		_on_log_message("Card not playable.")

func _try_play_card(index: int) -> bool:
	if combat_manager == null or not combat_manager.is_hand_card_playable(index):
		return false
	combat_manager.play_card(index)
	return true

func _get_focused_card_index() -> int:
	var focus_owner := get_viewport().gui_get_focus_owner()
	for i in range(card_buttons.size()):
		if card_buttons[i] == focus_owner:
			return i
	return -1

func _refresh_card_enabled_state() -> void:
	if combat_manager == null:
		return
	for i in range(card_buttons.size()):
		card_buttons[i].disabled = not combat_manager.is_hand_card_playable(i)
		card_buttons[i].modulate = _prediction_color_for_card(i)

func _prediction_color_for_card(index: int) -> Color:
	if combat_manager == null or not combat_manager.has_method("get_card_prediction"):
		return Color.WHITE
	var prediction := String(combat_manager.get_card_prediction(index))
	return PREDICTION_COLORS.get(prediction, Color.WHITE)

func _format_card_text(card: Resource) -> String:
	return "%s\nDMG %d | ST %d\nStart %df\nHit +%d | Whiff %s%d\nNext: %s" % [
		card.display_name,
		card.damage,
		card.stance_damage,
		card.startup_frame,
		card.frame_gain,
		"+" if int(card.whiff_frame_penalty) >= 0 else "",
		card.whiff_frame_penalty,
		deck_manager_ref.get_follow_up_tags(card)
	]

func _format_card_tooltip(card: Resource) -> String:
	return "%s\nStartup: %df\nDamage: %d\nStance Damage: %d\nFrame Cost: %d\nFrame Gain: %d\nWhiff Penalty: %d\nTags: %s\nRoute IDs: %s" % [
		card.description,
		card.startup_frame,
		card.damage,
		card.stance_damage,
		card.frame_cost,
		card.frame_gain,
		card.whiff_frame_penalty,
		", ".join(card.tags) if not card.tags.is_empty() else "None",
		", ".join(card.allowed_follow_up_card_ids) if not card.allowed_follow_up_card_ids.is_empty() else "None"
	]

func _show_card_debug(card: Resource) -> void:
	log_label.text = "Card: %s | Start %df | DMG %d | ST %d | Cost %d | Hit +%d | Whiff %d | Tags: %s | Route: %s" % [
		card.display_name,
		card.startup_frame,
		card.damage,
		card.stance_damage,
		card.frame_cost,
		card.frame_gain,
		card.whiff_frame_penalty,
		", ".join(card.tags) if not card.tags.is_empty() else "None",
		", ".join(card.allowed_follow_up_card_ids) if not card.allowed_follow_up_card_ids.is_empty() else "None"
	]

func _refresh_combat_log() -> void:
	var text := ""
	for event in combat_log_events:
		if text != "":
			text += "\n"
		text += "- %s" % event
	combat_log_label.text = text
