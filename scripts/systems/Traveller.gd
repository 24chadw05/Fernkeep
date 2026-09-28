extends Node2D

# A passing traveller from far-off lands — a horse-drawn carriage, a horse
# rider, or someone leading a horse on a leash. They are NOT citizens: they
# roam the road network for a while, then leave town again. Spawned by
# GameManager in numbers that scale with the city's reputation.

const TILE_SIZE: int = 64

# type → the two walk frames that get cycled for a simple animation
const TYPE_FRAMES: Dictionary = {
	"carriage": ["res://assets/sprites/travellers/carriage_1.png", "res://assets/sprites/travellers/carriage_2.png"],
	"rider":    ["res://assets/sprites/travellers/rider_1.png",    "res://assets/sprites/travellers/rider_2.png"],
	"leash":    ["res://assets/sprites/travellers/leash_1.png",    "res://assets/sprites/travellers/leash_2.png"],
}
const TYPES: Array = ["carriage", "rider", "leash"]

var speed: float = 40.0
var target_pos: Vector2 = Vector2.ZERO
var wait_timer: float = 0.0
var is_waiting: bool = false

var traveller_type: String = "rider"
var _frames: Array = []
var _frame_idx: int = 0
var _frame_timer: float = 0.0
const FRAME_TIME: float = 0.35

# Travellers pass through — after their visit they wander off and despawn.
var lifetime: float = 45.0
var _leaving: bool = false

@onready var sprite: Sprite2D = $Sprite

func setup(type: String = "") -> void:
	traveller_type = type if type in TYPES else TYPES[randi() % TYPES.size()]
	lifetime = randf_range(35.0, 70.0)

func _ready() -> void:
	if traveller_type not in TYPES:
		traveller_type = TYPES[randi() % TYPES.size()]
	for path in TYPE_FRAMES[traveller_type]:
		var tex: Texture2D = load(path)
		if tex:
			_frames.append(tex)
	if sprite and not _frames.is_empty():
		sprite.texture = _frames[0]
	target_pos = position
	_pick_new_target()

func _process(delta: float) -> void:
	# Frame animation (rotates between the type's pictures)
	if _frames.size() > 1:
		_frame_timer += delta
		if _frame_timer >= FRAME_TIME:
			_frame_timer = 0.0
			_frame_idx = (_frame_idx + 1) % _frames.size()
			if sprite:
				sprite.texture = _frames[_frame_idx]

	# Fade out and leave once the visit is over
	lifetime -= delta
	if lifetime <= 0.0:
		_leaving = true
		modulate.a = maxf(modulate.a - delta * 0.8, 0.0)
		if modulate.a <= 0.05:
			queue_free()
			return

	if is_waiting:
		wait_timer -= delta
		if wait_timer <= 0.0:
			is_waiting = false
			_pick_new_target()
		return

	var dir := target_pos - position
	if dir.length() < 6.0:
		is_waiting = true
		wait_timer = randf_range(0.4, 1.6)
		return

	position += dir.normalized() * speed * delta
	if sprite and absf(dir.x) > 1.0:
		sprite.flip_h = dir.x < 0

# Travellers keep to the roads, hopping road tile to road tile.
func _pick_new_target() -> void:
	var cur := _world_to_cell(position)
	if not RoadManager.is_road(cur):
		var near = RoadManager.nearest_road_cell(cur)
		target_pos = position if near == null else _cell_center(near)
		return
	var neighbours: Array = RoadManager.road_neighbours(cur)
	if neighbours.is_empty():
		target_pos = position
		return
	target_pos = _cell_center(neighbours[randi() % neighbours.size()])

func _world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE_SIZE)), int(floor(p.y / TILE_SIZE)))

func _cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * TILE_SIZE + TILE_SIZE / 2.0, c.y * TILE_SIZE + TILE_SIZE / 2.0)
