extends Control

var current_building: PlacedBuilding = null

@onready var title_label: Label = $Panel/Title
@onready var close_button: Button = $Panel/CloseButton
@onready var name_label: Label = $Panel/VBox/NameLabel
@onready var tier_label: Label = $Panel/VBox/TierLabel
@onready var income_label: Label = $Panel/VBox/IncomeLabel
@onready var staff_label: Label = $Panel/VBox/StaffLabel
@onready var upgrade_cost_label: Label = $Panel/VBox/UpgradeSection/UpgradeCostLabel
@onready var upgrade_button: Button = $Panel/VBox/UpgradeSection/UpgradeButton
@onready var staff_list: VBoxContainer = $Panel/VBox/StaffSection/StaffList
@onready var sell_button: Button = $Panel/VBox/SellButton

var property_value_label: Label = null
var daily_income_label: Label = null
var popularity_label: Label = null
var residents_section: VBoxContainer = null
var menu_button: Button = null

var _popup: ConfirmPopup = null

func _ready() -> void:
	visible = false
	SignalBus.open_building_inspector.connect(show_building)
	SignalBus.close_all_panels.connect(func(): visible = false)
	close_button.pressed.connect(func(): visible = false)
	upgrade_button.pressed.connect(_show_upgrade_popup)
	sell_button.pressed.connect(_on_sell)

	_popup = ConfirmPopup.new()
	add_child(_popup)
	CitizenManager.connect("citizen_assigned", func(_n, _b): _refresh_if_visible())
	CitizenManager.connect("housing_updated", _refresh_if_visible)

	var vbox = $Panel/VBox

	# Property value — shown for all buildings
	property_value_label = Label.new()
	property_value_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	vbox.add_child(property_value_label)
	vbox.move_child(property_value_label, income_label.get_index() + 1)

	# Daily income summary — shown for all buildings
	daily_income_label = Label.new()
	daily_income_label.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55))
	vbox.add_child(daily_income_label)
	vbox.move_child(daily_income_label, property_value_label.get_index() + 1)

	# Popularity score — shown for non-house buildings
	popularity_label = Label.new()
	popularity_label.add_theme_color_override("font_color", Color(0.7, 0.75, 1.0))
	vbox.add_child(popularity_label)
	vbox.move_child(popularity_label, daily_income_label.get_index() + 1)

	# Residents section — shown for house buildings
	residents_section = VBoxContainer.new()
	residents_section.visible = false
	vbox.add_child(residents_section)

	# Menu management — shown for taverns only
	menu_button = Button.new()
	menu_button.text = "Manage Menu"
	menu_button.custom_minimum_size = Vector2(0, 36)
	menu_button.visible = false
	menu_button.pressed.connect(func():
		if current_building:
			SignalBus.open_tavern_menu.emit(current_building)
	)
	vbox.add_child(menu_button)

func _refresh_if_visible() -> void:
	if visible and current_building:
		_populate(current_building)

func show_building(building: PlacedBuilding) -> void:
	current_building = building
	_populate(building)
	visible = true

func _populate(building: PlacedBuilding) -> void:
	var is_house = building.building_id == "house"

	name_label.text = building.get_display_name()
	tier_label.text = "Tier %d  •  Level %d  (Overall level %d)" % [building.tier, building.level, building.get_global_level()]

	var income = building.get_income_per_minute()
	income_label.text = "Passive income: %.1f gold / min" % income

	# Property value
	property_value_label.text = "Property value:  %.0f gold" % _calc_property_value(building)

	# Daily income
	var daily = _calc_daily_income(building)
	daily_income_label.text = "Daily income:  %.0f gold" % daily

	# Popularity (businesses only)
	popularity_label.visible = not is_house
	if not is_house:
		var pop = _calc_popularity(building)
		var pop_color = _score_color(pop)
		popularity_label.text = "Popularity:  %.0f / 100" % pop
		popularity_label.add_theme_color_override("font_color", pop_color)

	# Staff section — hide for houses
	staff_label.visible = not is_house
	$Panel/VBox/StaffSection.visible = not is_house

	# Tavern menu management
	menu_button.visible = building.building_id == "tavern"
	if menu_button.visible:
		menu_button.text = "Manage Menu  (%d/%d dishes)" % [building.menu.size(), building.get_menu_slots()]

	if not is_house:
		var slots = building.get_staff_slots()
		var filled = building.assigned_staff.size()
		staff_label.text = "Employees:  %d / %d" % [filled, slots]
		_populate_staff(building)

	# Upgrade section
	var upgrade_cost = building.get_upgrade_cost()
	if upgrade_cost < 0:
		upgrade_cost_label.text = "Max tier reached"
		upgrade_button.disabled = true
	else:
		var next_level = building.level + 1
		var next_tier = building.tier
		if next_level > 3:
			next_level = 1
			next_tier += 1
		upgrade_cost_label.text = "Upgrade to T%dL%d:  %.0f gold" % [next_tier, next_level, upgrade_cost]
		upgrade_button.disabled = not EconomyManager.can_afford(upgrade_cost)

	_populate_residents(building)

