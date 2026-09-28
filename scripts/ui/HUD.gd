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
var _buffs_label: Label = null   # active food/potion bonuses, with time left
var _last_city_happiness: float = 100.0

# Toast notification system
var _toast_panel: Panel = null
var _toast_label: Label = null
var _toast_queue: Array = []
var _toast_active: bool = false

var _festival_button: Button = null
var _kitchen_button: Button = null

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
	# Ordinary notifications go quietly into the news log (NewsManager archives
	# both kinds itself); only the timed/urgent ones still interrupt with a
	# bottom-of-screen toast.
	SignalBus.show_notification_timed.connect(func(m, d): _on_notification(m, d, _TOAST_RED))
	NewsManager.unread_count_changed.connect(_update_news_badge)
	ReputationManager.reputation_changed.connect(func(_r): _update_reputation_label())
	ForageManager.charges_changed.connect(func(c): forage_button.text = "Forage (%d)" % c)
	FishingManager.charges_changed.connect(func(c): fish_button.text = "Fish (%d)" % c)
	CaravanManager.caravan_arrived.connect(func(_n, days):
		caravan_button.visible = true
		caravan_button.text = "🐫 Caravan! (%dd)" % days
	)
	CaravanManager.caravan_departed.connect(func(): caravan_button.visible = false)
	FestivalManager.festival_state_changed.connect(_update_festival_button)
	TimeManager.new_season.connect(func(_s, _y): _update_festival_button())
	backpack_button.texture_normal = load("res://assets/items/backpack.png")
	backpack_button.mouse_entered.connect(func(): backpack_button.modulate = Color(1.2, 1.2, 1.1))
	backpack_button.mouse_exited.connect(func(): backpack_button.modulate = Color(1, 1, 1))
	CitizenManager.arrival_queue_changed.connect(_update_arrival_badge)
	SaveManager.game_loaded.connect(_refresh_all)
	SaveManager.saved.connect(_on_game_saved)
	EconomyManager.day_settled.connect(_on_day_settled)
	_build_extra_labels()
	_build_festival_button()
	_build_kitchen_button()
	_build_toast()
	_refresh_all()

# Festival banner button — appears in the HUD only while the current season's
# festival is still available to host.
func _build_festival_button() -> void:
	_festival_button = Button.new()
	_festival_button.add_theme_font_size_override("font_size", 26)
	_festival_button.custom_minimum_size = Vector2(0, 64)
	_festival_button.visible = false
	_festival_button.pressed.connect(func(): SignalBus.open_festival_panel.emit())
	# Sit it just above the Save button
	var vbox = $Panel/VBox
	vbox.add_child(_festival_button)
	vbox.move_child(_festival_button, save_button.get_index())
	_update_festival_button()

func _build_kitchen_button() -> void:
	_kitchen_button = Button.new()
	_kitchen_button.icon = load("res://assets/ui/cooking_pot.png")
	_kitchen_button.expand_icon = false
	_kitchen_button.pressed.connect(func(): SignalBus.open_kitchen_panel.emit())
	var vbox = $Panel/VBox
	vbox.add_child(_kitchen_button)
	vbox.move_child(_kitchen_button, fish_button.get_index() + 1)
	CookingManager.requests_changed.connect(_update_kitchen_button)
	BuildingManager.building_placed.connect(func(_b): _update_kitchen_button())
	BuildingManager.building_removed.connect(func(_b): _update_kitchen_button())
	_update_kitchen_button()

func _update_kitchen_button() -> void:
	if _kitchen_button == null:
		return
	_kitchen_button.visible = CookingManager.has_kitchen()
	var n := CookingManager.requests.size()
	_kitchen_button.text = "Kitchen (%d)" % n
	# Tint it warm while someone's waiting on a meal
	_kitchen_button.modulate = Color(1.15, 1.0, 0.8) if n > 0 else Color.WHITE

func _update_festival_button() -> void:
	if _festival_button == null:
		return
	_festival_button.visible = FestivalManager.is_available()
	if _festival_button.visible:
		_festival_button.text = "🎉 %s" % FestivalManager.current_festival_name()

