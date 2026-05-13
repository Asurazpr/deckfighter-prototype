class_name Player
extends CharacterBody2D

signal hp_changed(current_hp: int, max_hp: int)
signal defense_performed(defense_type: String)

const CombatAnimationDriver := preload("res://scripts/animation/combat_animation_driver.gd")
const SPEED := 250.0
const JUMP_VELOCITY := -500.0
const GRAVITY := 1300.0

@export var max_hp := 100
@export var hurtbox_width := 50.0
@export var hurtbox_height := 90.0

var hp := max_hp
var input_enabled := true
var free_movement_enabled := true

@onready var body: ColorRect = $Body
@onready var state_label: Label = $StateLabel
@onready var rig: Node = $Rig

func _ready() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)
	_set_state("READY")

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	var direction := 0.0
	if input_enabled and free_movement_enabled:
		direction = Input.get_axis("move_left", "move_right")
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
			defense_performed.emit("jump")
			_flash(Color.SKY_BLUE, "JUMP")
		if Input.is_action_just_pressed("block"):
			defense_performed.emit("block")
			_flash(Color.DODGER_BLUE, "BLOCK")
		if Input.is_action_just_pressed("crouch_block"):
			defense_performed.emit("crouch_block")
			_flash(Color.CORNFLOWER_BLUE, "CROUCH")
		if Input.is_action_just_pressed("backstep"):
			velocity.x = -SPEED * 2.2
			defense_performed.emit("backstep")
			_flash(Color.LIGHT_BLUE, "BACKSTEP")

	if absf(velocity.x) < SPEED * 1.8:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, direction * SPEED, SPEED * delta * 5.0)

	move_and_slide()

func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	hp = maxi(0, hp - amount)
	hp_changed.emit(hp, max_hp)
	CombatAnimationDriver.drive_rig(rig, "hitstun", "IMPACT", 1.0, "", false)
	CombatAnimationDriver.play_impact(rig)
	_flash(Color.INDIAN_RED, "HIT")

func perform_card_action(card: Resource) -> void:
	_flash(Color.GOLD, card.display_name.to_upper())

func show_state(label: String, color: Color) -> void:
	_flash(color, label)

func show_timeline_phase(action_name: String, phase_name: String, phase_progress := 0.0, hit_level := "", hitbox_active := false) -> void:
	CombatAnimationDriver.drive_rig(rig, action_name, phase_name, phase_progress, hit_level, hitbox_active)
	match phase_name:
		"STARTUP":
			body.color = Color(0.35, 0.62, 1.0)
			body.scale = Vector2(0.92, 1.04)
		"ACTIVE", "IMPACT":
			body.color = Color.GOLD
			body.scale = Vector2(1.08, 0.96)
		"RECOVERY":
			body.color = Color(0.55, 0.82, 1.0)
			body.scale = Vector2(0.98, 1.0)
		_:
			body.color = Color(0.25, 0.75, 1.0)
			body.scale = Vector2.ONE
	_set_state("%s\n%s" % [action_name.to_upper(), phase_name])

func clear_timeline_visual() -> void:
	body.color = Color(0.25, 0.75, 1.0)
	body.scale = Vector2.ONE
	CombatAnimationDriver.clear(rig)

func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled

func set_free_movement_enabled(enabled: bool) -> void:
	free_movement_enabled = enabled
	if not enabled:
		velocity.x = 0.0

func _flash(color: Color, label: String) -> void:
	body.color = color
	_set_state(label)
	var tween := create_tween()
	tween.tween_property(body, "color", Color(0.25, 0.75, 1.0), 0.18)

func _set_state(text: String) -> void:
	state_label.text = text
