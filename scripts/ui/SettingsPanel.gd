extends Control

@onready var autosave_btn: CheckButton = $Center/Panel/Margin/VBox/AutosaveRow/AutosaveToggle
@onready var res_option: OptionButton  = $Center/Panel/Margin/VBox/ResolutionRow/ResolutionOption

func _ready() -> void:
	visible = false
	$Center/Panel/Margin/VBox/Header/CloseButton.pressed.connect(close)
	$Center/Panel/Margin/VBox/ApplyButton.pressed.connect(_on_apply)

	# Populate resolution options
	res_option.add_item("1920 × 1080  (1080p)", 0)
	res_option.add_item("2560 × 1440  (1440p)", 1)
	res_option.add_item("1280 × 720   (720p)",  2)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func open() -> void:
	# Sync controls to current settings
	autosave_btn.button_pressed = SaveManager.settings.get("autosave", true)
	var res = SaveManager.settings.get("resolution", "1920x1080")
	match res:
		"2560x1440": res_option.selected = 1
		"1280x720":  res_option.selected = 2
		_:           res_option.selected = 0
	visible = true

func close() -> void:
	visible = false

func _on_apply() -> void:
	SaveManager.settings["autosave"] = autosave_btn.button_pressed
	match res_option.selected:
		1: SaveManager.settings["resolution"] = "2560x1440"
		2: SaveManager.settings["resolution"] = "1280x720"
		_: SaveManager.settings["resolution"] = "1920x1080"
	SaveManager.save_settings()
	SaveManager.apply_resolution()
	close()
