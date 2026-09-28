extends Control

# Trade Port UI — 5 rotating barter offers. Click a card to open the trade
# section: slider picks how many to receive, the offer side picks which
# resource pays for it at the rolled discount. Sold-out offers show SOLD.

const INK_GREEN := Color(0.15, 0.45, 0.12)
const INK_RED := Color(0.62, 0.15, 0.1)
const INK_SEPIA := Color(0.42, 0.33, 0.22)
const INK := Color(0.227, 0.157, 0.094)

var current_building: PlacedBuilding = null
var _selected: int = -1
var _qty: int = 1
var _pay_id: String = ""

var _receive_label: Label = null
var _pay_label: Label = null
var _have_label: Label = null
var _status_label: Label = null
var _qty_slider: HSlider = null
var _pay_picker: OptionButton = null

@onready var subtitle_label: Label = $Panel/SubTitle
@onready var close_button: Button = $Panel/CloseButton
@onready var offers_row: HBoxContainer = $Panel/OffersRow
@onready var trade_box: VBoxContainer = $Panel/TradeBox

func _ready() -> void:
	visible = false
	SignalBus.open_trade_port_panel.connect(show_panel)
	SignalBus.close_all_panels.connect(func(): visible = false)
	close_button.pressed.connect(func(): visible = false)
	TradePortManager.offers_rerolled.connect(func():
		if visible:
			_selected = -1
			_rebuild()
	)

func _process(_delta: float) -> void:
	if visible:
		var t = maxi(0, int(TradePortManager.time_left))
		subtitle_label.text = "Barter goods for goods — offers re-roll in %d:%02d" % [int(t / 60.0), t % 60]

func show_panel(building: PlacedBuilding) -> void:
	current_building = building
	_selected = -1
	_rebuild()
	visible = true

# ── Offer cards ───────────────────────────────────────────────────────────────

func _rebuild() -> void:
	for child in offers_row.get_children():
		child.queue_free()
	for child in trade_box.get_children():
		child.queue_free()

	for i in range(TradePortManager.offers.size()):
		offers_row.add_child(_make_card(i))

	if _selected >= 0 and _selected < TradePortManager.offers.size():
		if int(TradePortManager.offers[_selected].stock) > 0:
			_build_trade_box()
	else:
		var hint := Label.new()
		hint.text = "Click an offer above to start a trade."
		hint.add_theme_font_size_override("font_size", 24)
		hint.add_theme_color_override("font_color", INK_SEPIA)
		trade_box.add_child(hint)

func _make_card(i: int) -> Button:
	var o: Dictionary = TradePortManager.offers[i]
	var rid: String = str(o.resource_id)
	var sold = int(o.stock) <= 0

	var card := Button.new()
	card.custom_minimum_size = Vector2(215, 330)
	card.disabled = sold
	if not sold:
		card.pressed.connect(func(): _select_offer(i))
	if i == _selected:
		card.modulate = Color(1.12, 1.06, 0.9)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8.0
	box.offset_top = 12.0
	box.offset_right = -8.0
	box.offset_bottom = -12.0
	box.add_theme_constant_override("separation", 6)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	# Icon with a SOLD stamp over it when the stock is bought out
	var icon_holder := Control.new()
	icon_holder.custom_minimum_size = Vector2(0, 110)
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_path = ResourceManager.get_item_icon_path(rid)
	if icon_path != "":
		icon.texture = load(icon_path)
	if sold:
		icon.modulate = Color(1, 1, 1, 0.35)
	icon_holder.add_child(icon)
	if sold:
		var sold_lbl := Label.new()
		sold_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sold_lbl.text = "SOLD"
		sold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sold_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sold_lbl.add_theme_font_size_override("font_size", 42)
		sold_lbl.add_theme_color_override("font_color", INK_RED)
		icon_holder.add_child(sold_lbl)
	box.add_child(icon_holder)

	var name_lbl := Label.new()
	name_lbl.text = ResourceManager.get_item_label(rid)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 26)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_lbl)

	if not sold:
		var stock_lbl := Label.new()
		stock_lbl.text = "Stock: %d" % int(o.stock)
		stock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stock_lbl.add_theme_font_size_override("font_size", 24)
		box.add_child(stock_lbl)

		var deal_lbl := Label.new()
		deal_lbl.text = "%d%% off" % int(round(float(o.discount) * 100.0))
		deal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		deal_lbl.add_theme_font_size_override("font_size", 24)
		deal_lbl.add_theme_color_override("font_color", INK_GREEN)
		box.add_child(deal_lbl)

		var val_lbl := Label.new()
		val_lbl.text = "worth %.0fg each" % TradePortManager.unit_value(rid)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val_lbl.add_theme_font_size_override("font_size", 20)
		val_lbl.add_theme_color_override("font_color", INK_SEPIA)
		box.add_child(val_lbl)

	return card

func _select_offer(i: int) -> void:
	_selected = i
	_qty = 1
	_pay_id = ""
	_rebuild()

# ── Trade section ─────────────────────────────────────────────────────────────

