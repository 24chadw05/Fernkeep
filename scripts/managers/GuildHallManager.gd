extends Node

# Guild Hall quest board. Each quest ("ledger") asks for a set of resources and
# pays a reward worth ~2x their market value. The board re-rolls on a timer:
# 60 min with no Taskmaster, 30 min staffed, down to 15 as the Taskmaster is
# promoted (a bigger cut = harder work). Claiming a quest hands over the items,
# pays the reward, and gives the Taskmaster their cut of the deal.

const RARE_VALUE_THRESHOLD: float = 30.0   # market base value at/above which a good is "rare"
const REWARD_VALUE_MULT: float = 2.0       # reward is worth 2x the requested items
const BASE_REFRESH_UNSTAFFED: float = 3600.0  # 60 min
const REFRESH_STAFFED_MAX: float = 1800.0     # 30 min (fresh Taskmaster)
const REFRESH_STAFFED_MIN: float = 900.0      # 15 min (fully promoted)

# Per-guild-hall-tier limits
const QUESTS_PER_TIER: Dictionary = {1: 3, 2: 4, 3: 5}     # how many ledgers on the board
const ITEM_TYPES_PER_TIER: Dictionary = {1: 3, 2: 4, 3: 5}  # distinct items per quest
const RARE_QTY_CAP_PER_TIER: Dictionary = {1: 3, 2: 6, 3: 10}  # max qty of a rare item

const CUT_MIN: float = 0.01
const CUT_MAX: float = 0.10
const CUT_STEP: float = 0.01   # each promotion

# Flavor titles rolled per quest
const TITLES: Array = [
	"Looking for", "In need of", "The guild requests", "Gathering",
	"Wanted:", "A call for", "Seeking", "Supplies needed:",
]

# quest = {"id": int, "title": String, "requests": [{res, qty}], "rewards": [{res|"gold", qty}], "claimed": bool}
var board: Array = []
var time_left: float = BASE_REFRESH_UNSTAFFED
var _next_id: int = 0

signal board_changed()

func _ready() -> void:
	# Upgrading the guild hall changes the tier → re-roll so the new quest
	# count (T1=1, T2=3, T3=5) takes effect right away.
	BuildingManager.building_upgraded.connect(_on_building_upgraded)

func _on_building_upgraded(b: PlacedBuilding) -> void:
	if b.building_id == "guild_hall":
		roll_board()

func _process(delta: float) -> void:
	if not BuildingManager.has_building_type("guild_hall"):
		return
	# Roll when empty OR when the board size no longer matches the current tier
	# (e.g. an old T1 board loaded from a save that's since reached T2/T3).
	if board.size() != _expected_count():
		roll_board()
	time_left -= delta
	if time_left <= 0.0:
		roll_board()
		SignalBus.show_notification.emit("The Guild Hall posted new quests!")

func _expected_count() -> int:
	return int(QUESTS_PER_TIER.get(_guild_tier(), 1))

# ── The Taskmaster ──────────────────────────────────────────────────────────

func get_guild_hall() -> PlacedBuilding:
	var halls = BuildingManager.get_buildings_of_type("guild_hall")
	return halls[0] if not halls.is_empty() else null

func get_taskmaster() -> NPC:
	var hall = get_guild_hall()
	if hall == null or hall.assigned_staff.is_empty():
		return null
	return CitizenManager.get_citizen_by_id(hall.assigned_staff[0])

func get_cut() -> float:
	var hall = get_guild_hall()
	return hall.taskmaster_cut if hall else 0.0

# Promote the Taskmaster: bigger cut, faster board. Returns false if maxed.
func promote_taskmaster() -> bool:
	var hall = get_guild_hall()
	if hall == null or get_taskmaster() == null:
		return false
	if hall.taskmaster_cut >= CUT_MAX - 0.0001:
		return false
	hall.taskmaster_cut = minf(CUT_MAX, hall.taskmaster_cut + CUT_STEP)
	emit_signal("board_changed")
	return true

func _refresh_interval() -> float:
	if get_taskmaster() == null:
		return BASE_REFRESH_UNSTAFFED
	# Promotion level (cut) drives how hard they work: 1% → 30 min, 10% → 15 min
	var t = (get_cut() - CUT_MIN) / maxf(CUT_MAX - CUT_MIN, 0.0001)
	return lerpf(REFRESH_STAFFED_MAX, REFRESH_STAFFED_MIN, clampf(t, 0.0, 1.0))

# ── Board generation ────────────────────────────────────────────────────────

func _guild_tier() -> int:
	var hall = get_guild_hall()
	return hall.tier if hall else 1

func _is_rare(res_id: String) -> bool:
	return MarketManager.get_base_value(res_id) >= RARE_VALUE_THRESHOLD

func _all_goods() -> Array:
	return MarketManager.goods.keys()

func roll_board() -> void:
	time_left = _refresh_interval()
	board.clear()
	var tier = _guild_tier()
	var count = int(QUESTS_PER_TIER.get(tier, 1))
	for _i in range(count):
		board.append(_roll_quest(tier))
	emit_signal("board_changed")
	print("[GuildHall] Board rolled: %d quests (tier %d)." % [board.size(), tier])

