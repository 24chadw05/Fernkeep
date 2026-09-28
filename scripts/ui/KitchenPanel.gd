extends Control

# The Kitchen — GDD "Cooking & tavern quests". A board of meal requests from
# citizens; cooking one is a two-part minigame:
#   PREP   — add the recipe's ingredients in order from a pantry that also
#            holds a couple of decoys, against the clock.
#   SIMMER — hold "Stoke the fire" to keep the pot's heat inside the green band;
#            heat falls whenever you let go. Fill the simmer meter to finish.
# Mistakes, a slow prep, and time out of the band cost stars (0-3). The
# ingredients go in the pot as soon as cooking starts (CookingManager).

enum Phase { BOARD, PREP, SIMMER, RESULT }

const ICON_FALLBACK := "res://assets/ui/cooking_pot.png"
const HEARTH := "res://assets/ui/kitchen_hearth.png"
const FLAME := "res://assets/ui/kitchen_flame.png"
const POT := "res://assets/ui/kitchen_pot.png"
const STAR_FULL := "res://assets/ui/star_full.png"
const STAR_EMPTY := "res://assets/ui/star_empty.png"

const INK := Color(0.227, 0.157, 0.094)
const MUTED := Color(0.42, 0.33, 0.22)
const GOOD := Color(0.15, 0.45, 0.12)
const BAD := Color(0.62, 0.15, 0.1)

# Prep
const PREP_BASE_SECONDS: float = 4.0
const PREP_SECONDS_PER_STEP: float = 1.3
const MAX_STEPS_PER_INGREDIENT: int = 2   # quantities above this are one tap each
const DECOYS: int = 2
# Simmer
const HEAT_RISE: float = 0.55             # per second while stoking
const HEAT_FALL: float = 0.25             # per second otherwise
const BAND_LOW: float = 0.55
const BAND_HIGH: float = 0.80
const SIMMER_GOAL: float = 4.0            # seconds in the band to finish
const SIMMER_LIMIT: float = 12.0          # seconds allowed

var phase: int = Phase.BOARD
var _req_id: int = -1
var _dish: Dictionary = {}
# prep state
var _steps: Array = []                    # ingredient ids, in the order to add them
var _step_idx: int = 0
var _mistakes: int = 0
var _prep_left: float = 0.0
var _prep_total: float = 0.0
var _prep_finished: bool = false
# simmer state
var _heat: float = 0.2
var _stoking: bool = false
var _in_band: float = 0.0
var _simmer_time: float = 0.0
var _sizzle_acc: float = 0.0

var _body: VBoxContainer
var _title: Label
var _step_icons: Array = []
var _timer_bar: ProgressBar
var _heat_bar: ProgressBar
var _simmer_bar: ProgressBar
var _flame: TextureRect
var _hint: Label

func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.06, 0.04, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# Centred via anchors + offsets (setting .position on a centre-anchored
	# control places it in parent space, i.e. off the top-left of the screen).
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -600.0
	panel.offset_right = 600.0
	panel.offset_top = -410.0
	panel.offset_bottom = 410.0
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	margin.add_child(outer)

	var header := HBoxContainer.new()
	var pot_icon := TextureRect.new()
	pot_icon.texture = load(ICON_FALLBACK)
	pot_icon.custom_minimum_size = Vector2(64, 64)
	pot_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pot_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(pot_icon)
	_title = _label("The Kitchen", 40)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(76, 72)
	close.add_theme_font_size_override("font_size", 32)
	close.pressed.connect(_close)
	header.add_child(close)
	outer.add_child(header)
	outer.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	scroll.add_child(_body)

	SignalBus.open_kitchen_panel.connect(show_panel)
	SignalBus.close_all_panels.connect(_close)
	# Not resource_changed: producing buildings fire it every second, which would
	# rebuild the board (and reset its scroll) constantly. The board re-reads
	# the pantry whenever it's shown or the requests change.
	CookingManager.requests_changed.connect(func(): if visible and phase == Phase.BOARD: _show_board())

func show_panel() -> void:
	_show_board()
	visible = true

func _close() -> void:
	if not visible:
		return
	if phase == Phase.PREP or phase == Phase.SIMMER:
		_finish(0)   # walking away from the stove spoils the dish
	phase = Phase.BOARD
	visible = false

# ── board ─────────────────────────────────────────────────────────────────────

