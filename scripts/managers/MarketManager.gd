extends Node

# ── Free-flowing demand economy ──────────────────────────────────────────────
# Every good has a HIDDEN, fixed base value. A single net "demand" variable
# floats with the player's activity — buying pushes it up, selling pushes it
# down. Prices are clamped: never below MIN_PRICE (1g), never above
# PRICE_CAP_MULT× base.
#
# NOTE ON CADENCE: in practice prices reprice once per GAME DAY (60 real
# seconds), because _on_new_day calls reprice_all(). REPRICE_SECONDS is only a
# backstop for a paused/very slow clock and almost never fires first. That means
# DEMAND_DECAY compounds daily, so a price crashed by dumping stock recovers
# over roughly a game week rather than lingering.
const REPRICE_SECONDS: float = 1800.0   # backstop only; the daily tick beats it
const MIN_PRICE: float = 1.0            # no material trades below 1 gold
const PRICE_CAP_MULT: float = 10.0      # …or above 10x its hidden base value
const DEMAND_PER_UNIT: float = 0.01     # each unit traded moves demand (100 units ≈ 2x)
const DEMAND_MIN: float = -1.0          # demand floor (maps price toward 1g)
const DEMAND_MAX: float = 9.0           # demand ceiling (maps price toward 10x)
const DEMAND_DECAY: float = 0.85        # demand relaxes toward 0 each reprice (mean reversion)
const DEMAND_DRIFT: float = 0.04        # small random wander each reprice (never fully still)
const SELL_MARGIN: float = 0.7          # the house keeps 30%: sell price = 70% of market value

# resource_id → {base_value (fixed, hidden), demand (net, live), price (shown, 30-min cached)}
var goods: Dictionary = {
	"wood":             {"base_value": 5.0,   "demand": 0.0, "price": 5.0},
	"stone":            {"base_value": 8.0,   "demand": 0.0, "price": 8.0},
	"herbs":            {"base_value": 15.0,  "demand": 0.0, "price": 15.0},
	"fish":             {"base_value": 12.0,  "demand": 0.0, "price": 12.0},
	"grain":            {"base_value": 10.0,  "demand": 0.0, "price": 10.0},
	"vegetables":       {"base_value": 12.0,  "demand": 0.0, "price": 12.0},
	"enchanted_ore":    {"base_value": 50.0,  "demand": 0.0, "price": 50.0},
	"rare_ingredients": {"base_value": 100.0, "demand": 0.0, "price": 100.0},
	# Cooking ingredients — specialty goods ordered through the market (GDD supply chain)
	"water":            {"base_value": 2.0,   "demand": 0.0, "price": 2.0},
	"mushroom":         {"base_value": 8.0,   "demand": 0.0, "price": 8.0},
	"wild_honey":       {"base_value": 20.0,  "demand": 0.0, "price": 20.0},
	"boar_meat":        {"base_value": 25.0,  "demand": 0.0, "price": 25.0},
	"basic_fruit":      {"base_value": 9.0,   "demand": 0.0, "price": 9.0},
	"premium_fruit":    {"base_value": 45.0,  "demand": 0.0, "price": 45.0},
	"rare_herbs":       {"base_value": 35.0,  "demand": 0.0, "price": 35.0},
	# Fresh catches — sellable at market; legendary fish stays off the books
	"river_fish":       {"base_value": 14.0,  "demand": 0.0, "price": 14.0},
	"lake_trout":       {"base_value": 30.0,  "demand": 0.0, "price": 30.0},
}

var _reprice_timer: float = 0.0

# ── Orders & delivery (GDD supply chain) ─────────────────────────────────────
# "Meats and specialty ingredients are ordered from the market with a delivery
# delay. Bulk discounts available at Market Tier 3." Staples (anything worth
# less than ORDER_MIN_VALUE) come straight off the stall; specialty goods are
# paid for now and delivered later. A better market delivers faster.
const ORDER_MIN_VALUE: float = 20.0
const DELIVERY_DAYS_BY_TIER: Dictionary = {1: 1.0, 2: 0.5, 3: 0.25}
const BULK_TIERS: Array = [[50, 0.20], [25, 0.10]]   # [min qty, discount], largest first
var orders: Array = []   # {"resource_id", "qty", "seconds_left"}

signal orders_changed()
signal prices_updated()
signal trade_completed(kind: String, resource_id: String, quantity: int)

func _ready() -> void:
	TimeManager.new_day.connect(_on_new_day)

func _process(delta: float) -> void:
	if not orders.is_empty():
		advance_orders(delta)
	_reprice_timer += delta
	if _reprice_timer >= REPRICE_SECONDS:
		_reprice_timer -= REPRICE_SECONDS
		reprice_all()

