extends Control

var current_building: PlacedBuilding = null

@onready var title_label: Label = $Panel/Title
@onready var close_button: Button = $Panel/CloseButton
@onready var name_label: Label = $Panel/Scroll/VBox/NameLabel
@onready var tier_label: Label = $Panel/Scroll/VBox/TierLabel
@onready var income_label: Label = $Panel/Scroll/VBox/IncomeLabel
@onready var staff_label: Label = $Panel/Scroll/VBox/StaffLabel
@onready var upgrade_cost_label: Label = $Panel/Scroll/VBox/UpgradeSection/UpgradeCostLabel
@onready var upgrade_button: Button = $Panel/Scroll/VBox/UpgradeSection/UpgradeButton
@onready var staff_list: VBoxContainer = $Panel/Scroll/VBox/StaffSection/StaffList
@onready var sell_button: Button = $Panel/Scroll/VBox/SellButton

# Which employee's Move options are expanded (one at a time)
var _expanded_npc_id: String = ""

var property_value_label: Label = null
var daily_income_label: Label = null
var production_label: Label = null
var popularity_label: Label = null
var residents_section: VBoxContainer = null
var menu_button: Button = null
var spec_section: VBoxContainer = null

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

	var vbox = $Panel/Scroll/VBox

	# Property value — shown for all buildings
	property_value_label = Label.new()
	property_value_label.add_theme_font_size_override("font_size", 28)
	property_value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	property_value_label.add_theme_color_override("font_color", Color(0.41, 0.35, 0.1))
	vbox.add_child(property_value_label)
	vbox.move_child(property_value_label, income_label.get_index() + 1)

	# Daily income summary — shown for all buildings
	daily_income_label = Label.new()
	daily_income_label.add_theme_font_size_override("font_size", 28)
	daily_income_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	daily_income_label.add_theme_color_override("font_color", Color(0.21, 0.43, 0.21))
	vbox.add_child(daily_income_label)
	vbox.move_child(daily_income_label, property_value_label.get_index() + 1)

	# Resource production — shown for producers (mining, logging, farm)
	production_label = Label.new()
	production_label.add_theme_font_size_override("font_size", 26)
	production_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	production_label.add_theme_color_override("font_color", Color(0.22, 0.4, 0.2))
	vbox.add_child(production_label)
	vbox.move_child(production_label, daily_income_label.get_index() + 1)

	# Popularity score — shown for non-house buildings
	popularity_label = Label.new()
	popularity_label.add_theme_font_size_override("font_size", 28)
	popularity_label.add_theme_color_override("font_color", Color(0.23, 0.26, 0.39))
	vbox.add_child(popularity_label)
	vbox.move_child(popularity_label, daily_income_label.get_index() + 1)

	# Residents section — shown for house buildings
	residents_section = VBoxContainer.new()
	residents_section.visible = false
	vbox.add_child(residents_section)

	# Menu management — shown for taverns only
	menu_button = Button.new()
	menu_button.text = "Manage Menu"
	menu_button.add_theme_font_size_override("font_size", 28)
	menu_button.custom_minimum_size = Vector2(0, 64)
	menu_button.visible = false
	menu_button.pressed.connect(func():
		if current_building:
			SignalBus.open_tavern_menu.emit(current_building)
	)
	vbox.add_child(menu_button)

	# Tier-3 tavern specialization — filled in per building
	spec_section = VBoxContainer.new()
	spec_section.add_theme_constant_override("separation", 6)
	spec_section.visible = false
	vbox.add_child(spec_section)
	vbox.move_child(spec_section, menu_button.get_index())

func _refresh_if_visible() -> void:
	if visible and current_building:
		_populate(current_building)

func show_building(building: PlacedBuilding) -> void:
	if current_building != building:
		_expanded_npc_id = ""
	current_building = building
	_populate(building)
	visible = true

