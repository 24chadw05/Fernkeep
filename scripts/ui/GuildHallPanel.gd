extends Control

# Guild Hall quest board — ledger cards. Each card: a topic, the requested
# items (sprite + count), and a red REWARD section (sprite + count). A Deliver
# button hands over the items for the reward (minus the Taskmaster's cut).

const INK := Color(0.227, 0.157, 0.094)
const INK_SEPIA := Color(0.42, 0.33, 0.22)
const INK_GREEN := Color(0.15, 0.45, 0.12)
const INK_RED := Color(0.62, 0.15, 0.1)

var current_building: PlacedBuilding = null

@onready var subtitle_label: Label = $Panel/SubTitle
@onready var close_button: Button = $Panel/CloseButton
@onready var board_flow: HBoxContainer = $Panel/ScrollContainer/BoardFlow
@onready var upgrade_box: PanelContainer = $Panel/UpgradeBox
@onready var employee_box: PanelContainer = $Panel/EmployeeBox

func _ready() -> void:
	visible = false
	SignalBus.open_guild_hall_panel.connect(show_panel)
	SignalBus.close_all_panels.connect(func(): visible = false)
	close_button.pressed.connect(func(): visible = false)
	GuildHallManager.board_changed.connect(func(): if visible: _rebuild())
	ResourceManager.resource_changed.connect(func(_r, _a): if visible: _rebuild())

func _process(_delta: float) -> void:
	if visible:
		var t = maxi(0, int(GuildHallManager.time_left))
		var tm = GuildHallManager.get_taskmaster()
		var staff_str: String
		if tm != null:
			staff_str = "Taskmaster: %s  (%.0f%% cut)" % [tm.get_full_name(), GuildHallManager.get_cut() * 100.0]
		else:
			staff_str = "No Taskmaster — assign one to speed up the board"
		subtitle_label.text = "%s  •  New quests in %d:%02d" % [staff_str, int(t / 60.0), t % 60]

func show_panel(building: PlacedBuilding = null) -> void:
	if building != null:
		current_building = building
	_rebuild()
	visible = true

func _rebuild() -> void:
	_build_upgrade_box()
	_build_employee_box()

	for child in board_flow.get_children():
		child.queue_free()
	if GuildHallManager.board.is_empty():
		var lbl := Label.new()
		lbl.text = "The board is empty. Check back soon."
		lbl.add_theme_font_size_override("font_size", 24)
		lbl.add_theme_color_override("font_color", INK_SEPIA)
		board_flow.add_child(lbl)
		return
	for i in range(GuildHallManager.board.size()):
		board_flow.add_child(_make_ledger(i))

# Compact top-left box: tier/level + an upgrade button that shows the cost
func _build_upgrade_box() -> void:
	for child in upgrade_box.get_children():
		child.queue_free()
	var hall = current_building if current_building else GuildHallManager.get_guild_hall()
	if hall == null:
		return

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	upgrade_box.add_child(box)

	var tier_lbl := Label.new()
	tier_lbl.text = "Guild Hall — Tier %d, Level %d" % [hall.tier, hall.level]
	tier_lbl.add_theme_font_size_override("font_size", 22)
	tier_lbl.add_theme_color_override("font_color", INK)
	box.add_child(tier_lbl)

	var cost = hall.get_upgrade_cost()
	var up_btn := Button.new()
	up_btn.custom_minimum_size = Vector2(220, 50)
	up_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if cost < 0:
		var maxed := Label.new()
		maxed.text = "Maximum tier reached."
		maxed.add_theme_font_size_override("font_size", 20)
		maxed.add_theme_color_override("font_color", INK_SEPIA)
		box.add_child(maxed)
		up_btn.text = "Max tier"
		up_btn.disabled = true
	else:
		var nt = hall.tier
		var nl = hall.level + 1
		if nl > 3:
			nl = 1
			nt += 1
		var parts: Array = ["%.0f gold" % cost]
		var next_data = DataManager.get_building_level_data("guild_hall", nt, nl)
		for r in next_data.get("resource_cost", {}):
			parts.append("%d %s" % [int(next_data["resource_cost"][r]), ResourceManager.get_item_label(r)])
		var cost_lbl := Label.new()
		cost_lbl.text = "Next (T%dL%d):  %s" % [nt, nl, "  +  ".join(PackedStringArray(parts))]
		cost_lbl.add_theme_font_size_override("font_size", 20)
		cost_lbl.add_theme_color_override("font_color", INK_GREEN)
		cost_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(cost_lbl)
		up_btn.text = "Upgrade"
		up_btn.pressed.connect(_on_upgrade)
	box.add_child(up_btn)

