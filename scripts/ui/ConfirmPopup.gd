extends Control
class_name ConfirmPopup

# Usage:
#   var popup = ConfirmPopup.new()
#   add_child(popup)
#   popup.open("Title", rows, "Confirm Label", func(): do_thing())
#
# Row types:
#   {"type": "header",  "text": "SECTION"}
#   {"type": "row",     "label": "...", "old": "...", "new": "...", "highlight": 1/-1/0}
#   {"type": "note",    "text": "..."}
#   {"type": "unlock",  "text": "..."}
#   {"type": "cost",    "text": "..."}

var _on_confirm: Callable = Callable()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func open(title: String, rows: Array, confirm_label: String, on_confirm: Callable) -> void:
	_on_confirm = on_confirm
	_clear()
	_build(title, rows, confirm_label)
	visible = true

func _clear() -> void:
	for c in get_children():
		remove_child(c)
		c.free()

func _build(title: String, rows: Array, confirm_label: String) -> void:
	# Dim overlay
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# Center container
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# Outer panel
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 20 if side.ends_with("top") or side.ends_with("bottom") else 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Title
	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	vbox.add_child(title_lbl)
	vbox.add_child(_sep())

	# Content rows
	for row: Dictionary in rows:
		match row.get("type", "row"):
			"header":
				var lbl := Label.new()
				lbl.text = row.get("text", "")
				lbl.add_theme_font_size_override("font_size", 11)
				lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
				vbox.add_child(lbl)
			"row":
				vbox.add_child(_make_row(row))
			"note":
				var lbl := Label.new()
				lbl.text = row.get("text", "")
				lbl.add_theme_font_size_override("font_size", 12)
				lbl.add_theme_color_override("font_color", Color(0.72, 0.80, 1.0))
				lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				vbox.add_child(lbl)
			"unlock":
				var lbl := Label.new()
				lbl.text = "✦  " + row.get("text", "")
				lbl.add_theme_font_size_override("font_size", 12)
				lbl.add_theme_color_override("font_color", Color(0.35, 0.90, 0.60))
				lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				vbox.add_child(lbl)
			"cost":
				var lbl := Label.new()
				lbl.text = row.get("text", "")
				lbl.add_theme_font_size_override("font_size", 13)
				lbl.add_theme_color_override("font_color", Color(0.95, 0.70, 0.28))
				vbox.add_child(lbl)

	vbox.add_child(_sep())

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_END

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 40)
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = confirm_label
	confirm_btn.custom_minimum_size = Vector2(160, 40)
	confirm_btn.add_theme_font_size_override("font_size", 14)
	confirm_btn.add_theme_color_override("font_color", Color(0.25, 0.95, 0.45))
	confirm_btn.pressed.connect(_on_confirm_pressed)
	btn_row.add_child(confirm_btn)

	vbox.add_child(btn_row)

func _make_row(row: Dictionary) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)

	var label_lbl := Label.new()
	label_lbl.text = row.get("label", "")
	label_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_lbl.add_theme_font_size_override("font_size", 13)
	hbox.add_child(label_lbl)

	var old_lbl := Label.new()
	old_lbl.text = row.get("old", "")
	old_lbl.custom_minimum_size = Vector2(110, 0)
	old_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	old_lbl.add_theme_font_size_override("font_size", 13)
	old_lbl.add_theme_color_override("font_color", Color(0.60, 0.60, 0.60))
	hbox.add_child(old_lbl)

	var arrow := Label.new()
	arrow.text = "→"
	arrow.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	hbox.add_child(arrow)

	var new_lbl := Label.new()
	new_lbl.text = row.get("new", "")
	new_lbl.custom_minimum_size = Vector2(110, 0)
	new_lbl.add_theme_font_size_override("font_size", 13)
	match int(row.get("highlight", 0)):
		1:  new_lbl.add_theme_color_override("font_color", Color(0.28, 0.90, 0.42))
		-1: new_lbl.add_theme_color_override("font_color", Color(0.92, 0.35, 0.35))
		_:  new_lbl.add_theme_color_override("font_color", Color(0.90, 0.85, 0.52))
	hbox.add_child(new_lbl)

	return hbox

func _sep() -> HSeparator:
	var s := HSeparator.new()
	s.custom_minimum_size = Vector2(0, 4)
	return s

func _on_confirm_pressed() -> void:
	visible = false
	if _on_confirm.is_valid():
		_on_confirm.call()

func _on_cancel() -> void:
	visible = false
