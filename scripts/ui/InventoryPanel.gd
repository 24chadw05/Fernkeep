extends Control

# Inventory — everything in the town stores, as a grid of item sprites with
# counts. Hover an item for its name. Opened from the backpack button.

const CELL_SIZE := Vector2(150, 150)
const ICON_SIZE := Vector2(96, 96)

@onready var title_label: Label = $Panel/Title
@onready var subtitle_label: Label = $Panel/SubTitle
@onready var close_button: Button = $Panel/CloseButton
@onready var grid: GridContainer = $Panel/Scroll/Grid

func _ready() -> void:
	visible = false
	SignalBus.open_inventory_panel.connect(show_panel)
	SignalBus.close_all_panels.connect(func(): visible = false)
	close_button.pressed.connect(func(): visible = false)
	ResourceManager.resource_changed.connect(func(_r, _a):
		if visible:
			_rebuild()
	)

func show_panel() -> void:
	_rebuild()
	visible = true

func _rebuild() -> void:
	for child in grid.get_children():
		child.queue_free()

	title_label.text = "Inventory"

	var shown := 0
	var kinds := 0
	var total := 0
	for res_id in ResourceManager.ITEM_INFO:
		var amount = int(ResourceManager.get_amount(res_id))
		if amount <= 0:
			continue
		kinds += 1
		total += amount
		grid.add_child(_make_cell(res_id, amount))
		shown += 1

	subtitle_label.text = "%d item type(s)  •  %d goods stored" % [kinds, total]

	if shown == 0:
		var empty := Label.new()
		empty.text = "Your stores are empty — forage, fish, farm, or trade to fill them."
		empty.add_theme_font_size_override("font_size", 28)
		empty.add_theme_color_override("font_color", Color(0.4, 0.29, 0.18))
		grid.add_child(empty)

func _make_cell(res_id: String, amount: int) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = CELL_SIZE
	cell.tooltip_text = ResourceManager.get_item_label(res_id)
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cell.mouse_entered.connect(func(): cell.modulate = Color(1.15, 1.15, 1.08))
	cell.mouse_exited.connect(func(): cell.modulate = Color(1, 1, 1))

	# Icon centered in the cell
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	var icon_path = ResourceManager.get_item_icon_path(res_id)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(icon)
	cell.add_child(center)

	# Count badge, bottom-right of the cell
	var count := Label.new()
	count.text = _format_count(amount)
	count.add_theme_font_size_override("font_size", 26)
	count.add_theme_color_override("font_color", Color(0.28, 0.2, 0.13))
	count.add_theme_color_override("font_outline_color", Color(0.95, 0.9, 0.75))
	count.add_theme_constant_override("outline_size", 8)
	count.size_flags_horizontal = Control.SIZE_SHRINK_END
	count.size_flags_vertical = Control.SIZE_SHRINK_END
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(count)

	return cell

func _format_count(amount: int) -> String:
	if amount >= 10000:
		return "%.1fk" % (amount / 1000.0)
	return str(amount)
