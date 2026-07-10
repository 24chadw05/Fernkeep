extends Control

# Distinct placeholder colors per resource — replace with sprites later
const RESOURCE_CONFIG: Dictionary = {
	"wood":             {"display": "Wood",             "color": Color(0.55, 0.35, 0.15)},
	"stone":            {"display": "Stone",            "color": Color(0.60, 0.60, 0.60)},
	"herbs":            {"display": "Herbs",            "color": Color(0.20, 0.70, 0.30)},
	"fish":             {"display": "Fish",             "color": Color(0.20, 0.50, 0.80)},
	"grain":            {"display": "Grain",            "color": Color(0.85, 0.75, 0.20)},
	"vegetables":       {"display": "Vegetables",       "color": Color(0.30, 0.75, 0.30)},
	"enchanted_ore":    {"display": "Enchanted Ore",    "color": Color(0.60, 0.20, 0.90)},
	"rare_ingredients": {"display": "Rare Ingredients", "color": Color(0.90, 0.40, 0.20)},
	"water":            {"display": "Water",            "color": Color(0.45, 0.70, 0.95)},
	"mushroom":         {"display": "Mushrooms",        "color": Color(0.75, 0.55, 0.40)},
	"wild_honey":       {"display": "Wild Honey",       "color": Color(0.95, 0.70, 0.15)},
	"boar_meat":        {"display": "Boar Meat",        "color": Color(0.80, 0.35, 0.30)},
	"basic_fruit":      {"display": "Fruit",            "color": Color(0.90, 0.45, 0.55)},
	"premium_fruit":    {"display": "Premium Fruit",    "color": Color(0.95, 0.30, 0.65)},
	"rare_herbs":       {"display": "Rare Herbs",       "color": Color(0.10, 0.55, 0.45)},
}

var current_building: PlacedBuilding = null

# resource_id → Dictionary of UI node references
var _rows: Dictionary = {}

@onready var title_label:    Label         = $Panel/Title
@onready var subtitle_label: Label         = $Panel/SubTitle
@onready var close_button:   Button        = $Panel/CloseButton
@onready var resource_list:  VBoxContainer = $Panel/ScrollContainer/ResourceList

func _ready() -> void:
	visible = false
	SignalBus.open_market_panel.connect(show_panel)
	SignalBus.close_all_panels.connect(func(): visible = false)
	close_button.pressed.connect(func(): visible = false)
	MarketManager.prices_updated.connect(_on_prices_updated)
	ResourceManager.resource_changed.connect(_on_resource_changed)
	EconomyManager.gold_changed.connect(func(_g): if visible: _refresh_button_states())
	_build_rows()

# ── Public ────────────────────────────────────────────────────────────────────

func show_panel(building: PlacedBuilding) -> void:
	current_building = building
	title_label.text = "Market"
	subtitle_label.text = "Tier %d  •  Level %d  •  Buy and sell resources" % [
		building.tier, building.level
	]
	_refresh_all()
	visible = true

# ── Row construction ──────────────────────────────────────────────────────────

func _build_rows() -> void:
	_build_header()
	resource_list.add_child(_make_hsep())
	for res_id in RESOURCE_CONFIG:
		_build_resource_row(res_id)
		resource_list.add_child(_make_hsep())

func _build_header() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_fixed_label(row, "", 52, Color(0.5, 0.5, 0.5))       # sprite column
	_fixed_label(row, "RESOURCE", 160, Color(0.55, 0.55, 0.55))
	var buy_hdr := _expand_label(row, "BUY", Color(0.75, 0.70, 0.30))
	buy_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sell_hdr := _expand_label(row, "SELL", Color(0.35, 0.75, 0.35))
	sell_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for lbl in [buy_hdr, sell_hdr]:
		lbl.add_theme_font_size_override("font_size", 11)
	resource_list.add_child(row)

