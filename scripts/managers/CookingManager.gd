extends Node

# CookingManager — the GDD's "Cooking & tavern quests": citizens ask for a dish,
# the player cooks it in the Kitchen minigame (KitchenPanel), and a good result
# grants that dish's timed BUFF (recipes.json "buff": happiness for everyday
# food, economic and reputation edges for dishes made from rare catches), a
# little reputation, cheers up whoever asked, and can unlock the dish for the
# tavern menus. Cooking the same dish perfectly three times masters it:
# taverns then earn more every time they serve it.
#
# Requests only appear once the city has a tavern (the kitchen lives there) and
# at least one citizen to do the asking.

const MAX_REQUESTS: int = 3
const REQUEST_DAYS: int = 4             # a request goes stale after this many days
# Stars scale how long the buff lasts: a perfect cook gets the full duration.
const STAR_DURATION: Array = [0.0, 0.5, 0.75, 1.0]
const SEASONAL_DURATION: float = 1.5    # in-season dishes' buffs last half again
const REPUTATION_PER_STAR: float = 1.0 / 3.0   # of the dish's reputation_gain
const LOCKED_REQUEST_CHANCE: float = 0.3
const MASTERY_PERFECTS: int = 3
const MASTERY_SERVE_MULT: float = 1.25
const TREAT_DAYS: int = 3               # how long a well-cooked meal cheers its requester

# {"id", "npc_id", "npc_name", "dish_id", "days_left", "seasonal"}  (older saves may also carry an unused "tip")
var requests: Array = []
var perfect_counts: Dictionary = {}     # dish_id → 3-star cooks
var mastered: Dictionary = {}           # dish_id → true
var _next_id: int = 0

signal requests_changed()
signal dish_cooked(dish_id: String, stars: int)
signal dish_mastered(dish_id: String)

func _ready() -> void:
	TimeManager.new_day.connect(_on_new_day)

# ── queries ───────────────────────────────────────────────────────────────────

func has_kitchen() -> bool:
	return BuildingManager.has_building_type("tavern")

func get_request(req_id: int) -> Dictionary:
	for r in requests:
		if int(r.id) == req_id:
			return r
	return {}

func can_cook(req: Dictionary) -> bool:
	var dish = DataManager.get_dish(str(req.get("dish_id", "")))
	return not dish.is_empty() and ResourceManager.can_afford_cost(dish.get("ingredients", {}))

func missing_ingredients(req: Dictionary) -> Dictionary:
	var dish = DataManager.get_dish(str(req.get("dish_id", "")))
	var need: Dictionary = {}
	for res_id in dish.get("ingredients", {}):
		var short = float(dish.ingredients[res_id]) - ResourceManager.get_amount(res_id)
		if short > 0.0:
			need[res_id] = int(ceil(short))
	return need

# How long a dish's buff lasts for a given result (in real seconds; a game day
# is TimeManager.DAY_LENGTH_SECONDS).
func get_buff_seconds(dish: Dictionary, stars: int, seasonal: bool) -> float:
	var days = float(dish.get("buff", {}).get("days", 1.0))
	return days * TimeManager.DAY_LENGTH_SECONDS * float(STAR_DURATION[clampi(stars, 0, 3)]) \
		* (SEASONAL_DURATION if seasonal else 1.0)

# "Tavern Favourite: +25% tavern takings for 1 day" — for cards and tooltips.
func describe_buff(dish_id: String, seasonal: bool = false) -> String:
	var dish = DataManager.get_dish(dish_id)
	var buff: Dictionary = dish.get("buff", {})
	if buff.is_empty():
		return ""
	var days = get_buff_seconds(dish, 3, seasonal) / TimeManager.DAY_LENGTH_SECONDS
	return "%s: %s for %s" % [buff.get("name", ""), RecipeManager.describe_effect(buff.get("effect", {})),
		days_text(days)]