func _build_trade_box() -> void:
	var o: Dictionary = TradePortManager.offers[_selected]
	var rid: String = str(o.resource_id)
	var stock = int(o.stock)
	_qty = clampi(_qty, 1, stock)

	var header := Label.new()
	header.text = "TRADING FOR %s  —  %d%% OFF" % [
		ResourceManager.get_item_label(rid).to_upper(), int(round(float(o.discount) * 100.0))
	]
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	trade_box.add_child(header)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	trade_box.add_child(row)

	# LEFT — how many you receive
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)

	var receive_head := Label.new()
	receive_head.text = "RECEIVE"
	receive_head.add_theme_font_size_override("font_size", 20)
	receive_head.add_theme_color_override("font_color", INK_SEPIA)
	left.add_child(receive_head)

	var receive_row := HBoxContainer.new()
	receive_row.add_theme_constant_override("separation", 12)
	var ricon := TextureRect.new()
	ricon.custom_minimum_size = Vector2(56, 56)
	ricon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ricon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var ripath = ResourceManager.get_item_icon_path(rid)
	if ripath != "":
		ricon.texture = load(ripath)
	receive_row.add_child(ricon)
	_receive_label = Label.new()
	_receive_label.add_theme_font_size_override("font_size", 26)
	receive_row.add_child(_receive_label)
	left.add_child(receive_row)

	_qty_slider = HSlider.new()
	_qty_slider.min_value = 1
	_qty_slider.max_value = stock
	_qty_slider.step = 1
	_qty_slider.value = _qty
	_qty_slider.custom_minimum_size = Vector2(0, 44)
	_qty_slider.value_changed.connect(func(v):
		_qty = int(v)
		_update_trade_labels()
	)
	left.add_child(_qty_slider)

	# RIGHT — what you offer in exchange
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)

	var offer_head := Label.new()
	offer_head.text = "YOUR OFFER  (pay %d%% of value)" % int(round((1.0 - float(o.discount)) * 100.0))
	offer_head.add_theme_font_size_override("font_size", 20)
	offer_head.add_theme_color_override("font_color", INK_SEPIA)
	right.add_child(offer_head)

	_pay_picker = OptionButton.new()
	_pay_picker.custom_minimum_size = Vector2(0, 56)
	var first_id := ""
	for pid in MarketManager.goods.keys():
		if pid == rid:
			continue
		var owned = int(ResourceManager.get_amount(pid))
		if owned <= 0:
			continue
		var label = "%s  (have %d)" % [ResourceManager.get_item_label(pid), owned]
		var pipath = ResourceManager.get_item_icon_path(pid)
		if pipath != "":
			_pay_picker.add_icon_item(load(pipath), label)
		else:
			_pay_picker.add_item(label)
		_pay_picker.set_item_metadata(_pay_picker.item_count - 1, pid)
		if first_id == "":
			first_id = pid
	if _pay_id == "" or not _picker_has(_pay_id):
		_pay_id = first_id
	_pay_picker.item_selected.connect(func(idx):
		_pay_id = str(_pay_picker.get_item_metadata(idx))
		_update_trade_labels()
	)
	right.add_child(_pay_picker)

	_pay_label = Label.new()
	_pay_label.add_theme_font_size_override("font_size", 26)
	right.add_child(_pay_label)

	_have_label = Label.new()
	_have_label.add_theme_font_size_override("font_size", 22)
	_have_label.add_theme_color_override("font_color", INK_SEPIA)
	right.add_child(_have_label)

	# Trade button + status
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 20)
	trade_box.add_child(bottom)

	var trade_btn := Button.new()
	trade_btn.text = "Trade"
	trade_btn.custom_minimum_size = Vector2(260, 68)
	trade_btn.add_theme_color_override("font_color", INK_GREEN)
	trade_btn.pressed.connect(_on_trade_pressed)
	bottom.add_child(trade_btn)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 24)
	_status_label.add_theme_color_override("font_color", INK_RED)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_status_label)

	if _pay_id == "":
		trade_btn.disabled = true
		_status_label.text = "You have nothing the port will take — gather some resources first."
	else:
		# Reflect the current picker selection
		for idx in range(_pay_picker.item_count):
			if str(_pay_picker.get_item_metadata(idx)) == _pay_id:
				_pay_picker.select(idx)
				break

	_update_trade_labels()

func _picker_has(pid: String) -> bool:
	for idx in range(_pay_picker.item_count):
		if str(_pay_picker.get_item_metadata(idx)) == pid:
			return true
	return false

func _update_trade_labels() -> void:
	if _selected < 0 or _receive_label == null:
		return
	var o: Dictionary = TradePortManager.offers[_selected]
	var rid: String = str(o.resource_id)
	_receive_label.text = "%d × %s   (worth %.0fg)" % [
		_qty, ResourceManager.get_item_label(rid), TradePortManager.get_offer_value(_selected, _qty)
	]
	if _pay_id == "":
		_pay_label.text = "—"
		_have_label.text = ""
		return
	var pay_qty = TradePortManager.get_pay_qty(_selected, _qty, _pay_id)
	var have = int(ResourceManager.get_amount(_pay_id))
	_pay_label.text = "Pay %d × %s   (%.0fg value)" % [
		pay_qty, ResourceManager.get_item_label(_pay_id), TradePortManager.get_pay_value(_selected, _qty)
	]
	_pay_label.add_theme_color_override("font_color", INK if have >= pay_qty else INK_RED)
	_have_label.text = "You have %d %s" % [have, ResourceManager.get_item_label(_pay_id)]
	if _status_label:
		_status_label.text = ""

func _on_trade_pressed() -> void:
	if _pay_id == "":
		return
	var err = TradePortManager.execute_trade(_selected, _qty, _pay_id)
	if err == "":
		SignalBus.show_notification.emit("Trade complete!")
		_qty = 1
		_rebuild()
	elif _status_label:
		_status_label.text = err
