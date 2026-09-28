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
var lbl_plots:      Label
var lbl_th_upgrade: Label
var upgrade_button: Button
var lbl_prestige:   Label
var prestige_button: Button

# _refresh reads calculate_city_happiness(), which EMITS city_happiness_updated,
# which we also listen to → guard against the re-entrant refresh loop.
var _refreshing: bool = false

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
	PrestigeManager.prestige_stats_changed.connect(func(): if visible: _refresh_prestige())

# ── Public ────────────────────────────────────────────────────────────────────

func show_panel(building: PlacedBuilding) -> void:
	current_building = building
	title_label.text = "Town Hall — Fernkeep"
	_refresh()
	visible = true

# ── Tab builders ──────────────────────────────────────────────────────────────

func _build_overview_tab() -> void:
	# Three columns spread across the panel width
	var cols = _columns(overview_box, 3)

	lbl_level     = _section_label(cols[0], "PROGRESSION", Color(0.5, 0.38, 0.06))
	lbl_xp        = _body_label(cols[0])
	xp_bar        = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(0, 28)
	xp_bar.show_percentage     = false
	cols[0].add_child(xp_bar)

	_section_label(cols[1], "POPULATION", Color(0.16, 0.42, 0.3))
	lbl_citizens  = _body_label(cols[1])
	lbl_housing   = _body_label(cols[1])

	_section_label(cols[2], "CITY MOOD", Color(0.25, 0.28, 0.55))
	lbl_happiness = _body_label(cols[2])

func _build_economy_tab() -> void:
	var cols = _columns(economy_box, 2)

	_section_label(cols[0], "TREASURY", Color(0.55, 0.42, 0.05))
	lbl_gold      = _body_label(cols[0])
	_spacer(cols[0])
	_section_label(cols[0], "INCOME", Color(0.15, 0.45, 0.12))
	lbl_income    = _body_label(cols[0])
	lbl_rent      = _body_label(cols[0])

	_section_label(cols[1], "EXPENSES", Color(0.6, 0.16, 0.12))
	lbl_wages     = _body_label(cols[1])
	_spacer(cols[1])
	_section_label(cols[1], "NET DAILY", Color(0.35, 0.27, 0.18))
	lbl_net       = _body_label(cols[1])

func _build_resources_tab() -> void:
	_section_label(resources_box, "STOCKPILE", Color(0.42, 0.32, 0.2))
	# Table: Resource | In stock | Market value each | Total worth
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	resources_box.add_child(grid)
	for h in ["Resource", "In stock", "Value each", "Total worth"]:
		var head = Label.new()
		head.text = h
		head.add_theme_font_size_override("font_size", 22)
		head.add_theme_color_override("font_color", Color(0.5, 0.4, 0.24))
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(head)
	var tracked = ["wood", "stone", "herbs", "fish", "grain", "vegetables", "enchanted_ore", "rare_ingredients"]
	for res in tracked:
		var name_lbl = _table_cell(grid, ResourceManager.get_item_label(res))
		name_lbl.add_theme_color_override("font_color", Color(0.3, 0.22, 0.14))
		resource_labels[res] = _table_cell(grid, "0")
		resource_labels[res + "_val"] = _table_cell(grid, "—")
		resource_labels[res + "_tot"] = _table_cell(grid, "—")

	_spacer(resources_box)
	_section_label(resources_box, "PRODUCERS", Color(0.22, 0.4, 0.2))
	var producers_label = _body_label(resources_box)
	resource_labels["_producers"] = producers_label

