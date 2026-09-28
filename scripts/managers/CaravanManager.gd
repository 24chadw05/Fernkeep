extends Node

# CaravanManager — visiting merchant caravans (GDD: unlocked at Market Tier 2).
# While a market of tier 2+ stands, caravans roll into town every few days with
# a handful of one-time deals: discounted bulk buys, premium sell offers, and
# barter swaps. At Market Tier 3 + the "passive_trade_route" quest flag, trade
# routes also trickle in free goods daily.

signal caravan_arrived(caravan_name: String, days: int)
signal caravan_departed()
signal deals_changed()
signal caravan_trade(kind: String, resource_id: String, quantity: int)

const ARRIVAL_CHANCE: float = 0.35   # per day, once the gap has passed
const MIN_DAYS_BETWEEN: int = 2
const STAY_DAYS: int = 2

const MERCHANT_NAMES: Array = [
	"Zarah's Caravan", "The Dustroad Company", "Bramblewick Traders",
	"The Gilded Wheel", "Caravan of the Seven Winds", "Old Tam's Wagons",
]

# Resources caravans deal in (must exist in MarketManager.goods for pricing)
const DEAL_RESOURCES: Array = [
	"wood", "stone", "herbs", "grain", "vegetables", "fish", "mushroom",
	"wild_honey", "boar_meat", "basic_fruit", "premium_fruit", "rare_herbs",
	"enchanted_ore",
]

var active: bool = false
var caravan_name: String = ""
var days_left: int = 0
var days_since_last: int = 99
# Deals: {"kind": buy|sell|barter, "give_res", "give_qty", "get_res", "get_qty",
#         "gold": price (buy/sell), "taken": bool}
var deals: Array = []

func _ready() -> void:
	TimeManager.new_day.connect(_on_new_day)

func _market_tier() -> int:
	var best = 0
	for b in BuildingManager.get_buildings_of_type("market"):
		best = max(best, b.tier)
	return best

func _on_new_day(_day: int, _season: String, _year: int) -> void:
	_passive_trade_route()

	if active:
		days_left -= 1
		if days_left <= 0:
			_depart()
		return

	days_since_last += 1
	if _market_tier() < 2:
		return
	if days_since_last >= MIN_DAYS_BETWEEN and randf() < ARRIVAL_CHANCE:
		_arrive()

# Trade routes as passive generators (Market T3 + quest reward flag)
func _passive_trade_route() -> void:
	if _market_tier() < 3:
		return
	if not ("passive_trade_route" in QuestManager.permanent_unlocks):
		return
	var res: String = DEAL_RESOURCES[randi() % DEAL_RESOURCES.size()]
	var qty := randi_range(2, 5)
	ResourceManager.add(res, float(qty), "Trade route shipment")

func _arrive() -> void:
	active = true
	caravan_name = MERCHANT_NAMES[randi() % MERCHANT_NAMES.size()]
	days_left = STAY_DAYS
	days_since_last = 0
	_generate_deals()
	emit_signal("caravan_arrived", caravan_name, days_left)
	SignalBus.show_notification.emit("🐫 %s has arrived! Fresh deals at the market." % caravan_name)
	print("[CaravanManager] Arrived: %s (%d deals)" % [caravan_name, deals.size()])

func _depart() -> void:
	active = false
	deals.clear()
	emit_signal("caravan_departed")
	SignalBus.show_notification.emit("%s has moved on down the road." % caravan_name)

func _generate_deals() -> void:
	deals.clear()
	var count = 4 if _market_tier() >= 3 else 3
	# Always include one barter (quest 'market_first_caravan' needs one)
	deals.append(_make_barter_deal())
	for _i in range(count - 1):
		if randf() < 0.5:
			deals.append(_make_buy_deal())
		else:
			deals.append(_make_sell_deal())

# Caravan deals track the live market price so they follow demand like the market and port
func _market_value(res: String) -> float:
	return MarketManager.get_current_value(res)

func _make_buy_deal() -> Dictionary:
	var res: String = DEAL_RESOURCES[randi() % DEAL_RESOURCES.size()]
	var qty := randi_range(10, 25)
	var price := _market_value(res) * qty * 0.7  # 30% off market
	return {"kind": "buy", "get_res": res, "get_qty": qty,
		"give_res": "", "give_qty": 0, "gold": price, "taken": false}