func _build_extra_labels() -> void:
	var vbox = $Panel/VBox
	_income_rate_label = Label.new()
	_income_rate_label.add_theme_font_size_override("font_size", 24)
	_income_rate_label.add_theme_color_override("font_color", Color(0.21, 0.43, 0.21))
	vbox.add_child(_income_rate_label)

	_demand_label = Label.new()
	_demand_label.add_theme_font_size_override("font_size", 24)
	_demand_label.add_theme_color_override("font_color", Color(0.23, 0.26, 0.39))
	vbox.add_child(_demand_label)

	_reputation_label = Label.new()
	_reputation_label.add_theme_font_size_override("font_size", 24)
	_reputation_label.add_theme_color_override("font_color", Color(0.41, 0.33, 0.13))
	vbox.add_child(_reputation_label)

	_buffs_label = Label.new()
	_buffs_label.add_theme_font_size_override("font_size", 20)
	_buffs_label.add_theme_color_override("font_color", Color(0.35, 0.25, 0.5))
	_buffs_label.visible = false
	vbox.add_child(_buffs_label)
	RecipeManager.effects_changed.connect(_update_buffs_label)

func _build_toast() -> void:
	_toast_panel = Panel.new()
	_toast_panel.anchor_left   = 0.5
	_toast_panel.anchor_right  = 0.5
	_toast_panel.anchor_top    = 1.0
	_toast_panel.anchor_bottom = 1.0
	_toast_panel.offset_left   = -480.0
	_toast_panel.offset_right  = 480.0
	_toast_panel.offset_top    = -130.0
	_toast_panel.offset_bottom = -30.0
	_toast_panel.visible = false
	_toast_label = Label.new()
	_toast_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_panel.add_child(_toast_label)
	# Put the toast on its own high CanvasLayer so it draws above every window
	var toast_layer := CanvasLayer.new()
	toast_layer.layer = 128
	add_child(toast_layer)
	toast_layer.add_child(_toast_panel)

func _refresh_all() -> void:
	_on_gold_changed(EconomyManager.gold)
	_update_level_label()
	_last_city_happiness = CitizenManager.calculate_city_happiness()
	happiness_label.text = "Happiness: %.0f%%" % _last_city_happiness
	citizens_label.text = "Citizens: %d" % CitizenManager.get_citizen_count()
	time_label.text = TimeManager.get_display_string()
	wood_label.text = "Wood: %d" % int(ResourceManager.get_amount("wood"))
	stone_label.text = "Stone: %d" % int(ResourceManager.get_amount("stone"))
	forage_button.text = "Forage (%d)" % ForageManager.charges
	fish_button.text = "Fish (%d)" % FishingManager.charges
	_update_income_rate()
	_update_demand_label()
	_update_reputation_label()
	_update_arrival_badge()
	_update_news_badge()
	_update_festival_button()
	_update_kitchen_button()

func _update_arrival_badge() -> void:
	var count = CitizenManager.get_pending_count()
	arrival_badge.visible = count > 0
	arrival_count_label.text = str(count)

func _update_news_badge(count: int = -1) -> void:
	var unread = count if count >= 0 else NewsManager.get_unread_count()
	news_badge.visible = unread > 0
	news_count_label.text = str(unread)

