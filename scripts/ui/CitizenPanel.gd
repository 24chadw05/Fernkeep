extends Control

var selected_npc: NPC = null
var finance_label: Label = null
var ledger_label: Label = null

@onready var citizen_list: VBoxContainer = $Panel/Left/Scroll/CitizenList
@onready var close_button: Button = $Panel/CloseButton
@onready var no_selection_label: Label = $Panel/Right/NoSelectionLabel

@onready var name_label: Label = $Panel/Right/Detail/NameLabel
@onready var details_label: Label = $Panel/Right/Detail/DetailsLabel
@onready var skills_label: Label = $Panel/Right/Detail/SkillsLabel
@onready var housing_label: Label = $Panel/Right/Detail/HousingLabel
@onready var happiness_label: Label = $Panel/Right/Detail/HappinessLabel
@onready var days_label: Label = $Panel/Right/Detail/DaysLabel

@onready var job_label: Label = $Panel/Right/Detail/JobSection/JobLabel
@onready var building_picker: OptionButton = $Panel/Right/Detail/JobSection/BuildingPicker
@onready var assign_button: Button = $Panel/Right/Detail/JobSection/Buttons/AssignButton
@onready var unassign_button: Button = $Panel/Right/Detail/JobSection/Buttons/UnassignButton

func _ready() -> void:
	visible = false
	SignalBus.open_citizen_panel.connect(toggle)
	close_button.pressed.connect(func(): visible = false)
	assign_button.pressed.connect(_on_assign)
	unassign_button.pressed.connect(_on_unassign)
	CitizenManager.connect("citizen_arrived", _on_roster_changed)
	CitizenManager.connect("citizen_assigned", _on_roster_changed)

	# Personal finances — created dynamically under the happiness label
	var detail = $Panel/Right/Detail
	finance_label = Label.new()
	finance_label.add_theme_font_size_override("font_size", 26)
	finance_label.add_theme_color_override("font_color", Color(0.41, 0.35, 0.13))
	detail.add_child(finance_label)
	detail.move_child(finance_label, happiness_label.get_index() + 1)

	ledger_label = Label.new()
	ledger_label.add_theme_font_size_override("font_size", 24)
	ledger_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(ledger_label)
	detail.move_child(ledger_label, finance_label.get_index() + 1)

	_set_detail_visible(false)

func toggle() -> void:
	visible = not visible
	if visible:
		_refresh_list()

func _refresh_list() -> void:
	for child in citizen_list.get_children():
		child.queue_free()

	if CitizenManager.citizens.is_empty():
		var empty = Label.new()
		empty.text = "No citizens yet."
		empty.add_theme_color_override("font_color", Color(0.4, 0.29, 0.18))
		citizen_list.add_child(empty)
		return

	for npc in CitizenManager.citizens:
		var btn = Button.new()
		var job_tag = " [%s]" % _short_job(npc) if npc.is_employed else ""
		btn.text = npc.get_full_name() + job_tag
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 76)
		btn.pressed.connect(_on_citizen_selected.bind(npc.id))
		# Highlight selected
		if selected_npc and selected_npc.id == npc.id:
			btn.disabled = false
			btn.modulate = Color(0.7, 1.0, 0.7)
		citizen_list.add_child(btn)

	# Re-show current selection if still valid
	if selected_npc:
		var still_exists = CitizenManager.get_citizen_by_id(selected_npc.id)
		if still_exists:
			_show_citizen(still_exists)
		else:
			selected_npc = null
			_set_detail_visible(false)

func _on_citizen_selected(npc_id: String) -> void:
	selected_npc = CitizenManager.get_citizen_by_id(npc_id)
	if selected_npc:
		_show_citizen(selected_npc)
	_refresh_list()

func _show_citizen(npc: NPC) -> void:
	_set_detail_visible(true)

	name_label.text = npc.get_full_name()

	var wealth_data = DataManager.get_wealth_level(npc.wealth_level)
	details_label.text = "Age %d   •   %s   •   Wealth %d/10" % [
		npc.age,
		wealth_data.get("label", "Unknown"),
		npc.wealth_level
	]

	var good_data = DataManager.get_citizen_skill(npc.good_skill)
	var bad_data = DataManager.get_bad_skill(npc.bad_skill)
	var skill_prefix = "★ Special" if npc.is_special_skill else "✦ Good"
	skills_label.text = "%s:  %s\n✗  Bad:   %s" % [
		skill_prefix,
		good_data.get("label", npc.good_skill),
		bad_data.get("label", npc.bad_skill)
	]

	var housing_str = "Renter" if npc.housing_type == "renter" else "Owner"
	if npc.house_building_id != "":
		var house = BuildingManager.get_building_by_id(npc.house_building_id)
		var house_name = house.get_display_name() if house else "Unknown House"
		housing_label.text = "Housing: %s  •  %s  •  %.0fg/day" % [housing_str, house_name, npc.daily_payment]
	else:
		housing_label.text = "Housing: %s  •  Homeless  •  %.0fg/day" % [housing_str, npc.daily_payment]
		housing_label.add_theme_color_override("font_color", Color(0.41, 0.11, 0.05))

	npc.calculate_happiness()
	happiness_label.text = "Happiness: %.0f / 100" % npc.happiness
	days_label.text = "Days in town: %d" % npc.days_in_town
	_show_finances(npc)

	# Job section
	if npc.is_employed:
		var building = BuildingManager.get_building_by_id(npc.job_building_id)
		var bname = building.get_display_name() if building else "Unknown"
		job_label.text = "Current job:  %s" % bname
	else:
		job_label.text = "Current job:  Unemployed"

	_populate_building_picker(npc)
	assign_button.disabled = false
	unassign_button.disabled = not npc.is_employed

