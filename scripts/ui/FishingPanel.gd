extends Control

# Fishing trip — cast, wait for the bite, then stop the sweeping marker inside
# the green catch zone. Rarer fish have smaller zones and faster markers.

const ICON_DIR := "res://assets/fishing/"

enum State { IDLE, WAITING, BITE, DONE }

var state: int = State.IDLE
var casts_left: int = 0
var _caught: Dictionary = {}          # resource_id → count
var _wait_timer: float = 0.0
var _bite_timer: float = 0.0          # escapes when it runs out
var _sweep_t: float = 0.0
var _current_fish: Dictionary = {}
var _zone_start: float = 0.0          # 0..1 along the bar

@onready var title_label: Label = $Header/Title
@onready var charges_label: Label = $Header/ChargesLabel
@onready var leave_button: Button = $Header/LeaveButton
@onready var status_label: Label = $StatusLabel
@onready var bar_bg: ColorRect = $BarArea/BarBG
@onready var zone_rect: ColorRect = $BarArea/BarBG/Zone
@onready var marker_rect: ColorRect = $BarArea/BarBG/Marker
@onready var fish_icon: TextureRect = $FishIcon
@onready var action_button: Button = $ActionButton
@onready var caught_label: Label = $CaughtLabel

func _ready() -> void:
	visible = false
	SignalBus.open_fishing_panel.connect(show_panel)
	SignalBus.close_all_panels.connect(_leave)
	leave_button.pressed.connect(_leave)
	action_button.pressed.connect(_on_action)
	FishingManager.charges_changed.connect(func(c): charges_label.text = "Trips left today: %d" % c)

func show_panel() -> void:
	if not FishingManager.can_fish():
		SignalBus.show_notification.emit("No fishing trips left — the fish need a rest too.")
		return
	casts_left = FishingManager.start_trip()
	_caught.clear()
	charges_label.text = "Trips left today: %d" % FishingManager.charges
	title_label.text = "Fishing — the River"
	_set_state(State.IDLE)
	_update_caught_label()
	visible = true

func _leave() -> void:
	if not visible:
		return
	visible = false
	if not _caught.is_empty():
		var parts: Array = []
		for res_id in _caught:
			parts.append("%d %s" % [_caught[res_id], ResourceManager.get_item_label(res_id)])
		SignalBus.show_notification.emit("Fishing haul: " + ", ".join(PackedStringArray(parts)))

func _set_state(new_state: int) -> void:
	state = new_state
	match state:
		State.IDLE:
			status_label.text = "%d cast(s) left — throw your line!" % casts_left
			action_button.text = "Cast"
			action_button.disabled = false
			bar_bg.visible = false
			fish_icon.visible = false
		State.WAITING:
			status_label.text = "Waiting for a bite…"
			action_button.text = "…"
			action_button.disabled = true
			bar_bg.visible = false
			_wait_timer = randf_range(1.0, 2.8)
		State.BITE:
			status_label.text = "A bite! Stop the marker in the green zone!"
			action_button.text = "Catch!"
			action_button.disabled = false
			bar_bg.visible = true
			_sweep_t = 0.0
			_bite_timer = 4.0
			# A copy: roll_bite hands back the constant catch-table entry, and the
			# zone is widened here by any fishing buff (capped so it's still a game)
			_current_fish = FishingManager.roll_bite().duplicate()
			_current_fish["zone"] = minf(float(_current_fish["zone"]) * RecipeManager.get_fishing_zone_multiplier(), 0.6)
			var zone_width = float(_current_fish["zone"])
			_zone_start = randf_range(0.05, 0.95 - zone_width)
			var bar_w = bar_bg.size.x
			zone_rect.position.x = _zone_start * bar_w
			zone_rect.size.x = zone_width * bar_w
			fish_icon.visible = false
		State.DONE:
			status_label.text = "Out of casts — a fine day on the water."
			action_button.text = "Head Home"
			action_button.disabled = false
			bar_bg.visible = false

func _process(delta: float) -> void:
	if not visible:
		return
	match state:
		State.WAITING:
			_wait_timer -= delta
			if _wait_timer <= 0.0:
				_set_state(State.BITE)
		State.BITE:
			_bite_timer -= delta
			_sweep_t += delta * float(_current_fish["speed"])
			var pos = 0.5 + 0.5 * sin(_sweep_t)
			marker_rect.position.x = pos * (bar_bg.size.x - marker_rect.size.x)
			if _bite_timer <= 0.0:
				status_label.text = "It got away…"
				_finish_cast()

func _on_action() -> void:
	match state:
		State.IDLE:
			AudioManager.play("splash")      # the cast hits the water
			_set_state(State.WAITING)
		State.BITE:
			_resolve_catch()
		State.DONE:
			_leave()

func _resolve_catch() -> void:
	var bar_w = bar_bg.size.x
	var marker_center = (marker_rect.position.x + marker_rect.size.x * 0.5) / bar_w
	var zone_width = float(_current_fish["zone"])
	var fish_id: String = _current_fish["id"]
	if marker_center >= _zone_start and marker_center <= _zone_start + zone_width:
		FishingManager.land_catch(fish_id)
		AudioManager.play("catch")
		_caught[fish_id] = int(_caught.get(fish_id, 0)) + 1
		var pretty = ResourceManager.get_item_label(fish_id)
		status_label.text = "✨ Caught a legendary fish!" if fish_id == "legendary_fish" \
			else "Caught a %s!" % pretty
		var icon_path = ICON_DIR + fish_id + ".png"
		if ResourceLoader.exists(icon_path):
			fish_icon.texture = load(icon_path)
			fish_icon.visible = true
		_update_caught_label()
	else:
		status_label.text = "Too slow — it slipped off the hook!"
		AudioManager.play("cook_fail", 0.0)
	_finish_cast()

func _finish_cast() -> void:
	casts_left -= 1
	bar_bg.visible = false
	if casts_left <= 0:
		_set_state(State.DONE)
	else:
		action_button.text = "Cast"
		action_button.disabled = false
		state = State.IDLE
		# Keep the last catch message visible; show remaining casts alongside
		status_label.text += "   (%d cast(s) left)" % casts_left

func _update_caught_label() -> void:
	if _caught.is_empty():
		caught_label.text = "Nothing caught yet."
		return
	var parts: Array = []
	for res_id in _caught:
		parts.append("%s ×%d" % [ResourceManager.get_item_label(res_id), _caught[res_id]])
	caught_label.text = "Caught:  " + "   ".join(PackedStringArray(parts))
