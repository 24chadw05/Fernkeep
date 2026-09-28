extends Control

# Rows come straight from MarketManager.goods; names and icons come from
# ResourceManager.ITEM_INFO — one registry for the whole game.

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
	MarketManager.orders_changed.connect(func(): if visible: _update_subtitle())
	_build_rows()

# ── Public ────────────────────────────────────────────────────────────────────

func show_panel(building: PlacedBuilding) -> void:
	current_building = building
	title_label.text = "Market"
	_update_subtitle()
	_refresh_all()
	visible = true

func _update_subtitle() -> void:
	var parts: Array = []
	if current_building:
		parts.append("Tier %d  •  Level %d" % [current_building.tier, current_building.level])
	parts.append("Specialty goods delivered in ~%s" % MarketManager.eta_text(MarketManager.get_delivery_seconds()))
	if MarketManager.get_bulk_discount(25) > 0.0:
		parts.append("Bulk: −10%% on 25+, −20%% on 50+")
	if not MarketManager.orders.is_empty():
		var inc: Array = []
		for o in MarketManager.orders:
			inc.append("%d %s (%s)" % [int(o.qty), ResourceManager.get_item_label(o.resource_id),
				MarketManager.eta_text(float(o.seconds_left))])
		parts.append("Incoming: " + ", ".join(PackedStringArray(inc)))
	subtitle_label.text = "  •  ".join(PackedStringArray(parts))

# ── Row construction ──────────────────────────────────────────────────────────

func _build_rows() -> void:
	_build_header()
	resource_list.add_child(_make_hsep())
	for res_id in MarketManager.goods:
		_build_resource_row(res_id)
		resource_list.add_child(_make_hsep())

func _build_header() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_fixed_label(row, "", 52, Color(0.5, 0.5, 0.5))       # sprite column
	_fixed_label(row, "RESOURCE", 160, Color(0.55, 0.55, 0.55))
	var buy_hdr := _expand_label(row, "BUY", Color(0.5, 0.38, 0.06))
	buy_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sell_hdr := _expand_label(row, "SELL", Color(0.15, 0.45, 0.12))
	sell_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for lbl in [buy_hdr, sell_hdr]:
		lbl.add_theme_font_size_override("font_size", 22)
	resource_list.add_child(row)

func _build_resource_row(res_id: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 152)
	row.add_theme_constant_override("separation", 10)

	# ── Item sprite ─────────────────────────────────────────────────────
	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(104, 0)
	var icon := TextureRect.new()
	var icon_path = ResourceManager.get_item_icon_path(res_id)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	icon.custom_minimum_size = Vector2(88, 88)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	center.add_child(icon)
	row.add_child(center)

	# ── Resource name + stock ───────────────────────────────────────────
	var info_box := VBoxContainer.new()
	info_box.custom_minimum_size = Vector2(320, 0)
	info_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_lbl := Label.new()
	name_lbl.text = ResourceManager.get_item_label(res_id)
	name_lbl.add_theme_font_size_override("font_size", 28)
	var owned_lbl := Label.new()
	owned_lbl.add_theme_font_size_override("font_size", 24)
	owned_lbl.add_theme_color_override("font_color", Color(0.32, 0.24, 0.15))
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
	buy_price_lbl.add_theme_font_size_override("font_size", 24)
	buy_price_lbl.add_theme_color_override("font_color", Color(0.41, 0.35, 0.1))
	buy_price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var buy_ctrl := HBoxContainer.new()
	buy_ctrl.alignment = BoxContainer.ALIGNMENT_CENTER
	buy_ctrl.add_theme_constant_override("separation", 6)
	var buy_spin := SpinBox.new()
	buy_spin.min_value = 1
	buy_spin.max_value = 9999
	buy_spin.value = 1
	buy_spin.step = 1
	buy_spin.custom_minimum_size = Vector2(180, 0)
	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.custom_minimum_size = Vector2(144, 68)
	buy_btn.add_theme_font_size_override("font_size", 26)
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
	sell_price_lbl.add_theme_font_size_override("font_size", 24)
	sell_price_lbl.add_theme_color_override("font_color", Color(0.12, 0.43, 0.12))
	sell_price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var sell_ctrl := HBoxContainer.new()
	sell_ctrl.alignment = BoxContainer.ALIGNMENT_CENTER
	sell_ctrl.add_theme_constant_override("separation", 6)
	var sell_spin := SpinBox.new()
	sell_spin.min_value = 1
	sell_spin.max_value = 9999
	sell_spin.value = 1
	sell_spin.step = 1
	sell_spin.custom_minimum_size = Vector2(180, 0)
	var sell_btn := Button.new()
	sell_btn.text = "Sell"
	sell_btn.custom_minimum_size = Vector2(144, 68)
	sell_btn.add_theme_font_size_override("font_size", 26)
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
	var buy_total: float = MarketManager.get_buy_price(res_id, buy_qty)
	var sell_total: float = unit_sell * sell_qty
	var discount := MarketManager.get_bulk_discount(buy_qty)

	row["buy_price_lbl"].text  = "%.1fg each  →  %.0fg total%s" % [unit_buy, buy_total,
		("  (bulk −%d%%)" % int(discount * 100.0)) if discount > 0.0 else ""]
	var ordered := MarketManager.is_ordered_good(res_id)
	row["buy_btn"].text = "Order" if ordered else "Buy"
	row["buy_btn"].tooltip_text = ("Delivered in ~%s" % MarketManager.eta_text(MarketManager.get_delivery_seconds())) if ordered else "Straight off the stall"
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
	lbl.add_theme_font_size_override("font_size", 22)
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
	sep.custom_minimum_size = Vector2(0, 4)
	return sep

func _make_vsep() -> VSeparator:
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(4, 0)
	return sep
