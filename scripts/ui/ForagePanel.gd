extends Control

# Foraging trip — a forest clearing scattered with seasonal gatherables.
# Click everything you can find, then head home. Trips cost ForageManager charges.

const ICON_DIR := "res://assets/forage/"
const TREE_TEXTURES: Array = [
	"res://assets/decor/Tree_1.png",
	"res://assets/decor/Tree_2.png",
]

var _remaining: int = 0
var _collected: Dictionary = {}  # resource_id → count

@onready var title_label: Label = $Header/Title
@onready var charges_label: Label = $Header/ChargesLabel
@onready var leave_button: Button = $Header/LeaveButton
@onready var play_area: Control = $PlayArea
@onready var summary_label: Label = $SummaryLabel

func _ready() -> void:
	visible = false
	SignalBus.open_forage_panel.connect(show_panel)
	SignalBus.close_all_panels.connect(_leave)
	leave_button.pressed.connect(_leave)
	ForageManager.charges_changed.connect(func(c): charges_label.text = "Trips left today: %d" % c)

func show_panel() -> void:
	if not ForageManager.can_forage():
		SignalBus.show_notification.emit("No foraging trips left — rest until tomorrow.")
		return
	visible = true
	_start_trip()

func _leave() -> void:
	if not visible:
		return
	visible = false
	if not _collected.is_empty():
		var parts: Array = []
		for res_id in _collected:
			parts.append("%d %s" % [_collected[res_id], ResourceManager.get_item_label(res_id)])
		SignalBus.show_notification.emit("Foraging haul: " + ", ".join(PackedStringArray(parts)))

func _start_trip() -> void:
	_collected.clear()
	for child in play_area.get_children():
		child.queue_free()

	title_label.text = "Foraging — %s" % TimeManager.get_season_name()
	charges_label.text = "Trips left today: %d" % ForageManager.charges
	summary_label.text = "Click plants and mushrooms to gather them, then head home."

	var spawns: Array = ForageManager.start_trip()
	_remaining = spawns.size()

	var area: Vector2 = play_area.size
	if area.x < 200 or area.y < 200:
		area = Vector2(1400, 720)

	# Grid-jitter placement so nothing overlaps: shuffle cells, take what we need
	var cols := 8
	var rows := 4
	var cell := Vector2(area.x / cols, area.y / rows)
	var cells: Array = []
	for cx in range(cols):
		for cy in range(rows):
			cells.append(Vector2(cx, cy))
	cells.shuffle()

	# Decorative trees fill a few cells behind the gatherables
	var tree_count := 5
	for i in range(min(tree_count, cells.size() - spawns.size())):
		var c: Vector2 = cells.pop_back()
		var tree := TextureRect.new()
		tree.texture = load(TREE_TEXTURES[randi() % TREE_TEXTURES.size()])
		tree.custom_minimum_size = Vector2(192, 192)
		tree.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tree.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tree.flip_h = randi() % 2 == 0
		tree.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tree.modulate = Color(0.85, 0.9, 0.85)
		tree.position = c * cell + Vector2(randf_range(0, maxf(cell.x - 96, 1)), randf_range(0, maxf(cell.y - 96, 1)))
		play_area.add_child(tree)

	for spawn in spawns:
		if cells.is_empty():
			break
		var c: Vector2 = cells.pop_back()
		_spawn_item(spawn, c * cell, cell)

func _spawn_item(spawn: Dictionary, cell_origin: Vector2, cell: Vector2) -> void:
	var id: String = spawn["id"]
	var enchanted: bool = spawn.get("enchanted", false)

	var btn := TextureButton.new()
	var icon_path := ICON_DIR + id + ".png"
	if ResourceLoader.exists(icon_path):
		btn.texture_normal = load(icon_path)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var side := 72.0 if enchanted else 56.0
	btn.custom_minimum_size = Vector2(side, side)
	btn.size = Vector2(side, side)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.position = cell_origin + Vector2(
		randf_range(6, maxf(cell.x - side - 6, 7)),
		randf_range(6, maxf(cell.y - side - 6, 7))
	)
	if enchanted:
		btn.modulate = Color(1.15, 0.95, 1.3)
	btn.mouse_entered.connect(func(): btn.modulate = btn.modulate * 1.15)
	btn.mouse_exited.connect(func():
		btn.modulate = Color(1.15, 0.95, 1.3) if enchanted else Color(1, 1, 1)
	)
	btn.pressed.connect(func(): _on_item_clicked(btn, id, enchanted))
	play_area.add_child(btn)

func _on_item_clicked(btn: TextureButton, id: String, enchanted: bool) -> void:
	ForageManager.collect(id)
	_collected[id] = int(_collected.get(id, 0)) + 1
	_remaining -= 1
	btn.queue_free()

	var pretty: String = ResourceManager.get_item_label(id)
	if enchanted:
		summary_label.text = "✨ A rare find — %s! (%d left)" % [pretty, _remaining]
	else:
		summary_label.text = "+1 %s  (%d left to find)" % [pretty, _remaining]

	if _remaining <= 0:
		summary_label.text = "The clearing is picked clean — time to head home!"
