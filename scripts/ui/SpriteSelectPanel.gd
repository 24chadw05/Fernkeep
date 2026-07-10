extends Control

signal sprite_selected(building_id: String, sprite_path: String)

const HIDDEN_X: float = -240.0
const SHOWN_X:  float = 252.0

var _building_id: String = ""

@onready var title_label: Label  = $Panel/TitleLabel
@onready var vbox: VBoxContainer = $Panel/ScrollContainer/VBox
@onready var close_btn: Button   = $Panel/CloseButton

func _ready() -> void:
	position.x = HIDDEN_X
	visible    = false
	close_btn.pressed.connect(_slide_out)
	SignalBus.close_all_panels.connect(_slide_out)

func show_for_building(building_id: String, variants: Array) -> void:
	_building_id = building_id

	for child in vbox.get_children():
		child.queue_free()

	var data = DataManager.get_building(building_id)
	title_label.text = data.get("name", building_id)

	for variant in variants:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(0, 82)
		btn.alignment           = HORIZONTAL_ALIGNMENT_LEFT
		btn.text                = "  " + variant["label"]
		btn.add_theme_constant_override("icon_max_width", 68)
		btn.expand_icon = true
		if ResourceLoader.exists(variant["path"]):
			btn.icon = load(variant["path"])
		var path: String = variant["path"]
		btn.pressed.connect(func(): _on_sprite_chosen(path))
		vbox.add_child(btn)

	_slide_in()

func _on_sprite_chosen(sprite_path: String) -> void:
	emit_signal("sprite_selected", _building_id, sprite_path)
	_slide_out()

func _slide_in() -> void:
	position.x = HIDDEN_X
	visible = true
	var tween = create_tween()
	tween.tween_property(self, "position:x", SHOWN_X, 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _slide_out() -> void:
	if not visible:
		return
	var tween = create_tween()
	tween.tween_property(self, "position:x", HIDDEN_X, 0.14) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(func(): visible = false)
