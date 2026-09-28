extends Control

# Player cash-flow ledger: actual gold moved today (from EconomyManager's
# daily counters) plus a projected per-day breakdown of every recurring
# income source and cost. Opened from the Revenue button in the HUD.

@onready var subtitle_label: Label = $Panel/SubTitle
@onready var close_button: Button = $Panel/CloseButton
@onready var today_label: Label = $Panel/TodayLabel
@onready var projected_label: Label = $Panel/ProjectedLabel
@onready var ledger_list: VBoxContainer = $Panel/ScrollContainer/LedgerList

const INK_GREEN := Color(0.15, 0.45, 0.12)
const INK_RED := Color(0.62, 0.15, 0.1)
const INK_AMBER := Color(0.55, 0.42, 0.05)
const INK_SEPIA := Color(0.42, 0.33, 0.22)

func _ready() -> void:
	visible = false
	SignalBus.open_revenue_panel.connect(show_panel)
	SignalBus.close_all_panels.connect(func(): visible = false)
	close_button.pressed.connect(func(): visible = false)
	# Live totals every income tick; full rebuild only when the city changes
	BuildingManager.income_tick.connect(func(_t): _update_summary_if_visible())
	TimeManager.new_day.connect(func(_d, _s, _y): _refresh_if_visible())
	CitizenManager.citizen_assigned.connect(func(_n, _b): _refresh_if_visible())
	CitizenManager.housing_updated.connect(_refresh_if_visible)
	BuildingManager.building_placed.connect(func(_b): _refresh_if_visible())
	BuildingManager.building_removed.connect(func(_b): _refresh_if_visible())
	BuildingManager.building_upgraded.connect(func(_b): _refresh_if_visible())

func _refresh_if_visible() -> void:
	if visible:
		_rebuild()

func _update_summary_if_visible() -> void:
	if visible:
		_update_summary(_projection())

func show_panel() -> void:
	_rebuild()
	visible = true

# ── Projection math ───────────────────────────────────────────────────────────
# A game day is 60 real seconds, so income-per-minute IS income-per-day.

func _projection() -> Dictionary:
	var mults = RecipeManager.get_income_multiplier() * TimeManager.get_income_multiplier() * PrestigeManager.get_income_multiplier()
	var businesses: Array = []
	var houses: Array = []
	var total_revenue := 0.0
	var total_wages := 0.0
	var total_rent := 0.0

	for b in BuildingManager.placed_buildings:
		if not b.is_active:
			continue
		if b.building_id == "house":
			var rent := 0.0
			for npc_id in b.assigned_residents:
				var npc = CitizenManager.get_citizen_by_id(npc_id)
				if npc:
					rent += npc.daily_payment
			houses.append({"b": b, "rent": rent})
			total_rent += rent
			continue

		var revenue = BuildingManager.get_live_income_per_minute(b) * mults
		var wages := 0.0
		for npc_id in b.assigned_staff:
			var npc = CitizenManager.get_citizen_by_id(npc_id)
			if npc:
				wages += npc.daily_wage
		# Skip pure decor (no income, no staff)
		if revenue <= 0.0 and wages <= 0.0 and b.get_staff_slots() <= 0:
			continue
		businesses.append({"b": b, "revenue": revenue, "wages": wages})
		total_revenue += revenue
		total_wages += wages

	var happiness = CitizenManager.calculate_city_happiness()
	# A game day is 60 s, so the per-second town tick x60 is the per-day figure.
	var baseline = EconomyManager.BASELINE_GOLD_PER_SECOND * 60.0 * (happiness / 100.0) * mults

	var groceries := 0.0
	if BuildingManager.has_building_type("market"):
		for c in CitizenManager.citizens:
			groceries += CitizenManager.get_daily_food_cost(c)

	var homeless := 0
	for c in CitizenManager.citizens:
		if c.house_building_id == "":
			homeless += 1

	return {
		"businesses": businesses, "houses": houses,
		"revenue": total_revenue, "wages": total_wages, "rent": total_rent,
		"baseline": baseline, "groceries": groceries, "homeless": homeless,
		"income": total_revenue + total_rent + baseline + groceries,
	}

# ── UI ────────────────────────────────────────────────────────────────────────

func _update_summary(p: Dictionary) -> void:
	subtitle_label.text = TimeManager.get_display_string()
	today_label.text = "Today so far:  +%.0f earned  •  −%.0f spent  •  %.0f held for payday" % [
		EconomyManager.daily_income, EconomyManager.daily_expenses,
		EconomyManager.pending_revenue,
	]
	var profit = p.income - p.wages
	projected_label.text = "Projected:  +%.0f g/day income  •  −%.0f g/day wages  •  profit %+.0f g/day" % [
		p.income, p.wages, profit,
	]
	projected_label.add_theme_color_override("font_color", INK_GREEN if profit >= 0.0 else INK_RED)