func _populate_staff(building: PlacedBuilding) -> void:
	for child in staff_list.get_children():
		child.queue_free()

	if building.assigned_staff.is_empty():
		var lbl = Label.new()
		lbl.text = "No employees assigned."
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		staff_list.add_child(lbl)
		return

	for npc_id in building.assigned_staff:
		var npc = CitizenManager.get_citizen_by_id(npc_id)
		if not npc:
			continue
		var row = HBoxContainer.new()

		var name_lbl = Label.new()
		name_lbl.text = npc.get_full_name()
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var happiness_lbl = Label.new()
		npc.calculate_happiness()
		happiness_lbl.text = "%.0f%%" % npc.happiness
		happiness_lbl.add_theme_color_override("font_color", _score_color(npc.happiness))

		var wage_lbl = Label.new()
		wage_lbl.text = "%.0fg/day" % npc.daily_wage
		wage_lbl.add_theme_color_override("font_color", Color(0.8, 0.65, 0.4))

		var raise_btn = Button.new()
		raise_btn.text = "+Raise"
		raise_btn.custom_minimum_size = Vector2(70, 0)
		var wage_cap = npc.base_daily_wage * 1.5
		raise_btn.disabled = npc.daily_wage >= wage_cap
		raise_btn.pressed.connect(_show_raise_popup.bind(npc_id))

		var unassign_btn = Button.new()
		unassign_btn.text = "Unassign"
		unassign_btn.custom_minimum_size = Vector2(80, 0)
		unassign_btn.pressed.connect(_on_unassign_staff.bind(npc_id))

		row.add_child(name_lbl)
		row.add_child(happiness_lbl)
		row.add_child(wage_lbl)
		row.add_child(raise_btn)
		row.add_child(unassign_btn)
		staff_list.add_child(row)

func _populate_residents(building: PlacedBuilding) -> void:
	var is_house = building.building_id == "house"
	residents_section.visible = is_house
	if not is_house:
		return

	for child in residents_section.get_children():
		child.queue_free()

	var header = Label.new()
	header.text = "Residents  (%d / %d)" % [building.assigned_residents.size(), building.get_housing_capacity()]
	header.add_theme_color_override("font_color", Color(0.85, 0.75, 0.5))
	residents_section.add_child(header)

	if building.assigned_residents.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "  Nobody lives here."
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		residents_section.add_child(empty_lbl)
		return

	for npc_id in building.assigned_residents:
		var npc = CitizenManager.get_citizen_by_id(npc_id)
		if not npc:
			continue
		var row = HBoxContainer.new()

		var name_lbl = Label.new()
		name_lbl.text = npc.get_full_name()
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var wealth_data = DataManager.get_wealth_level(npc.wealth_level)
		var wealth_lbl = Label.new()
		wealth_lbl.text = wealth_data.get("label", "Wealth %d" % npc.wealth_level)
		wealth_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))

		var payment_type = "Rent" if npc.housing_type == "renter" else "Tax"
		var pay_lbl = Label.new()
		pay_lbl.text = "  %s: %.0fg/day" % [payment_type, npc.daily_payment]
		pay_lbl.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))

		row.add_child(name_lbl)
		row.add_child(wealth_lbl)
		row.add_child(pay_lbl)
		residents_section.add_child(row)

# ── Calculations ─────────────────────────────────────────────────────────────

func _calc_property_value(building: PlacedBuilding) -> float:
	var level_data = building.get_level_data()
	var base_cost = float(level_data.get("gold_cost", 100))
	# Rough cumulative investment across tiers
	var global_level = building.get_global_level()
	var investment = base_cost * global_level

	# Tier multiplier: T1=1.0, T2=1.5, T3=2.2
	var tier_mult = 1.0 + (building.tier - 1) * 0.6

	# Occupancy bonus: occupied slots add value
	var max_slots: int
	var filled: int
	if building.building_id == "house":
		max_slots = building.get_housing_capacity()
		filled = building.assigned_residents.size()
		# Resident wealth adds prestige
		var wealth_bonus = 0.0
		for npc_id in building.assigned_residents:
			var npc = CitizenManager.get_citizen_by_id(npc_id)
			if npc:
				wealth_bonus += npc.wealth_level * 15.0
		investment += wealth_bonus
	else:
		max_slots = building.get_staff_slots()
		filled = building.assigned_staff.size()

	var occupancy_bonus = 1.0 + (float(filled) / max(max_slots, 1)) * 0.35

	return investment * tier_mult * occupancy_bonus

