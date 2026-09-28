extends Control

func _ready() -> void:
	visible = false
	$Center/Panel/Margin/VBox/ResumeButton.pressed.connect(_close)
	$Center/Panel/Margin/VBox/SaveButton.pressed.connect(_on_save)
	$Center/Panel/Margin/VBox/NewSaveButton.pressed.connect(_on_new_save)
	$Center/Panel/Margin/VBox/SettingsButton.pressed.connect(_on_settings)
	$Center/Panel/Margin/VBox/QuitButton.pressed.connect(_on_quit)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if visible:
			_close()
		elif _any_panel_open() or SignalBus.build_mode_active:
			# First ESC closes whatever is open (panels, build/road modes);
			# a second ESC brings up the pause menu
			SignalBus.cancel_road_mode_requested.emit()
			SignalBus.close_all_panels.emit()
		else:
			_open()
		get_viewport().set_input_as_handled()

func _any_panel_open() -> bool:
	for sibling in get_parent().get_children():
		if sibling == self:
			continue
		if sibling is Control and sibling.visible:
			return true
	return false

func _open() -> void:
	visible = true

func _close() -> void:
	visible = false

func _on_save() -> void:
	SaveManager.save()  # the HUD Save button flashes on SaveManager.saved

func _on_new_save() -> void:
	var panel = get_node_or_null("../SaveSlotsPanel")
	if panel:
		panel.open()

func _on_settings() -> void:
	var panel = get_node_or_null("../SettingsPanel")
	if panel:
		panel.open()

func _on_quit() -> void:
	SaveManager.save()
	get_tree().quit()
