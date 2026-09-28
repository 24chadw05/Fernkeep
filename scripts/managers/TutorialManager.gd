extends Node

# TutorialManager — the GDD's Phase 4 "tutorial flow": a guided first session
# for a brand-new game. Each step completes when the player actually does the
# thing (the same signals the game already emits), not when they click "next",
# so nothing is scripted around them. TutorialOverlay draws the coach card and
# highlights the control each step is about.
#
# It runs only for a true new game — not after prestige, and not for saves made
# before the tutorial existed. Progress is saved per slot.

# target: node path from the main scene to the control to highlight ("" = none)
# next:   the step completes from a button on the coach card, not an action
const STEPS: Array = [
	{"id": "welcome", "title": "Welcome, founder!", "next": true, "button": "Let's begin",
	 "text": "You've found a forgotten hamlet — two crumbling houses and a town hall. Let's turn it into a kingdom.", "target": ""},
	{"id": "open_build", "title": "Build something",
	 "text": "Open the Build menu.", "target": "CanvasLayer/HUD/Panel/VBox/BuildButton"},
	{"id": "build_camp", "title": "A Logging Camp",
	 "text": "Build a Logging Camp — it needs no materials, and its wood pays for everything else. Buildings must face a road.", "target": ""},
	{"id": "arrival", "title": "A traveller at the gates",
	 "text": "Someone wants to settle here! Open the arrivals and welcome them in.", "target": "CanvasLayer/HUD/ArrivalsButton"},
	{"id": "assign", "title": "Put them to work",
	 "text": "Open Citizens, select your new citizen, pick the Logging Camp and press Assign.", "target": "CanvasLayer/HUD/Panel/VBox/CitizensButton"},
	{"id": "payday", "title": "Payday",
	 "text": "Your camp is working. At the end of each day its takings pay the wages, and the rest lands in your treasury. Wait for sundown…", "target": "CanvasLayer/HUD/Panel/VBox/GoldLabel"},
	{"id": "forage", "title": "Go exploring",
	 "text": "While the city works, take a foraging trip and gather what you find.", "target": "CanvasLayer/HUD/Panel/VBox/ForageButton"},
	{"id": "done", "title": "You're ready", "next": true, "button": "Start building",
	 "text": "Next: save 15 wood for a Tavern — citizens will ask for meals in its Kitchen. The newspaper keeps the city's news. Put the game down any time: your city keeps earning.", "target": ""},
]

var active: bool = false
var step: int = 0
var _achieved: Dictionary = {}   # step id → true, even if done before its turn

signal step_changed(index: int)
signal finished()

func _ready() -> void:
	SignalBus.open_build_menu.connect(func(): _achieve("open_build"))
	BuildingManager.building_placed.connect(_on_building_placed)
	CitizenManager.citizen_arrived.connect(func(_n): _achieve("arrival"))
	CitizenManager.citizen_assigned.connect(func(_n, _b): _achieve("assign"))
	EconomyManager.day_settled.connect(func(_r, _w, _p): _achieve("payday"))
	ForageManager.foraged.connect(func(_r, _a): _achieve("forage"))

func _on_building_placed(b: PlacedBuilding) -> void:
	if b.building_id == "logging_camp":
		_achieve("build_camp")

func start() -> void:
	active = true
	step = 0
	_achieved.clear()
	_enter_step()

func skip() -> void:
	if not active:
		return
	active = false
	emit_signal("finished")

func current() -> Dictionary:
	return STEPS[step] if active and step < STEPS.size() else {}

# Called by the coach card's button on "next" steps.
func advance() -> void:
	if not active:
		return
	step += 1
	if step >= STEPS.size():
		active = false
		emit_signal("finished")
		return
	_enter_step()

func _achieve(step_id: String) -> void:
	_achieved[step_id] = true
	if active and current().get("id", "") == step_id:
		advance()

func _enter_step() -> void:
	var s: Dictionary = STEPS[step]
	# Already done it before we got here? Move straight on.
	if not s.get("next", false) and _achieved.has(s.id):
		advance()
		return
	match s.id:
		"arrival":
			# Don't make a new player wait up to 45s for the step to be possible.
			if CitizenManager.get_pending_count() == 0:
				CitizenManager.spawn_arrival_now()
		"assign":
			if CitizenManager.citizens.is_empty():     # they declined everyone
				step = _index_of("arrival")
				_enter_step()
				return
	emit_signal("step_changed", step)

func _index_of(step_id: String) -> int:
	for i in STEPS.size():
		if STEPS[i].id == step_id:
			return i
	return 0

# ── save / load / reset ───────────────────────────────────────────────────────

func reset() -> void:
	active = false
	step = 0
	_achieved.clear()
	emit_signal("finished")

func to_dict() -> Dictionary:
	return {"active": active, "step": step, "achieved": _achieved.keys()}

# Saves from before the tutorial existed load with an empty dict: inactive.
func from_dict(data: Dictionary) -> void:
	active = bool(data.get("active", false))
	step = clampi(int(data.get("step", 0)), 0, STEPS.size() - 1)
	_achieved.clear()
	for a in data.get("achieved", []):
		_achieved[str(a)] = true
	if active:
		call_deferred("_enter_step")   # the overlay may not exist yet
	else:
		emit_signal("finished")