func _populate(building: PlacedBuilding) -> void:
	var is_house = building.building_id == "house"

	name_label.text = building.get_display_name()
	tier_label.text = "Tier %d  •  Level %d  (Overall level %d)" % [building.tier, building.level, building.get_global_level()]

	var base_income = building.get_income_per_minute()
	var productivity = BuildingManager.get_productivity(building)
	if building.get_staff_slots() > 0:
		income_label.text = "Income: %.1f g/day  (%.0f%% productivity)" % [
			base_income * productivity, productivity * 100.0
		]
	else:
		income_label.text = "Passive income: %.1f gold / day" % base_income

	# Property value
	property_value_label.text = "Property value:  %.0f gold" % _calc_property_value(building)

	# Daily income
	var daily = _calc_daily_income(building)
	daily_income_label.text = "Daily income:  %.0f gold" % daily

	# Resource production breakdown (mining/logging/farm)
	_populate_production(building)

	# Popularity (businesses only)
	popularity_label.visible = not is_house
	if not is_house:
		var pop = _calc_popularity(building)
		var pop_color = _score_color(pop)
		popularity_label.text = "Popularity:  %.0f / 100" % pop
		popularity_label.add_theme_color_override("font_color", pop_color)

	# Staff section — hide for houses
	staff_label.visible = not is_house
	$Panel/Scroll/VBox/StaffSection.visible = not is_house

	# Tavern menu management
	menu_button.visible = building.building_id == "tavern"
	if menu_button.visible:
		menu_button.text = "Manage Menu  (%d/%d dishes)" % [building.menu.size(), building.get_menu_slots()]
	_populate_specialization(building)

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

# Tier-3 branch UI: a maxed tavern picks Grand Tavern or a cuisine restaurant
func _populate_specialization(building: PlacedBuilding) -> void:
	for child in spec_section.get_children():
		child.queue_free()
	spec_section.visible = false
	if building.building_id != "tavern":
		return

	if building.specialization != "":
		spec_section.visible = true
		var done_lbl := Label.new()
		done_lbl.text = "✦ %s" % building.get_spec_info().get("blurb", "Specialized.")
		done_lbl.add_theme_font_size_override("font_size", 24)
		done_lbl.add_theme_color_override("font_color", Color(0.41, 0.35, 0.16))
		done_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		spec_section.add_child(done_lbl)
		return

	if not building.can_specialize():
		return

	spec_section.visible = true
	var header := Label.new()
	header.text = "SPECIALIZE — %.0fg, permanent" % BuildingManager.SPECIALIZE_COST
	header.add_theme_font_size_override("font_size", 26)
	header.add_theme_color_override("font_color", Color(0.41, 0.35, 0.16))
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	spec_section.add_child(header)

	for spec_id in PlacedBuilding.SPECIALIZATIONS:
		var info: Dictionary = PlacedBuilding.SPECIALIZATIONS[spec_id]
		var btn := Button.new()
		btn.text = info["label"]
		btn.custom_minimum_size = Vector2(0, 60)
		btn.add_theme_font_size_override("font_size", 26)
		btn.tooltip_text = info["blurb"]
		btn.pressed.connect(_confirm_specialize.bind(spec_id))
		spec_section.add_child(btn)

func _confirm_specialize(spec_id: String) -> void:
	if not current_building:
		return
	var info: Dictionary = PlacedBuilding.SPECIALIZATIONS[spec_id]
	var rows: Array = [
		{"type": "cost", "text": "Cost:  %.0f gold" % BuildingManager.SPECIALIZE_COST},
		{"type": "header", "text": "WHAT YOU GET"},
		{"type": "note", "text": info["blurb"]},
		{"type": "note", "text": "This choice is permanent — this tavern becomes the %s." % info["label"]},
	]
	_popup.open(
		"Specialize  —  %s" % info["label"],
		rows,
		"Open the %s" % info["label"],
		func():
			if BuildingManager.specialize_tavern(current_building, spec_id):
				_populate(current_building)
	)

func _populate_staff(building: PlacedBuilding) -> void:
	for child in staff_list.get_children():
		child.queue_free()

	if building.assigned_staff.is_empty():
		var lbl = Label.new()
		lbl.text = "No employees assigned."
		lbl.add_theme_font_size_override("font_size", 28)
		lbl.add_theme_color_override("font_color", Color(0.4, 0.29, 0.18))
		staff_list.add_child(lbl)
		return

	for npc_id in building.assigned_staff:
		var npc = CitizenManager.get_citizen_by_id(npc_id)
		if not npc:
			continue
		staff_list.add_child(_make_employee_card(npc, building))