func days_text(days: float) -> String:
	if is_equal_approx(days, roundf(days)):
		return "%d day%s" % [roundi(days), "" if roundi(days) == 1 else "s"]
	return "%.1f days" % days

# Taverns serve a mastered dish for more (RecipeManager._serve_daily_meals).
func get_serve_multiplier(dish_id: String) -> float:
	return MASTERY_SERVE_MULT if mastered.has(dish_id) else 1.0

func is_mastered(dish_id: String) -> bool:
	return mastered.has(dish_id)

# ── cooking ───────────────────────────────────────────────────────────────────

# Called by the Kitchen when the player starts on a request: the ingredients go
# into the pot whatever the outcome — a burnt stew still used the vegetables.
func begin_cooking(req_id: int) -> bool:
	var req = get_request(req_id)
	if req.is_empty() or not can_cook(req):
		return false
	var dish = DataManager.get_dish(req.dish_id)
	ResourceManager.spend_cost(dish.get("ingredients", {}), "Cooked for " + req.npc_name)
	return true

# stars: 0 (ruined) .. 3 (perfect). Returns a summary for the Kitchen to show.
func finish_cooking(req_id: int, stars: int) -> Dictionary:
	var req = get_request(req_id)
	if req.is_empty():
		return {}
	var dish = DataManager.get_dish(req.dish_id)
	var dish_name = str(dish.get("name", req.dish_id))
	var result := {"stars": stars, "dish": dish_name, "reputation": 0.0,
		"buff_name": "", "buff_text": "", "buff_days": 0.0, "unlocked": false, "mastered": false}
	emit_signal("dish_cooked", req.dish_id, stars)
	if stars <= 0:
		# The request stands — they're still hungry; the ingredients are gone.
		return result

	var buff: Dictionary = dish.get("buff", {})
	if not buff.is_empty():
		var seconds = get_buff_seconds(dish, stars, bool(req.get("seasonal", false)))
		RecipeManager.add_timed_effect("dish:" + req.dish_id, str(buff.get("name", dish_name)),
			buff.get("effect", {}), seconds, bool(buff.get("stacks", false)))
		result.buff_name = str(buff.get("name", dish_name))
		result.buff_text = RecipeManager.describe_effect(buff.get("effect", {}))
		result.buff_days = seconds / TimeManager.DAY_LENGTH_SECONDS
	var rep = float(dish.get("reputation_gain", 1)) * stars * REPUTATION_PER_STAR
	ReputationManager.add_reputation(rep, "%s loved the %s" % [req.npc_name, dish_name])
	ProgressionManager.reward_xp("trade_completed")
	result.reputation = rep

	var npc = CitizenManager.get_citizen_by_id(req.npc_id)
	if npc:
		npc.treat_days = maxi(npc.treat_days, TREAT_DAYS)
		npc.calculate_happiness()

	# A good cook of a dish the taverns don't know yet teaches it to them.
	if stars >= 2 and not RecipeManager.is_dish_unlocked(req.dish_id):
		RecipeManager.unlock_dish(req.dish_id)
		result.unlocked = true

	if stars >= 3:
		perfect_counts[req.dish_id] = int(perfect_counts.get(req.dish_id, 0)) + 1
		if perfect_counts[req.dish_id] >= MASTERY_PERFECTS and not mastered.has(req.dish_id):
			mastered[req.dish_id] = true
			result.mastered = true
			emit_signal("dish_mastered", req.dish_id)
			SignalBus.show_notification.emit(
				"%s mastered! Taverns earn +%d%% serving it." % [dish_name, int((MASTERY_SERVE_MULT - 1.0) * 100.0)]
			)

	requests.erase(req)
	emit_signal("requests_changed")
	return result

# ── daily requests ────────────────────────────────────────────────────────────

