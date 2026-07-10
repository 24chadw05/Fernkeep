extends CanvasLayer

@onready var gold_label: Label = $Panel/VBox/GoldLabel
@onready var level_label: Label = $Panel/VBox/LevelLabel
@onready var happiness_label: Label = $Panel/VBox/HappinessLabel
@onready var citizens_label: Label = $Panel/VBox/CitizensLabel
@onready var time_label: Label = $Panel/VBox/TimeLabel
@onready var wood_label: Label = $Panel/VBox/Resources/WoodLabel
@onready var stone_label: Label = $Panel/VBox/Resources/StoneLabel

# Dynamically created extras
var _income_rate_label: Label = null
var _demand_label: Label = null
var _reputation_label: Label = null
var _last_city_happiness: float = 100.0

# Toast notification system
var _toast_panel: Panel = null
var _toast_label: Label = null
var _toast_queue: Array = []
var _toast_active: bool = false

func _ready() -> void:
	EconomyManager.connect("gold_changed", _on_gold_changed)
	ProgressionManager.connect("level_up", func(_l, _u): _update_level_label())
	ProgressionManager.connect("xp_gained", func(_a, _t): _update_level_label())
	CitizenManager.connect("city_happiness_updated", func(h):
		_last_city_happiness = h
		happiness_label.text = "Happiness: %.0f%%" % h
	)
	CitizenManager.connect("citizen_arrived", func(_n): citizens_label.text = "Citizens: %d" % CitizenManager.get_citizen_count())
	ResourceManager.connect("resource_changed", _on_resource_changed)
	TimeManager.connect("new_day", _on_new_day)
	BuildingManager.connect("income_tick", _on_income_tick)
	SignalBus.road_mode_started.connect(func(): cancel_road_button.visible = true)
	SignalBus.road_mode_ended.connect(func(): cancel_road_button.visible = false)
	SignalBus.show_notification.connect(_on_notification)
	ReputationManager.reputation_changed.connect(func(_r): _update_reputation_label())
	_build_extra_labels()
	_build_toast()
	_refresh_all()

func _build_extra_labels() -> void:
	var vbox = $Panel/VBox
	_income_rate_label = Label.new()
	_income_rate_label.add_theme_font_size_override("font_size", 12)
	_income_rate_label.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55))
	vbox.add_child(_income_rate_label)

	_demand_label = Label.new()
	_demand_label.add_theme_font_size_override("font_size", 12)
	_demand_label.add_theme_color_override("font_color", Color(0.7, 0.75, 1.0))
	vbox.add_child(_demand_label)

	_reputation_label = Label.new()
	_reputation_label.add_theme_font_size_override("font_size", 12)
	_reputation_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	vbox.add_child(_reputation_label)

func _build_toast() -> void:
	_toast_panel = Panel.new()
	_toast_panel.anchor_left   = 0.5
	_toast_panel.anchor_right  = 0.5
	_toast_panel.anchor_top    = 1.0
	_toast_panel.anchor_bottom = 1.0
	_toast_panel.offset_left   = -280.0
	_toast_panel.offset_right  = 280.0
	_toast_panel.offset_top    = -80.0
	_toast_panel.offset_bottom = -24.0
	_toast_panel.visible = false
	_toast_label = Label.new()
	_toast_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_panel.add_child(_toast_label)
	add_child(_toast_panel)

func _refresh_all() -> void:
	_on_gold_changed(EconomyManager.gold)
	_update_level_label()
	happiness_label.text = "Happiness: 100%"
	citizens_label.text = "Citizens: 0"
	time_label.text = TimeManager.get_display_string()
	wood_label.text = "Wood: %d" % int(ResourceManager.get_amount("wood"))
	stone_label.text = "Stone: %d" % int(ResourceManager.get_amount("stone"))
	_update_income_rate()
	_update_demand_label()
	_update_reputation_label()

func _on_gold_changed(_amount: float) -> void:
	gold_label.text = "Gold: " + EconomyManager.get_gold_display()

func _update_level_label() -> void:
	level_label.text = ProgressionManager.get_display_string()

func _on_resource_changed(resource_id: String, amount: float) -> void:
	match resource_id:
		"wood":  wood_label.text = "Wood: %d" % int(amount)
		"stone": stone_label.text = "Stone: %d" % int(amount)

func _on_new_day(_d: int, _s: String, _y: int) -> void:
	time_label.text = TimeManager.get_display_string()
	_update_demand_label()

func _on_income_tick(_total: float) -> void:
	_update_income_rate()

func _update_income_rate() -> void:
	if not _income_rate_label:
		return
	var ipm = 0.0
	for b in BuildingManager.placed_buildings:
		if b.is_active:
			ipm += b.get_income_per_minute()
	var happiness_mult = maxf(_last_city_happiness / 100.0, 0.1)
	_income_rate_label.text = "Income: ~%.1f g/min" % (ipm * happiness_mult)

func _update_demand_label() -> void:
	if not _demand_label:
		return
	_demand_label.text = "Demand: %.0f / 100" % CitizenManager.demand_score

func _update_reputation_label() -> void:
	if not _reputation_label:
		return
	_reputation_label.text = "Rep: %.0f  •  %s" % [
		ReputationManager.reputation, ReputationManager.get_title()
	]

# ── Toast notifications ────────────────────────────────────────────────────────

func _on_notification(message: String) -> void:
	_toast_queue.append(message)
	if not _toast_active:
		_show_next_toast()

func _show_next_toast() -> void:
	if _toast_queue.is_empty():
		_toast_active = false
		return
	_toast_active = true
	_toast_label.text = _toast_queue.pop_front()
	_toast_panel.visible = true
	await get_tree().create_timer(2.5).timeout
	_toast_panel.visible = false
	await get_tree().create_timer(0.15).timeout
	_show_next_toast()

func _on_cancel_road_pressed() -> void:
	SignalBus.cancel_road_mode_requested.emit()

func _on_build_button_pressed() -> void:
	SignalBus.open_build_menu.emit()

func _on_citizens_button_pressed() -> void:
	SignalBus.open_citizen_panel.emit()

func _on_quests_button_pressed() -> void:
	SignalBus.open_quest_panel.emit()

func _on_save_button_pressed() -> void:
	SaveManager.save()
	save_button.text = "Saved!"
	await get_tree().create_timer(1.5).timeout
	save_button.text = "Save"

@onready var save_button: Button = $Panel/VBox/SaveButton
@onready var cancel_road_button: Button = $Panel/VBox/CancelRoadButton
