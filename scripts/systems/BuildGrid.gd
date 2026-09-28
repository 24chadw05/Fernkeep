extends Node2D

const TILE_SIZE   = 64
const MAP_SIZE    = 125
const DRAG_THRESHOLD = 8.0  # screen pixels before a press becomes a drag

var grid: Dictionary = {}

# Build-placement state
var is_build_mode: bool = false
var pending_building_id: String = ""
var pending_sprite_path: String = ""
var building_size: Vector2i = Vector2i(1, 1)
var hover_cell: Vector2i = Vector2i.ZERO

# Grid overlay (shown while build menu is open)
var grid_visible: bool = false

# True while the cursor is over UI (build menu bar etc.) — suspends the
# placement ghost and lets clicks through to the menu
var _mouse_on_ui: bool = false

# One-time toast explaining the double-click-to-place scheme
var _placement_hint_shown: bool = false

# Drag state
var drag_building: PlacedBuilding = null
var drag_original_origin: Vector2i
var drag_grab_offset: Vector2i   # cell grabbed, relative to building origin
var drag_press_screen: Vector2
var drag_confirmed: bool = false

# Road paint state
var is_road_mode: bool = false
var current_road_type: String = ""
var _last_road_warn: int = 0  # throttles the "not enough materials" toast while dragging
var _road_painting: bool = false  # true while left mouse held in road mode

# Road erase state
var is_road_erase_mode: bool = false
var _road_erasing: bool = false  # true while left mouse held in erase mode

# Colours
var grid_color:    Color = Color(0.35, 0.35, 0.35, 0.22)
var valid_color:   Color = Color(0.0,  1.0,  0.0,  0.30)
var invalid_color: Color = Color(1.0,  0.0,  0.0,  0.30)
var road_preview_color: Color = Color(0.60, 0.42, 0.18, 0.50)
var road_erase_color:   Color = Color(1.0,  0.15, 0.15, 0.55)

signal building_moved(building: PlacedBuilding, old_origin: Vector2i)

func _ready() -> void:
	SignalBus.open_build_menu.connect(func():
		grid_visible = true
		queue_redraw()
	)
	SignalBus.close_all_panels.connect(func():
		grid_visible = false
		queue_redraw()
	)
	SignalBus.build_menu_closed.connect(func():
		grid_visible = false
		queue_redraw()
	)
	SignalBus.cancel_road_mode_requested.connect(func():
		if is_road_mode:
			cancel_road_mode()
		elif is_road_erase_mode:
			cancel_road_erase_mode()
	)

# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	var show_overlay = grid_visible or is_build_mode or is_road_mode or is_road_erase_mode or (drag_building != null and drag_confirmed)
	if not show_overlay:
		return

	var view_size = get_viewport_rect().size
	var cam = get_viewport().get_camera_2d()
	if not cam:
		return

	var cam_pos = cam.get_screen_center_position()
	var zoom    = cam.zoom.x

	var start_x = int((cam_pos.x - view_size.x / zoom / 2.0) / TILE_SIZE) - 1
	var end_x   = int((cam_pos.x + view_size.x / zoom / 2.0) / TILE_SIZE) + 1
	var start_y = int((cam_pos.y - view_size.y / zoom / 2.0) / TILE_SIZE) - 1
	var end_y   = int((cam_pos.y + view_size.y / zoom / 2.0) / TILE_SIZE) + 1

	# Grey overlay on every buildable cell
	for x in range(start_x, end_x):
		for y in range(start_y, end_y):
			if not is_buildable(x, y):
				continue
			draw_rect(
				Rect2(Vector2(x * TILE_SIZE, y * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE)),
				grid_color, true
			)

	# Building placement preview (hidden while hovering the build menu)
	if is_build_mode and pending_building_id != "" and not _mouse_on_ui:
		var ok = is_footprint_valid(hover_cell, building_size)
		var has_road = not _placement_needs_road(pending_building_id) or RoadManager.has_road_in_front(hover_cell, building_size)
		var placement_ok = ok and has_road
		for dx in range(building_size.x):
			for dy in range(building_size.y):
				var cell = hover_cell + Vector2i(dx, dy)
				draw_rect(
					Rect2(Vector2(cell.x * TILE_SIZE, cell.y * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE)),
					valid_color if placement_ok else invalid_color, true
				)

	# Road paint preview
	if is_road_mode and not _mouse_on_ui:
		if not grid.has(hover_cell) and is_buildable(hover_cell.x, hover_cell.y):
			draw_rect(
				Rect2(Vector2(hover_cell.x * TILE_SIZE, hover_cell.y * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE)),
				road_preview_color, true
			)

	# Road erase preview
	if is_road_erase_mode and not _mouse_on_ui:
		if RoadManager and RoadManager.is_road(hover_cell):
			draw_rect(
				Rect2(Vector2(hover_cell.x * TILE_SIZE, hover_cell.y * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE)),
				road_erase_color, true
			)

	# Drag preview
	if drag_building != null and drag_confirmed:
		var bsize      = drag_building.get_size()
		var new_origin = hover_cell - drag_grab_offset
		var ok         = _is_footprint_valid_for_drag(new_origin, bsize, drag_building)
		for dx in range(bsize.x):
			for dy in range(bsize.y):
				var cell = new_origin + Vector2i(dx, dy)
				draw_rect(
					Rect2(Vector2(cell.x * TILE_SIZE, cell.y * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE)),
					valid_color if ok else invalid_color, true
				)