func _build_townhall_tab() -> void:
	var cols = _columns(townhall_box, 2)

	_section_label(cols[0], "TOWN HALL STATUS", Color(0.5, 0.38, 0.06))
	lbl_th_tier   = _body_label(cols[0])
	lbl_plots     = _body_label(cols[0])
	_spacer(cols[0])
	_section_label(cols[0], "UPGRADE", Color(0.18, 0.45, 0.15))
	lbl_th_upgrade = _body_label(cols[0])
	upgrade_button = Button.new()
	upgrade_button.custom_minimum_size = Vector2(0, 80)
	upgrade_button.add_theme_font_size_override("font_size", 28)
	upgrade_button.pressed.connect(_show_upgrade_popup)
	cols[0].add_child(upgrade_button)

	_section_label(cols[1], "STAFF", Color(0.28, 0.28, 0.5))
	var staff_lbl = _body_label(cols[1])
	resource_labels["_th_staff"] = staff_lbl
	_spacer(cols[1])
	_section_label(cols[1], "PRESTIGE — FOUND ANEW", Color(0.5, 0.3, 0.55))
	lbl_prestige = _body_label(cols[1])
	prestige_button = Button.new()
	prestige_button.custom_minimum_size = Vector2(0, 80)
	prestige_button.add_theme_font_size_override("font_size", 28)
	prestige_button.pressed.connect(_show_prestige_popup)
	cols[1].add_child(prestige_button)

# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh() -> void:
	if not current_building or _refreshing:
		return
	_refreshing = true

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
	lbl_gold.text   = "Gold:  %.0f" % EconomyManager.gold
	var income_min  = 0.0
	var daily_rent  = 0.0
	var daily_wages = 0.0
	for b in BuildingManager.placed_buildings:
		income_min  += BuildingManager.get_live_income_per_minute(b)
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
	lbl_net.add_theme_color_override("font_color", Color(0.12, 0.43, 0.12) if net >= 0 else Color(0.62, 0.14, 0.1))

	# Resources table — stock, market value each, total worth
	var tracked = ["wood", "stone", "herbs", "fish", "grain", "vegetables", "enchanted_ore", "rare_ingredients"]
	for res_id in tracked:
		if not resource_labels.has(res_id):
			continue
		var amount = int(ResourceManager.get_amount(res_id))
		var unit_val = MarketManager.get_current_value(res_id)
		resource_labels[res_id].text = "%d" % amount
		resource_labels[res_id + "_val"].text = "%.0fg" % unit_val
		resource_labels[res_id + "_tot"].text = "%.0fg" % (amount * unit_val)

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
	var used_plots = BuildingManager.get_non_town_hall_count()
	var plot_limit = BuildingManager.get_building_slot_limit()
	var expansion = BuildingManager.get_expansion_points()
	lbl_plots.text = "Building plots:  %d / %d   (+%d from mastered buildings)" % [
		used_plots, plot_limit, expansion
	]
	lbl_plots.add_theme_color_override("font_color", Color(0.16, 0.42, 0.3))
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

	_refresh_prestige()
	_refreshing = false

func _refresh_prestige() -> void:
	if not lbl_prestige:
		return
	var bonus_pct = (PrestigeManager.get_income_multiplier() - 1.0) * 100.0
	var status = "Renown: %.0f  (+%.0f%% income, permanent)  •  Founded anew %d time(s)" % [
		PrestigeManager.renown, bonus_pct, PrestigeManager.prestige_count
	]
	if PrestigeManager.can_prestige():
		lbl_prestige.text = "%s\nReady! Reset the city for +%.0f Renown and a new beginning." % [
			status, PrestigeManager.renown_reward()
		]
		lbl_prestige.add_theme_color_override("font_color", Color(0.15, 0.45, 0.12))
		prestige_button.text = "Found Anew…  (+%.0f Renown)" % PrestigeManager.renown_reward()
		prestige_button.disabled = false
	else:
		lbl_prestige.text = "%s\nUnlocks when your Town Hall reaches Tier 3 (global level %d)." % [
			status, PrestigeManager.PRESTIGE_TOWN_HALL_LEVEL
		]
		lbl_prestige.add_theme_color_override("font_color", Color(0.42, 0.33, 0.22))
		prestige_button.text = "Prestige Locked"
		prestige_button.disabled = true

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
	var blocker = BuildingManager.get_upgrade_blocker(current_building)
	if blocker != "":
		SignalBus.show_notification_timed.emit(blocker, 1.5)
		return
	if BuildingManager.upgrade_building(current_building.id):
		ProgressionManager.town_hall_level = current_building.get_global_level()
		SignalBus.show_notification.emit(
			"Town Hall upgraded to T%dL%d!" % [current_building.tier, current_building.level]
		)
		_refresh()