# Compact top-right box: the single Taskmaster + a promote button
func _build_employee_box() -> void:
	for child in employee_box.get_children():
		child.queue_free()

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	employee_box.add_child(box)

	var head := Label.new()
	head.text = "TASKMASTER"
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", INK_SEPIA)
	box.add_child(head)

	var tm = GuildHallManager.get_taskmaster()
	if tm == null:
		var none := Label.new()
		none.text = "None — assign one in the Citizens panel to speed up the board."
		none.add_theme_font_size_override("font_size", 20)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(none)
		return

	var name_lbl := Label.new()
	name_lbl.text = "%s  •  %.0f%% cut" % [tm.get_full_name(), GuildHallManager.get_cut() * 100.0]
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", INK)
	box.add_child(name_lbl)

	var promo_btn := Button.new()
	promo_btn.custom_minimum_size = Vector2(0, 52)
	if GuildHallManager.get_cut() >= GuildHallManager.CUT_MAX - 0.0001:
		promo_btn.text = "Max cut (10%)"
		promo_btn.disabled = true
	else:
		promo_btn.text = "Promote → %.0f%% cut (faster board)" % ((GuildHallManager.get_cut() + GuildHallManager.CUT_STEP) * 100.0)
		promo_btn.add_theme_font_size_override("font_size", 18)
		promo_btn.pressed.connect(func():
			if GuildHallManager.promote_taskmaster():
				SignalBus.show_notification.emit("%s promoted!" % tm.get_full_name())
		)
	box.add_child(promo_btn)

func _make_ledger(index: int) -> Control:
	var q: Dictionary = GuildHallManager.board[index]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(420, 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # sit at top, don't stretch to row height

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	# Topic
	var title := Label.new()
	title.text = str(q.get("title", "Quest"))
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", INK)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	box.add_child(HSeparator.new())

	# Requested items
	var req_head := Label.new()
	req_head.text = "DELIVER"
	req_head.add_theme_font_size_override("font_size", 20)
	req_head.add_theme_color_override("font_color", INK_SEPIA)
	box.add_child(req_head)
	for r in q["requests"]:
		box.add_child(_item_row(str(r["res"]), int(r["qty"]), true))

	box.add_child(HSeparator.new())

	# Reward
	var rew_head := Label.new()
	rew_head.text = "REWARD"
	rew_head.add_theme_font_size_override("font_size", 22)
	rew_head.add_theme_color_override("font_color", INK_RED)
	box.add_child(rew_head)
	for rw in q["rewards"]:
		box.add_child(_item_row(str(rw["res"]), int(rw["qty"]), false))

	# Deliver button / claimed state
	var claimed = q.get("claimed", false)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 60)
	if claimed:
		btn.text = "✓ Delivered"
		btn.disabled = true
	elif GuildHallManager.can_claim(index):
		btn.text = "Deliver"
		btn.add_theme_color_override("font_color", INK_GREEN)
		btn.pressed.connect(func(): _on_deliver(index))
	else:
		btn.text = "Missing items"
		btn.disabled = true
	box.add_child(btn)

	return card

func _item_row(res_id: String, qty: int, is_request: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if res_id != "gold":
		var path = ResourceManager.get_item_icon_path(res_id)
		if path != "":
			icon.texture = load(path)
	row.add_child(icon)

	var lbl := Label.new()
	var label_name = "Gold" if res_id == "gold" else ResourceManager.get_item_label(res_id)
	lbl.text = "%d  %s" % [qty, label_name]
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	# For requests, show how many the player has (red if short)
	if is_request and res_id != "gold":
		var have = int(ResourceManager.get_amount(res_id))
		var have_lbl := Label.new()
		have_lbl.text = "have %d" % have
		have_lbl.add_theme_font_size_override("font_size", 20)
		have_lbl.add_theme_color_override("font_color", INK_GREEN if have >= qty else INK_RED)
		row.add_child(have_lbl)

	return row

func _on_deliver(index: int) -> void:
	var err = GuildHallManager.claim(index)
	if err == "":
		SignalBus.show_notification.emit("Quest delivered — reward collected!")
		_rebuild()
	else:
		SignalBus.show_notification.emit(err)

func _on_upgrade() -> void:
	if current_building == null:
		return
	var blocker = BuildingManager.get_upgrade_blocker(current_building)
	if blocker != "":
		SignalBus.show_notification_timed.emit(blocker, 1.5)
		return
	if BuildingManager.upgrade_building(current_building.id):
		SignalBus.show_notification.emit(
			"Guild Hall upgraded to T%dL%d!" % [current_building.tier, current_building.level]
		)
		_rebuild()