# ── Process ───────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if is_build_mode or is_road_mode or is_road_erase_mode or (drag_building != null and drag_confirmed):
		_mouse_on_ui = _is_mouse_over_ui()
		update_hover()
		queue_redraw()

# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# ── Road erase mode ──────────────────────────────────────────────────────
	if is_road_erase_mode:
		if event is InputEventMouseMotion:
			if _is_mouse_over_ui():
				_road_erasing = false  # stroke ends at the menu edge
				return
			update_hover()
			if _road_erasing:
				_erase_road_at_hover()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton:
			if _is_mouse_over_ui():
				_road_erasing = false
				return
			if event.button_index == MOUSE_BUTTON_RIGHT:
				cancel_road_erase_mode()
				get_viewport().set_input_as_handled()
				return
			if event.button_index == MOUSE_BUTTON_LEFT:
				_road_erasing = event.pressed
				if event.pressed:
					_erase_road_at_hover()
				get_viewport().set_input_as_handled()
				return
		return

	# ── Road paint mode ──────────────────────────────────────────────────────
	if is_road_mode:
		if event is InputEventMouseMotion:
			if _is_mouse_over_ui():
				_road_painting = false  # stroke ends at the menu edge
				return
			update_hover()
			if _road_painting:
				_paint_road_at_hover()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton:
			if _is_mouse_over_ui():
				_road_painting = false
				return
			if event.button_index == MOUSE_BUTTON_RIGHT:
				cancel_road_mode()
				get_viewport().set_input_as_handled()
				return
			if event.button_index == MOUSE_BUTTON_LEFT:
				_road_painting = event.pressed
				if event.pressed:
					_paint_road_at_hover()
				get_viewport().set_input_as_handled()
				return
		return

	# Track mouse movement to confirm a drag once threshold is exceeded
	if event is InputEventMouseMotion:
		if drag_building != null and not drag_confirmed:
			if grid_visible and (event.position as Vector2).distance_to(drag_press_screen) > DRAG_THRESHOLD:
				drag_confirmed = true
				_set_drag_node_opacity(0.35)
				get_viewport().set_input_as_handled()
		if drag_building != null and drag_confirmed:
			get_viewport().set_input_as_handled()  # block camera pan during drag
		return

	if not (event is InputEventMouseButton):
		return

	# ── Button released ──────────────────────────────────────────────────────
	if not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and drag_building != null:
			if drag_confirmed:
				_commit_drag()
				get_viewport().set_input_as_handled()
			else:
				# Short click — route to the right panel
				if drag_building.building_id == "town_hall":
					SignalBus.open_town_hall_panel.emit(drag_building)
				elif drag_building.building_id == "market":
					SignalBus.open_market_panel.emit(drag_building)
				elif drag_building.building_id == "magic_tower":
					SignalBus.open_magic_tower_panel.emit(drag_building)
				elif drag_building.building_id == "trade_port":
					SignalBus.open_trade_port_panel.emit(drag_building)
				elif drag_building.building_id == "guild_hall":
					SignalBus.open_guild_hall_panel.emit(drag_building)
				else:
					SignalBus.open_building_inspector.emit(drag_building)
				_reset_drag()
				# Don't consume — let camera receive the release to exit its drag state
		return

	# ── Button pressed ───────────────────────────────────────────────────────
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if drag_building != null:
			_reset_drag()
			get_viewport().set_input_as_handled()
		elif is_build_mode:
			cancel_placement()
			get_viewport().set_input_as_handled()
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if is_build_mode and pending_building_id != "":
		# Over the build menu the selection is suspended: the click falls
		# through so you can pick another card, switch tabs, or hit ✕
		if _is_mouse_over_ui():
			return
		# Double-click places; a single click falls through to the camera
		# so hold-and-drag pans the map while a building is selected
		if event.double_click and is_footprint_valid(hover_cell, building_size):
			_commit_placement()
			get_viewport().set_input_as_handled()
		return

	if not is_build_mode and drag_building == null:
		if _is_mouse_over_ui():
			return
		var cell = _mouse_to_cell()
		if grid.has(cell):
			var b = BuildingManager.get_building_by_id(grid[cell])
			if b:
				drag_building        = b
				drag_original_origin = b.grid_origin
				drag_grab_offset     = cell - b.grid_origin
				drag_press_screen    = event.position
				drag_confirmed       = false
				# Don't consume yet — wait to distinguish click from drag
		else:
			# Clicking empty ground dismisses any open panel (click-outside-to-close)
			SignalBus.close_all_panels.emit()

