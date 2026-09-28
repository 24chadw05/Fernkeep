extends Control

# Read-only full-profile card for a single NPC. Opened by the small "ⓘ" button
# next to a citizen's name in the building menus, via SignalBus.

const VILLAGER_VARIANTS: int = 6

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/Title
@onready var close_button: Button = $Panel/CloseButton
@onready var vbox: VBoxContainer = $Panel/Scroll/VBox

func _ready() -> void:
	visible = false
	SignalBus.open_character_profile.connect(show_npc)
	SignalBus.close_all_panels.connect(func(): visible = false)
	close_button.pressed.connect(func(): visible = false)

func show_npc(npc: NPC) -> void:
	if npc == null:
		return
	_build(npc)
	visible = true
	move_to_front()

func _build(npc: NPC) -> void:
	for child in vbox.get_children():
		child.queue_free()

	title_label.text = npc.get_full_name()

	# ── Portrait + headline ──
	npc.calculate_happiness()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	var portrait := TextureRect.new()
	var idx = (absi(npc.id.hash()) % VILLAGER_VARIANTS) + 1
	var tex: Texture2D = load("res://assets/sprites/villager_%d.png" % idx)
	if tex:
		portrait.texture = tex
	portrait.custom_minimum_size = Vector2(120, 120)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	head.add_child(portrait)

	var wealth_data = DataManager.get_wealth_level(npc.wealth_level)
	var headline := _label("Age %d   •   %s   •   Wealth %d/10" % [
		npc.age, wealth_data.get("label", "Unknown"), npc.wealth_level
	], 28, Color(0.35, 0.28, 0.16))
	headline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(headline)
	vbox.add_child(head)

	# ── Skills ──
	_section("SKILLS")
	var good_data = DataManager.get_citizen_skill(npc.good_skill)
	var bad_data = DataManager.get_bad_skill(npc.bad_skill)
	var skill_prefix = "★ Special" if npc.is_special_skill else "✦ Good"
	_label("%s:  %s" % [skill_prefix, good_data.get("label", npc.good_skill)], 28, Color(0.2, 0.42, 0.12))
	if npc.is_special_skill and good_data.has("description"):
		_label("   %s" % good_data.get("description", ""), 22, Color(0.42, 0.33, 0.22))
	_label("✗ Bad:  %s" % bad_data.get("label", npc.bad_skill), 28, Color(0.6, 0.16, 0.1))

	# ── Housing & work ──
	_section("HOME & WORK")
	var housing_str = "Renter" if npc.housing_type == "renter" else "Owner"
	if npc.house_building_id != "":
		var house = BuildingManager.get_building_by_id(npc.house_building_id)
		var house_name = house.get_display_name() if house else "Unknown House"
		_label("Housing:  %s  •  %s  •  %.0fg/day" % [housing_str, house_name, npc.daily_payment], 28, Color(0.32, 0.28, 0.18))
	else:
		_label("Housing:  %s  •  Homeless  •  %.0fg/day" % [housing_str, npc.daily_payment], 28, Color(0.6, 0.16, 0.1))

	if npc.is_employed:
		var building = BuildingManager.get_building_by_id(npc.job_building_id)
		var bname = building.get_display_name() if building else "Unknown"
		_label("Job:  %s  •  %.0fg/day wage" % [bname, npc.daily_wage], 28, Color(0.32, 0.28, 0.18))
	else:
		_label("Job:  Unemployed", 28, Color(0.42, 0.33, 0.22))
	_label("Days in town:  %d" % npc.days_in_town, 24, Color(0.42, 0.33, 0.22))

	# ── Happiness breakdown ──
	_section("HAPPINESS  —  %.0f / 100" % npc.happiness)
	_happiness_row("Base wellbeing", 35.0)
	if npc.job_fit_bonus != 0.0:
		_happiness_row("Job-skill fit", npc.job_fit_bonus)
	if npc.pay_happiness != 0.0:
		_happiness_row("Pay vs. fair wage", npc.pay_happiness)
	if npc.assigned_job == "":
		_happiness_row("Unemployed", -10.0)
	if npc.house_building_id == "":
		_happiness_row("Homeless", -25.0)
	elif npc.housing_bonus != 0.0:
		_happiness_row("Home comfort", npc.housing_bonus)
	if npc.amenity_bonus != 0.0:
		_happiness_row("Town amenities", npc.amenity_bonus)
	if npc.comfort_bonus != 0.0:
		_happiness_row("Savings & hobby", npc.comfort_bonus)
	if npc.needs_penalty != 0.0:
		_happiness_row("Unmet needs", -npc.needs_penalty)

	# ── Personal finances ──
	_section("PERSONAL LIFE")
	var hobby_data = DataManager.get_hobby(npc.hobby)
	var hobby_str = "%s (%.0fg/day)" % [
		hobby_data.get("label", npc.hobby.capitalize()), float(hobby_data.get("daily_cost", 0))
	] if not hobby_data.is_empty() else "None"
	_label("Savings:  %.0fg" % npc.savings, 28, Color(0.41, 0.35, 0.13))
	_label("Hobby:  %s" % hobby_str, 26, Color(0.32, 0.28, 0.18))
	if npc.kids > 0:
		_label("Children:  %d" % npc.kids, 26, Color(0.32, 0.28, 0.18))

# ── Small builders ────────────────────────────────────────────────────────────

func _section(text: String) -> void:
	var sep := HSeparator.new()
	vbox.add_child(sep)
	var lbl := _label(text, 26, Color(0.45, 0.38, 0.2))
	lbl.add_theme_constant_override("outline_size", 0)

func _label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(lbl)
	return lbl

func _happiness_row(name: String, value: float) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "   " + name
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color(0.42, 0.33, 0.22))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var val := Label.new()
	val.text = "%+.0f" % value
	val.add_theme_font_size_override("font_size", 24)
	val.add_theme_color_override("font_color", Color(0.2, 0.42, 0.12) if value >= 0.0 else Color(0.6, 0.16, 0.1))
	row.add_child(val)
	vbox.add_child(row)