# One employee: name + Move button, a salary/happiness/fit line, a +Raise,
# and (when Move is toggled) the Fire / Reassign options expanded to the right.
func _make_employee_card(npc: NPC, building: PlacedBuilding) -> PanelContainer:
	var card := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	# Row 1: name + Move
	var top := HBoxContainer.new()
	top.add_child(_make_info_button(npc))

	var name_lbl := Label.new()
	name_lbl.text = npc.get_full_name()
	name_lbl.add_theme_font_size_override("font_size", 30)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_lbl)

	var move_btn := Button.new()
	move_btn.text = "Move ◂" if _expanded_npc_id == npc.id else "Move ▸"
	move_btn.custom_minimum_size = Vector2(150, 58)
	move_btn.add_theme_font_size_override("font_size", 26)
	move_btn.pressed.connect(func(): _toggle_move(npc.id))
	top.add_child(move_btn)
	box.add_child(top)

	# Row 2: salary • happiness • fit — flows onto a second line in the narrow panel
	var stats := HFlowContainer.new()
	stats.add_theme_constant_override("h_separation", 16)
	stats.add_theme_constant_override("v_separation", 2)

	var wage_lbl := Label.new()
	wage_lbl.text = "%.0fg/day" % npc.daily_wage
	wage_lbl.add_theme_font_size_override("font_size", 26)
	wage_lbl.add_theme_color_override("font_color", Color(0.46, 0.35, 0.16))
	stats.add_child(wage_lbl)

	npc.calculate_happiness()
	var happiness_lbl := Label.new()
	happiness_lbl.text = "%.0f%% happy" % npc.happiness
	happiness_lbl.add_theme_font_size_override("font_size", 26)
	happiness_lbl.add_theme_color_override("font_color", _score_color(npc.happiness))
	stats.add_child(happiness_lbl)

	var fit_lbl := Label.new()
	fit_lbl.text = _fit_text(npc)
	fit_lbl.add_theme_font_size_override("font_size", 26)
	fit_lbl.add_theme_color_override("font_color", _fit_color(npc))
	stats.add_child(fit_lbl)
	box.add_child(stats)

	# Row 3: +Raise on its own line (big text needs the room)
	var raise_btn := Button.new()
	raise_btn.text = "+Raise"
	raise_btn.custom_minimum_size = Vector2(150, 52)
	raise_btn.add_theme_font_size_override("font_size", 24)
	raise_btn.disabled = npc.daily_wage >= npc.base_daily_wage * 2.5
	raise_btn.pressed.connect(_show_raise_popup.bind(npc.id))
	var raise_row := HBoxContainer.new()
	raise_row.alignment = BoxContainer.ALIGNMENT_END
	raise_row.add_child(raise_btn)
	box.add_child(raise_row)

	# Expanded Move options — flows to a second line if the panel is too narrow
	if _expanded_npc_id == npc.id:
		var options := HFlowContainer.new()
		options.add_theme_constant_override("h_separation", 12)
		options.add_theme_constant_override("v_separation", 8)
		options.alignment = FlowContainer.ALIGNMENT_END

		var fire_btn := Button.new()
		fire_btn.text = "Fire"
		fire_btn.custom_minimum_size = Vector2(140, 64)
		fire_btn.add_theme_font_size_override("font_size", 28)
		fire_btn.add_theme_color_override("font_color", Color(0.41, 0.11, 0.08))
		fire_btn.pressed.connect(func(): _on_fire(npc.id))
		options.add_child(fire_btn)

		var reassign_btn := Button.new()
		reassign_btn.text = "Reassign…"
		reassign_btn.custom_minimum_size = Vector2(200, 64)
		reassign_btn.add_theme_font_size_override("font_size", 28)
		reassign_btn.pressed.connect(func(): _on_reassign(npc.id))
		options.add_child(reassign_btn)

		box.add_child(options)

	return card

# Small "ⓘ" button that opens the citizen's full character profile.
func _make_info_button(npc: NPC) -> Button:
	var info_btn := Button.new()
	info_btn.text = "i"
	info_btn.custom_minimum_size = Vector2(52, 52)
	info_btn.add_theme_font_size_override("font_size", 28)
	info_btn.tooltip_text = "View %s's full profile" % npc.get_full_name()
	info_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_btn.pressed.connect(func(): SignalBus.open_character_profile.emit(npc))
	return info_btn

func _fit_text(npc: NPC) -> String:
	if npc.job_fit_bonus > 0.0:
		return "★ Great fit"
	if npc.job_fit_bonus < 0.0:
		return "✗ Bad fit"
	return "— Neutral fit"

