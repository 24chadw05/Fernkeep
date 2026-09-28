extends Control

# Quest log — active quests with live objective progress, plus completed history.

@onready var title_label: Label = $Panel/Title
@onready var subtitle_label: Label = $Panel/SubTitle
@onready var close_button: Button = $Panel/CloseButton
@onready var quest_list: VBoxContainer = $Panel/ScrollContainer/QuestList

func _ready() -> void:
	visible = false
	title_label.text = "Quest Log"
	SignalBus.open_quest_panel.connect(show_panel)
	SignalBus.close_all_panels.connect(func(): visible = false)
	close_button.pressed.connect(func(): visible = false)
	QuestManager.quest_started.connect(func(_q): _refresh_if_visible())
	QuestManager.quest_completed.connect(func(_q): _refresh_if_visible())
	QuestManager.quest_progress.connect(func(_id): _refresh_if_visible())

func _refresh_if_visible() -> void:
	if visible:
		_rebuild()

func show_panel() -> void:
	_rebuild()
	visible = true

func _rebuild() -> void:
	for child in quest_list.get_children():
		child.queue_free()

	var active_ids: Array = QuestManager.get_active_quest_ids()
	subtitle_label.text = "%d active  •  %d completed" % [active_ids.size(), QuestManager.completed_quests.size()]

	_add_section_header("ACTIVE QUESTS" if not active_ids.is_empty() else "NO ACTIVE QUESTS — KEEP GROWING YOUR CITY")
	for quest_id in active_ids:
		_add_active_quest(quest_id)

	if not QuestManager.completed_quests.is_empty():
		_add_section_header("COMPLETED")
		for quest_id in QuestManager.completed_quests:
			var quest = DataManager.get_quest(quest_id)
			var lbl := Label.new()
			lbl.text = "✓  " + quest.get("name", quest_id)
			lbl.add_theme_font_size_override("font_size", 24)
			lbl.add_theme_color_override("font_color", Color(0.35, 0.52, 0.35))
			quest_list.add_child(lbl)

func _add_section_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	quest_list.add_child(lbl)
	var sep := HSeparator.new()
	quest_list.add_child(sep)

func _add_active_quest(quest_id: String) -> void:
	var quest = DataManager.get_quest(quest_id)
	if quest.is_empty():
		return

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)

	var name_lbl := Label.new()
	name_lbl.text = quest.get("name", quest_id)
	name_lbl.add_theme_font_size_override("font_size", 30)
	name_lbl.add_theme_color_override("font_color", Color(0.41, 0.35, 0.16))
	box.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = quest.get("description", "")
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 24)
	box.add_child(desc_lbl)

	var dialogue: Dictionary = quest.get("dialogue", {})
	if dialogue.has("start"):
		var quote_lbl := Label.new()
		quote_lbl.text = "“%s”" % dialogue["start"]
		quote_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		quote_lbl.add_theme_font_size_override("font_size", 22)
		quote_lbl.add_theme_color_override("font_color", Color(0.29, 0.33, 0.43))
		box.add_child(quote_lbl)

	for objective in quest.get("objectives", []):
		var progress: Dictionary = QuestManager.get_objective_progress(quest_id, objective)
		var obj_lbl := Label.new()
		obj_lbl.add_theme_font_size_override("font_size", 24)
		if not progress.supported:
			obj_lbl.text = "  ◌ %s  (coming soon)" % objective.get("description", "")
			obj_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		elif progress.done:
			obj_lbl.text = "  ✓ %s" % objective.get("description", "")
			obj_lbl.add_theme_color_override("font_color", Color(0.17, 0.45, 0.17))
		else:
			obj_lbl.text = "  ▢ %s  (%.0f / %.0f)" % [
				objective.get("description", ""), progress.current, progress.target
			]
			obj_lbl.add_theme_color_override("font_color", Color(0.32, 0.24, 0.15))
		obj_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(obj_lbl)

	var rewards: Dictionary = quest.get("rewards", {})
	var reward_parts: Array = []
	if float(rewards.get("gold", 0)) > 0:
		reward_parts.append("%d gold" % int(rewards["gold"]))
	if float(rewards.get("xp", 0)) > 0:
		reward_parts.append("%d XP" % int(rewards["xp"]))
	if float(rewards.get("reputation", 0)) > 0:
		reward_parts.append("%d reputation" % int(rewards["reputation"]))
	if rewards.get("unlock_recipe", null) != null:
		reward_parts.append("recipe: %s" % RecipeManager.pretty_name(str(rewards["unlock_recipe"])))
	if rewards.get("unlock_potion", null) != null:
		reward_parts.append("potion: %s" % RecipeManager.pretty_name(str(rewards["unlock_potion"])))
	if not reward_parts.is_empty():
		var reward_lbl := Label.new()
		reward_lbl.text = "  Rewards: " + ", ".join(PackedStringArray(reward_parts))
		reward_lbl.add_theme_font_size_override("font_size", 22)
		reward_lbl.add_theme_color_override("font_color", Color(0.41, 0.3, 0.08))
		reward_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(reward_lbl)

	quest_list.add_child(box)
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 16)
	quest_list.add_child(sep)