# ── Prestige ──────────────────────────────────────────────────────────────────

func _show_prestige_popup() -> void:
	if not PrestigeManager.can_prestige():
		return
	# Scenario chooser overlay — pick a fresh beginning before confirming the reset
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Found Anew — Choose Your Beginning"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.5, 0.3, 0.55))
	vbox.add_child(title)

	var warn := Label.new()
	warn.text = "This resets your city, citizens, gold, and buildings. You keep your Renown (+%.0f from this founding) and its permanent income bonus." % PrestigeManager.renown_reward()
	warn.add_theme_font_size_override("font_size", 22)
	warn.add_theme_color_override("font_color", Color(0.6, 0.16, 0.12))
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(warn)

	for scenario_id in PrestigeManager.SCENARIOS:
		var info: Dictionary = PrestigeManager.SCENARIOS[scenario_id]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 76)
		btn.add_theme_font_size_override("font_size", 24)
		btn.text = "%s — %s" % [info.get("name", scenario_id), info.get("blurb", "")]
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(func():
			overlay.queue_free()
			_confirm_prestige(scenario_id)
		)
		vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 64)
	cancel.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(cancel)

	add_child(overlay)

func _confirm_prestige(scenario_id: String) -> void:
	var info: Dictionary = PrestigeManager.get_scenario(scenario_id)
	var rows: Array = [
		{"type": "header", "text": "YOU KEEP"},
		{"type": "note", "text": "Renown %.0f → %.0f  (+%.0f%% permanent income)" % [
			PrestigeManager.renown, PrestigeManager.renown + PrestigeManager.renown_reward(),
			(1.0 + (PrestigeManager.renown + PrestigeManager.renown_reward()) * PrestigeManager.RENOWN_INCOME_PER_POINT - 1.0) * 100.0
		]},
		{"type": "header", "text": "YOU RESET"},
		{"type": "note", "text": "All gold, resources, buildings, and citizens — reborn as %s." % info.get("name", "a new city")},
	]
	_popup.open(
		"Found Anew  —  %s" % info.get("name", "New Beginning"),
		rows,
		"Found Anew",
		func(): PrestigeManager.execute_prestige(scenario_id)
	)

# ── Helpers ───────────────────────────────────────────────────────────────────

# Split a tab's content into N equal-width columns spread across the panel
func _columns(parent: VBoxContainer, count: int) -> Array:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 48)
	parent.add_child(row)
	var cols: Array = []
	for i in range(count):
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 6)
		row.add_child(col)
		cols.append(col)
	return cols

func _table_cell(grid: GridContainer, text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(lbl)
	return lbl

func _section_label(parent: Container, text: String, color: Color) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)
	return lbl

func _body_label(parent: Container) -> Label:
	var lbl = Label.new()
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(lbl)
	return lbl

func _spacer(parent: VBoxContainer) -> void:
	var sep = HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 12)
	parent.add_child(sep)

func _score_color(score: float) -> Color:
	if score >= 75: return Color(0.15, 0.45, 0.12)
	if score >= 50: return Color(0.55, 0.42, 0.05)
	return Color(0.62, 0.14, 0.1)

func _mood_word(score: float) -> String:
	if score >= 90: return "(Thriving)"
	if score >= 75: return "(Content)"
	if score >= 50: return "(Restless)"
	if score >= 25: return "(Unhappy)"
	return "(Furious)"