func _show_board() -> void:
	phase = Phase.BOARD
	_title.text = "The Kitchen"
	_clear()
	if not CookingManager.has_kitchen():
		_body.add_child(_label("Build a Tavern to open the kitchen — citizens will start asking for meals.", 26, MUTED, true))
		return
	if CookingManager.requests.is_empty():
		_body.add_child(_label("No one has asked for a meal yet. Requests arrive each morning.", 26, MUTED, true))
		return
	_body.add_child(_label("Cook what your citizens are craving. Every dish grants its own timed bonus — the better you cook, the longer it lasts. Food bonuses don't stack: the same dish refreshes its timer, and only the strongest bonus to each stat counts.", 22, MUTED, true))
	for req in CookingManager.requests:
		_body.add_child(_request_card(req))

func _request_card(req: Dictionary) -> Control:
	var dish = DataManager.get_dish(req.dish_id)
	var card := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	card.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tags: Array = []
	if req.get("seasonal", false):
		tags.append("★ in season")
	if not RecipeManager.is_dish_unlocked(req.dish_id):
		tags.append("NEW RECIPE — cook it well to add it to tavern menus")
	if CookingManager.is_mastered(req.dish_id):
		tags.append("Mastered")
	else:
		var perfect = int(CookingManager.perfect_counts.get(req.dish_id, 0))
		if perfect > 0:
			tags.append("Perfect cooks: %d/%d" % [perfect, CookingManager.MASTERY_PERFECTS])
	info.add_child(_label(str(dish.get("name", req.dish_id)), 30))
	info.add_child(_label("For %s   •   %d day(s) left" % [req.npc_name, int(req.days_left)], 22, MUTED))
	var buff_text := CookingManager.describe_buff(req.dish_id, bool(req.get("seasonal", false)))
	if buff_text != "":
		info.add_child(_label("✦ " + buff_text + "  (perfect cook)", 22, Color(0.35, 0.25, 0.5), true))
	if not tags.is_empty():
		info.add_child(_label("   ".join(PackedStringArray(tags)), 20, GOOD))

	var need := CookingManager.missing_ingredients(req)
	var ing_row := HBoxContainer.new()
	ing_row.add_theme_constant_override("separation", 14)
	for res_id in dish.get("ingredients", {}):
		var have = int(ResourceManager.get_amount(res_id))
		var want = int(dish.ingredients[res_id])
		var cell := HBoxContainer.new()
		cell.add_child(_icon(res_id, 36))
		cell.add_child(_label("%d/%d" % [mini(have, want), want], 20, BAD if need.has(res_id) else INK))
		cell.tooltip_text = ResourceManager.get_item_label(res_id)
		ing_row.add_child(cell)
	info.add_child(ing_row)
	row.add_child(info)

	var cook := Button.new()
	cook.text = "Cook"
	cook.custom_minimum_size = Vector2(180, 80)
	cook.add_theme_font_size_override("font_size", 30)
	cook.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cook.disabled = not need.is_empty()
	if not need.is_empty():
		var parts: Array = []
		for res_id in need:
			parts.append("%d %s" % [need[res_id], ResourceManager.get_item_label(res_id)])
		cook.tooltip_text = "Still need: " + ", ".join(PackedStringArray(parts))
	cook.pressed.connect(_start_cooking.bind(int(req.id)))
	row.add_child(cook)
	return card

# ── prep ──────────────────────────────────────────────────────────────────────

func _start_cooking(req_id: int) -> void:
	var req = CookingManager.get_request(req_id)
	if req.is_empty() or not CookingManager.begin_cooking(req_id):
		AudioManager.play("error")
		return
	_req_id = req_id
	_dish = DataManager.get_dish(req.dish_id)
	_steps.clear()
	for res_id in _dish.get("ingredients", {}):
		for _i in mini(int(_dish.ingredients[res_id]), MAX_STEPS_PER_INGREDIENT):
			_steps.append(res_id)
	_step_idx = 0
	_mistakes = 0
	_prep_total = PREP_BASE_SECONDS + PREP_SECONDS_PER_STEP * _steps.size()
	_prep_left = _prep_total
	_prep_finished = false
	phase = Phase.PREP
	_build_prep_view()

