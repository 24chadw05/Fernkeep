extends Control

var current_building: PlacedBuilding = null

@onready var title_label:    Label         = $Panel/Title
@onready var day_label:      Label         = $Panel/DayLabel
@onready var close_button:   Button        = $Panel/CloseButton
@onready var tab_container:  TabContainer  = $Panel/TabContainer

# Per-tab content VBoxes
@onready var overview_box:   VBoxContainer = $Panel/TabContainer/Overview/Content
@onready var economy_box:    VBoxContainer = $Panel/TabContainer/Economy/Content
@onready var resources_box:  VBoxContainer = $Panel/TabContainer/Resources/Content
@onready var townhall_box:   VBoxContainer = $"Panel/TabContainer/Town Hall/Content"

# Dynamic labels populated in _ready and refreshed on show
var lbl_level:      Label
var lbl_xp:         Label
var xp_bar:         ProgressBar
var lbl_citizens:   Label
var lbl_housing:    Label
var lbl_happiness:  Label

var lbl_gold:       Label
var lbl_income:     Label
var lbl_wages:      Label
var lbl_rent:       Label
var lbl_net:        Label

var resource_labels: Dictionary = {}   # resource_id → Label

var lbl_th_tier:    Label
var lbl_th_upgrade: Label
var upgrade_button: Button

var _popup: ConfirmPopup = null

func _ready() -> void:
	visible = false
	SignalBus.open_town_hall_panel.connect(show_panel)
	SignalBus.close_all_panels.connect(func(): visible = false)
	close_button.pressed.connect(func(): visible = false)

	_build_overview_tab()
	_build_economy_tab()
	_build_resources_tab()
	_build_townhall_tab()

	_popup = ConfirmPopup.new()
	add_child(_popup)

	# Keep data live while the panel is open
	TimeManager.connect("new_day",    func(_d, _s, _y): if visible: _refresh())
	ProgressionManager.connect("level_up", func(_l, _u): if visible: _refresh())
	CitizenManager.connect("city_happiness_updated", func(_h): if visible: _refresh())

# ── Public ────────────────────────────────────────────────────────────────────

func show_panel(building: PlacedBuilding) -> void:
	current_building = building
	title_label.text = "Town Hall — Fernkeep"
	_refresh()
	visible = true

# ── Tab builders ──────────────────────────────────────────────────────────────

func _build_overview_tab() -> void:
	lbl_level     = _section_label(overview_box, "PROGRESSION", Color(0.85, 0.75, 0.4))
	lbl_xp        = _body_label(overview_box)
	xp_bar        = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(0, 14)
	xp_bar.show_percentage     = false
	overview_box.add_child(xp_bar)
	_spacer(overview_box)

	_section_label(overview_box, "POPULATION", Color(0.55, 0.85, 0.7))
	lbl_citizens  = _body_label(overview_box)
	lbl_housing   = _body_label(overview_box)
	_spacer(overview_box)

	_section_label(overview_box, "CITY MOOD", Color(0.7, 0.75, 1.0))
	lbl_happiness = _body_label(overview_box)

func _build_economy_tab() -> void:
	_section_label(economy_box, "TREASURY", Color(0.95, 0.85, 0.35))
	lbl_gold      = _body_label(economy_box)
	_spacer(economy_box)

	_section_label(economy_box, "INCOME", Color(0.5, 0.9, 0.5))
	lbl_income    = _body_label(economy_box)
	lbl_rent      = _body_label(economy_box)
	_spacer(economy_box)

	_section_label(economy_box, "EXPENSES", Color(0.9, 0.45, 0.45))
	lbl_wages     = _body_label(economy_box)
	_spacer(economy_box)

	_section_label(economy_box, "NET DAILY", Color(0.8, 0.8, 0.8))
	lbl_net       = _body_label(economy_box)

func _build_resources_tab() -> void:
	_section_label(resources_box, "STOCKPILE", Color(0.75, 0.65, 0.5))
	var tracked = ["wood", "stone", "herbs", "fish", "grain", "vegetables", "enchanted_ore", "rare_ingredients"]
	for res in tracked:
		var lbl = _body_label(resources_box)
		resource_labels[res] = lbl

	_spacer(resources_box)
	_section_label(resources_box, "PRODUCERS", Color(0.6, 0.75, 0.6))
	var producers_label = _body_label(resources_box)
	resource_labels["_producers"] = producers_label