# ── Price queries ──────────────────────────────────────────────────────────────

# The fixed, hidden base value — used for barter/caravan rarity, never shown raw.
func get_base_value(resource_id: String) -> float:
	return float(goods.get(resource_id, {}).get("base_value", 10.0))

# The current market value of one unit (already clamped [1g, 10x base]).
func get_current_value(resource_id: String) -> float:
	var g: Dictionary = goods.get(resource_id, {})
	if g.is_empty():
		return 0.0
	return g["price"]

func get_unit_buy_price(resource_id: String) -> float:
	return get_current_value(resource_id)

func get_unit_sell_price(resource_id: String) -> float:
	var g: Dictionary = goods.get(resource_id, {})
	if g.is_empty():
		return 0.0
	return maxf(MIN_PRICE, g["price"] * SELL_MARGIN * RecipeManager.get_market_sell_multiplier())

func get_buy_price(resource_id: String, quantity: int) -> float:
	return get_unit_buy_price(resource_id) * quantity * (1.0 - get_bulk_discount(quantity))

# ── Orders ───────────────────────────────────────────────────────────────────

func _market_tier() -> int:
	return RecipeManager.get_best_tier("market")

func is_ordered_good(resource_id: String) -> bool:
	return get_base_value(resource_id) >= ORDER_MIN_VALUE

func get_delivery_seconds() -> float:
	var days = float(DELIVERY_DAYS_BY_TIER.get(clampi(_market_tier(), 1, 3), 1.0))
	return TimeManager.DAY_LENGTH_SECONDS * days

func get_bulk_discount(quantity: int) -> float:
	if _market_tier() < 3:
		return 0.0
	for t in BULK_TIERS:
		if quantity >= int(t[0]):
			return float(t[1])
	return 0.0

# Counts down every order and delivers the ones that are due. Also called with
# the whole offline window when the player returns, so deliveries land while away.
func advance_orders(seconds: float) -> void:
	var arrived: Array = []
	for o in orders:
		o.seconds_left = float(o.seconds_left) - seconds
		if float(o.seconds_left) <= 0.0:
			arrived.append(o)
	for o in arrived:
		orders.erase(o)
		ResourceManager.add(o.resource_id, float(o.qty), "Market delivery")
		SignalBus.show_notification.emit("Delivery arrived: %d %s" % [
			int(o.qty), ResourceManager.get_item_label(o.resource_id)])
	if not arrived.is_empty():
		emit_signal("orders_changed")

func get_sell_price(resource_id: String, quantity: int) -> float:
	return get_unit_sell_price(resource_id) * quantity

# Nudge a good's demand and clamp it. Buying = positive, selling = negative.
# The shown price does NOT move until the next reprice (see cadence note above).
func adjust_demand(resource_id: String, amount: float) -> void:
	if not goods.has(resource_id):
		return
	goods[resource_id]["demand"] = clampf(
		goods[resource_id]["demand"] + amount, DEMAND_MIN, DEMAND_MAX
	)

# Recompute every good's shown price from its accumulated demand, then relax
# demand toward zero with a little random wander so the market never sits still.
func reprice_all() -> void:
	for res_id in goods:
		var g: Dictionary = goods[res_id]
		var base: float = g["base_value"]
		g["price"] = clampf(base * (1.0 + g["demand"]), MIN_PRICE, base * PRICE_CAP_MULT)
		g["demand"] = clampf(
			g["demand"] * DEMAND_DECAY + randf_range(-DEMAND_DRIFT, DEMAND_DRIFT),
			DEMAND_MIN, DEMAND_MAX
		)
	emit_signal("prices_updated")
	print("[MarketManager] Prices re-rolled from demand.")

# ── Transactions ───────────────────────────────────────────────────────────────

func buy(resource_id: String, quantity: int) -> bool:
	if quantity <= 0 or not goods.has(resource_id):
		return false
	var total_cost: float = get_buy_price(resource_id, quantity)
	if not EconomyManager.can_afford(total_cost):
		SignalBus.show_notification.emit("Not enough gold!")
		return false
	EconomyManager.spend_gold(total_cost, "Market: bought %d %s" % [quantity, resource_id])
	if is_ordered_good(resource_id):
		var secs := get_delivery_seconds()
		orders.append({"resource_id": resource_id, "qty": quantity, "seconds_left": secs})
		emit_signal("orders_changed")
		SignalBus.show_notification.emit("Ordered %d %s for %.0f gold — arriving in ~%s." % [
			quantity, ResourceManager.get_item_label(resource_id), total_cost, eta_text(secs)])
	else:
		ResourceManager.add(resource_id, quantity, "Market purchase")
	adjust_demand(resource_id, DEMAND_PER_UNIT * quantity)
	ProgressionManager.reward_xp("trade_completed")
	emit_signal("prices_updated")
	emit_signal("trade_completed", "buy", resource_id, quantity)
	if not is_ordered_good(resource_id):
		SignalBus.show_notification.emit("Bought %d %s for %.0f gold" % [quantity, _display(resource_id), total_cost])
	return true

