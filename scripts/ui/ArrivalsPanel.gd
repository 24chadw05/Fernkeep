extends Control

# Queue of wanderers waiting to join the city — replaces the old blocking
# ArrivalPopup. Opened from the circular arrivals button in the HUD.

@onready var title_label: Label = $Panel/Title
@onready var subtitle_label: Label = $Panel/SubTitle
@onready var close_button: Button = $Panel/CloseButton
@onready var arrival_list: VBoxContainer = $Panel/ScrollContainer/ArrivalList

const VILLAGER_VARIANTS: int = 5

func _ready() -> void:
	visible = false
	SignalBus.open_arrivals_panel.connect(show_panel)
	SignalBus.close_all_panels.connect(func(): visible = false)
	close_button.pressed.connect(func(): visible = false)
	CitizenManager.arrival_queue_changed.connect(_refresh_if_visible)
	CitizenManager.housing_updated.connect(_refresh_if_visible)

func _refresh_if_visible() -> void:
	if visible:
		_rebuild()

func show_panel() -> void:
	_rebuild()
	visible = true

func _rebuild() -> void:
	for child in arrival_list.get_children():
		child.queue_free()

	var pending: Array = CitizenManager.pending_arrivals
	var open_housing = CitizenManager.get_available_housing_count()
	var housing_text = "%d housing slot(s) open" % open_housing
	if open_housing <= 0:
		if BuildingManager.get_housing_buildings().is_empty():
			housing_text = "No houses built — build a House first!"
		else:
			housing_text = "Housing full! Build more houses to accept arrivals."
	subtitle_label.text = "%d waiting  •  %s" % [pending.size(), housing_text]

	if pending.is_empty():
		var lbl := Label.new()
		lbl.text = "No one is waiting right now. Travellers arrive as your city's demand grows."
		lbl.add_theme_font_size_override("font_size", 24)
		lbl.add_theme_color_override("font_color", Color(0.42, 0.33, 0.22))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		arrival_list.add_child(lbl)
		return

	for npc in pending:
		arrival_list.add_child(_build_card(npc, open_housing > 0))

func _build_card(npc: NPC, can_accept: bool) -> Control:
	var card := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	card.add_child(row)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(96, 96)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var idx = (absi(npc.id.hash()) % VILLAGER_VARIANTS) + 1
	portrait.texture = load("res://assets/sprites/villager_%d.png" % idx)
	row.add_child(portrait)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var name_lbl := Label.new()
	name_lbl.text = npc.get_full_name()
	name_lbl.add_theme_font_size_override("font_size", 28)
	info.add_child(name_lbl)

	var wealth_data = DataManager.get_wealth_level(npc.wealth_level)
	var meta_lbl := Label.new()
	meta_lbl.text = "Age %d  •  %s  •  Wealth %d" % [
		npc.age, wealth_data.get("label", "Unknown"), npc.wealth_level
	]
	meta_lbl.add_theme_font_size_override("font_size", 22)
	meta_lbl.add_theme_color_override("font_color", Color(0.42, 0.33, 0.22))
	info.add_child(meta_lbl)

	var good_data = DataManager.get_citizen_skill(npc.good_skill)
	var bad_data = DataManager.get_bad_skill(npc.bad_skill)
	var skill_type = "★ Special" if npc.is_special_skill else "Good"
	var skills_lbl := Label.new()
	skills_lbl.text = "%s: %s   •   Bad: %s" % [
		skill_type,
		good_data.get("label", npc.good_skill),
		bad_data.get("label", npc.bad_skill),
	]
	skills_lbl.add_theme_font_size_override("font_size", 22)
	skills_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if npc.is_special_skill:
		skills_lbl.add_theme_color_override("font_color", Color(0.55, 0.42, 0.05))
	info.add_child(skills_lbl)

	var detail_lbl := Label.new()
	var details = "Savings: %.0f gold" % npc.savings
	var hobby_data = DataManager.get_hobby(npc.hobby)
	if not hobby_data.is_empty():
		details += "   •   Hobby: %s" % hobby_data.get("label", npc.hobby)
	if npc.kids > 0:
		details += "   •   Kids: %d" % npc.kids
	detail_lbl.text = details
	detail_lbl.add_theme_font_size_override("font_size", 22)
	detail_lbl.add_theme_color_override("font_color", Color(0.42, 0.33, 0.22))
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(detail_lbl)

	var offer_lbl := Label.new()
	var offer_type = "Rent" if npc.housing_type == "renter" else "Tax (owner)"
	offer_lbl.text = "%s: %.0f gold/day" % [offer_type, npc.daily_payment]
	offer_lbl.add_theme_font_size_override("font_size", 24)
	offer_lbl.add_theme_color_override("font_color", Color(0.15, 0.45, 0.12))
	info.add_child(offer_lbl)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(buttons)

	var accept := Button.new()
	accept.text = "Accept"
	accept.custom_minimum_size = Vector2(190, 64)
	accept.disabled = not can_accept
	if not can_accept:
		accept.tooltip_text = "No housing available"
	accept.pressed.connect(func(): CitizenManager.accept_arrival(npc))
	buttons.add_child(accept)

	var decline := Button.new()
	decline.text = "Decline"
	decline.custom_minimum_size = Vector2(190, 64)
	decline.pressed.connect(func(): CitizenManager.decline_arrival(npc))
	buttons.add_child(decline)

	return card
