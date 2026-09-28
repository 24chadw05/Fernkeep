extends CanvasLayer

# Draws the tutorial: a coach card across the top of the screen and a pulsing
# frame around the control the current step is about. Everything here ignores
# the mouse except the card's own buttons, so the game stays fully playable
# underneath — the player does each step for real.

const GOLD := Color(0.95, 0.76, 0.25)

var _card: PanelContainer
var _title: Label
var _text: Label
var _counter: Label
var _next_btn: Button
var _frame: Panel
var _target: Control = null

func _ready() -> void:
	layer = 100   # above panels, below the urgent toast (128)

	_frame = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(6)
	sb.border_color = GOLD
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(GOLD, 0.5)
	sb.shadow_size = 10
	_frame.add_theme_stylebox_override("panel", sb)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.visible = false
	add_child(_frame)
	var pulse := create_tween().set_loops()
	pulse.tween_property(_frame, "modulate:a", 0.35, 0.6).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_frame, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)

	_card = PanelContainer.new()
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.offset_left = -390.0
	_card.offset_right = 390.0
	_card.offset_top = 20.0
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 20)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 32)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_counter = Label.new()
	_counter.add_theme_font_size_override("font_size", 20)
	_counter.add_theme_color_override("font_color", Color(0.42, 0.33, 0.22))
	head.add_child(_counter)
	v.add_child(head)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 24)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_text)
	var buttons := HBoxContainer.new()
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skip := Button.new()
	skip.text = "Skip tutorial"
	skip.flat = true
	skip.add_theme_font_size_override("font_size", 20)
	skip.pressed.connect(func(): TutorialManager.skip())
	buttons.add_child(skip)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.add_child(spacer)
	_next_btn = Button.new()
	_next_btn.custom_minimum_size = Vector2(220, 60)
	_next_btn.add_theme_font_size_override("font_size", 26)
	_next_btn.pressed.connect(func(): TutorialManager.advance())
	buttons.add_child(_next_btn)
	v.add_child(buttons)

	for lbl in [_title, _text, _counter]:
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	TutorialManager.step_changed.connect(_show_step)
	TutorialManager.finished.connect(_hide)
	if TutorialManager.active:
		_show_step(TutorialManager.step)
	else:
		_hide()

func _show_step(index: int) -> void:
	var s: Dictionary = TutorialManager.STEPS[index]
	_title.text = str(s.get("title", ""))
	_text.text = str(s.get("text", ""))
	_counter.text = "%d / %d" % [index + 1, TutorialManager.STEPS.size()]
	_next_btn.visible = s.get("next", false)
	_next_btn.text = str(s.get("button", "Next"))
	var path := str(s.get("target", ""))
	_target = null
	if path != "" and get_tree().current_scene:
		_target = get_tree().current_scene.get_node_or_null(path) as Control
	_card.visible = true
	# a small "pop" so the player notices the card changed
	_card.pivot_offset = Vector2(390, 0)
	_card.scale = Vector2(0.96, 0.96)
	create_tween().tween_property(_card, "scale", Vector2.ONE, 0.15)
	AudioManager.play("notify", 0.0, 0)

func _hide() -> void:
	_card.visible = false
	_frame.visible = false
	_target = null

func _process(_delta: float) -> void:
	# Follow the target every frame: panels open, the HUD reflows, etc.
	if _target == null or not is_instance_valid(_target) or not _target.is_visible_in_tree():
		_frame.visible = false
		return
	var r := _target.get_global_rect().grow(10.0)
	_frame.position = r.position
	_frame.size = r.size
	_frame.visible = true