func _build_prep_view() -> void:
	_title.text = "Cooking: %s" % _dish.get("name", "")
	_clear()
	_body.add_child(_label("Add the ingredients in the order shown — quickly! Decoys are in the pantry too.", 24, MUTED, true))

	var strip := HBoxContainer.new()
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 10)
	_step_icons.clear()
	for i in _steps.size():
		var slot := PanelContainer.new()
		var ic := _icon(_steps[i], 72)
		ic.modulate = Color(1, 1, 1, 0.35)          # dim until it's been added
		slot.add_child(ic)
		strip.add_child(slot)
		if i < _steps.size() - 1:
			strip.add_child(_label("›", 36, MUTED))
		_step_icons.append(ic)
	_body.add_child(strip)

	_timer_bar = ProgressBar.new()
	_timer_bar.max_value = _prep_total
	_timer_bar.value = _prep_left
	_timer_bar.show_percentage = false
	_timer_bar.custom_minimum_size = Vector2(0, 22)
	_body.add_child(_timer_bar)

	# The pantry: every real ingredient once, plus decoys, shuffled.
	var pantry_ids: Array = []
	for res_id in _dish.get("ingredients", {}):
		pantry_ids.append(res_id)
	var decoy_pool: Array = ResourceManager.ITEM_INFO.keys().filter(func(r): return not pantry_ids.has(r))
	decoy_pool.shuffle()
	for i in mini(DECOYS, decoy_pool.size()):
		pantry_ids.append(decoy_pool[i])
	pantry_ids.shuffle()

	var pantry := HFlowContainer.new()
	pantry.alignment = FlowContainer.ALIGNMENT_CENTER
	pantry.add_theme_constant_override("h_separation", 16)
	pantry.add_theme_constant_override("v_separation", 16)
	for res_id in pantry_ids:
		var cell := VBoxContainer.new()
		var b := Button.new()
		b.custom_minimum_size = Vector2(132, 132)
		b.icon = _tex(res_id)
		b.expand_icon = true
		b.tooltip_text = ResourceManager.get_item_label(res_id)
		b.pressed.connect(_on_pantry.bind(res_id, b))
		cell.add_child(b)
		var name_lbl := _label(ResourceManager.get_item_label(res_id), 18, MUTED)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(name_lbl)
		pantry.add_child(cell)
	_body.add_child(pantry)
	_hint = _label("", 22, BAD)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(_hint)

func _on_pantry(res_id: String, button: Button) -> void:
	if phase != Phase.PREP:
		return
	if _step_idx < _steps.size() and _steps[_step_idx] == res_id:
		_step_icons[_step_idx].modulate = Color.WHITE
		_step_idx += 1
		AudioManager.play("chop", 0.08, 0)
		if _step_idx >= _steps.size():
			_prep_finished = true
			_begin_simmer()
	else:
		_mistakes += 1
		AudioManager.play("error", 0.0, 0)
		_hint.text = "Not that one — %d mistake(s)." % _mistakes
		var tw := create_tween()          # a little shake on the wrong button
		var x0 := button.position.x
		for dx in [-8.0, 8.0, -5.0, 0.0]:
			tw.tween_property(button, "position:x", x0 + dx, 0.04)

# ── simmer ────────────────────────────────────────────────────────────────────

func _begin_simmer() -> void:
	phase = Phase.SIMMER
	_heat = 0.2
	_stoking = false
	_in_band = 0.0
	_simmer_time = 0.0
	_clear()
	_body.add_child(_label("Hold “Stoke the fire” to keep the heat in the green band until the stew is simmered.", 24, MUTED, true))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)

	# Hearth, with the flame and pot layered on top of it
	var hearth := TextureRect.new()
	hearth.texture = load(HEARTH)
	hearth.custom_minimum_size = Vector2(384, 256)      # the 192x128 art at 2x
	hearth.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flame = TextureRect.new()
	_flame.texture = load(FLAME)
	_flame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hearth.add_child(_flame)
	var pot := TextureRect.new()
	pot.texture = load(POT)
	pot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pot.size = Vector2(128, 96)
	pot.position = Vector2(128, 112)
	hearth.add_child(pot)
	row.add_child(hearth)

	# Heat gauge with its target band marked
	var gauge := VBoxContainer.new()
	gauge.add_child(_label("Heat", 24))
	_heat_bar = ProgressBar.new()
	_heat_bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	_heat_bar.max_value = 1.0
	_heat_bar.show_percentage = false
	_heat_bar.custom_minimum_size = Vector2(60, 256)
	var band := ColorRect.new()
	band.color = Color(0.3, 0.7, 0.3, 0.45)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.position = Vector2(0, 256 * (1.0 - BAND_HIGH))
	band.size = Vector2(60, 256 * (BAND_HIGH - BAND_LOW))
	_heat_bar.add_child(band)
	gauge.add_child(_heat_bar)
	row.add_child(gauge)
	_body.add_child(row)

	_body.add_child(_label("Simmered", 22, MUTED))
	_simmer_bar = ProgressBar.new()
	_simmer_bar.max_value = SIMMER_GOAL
	_simmer_bar.show_percentage = false
	_simmer_bar.custom_minimum_size = Vector2(0, 22)
	_body.add_child(_simmer_bar)

	var stoke := Button.new()
	stoke.text = "Stoke the fire (hold)"
	stoke.custom_minimum_size = Vector2(420, 96)
	stoke.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stoke.add_theme_font_size_override("font_size", 32)
	stoke.button_down.connect(func(): _stoking = true)
	stoke.button_up.connect(func(): _stoking = false)
	_body.add_child(stoke)
	_update_simmer_visuals()