func _fit_color(npc: NPC) -> Color:
	if npc.job_fit_bonus > 0.0:
		return Color(0.15, 0.45, 0.12)
	if npc.job_fit_bonus < 0.0:
		return Color(0.62, 0.16, 0.1)
	return Color(0.42, 0.33, 0.22)

func _toggle_move(npc_id: String) -> void:
	_expanded_npc_id = "" if _expanded_npc_id == npc_id else npc_id
	if current_building:
		_populate_staff(current_building)

func _on_fire(npc_id: String) -> void:
	var npc = CitizenManager.get_citizen_by_id(npc_id)
	CitizenManager.unassign_from_building(npc_id)
	_expanded_npc_id = ""
	if npc:
		SignalBus.show_notification.emit("%s has been let go." % npc.get_full_name())
	if current_building:
		_populate(current_building)

func _on_reassign(npc_id: String) -> void:
	var npc = CitizenManager.get_citizen_by_id(npc_id)
	if npc:
		SignalBus.open_reassign_panel.emit(npc)

func _populate_residents(building: PlacedBuilding) -> void:
	var is_house = building.building_id == "house"
	residents_section.visible = is_house
	if not is_house:
		return

	for child in residents_section.get_children():
		child.queue_free()

	var header = Label.new()
	header.text = "Residents  (%d / %d)" % [building.assigned_residents.size(), building.get_housing_capacity()]
	header.add_theme_font_size_override("font_size", 28)
	header.add_theme_color_override("font_color", Color(0.45, 0.38, 0.2))
	residents_section.add_child(header)

	if building.assigned_residents.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "  Nobody lives here."
		empty_lbl.add_theme_font_size_override("font_size", 26)
		empty_lbl.add_theme_color_override("font_color", Color(0.4, 0.29, 0.18))
		residents_section.add_child(empty_lbl)
		return

	for npc_id in building.assigned_residents:
		var npc = CitizenManager.get_citizen_by_id(npc_id)
		if not npc:
			continue
		var row = HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 12)
		row.add_theme_constant_override("v_separation", 0)

		row.add_child(_make_info_button(npc))

		var name_lbl = Label.new()
		name_lbl.text = npc.get_full_name()
		name_lbl.add_theme_font_size_override("font_size", 26)

		var wealth_data = DataManager.get_wealth_level(npc.wealth_level)
		var wealth_lbl = Label.new()
		wealth_lbl.text = wealth_data.get("label", "Wealth %d" % npc.wealth_level)
		wealth_lbl.add_theme_font_size_override("font_size", 24)
		wealth_lbl.add_theme_color_override("font_color", Color(0.35, 0.26, 0.16))

		var payment_type = "Rent" if npc.housing_type == "renter" else "Tax"
		var pay_lbl = Label.new()
		pay_lbl.text = "%s: %.0fg/day" % [payment_type, npc.daily_payment]
		pay_lbl.add_theme_font_size_override("font_size", 24)
		pay_lbl.add_theme_color_override("font_color", Color(0.29, 0.43, 0.29))

		row.add_child(name_lbl)
		row.add_child(wealth_lbl)
		row.add_child(pay_lbl)
		residents_section.add_child(row)

# Resource output for producers — daily amount + the gold each is worth at
# market, so the player can see the resources they're "paying wages" for.
func _populate_production(building: PlacedBuilding) -> void:
	var production: Dictionary = building.get_level_data().get("resource_production", {})
	if production.is_empty():
		production_label.visible = false
		return
	production_label.visible = true

	var staff = building.assigned_staff.size()
	var yield_mult = BuildingManager.get_yield_multiplier(building)
	var lines: Array = ["Daily output" + ("  (idle — assign staff)" if staff == 0 else ":")]
	var total_value = 0.0
	for res_id in production:
		var per_day = float(production[res_id]) * staff * yield_mult
		var unit_value = MarketManager.get_current_value(res_id)
		var day_value = per_day * unit_value
		total_value += day_value
		lines.append("  • %s %s/day  ×  %.0fg each  =  %.0fg/day" % [
			_fmt(per_day), ResourceManager.get_item_label(res_id), unit_value, day_value
		])
	if total_value > 0.0:
		lines.append("Resource value:  ~%.0f gold / day" % total_value)
	production_label.text = "\n".join(PackedStringArray(lines))