func _build_townhall_tab() -> void:
	_section_label(townhall_box, "TOWN HALL STATUS", Color(0.85, 0.75, 0.4))
	lbl_th_tier   = _body_label(townhall_box)
	_spacer(townhall_box)

	_section_label(townhall_box, "UPGRADE", Color(0.6, 0.85, 0.6))
	lbl_th_upgrade = _body_label(townhall_box)
	upgrade_button = Button.new()
	upgrade_button.custom_minimum_size = Vector2(0, 40)
	upgrade_button.add_theme_font_size_override("font_size", 14)
	upgrade_button.pressed.connect(_show_upgrade_popup)
	townhall_box.add_child(upgrade_button)

	_spacer(townhall_box)
	_section_label(townhall_box, "STAFF", Color(0.7, 0.7, 0.9))
	var staff_lbl = _body_label(townhall_box)
	resource_labels["_th_staff"] = staff_lbl

# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh() -> void:
	if not current_building:
		return

	var time_str = "Day %d  •  %s  •  Year %d" % [
		TimeManager.current_day, TimeManager.get_season_name(), TimeManager.current_year
	]
	day_label.text = time_str

	# Overview
	lbl_level.text = "Level %d" % ProgressionManager.player_level
	var xp_cur = ProgressionManager.current_xp
	var xp_max = ProgressionManager.xp_to_next_level
	lbl_xp.text    = "XP:  %.0f / %.0f" % [xp_cur, xp_max]
	xp_bar.value   = (xp_cur / xp_max) * 100.0

	var citizen_count = CitizenManager.citizens.size()
	var citizen_cap   = BuildingManager.get_total_citizen_cap()
	lbl_citizens.text = "Citizens:  %d / %d" % [citizen_count, citizen_cap]

	var total_housing = BuildingManager.get_total_housing_capacity()
	var housed        = 0
	for npc in CitizenManager.citizens:
		if npc.house_building_id != "":
			housed += 1
	lbl_housing.text  = "Housed:  %d / %d   •   Homeless: %d" % [housed, total_housing, citizen_count - housed]

	var happiness = CitizenManager.calculate_city_happiness()
	lbl_happiness.text = "Happiness:  %.1f%%   %s" % [happiness, _mood_word(happiness)]
	lbl_happiness.add_theme_color_override("font_color", _score_color(happiness))

	# Economy
	lbl_gold.text   = "Gold:  %.0f / %.0f" % [EconomyManager.gold, EconomyManager.gold_cap]
	var income_min  = 0.0
	var daily_rent  = 0.0
	var daily_wages = 0.0
	for b in BuildingManager.placed_buildings:
		income_min  += b.get_income_per_minute()
		for npc_id in b.assigned_staff:
			var npc = CitizenManager.get_citizen_by_id(npc_id)
			if npc:
				daily_wages += npc.daily_wage
		if b.building_id == "house":
			for npc_id in b.assigned_residents:
				var npc = CitizenManager.get_citizen_by_id(npc_id)
				if npc:
					daily_rent += npc.daily_payment
	lbl_income.text = "Passive income:  %.1f gold / min" % income_min
	lbl_rent.text   = "Daily rent/tax:  %.0f gold / day" % daily_rent
	lbl_wages.text  = "Daily wages:  %.0f gold / day" % daily_wages
	var net = daily_rent - daily_wages + (income_min * 60.0)
	lbl_net.text    = "Net daily:  %.0f gold" % net
	lbl_net.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4) if net >= 0 else Color(0.9, 0.3, 0.3))

	# Resources
	var res_names = {
		"wood": "Wood", "stone": "Stone", "herbs": "Herbs", "fish": "Fish",
		"grain": "Grain", "vegetables": "Vegetables",
		"enchanted_ore": "Enchanted Ore", "rare_ingredients": "Rare Ingredients"
	}
	for res_id in res_names:
		if resource_labels.has(res_id):
			resource_labels[res_id].text = "%s:  %d" % [res_names[res_id], int(ResourceManager.get_amount(res_id))]

	var producers: Array = []
	for b in BuildingManager.placed_buildings:
		var prod: Dictionary = b.get_level_data().get("resource_production", {})
		if not prod.is_empty():
			var worker_count = b.assigned_staff.size()
			var parts: Array = []
			for r in prod:
				parts.append("%.1f %s" % [prod[r] * worker_count, r])
			producers.append("%s (%d workers): %s / min" % [b.get_display_name(), worker_count, ", ".join(parts)])
	if resource_labels.has("_producers"):
		resource_labels["_producers"].text = "\n".join(producers) if not producers.is_empty() else "No resource producers placed."

	# Town Hall tab
	lbl_th_tier.text = "Tier %d  •  Level %d  (Global level %d)" % [
		current_building.tier, current_building.level, current_building.get_global_level()
	]
	var upgrade_cost = current_building.get_upgrade_cost()
	if upgrade_cost < 0:
		lbl_th_upgrade.text  = "Maximum tier reached."
		upgrade_button.text  = "Max Tier"
		upgrade_button.disabled = true
	else:
		var nl = current_building.level + 1
		var nt = current_building.tier
		if nl > 3:
			nl = 1
			nt += 1
		lbl_th_upgrade.text  = "Upgrade to T%dL%d costs %.0f gold" % [nt, nl, upgrade_cost]
		upgrade_button.text  = "Upgrade Town Hall"
		upgrade_button.disabled = not EconomyManager.can_afford(upgrade_cost)

	var filled = current_building.assigned_staff.size()
	var slots  = current_building.get_staff_slots()
	if resource_labels.has("_th_staff"):
		resource_labels["_th_staff"].text = "Staff:  %d / %d slots filled" % [filled, slots]

