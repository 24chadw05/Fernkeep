extends Control

# Build menu — bottom bar with Buildings / Roads / Decor tabs.
# Cards show sprite, footprint, income, cost (live affordability colour),
# and a concrete unlock reason when locked.

const SECTIONS: Array = [
	{"label": "HOUSING & CIVIC", "ids": ["house"]},
	{"label": "COMMERCE",        "ids": ["tavern", "market", "guild_hall"]},
	{"label": "INDUSTRY",        "ids": ["farm", "logging_camp", "mining_operation", "blacksmith"]},
	{"label": "MYSTIC",          "ids": ["magic_tower"]},
]

const DECOR_IDS: Array = ["tree", "flower_bed", "well"]

const SPRITE_VARIANTS: Dictionary = {
	"house": [
		{"path": "res://assets/buildings/House_Cottage.png",     "label": "Cottage"},
		{"path": "res://assets/buildings/House_Timber.png",      "label": "Timber"},
		{"path": "res://assets/buildings/House_Stone.png",       "label": "Stone"},
		{"path": "res://assets/buildings/House_Hay_1.png",       "label": "Hay"},
		{"path": "res://assets/buildings/Fern_h_house1_2x2.png", "label": "Rustic"},
	],
	"tree": [
		{"path": "res://assets/decor/Tree_1.png", "label": "Oak"},
		{"path": "res://assets/decor/Tree_2.png", "label": "Elm"},
	],
}

const ROAD_TYPES: Array = [
	{"id": "dirt", "label": "Dirt Road", "path": "res://assets/roads/dirt.png", "cost": "Free"},
]

var _current_tab: String = "buildings"
var _sprite_panel: Control = null
# Cards needing live affordability recolour: [{"label": Label, "cost": float}]
var _cost_labels: Array = []

@onready var content_box:    HBoxContainer = $Panel/ScrollContainer/ContentBox
@onready var close_button:   Button        = $Panel/TabBar/CloseButton
@onready var tab_buildings:  Button        = $Panel/TabBar/TabBuildings
@onready var tab_roads:      Button        = $Panel/TabBar/TabRoads
@onready var tab_decor:      Button        = $Panel/TabBar/TabDecor
@onready var slots_label:    Label         = $Panel/TabBar/SlotsLabel

func _ready() -> void:
	visible = false
	SignalBus.open_build_menu.connect(toggle)
	close_button.pressed.connect(_close)
	tab_buildings.pressed.connect(func(): _switch_tab("buildings"))
	tab_roads.pressed.connect(func(): _switch_tab("roads"))
	tab_decor.pressed.connect(func(): _switch_tab("decor"))
	EconomyManager.gold_changed.connect(func(_g):
		if visible:
			_recolour_costs()
	)
	BuildingManager.building_placed.connect(func(_b):
		if visible:
			_update_slots_label()
	)
	call_deferred("_connect_sprite_panel")
	_build_content()

func _connect_sprite_panel() -> void:
	_sprite_panel = get_node_or_null("../SpriteSelectPanel")
	if _sprite_panel:
		_sprite_panel.sprite_selected.connect(_on_sprite_selected)

func toggle() -> void:
	visible = not visible
	if visible:
		_build_content()
	else:
		SignalBus.build_menu_closed.emit()
		if _sprite_panel:
			_sprite_panel._slide_out()

func _close() -> void:
	visible = false
	SignalBus.build_menu_closed.emit()
	if _sprite_panel:
		_sprite_panel._slide_out()

func _switch_tab(tab: String) -> void:
	_current_tab = tab
	_update_tab_highlights()
	_build_content()

func _update_tab_highlights() -> void:
	tab_buildings.flat = (_current_tab != "buildings")
	tab_roads.flat     = (_current_tab != "roads")
	tab_decor.flat     = (_current_tab != "decor")

# ── Content builders ──────────────────────────────────────────────────────────

func _build_content() -> void:
	for child in content_box.get_children():
		child.queue_free()
	_cost_labels.clear()
	_update_slots_label()
	match _current_tab:
		"buildings": _build_building_items()
		"roads":     _build_road_items()
		"decor":     _build_decor_items()

