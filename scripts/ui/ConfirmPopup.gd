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

	# Outer panel — fit inside whatever we're parented to. Full-screen parents
	# get the wide two-column layout; the narrow BuildingInspector column gets
	# a stacked vertical one that stays on screen.
	var narrow := size.x < 720.0
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(1000.0, size.x - 20.0), 0)
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
	title_lbl.add_theme_font_size_override("font_size", 28 if narrow else 32)
	title_lbl.add_theme_color_override("font_color", Color(0.39, 0.35, 0.16))
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title_lbl)
	vbox.add_child(_sep())

	# Content rows
	for row: Dictionary in rows:
		match row.get("type", "row"):
			"header":
				var lbl := Label.new()
				lbl.text = row.get("text", "")
				lbl.add_theme_font_size_override("font_size", 22)
				lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
				vbox.add_child(lbl)
			"row":
				vbox.add_child(_make_row(row, narrow))
			"note":
				var lbl := Label.new()
				lbl.text = row.get("text", "")
				lbl.add_theme_font_size_override("font_size", 24)
				lbl.add_theme_color_override("font_color", Color(0.24, 0.28, 0.39))
				lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				vbox.add_child(lbl)
			"unlock":
				var lbl := Label.new()
				lbl.text = "✦  " + row.get("text", "")
				lbl.add_theme_font_size_override("font_size", 24)
				lbl.add_theme_color_override("font_color", Color(0.09, 0.43, 0.24))
				lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				vbox.add_child(lbl)
			"cost":
				var lbl := Label.new()
				lbl.text = row.get("text", "")
				lbl.add_theme_font_size_override("font_size", 26)
				lbl.add_theme_color_override("font_color", Color(0.41, 0.27, 0.04))
				lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				vbox.add_child(lbl)

	vbox.add_child(_sep())

	# Buttons — side by side when wide, stacked full-width when narrow
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel)

	var confirm_btn := Button.new()
	confirm_btn.text = confirm_label
	confirm_btn.add_theme_font_size_override("font_size", 28)
	confirm_btn.add_theme_color_override("font_color", Color(0.03, 0.41, 0.14))
	confirm_btn.pressed.connect(_on_confirm_pressed)

	if narrow:
		var btn_col := VBoxContainer.new()
		btn_col.add_theme_constant_override("separation", 10)
		confirm_btn.custom_minimum_size = Vector2(0, 72)
		cancel_btn.custom_minimum_size = Vector2(0, 64)
		btn_col.add_child(confirm_btn)
		btn_col.add_child(cancel_btn)
		vbox.add_child(btn_col)
	else:
		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 12)
		btn_row.alignment = BoxContainer.ALIGNMENT_END
		cancel_btn.custom_minimum_size = Vector2(200, 80)
		confirm_btn.custom_minimum_size = Vector2(320, 80)
		btn_row.add_child(cancel_btn)
		btn_row.add_child(confirm_btn)
		vbox.add_child(btn_row)

func _make_row(row: Dictionary, narrow: bool = false) -> Container:
	# Narrow: label on its own line, "old → new" underneath
	if narrow:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)

		var label_top := Label.new()
		label_top.text = row.get("label", "")
		label_top.add_theme_font_size_override("font_size", 24)
		label_top.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(label_top)

		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.add_child(_value_label(row.get("old", ""), Color(0.4, 0.29, 0.18), 24))
		var arr := Label.new()
		arr.text = "→"
		arr.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		line.add_child(arr)
		line.add_child(_value_label(row.get("new", ""), _highlight_color(row), 24))
		col.add_child(line)
		return col

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)

	var label_lbl := Label.new()
	label_lbl.text = row.get("label", "")
	label_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_lbl.add_theme_font_size_override("font_size", 26)
	hbox.add_child(label_lbl)

	var old_lbl := _value_label(row.get("old", ""), Color(0.4, 0.29, 0.18), 26)
	old_lbl.custom_minimum_size = Vector2(220, 0)
	old_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(old_lbl)

	var arrow := Label.new()
	arrow.text = "→"
	arrow.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	hbox.add_child(arrow)

	var new_lbl := _value_label(row.get("new", ""), _highlight_color(row), 26)
	new_lbl.custom_minimum_size = Vector2(220, 0)
	hbox.add_child(new_lbl)

	return hbox

func _value_label(text: String, color: Color, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl

func _highlight_color(row: Dictionary) -> Color:
	match int(row.get("highlight", 0)):
		1:  return Color(0.05, 0.43, 0.14)
		-1: return Color(0.42, 0.09, 0.09)
		_:  return Color(0.43, 0.4, 0.19)

func _sep() -> HSeparator:
	var s := HSeparator.new()
	s.custom_minimum_size = Vector2(0, 8)
	return s

func _on_confirm_pressed() -> void:
	visible = false
	if _on_confirm.is_valid():
		_on_confirm.call()

func _on_cancel() -> void:
	visible = false
