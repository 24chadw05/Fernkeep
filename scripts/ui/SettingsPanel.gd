extends Control

@onready var autosave_btn: CheckButton = $Center/Panel/Margin/VBox/AutosaveRow/AutosaveToggle
@onready var res_option: OptionButton  = $Center/Panel/Margin/VBox/ResolutionRow/ResolutionOption
@onready var music_slider: HSlider = $Center/Panel/Margin/VBox/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $Center/Panel/Margin/VBox/SfxRow/SfxSlider

func _ready() -> void:
	visible = false
	$Center/Panel/Margin/VBox/Header/CloseButton.pressed.connect(close)
	$Center/Panel/Margin/VBox/ApplyButton.pressed.connect(_on_apply)

	# Populate resolution options
	res_option.add_item("1920 × 1080  (1080p)", 0)
	res_option.add_item("2560 × 1440  (1440p)", 1)
	res_option.add_item("1280 × 720   (720p)",  2)

	# Volume applies and saves as the slider moves, so the player hears the
	# change immediately rather than after pressing Apply.
	music_slider.value_changed.connect(func(v): _set_volume("music_volume", v))
	sfx_slider.value_changed.connect(func(v):
		_set_volume("sfx_volume", v)
		AudioManager.play("click", 0.0, 120)   # a sample of the new level
	)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func open() -> void:
	# Sync controls to current settings
	autosave_btn.button_pressed = SaveManager.settings.get("autosave", true)
	music_slider.set_value_no_signal(float(SaveManager.settings.get("music_volume", 0.6)))
	sfx_slider.set_value_no_signal(float(SaveManager.settings.get("sfx_volume", 0.8)))
	var res = SaveManager.settings.get("resolution", "1920x1080")
	match res:
		"2560x1440": res_option.selected = 1
		"1280x720":  res_option.selected = 2
		_:           res_option.selected = 0
	visible = true

func _set_volume(key: String, value: float) -> void:
	SaveManager.settings[key] = value
	SaveManager.save_settings()
	AudioManager.apply_volumes()

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
