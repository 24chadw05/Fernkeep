extends Control

# GDD core loop, stage 1 — "Return & collect". When the player comes back after
# time away, this shows what the city earned: the gold counts up, each resource
# is listed with its icon, and Collect closes it with a flourish on the HUD.
# The gold is already banked by GameManager before this opens; the panel is the
# ceremony, so closing the game on it never loses anything.

@onready var away_label: Label = $Panel/Margin/VBox/AwayLabel
@onready var gold_label: Label = $Panel/Margin/VBox/GoldLabel
@onready var resource_list: VBoxContainer = $Panel/Margin/VBox/ResourceList
@onready var cap_label: Label = $Panel/Margin/VBox/CapLabel
@onready var collect_button: Button = $Panel/Margin/VBox/CollectButton

const COUNT_UP_SECONDS: float = 1.2
var _gold_target: float = 0.0
var _gold_shown: float = 0.0

func _ready() -> void:
	visible = false
	SignalBus.show_welcome_back.connect(show_summary)
	collect_button.pressed.connect(_collect)
	# ESC's "close everything" counts as collecting, so the panel can't strand
	# the player behind a modal they have to find the button for.
	SignalBus.close_all_panels.connect(func(): if visible: _collect())

func show_summary(summary: Dictionary) -> void:
	var away := float(summary.get("seconds_away", 0.0))
	var counted := float(summary.get("seconds_counted", away))
	away_label.text = "You were away for %s." % _duration(away)

	# Tell the player when the idle cap cut their time short — and how to raise it.
	if away > counted + 60.0:
		cap_label.text = "Your city can only work unattended for %s. Upgrade the Town Hall to extend it (up to 24h)." % _duration(counted)
		cap_label.visible = true
	else:
		cap_label.visible = false

	for child in resource_list.get_children():
		resource_list.remove_child(child)
		child.queue_free()
	var resources: Dictionary = summary.get("resources", {})
	for res_id in resources:
		resource_list.add_child(_resource_row(res_id, float(resources[res_id])))

	_gold_target = float(summary.get("gold", 0.0))
	_gold_shown = 0.0
	gold_label.text = "+0 gold"
	visible = true
	var tw := create_tween()
	tw.tween_method(_set_gold_shown, 0.0, _gold_target, COUNT_UP_SECONDS) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

func _set_gold_shown(v: float) -> void:
	_gold_shown = v
	gold_label.text = "+%.0f gold" % v

func _resource_row(res_id: String, amount: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var path := ResourceManager.get_item_icon_path(res_id)
	if path != "" and ResourceLoader.exists(path):
		icon.texture = load(path)
	row.add_child(icon)
	var lbl := Label.new()
	lbl.text = "+%d  %s" % [int(amount), ResourceManager.get_item_label(res_id)]
	lbl.add_theme_font_size_override("font_size", 26)
	row.add_child(lbl)
	return row

func _collect() -> void:
	# Finish the count if the player was quicker than the animation.
	_set_gold_shown(_gold_target)
	visible = false
	if _gold_target >= 1.0:
		# Reuse the HUD's payday pop so collecting lands on the gold counter.
		EconomyManager.emit_signal("day_settled", 0.0, 0.0, _gold_target)

func _duration(seconds: float) -> String:
	var mins := int(seconds / 60.0)
	if mins < 60:
		return "%d min" % maxi(mins, 1)
	var hours := mins / 60
	var rem := mins % 60
	if hours < 24:
		return "%dh %02dm" % [hours, rem] if rem > 0 else "%dh" % hours
	return "%dd %dh" % [hours / 24, hours % 24]