func _update_slots_label() -> void:
	slots_label.text = "Slots %d / %d" % [
		BuildingManager.get_non_town_hall_count(),
		BuildingManager.get_building_slot_limit(),
	]

func _build_building_items() -> void:
	for section in SECTIONS:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)

		var header := Label.new()
		header.text = section["label"]
		header.add_theme_font_size_override("font_size", 10)
		header.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		col.add_child(header)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for id in section["ids"]:
			var card = _make_building_card(id)
			if card:
				row.add_child(card)
		col.add_child(row)

		content_box.add_child(col)
		var sep := VSeparator.new()
		sep.custom_minimum_size = Vector2(10, 0)
		content_box.add_child(sep)

func _build_decor_items() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var header := Label.new()
	header.text = "DECOR — no road needed, doesn't use building slots"
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	col.add_child(header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for id in DECOR_IDS:
		var card = _make_building_card(id)
		if card:
			row.add_child(card)
	col.add_child(row)
	content_box.add_child(col)

func _build_road_items() -> void:
	for road in ROAD_TYPES:
		var card: PanelContainer = _make_card(road["label"], "Free", road["path"],
			"Click and drag to paint", true, "")
		var road_id: String = road["id"]
		card.gui_input.connect(func(e: InputEvent): _on_road_card_input(e, road_id))
		content_box.add_child(card)
	var erase_card: PanelContainer = _make_card("Erase Road", "Free", "",
		"Click and drag to erase", true, "✕")
	erase_card.gui_input.connect(func(e: InputEvent): _on_erase_card_input(e))
	content_box.add_child(erase_card)

# ── Card builders ─────────────────────────────────────────────────────────────

func _make_building_card(id: String) -> PanelContainer:
	var data: Dictionary = DataManager.get_building(id)
	if data.is_empty():
		return null
	var level_data: Dictionary = DataManager.get_building_level_data(id, 1, 1)
	var gold_cost := float(level_data.get("gold_cost", 0)) * QuestManager.get_cost_multiplier()
	var unlock = data.get("unlock", "default")
	var is_unlocked: bool = ProgressionManager.check_unlock_condition(unlock, id)

	var size: Array = data.get("size", [1, 1])
	var income := float(level_data.get("income_per_minute", 0))
	var info := "%d×%d" % [int(size[0]), int(size[1])]
	if income > 0.0:
		info += "  •  %.0fg/min" % income

	var variants: Array = SPRITE_VARIANTS.get(id, [])
	var sprite_path: String = variants[0]["path"] if not variants.is_empty() \
		else BuildingNode.SPRITE_MAP.get(id, "")

	var lock_reason := "" if is_unlocked else _describe_unlock(unlock, id)
	var card := _make_card(data.get("name", id), "%.0f gold" % gold_cost,
		sprite_path, info, is_unlocked, "", lock_reason, gold_cost)
	if is_unlocked:
		card.gui_input.connect(func(e: InputEvent): _on_card_input(e, id))
	return card

func _make_card(title: String, cost_text: String, sprite_path: String, info: String,
		unlocked: bool, icon_char: String = "", lock_reason: String = "",
		gold_cost: float = -1.0) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(118, 150)
	if unlocked:
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.mouse_entered.connect(func(): card.modulate = Color(1.12, 1.12, 1.05))
		card.mouse_exited.connect(func(): card.modulate = Color(1, 1, 1))

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	# Preview area: sprite, big glyph, or placeholder
	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(0, 70)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if icon_char != "":
		var icon := Label.new()
		icon.text = icon_char
		icon.add_theme_font_size_override("font_size", 36)
		icon.add_theme_color_override("font_color", Color(0.85, 0.25, 0.25))
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(icon)
	elif sprite_path != "" and ResourceLoader.exists(sprite_path):
		var tex := TextureRect.new()
		tex.texture = load(sprite_path)
		tex.custom_minimum_size = Vector2(68, 68)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not unlocked:
			tex.modulate = Color(0.35, 0.35, 0.4)
		center.add_child(tex)
	else:
		var placeholder := ColorRect.new()
		placeholder.custom_minimum_size = Vector2(64, 64)
		placeholder.color = Color(0.28, 0.28, 0.32) if unlocked else Color(0.14, 0.14, 0.14)
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(placeholder)
	vbox.add_child(center)

	var name_lbl := Label.new()
	name_lbl.text = ("🔒 " if not unlocked else "") + title
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	# Footprint / income (or road hint)
	if info != "":
		var info_lbl := Label.new()
		info_lbl.text = info
		info_lbl.add_theme_font_size_override("font_size", 9)
		info_lbl.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
		info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(info_lbl)

	if unlocked:
		var cost_lbl := Label.new()
		cost_lbl.text = cost_text
		cost_lbl.add_theme_font_size_override("font_size", 10)
		cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(cost_lbl)
		if gold_cost >= 0.0:
			_cost_labels.append({"label": cost_lbl, "cost": gold_cost})
			_colour_cost(cost_lbl, gold_cost)
		else:
			cost_lbl.add_theme_color_override("font_color", Color(0.80, 0.90, 0.40))
	else:
		var lock_lbl := Label.new()
		lock_lbl.text = lock_reason
		lock_lbl.add_theme_font_size_override("font_size", 9)
		lock_lbl.add_theme_color_override("font_color", Color(0.85, 0.6, 0.35))
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(lock_lbl)
		card.modulate.a = 0.7

	return card

func _colour_cost(lbl: Label, cost: float) -> void:
	lbl.add_theme_color_override("font_color",
		Color(0.80, 0.90, 0.40) if EconomyManager.can_afford(cost) else Color(0.92, 0.45, 0.40))

func _recolour_costs() -> void:
	for entry in _cost_labels:
		var lbl: Label = entry["label"]
		if is_instance_valid(lbl):
			_colour_cost(lbl, float(entry["cost"]))

# Human-readable unlock requirement for locked cards
func _describe_unlock(condition, building_id: String) -> String:
	if not (condition is Dictionary):
		return "Locked"
	var parts: Array = []
	if condition.has("player_level"):
		if condition.has("count_per_5_levels"):
			var base = int(condition.get("player_level", 1))
			var allowed = 1 + int((ProgressionManager.player_level - base) / 5.0)
			parts.append("Limit %d — next at level %d" % [
				allowed, base + allowed * 5
			])
		else:
			parts.append("Player level %d" % int(condition["player_level"]))
	if condition.has("town_hall_level"):
		parts.append("Town Hall level %d" % int(condition["town_hall_level"]))
	if condition.has("town_hall_tier"):
		parts.append("Town Hall tier %d" % int(condition["town_hall_tier"]))
	if condition.has("special_npc_skill"):
		parts.append("Needs a %s citizen" % str(condition["special_npc_skill"]))
	if parts.is_empty():
		return "Locked"
	return ", ".join(PackedStringArray(parts))

# ── Input handlers ────────────────────────────────────────────────────────────

func _on_card_input(event: InputEvent, building_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_building_selected(building_id)

func _on_road_card_input(event: InputEvent, road_type: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_start_road_mode(road_type)

func _on_erase_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		visible = false
		var build_grid: Node = get_tree().get_root().get_node_or_null("Node2D/BuildGrid")
		if build_grid:
			build_grid.start_road_erase_mode()

func _on_building_selected(building_id: String) -> void:
	var variants: Array = SPRITE_VARIANTS.get(building_id, [])
	if variants.size() <= 1 or not _sprite_panel:
		var path: String = variants[0]["path"] if not variants.is_empty() else ""
		_start_placement(building_id, path)
		return
	_sprite_panel.show_for_building(building_id, variants)

func _on_sprite_selected(building_id: String, sprite_path: String) -> void:
	_start_placement(building_id, sprite_path)

func _start_placement(building_id: String, sprite_path: String) -> void:
	visible = false
	var build_grid: Node = get_tree().get_root().get_node_or_null("Node2D/BuildGrid")
	if build_grid:
		build_grid.start_placement(building_id, sprite_path)

func _start_road_mode(road_type: String) -> void:
	visible = false
	var build_grid: Node = get_tree().get_root().get_node_or_null("Node2D/BuildGrid")
	if build_grid:
		build_grid.start_road_mode(road_type)
