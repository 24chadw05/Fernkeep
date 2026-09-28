extends Control

func _ready() -> void:
	visible = false
	$Center/Panel/Margin/VBox/Header/CloseButton.pressed.connect(close)
	_build_slots()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func open() -> void:
	_build_slots()
	visible = true

func close() -> void:
	visible = false

func _build_slots() -> void:
	var container = $Center/Panel/Margin/VBox/Slots
	for child in container.get_children():
		child.queue_free()

	for i in range(1, SaveManager.SLOT_COUNT + 1):
		var info = SaveManager.get_slot_info(i)
		var row = _make_slot_row(i, info)
		container.add_child(row)

func _make_slot_row(slot: int, info: Dictionary) -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 160)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)

	# Name / info column
	var info_col = VBoxContainer.new()
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_col)

	var name_edit = LineEdit.new()
	name_edit.placeholder_text = "Slot %d" % slot
	name_edit.text = info.get("name", "Slot %d" % slot) if info["exists"] else ""
	name_edit.custom_minimum_size = Vector2(0, 60)
	name_edit.text_changed.connect(func(t): SaveManager.set_slot_name(slot, t))
	info_col.add_child(name_edit)

	var ts_label = Label.new()
	ts_label.add_theme_font_size_override("font_size", 22)
	if info["exists"]:
		ts_label.text = info.get("timestamp", "")
		ts_label.add_theme_color_override("font_color", Color(0.37, 0.27, 0.17))
	else:
		ts_label.text = "Empty"
		ts_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	info_col.add_child(ts_label)

	# Buttons
	var btn_col = VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", 4)
	hbox.add_child(btn_col)

	var launch_btn = Button.new()
	launch_btn.text = "Launch"
	launch_btn.custom_minimum_size = Vector2(160, 0)
	launch_btn.pressed.connect(func(): _launch(slot, name_edit.text))
	btn_col.add_child(launch_btn)

	var del_btn = Button.new()
	del_btn.text = "Delete"
	del_btn.custom_minimum_size = Vector2(160, 0)
	del_btn.disabled = not info["exists"]
	del_btn.pressed.connect(func(): _delete(slot))
	btn_col.add_child(del_btn)

	return panel

func _launch(slot: int, name_text: String) -> void:
	# Bank the city that's running now before leaving it. Switching slots reloads
	# the scene, and anything since the last autosave (up to 5 minutes) was lost.
	SaveManager.save()

	if SaveManager.has_save(slot) and name_text.strip_edges() != "":
		SaveManager.set_slot_name(slot, name_text.strip_edges())

	SaveManager.active_slot = slot
	SaveManager.settings["last_slot"] = slot
	SaveManager.save_settings()
	SaveManager.pending_new_game = not SaveManager.has_save(slot)
	get_tree().reload_current_scene()

func _delete(slot: int) -> void:
	SaveManager.delete_slot(slot)
	_build_slots()