func _calc_daily_income(building: PlacedBuilding) -> float:
	# A game-day is 60 real seconds = 1 real minute, so income/min == income/day
	var passive = building.get_income_per_minute()

	if building.building_id == "house":
		var rent_total = 0.0
		for npc_id in building.assigned_residents:
			var npc = CitizenManager.get_citizen_by_id(npc_id)
			if npc:
				rent_total += npc.daily_payment
		return passive + rent_total

	# Business: passive income minus wages of staff assigned here
	var wage_cost = 0.0
	for npc_id in building.assigned_staff:
		var npc = CitizenManager.get_citizen_by_id(npc_id)
		if npc:
			wage_cost += npc.daily_wage
	return passive - wage_cost

func _calc_popularity(building: PlacedBuilding) -> float:
	var score = 50.0
	var max_slots = building.get_staff_slots()
	if max_slots > 0:
		var filled = building.assigned_staff.size()
		score += (float(filled) / max_slots) * 20.0  # fully staffed = +20

		var total_happiness = 0.0
		for npc_id in building.assigned_staff:
			var npc = CitizenManager.get_citizen_by_id(npc_id)
			if npc:
				npc.calculate_happiness()
				total_happiness += npc.happiness
		if filled > 0:
			score += (total_happiness / filled / 100.0) * 20.0  # happy staff = +20

	score += (building.tier - 1) * 5.0  # T2: +5, T3: +10
	return clamp(score, 0.0, 100.0)

func _score_color(score: float) -> Color:
	if score >= 75: return Color(0.3, 0.9, 0.3)
	if score >= 50: return Color(0.9, 0.8, 0.2)
	return Color(0.9, 0.3, 0.3)

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

	# Cost line
	var cost_parts: Array = ["%.0f gold" % gold_cost]
	for r in res_cost:
		cost_parts.append("%d %s" % [int(res_cost[r]), r.replace("_", " ")])
	rows.append({"type": "cost", "text": "Cost:  " + "  +  ".join(cost_parts)})
	rows.append({"type": "header", "text": "WHAT CHANGES"})

	# Income
	var cur_income = float(cur_data.get("income_per_minute", 0))
	var new_income = float(next_data.get("income_per_minute", 0))
	if cur_income > 0.0 or new_income > 0.0:
		rows.append({
			"type": "row", "label": "Passive income",
			"old": "%.1f g/min" % cur_income, "new": "%.1f g/min" % new_income,
			"highlight": 1 if new_income > cur_income else 0
		})

	# Staff slots
	var cur_slots = int(cur_data.get("staff_slots", 0))
	var new_slots = int(next_data.get("staff_slots", 0))
	if cur_slots > 0 or new_slots > 0:
		rows.append({
			"type": "row", "label": "Staff slots",
			"old": str(cur_slots), "new": str(new_slots),
			"highlight": 1 if new_slots > cur_slots else 0
		})

	# Housing cap
	var cur_cap = int(cur_data.get("citizen_cap", 0))
	var new_cap = int(next_data.get("citizen_cap", 0))
	if cur_cap > 0 or new_cap > 0:
		rows.append({
			"type": "row", "label": "Housing capacity",
			"old": str(cur_cap), "new": str(new_cap),
			"highlight": 1 if new_cap > cur_cap else 0
		})

	# Building slots (town hall)
	var cur_bslots = int(cur_data.get("building_slots", 0))
	var new_bslots = int(next_data.get("building_slots", 0))
	if cur_bslots > 0 or new_bslots > 0:
		rows.append({
			"type": "row", "label": "Building slots",
			"old": str(cur_bslots), "new": str(new_bslots),
			"highlight": 1 if new_bslots > cur_bslots else 0
		})

	# Quest slots (guild hall)
	var cur_qslots = int(cur_data.get("quest_slots", 0))
	var new_qslots = int(next_data.get("quest_slots", 0))
	if cur_qslots > 0 or new_qslots > 0:
		rows.append({
			"type": "row", "label": "Quest slots",
			"old": str(cur_qslots), "new": str(new_qslots),
			"highlight": 1 if new_qslots > cur_qslots else 0
		})

	# Potion slots (magic tower)
	var cur_pslots = int(cur_data.get("potion_slots", 0))
	var new_pslots = int(next_data.get("potion_slots", 0))
	if cur_pslots > 0 or new_pslots > 0:
		rows.append({
			"type": "row", "label": "Potion slots",
			"old": str(cur_pslots), "new": str(new_pslots),
			"highlight": 1 if new_pslots > cur_pslots else 0
		})

	# Headhunt cost (guild hall)
	var cur_hh = int(cur_data.get("headhunt_cost", 0))
	var new_hh = int(next_data.get("headhunt_cost", 0))
	if cur_hh > 0 or new_hh > 0:
		rows.append({
			"type": "row", "label": "Headhunt cost",
			"old": "%dg" % cur_hh, "new": "%dg" % new_hh,
			"highlight": 1 if new_hh < cur_hh else 0  # cheaper = better
		})

	# Unlock / reward text
	var reward: String = next_data.get("reward", "")
	if reward != "":
		rows.append({"type": "unlock", "text": reward})

	_popup.open(
		"Upgrade %s  —  T%dL%d → T%dL%d" % [b.get_display_name(), b.tier, b.level, next_tier, next_level],
		rows,
		"Upgrade  (%.0fg)" % gold_cost,
		func(): _execute_upgrade()
	)