# ── Actions ───────────────────────────────────────────────────────────────────

func _show_upgrade_popup() -> void:
	if not current_building:
		return
	var b = current_building
	var next_level = b.level + 1
	var next_tier  = b.tier
	if next_level > 3:
		next_level = 1
		next_tier += 1
	if next_tier > 3:
		return

	var cur_data  = b.get_level_data()
	var next_data = DataManager.get_building_level_data(b.building_id, next_tier, next_level)
	if next_data.is_empty():
		return

	var gold_cost: float = float(next_data.get("gold_cost", 0))
	var res_cost: Dictionary = next_data.get("resource_cost", {})

	var rows: Array = []

	var cost_parts: Array = ["%.0f gold" % gold_cost]
	for r in res_cost:
		cost_parts.append("%d %s" % [int(res_cost[r]), r.replace("_", " ")])
	rows.append({"type": "cost", "text": "Cost:  " + "  +  ".join(cost_parts)})
	rows.append({"type": "header", "text": "WHAT CHANGES"})

	var cur_ccap = int(cur_data.get("citizen_cap", 0))
	var new_ccap = int(next_data.get("citizen_cap", 0))
	if cur_ccap > 0 or new_ccap > 0:
		rows.append({
			"type": "row", "label": "Citizen cap",
			"old": str(cur_ccap), "new": str(new_ccap),
			"highlight": 1 if new_ccap > cur_ccap else 0
		})

	var cur_bslots = int(cur_data.get("building_slots", 0))
	var new_bslots = int(next_data.get("building_slots", 0))
	if cur_bslots > 0 or new_bslots > 0:
		rows.append({
			"type": "row", "label": "Building slots",
			"old": str(cur_bslots), "new": str(new_bslots),
			"highlight": 1 if new_bslots > cur_bslots else 0
		})

	var reward: String = next_data.get("reward", "")
	if reward != "":
		rows.append({"type": "unlock", "text": reward})

	_popup.open(
		"Upgrade Town Hall  —  T%dL%d → T%dL%d" % [b.tier, b.level, next_tier, next_level],
		rows,
		"Upgrade  (%.0fg)" % gold_cost,
		func(): _execute_upgrade()
	)

func _execute_upgrade() -> void:
	if not current_building:
		return
	if BuildingManager.upgrade_building(current_building.id):
		ProgressionManager.town_hall_level = current_building.get_global_level()
		SignalBus.show_notification.emit(
			"Town Hall upgraded to T%dL%d!" % [current_building.tier, current_building.level]
		)
		_refresh()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _section_label(parent: VBoxContainer, text: String, color: Color) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)
	return lbl

func _body_label(parent: VBoxContainer) -> Label:
	var lbl = Label.new()
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(lbl)
	return lbl

func _spacer(parent: VBoxContainer) -> void:
	var sep = HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 6)
	parent.add_child(sep)

func _score_color(score: float) -> Color:
	if score >= 75: return Color(0.3, 0.9, 0.3)
	if score >= 50: return Color(0.9, 0.8, 0.2)
	return Color(0.9, 0.3, 0.3)

func _mood_word(score: float) -> String:
	if score >= 90: return "(Thriving)"
	if score >= 75: return "(Content)"
	if score >= 50: return "(Restless)"
	if score >= 25: return "(Unhappy)"
	return "(Furious)"
