extends Node

# Supply/demand tuning — balance these during playtesting
const DEMAND_FACTOR: float = 2.0        # buying drives buy price up by up to 2x base
const SUPPLY_FACTOR: float = 0.8        # selling drives sell price down by up to 80%
const PRESSURE_PER_UNIT: float = 0.005  # pressure gained per unit traded (200 units = max)
const DAILY_DECAY: float = 0.85         # pressure retained per day (resets toward baseline)
const MIN_SELL_RATIO: float = 0.1       # sell price floor: 10% of base sell price

# resource_id → base prices and current market pressure [0..1]
var goods: Dictionary = {
	"wood":             {"base_buy": 5.0,   "base_sell": 3.0,   "demand": 0.0, "supply": 0.0},
	"stone":            {"base_buy": 8.0,   "base_sell": 5.0,   "demand": 0.0, "supply": 0.0},
	"herbs":            {"base_buy": 15.0,  "base_sell": 10.0,  "demand": 0.0, "supply": 0.0},
	"fish":             {"base_buy": 12.0,  "base_sell": 8.0,   "demand": 0.0, "supply": 0.0},
	"grain":            {"base_buy": 10.0,  "base_sell": 6.0,   "demand": 0.0, "supply": 0.0},
	"vegetables":       {"base_buy": 12.0,  "base_sell": 8.0,   "demand": 0.0, "supply": 0.0},
	"enchanted_ore":    {"base_buy": 50.0,  "base_sell": 35.0,  "demand": 0.0, "supply": 0.0},
	"rare_ingredients": {"base_buy": 100.0, "base_sell": 70.0,  "demand": 0.0, "supply": 0.0},
	# Cooking ingredients — specialty goods ordered through the market (GDD supply chain)
	"water":            {"base_buy": 2.0,   "base_sell": 1.0,   "demand": 0.0, "supply": 0.0},
	"mushroom":         {"base_buy": 8.0,   "base_sell": 5.0,   "demand": 0.0, "supply": 0.0},
	"wild_honey":       {"base_buy": 20.0,  "base_sell": 14.0,  "demand": 0.0, "supply": 0.0},
	"boar_meat":        {"base_buy": 25.0,  "base_sell": 18.0,  "demand": 0.0, "supply": 0.0},
	"basic_fruit":      {"base_buy": 9.0,   "base_sell": 6.0,   "demand": 0.0, "supply": 0.0},
	"premium_fruit":    {"base_buy": 45.0,  "base_sell": 32.0,  "demand": 0.0, "supply": 0.0},
	"rare_herbs":       {"base_buy": 35.0,  "base_sell": 25.0,  "demand": 0.0, "supply": 0.0},
}

signal prices_updated()
signal trade_completed(kind: String, resource_id: String, quantity: int)

func _ready() -> void:
	TimeManager.new_day.connect(_on_new_day)

# ── Price queries ──────────────────────────────────────────────────────────────

func get_unit_buy_price(resource_id: String) -> float:
	var g: Dictionary = goods.get(resource_id, {})
	if g.is_empty():
		return 0.0
	return g["base_buy"] * (1.0 + g["demand"] * DEMAND_FACTOR)

func get_unit_sell_price(resource_id: String) -> float:
	var g: Dictionary = goods.get(resource_id, {})
	if g.is_empty():
		return 0.0
	return g["base_sell"] * maxf(MIN_SELL_RATIO, 1.0 - g["supply"] * SUPPLY_FACTOR)

func get_buy_price(resource_id: String, quantity: int) -> float:
	return get_unit_buy_price(resource_id) * quantity

func get_sell_price(resource_id: String, quantity: int) -> float:
	return get_unit_sell_price(resource_id) * quantity

# ── Transactions ───────────────────────────────────────────────────────────────

func buy(resource_id: String, quantity: int) -> bool:
	if quantity <= 0 or not goods.has(resource_id):
		return false
	var total_cost: float = get_buy_price(resource_id, quantity)
	if not EconomyManager.can_afford(total_cost):
		SignalBus.show_notification.emit("Not enough gold!")
		return false
	EconomyManager.spend_gold(total_cost, "Market: bought %d %s" % [quantity, resource_id])
	ResourceManager.add(resource_id, quantity, "Market purchase")
	goods[resource_id]["demand"] = minf(1.0, goods[resource_id]["demand"] + PRESSURE_PER_UNIT * quantity)
	ProgressionManager.reward_xp("trade_completed")
	emit_signal("prices_updated")
	emit_signal("trade_completed", "buy", resource_id, quantity)
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
	goods[resource_id]["supply"] = minf(1.0, goods[resource_id]["supply"] + PRESSURE_PER_UNIT * quantity)
	ProgressionManager.reward_xp("trade_completed")
	emit_signal("prices_updated")
	emit_signal("trade_completed", "sell", resource_id, quantity)
	SignalBus.show_notification.emit("Sold %d %s for %.0f gold" % [quantity, _display(resource_id), total_gold])
	return true

# ── Daily decay ────────────────────────────────────────────────────────────────

func _on_new_day(_day: int, _season: String, _year: int) -> void:
	for res_id in goods:
		goods[res_id]["demand"] *= DAILY_DECAY
		goods[res_id]["supply"] *= DAILY_DECAY
	emit_signal("prices_updated")

# ── Save / Load ────────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	var result: Dictionary = {}
	for res_id in goods:
		result[res_id] = {
			"demand": goods[res_id]["demand"],
			"supply": goods[res_id]["supply"],
		}
	return result

func from_dict(data: Dictionary) -> void:
	for res_id in data:
		if goods.has(res_id):
			goods[res_id]["demand"] = float(data[res_id].get("demand", 0.0))
			goods[res_id]["supply"] = float(data[res_id].get("supply", 0.0))
	emit_signal("prices_updated")

# ── Helpers ────────────────────────────────────────────────────────────────────

func _display(resource_id: String) -> String:
	return resource_id.replace("_", " ")
