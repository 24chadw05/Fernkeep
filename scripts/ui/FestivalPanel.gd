extends Control

# The seasonal festival card. Shows the current season's festival, its cost,
# rewards and buff, and lets the player host it once per season.

@onready var title_label: Label = $Panel/Title
@onready var close_button: Button = $Panel/CloseButton
@onready var vbox: VBoxContainer = $Panel/Scroll/VBox
@onready var host_button: Button = $Panel/HostButton

func _ready() -> void:
	visible = false
	SignalBus.open_festival_panel.connect(toggle)
	SignalBus.close_all_panels.connect(func(): visible = false)
	close_button.pressed.connect(func(): visible = false)
	host_button.pressed.connect(_on_host)
	FestivalManager.festival_state_changed.connect(func():
		if visible:
			_refresh()
	)

func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()
		move_to_front()

func _refresh() -> void:
	for child in vbox.get_children():
		child.queue_free()

	var f: Dictionary = FestivalManager.current_festival()
	if f.is_empty():
		title_label.text = "Festival"
		_label("There is no festival this season.", 28, Color(0.42, 0.33, 0.22))
		host_button.disabled = true
		return

	title_label.text = "%s  —  %s" % [TimeManager.get_season_name(), f.get("name", "Festival")]

	_label(f.get("blurb", ""), 26, Color(0.35, 0.28, 0.16))

	# Cost
	_section("COST")
	var cost: Dictionary = f.get("cost", {})
	if cost.is_empty():
		_label("Free", 26, Color(0.2, 0.42, 0.12))
	else:
		for r in cost:
			var have := ResourceManager.get_amount(r)
			var need := float(cost[r])
			var ok := have >= need
			_label("• %d %s   (have %.0f)" % [int(need), ResourceManager.get_item_label(r), have],
				26, Color(0.2, 0.42, 0.12) if ok else Color(0.6, 0.16, 0.1))

	# Rewards
	_section("REWARDS")
	_label("• +%.0f gold" % float(f.get("reward_gold", 0.0)), 26, Color(0.41, 0.35, 0.13))
	_label("• +%.0f reputation" % float(f.get("reward_reputation", 0.0)), 26, Color(0.25, 0.28, 0.55))
	_label("• %s  (for %d days)" % [f.get("buff_desc", "a festive buff"), int(FestivalManager.BUFF_DAYS)],
		26, Color(0.2, 0.42, 0.12))

	# Host button state
	var blocker := FestivalManager.host_blocker()
	if blocker == "":
		host_button.disabled = false
		host_button.text = "Host %s" % f.get("name", "the Festival")
	else:
		host_button.disabled = true
		host_button.text = blocker

func _on_host() -> void:
	if FestivalManager.host_festival():
		_refresh()

# ── Builders ──────────────────────────────────────────────────────────────────

func _section(text: String) -> void:
	vbox.add_child(HSeparator.new())
	_label(text, 26, Color(0.45, 0.38, 0.2))

func _label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(lbl)
	return lbl
