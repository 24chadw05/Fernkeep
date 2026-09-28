extends Camera2D

var is_dragging = false
var min_zoom = 0.3
var max_zoom = 4.0
var map_limit = (125 + 25) * 64

func _ready():
	# SaveManager finds the camera through this group when writing a save, and
	# hands the saved view back through game_loaded.
	add_to_group("save_camera")
	SaveManager.game_loaded.connect(_apply_saved_view)

func _apply_saved_view():
	var st: Dictionary = SaveManager.camera_state
	if st.is_empty():
		return
	position = Vector2(float(st.get("x", position.x)), float(st.get("y", position.y)))
	var z = clamp(float(st.get("zoom", zoom.x)), min_zoom, max_zoom)
	zoom = Vector2(z, z)

func _process(_delta):
	clamp_position()

func _unhandled_input(event):
	# Wheel and trackpad scrolls that a menu didn't use up (a list already at its
	# end, a pan gesture over a panel) still arrive here. Zooming the map while
	# the pointer is over a window made scrolling menus "zoom like crazy", so the
	# camera only reacts when the pointer is over the map itself — windows own
	# the scroll wheel.
	var over_ui := _pointer_over_ui()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Only start dragging on the map; any release ends the drag.
			is_dragging = event.pressed and not over_ui
		elif not over_ui:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_camera(1.1)
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_camera(0.9)
	if event is InputEventMouseMotion and is_dragging:
		# A release that landed on a window is swallowed by that window, which
		# used to leave the camera stuck dragging; trust the live button state.
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			is_dragging = false
		else:
			position -= event.relative / zoom.x
	if event is InputEventScreenDrag and not over_ui:
		position -= event.relative / zoom.x
	if event is InputEventMagnifyGesture and not over_ui:
		zoom_camera(event.factor)
	if event is InputEventPanGesture and not over_ui:
		# Two-finger trackpad scroll zooms (wheel events cover real mice)
		zoom_camera(1.0 - event.delta.y * 0.05)

func _pointer_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

func zoom_camera(factor: float):
	var new_zoom = clamp(zoom.x * factor, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)

func clamp_position():
	var half_w = (get_viewport_rect().size.x / 2) / zoom.x
	var half_h = (get_viewport_rect().size.y / 2) / zoom.x
	position.x = clamp(position.x, -map_limit + half_w, map_limit - half_w)
	position.y = clamp(position.y, -map_limit + half_h, map_limit - half_h)