func _rebuild() -> void:
	for child in ledger_list.get_children():
		child.queue_free()

	var p = _projection()
	_update_summary(p)

	# ── Businesses ──
	_add_header("BUSINESSES")
	if p.businesses.is_empty():
		_add_note("No businesses yet — build a tavern, farm, or shop.")
	for entry in p.businesses:
		var b = entry.b
		var card := PanelContainer.new()
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		card.add_child(box)

		var name_lbl := Label.new()
		name_lbl.text = "%s  (T%dL%d)" % [b.get_display_name(), b.tier, b.level]
		name_lbl.add_theme_font_size_override("font_size", 26)
		box.add_child(name_lbl)

		var stats := HFlowContainer.new()
		stats.add_theme_constant_override("h_separation", 24)
		stats.add_child(_stat_label("Revenue  +%.0f g/day" % entry.revenue, INK_GREEN))
		if entry.wages > 0.0:
			stats.add_child(_stat_label("Wages  −%.0f g/day" % entry.wages, INK_RED))
		var net = entry.revenue - entry.wages
		stats.add_child(_stat_label("Net  %+.0f g/day" % net, INK_GREEN if net >= 0.0 else INK_RED))
		box.add_child(stats)
		ledger_list.add_child(card)

	# ── Housing ──
	_add_header("HOUSING — RENT & TAX")
	if p.houses.is_empty():
		_add_note("No houses yet.")
	for entry in p.houses:
		var b = entry.b
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 24)
		row.add_child(_stat_label("%s  (T%dL%d)  •  %d resident(s)" % [
			b.get_display_name(), b.tier, b.level, b.assigned_residents.size()
		], Color(0.227, 0.157, 0.094)))
		row.add_child(_stat_label("+%.0f g/day" % entry.rent, INK_GREEN))
		ledger_list.add_child(row)
	if p.homeless > 0:
		_add_note("%d citizen(s) are homeless and pay nothing — build more houses." % p.homeless)

	# ── Other income ──
	_add_header("OTHER INCOME")
	var base_row := HFlowContainer.new()
	base_row.add_theme_constant_override("h_separation", 24)
	base_row.add_child(_stat_label("Town income (happiness-driven)", Color(0.227, 0.157, 0.094)))
	base_row.add_child(_stat_label("+%.0f g/day" % p.baseline, INK_GREEN))
	ledger_list.add_child(base_row)
	if BuildingManager.has_building_type("market"):
		var groc_row := HFlowContainer.new()
		groc_row.add_theme_constant_override("h_separation", 24)
		groc_row.add_child(_stat_label("Groceries spent at your market", Color(0.227, 0.157, 0.094)))
		groc_row.add_child(_stat_label("~+%.0f g/day" % p.groceries, INK_GREEN))
		ledger_list.add_child(groc_row)
	else:
		_add_note("No market — citizens buy imported food and you see none of it.")

	# ── Totals ──
	_add_header("DAILY TOTALS")
	_add_total_row("Business revenue", p.revenue, INK_GREEN)
	_add_total_row("Rent & tax", p.rent, INK_GREEN)
	_add_total_row("Town income", p.baseline, INK_GREEN)
	if p.groceries > 0.0:
		_add_total_row("Groceries", p.groceries, INK_GREEN)
	_add_total_row("Wages", -p.wages, INK_RED)
	var profit = p.income - p.wages
	var profit_lbl := Label.new()
	profit_lbl.text = "PROFIT:  %+.0f gold / day" % profit
	profit_lbl.add_theme_font_size_override("font_size", 30)
	profit_lbl.add_theme_color_override("font_color", INK_GREEN if profit >= 0.0 else INK_RED)
	ledger_list.add_child(profit_lbl)
	_add_note("Business and town revenue is held until payday: at the end of each day wages come out of it and the remainder is banked in one lump. Rent, groceries, quests, market trades and construction move gold immediately.")

func _stat_label(text: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", color)
	return lbl

func _add_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	ledger_list.add_child(lbl)
	ledger_list.add_child(HSeparator.new())

func _add_note(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", INK_SEPIA)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ledger_list.add_child(lbl)

func _add_total_row(label: String, amount: float, color: Color) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 24)
	row.add_child(_stat_label(label, Color(0.227, 0.157, 0.094)))
	row.add_child(_stat_label("%+.0f g/day" % amount, color))
	ledger_list.add_child(row)
