extends Control

# Reassignment window — a large centered list of every business in town.
# Opened from the inspector's Move → Reassign; click Assign to move the
# employee to any business with an open slot.

var current_npc: NPC = null

@onready var title_label: Label = $Panel/Title
@onready var subtitle_label: Label = $Panel/SubTitle
@onready var close_button: Button = $Panel/CloseButton
@onready var business_list: VBoxContainer = $Panel/Scroll/BusinessList

func _ready() -> void:
	visible = false
	SignalBus.open_reassign_panel.connect(show_panel)
	SignalBus.close_all_panels.connect(func(): visible = false)
	close_button.pressed.connect(func(): visible = false)

func show_panel(npc: NPC) -> void:
	current_npc = npc
	_rebuild()
	visible = true

func _rebuild() -> void:
	for child in business_list.get_children():
		child.queue_free()

	var npc = current_npc
	title_label.text = "Reassign %s" % npc.get_full_name()
	var good_data = DataManager.get_citizen_skill(npc.good_skill)
	subtitle_label.text = "Skill: %s  •  Current wage: %.0fg/day  •  Pick a new workplace below" % [
		good_data.get("label", npc.good_skill), npc.daily_wage
	]

	var businesses: Array = []
	for b in BuildingManager.get_all_buildings():
		if b.get_staff_slots() > 0:
			businesses.append(b)

	if businesses.is_empty():
		var lbl := Label.new()
		lbl.text = "No businesses in town yet."
		lbl.add_theme_font_size_override("font_size", 30)
		lbl.add_theme_color_override("font_color", Color(0.4, 0.29, 0.18))
		business_list.add_child(lbl)
		return

	for b in businesses:
		business_list.add_child(_make_business_row(b, npc))
		business_list.add_child(HSeparator.new())

func _make_business_row(b: PlacedBuilding, npc: NPC) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 128)
	row.add_theme_constant_override("separation", 14)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER

	var is_current = b.id == npc.job_building_id
	var name_lbl := Label.new()
	name_lbl.text = "%s  (T%d L%d)%s" % [
		b.get_display_name(), b.tier, b.level, "   ← current job" if is_current else ""
	]
	name_lbl.add_theme_font_size_override("font_size", 32)
	info.add_child(name_lbl)

	# Staffing, projected pay, and how well their skill fits here
	var filled = b.assigned_staff.size()
	var slots = b.get_staff_slots()
	var fair_here = CitizenManager.get_fair_wage_at(npc, b)
	var projected_wage = maxf(npc.daily_wage, fair_here * CitizenManager.HIRE_WAGE_FRACTION)
	var detail_lbl := Label.new()
	detail_lbl.text = "Staff %d/%d   •   pays ~%.0fg/day   •   %s" % [
		filled, slots, projected_wage, _fit_text(npc, b)
	]
	detail_lbl.add_theme_font_size_override("font_size", 26)
	detail_lbl.add_theme_color_override("font_color", _fit_color(npc, b))
	info.add_child(detail_lbl)

	row.add_child(info)

	var assign_btn := Button.new()
	assign_btn.custom_minimum_size = Vector2(260, 88)
	assign_btn.add_theme_font_size_override("font_size", 30)
	if is_current:
		assign_btn.text = "Current"
		assign_btn.disabled = true
	elif not b.can_add_staff():
		assign_btn.text = "Full"
		assign_btn.disabled = true
	else:
		assign_btn.text = "Assign"
		assign_btn.pressed.connect(func(): _on_assign(b.id))
	row.add_child(assign_btn)

	return row

func _fit_text(npc: NPC, b: PlacedBuilding) -> String:
	for pos in b.get_positions():
		if npc.good_skill in pos.get("good_skills", []):
			return "★ Great fit"
		if npc.good_skill in pos.get("bad_skills", []):
			return "✗ Bad fit"
	return "— Neutral fit"

func _fit_color(npc: NPC, b: PlacedBuilding) -> Color:
	match _fit_text(npc, b):
		"★ Great fit":
			return Color(0.15, 0.45, 0.12)
		"✗ Bad fit":
			return Color(0.62, 0.16, 0.1)
	return Color(0.42, 0.33, 0.22)

func _on_assign(building_instance_id: String) -> void:
	if current_npc == null:
		return
	if CitizenManager.assign_to_building(current_npc.id, building_instance_id):
		var b = BuildingManager.get_building_by_id(building_instance_id)
		SignalBus.show_notification.emit("%s now works at %s." % [
			current_npc.get_full_name(),
			b.get_display_name() if b else "their new job"
		])
		visible = false