func _roll_quest(tier: int) -> Dictionary:
	var goods: Array = _all_goods()
	goods.shuffle()
	var max_types = int(ITEM_TYPES_PER_TIER.get(tier, 3))
	var rare_cap = int(RARE_QTY_CAP_PER_TIER.get(tier, 3))
	var type_count = randi_range(1, max_types)

	var requests: Array = []
	var request_value := 0.0
	for res_id in goods:
		if requests.size() >= type_count:
			break
		var qty: int
		if _is_rare(res_id):
			qty = randi_range(1, rare_cap)
		else:
			qty = randi_range(5, 100)
		requests.append({"res": res_id, "qty": qty})
		request_value += MarketManager.get_current_value(res_id) * qty

	var rewards := _roll_rewards(request_value * REWARD_VALUE_MULT, rare_cap)

	# Title names the headline (largest) request
	var headline = requests[0]["res"] if not requests.is_empty() else "goods"
	var title = "%s %s" % [TITLES[randi() % TITLES.size()], ResourceManager.get_item_label(headline)]

	_next_id += 1
	return {"id": _next_id, "title": title, "requests": requests, "rewards": rewards, "claimed": false}

# Fill `target_value` gold worth of reward, part gold and part materials, with
# no more rare items than the guild tier allows a request to contain.
func _roll_rewards(target_value: float, rare_cap: int) -> Array:
	var rewards: Array = []
	var remaining = target_value

	# Roughly half in gold (rounded), the rest in materials
	var gold_part = roundf(remaining * randf_range(0.35, 0.6))
	if gold_part >= 1.0:
		rewards.append({"res": "gold", "qty": int(gold_part)})
		remaining -= gold_part

	var goods: Array = _all_goods()
	goods.shuffle()
	var rare_used := 0
	for res_id in goods:
		if remaining < MarketManager.get_current_value(res_id):
			continue
		var unit = MarketManager.get_current_value(res_id)
		if unit <= 0.0:
			continue
		var is_rare = _is_rare(res_id)
		var max_qty = int(remaining / unit)
		if is_rare:
			max_qty = min(max_qty, rare_cap - rare_used)
		if max_qty <= 0:
			continue
		var qty = randi_range(1, max_qty)
		if is_rare:
			rare_used += qty
		rewards.append({"res": res_id, "qty": qty})
		remaining -= unit * qty
		if remaining < 1.0 or rewards.size() >= 4:
			break

	# Guarantee at least something
	if rewards.is_empty():
		rewards.append({"res": "gold", "qty": maxi(1, int(target_value))})
	return rewards

# ── Claiming ────────────────────────────────────────────────────────────────

func can_claim(index: int) -> bool:
	if index < 0 or index >= board.size():
		return false
	var q: Dictionary = board[index]
	if q.get("claimed", false):
		return false
	for r in q["requests"]:
		if ResourceManager.get_amount(r["res"]) < float(r["qty"]):
			return false
	return true

func claim(index: int) -> String:
	if not can_claim(index):
		return "You don't have everything the guild asked for."
	var q: Dictionary = board[index]

	# Hand over the requested items
	for r in q["requests"]:
		ResourceManager.spend(r["res"], float(r["qty"]), "Guild quest")

	# Pay the reward and tally its total value for the Taskmaster's cut
	var reward_value := 0.0
	var gold_reward := 0.0
	for rw in q["rewards"]:
		if rw["res"] == "gold":
			gold_reward += float(rw["qty"])
			reward_value += float(rw["qty"])
		else:
			ResourceManager.add(rw["res"], float(rw["qty"]), "Guild reward")
			reward_value += MarketManager.get_current_value(rw["res"]) * float(rw["qty"])
	if gold_reward > 0.0:
		EconomyManager.add_gold(gold_reward, "Guild quest reward")

	# The Taskmaster's cut — from the gold reward if there was one, else the treasury
	var tm = get_taskmaster()
	if tm != null:
		var cut = reward_value * get_cut()
		if cut >= 1.0:
			EconomyManager.spend_gold(cut, "Taskmaster's cut")
			tm.savings += cut  # the cut is the Taskmaster's living
			SignalBus.show_notification.emit("%s took a %.0f%% cut (%.0fg)." % [
				tm.get_full_name(), get_cut() * 100.0, cut
			])

	q["claimed"] = true
	board[index] = q
	MarketManager.trade_completed.emit("guild", "quest", 1)
	ProgressionManager.reward_xp("quest_completed")
	emit_signal("board_changed")
	return ""

# ── Save / Load ─────────────────────────────────────────────────────────────

func reset() -> void:
	board.clear()
	_next_id = 0
	time_left = BASE_REFRESH_UNSTAFFED
	emit_signal("board_changed")

func to_dict() -> Dictionary:
	return {"board": board.duplicate(true), "time_left": time_left, "next_id": _next_id}

func from_dict(data: Dictionary) -> void:
	board = data.get("board", []).duplicate(true)
	time_left = float(data.get("time_left", BASE_REFRESH_UNSTAFFED))
	_next_id = int(data.get("next_id", 0))
	emit_signal("board_changed")
