extends Control

# Tavern menu management — assign unlocked dishes to this tavern's menu slots.
# Dishes on the menu are served automatically each game day while staff are assigned.

var current_building: PlacedBuilding = null

@onready var title_label: Label = $Panel/Title
@onready var subtitle_label: Label = $Panel/SubTitle
@onready var close_button: Button = $Panel/CloseButton
@onready var dish_list: VBoxContainer = $Panel/ScrollContainer/DishList

func _ready() -> void:
	visible = false
	SignalBus.open_tavern_menu.connect(show_panel)
	SignalBus.close_all_panels.connect(func(): visible = false)
	close_button.pressed.connect(func(): visible = false)
	RecipeManager.recipes_updated.connect(func():
		if visible and current_building:
			_rebuild()
	)

func show_panel(building: PlacedBuilding) -> void:
	current_building = building
	_rebuild()
	visible = true

func _rebuild() -> void:
	for child in dish_list.get_children():
		child.queue_free()

	var b = current_building
	title_label.text = "%s — Menu" % b.get_display_name()
	subtitle_label.text = "Tier %d  •  %d/%d menu slots  •  %d staff serving  •  Dishes are cooked each day if ingredients are in stock" % [
		b.tier, b.menu.size(), b.get_menu_slots(), b.assigned_staff.size()
	]
	if b.assigned_staff.is_empty():
		subtitle_label.text += "  ⚠ No staff — nothing will be served!"

	_add_header("ON THE MENU")
	if b.menu.is_empty():
		_add_hint("Nothing yet — add dishes below.")
	for dish_id in b.menu:
		_add_dish_row(dish_id, true)

	_add_header("KNOWN RECIPES")
	var any_available = false
	for dish_id in RecipeManager.unlocked_dishes:
		if dish_id in b.menu:
			continue
		any_available = true
		_add_dish_row(dish_id, false)
	if not any_available:
		_add_hint("No further recipes known. Quests, seasons, and new ingredients unlock more.")

	# Locked dishes — shown greyed with their unlock hints
	var locked: Array = []
	for dish_id in DataManager.recipes.get("dishes", {}):
		if dish_id != "comment" and not RecipeManager.is_dish_unlocked(dish_id):
			locked.append(dish_id)
	if not locked.is_empty():
		_add_header("UNDISCOVERED")
		for dish_id in locked:
			var dish = DataManager.get_dish(dish_id)
			var lbl := Label.new()
			var hint = RecipeManager.describe_unlock(dish.get("unlock", {}))
			lbl.text = "🔒 %s   %s" % [dish.get("name", dish_id), hint]
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dish_list.add_child(lbl)

func _add_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	dish_list.add_child(lbl)
	dish_list.add_child(HSeparator.new())

func _add_hint(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	dish_list.add_child(lbl)

func _add_dish_row(dish_id: String, on_menu: bool) -> void:
	var dish = DataManager.get_dish(dish_id)
	if dish.is_empty():
		return

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_lbl := Label.new()
	name_lbl.text = dish.get("name", dish_id)
	name_lbl.add_theme_font_size_override("font_size", 14)
	info.add_child(name_lbl)

	var ingredients: Dictionary = dish.get("ingredients", {})
	var ing_parts: Array = []
	for res_id in ingredients:
		ing_parts.append("%s ×%d (%d)" % [
			RecipeManager.pretty_name(res_id), int(ingredients[res_id]),
			int(ResourceManager.get_amount(res_id))
		])
	var detail_lbl := Label.new()
	detail_lbl.text = "%.0fg/serve  •  +%d rep  •  +%.0f happiness  •  Needs: %s" % [
		float(dish.get("gold_per_serve", 0)), int(dish.get("reputation_gain", 0)),
		float(dish.get("happiness_bonus", 0)), ", ".join(PackedStringArray(ing_parts))
	]
	detail_lbl.add_theme_font_size_override("font_size", 11)
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var can_cook = ResourceManager.can_afford_cost(ingredients)
	detail_lbl.add_theme_color_override("font_color",
		Color(0.7, 0.85, 0.7) if can_cook else Color(0.9, 0.6, 0.5))
	info.add_child(detail_lbl)

	var tier_req = int(dish.get("tavern_tier_required", 1))
	if current_building.tier < tier_req:
		var tier_lbl := Label.new()
		tier_lbl.text = "Requires tavern tier %d" % tier_req
		tier_lbl.add_theme_font_size_override("font_size", 11)
		tier_lbl.add_theme_color_override("font_color", Color(0.9, 0.55, 0.35))
		info.add_child(tier_lbl)

	row.add_child(info)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(96, 34)
	btn.add_theme_font_size_override("font_size", 13)
	if on_menu:
		btn.text = "Remove"
		btn.pressed.connect(func():
			current_building.remove_menu_dish(dish_id)
			_rebuild()
		)
	else:
		btn.text = "Add"
		btn.disabled = not current_building.can_add_menu_dish() or current_building.tier < tier_req
		btn.pressed.connect(func():
			if current_building.add_menu_dish(dish_id):
				_rebuild()
		)
	row.add_child(btn)

	dish_list.add_child(row)
	dish_list.add_child(HSeparator.new())