func _make_sell_deal() -> Dictionary:
	var res: String = DEAL_RESOURCES[randi() % DEAL_RESOURCES.size()]
	var qty := randi_range(8, 18)
	var price := _market_value(res) * qty * randf_range(0.9, 1.1)  # premium over local sell rate
	return {"kind": "sell", "give_res": res, "give_qty": qty,
		"get_res": "", "get_qty": 0, "gold": price, "taken": false}

func _make_barter_deal() -> Dictionary:
	var give_res: String = DEAL_RESOURCES[randi() % DEAL_RESOURCES.size()]
	var get_res: String = DEAL_RESOURCES[randi() % DEAL_RESOURCES.size()]
	while get_res == give_res:
		get_res = DEAL_RESOURCES[randi() % DEAL_RESOURCES.size()]
	var give_qty := randi_range(10, 20)
	# Favorable swap: ~120% of value back
	var give_value := _market_value(give_res) * give_qty
	var get_qty := maxi(1, int(give_value * 1.2 / _market_value(get_res)))
	return {"kind": "barter", "give_res": give_res, "give_qty": give_qty,
		"get_res": get_res, "get_qty": get_qty, "gold": 0.0, "taken": false}

# Returns "" on success, else a human-readable blocker.
func accept_deal(index: int) -> String:
	if index < 0 or index >= deals.size():
		return "That deal is gone."
	var deal: Dictionary = deals[index]
	if deal["taken"]:
		return "Already traded."
	match deal["kind"]:
		"buy":
			if not EconomyManager.can_afford(deal["gold"]):
				return "Not enough gold."
			EconomyManager.spend_gold(deal["gold"], "Caravan: bought %d %s" % [deal["get_qty"], deal["get_res"]])
			ResourceManager.add(deal["get_res"], float(deal["get_qty"]), "Caravan purchase")
			emit_signal("caravan_trade", "caravan", deal["get_res"], deal["get_qty"])
		"sell":
			if not ResourceManager.can_afford(deal["give_res"], float(deal["give_qty"])):
				return "Not enough %s." % deal["give_res"].replace("_", " ")
			ResourceManager.spend(deal["give_res"], float(deal["give_qty"]), "Caravan sale")
			EconomyManager.add_gold(deal["gold"], "Caravan: sold %d %s" % [deal["give_qty"], deal["give_res"]])
			emit_signal("caravan_trade", "caravan", deal["give_res"], deal["give_qty"])
		"barter":
			if not ResourceManager.can_afford(deal["give_res"], float(deal["give_qty"])):
				return "Not enough %s." % deal["give_res"].replace("_", " ")
			ResourceManager.spend(deal["give_res"], float(deal["give_qty"]), "Caravan barter")
			ResourceManager.add(deal["get_res"], float(deal["get_qty"]), "Caravan barter")
			emit_signal("caravan_trade", "barter", deal["get_res"], deal["get_qty"])
	deal["taken"] = true
	ProgressionManager.reward_xp("trade_completed")
	ReputationManager.add_reputation(2.0, "Trading with %s" % caravan_name)
	emit_signal("deals_changed")
	return ""

# ── Save / Load / Reset ───────────────────────────────────────────────────────

func reset() -> void:
	active = false
	caravan_name = ""
	days_left = 0
	days_since_last = 99
	deals.clear()
	emit_signal("caravan_departed")

func to_dict() -> Dictionary:
	return {
		"active": active,
		"caravan_name": caravan_name,
		"days_left": days_left,
		"days_since_last": days_since_last,
		"deals": deals.duplicate(true),
	}

func from_dict(data: Dictionary) -> void:
	active = bool(data.get("active", false))
	caravan_name = str(data.get("caravan_name", ""))
	days_left = int(data.get("days_left", 0))
	days_since_last = int(data.get("days_since_last", 99))
	deals = data.get("deals", []).duplicate(true)
	if active:
		emit_signal("caravan_arrived", caravan_name, days_left)
	else:
		emit_signal("caravan_departed")