# Payday: float the banked lump up from the gold counter so the once-a-day
# payout is visible without adding a news entry every game day.
func _on_day_settled(_revenue: float, _wages: float, payout: float) -> void:
	if payout < 1.0:
		return
	var pop := Label.new()
	pop.text = "+%.0f payday" % payout
	pop.add_theme_font_size_override("font_size", 28)
	pop.add_theme_color_override("font_color", Color(0.15, 0.45, 0.12))
	pop.add_theme_color_override("font_outline_color", Color(0.97, 0.94, 0.85))
	pop.add_theme_constant_override("outline_size", 6)
	pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pop)
	pop.global_position = gold_label.global_position + Vector2(gold_label.size.x + 12.0, 0.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(pop, "position:y", pop.position.y - 40.0, 1.6)
	tw.tween_property(pop, "modulate:a", 0.0, 1.6).set_delay(0.6)
	tw.chain().tween_callback(pop.queue_free)

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
	_update_buffs_label()   # once a second is plenty for "0.7d left"

# "✦ Tavern Favourite 0.8d" per active bonus; hover shows what each one does.
func _update_buffs_label() -> void:
	if _buffs_label == null:
		return
	var lines: Array = []
	var tips: Array = []
	for e in RecipeManager.active_effects:
		var days = float(e["remaining"]) / TimeManager.DAY_LENGTH_SECONDS
		lines.append("✦ %s  %s" % [e.get("name", "Bonus"),
			("%.1fd" % days) if days >= 0.1 else ("%ds" % int(e["remaining"]))])
		tips.append("%s: %s" % [e.get("name", "Bonus"), RecipeManager.describe_effect(e["effect"])])
	_buffs_label.visible = not lines.is_empty()
	_buffs_label.text = "\n".join(PackedStringArray(lines))
	_buffs_label.tooltip_text = "\n".join(PackedStringArray(tips))
	_buffs_label.mouse_filter = Control.MOUSE_FILTER_PASS   # so the tooltip shows

func _update_income_rate() -> void:
	if not _income_rate_label:
		return
	var ipm = 0.0
	for b in BuildingManager.placed_buildings:
		if b.is_active:
			ipm += BuildingManager.get_live_income_per_minute(b)
	ipm *= RecipeManager.get_income_multiplier() * TimeManager.get_income_multiplier() * PrestigeManager.get_income_multiplier()
	# Takings are held until payday, so show what's accrued — otherwise the gold
	# counter looks frozen all day and the income rate reads as a lie.
	_income_rate_label.text = "Income: ~%.1f g/day  •  %.0f held" % [
		ipm, EconomyManager.pending_revenue
	]

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

const _TOAST_INK := Color(0.227, 0.157, 0.094)
const _TOAST_RED := Color(0.72, 0.13, 0.1)

func _on_notification(message: String, duration: float = 2.5, color: Color = _TOAST_INK) -> void:
	_toast_queue.append({"msg": message, "dur": duration, "color": color})
	if not _toast_active:
		_show_next_toast()

func _show_next_toast() -> void:
	if _toast_queue.is_empty():
		_toast_active = false
		return
	_toast_active = true
	var item: Dictionary = _toast_queue.pop_front()
	_toast_label.text = str(item["msg"])
	_toast_label.add_theme_color_override("font_color", item.get("color", _TOAST_INK))
	_toast_panel.visible = true
	await get_tree().create_timer(float(item["dur"])).timeout
	_toast_panel.visible = false
	await get_tree().create_timer(0.15).timeout
	_show_next_toast()

func _on_cancel_road_pressed() -> void:
	SignalBus.cancel_road_mode_requested.emit()

func _on_build_button_pressed() -> void:
	SignalBus.open_build_menu.emit()

func _on_citizens_button_pressed() -> void:
	SignalBus.open_citizen_panel.emit()

func _on_revenue_button_pressed() -> void:
	SignalBus.open_revenue_panel.emit()

func _on_quests_button_pressed() -> void:
	SignalBus.open_quest_panel.emit()

func _on_forage_button_pressed() -> void:
	SignalBus.open_forage_panel.emit()

func _on_fish_button_pressed() -> void:
	SignalBus.open_fishing_panel.emit()

func _on_caravan_button_pressed() -> void:
	SignalBus.open_caravan_panel.emit()

func _on_backpack_pressed() -> void:
	SignalBus.open_inventory_panel.emit()

func _on_arrivals_pressed() -> void:
	SignalBus.open_arrivals_panel.emit()

func _on_news_pressed() -> void:
	SignalBus.open_news_panel.emit()

func _on_save_button_pressed() -> void:
	SaveManager.save()  # the button's feedback comes from SaveManager.saved

# Every successful write (manual, autosave, focus-loss) flashes the Save button,
# so the player can see progress is safe without a notification each time.
var _save_flash_id: int = 0
func _on_game_saved(_slot: int, is_autosave: bool) -> void:
	_save_flash_id += 1
	var my_id := _save_flash_id
	save_button.text = "Auto-saved" if is_autosave else "Saved!"
	await get_tree().create_timer(1.5).timeout
	if my_id == _save_flash_id:  # a newer save restarted the flash; let it finish
		save_button.text = "Save"

@onready var save_button: Button = $Panel/VBox/SaveButton
@onready var cancel_road_button: Button = $Panel/VBox/CancelRoadButton
@onready var forage_button: Button = $Panel/VBox/ForageButton
@onready var fish_button: Button = $Panel/VBox/FishButton
@onready var caravan_button: Button = $Panel/VBox/CaravanButton
@onready var backpack_button: TextureButton = $BackpackButton
@onready var arrivals_button: Button = $ArrivalsButton
@onready var arrival_badge: Panel = $ArrivalsButton/Badge
@onready var arrival_count_label: Label = $ArrivalsButton/Badge/CountLabel
@onready var news_button: Button = $NewsButton
@onready var news_badge: Panel = $NewsButton/Badge
@onready var news_count_label: Label = $NewsButton/Badge/CountLabel
