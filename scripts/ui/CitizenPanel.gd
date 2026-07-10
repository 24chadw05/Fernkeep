extends Control

var selected_npc: NPC = null

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
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		citizen_list.add_child(empty)
		return

	for npc in CitizenManager.citizens:
		var btn = Button.new()
		var job_tag = " [%s]" % _short_job(npc) if npc.is_employed else ""
		btn.text = npc.get_full_name() + job_tag
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 38)
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
		housing_label.add_theme_color_override("font_color", Color(0.95, 0.4, 0.3))

	npc.calculate_happiness()
	happiness_label.text = "Happiness: %.0f / 100" % npc.happiness
	days_label.text = "Days in town: %d" % npc.days_in_town

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
