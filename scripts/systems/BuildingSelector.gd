extends Node
# Dedicated building click handler. Deliberately separate from GameManager.
# Uses _input() so it fires at higher priority than _unhandled_input, and does
# its own screen→world transform rather than relying on physics picking (Area2D
# _input_event) which is unreliable with Camera2D zoom in Godot 4.

func _input(event: InputEvent) -> void:
	if SignalBus.build_mode_active:
		return
	if not (event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed):
		return
	if _is_mouse_over_ui():
		return

	# Explicit canvas transform: maps screen/viewport coords → world coords.
	# This is correct regardless of Camera2D zoom or pan.
	var vp       := get_viewport()
	var world_pos: Vector2 = vp.get_canvas_transform().affine_inverse() * vp.get_mouse_position()

	print("[BuildingSelector] click | world=%s | buildings=%d" % [
		world_pos, BuildingManager.placed_buildings.size()])

	for building: PlacedBuilding in BuildingManager.placed_buildings:
		var origin := Vector2(building.grid_origin.x, building.grid_origin.y) * 64.0
		var bsize: Vector2i = building.get_size()
		var bounds := Rect2(origin, Vector2(bsize.x, bsize.y) * 64.0)

		if bounds.has_point(world_pos):
			print("[BuildingSelector] hit: %s at %s" % [building.building_id, origin])
			vp.set_input_as_handled()
			SignalBus.open_building_inspector.emit(building)
			return

	print("[BuildingSelector] no hit")

func _is_mouse_over_ui() -> bool:
	var ctrl = get_viewport().gui_get_hovered_control()
	if ctrl == null:
		return false
	var node: Node = ctrl.get_parent()
	while node:
		if node is CanvasLayer:
			return true
		node = node.get_parent()
	return false
