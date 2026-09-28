extends Node

# Trade Port — barter resources for other resources at a rolled discount.
# 5 offers drawn from the market goods list (common goods appear more often),
# re-rolled every 15 real minutes while a trade port exists. The player
# RECEIVES the offered resource and PAYS with any other resource worth
# (1 - discount) x the received value — discounts roll 10-30% per offer.

const OFFER_COUNT: int = 5
const REROLL_SECONDS: float = 900.0
const DISCOUNT_MIN: float = 0.10
const DISCOUNT_MAX: float = 0.30

signal offers_rerolled()
signal offer_updated(index: int)

# Each offer: {"resource_id": String, "stock": int, "discount": float}
var offers: Array = []
var time_left: float = REROLL_SECONDS

func _ready() -> void:
	if offers.is_empty():
		roll_offers()

func _process(delta: float) -> void:
	# The clock only runs once the city actually has a trade port
	if not BuildingManager.has_building_type("trade_port"):
		return
	time_left -= delta
	if time_left <= 0.0:
		roll_offers()
		SignalBus.show_notification.emit("New offers at the Trade Port!")

# Live market value — floats with demand (buying anywhere raises it here too)
func unit_value(resource_id: String) -> float:
	return MarketManager.get_current_value(resource_id)

# Fixed hidden base — used for rarity (offer frequency + stock), never floats
func base_value(resource_id: String) -> float:
	return MarketManager.get_base_value(resource_id)

func roll_offers() -> void:
	time_left = REROLL_SECONDS
	offers.clear()
	var pool: Array = MarketManager.goods.keys()
	# Weight ∝ 1/base_value → common materials show up more often (rarity is fixed)
	var weights: Array = []
	var total := 0.0
	for id in pool:
		var w = 1.0 / base_value(id)
		weights.append(w)
		total += w
	for _i in range(OFFER_COUNT):
		if pool.is_empty():
			break
		var pick = randf() * total
		var idx := 0
		for j in range(pool.size()):
			pick -= weights[j]
			if pick <= 0.0:
				idx = j
				break
		offers.append({
			"resource_id": pool[idx],
			"stock": _roll_stock(pool[idx]),
			"discount": randf_range(DISCOUNT_MIN, DISCOUNT_MAX),
		})
		total -= weights[idx]
		pool.remove_at(idx)
		weights.remove_at(idx)
	emit_signal("offers_rerolled")
	print("[TradePortManager] Offers re-rolled (%d)." % offers.size())

# Cheap goods arrive by the wagon-load (wood ~500), rare ones by the crate (~5).
# Steep 1/base^1.5 curve so common/rare stocks span the full 5-1000 range (rarity is fixed).
func _roll_stock(resource_id: String) -> int:
	var hi = clampi(int(6000.0 / pow(base_value(resource_id), 1.5)), 5, 1000)
	var lo = maxi(5, int(hi * 0.6))
	return randi_range(lo, hi)

func get_offer_value(index: int, qty: int) -> float:
	var o: Dictionary = offers[index]
	return unit_value(o.resource_id) * qty

# What the trade actually costs the player (discount already applied)
func get_pay_value(index: int, qty: int) -> float:
	var o: Dictionary = offers[index]
	return get_offer_value(index, qty) * (1.0 - float(o.discount))

func get_pay_qty(index: int, qty: int, pay_resource: String) -> int:
	return int(ceil(get_pay_value(index, qty) / unit_value(pay_resource)))

# Returns "" on success, otherwise a blocker message for the UI
func execute_trade(index: int, qty: int, pay_resource: String) -> String:
	if index < 0 or index >= offers.size():
		return "That offer is gone."
	var o: Dictionary = offers[index]
	if qty <= 0 or qty > int(o.stock):
		return "Not enough stock."
	if pay_resource == o.resource_id:
		return "Pick a different resource to pay with."
	if not MarketManager.goods.has(pay_resource):
		return "The port won't take that."
	var pay_qty = get_pay_qty(index, qty, pay_resource)
	if ResourceManager.get_amount(pay_resource) < pay_qty:
		return "Not enough %s — need %d." % [ResourceManager.get_item_label(pay_resource), pay_qty]
	ResourceManager.spend(pay_resource, pay_qty, "Trade Port")
	ResourceManager.add(o.resource_id, qty, "Trade Port")
	o.stock = int(o.stock) - qty
	offers[index] = o
	emit_signal("offer_updated", index)
	MarketManager.trade_completed.emit("trade_port", str(o.resource_id), qty)
	print("[TradePortManager] Traded %d %s for %d %s" % [pay_qty, pay_resource, qty, o.resource_id])
	return ""

func reset() -> void:
	roll_offers()

func to_dict() -> Dictionary:
	return {"offers": offers.duplicate(true), "time_left": time_left}

func from_dict(data: Dictionary) -> void:
	offers = data.get("offers", []).duplicate(true)
	time_left = clampf(float(data.get("time_left", REROLL_SECONDS)), 1.0, REROLL_SECONDS)
	if offers.is_empty():
		roll_offers()
	else:
		emit_signal("offers_rerolled")