func sell(resource_id: String, quantity: int) -> bool:
	if quantity <= 0 or not goods.has(resource_id):
		return false
	if not ResourceManager.can_afford(resource_id, float(quantity)):
		SignalBus.show_notification.emit("Not enough %s!" % _display(resource_id))
		return false
	var total_gold: float = get_sell_price(resource_id, quantity)
	ResourceManager.spend(resource_id, float(quantity), "Market sale")
	EconomyManager.add_gold(total_gold, "Market: sold %d %s" % [quantity, resource_id])
	adjust_demand(resource_id, -DEMAND_PER_UNIT * quantity)
	ProgressionManager.reward_xp("trade_completed")
	emit_signal("prices_updated")
	emit_signal("trade_completed", "sell", resource_id, quantity)
	SignalBus.show_notification.emit("Sold %d %s for %.0f gold" % [quantity, _display(resource_id), total_gold])
	return true

# How pricey groceries are right now: average buy-price inflation of staple
# foods relative to their hidden base (1.0 = calm market, up to 10x when demand peaks).
func get_food_price_multiplier() -> float:
	var total := 0.0
	var count := 0
	for res_id in ["grain", "vegetables"]:
		var g: Dictionary = goods.get(res_id, {})
		if g.is_empty():
			continue
		total += get_unit_buy_price(res_id) / float(g["base_value"])
		count += 1
	return total / count if count > 0 else 1.0

# ── Daily nudge ────────────────────────────────────────────────────────────────
# A new day counts as one reprice cycle (in case the 30-min timer hasn't fired).
func _on_new_day(_day: int, _season: String, _year: int) -> void:
	reprice_all()

# ── Save / Load / Reset ────────────────────────────────────────────────────────

# Back to untouched prices: every good sits at its hidden base value with no
# accumulated demand. A new city inherits none of the last one's market pressure.
func reset() -> void:
	_reprice_timer = 0.0
	orders.clear()
	emit_signal("orders_changed")
	for res_id in goods:
		goods[res_id]["demand"] = 0.0
		goods[res_id]["price"] = goods[res_id]["base_value"]
	emit_signal("prices_updated")

func to_dict() -> Dictionary:
	var result: Dictionary = {"_timer": _reprice_timer, "_orders": orders.duplicate(true)}
	for res_id in goods:
		result[res_id] = {
			"demand": goods[res_id]["demand"],
			"price": goods[res_id]["price"],
		}
	return result

func from_dict(data: Dictionary) -> void:
	reset()  # goods added since this save was written must not keep the old slot's prices
	_reprice_timer = float(data.get("_timer", 0.0))
	for o in data.get("_orders", []):
		if o is Dictionary and goods.has(str(o.get("resource_id", ""))):
			orders.append({"resource_id": str(o.resource_id), "qty": int(o.get("qty", 0)),
				"seconds_left": float(o.get("seconds_left", 0.0))})
	emit_signal("orders_changed")
	for res_id in data:
		if goods.has(res_id) and data[res_id] is Dictionary:
			var g: Dictionary = data[res_id]
			goods[res_id]["demand"] = clampf(float(g.get("demand", 0.0)), DEMAND_MIN, DEMAND_MAX)
			# Restore the shown price; older saves (no "price") re-derive from demand
			if g.has("price"):
				goods[res_id]["price"] = float(g["price"])
			else:
				var base: float = goods[res_id]["base_value"]
				goods[res_id]["price"] = clampf(base * (1.0 + goods[res_id]["demand"]), MIN_PRICE, base * PRICE_CAP_MULT)
	emit_signal("prices_updated")

# ── Helpers ────────────────────────────────────────────────────────────────────

func eta_text(seconds: float) -> String:
	var days := seconds / TimeManager.DAY_LENGTH_SECONDS
	if days >= 0.95:
		return "%d day%s" % [roundi(days), "" if roundi(days) == 1 else "s"]
	return "%d hours" % maxi(1, roundi(days * 24.0))   # in-game hours

func _display(resource_id: String) -> String:
	return resource_id.replace("_", " ")
