extends Control

# The city news log — every notification the game has raised, newest first,
# each stamped with how long ago it happened.
#
# Read state follows the player's eyes rather than the act of opening: only the
# cards actually on screen are marked read. Scrolling further down marks the
# cards that come into view, so a backlog of 15 opened to reveal 5 leaves the
# other 10 unread until they're scrolled to.

@onready var subtitle_label: Label = $Panel/SubTitle
@onready var close_button: Button = $Panel/CloseButton
@onready var scroll: ScrollContainer = $Panel/ScrollContainer
@onready var news_list: VBoxContainer = $Panel/ScrollContainer/NewsList

# A card counts as "seen" once at least this much of its height is inside the
# scroll viewport — a sliver peeking over the edge isn't something you've read.
const VISIBLE_FRACTION: float = 0.5

const INK      := Color(0.227, 0.157, 0.094)
const URGENT   := Color(0.72, 0.13, 0.1)
const MUTED    := Color(0.42, 0.33, 0.22)
const UNREAD_BG := Color(0.85, 0.78, 0.62, 0.5)

# card node → the entry Dictionary it renders, so visibility checks can map back
var _card_entries: Dictionary = {}

func _ready() -> void:
	visible = false
	SignalBus.open_news_panel.connect(show_panel)
	SignalBus.close_all_panels.connect(func(): visible = false)
	close_button.pressed.connect(func(): visible = false)
	NewsManager.news_changed.connect(_refresh_if_visible)
	scroll.get_v_scroll_bar().value_changed.connect(func(_v): _mark_visible_read())

func _refresh_if_visible() -> void:
	if visible:
		_rebuild()

func show_panel() -> void:
	_rebuild()
	visible = true

func _rebuild() -> void:
	# Rebuilding while open (a new item arrived) must not yank the player back to
	# the top of a list they were reading, so hold the scroll offset across it.
	var previous_scroll := scroll.scroll_vertical if visible else 0

	# Detach before freeing: queue_free() only takes effect at end of frame, and
	# the deferred layout pass below measures card.position.y — stale cards still
	# sitting in the VBox would push every new card's offset down.
	for child in news_list.get_children():
		news_list.remove_child(child)
		child.queue_free()
	_card_entries.clear()

	var unread := NewsManager.get_unread_count()
	subtitle_label.text = "%d item(s)  •  %d unread" % [NewsManager.entries.size(), unread]
	if unread > 0:
		subtitle_label.text += "  •  scroll to read, or click an item to mark it read"

	if NewsManager.entries.is_empty():
		var empty := Label.new()
		empty.text = "No news yet. Events around the city will be reported here."
		empty.add_theme_font_size_override("font_size", 24)
		empty.add_theme_color_override("font_color", MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		news_list.add_child(empty)
		return

	for entry in NewsManager.entries:
		var card := _build_card(entry)
		news_list.add_child(card)
		_card_entries[card] = entry

	_after_layout(previous_scroll)

# Restoring the offset and measuring the cards both have to wait for the
# container to lay the new children out — before that every card's size is still
# zero and any scroll offset we set clamps straight back to 0. call_deferred is
# NOT enough: it isn't ordered against the container's sort pass, so it can run
# on unsized cards, which _mark_visible_read then skips — leaving their unread
# dots stuck. Awaiting a real frame guarantees layout has happened.
func _after_layout(previous_scroll: int) -> void:
	await get_tree().process_frame
	if not visible:
		return
	scroll.scroll_vertical = previous_scroll
	_mark_visible_read()

func _build_card(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	var is_unread: bool = not entry.get("read", false)

	if is_unread:
		var bg := StyleBoxFlat.new()
		bg.bg_color = UNREAD_BG
		bg.set_corner_radius_all(6)
		bg.content_margin_left = 10
		bg.content_margin_right = 10
		bg.content_margin_top = 8
		bg.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", bg)

	# Clicking a card marks just that entry read — a manual override for anything
	# the visibility pass hasn't caught (a card wedged at the edge of the
	# viewport, or one the player wants to clear without scrolling past it).
	if is_unread:
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.tooltip_text = "Click to mark as read"
		card.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton \
					and event.button_index == MOUSE_BUTTON_LEFT \
					and event.pressed:
				NewsManager.mark_read([entry])
		)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	# The contents must not swallow the click before it reaches the card.
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	# The unread dot — the same badge colour as the arrivals button, so an
	# unread item here reads as the same "new thing" signal as the HUD badge.
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(18, 18)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = URGENT if entry.get("urgent", false) else INK
	dot_style.set_corner_radius_all(9)
	dot.add_theme_stylebox_override("panel", dot_style)
	dot.visible = is_unread
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dot)

	var message := Label.new()
	message.text = str(entry.get("msg", ""))
	message.add_theme_font_size_override("font_size", 24)
	message.add_theme_color_override("font_color", URGENT if entry.get("urgent", false) else INK)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(message)

	var stamp := Label.new()
	stamp.text = NewsManager.time_ago(entry)
	stamp.add_theme_font_size_override("font_size", 20)
	stamp.add_theme_color_override("font_color", MUTED)
	stamp.custom_minimum_size = Vector2(140, 0)
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stamp)

	return card

# Marks every card currently inside the scroll viewport as read. Called on open
# and on every scroll, so news is only ever consumed by being looked at.
func _mark_visible_read() -> void:
	if not visible or _card_entries.is_empty():
		return
	var view_top := float(scroll.scroll_vertical)
	var view_bottom := view_top + scroll.size.y

	var seen: Array = []
	for card in _card_entries:
		if not is_instance_valid(card):
			continue
		var card_top: float = card.position.y
		var card_height: float = card.size.y
		if card_height <= 0.0:
			continue
		var overlap := minf(card_top + card_height, view_bottom) - maxf(card_top, view_top)
		if overlap >= card_height * VISIBLE_FRACTION:
			seen.append(_card_entries[card])

	# mark_read emits news_changed, which rebuilds this panel and repaints the
	# cards that just lost their unread dot.
	NewsManager.mark_read(seen)