func _show_finances(npc: NPC) -> void:
	var hobby_data = DataManager.get_hobby(npc.hobby)
	var hobby_str = "%s (%.0fg/day)" % [
		hobby_data.get("label", npc.hobby.capitalize()), float(hobby_data.get("daily_cost", 0))
	] if not hobby_data.is_empty() else "None"
	var kids_str = "  •  Kids: %d" % npc.kids if npc.kids > 0 else ""
	finance_label.text = "Savings: %.0fg  •  Hobby: %s%s" % [npc.savings, hobby_str, kids_str]

	var ledger: Dictionary = npc.last_ledger
	if ledger.is_empty():
		ledger_label.text = "No spending recorded yet — check back tomorrow."
		ledger_label.add_theme_color_override("font_color", Color(0.4, 0.29, 0.18))
		return

	# One line per cost — cut items show an explicit 0g plus the happiness hit,
	# so a glance at the ledger explains this citizen's mood
	var skipped: Array = ledger.get("skipped", [])
	var lines: Array = []

	var wage = float(ledger.get("income", 0))
	if wage > 0.0:
		lines.append("Wage:  +%.0fg" % wage)
	elif npc.is_employed:
		lines.append("Wage:  0g — treasury couldn't pay!")
	else:
		lines.append("Wage:  0g — unemployed")

	if npc.house_building_id != "":
		var housing_word = "Rent" if npc.housing_type == "renter" else "Tax"
		if "rent" in skipped:
			lines.append("%s:  0g — couldn't pay  (happiness −10)" % housing_word)
		else:
			var housing_key = "rent" if npc.housing_type == "renter" else "tax"
			lines.append("%s:  −%.0fg" % [housing_word, float(ledger.get(housing_key, 0))])

	if "food" in skipped:
		lines.append("Food:  0g — going hungry  (happiness −18)")
	else:
		lines.append("Food:  −%.0fg" % float(ledger.get("food", 0)))

	if npc.kids > 0:
		if "kids" in skipped:
			lines.append("Kids:  0g — can't provide  (happiness −15)")
		else:
			lines.append("Kids:  −%.0fg" % float(ledger.get("kids", 0)))

	if not DataManager.get_hobby(npc.hobby).is_empty():
		if "hobby" in skipped:
			lines.append("Hobby:  0g — cut  (happiness −6)")
		else:
			lines.append("Hobby:  −%.0fg" % float(ledger.get("hobby", 0)))

	var net = wage - float(ledger.get("rent", 0)) \
		- float(ledger.get("tax", 0)) - float(ledger.get("food", 0)) \
		- float(ledger.get("kids", 0)) - float(ledger.get("hobby", 0))
	lines.append("Net:  %+.0fg / day" % net)

	if not skipped.is_empty():
		ledger_label.add_theme_color_override("font_color", Color(0.41, 0.16, 0.1))
	else:
		ledger_label.add_theme_color_override("font_color", Color(0.32, 0.24, 0.15))
	ledger_label.text = "Yesterday's ledger:\n" + "\n".join(PackedStringArray(lines))

func _populate_building_picker(npc: NPC) -> void:
	building_picker.clear()
	building_picker.add_item("— select a building —")
	building_picker.set_item_metadata(0, "")

	for building in BuildingManager.get_all_buildings():
		if building.get_staff_slots() <= 0:
			continue
		var has_slot = building.can_add_staff()
		var is_current = building.id == npc.job_building_id
		if not has_slot and not is_current:
			continue

		var fit_str = _fit_label(npc, building)
		var slot_str = "%d/%d staff" % [building.assigned_staff.size(), building.get_staff_slots()]
		var label = "%s  [%s]  %s" % [building.get_display_name(), slot_str, fit_str]

		building_picker.add_item(label)
		var idx = building_picker.item_count - 1
		building_picker.set_item_metadata(idx, building.id)

		# Pre-select current building
		if is_current:
			building_picker.selected = idx

func _fit_label(npc: NPC, building: PlacedBuilding) -> String:
	var positions = building.get_positions()
	for pos in positions:
		if npc.good_skill in pos.get("good_skills", []):
			return "★ Great fit"
		if npc.good_skill in pos.get("bad_skills", []):
			return "✗ Bad fit"
	return ""

func _short_job(npc: NPC) -> String:
	var building = BuildingManager.get_building_by_id(npc.job_building_id)
	return building.get_display_name() if building else "?"

func _set_detail_visible(show: bool) -> void:
	no_selection_label.visible = not show
	$Panel/Right/Detail.visible = show

func _on_assign() -> void:
	if not selected_npc:
		return
	var idx = building_picker.selected
	if idx <= 0:
		return
	var building_id = building_picker.get_item_metadata(idx)
	if building_id == "":
		return
	if CitizenManager.assign_to_building(selected_npc.id, building_id):
		_show_citizen(selected_npc)
		_refresh_list()

func _on_unassign() -> void:
	if not selected_npc:
		return
	CitizenManager.unassign_from_building(selected_npc.id)
	_show_citizen(selected_npc)
	_refresh_list()

func _on_roster_changed(_a = null, _b = null) -> void:
	if visible:
		_refresh_list()