func _fmt(v: float) -> String:
	return "%.0f" % v if v >= 10.0 or v == floor(v) else "%.1f" % v

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
	var passive = BuildingManager.get_live_income_per_minute(building)

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
	if score >= 75: return Color(0.15, 0.45, 0.12)
	if score >= 50: return Color(0.55, 0.42, 0.05)
	return Color(0.62, 0.14, 0.1)

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

	# Income — from the invested-gold formula, not the legacy per-level data
	var cur_income = DataManager.get_base_income_per_minute(b.building_id, b.tier, b.level)
	var new_income = DataManager.get_base_income_per_minute(b.building_id, next_tier, next_level)
	if cur_income > 0.0 or new_income > 0.0:
		rows.append({
			"type": "row", "label": "Base income",
			"old": "%.1f g/day" % cur_income, "new": "%.1f g/day" % new_income,
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
	var blocker = BuildingManager.get_upgrade_blocker(current_building)
	if blocker != "":
		SignalBus.show_notification_timed.emit(blocker, 1.5)
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
	var cap = npc.base_daily_wage * 2.5
	if npc.daily_wage >= cap:
		return

	var new_wage = minf(npc.daily_wage * 1.1, cap)
	var fair_wage = CitizenManager.get_fair_wage(npc)

	# Project post-raise happiness (pay component changes, the rest stays)
	var new_pay_h = clamp((new_wage / fair_wage - 0.8) * 100.0, -20.0, 25.0)
	var proj_h = clamp(npc.calculate_happiness() - npc.pay_happiness + new_pay_h, 0.0, 100.0)

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
			"text": "Happier staff work harder: a fully staffed building runs at 40%-160% of base income depending on happiness. Raises also boost their spending money — and the rent they can pay you."
		},
		{"type": "cost", "text": "Extra daily cost:  +%.0fg / day" % (new_wage - npc.daily_wage)},
	]

	# What the extra money unlocks — anything they skipped yesterday that the
	# new wage should cover (spending priority: rent → food → kids → hobby)
	var skipped: Array = npc.last_ledger.get("skipped", [])
	if not skipped.is_empty():
		var remaining = new_wage
		var rent_cost = minf(npc.base_daily_payment, new_wage * CitizenManager.RENT_INCOME_CAP)
		var covers_rent = remaining >= rent_cost
		if covers_rent:
			remaining -= rent_cost
		var food_cost = CitizenManager.get_daily_food_cost(npc)
		var covers_food = remaining >= food_cost
		if covers_food:
			remaining -= food_cost
		var kid_cost = CitizenManager.KID_COST * npc.kids
		var covers_kids = remaining >= kid_cost
		if npc.kids > 0 and covers_kids:
			remaining -= kid_cost
		var hobby_data = DataManager.get_hobby(npc.hobby)
		var hobby_cost = float(hobby_data.get("daily_cost", 0.0))
		var covers_hobby = not hobby_data.is_empty() and remaining >= hobby_cost

		if "rent" in skipped and covers_rent:
			var pay_word = "rent" if npc.housing_type == "renter" else "tax"
			rows.append({"type": "unlock", "text": "They could pay %s again — +%.0fg/day back to you" % [pay_word, rent_cost]})
		if "food" in skipped and covers_food:
			rows.append({"type": "unlock", "text": "They could afford food again (+18 happiness)"})
		if "kids" in skipped and npc.kids > 0 and covers_kids:
			rows.append({"type": "unlock", "text": "They could support their kids again (+15 happiness)"})
		if "hobby" in skipped and covers_hobby:
			rows.append({"type": "unlock", "text": "They could fund their %s hobby again (+%d happiness)" % [
				hobby_data.get("label", npc.hobby), 6 + int(hobby_data.get("happiness_bonus", 0))
			]})

	# Warn if at or near the raise cap
	if new_wage >= cap:
		rows.append({"type": "note", "text": "This is the maximum raise for this employee (cap: +150% above starting wage)."})

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
	CitizenManager.update_daily_payment(npc)
	SignalBus.show_notification.emit(
		"%s got a raise — %.0fg/day  (happiness: %.0f%%)" % [npc.get_full_name(), npc.daily_wage, npc.happiness]
	)
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
