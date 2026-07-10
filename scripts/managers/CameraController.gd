extends Camera2D

var is_dragging = false
var min_zoom = 0.3
var max_zoom = 4.0
var map_limit = (125 + 25) * 64

func _process(_delta):
	clamp_position()

func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.pressed
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_camera(1.1)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_camera(0.9)
	if event is InputEventMouseMotion and is_dragging:
		position -= event.relative / zoom.x
	if event is InputEventScreenDrag:
		position -= event.relative / zoom.x
	if event is InputEventMagnifyGesture:
		zoom_camera(event.factor)

func zoom_camera(factor: float):
	var new_zoom = clamp(zoom.x * factor, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)

func clamp_position():
	var half_w = (get_viewport_rect().size.x / 2) / zoom.x
	var half_h = (get_viewport_rect().size.y / 2) / zoom.x
	position.x = clamp(position.x, -map_limit + half_w, map_limit - half_w)
	position.y = clamp(position.y, -map_limit + half_h, map_limit - half_h)