func _on_new_day(_day: int, _season: String, _year: int) -> void:
	var changed := false
	for r in requests.duplicate():
		r.days_left = int(r.days_left) - 1
		if int(r.days_left) <= 0 or CitizenManager.get_citizen_by_id(r.npc_id) == null:
			requests.erase(r)
		changed = true
	if has_kitchen() and requests.size() < MAX_REQUESTS and not CitizenManager.citizens.is_empty():
		# Usually one new request a day; two when the queue is empty.
		var wanted = 2 if requests.is_empty() else 1
		for _i in wanted:
			if requests.size() < MAX_REQUESTS and _add_request():
				changed = true
	if changed:
		emit_signal("requests_changed")

func _add_request() -> bool:
	var dish_id = _pick_dish()
	if dish_id == "":
		return false
	# Someone who hasn't already asked for something
	var asking: Dictionary = {}
	for r in requests:
		asking[r.npc_id] = true
	var candidates = CitizenManager.citizens.filter(func(c): return not asking.has(c.id))
	if candidates.is_empty():
		return false
	var npc: NPC = candidates[randi() % candidates.size()]
	var dish = DataManager.get_dish(dish_id)
	var seasonal = _is_in_season(dish)
	requests.append({
		"id": _next_id, "npc_id": npc.id, "npc_name": npc.get_full_name(),
		"dish_id": dish_id, "days_left": REQUEST_DAYS, "seasonal": seasonal,
	})
	_next_id += 1
	SignalBus.show_notification.emit("%s is craving %s — visit the Kitchen." % [
		npc.first_name, dish.get("name", dish_id)
	])
	return true

func _pick_dish() -> String:
	var tavern_tier = RecipeManager.get_best_tier("tavern")
	var known: Array = []
	var locked: Array = []
	var seasonal: Array = []
	for dish_id in DataManager.recipes.get("dishes", {}):
		if dish_id == "comment":
			continue
		var dish = DataManager.get_dish(dish_id)
		if int(dish.get("tavern_tier_required", 1)) > tavern_tier:
			continue
		if _is_in_season(dish):
			seasonal.append(dish_id)
		if RecipeManager.is_dish_unlocked(dish_id):
			known.append(dish_id)
		elif _ingredients_known(dish):
			locked.append(dish_id)   # only ask for what the player could actually make
	if not seasonal.is_empty() and randf() < 0.5:
		return seasonal[randi() % seasonal.size()]
	if not locked.is_empty() and randf() < LOCKED_REQUEST_CHANCE:
		return locked[randi() % locked.size()]
	if not known.is_empty():
		return known[randi() % known.size()]
	return ""

func _is_in_season(dish: Dictionary) -> bool:
	var cond = dish.get("unlock", "")
	return cond is Dictionary and cond.has("season") \
		and str(cond.season).to_lower() == TimeManager.get_season_name().to_lower()

func _ingredients_known(dish: Dictionary) -> bool:
	for res_id in dish.get("ingredients", {}):
		if not RecipeManager.discovered_ingredients.has(res_id) and ResourceManager.get_amount(res_id) <= 0.0:
			return false
	return true

# ── save / load / reset ───────────────────────────────────────────────────────

func reset() -> void:
	requests.clear()
	perfect_counts.clear()
	mastered.clear()
	_next_id = 0
	emit_signal("requests_changed")

func to_dict() -> Dictionary:
	return {"requests": requests.duplicate(true), "perfect_counts": perfect_counts.duplicate(),
		"mastered": mastered.keys(), "next_id": _next_id}

func from_dict(data: Dictionary) -> void:
	requests.clear()
	for r in data.get("requests", []):
		if r is Dictionary and r.has("dish_id") and not DataManager.get_dish(str(r.dish_id)).is_empty():
			r.id = int(r.get("id", 0))
			r.days_left = int(r.get("days_left", 1))
			requests.append(r)
	perfect_counts = data.get("perfect_counts", {}).duplicate()
	mastered.clear()
	for d in data.get("mastered", []):
		mastered[str(d)] = true
	_next_id = int(data.get("next_id", 0))
	for r in requests:                     # never reissue an id that's in use
		_next_id = maxi(_next_id, int(r.id) + 1)
	emit_signal("requests_changed")