# ── Road mode ─────────────────────────────────────────────────────────────────

func start_road_mode(road_type: String) -> void:
	is_road_mode       = true
	current_road_type  = road_type
	_road_painting     = false
	SignalBus.build_mode_active = true
	SignalBus.road_mode_started.emit()
	queue_redraw()
	SignalBus.show_notification.emit("Click and drag to paint roads  •  Right-click to cancel")

func cancel_road_mode() -> void:
	is_road_mode       = false
	current_road_type  = ""
	_road_painting     = false
	SignalBus.build_mode_active = false
	SignalBus.road_mode_ended.emit()
	queue_redraw()

func start_road_erase_mode() -> void:
	is_road_erase_mode          = true
	_road_erasing               = false
	SignalBus.build_mode_active = true
	SignalBus.road_mode_started.emit()
	queue_redraw()
	SignalBus.show_notification.emit("Click and drag to erase roads  •  Right-click to cancel")

func cancel_road_erase_mode() -> void:
	is_road_erase_mode          = false
	_road_erasing               = false
	SignalBus.build_mode_active = false
	SignalBus.road_mode_ended.emit()
	queue_redraw()

func _erase_road_at_hover() -> void:
	if RoadManager and RoadManager.is_road(hover_cell):
		RoadManager.erase(hover_cell)

func _paint_road_at_hover() -> void:
	var cell := _mouse_to_cell()
	if not is_buildable(cell.x, cell.y):
		return
	if grid.has(cell):
		return  # don't paint over buildings
	if RoadManager.get_road_type_at(cell) == current_road_type:
		return  # already this exact road — no double charge
	# Paved roads cost materials per tile; skip (with a throttled toast) if broke
	var cost: Dictionary = RoadManager.get_road_cost(current_road_type)
	if not cost.is_empty():
		if not ResourceManager.can_afford_cost(cost):
			var now := Time.get_ticks_msec()
			if now - _last_road_warn > 1200:
				_last_road_warn = now
				var parts: Array = []
				for r in cost:
					parts.append("%d %s" % [int(cost[r]), ResourceManager.get_item_label(r)])
				SignalBus.show_notification_timed.emit(
					"Not enough materials — %s road needs %s per tile" % [
						current_road_type, ", ".join(PackedStringArray(parts))
					], 1.5)
			return
		ResourceManager.spend_cost(cost, "%s road" % current_road_type)
	RoadManager.paint(cell, current_road_type)

# ── Drag helpers ──────────────────────────────────────────────────────────────

func _commit_drag() -> void:
	var bsize      = drag_building.get_size()
	var new_origin = hover_cell - drag_grab_offset

	if _is_footprint_valid_for_drag(new_origin, bsize, drag_building):
		free_cells(drag_original_origin, bsize)
		occupy_cells(new_origin, bsize, drag_building.id)
		var old_origin          = drag_original_origin
		drag_building.grid_origin = new_origin
		emit_signal("building_moved", drag_building, old_origin)
		print("[BuildGrid] Moved %s to %s" % [drag_building.building_id, new_origin])
	else:
		print("[BuildGrid] Invalid drop — snapping back")

	_reset_drag()