func _execute_upgrade() -> void:
	if not current_building:
		return
	if BuildingManager.upgrade_building(current_building.id):
		_populate(current_building)
		SignalBus.show_notification.emit(
			"%s upgraded to T%dL%d!" % [current_building.get_display_name(), current_building.tier, current_building.level]
		)

func _show_raise_popup(npc_id: String) -> void:
	var npc = CitizenManager.get_citizen_by_id(npc_id)
	if not npc:
		return
	var cap = npc.base_daily_wage * 1.5
	if npc.daily_wage >= cap:
		return

	var new_wage = minf(npc.daily_wage * 1.1, cap)
	var wealth_data = DataManager.get_wealth_level(npc.wealth_level)
	var fair_wage = float(wealth_data.get("base_rent", 5.0))

	# Project post-raise happiness
	var new_pay_h = clamp((new_wage / fair_wage - 0.8) * 125.0, -20.0, 50.0)
	var proj_h = 50.0 + npc.job_fit_bonus + new_pay_h
	if npc.assigned_job == "":
		proj_h -= 10.0
	if npc.house_building_id == "":
		proj_h -= 25.0
	proj_h = clamp(proj_h, 0.0, 100.0)

	# Work efficiency: income mult = 0.5 + (happiness / 100)
	var cur_eff  = 0.5 + (npc.happiness / 100.0)
	var new_eff  = 0.5 + (proj_h / 100.0)

	var rows: Array = [
		{"type": "header", "text": "COMPENSATION"},
		{
			"type": "row", "label": "Daily wage",
			"old": "%.0fg / day" % npc.daily_wage, "new": "%.0fg / day" % new_wage,
			"highlight": -1
		},
		{"type": "header", "text": "PERFORMANCE"},
		{
			"type": "row", "label": "Happiness",
			"old": "%.0f%%" % npc.happiness, "new": "%.0f%%" % proj_h,
			"highlight": 1 if proj_h > npc.happiness else 0
		},
		{
			"type": "row", "label": "Work efficiency",
			"old": "%.0f%%" % (cur_eff * 100.0), "new": "%.0f%%" % (new_eff * 100.0),
			"highlight": 1 if new_eff > cur_eff else 0
		},
		{
			"type": "note",
			"text": "Happier staff run their building more efficiently. At 100% happiness a building earns 50% more than its base rate; at 0% it earns half."
		},
		{"type": "cost", "text": "Extra daily cost:  +%.0fg / day" % (new_wage - npc.daily_wage)},
	]

	# Warn if at or near the raise cap
	if new_wage >= cap:
		rows.append({"type": "note", "text": "This is the maximum raise for this employee (cap: +50% above starting wage)."})

	_popup.open(
		"Give Raise  —  %s" % npc.get_full_name(),
		rows,
		"Give Raise",
		func(): _execute_raise(npc_id, new_wage, fair_wage)
	)

func _execute_raise(npc_id: String, new_wage: float, fair_wage: float) -> void:
	var npc = CitizenManager.get_citizen_by_id(npc_id)
	if not npc:
		return
	npc.daily_wage = new_wage
	npc.recalculate_pay_happiness(fair_wage)
	SignalBus.show_notification.emit(
		"%s got a raise — %.0fg/day  (happiness: %.0f%%)" % [npc.get_full_name(), npc.daily_wage, npc.happiness]
	)
	if current_building:
		_populate(current_building)

func _on_unassign_staff(npc_id: String) -> void:
	CitizenManager.unassign_from_building(npc_id)
	if current_building:
		_populate(current_building)

func _on_sell() -> void:
	if not current_building:
		return
	# Refund 50 % of the T1-L1 build cost — upgrades are a sunk cost
	var base_data = DataManager.get_building_level_data(current_building.building_id, 1, 1)
	var refund    = float(base_data.get("gold_cost", 0)) * 0.5
	EconomyManager.add_gold(refund, "Sold " + current_building.get_display_name())
	SignalBus.show_notification.emit(
		"Sold %s for %.0f gold." % [current_building.get_display_name(), refund]
	)
	BuildingManager.remove_building(current_building.id)
	current_building = null
	visible = false