func _update_simmer_visuals() -> void:
	_heat_bar.value = _heat
	_simmer_bar.value = _in_band
	var ok := _heat >= BAND_LOW and _heat <= BAND_HIGH
	_heat_bar.modulate = Color(0.8, 1.2, 0.8) if ok else (Color(1.3, 0.8, 0.7) if _heat > BAND_HIGH else Color(1, 1, 1))
	# The flame is anchored on the logs and grows with the heat.
	var w := 192.0 * (0.6 + 0.4 * _heat)
	var h := maxf(4.0, 128.0 * _heat)
	_flame.size = Vector2(w, h)
	_flame.position = Vector2(192.0 - w / 2.0, 208.0 - h)

func _process(delta: float) -> void:
	match phase:
		Phase.PREP:
			_prep_left -= delta
			_timer_bar.value = maxf(_prep_left, 0.0)
			if _prep_left <= 0.0:
				_hint.text = "Out of time — the rest goes in any old how."
				_begin_simmer()
		Phase.SIMMER:
			_heat = clampf(_heat + (HEAT_RISE if _stoking else -HEAT_FALL) * delta, 0.0, 1.0)
			_simmer_time += delta
			if _heat >= BAND_LOW and _heat <= BAND_HIGH:
				_in_band += delta
				_sizzle_acc -= delta
				if _sizzle_acc <= 0.0:
					AudioManager.play("sizzle", 0.05, 0)
					_sizzle_acc = 0.9
			_update_simmer_visuals()
			if _in_band >= SIMMER_GOAL or _simmer_time >= SIMMER_LIMIT:
				_finish(_score())

# prep: 1.5 for a clean, finished prep, -0.5 per mistake; nothing if time ran out.
# simmer: up to 1.5 for how much of the goal was reached. Round to stars.
func _score() -> int:
	var prep := 0.0 if not _prep_finished else maxf(0.0, 1.5 - 0.5 * _mistakes)
	var simmer := 1.5 * clampf(_in_band / SIMMER_GOAL, 0.0, 1.0)
	return clampi(int(floor(prep + simmer + 0.26)), 0, 3)

# ── result ────────────────────────────────────────────────────────────────────

func _finish(stars: int) -> void:
	var result := CookingManager.finish_cooking(_req_id, stars)
	_stoking = false
	phase = Phase.RESULT
	AudioManager.play("cook_success" if stars > 0 else "cook_fail", 0.0, 0)
	if not visible:
		return
	_clear()
	var star_row := HBoxContainer.new()
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 3:
		var s := TextureRect.new()
		s.texture = load(STAR_FULL if i < stars else STAR_EMPTY)
		s.custom_minimum_size = Vector2(96, 96)
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star_row.add_child(s)
	_body.add_child(star_row)

	var headline: String = ["Ruined! The ingredients are lost — but they're still hungry.",
		"Edible.", "Delicious!", "Perfect!"][stars]
	var hl := _label(headline, 36, GOOD if stars > 0 else BAD)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(hl)
	if stars > 0 and not result.is_empty():
		var lines: Array = []
		if result.buff_name != "":
			lines.append("✦ %s for %s — %s" % [result.buff_name,
				CookingManager.days_text(result.buff_days), result.buff_text])
		lines.append("+%.0f reputation" % result.reputation)
		if result.unlocked:
			lines.append("New recipe learned — %s can go on tavern menus!" % result.dish)
		if result.mastered:
			lines.append("%s mastered! Taverns earn +25%% serving it." % result.dish)
		for l in lines:
			var lbl := _label(l, 26)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_body.add_child(lbl)
	var done := Button.new()
	done.text = "Back to the board"
	done.custom_minimum_size = Vector2(360, 80)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.add_theme_font_size_override("font_size", 28)
	done.pressed.connect(_show_board)
	_body.add_child(done)

# ── helpers ───────────────────────────────────────────────────────────────────

func _clear() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()

func _label(text: String, size: int, color: Color = INK, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _tex(res_id: String) -> Texture2D:
	var path := ResourceManager.get_item_icon_path(res_id)
	return load(path) if path != "" and ResourceLoader.exists(path) else load(ICON_FALLBACK)

func _icon(res_id: String, px: int) -> TextureRect:
	var t := TextureRect.new()
	t.texture = _tex(res_id)
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return t
