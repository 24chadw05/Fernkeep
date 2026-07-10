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
		else:
			_open()
		get_viewport().set_input_as_handled()

func _open() -> void:
	visible = true

func _close() -> void:
	visible = false

func _on_save() -> void:
	SaveManager.save()
	SignalBus.show_notification.emit("Game saved.")

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
