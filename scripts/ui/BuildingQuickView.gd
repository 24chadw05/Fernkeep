extends Panel
# Compact popup shown when any building is clicked.
# Appears near the cursor; "Manage →" opens the full BuildingInspector.

var current_building: PlacedBuilding = null

var _name_lbl:    Label
var _tier_lbl:    Label
var _value_lbl:   Label
var _income_lbl:  Label
var _pop_lbl:     Label
var _occ_header:  Label
var _occ_list:    VBoxContainer

const POPUP_WIDTH  = 290
const POPUP_MARGIN = 14

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(POPUP_WIDTH, 0)

	# ── outer margin ────────────────────────────────────────────
	var margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	# ── header ──────────────────────────────────────────────────
	var header = HBoxContainer.new()
	vbox.add_child(header)

	_name_lbl = Label.new()
	_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	header.add_child(_name_lbl)

	_tier_lbl = Label.new()
	_tier_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	header.add_child(_tier_lbl)

	var close_btn = Button.new()
	close_btn.text = " ✕ "
	close_btn.flat = true
	close_btn.pressed.connect(func(): visible = false)
	header.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	# ── stats ────────────────────────────────────────────────────
	_value_lbl  = _lbl(Color(0.95, 0.85, 0.4))
	_income_lbl = _lbl(Color(0.5,  0.9,  0.5))
	_pop_lbl    = _lbl(Color(0.7,  0.75, 1.0))
	vbox.add_child(_value_lbl)
	vbox.add_child(_income_lbl)
	vbox.add_child(_pop_lbl)

	vbox.add_child(HSeparator.new())

	# ── occupants ────────────────────────────────────────────────
	_occ_header = _lbl(Color(0.85, 0.75, 0.5))
	vbox.add_child(_occ_header)

	_occ_list = VBoxContainer.new()
	_occ_list.add_theme_constant_override("separation", 3)
	vbox.add_child(_occ_list)

	vbox.add_child(HSeparator.new())

	# ── manage button ────────────────────────────────────────────
	var manage_btn = Button.new()
	manage_btn.text = "Manage / Upgrade  →"
	manage_btn.pressed.connect(_on_manage)
	vbox.add_child(manage_btn)

	# ── signals ──────────────────────────────────────────────────
	SignalBus.building_selected.connect(_on_building_selected)
	SignalBus.close_all_panels.connect(func(): visible = false)

func _lbl(color: Color) -> Label:
	var l = Label.new()
	l.add_theme_color_override("font_color", color)
	return l

# ── signal handler ───────────────────────────────────────────────

func _on_building_selected(building: PlacedBuilding) -> void:
	current_building = building
	_populate(building)
	_reposition()
	visible = true

func _populate(building: PlacedBuilding) -> void:
	var is_house = building.building_id == "house"

	_name_lbl.text  = building.get_display_name()
	_tier_lbl.text  = "  T%d L%d" % [building.tier, building.level]

	_value_lbl.text  = "Value:   %.0f gold"      % _calc_value(building)
	_income_lbl.text = "Income:  %.0f gold/day"   % _calc_daily_income(building)

	_pop_lbl.visible = not is_house
	if not is_house:
		var pop = _calc_popularity(building)
		_pop_lbl.text = "Popularity:  %.0f / 100" % pop
		_pop_lbl.add_theme_color_override("font_color", _score_color(pop))

	_fill_occupants(building)

func _fill_occupants(building: PlacedBuilding) -> void:
	for c in _occ_list.get_children():
		c.queue_free()

	if building.building_id == "house":
		var cap   = building.get_housing_capacity()
		var count = building.assigned_residents.size()
		_occ_header.text = "Residents  %d / %d" % [count, cap]
		if count == 0:
			_occ_list.add_child(_dim("Nobody lives here."))
		else:
			for npc_id in building.assigned_residents:
				var npc = CitizenManager.get_citizen_by_id(npc_id)
				if not npc: continue
				var ptype = "Rent" if npc.housing_type == "renter" else "Tax"
				_occ_list.add_child(_row(
					npc.get_full_name(),
					"%s  %.0fg/day" % [ptype, npc.daily_payment],
					Color(0.6, 0.9, 0.6)
				))
	else:
		var slots = building.get_staff_slots()
		var count = building.assigned_staff.size()
		_occ_header.text = "Employees  %d / %d" % [count, slots]
		if slots == 0:
			_occ_list.add_child(_dim("No staff positions."))
		elif count == 0:
			_occ_list.add_child(_dim("No employees assigned."))
		else:
			for npc_id in building.assigned_staff:
				var npc = CitizenManager.get_citizen_by_id(npc_id)
				if not npc: continue
				npc.calculate_happiness()
				_occ_list.add_child(_row(
					npc.get_full_name(),
					"%.0f%%  •  %.0fg/day" % [npc.happiness, npc.daily_wage],
					_score_color(npc.happiness)
				))