func _reset_drag() -> void:
	if drag_building:
		_set_drag_node_opacity(1.0)
	drag_building  = null
	drag_confirmed = false
	queue_redraw()

func _set_drag_node_opacity(alpha: float) -> void:
	if not drag_building:
		return
	var node = get_parent().get_node_or_null("Buildings/" + drag_building.id)
	if node:
		node.modulate.a = alpha

func _is_footprint_valid_for_drag(origin: Vector2i, size: Vector2i, except: PlacedBuilding) -> bool:
	for dx in range(size.x):
		for dy in range(size.y):
			var cell = origin + Vector2i(dx, dy)
			if not is_buildable(cell.x, cell.y):
				return false
			if grid.has(cell) and grid[cell] != except.id:
				return false
	return true

func _mouse_to_cell() -> Vector2i:
	var mouse = get_global_mouse_position()
	return Vector2i(int(floor(mouse.x / TILE_SIZE)), int(floor(mouse.y / TILE_SIZE)))

# ── Placement ─────────────────────────────────────────────────────────────────

func start_placement(building_id: String, sprite_path: String = "") -> void:
	pending_building_id  = building_id
	pending_sprite_path  = sprite_path
	is_build_mode        = true
	SignalBus.build_mode_active = true
	var bdata    = DataManager.get_building(building_id)
	var size     = bdata.get("size", [1, 1])
	building_size = Vector2i(int(size[0]), int(size[1]))
	queue_redraw()
	if not _placement_hint_shown:
		_placement_hint_shown = true
		SignalBus.show_notification.emit("Double-click to place — hold and drag to move the camera")
	print("[BuildGrid] Placement started: %s (%dx%d)" % [building_id, building_size.x, building_size.y])

func cancel_placement() -> void:
	pending_building_id  = ""
	pending_sprite_path  = ""
	is_build_mode        = false
	SignalBus.build_mode_active = false
	queue_redraw()
	print("[BuildGrid] Placement cancelled.")

func cancel_all_modes() -> void:
	if is_build_mode:
		cancel_placement()
	if is_road_mode:
		cancel_road_mode()
	if is_road_erase_mode:
		cancel_road_erase_mode()

func toggle_build_mode() -> void:
	is_build_mode = not is_build_mode
	if not is_build_mode:
		pending_building_id = ""
	SignalBus.build_mode_active = is_build_mode
	queue_redraw()

func _placement_needs_road(building_id: String) -> bool:
	if building_id == "town_hall":
		return false
	return DataManager.get_building(building_id).get("needs_road", true)

func _commit_placement() -> void:
	# Buildings need a road in front; decor (needs_road=false) can go anywhere
	if _placement_needs_road(pending_building_id):
		if not RoadManager.has_road_in_front(hover_cell, building_size):
			SignalBus.show_notification.emit("A road must be placed in front of this building first!")
			return

	var placed = BuildingManager.place_building(pending_building_id, hover_cell, pending_sprite_path)
	if placed:
		occupy_cells(hover_cell, building_size, placed.id)
		print("[BuildGrid] Committed %s (%s) at %s" % [pending_building_id, placed.id, hover_cell])
	pending_building_id         = ""
	pending_sprite_path         = ""
	is_build_mode               = false
	SignalBus.build_mode_active = false
	queue_redraw()

func update_hover() -> void:
	var mouse = get_global_mouse_position()
	hover_cell = Vector2i(
		int(floor(mouse.x / TILE_SIZE)),
		int(floor(mouse.y / TILE_SIZE))
	)

# ── Grid data ─────────────────────────────────────────────────────────────────

func is_buildable(x: int, y: int) -> bool:
	return abs(x) <= MAP_SIZE and abs(y) <= MAP_SIZE

func is_footprint_valid(origin: Vector2i, size: Vector2i) -> bool:
	for dx in range(size.x):
		for dy in range(size.y):
			var cell = origin + Vector2i(dx, dy)
			if not is_buildable(cell.x, cell.y):
				return false
			if grid.has(cell):
				return false
	return true

func occupy_cells(origin: Vector2i, size: Vector2i, instance_id: String) -> void:
	for dx in range(size.x):
		for dy in range(size.y):
			grid[origin + Vector2i(dx, dy)] = instance_id

func free_cells(origin: Vector2i, size: Vector2i) -> void:
	for dx in range(size.x):
		for dy in range(size.y):
			grid.erase(origin + Vector2i(dx, dy))

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
