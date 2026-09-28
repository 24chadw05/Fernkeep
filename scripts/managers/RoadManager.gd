extends Node

# road_cells: Vector2i cell → road_type String (e.g. "dirt")
var road_cells: Dictionary = {}

# Material cost to paint one cell of each road type. Dirt is free; the paved
# roads cost 5 of their namesake material per tile (charged in BuildGrid).
const ROAD_COSTS: Dictionary = {
	"dirt":  {},
	"stone": {"stone": 5},
	"wood":  {"wood": 5},
}

const _NEIGHBOUR_OFFSETS: Array = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

signal road_painted(cell: Vector2i, road_type: String)
signal road_erased(cell: Vector2i)
signal roads_loaded()

func paint(cell: Vector2i, road_type: String) -> void:
	if road_cells.get(cell) == road_type:
		return
	road_cells[cell] = road_type
	emit_signal("road_painted", cell, road_type)

func erase(cell: Vector2i) -> void:
	if not road_cells.has(cell):
		return
	road_cells.erase(cell)
	emit_signal("road_erased", cell)

func is_road(cell: Vector2i) -> bool:
	return road_cells.has(cell)

# Returns true if at least one cell in the row directly below the building footprint is a road.
func has_road_in_front(grid_origin: Vector2i, size: Vector2i) -> bool:
	var front_y: int = grid_origin.y + size.y
	for dx in range(size.x):
		if is_road(Vector2i(grid_origin.x + dx, front_y)):
			return true
	return false

func get_road_type_at(cell: Vector2i) -> String:
	return road_cells.get(cell, "")

# Material cost (Dictionary res_id → amount) to paint one tile of this road.
func get_road_cost(road_type: String) -> Dictionary:
	return ROAD_COSTS.get(road_type, {}).duplicate()

func has_roads() -> bool:
	return not road_cells.is_empty()

# ── Road-network queries (used to keep NPCs & travellers on the roads) ──────────

# The road cells directly adjacent (4-connected) to `cell`.
func road_neighbours(cell: Vector2i) -> Array:
	var result: Array = []
	for off in _NEIGHBOUR_OFFSETS:
		var n: Vector2i = cell + off
		if road_cells.has(n):
			result.append(n)
	return result

# Nearest road cell to `cell` (brute force — the network is small). null if none.
func nearest_road_cell(cell: Vector2i):
	if road_cells.is_empty():
		return null
	var best: Vector2i = Vector2i.ZERO
	var best_dist: float = INF
	for c in road_cells:
		var d: float = (Vector2(c) - Vector2(cell)).length_squared()
		if d < best_dist:
			best_dist = d
			best = c
	return best

func random_road_cell():
	if road_cells.is_empty():
		return null
	var keys: Array = road_cells.keys()
	return keys[randi() % keys.size()]

# ── Save / Load / Reset ────────────────────────────────────────────────────────

# Wipe the network without emitting road_erased per cell — the caller (a new game
# or a prestige) tears down the road visuals wholesale anyway.
func reset() -> void:
	road_cells.clear()
	emit_signal("roads_loaded")

func to_dict() -> Dictionary:
	var result: Dictionary = {}
	for cell in road_cells:
		result["%d,%d" % [cell.x, cell.y]] = road_cells[cell]
	return result

func from_dict(data: Dictionary) -> void:
	road_cells.clear()
	for key in data:
		var parts: PackedStringArray = key.split(",")
		if parts.size() == 2:
			var cell := Vector2i(int(parts[0]), int(parts[1]))
			road_cells[cell] = str(data[key])
	emit_signal("roads_loaded")
