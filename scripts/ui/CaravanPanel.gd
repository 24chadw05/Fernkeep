extends Control

# Caravan deals window — one-time offers from the visiting merchant caravan.

@onready var title_label: Label = $Panel/Title
@onready var subtitle_label: Label = $Panel/SubTitle
@onready var close_button: Button = $Panel/CloseButton
@onready var deal_list: VBoxContainer = $Panel/Scroll/DealList

func _ready() -> void:
	visible = false
	SignalBus.open_caravan_panel.connect(show_panel)
	SignalBus.close_all_panels.connect(func(): visible = false)
	close_button.pressed.connect(func(): visible = false)
	CaravanManager.deals_changed.connect(func():
		if visible:
			_rebuild()
	)
	CaravanManager.caravan_departed.connect(func(): visible = false)

func show_panel() -> void:
	if not CaravanManager.active:
		SignalBus.show_notification.emit("No caravan in town right now.")
		return
	_rebuild()
	visible = true

func _rebuild() -> void:
	for child in deal_list.get_children():
		child.queue_free()

	title_label.text = "🐫 %s" % CaravanManager.caravan_name
	subtitle_label.text = "Leaving in %d day(s)  •  One-time deals — take them or lose them" % CaravanManager.days_left

	for i in range(CaravanManager.deals.size()):
		deal_list.add_child(_make_deal_row(i))
		deal_list.add_child(HSeparator.new())

func _pretty(res: String) -> String:
	return ResourceManager.get_item_label(res)

func _deal_description(deal: Dictionary) -> Array:
	# Returns [headline, detail]
	match deal["kind"]:
		"buy":
			return [
				"BUY — %d× %s" % [deal["get_qty"], _pretty(deal["get_res"])],
				"Pay %.0f gold (≈30%% below market)" % deal["gold"],
			]
		"sell":
			return [
				"SELL — %d× %s" % [deal["give_qty"], _pretty(deal["give_res"])],
				"They pay %.0f gold (well over market rate)" % deal["gold"],
			]
		"barter":
			return [
				"BARTER — %d× %s  ⇄  %d× %s" % [
					deal["give_qty"], _pretty(deal["give_res"]),
					deal["get_qty"], _pretty(deal["get_res"]),
				],
				"A straight swap — no gold changes hands",
			]
	return ["Deal", ""]

func _kind_color(kind: String) -> Color:
	match kind:
		"buy":
			return Color(0.55, 0.42, 0.05)
		"sell":
			return Color(0.15, 0.45, 0.12)
	return Color(0.25, 0.28, 0.55)

func _make_deal_row(index: int) -> HBoxContainer:
	var deal: Dictionary = CaravanManager.deals[index]
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 130)
	row.add_theme_constant_override("separation", 16)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER

	var desc = _deal_description(deal)
	var head_lbl := Label.new()
	head_lbl.text = desc[0]
	head_lbl.add_theme_font_size_override("font_size", 32)
	head_lbl.add_theme_color_override("font_color", _kind_color(deal["kind"]))
	head_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(head_lbl)

	var detail_lbl := Label.new()
	detail_lbl.text = desc[1] + _stock_note(deal)
	detail_lbl.add_theme_font_size_override("font_size", 24)
	detail_lbl.add_theme_color_override("font_color", Color(0.34, 0.25, 0.15))
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(detail_lbl)

	row.add_child(info)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(240, 88)
	btn.add_theme_font_size_override("font_size", 30)
	if deal["taken"]:
		btn.text = "Traded ✓"
		btn.disabled = true
	else:
		btn.text = "Trade"
		btn.pressed.connect(func(): _on_trade(index))
	row.add_child(btn)

	return row

func _stock_note(deal: Dictionary) -> String:
	if deal["kind"] in ["sell", "barter"]:
		var have = int(ResourceManager.get_amount(deal["give_res"]))
		return "   (you have %d)" % have
	return "   (you have %.0f gold)" % EconomyManager.gold

func _on_trade(index: int) -> void:
	var blocker = CaravanManager.accept_deal(index)
	if blocker != "":
		SignalBus.show_notification.emit(blocker)
	_rebuild()
