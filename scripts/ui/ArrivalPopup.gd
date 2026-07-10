extends Control

@onready var name_label: Label = $Panel/VBox/NameLabel
@onready var wealth_label: Label = $Panel/VBox/WealthLabel
@onready var skills_label: Label = $Panel/VBox/SkillsLabel
@onready var offer_label: Label = $Panel/VBox/OfferLabel
@onready var accept_btn: Button = $Panel/VBox/Buttons/AcceptButton
@onready var decline_btn: Button = $Panel/VBox/Buttons/DeclineButton

var current_npc: NPC = null
var housing_label: Label = null

func _ready() -> void:
	visible = false
	CitizenManager.connect("arrival_pending", _on_arrival_pending)
	CitizenManager.connect("housing_updated", _refresh_housing_label)
	accept_btn.pressed.connect(_on_accept)
	decline_btn.pressed.connect(_on_decline)

	# Create housing availability label dynamically
	housing_label = Label.new()
	housing_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
	$Panel/VBox.add_child(housing_label)
	$Panel/VBox.move_child(housing_label, offer_label.get_index() + 1)

func _on_arrival_pending(npc: NPC) -> void:
	current_npc = npc
	_populate(npc)
	visible = true

func _populate(npc: NPC) -> void:
	name_label.text = npc.get_full_name()

	var wealth_data = DataManager.get_wealth_level(npc.wealth_level)
	wealth_label.text = "Age %d  •  %s  •  Wealth %d" % [
		npc.age,
		wealth_data.get("label", "Unknown"),
		npc.wealth_level
	]

	var good_data = DataManager.get_citizen_skill(npc.good_skill)
	var bad_data = DataManager.get_bad_skill(npc.bad_skill)
	var good_label_text = good_data.get("label", npc.good_skill)
	var bad_label_text = bad_data.get("label", npc.bad_skill)
	var skill_type = "★ Special" if npc.is_special_skill else "Good"
	skills_label.text = "%s skill: %s\nBad skill: %s" % [skill_type, good_label_text, bad_label_text]

	var offer_type = "Rent" if npc.housing_type == "renter" else "Tax (owner)"
	offer_label.text = "%s: %.0f gold/day" % [offer_type, npc.daily_payment]

	_refresh_housing_label()

func _refresh_housing_label() -> void:
	if not housing_label:
		return
	var open = CitizenManager.get_available_housing_count()
	if open > 0:
		housing_label.text = "Housing: %d slot(s) available" % open
		housing_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
		accept_btn.disabled = false
	else:
		var total_houses = BuildingManager.get_housing_buildings().size()
		if total_houses == 0:
			housing_label.text = "No houses built — build a House first!"
		else:
			housing_label.text = "Housing full! Build more houses or wages will rise."
		housing_label.add_theme_color_override("font_color", Color(0.95, 0.4, 0.3))
		accept_btn.disabled = true

func _on_accept() -> void:
	if current_npc:
		CitizenManager.accept_arrival(current_npc)
	visible = false

func _on_decline() -> void:
	if current_npc:
		CitizenManager.decline_arrival(current_npc)
	visible = false
