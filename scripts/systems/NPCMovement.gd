extends Node2D

var speed: float = 25.0
var wander_radius: float = 300.0
var target_pos: Vector2 = Vector2.ZERO
var wait_timer: float = 0.0
var is_waiting: bool = false

var npc_data: NPC = null

const VILLAGER_VARIANTS: int = 6

@onready var name_label: Label = $NameLabel
@onready var sprite: Sprite2D = $Sprite

func _ready() -> void:
	target_pos = position
	_pick_new_target()
	if npc_data and name_label:
		name_label.text = npc_data.first_name
	_apply_variant()

# Each citizen gets a stable villager look derived from their id
func _apply_variant() -> void:
	if npc_data == null or sprite == null:
		return
	var idx = (absi(npc_data.id.hash()) % VILLAGER_VARIANTS) + 1
	var tex: Texture2D = load("res://assets/sprites/villager_%d.png" % idx)
	if tex:
		sprite.texture = tex

func _process(delta: float) -> void:
	if is_waiting:
		wait_timer -= delta
		if wait_timer <= 0.0:
			is_waiting = false
			_pick_new_target()
		return

	var dir = target_pos - position
	if dir.length() < 5.0:
		is_waiting = true
		wait_timer = randf_range(2.0, 5.0)
		return

	position += dir.normalized() * speed * delta

	# Flip sprite based on direction
	if sprite:
		sprite.flip_h = dir.x < 0

func _pick_new_target() -> void:
	var offset = Vector2(
		randf_range(-wander_radius, wander_radius),
		randf_range(-wander_radius, wander_radius)
	)
	target_pos = position + offset

func setup(npc: NPC) -> void:
	npc_data = npc
	if name_label:
		name_label.text = npc.first_name
	_apply_variant()