func _build_resource_row(res_id: String) -> void:
	var cfg: Dictionary = RESOURCE_CONFIG[res_id]

	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 76)
	row.add_theme_constant_override("separation", 10)

	# ── Sprite placeholder ──────────────────────────────────────────────
	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(52, 0)
	var rect := ColorRect.new()
	rect.custom_minimum_size = Vector2(44, 44)
	rect.color = cfg["color"]
	center.add_child(rect)
	row.add_child(center)

	# ── Resource name + stock ───────────────────────────────────────────
	var info_box := VBoxContainer.new()
	info_box.custom_minimum_size = Vector2(160, 0)
	info_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_lbl := Label.new()
	name_lbl.text = cfg["display"]
	name_lbl.add_theme_font_size_override("font_size", 14)
	var owned_lbl := Label.new()
	owned_lbl.add_theme_font_size_override("font_size", 12)
	owned_lbl.add_theme_color_override("font_color", Color(0.70, 0.85, 0.70))
	info_box.add_child(name_lbl)
	info_box.add_child(owned_lbl)
	row.add_child(info_box)

	row.add_child(_make_vsep())

	# ── Buy section ─────────────────────────────────────────────────────
	var buy_box := VBoxContainer.new()
	buy_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy_box.alignment = BoxContainer.ALIGNMENT_CENTER
	buy_box.add_theme_constant_override("separation", 4)

	var buy_price_lbl := Label.new()
	buy_price_lbl.add_theme_font_size_override("font_size", 12)
	buy_price_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.40))
	buy_price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var buy_ctrl := HBoxContainer.new()
	buy_ctrl.alignment = BoxContainer.ALIGNMENT_CENTER
	buy_ctrl.add_theme_constant_override("separation", 6)
	var buy_spin := SpinBox.new()
	buy_spin.min_value = 1
	buy_spin.max_value = 9999
	buy_spin.value = 1
	buy_spin.step = 1
	buy_spin.custom_minimum_size = Vector2(90, 0)
	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.custom_minimum_size = Vector2(72, 34)
	buy_btn.add_theme_font_size_override("font_size", 13)
	buy_ctrl.add_child(buy_spin)
	buy_ctrl.add_child(buy_btn)

	buy_box.add_child(buy_price_lbl)
	buy_box.add_child(buy_ctrl)
	row.add_child(buy_box)

	row.add_child(_make_vsep())

	# ── Sell section ────────────────────────────────────────────────────
	var sell_box := VBoxContainer.new()
	sell_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_box.alignment = BoxContainer.ALIGNMENT_CENTER
	sell_box.add_theme_constant_override("separation", 4)

	var sell_price_lbl := Label.new()
	sell_price_lbl.add_theme_font_size_override("font_size", 12)
	sell_price_lbl.add_theme_color_override("font_color", Color(0.40, 0.90, 0.40))
	sell_price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var sell_ctrl := HBoxContainer.new()
	sell_ctrl.alignment = BoxContainer.ALIGNMENT_CENTER
	sell_ctrl.add_theme_constant_override("separation", 6)
	var sell_spin := SpinBox.new()
	sell_spin.min_value = 1
	sell_spin.max_value = 9999
	sell_spin.value = 1
	sell_spin.step = 1
	sell_spin.custom_minimum_size = Vector2(90, 0)
	var sell_btn := Button.new()
	sell_btn.text = "Sell"
	sell_btn.custom_minimum_size = Vector2(72, 34)
	sell_btn.add_theme_font_size_override("font_size", 13)
	sell_ctrl.add_child(sell_spin)
	sell_ctrl.add_child(sell_btn)

	sell_box.add_child(sell_price_lbl)
	sell_box.add_child(sell_ctrl)
	row.add_child(sell_box)

	resource_list.add_child(row)

	# Store references
	_rows[res_id] = {
		"owned_lbl":      owned_lbl,
		"buy_price_lbl":  buy_price_lbl,
		"buy_spin":       buy_spin,
		"buy_btn":        buy_btn,
		"sell_price_lbl": sell_price_lbl,
		"sell_spin":      sell_spin,
		"sell_btn":       sell_btn,
	}

	# Wire up interactions
	buy_spin.value_changed.connect(func(_v): _update_row(res_id))
	sell_spin.value_changed.connect(func(_v): _update_row(res_id))
	buy_btn.pressed.connect(func(): _on_buy(res_id))
	sell_btn.pressed.connect(func(): _on_sell(res_id))

# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh_all() -> void:
	for res_id in _rows:
		_update_row(res_id)

func _update_row(res_id: String) -> void:
	if not _rows.has(res_id):
		return
	var row: Dictionary = _rows[res_id]
	var buy_qty: int  = int(row["buy_spin"].value)
	var sell_qty: int = int(row["sell_spin"].value)

	var unit_buy:  float = MarketManager.get_unit_buy_price(res_id)
	var unit_sell: float = MarketManager.get_unit_sell_price(res_id)
	var buy_total: float = unit_buy * buy_qty
	var sell_total: float = unit_sell * sell_qty

	row["buy_price_lbl"].text  = "%.1fg each  →  %.0fg total" % [unit_buy,  buy_total]
	row["sell_price_lbl"].text = "%.1fg each  →  %.0fg total" % [unit_sell, sell_total]
	row["owned_lbl"].text = "In stock: %d" % ResourceManager.get_amount(res_id)

	row["buy_btn"].disabled  = not EconomyManager.can_afford(buy_total)
	row["sell_btn"].disabled = not ResourceManager.can_afford(res_id, float(sell_qty))

func _refresh_button_states() -> void:
	for res_id in _rows:
		var row: Dictionary = _rows[res_id]
		var buy_total: float = MarketManager.get_buy_price(res_id, int(row["buy_spin"].value))
		var sell_qty: int    = int(row["sell_spin"].value)
		row["buy_btn"].disabled  = not EconomyManager.can_afford(buy_total)
		row["sell_btn"].disabled = not ResourceManager.can_afford(res_id, float(sell_qty))

# ── Transactions ──────────────────────────────────────────────────────────────

func _on_buy(res_id: String) -> void:
	var qty: int = int(_rows[res_id]["buy_spin"].value)
	MarketManager.buy(res_id, qty)
	# prices_updated signal triggers _on_prices_updated → _refresh_all

func _on_sell(res_id: String) -> void:
	var qty: int = int(_rows[res_id]["sell_spin"].value)
	MarketManager.sell(res_id, qty)
	# prices_updated signal triggers _on_prices_updated → _refresh_all

# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_prices_updated() -> void:
	if visible:
		_refresh_all()

func _on_resource_changed(resource_id: String, _amount: int) -> void:
	if visible and _rows.has(resource_id):
		_update_row(resource_id)

# ── Node helpers ──────────────────────────────────────────────────────────────

func _fixed_label(parent: Control, text: String, min_width: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	lbl.custom_minimum_size = Vector2(min_width, 0)
	parent.add_child(lbl)
	return lbl

func _expand_label(parent: Control, text: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)
	return lbl

func _make_hsep() -> HSeparator:
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 2)
	return sep

func _make_vsep() -> VSeparator:
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(2, 0)
	return sep
