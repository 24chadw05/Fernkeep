extends Node2D

const TILE_SIZE: int = 64

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
	# Citizens live on the roads — start them on the nearest paved cell
	_snap_to_road()
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

# Citizens only ever walk the road network: each hop steps to a random
# adjacent road tile, so they stroll along the roads and never cross open grass.
func _pick_new_target() -> void:
	var cur := _world_to_cell(position)
	if not RoadManager.is_road(cur):
		var near = RoadManager.nearest_road_cell(cur)
		if near == null:
			target_pos = position  # no roads yet — stay put
		else:
			target_pos = _cell_center(near)
		return
	var neighbours: Array = RoadManager.road_neighbours(cur)
	if neighbours.is_empty():
		target_pos = position
		return
	target_pos = _cell_center(neighbours[randi() % neighbours.size()])

func _snap_to_road() -> void:
	var near = RoadManager.nearest_road_cell(_world_to_cell(position))
	if near != null:
		position = _cell_center(near)

func _world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE_SIZE)), int(floor(p.y / TILE_SIZE)))

func _cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * TILE_SIZE + TILE_SIZE / 2.0, c.y * TILE_SIZE + TILE_SIZE / 2.0)

func setup(npc: NPC) -> void:
	npc_data = npc
	if name_label:
		name_label.text = npc.first_name
	_apply_variant()
