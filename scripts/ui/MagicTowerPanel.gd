extends Control

# Magic tower — brew potions from gathered ingredients.
# One brew at a time; effects are temporary buffs or permanent city blessings.

var current_building: PlacedBuilding = null

@onready var title_label: Label = $Panel/Title
@onready var subtitle_label: Label = $Panel/SubTitle
@onready var close_button: Button = $Panel/CloseButton
@onready var potion_list: VBoxContainer = $Panel/ScrollContainer/PotionList

var _progress_bar: ProgressBar = null
var _progress_label: Label = null

func _ready() -> void:
	visible = false
	SignalBus.open_magic_tower_panel.connect(show_panel)
	SignalBus.close_all_panels.connect(func(): visible = false)
	close_button.pressed.connect(func(): visible = false)
	RecipeManager.recipes_updated.connect(func(): _refresh_if_visible())
	RecipeManager.potion_crafted.connect(func(_p): _refresh_if_visible())
	RecipeManager.effects_changed.connect(func(): _refresh_if_visible())

func _process(_delta: float) -> void:
	if visible and RecipeManager.is_crafting() and _progress_bar:
		_progress_bar.value = RecipeManager.get_craft_progress() * 100.0
		var potion = DataManager.get_potion(RecipeManager.crafting_potion_id)
		_progress_label.text = "Brewing %s — %ds left" % [
			potion.get("name", "..."), int(ceil(RecipeManager.craft_time_remaining))
		]

func _refresh_if_visible() -> void:
	if visible and current_building:
		_rebuild()

func show_panel(building: PlacedBuilding) -> void:
	current_building = building
	_rebuild()
	visible = true

func _rebuild() -> void:
	for child in potion_list.get_children():
		child.queue_free()
	_progress_bar = null
	_progress_label = null

	var b = current_building
	title_label.text = "Magic Tower"
	subtitle_label.text = "Tier %d  •  Level %d  •  Combine ingredients into potions and blessings" % [b.tier, b.level]

	# Brew in progress
	if RecipeManager.is_crafting():
		_progress_label = Label.new()
		_progress_label.add_theme_font_size_override("font_size", 13)
		_progress_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.95))
		potion_list.add_child(_progress_label)
		_progress_bar = ProgressBar.new()
		_progress_bar.custom_minimum_size = Vector2(0, 18)
		_progress_bar.max_value = 100.0
		_progress_bar.value = RecipeManager.get_craft_progress() * 100.0
		potion_list.add_child(_progress_bar)
		potion_list.add_child(HSeparator.new())

	# Active effects
	if not RecipeManager.active_effects.is_empty() or RecipeManager.permanent_happiness_bonus > 0.0:
		_add_header("ACTIVE EFFECTS")
		for e in RecipeManager.active_effects:
			var lbl := Label.new()
			var mins = int(e["remaining"]) / 60
			var secs = int(e["remaining"]) % 60
			lbl.text = "✦ %s — %d:%02d remaining" % [e.get("name", "Effect"), mins, secs]
			lbl.add_theme_font_size_override("font_size", 12)
			lbl.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
			potion_list.add_child(lbl)
		if RecipeManager.permanent_happiness_bonus > 0.0:
			var perm_lbl := Label.new()
			perm_lbl.text = "✦ Permanent blessings: +%.1f city happiness" % RecipeManager.permanent_happiness_bonus
			perm_lbl.add_theme_font_size_override("font_size", 12)
			perm_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
			potion_list.add_child(perm_lbl)
		potion_list.add_child(HSeparator.new())

	_add_header("KNOWN POTIONS")
	var any_known = false
	for potion_id in RecipeManager.unlocked_potions:
		any_known = true
		_add_potion_row(potion_id)
	if not any_known:
		var hint := Label.new()
		hint.text = "No potion recipes known yet."
		hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		potion_list.add_child(hint)

	var locked: Array = []
	for potion_id in DataManager.recipes.get("potions", {}):
		if not RecipeManager.is_potion_unlocked(potion_id):
			locked.append(potion_id)
	if not locked.is_empty():
		_add_header("UNDISCOVERED")
		for potion_id in locked:
			var potion = DataManager.get_potion(potion_id)
			var lbl := Label.new()
			lbl.text = "🔒 %s   %s" % [
				potion.get("name", potion_id),
				RecipeManager.describe_unlock(potion.get("unlock", {}))
			]
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			potion_list.add_child(lbl)

func _add_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	potion_list.add_child(lbl)
	potion_list.add_child(HSeparator.new())

func _add_potion_row(potion_id: String) -> void:
	var potion = DataManager.get_potion(potion_id)
	if potion.is_empty():
		return

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_lbl := Label.new()
	name_lbl.text = potion.get("name", potion_id)
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.7, 0.95))
	info.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = potion.get("description", "")
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc_lbl)

	var ingredients: Dictionary = potion.get("ingredients", {})
	var ing_parts: Array = []
	for res_id in ingredients:
		ing_parts.append("%s ×%d (%d)" % [
			RecipeManager.pretty_name(res_id), int(ingredients[res_id]),
			int(ResourceManager.get_amount(res_id))
		])
	var ing_lbl := Label.new()
	ing_lbl.text = "Needs: %s  •  Brew time: %ds" % [
		", ".join(PackedStringArray(ing_parts)), int(potion.get("craft_time_seconds", 30))
	]
	ing_lbl.add_theme_font_size_override("font_size", 11)
	ing_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ing_lbl.add_theme_color_override("font_color",
		Color(0.7, 0.85, 0.7) if ResourceManager.can_afford_cost(ingredients) else Color(0.9, 0.6, 0.5))
	info.add_child(ing_lbl)

	var blocker = RecipeManager.get_craft_blocker(potion_id)
	if blocker != "" and blocker != "Missing ingredients.":
		var block_lbl := Label.new()
		block_lbl.text = blocker
		block_lbl.add_theme_font_size_override("font_size", 11)
		block_lbl.add_theme_color_override("font_color", Color(0.9, 0.55, 0.35))
		info.add_child(block_lbl)

	row.add_child(info)

	var btn := Button.new()
	btn.text = "Brew"
	btn.custom_minimum_size = Vector2(96, 34)
	btn.add_theme_font_size_override("font_size", 13)
	btn.disabled = blocker != ""
	btn.pressed.connect(func():
		if RecipeManager.start_craft(potion_id):
			_rebuild()
	)
	row.add_child(btn)

	potion_list.add_child(row)
	potion_list.add_child(HSeparator.new())