func _row(left: String, right: String, right_color: Color) -> HBoxContainer:
	var row = HBoxContainer.new()
	var ll = Label.new(); ll.text = left
	ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ll.add_theme_font_size_override("font_size", 13)
	var rl = Label.new(); rl.text = right
	rl.add_theme_color_override("font_color", right_color)
	rl.add_theme_font_size_override("font_size", 13)
	row.add_child(ll); row.add_child(rl)
	return row

func _dim(text: String) -> Label:
	var l = Label.new()
	l.text = "  " + text
	l.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	l.add_theme_font_size_override("font_size", 13)
	return l

func _reposition() -> void:
	# Wait one frame so the panel's minimum size is computed after content change
	await get_tree().process_frame
	var vp    = get_viewport_rect().size
	var mpos  = get_viewport().get_mouse_position()
	var psize = get_combined_minimum_size()
	var x = clamp(mpos.x + POPUP_MARGIN, POPUP_MARGIN, vp.x - psize.x - POPUP_MARGIN)
	var y = clamp(mpos.y - psize.y * 0.5, POPUP_MARGIN, vp.y - psize.y - POPUP_MARGIN)
	position = Vector2(x, y)
	size = psize   # snap to minimum — don't stretch

# ── calculations ─────────────────────────────────────────────────

func _calc_value(b: PlacedBuilding) -> float:
	var ld       = b.get_level_data()
	var invest   = float(ld.get("gold_cost", 100)) * b.get_global_level()
	var tier_m   = 1.0 + (b.tier - 1) * 0.6
	var max_s: int
	var filled: int
	if b.building_id == "house":
		max_s  = b.get_housing_capacity()
		filled = b.assigned_residents.size()
		for id in b.assigned_residents:
			var n = CitizenManager.get_citizen_by_id(id)
			if n: invest += n.wealth_level * 15.0
	else:
		max_s  = b.get_staff_slots()
		filled = b.assigned_staff.size()
	return invest * tier_m * (1.0 + float(filled) / max(max_s, 1) * 0.35)

func _calc_daily_income(b: PlacedBuilding) -> float:
	var passive = b.get_income_per_minute()
	if b.building_id == "house":
		for id in b.assigned_residents:
			var n = CitizenManager.get_citizen_by_id(id)
			if n: passive += n.daily_payment
		return passive
	for id in b.assigned_staff:
		var n = CitizenManager.get_citizen_by_id(id)
		if n: passive -= n.daily_wage
	return passive

func _calc_popularity(b: PlacedBuilding) -> float:
	var score = 50.0
	var slots = b.get_staff_slots()
	if slots > 0:
		var filled = b.assigned_staff.size()
		score += float(filled) / slots * 20.0
		var h_total = 0.0
		for id in b.assigned_staff:
			var n = CitizenManager.get_citizen_by_id(id)
			if n: n.calculate_happiness(); h_total += n.happiness
		if filled > 0:
			score += h_total / filled / 100.0 * 20.0
	score += (b.tier - 1) * 5.0
	return clamp(score, 0.0, 100.0)

func _score_color(v: float) -> Color:
	if v >= 75: return Color(0.3, 0.9, 0.3)
	if v >= 50: return Color(0.9, 0.8, 0.2)
	return Color(0.9, 0.3, 0.3)

func _on_manage() -> void:
	if current_building:
		visible = false
		SignalBus.open_building_inspector.emit(current_building)
