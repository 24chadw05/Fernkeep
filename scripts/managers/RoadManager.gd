extends Node

# road_cells: Vector2i cell → road_type String (e.g. "dirt")
var road_cells: Dictionary = {}

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

# ── Save / Load ────────────────────────────────────────────────────────────────

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
