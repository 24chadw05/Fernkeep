extends Node

var citizens: Array = []
var pending_arrivals: Array = []  # NPCs waiting at the gates, oldest first

# Monotonic id counter, re-seeded above every id in the save on load. Millisecond
# timestamps aren't safe here: the engine clock restarts at 0 every launch, so a
# reloaded save's ids sit in exactly the range the new session hands out again.
var _next_npc_id: int = 0

const MAX_PENDING_ARRIVALS: int = 6

var arrival_timer: float = 0.0
var arrival_interval: float = 45.0

# Demand score (0-100): drives arrival quality independent of player level.
# Updated daily by GameManager.
var demand_score: float = 0.0

# Rent/tax affordability: a citizen is never charged more than this share of
# their income (daily wage when employed, wealth-level fair wage otherwise).
const RENT_INCOME_CAP: float = 0.35

# Personal economy
const KID_COST: float = 100.0          # per kid per day (tune later)
const KID_CHANCE: float = 0.05         # chance an arriving adult has children
const FOOD_BASE: float = 1.5           # base grocery cost/day (+0.35 per wealth level)
const FOOD_PER_WEALTH: float = 0.35
const NO_MARKET_FOOD_MULT: float = 1.5 # imported food costs more without a market
const SAVINGS_NEST_EGG_DAYS: float = 20.0  # arrival savings = fair wage × this

# Wages are a share of what the workplace earns, split across its staff slots,
# on top of a floor set by the citizen's wealth. Tying pay to revenue rather
# than to a level number means upgrading a building raises its wage bill in
# step with its income — labour stays a real cost (roughly 25-45% of revenue)
# at every tier instead of dwindling to a rounding error at the top.
const WAGE_REVENUE_SHARE: float = 0.40
# A new hire starts at 80% of fair; the same fraction sets the floor a worker is
# lifted to when their workplace is upgraded.
const HIRE_WAGE_FRACTION: float = 0.8

# City amenity score (0-15), refreshed daily — building variety, decor,
# road network, and a lively population all make everyone a bit happier.
var amenity_score: float = 0.0

signal citizen_arrived(npc: NPC)
signal citizen_assigned(npc: NPC, building_id: String)
signal arrival_queue_changed()
signal city_happiness_updated(happiness: float)
signal housing_updated()

func _ready() -> void:
	BuildingManager.building_upgraded.connect(rebaseline_wages)

# Upgrading a workplace raises what it earns, so it raises what the job there is
# worth. Everyone on staff is lifted to the new starting wage — never cut — so
# the wage bill grows with the building instead of the player having to walk the
# roster hitting Raise after every upgrade.
func rebaseline_wages(building: PlacedBuilding) -> void:
	if building.building_id == "guild_hall":
		return  # the Taskmaster works for a cut of each deal, not a wage
	var raised := 0
	for npc_id in building.assigned_staff:
		var npc = get_citizen_by_id(npc_id)
		if npc == null:
			continue
		var fair = get_fair_wage(npc)
		var target = fair * HIRE_WAGE_FRACTION
		if target > npc.daily_wage:
			npc.daily_wage = target
			raised += 1
		# Move the raise cap up with the new baseline, or a long-serving worker
		# would be stuck at 2.5x a wage set when the building was a shack.
		npc.base_daily_wage = maxf(npc.base_daily_wage, npc.daily_wage)
		npc.recalculate_pay_happiness(fair)
		update_daily_payment(npc)
	if raised > 0:
		SignalBus.show_notification.emit(
			"%s pays better now — %d worker(s) moved up to the new rate." % [
				building.get_display_name(), raised
			]
		)

func _process(delta: float) -> void:
	# Charm potions make word of the city travel faster
	arrival_timer += delta * RecipeManager.get_arrival_rate_multiplier()
	if arrival_timer >= arrival_interval and pending_arrivals.size() < MAX_PENDING_ARRIVALS:
		arrival_timer = 0.0
		_try_spawn_arrival()

# Put someone at the gates right now (the tutorial uses this rather than
# making a new player wait out the arrival timer).
func spawn_arrival_now() -> void:
	if pending_arrivals.size() < MAX_PENDING_ARRIVALS:
		arrival_timer = 0.0
		_try_spawn_arrival()

func _try_spawn_arrival() -> void:
	var npc = _generate_random_npc()
	pending_arrivals.append(npc)
	emit_signal("arrival_queue_changed")
	SignalBus.show_notification.emit("%s is waiting at the gates" % npc.get_full_name())
	print("[CitizenManager] New arrival waiting: %s (%d in queue)" % [npc.get_full_name(), pending_arrivals.size()])

func accept_arrival(npc: NPC) -> void:
	# Auto-assign to the first available house
	var house = _get_first_available_house()
	if house:
		house.add_resident(npc.id)
		npc.house_building_id = house.id
	# (If no house, NPC is homeless — arrival still allowed, happiness penalised)

	citizens.append(npc)
	pending_arrivals.erase(npc)
	emit_signal("arrival_queue_changed")
	emit_signal("citizen_arrived", npc)
	emit_signal("housing_updated")
	ProgressionManager.reward_xp("npc_arrived")
	EconomyManager.add_gold(npc.daily_payment, "Arrival deposit from " + npc.get_full_name())
	print("[CitizenManager] Accepted: %s (house: %s)" % [npc.get_full_name(), npc.house_building_id])

func decline_arrival(npc: NPC) -> void:
	pending_arrivals.erase(npc)
	emit_signal("arrival_queue_changed")
	print("[CitizenManager] Declined: %s" % npc.get_full_name())

func get_pending_count() -> int:
	return pending_arrivals.size()

func assign_to_building(npc_id: String, building_instance_id: String) -> bool:
	var npc = get_citizen_by_id(npc_id)
	var building = BuildingManager.get_building_by_id(building_instance_id)
	if not npc or not building:
		return false
	if npc.is_employed and npc.job_building_id != building_instance_id:
		unassign_from_building(npc_id)
	if not building.can_add_staff():
		print("[CitizenManager] No staff slots available in %s" % building.building_id)
		return false

	building.add_staff(npc_id)
	npc.assigned_job = building.building_id
	npc.job_building_id = building_instance_id
	npc.is_employed = true
	npc.job_fit_bonus = _calculate_job_fit(npc, building)
	var fair_wage = get_fair_wage(npc)
	if building.building_id == "guild_hall":
		# The Taskmaster draws no treasury wage — they live off their cut of
		# each deal (credited to savings on claim). Keep them content regardless.
		npc.daily_wage = 0.0
		npc.base_daily_wage = 0.0
		npc.pay_happiness = 10.0
	else:
		# Starting wage is 80% of fair for this workplace; moving to a higher-level
		# job re-baselines pay upward (never cuts an existing wage)
		npc.daily_wage = maxf(npc.daily_wage, fair_wage * HIRE_WAGE_FRACTION)
		npc.base_daily_wage = npc.daily_wage
		npc.recalculate_pay_happiness(fair_wage)
	update_daily_payment(npc)

	emit_signal("citizen_assigned", npc, building_instance_id)
	print("[CitizenManager] Assigned %s to %s (fit bonus: %.1f)" % [
		npc.get_full_name(), building.building_id, npc.job_fit_bonus
	])
	return true

func unassign_from_building(npc_id: String) -> void:
	var npc = get_citizen_by_id(npc_id)
	if not npc or not npc.is_employed:
		return
	var building = BuildingManager.get_building_by_id(npc.job_building_id)
	if building:
		building.remove_staff(npc_id)
	npc.assigned_job = ""
	npc.job_building_id = ""
	npc.is_employed = false
	npc.job_fit_bonus = 0.0
	npc.calculate_happiness()
	update_daily_payment(npc)

func _calculate_job_fit(npc: NPC, building: PlacedBuilding) -> float:
	var positions = building.get_positions()
	var best_fit = 0.0
	for pos in positions:
		var good_list: Array = pos.get("good_skills", [])
		var bad_list: Array = pos.get("bad_skills", [])
		if npc.good_skill in good_list:
			var skill_data = DataManager.get_citizen_skill(npc.good_skill)
			best_fit = max(best_fit, float(skill_data.get("happiness_bonus", 20.0)))
		elif npc.good_skill in bad_list:
			best_fit = min(best_fit, -15.0)
	return best_fit

# Fair daily wage: a floor set by the citizen's wealth, plus their share of what
# the workplace takes in. Income here is the building's base (pre-productivity)
# gold per game-day, so the wage is what the job is worth, not what today's
# staffing happened to earn.
func get_fair_wage(npc: NPC) -> float:
	if not npc.is_employed:
		return get_fair_wage_at(npc, null)
	return get_fair_wage_at(npc, BuildingManager.get_building_by_id(npc.job_building_id))

# What this citizen's work would be worth at a given building (null = unemployed).
# The single home of the wage formula — hiring, upgrades and the reassign
# panel's "pays ~Xg/day" projection all go through here.
func get_fair_wage_at(npc: NPC, building: PlacedBuilding) -> float:
	var wd = DataManager.get_wealth_level(npc.wealth_level)
	var base = float(wd.get("base_rent", 5.0))
	if building == null:
		return base
	var slots = building.get_staff_slots()
	if slots <= 0:
		return base
	return base + WAGE_REVENUE_SHARE * building.get_income_per_minute() / float(slots)

# Recompute what a citizen is actually charged: their wealth-based offer,
# capped at RENT_INCOME_CAP of their income. Raises let rent recover
# toward the full offer.
func update_daily_payment(npc: NPC) -> void:
	var income = npc.daily_wage if npc.is_employed else get_fair_wage(npc)
	npc.daily_payment = minf(npc.base_daily_payment, income * RENT_INCOME_CAP)

# Daily grocery bill — richer citizens eat fancier; market demand pressure
# raises prices; no market in town means pricier imported food.
func get_daily_food_cost(npc: NPC) -> float:
	var cost = (FOOD_BASE + FOOD_PER_WEALTH * npc.wealth_level) * MarketManager.get_food_price_multiplier()
	if not BuildingManager.has_building_type("market"):
		cost *= NO_MARKET_FOOD_MULT
	# Bad skills can inflate the grocery bill (picky_eater: ×1.2)
	var bad = DataManager.get_bad_skill(npc.bad_skill)
	cost *= float(bad.get("effects", {}).get("food_cost_multiplier", 1.0))
	return cost

# The daily money pass for one citizen. Wages come in, then living costs go
# out in priority order: rent/tax → food → kids → hobby. A citizen dips into
# savings to keep paying — a cost is only SKIPPED once savings run dry (<= 0).
# Because rent is paid first, the shortfalls (skips) fall on hobby → kids →
# food → rent, so rent is the last thing to lapse. last_ledger + happiness set.
func _run_daily_ledger(c: NPC, market_exists: bool) -> void:
	var ledger := {"income": 0.0, "rent": 0.0, "tax": 0.0, "food": 0.0,
		"kids": 0.0, "hobby": 0.0, "skipped": []}

	# Income — the citizen is only paid if the treasury can actually cover it
	if c.is_employed and c.daily_wage > 0.0:
		if EconomyManager.pay_wage(c.daily_wage, c.get_full_name()):
			c.savings += c.daily_wage
			ledger.income = c.daily_wage

	update_daily_payment(c)

	# 1) Rent / tax — paid from savings; only skipped when savings are gone
	if c.house_building_id != "" and c.daily_payment > 0.0:
		if c.savings > 0.0:
			c.savings -= c.daily_payment
			if c.housing_type == "renter":
				EconomyManager.collect_rent(c.daily_payment, c.get_full_name())
				ledger.rent = c.daily_payment
			else:
				EconomyManager.collect_tax(c.daily_payment, c.get_full_name())
				ledger.tax = c.daily_payment
		else:
			ledger.skipped.append("rent")

	# 2) Food — spent at your market when one exists (imported otherwise)
	var food_cost = get_daily_food_cost(c)
	if c.savings > 0.0:
		c.savings -= food_cost
		ledger.food = food_cost
		if market_exists:
			EconomyManager.add_gold(food_cost, "Groceries: " + c.get_full_name())
	else:
		ledger.skipped.append("food")

	# 3) Kids
	if c.kids > 0:
		var kid_cost = KID_COST * c.kids
		if c.savings > 0.0:
			c.savings -= kid_cost
			ledger.kids = kid_cost
		else:
			ledger.skipped.append("kids")

	# 4) Hobby
	var hobby_funded := false
	var hobby_data = DataManager.get_hobby(c.hobby)
	if not hobby_data.is_empty():
		var hobby_cost = float(hobby_data.get("daily_cost", 0.0))
		if c.savings > 0.0:
			c.savings -= hobby_cost
			ledger.hobby = hobby_cost
			hobby_funded = true
		else:
			ledger.skipped.append("hobby")
		# Workaholics need a job to enjoy "working"
		if hobby_data.get("requires_job", false) and not c.is_employed:
			hobby_funded = false

	# ── Happiness components from today's life ──
	c.amenity_bonus = amenity_score
	c.housing_bonus = 0.0
	if c.house_building_id != "":
		var house = BuildingManager.get_building_by_id(c.house_building_id)
		if house:
			c.housing_bonus = minf((house.get_global_level() - 1) * 1.0, 8.0)

	# Comfort: a savings buffer (10 days of expenses = fully secure) + hobby joy
	var daily_needs = maxf(c.daily_payment + food_cost + KID_COST * c.kids, 1.0)
	c.comfort_bonus = clampf(c.savings / (daily_needs * 10.0), 0.0, 1.0) * 8.0
	if hobby_funded:
		c.comfort_bonus += float(hobby_data.get("happiness_bonus", 0.0))

	c.needs_penalty = 0.0
	for skipped in ledger.skipped:
		match skipped:
			"rent":  c.needs_penalty += 10.0
			"food":  c.needs_penalty += 18.0
			"kids":  c.needs_penalty += 15.0
			"hobby": c.needs_penalty += 6.0
	if "rent" in ledger.skipped:
		SignalBus.show_notification.emit("%s couldn't afford rent!" % c.get_full_name())

	c.last_ledger = ledger
	c.calculate_happiness()

func calculate_amenity_score() -> float:
	var types := {}
	var decor_count := 0
	for b in BuildingManager.placed_buildings:
		if b.get_data().get("category", "") == "decor":
			decor_count += 1
		else:
			types[b.building_id] = true
	var variety = minf(types.size() * 1.0, 8.0)
	var decor = minf(decor_count * 0.5, 4.0)
	var roads = minf(RoadManager.road_cells.size() / 40.0, 2.0)
	var pop = minf(citizens.size() * 0.1, 1.0)
	return variety + decor + roads + pop  # 0-15

func calculate_city_happiness() -> float:
	if citizens.is_empty():
		return 100.0
	var total = 0.0
	for c in citizens:
		c.calculate_happiness()
		total += c.happiness
	var avg = total / float(citizens.size())
	# Meals, potions, and permanent blessings lift the whole city
	avg = clampf(avg + RecipeManager.get_city_happiness_bonus() + TimeManager.get_happiness_bonus(), 0.0, 100.0)
	emit_signal("city_happiness_updated", avg)
	return avg

func on_new_day() -> void:
	var housing_full = (get_available_housing_count() == 0 and citizens.size() > 0)
	amenity_score = calculate_amenity_score()
	var market_exists = BuildingManager.has_building_type("market")

	for c in citizens:
		c.days_in_town += 1
		c.treat_days = maxi(c.treat_days - 1, 0)
		_run_daily_ledger(c, market_exists)
		# Keep pay_happiness current after any wage pressure changes
		if c.is_employed:
			c.recalculate_pay_happiness(get_fair_wage(c))

	# Demand raises when housing is full (capped at +15% above base)
	if housing_full:
		var raised_count = 0
		for c in citizens:
			if c.is_employed and c.base_daily_wage > 0.0:
				var cap = c.base_daily_wage * 1.15
				if c.daily_wage < cap:
					c.daily_wage = min(c.daily_wage * 1.05, cap)
					raised_count += 1
		if raised_count > 0:
			SignalBus.show_notification.emit("No open housing! %d workers demanded a raise." % raised_count)
			print("[CitizenManager] Housing full — wages raised for %d citizens." % raised_count)

	calculate_city_happiness()

func assign_housing(npc_id: String, house_building_id: String) -> bool:
	var npc = get_citizen_by_id(npc_id)
	var house = BuildingManager.get_building_by_id(house_building_id)
	if not npc or not house or house.building_id != "house":
		return false
	if not house.can_add_resident():
		return false
	# Unassign old house if any
	if npc.house_building_id != "":
		var old_house = BuildingManager.get_building_by_id(npc.house_building_id)
		if old_house:
			old_house.remove_resident(npc_id)
	house.add_resident(npc_id)
	npc.house_building_id = house_building_id
	npc.calculate_happiness()
	emit_signal("housing_updated")
	return true

func unassign_housing(npc_id: String) -> void:
	var npc = get_citizen_by_id(npc_id)
	if not npc or npc.house_building_id == "":
		return
	var house = BuildingManager.get_building_by_id(npc.house_building_id)
	if house:
		house.remove_resident(npc_id)
	npc.house_building_id = ""
	npc.calculate_happiness()
	emit_signal("housing_updated")

func get_available_housing_count() -> int:
	var total_cap = 0
	var occupied = 0
	for b in BuildingManager.placed_buildings:
		if b.building_id == "house":
			total_cap += b.get_housing_capacity()
			occupied += b.assigned_residents.size()
	return max(0, total_cap - occupied)

func _get_first_available_house() -> PlacedBuilding:
	for b in BuildingManager.placed_buildings:
		if b.building_id == "house" and b.can_add_resident():
			return b
	return null

func get_citizen_by_id(npc_id: String) -> NPC:
	for c in citizens:
		if c.id == npc_id:
			return c
	return null

func get_unassigned_citizens() -> Array:
	return citizens.filter(func(c): return not c.is_employed)

func get_citizen_count() -> int:
	return citizens.size()

# --- NPC generation ---

func _generate_random_npc() -> NPC:
	var npc = NPC.new()
	var player_level = ProgressionManager.player_level
	var weights = DataManager.get_arrival_weights(player_level)

	# Name
	var pools = DataManager.get_name_pools()
	var gender = randi() % 3
	var first_pool: Array = []
	match gender:
		0: first_pool = pools.get("first_names_male", [])
		1: first_pool = pools.get("first_names_female", [])
		_: first_pool = pools.get("first_names_neutral", [])
	var last_pool: Array = pools.get("last_names", [])

	npc.id = "npc_%d" % _next_npc_id
	_next_npc_id += 1
	npc.first_name = first_pool[randi() % first_pool.size()] if first_pool.size() > 0 else "Unknown"
	npc.last_name = last_pool[randi() % last_pool.size()] if last_pool.size() > 0 else "Citizen"
	npc.age = _pick_age()

	# Wealth — demand score biases the distribution toward higher wealth tiers
	var dist: Array = weights.get("wealth_distribution", [20, 30, 25, 15, 7, 2, 1, 0, 0, 0])
	var raw_level = _weighted_pick(dist) + 1
	# At demand 100 → up to +3 wealth levels; at 0 → no boost
	var demand_bias = int((demand_score / 100.0) * 3.0)
	# Active charm potions sweeten the roll further
	var potion_bias = RecipeManager.get_arrival_quality_bonus()
	npc.wealth_level = clamp(raw_level + demand_bias + potion_bias, 1, 10)

	# Skills
	var special_chance: float = float(weights.get("special_skill_chance", 0.03))
	# Demand also raises special skill chance (up to +5% at max demand)
	special_chance += (demand_score / 100.0) * 0.05
	var job_skill_ids = DataManager.get_all_job_skill_ids()
	var special_skill_ids = DataManager.get_all_special_skill_ids()
	var bad_skill_ids = DataManager.get_all_bad_skill_ids()

	if randf() < special_chance and special_skill_ids.size() > 0:
		npc.good_skill = special_skill_ids[randi() % special_skill_ids.size()]
		npc.is_special_skill = true
	elif job_skill_ids.size() > 0:
		npc.good_skill = job_skill_ids[randi() % job_skill_ids.size()]

	if bad_skill_ids.size() > 0:
		npc.bad_skill = bad_skill_ids[randi() % bad_skill_ids.size()]

	# Housing offer — the wealth-based ask, charged at no more than 35% of income
	var wealth_data = DataManager.get_wealth_level(npc.wealth_level)
	npc.housing_type = "owner" if randi() % 4 == 0 else "renter"
	npc.base_daily_payment = float(wealth_data.get("base_rent", 5.0))
	update_daily_payment(npc)

	# Personal life: a hobby, a nest egg, and (rarely) a family
	npc.hobby = _roll_hobby(npc.wealth_level)
	npc.savings = float(wealth_data.get("base_rent", 5.0)) * SAVINGS_NEST_EGG_DAYS
	if npc.age >= 25 and randf() < KID_CHANCE:
		npc.kids = 1 if randf() < 0.7 else 2

	return npc

# Citizens pick hobbies they can actually afford: cost ≤ their wealth's base
# pay. Poor folk stargaze; nobles collect trinkets.
func _roll_hobby(wealth_level: int = 1) -> String:
	var budget = float(DataManager.get_wealth_level(wealth_level).get("base_rent", 5.0))
	var affordable: Array = []
	for hobby_id in DataManager.get_all_hobby_ids():
		if float(DataManager.get_hobby(hobby_id).get("daily_cost", 0.0)) <= budget:
			affordable.append(hobby_id)
	if affordable.is_empty():
		return "stargazing"
	return affordable[randi() % affordable.size()]

func _weighted_pick(weights: Array) -> int:
	var total = 0
	for w in weights:
		total += int(w)
	if total <= 0:
		return 0
	var r = randi() % total
	var cumulative = 0
	for i in range(weights.size()):
		cumulative += int(weights[i])
		if r < cumulative:
			return i
	return 0

func _pick_age() -> int:
	var age_data = DataManager.get_age_ranges()
	if age_data.is_empty():
		return randi_range(18, 50)
	var range_list = []
	var range_weights = []
	for key in age_data.keys():
		range_list.append(age_data[key])
		range_weights.append(int(age_data[key].get("weight", 10)))
	var idx = _weighted_pick(range_weights)
	if idx < range_list.size():
		var r = range_list[idx]
		return randi_range(r.get("min", 18), r.get("max", 60))
	return 25

func update_demand_score() -> void:
	var cur_happiness = calculate_city_happiness()
	var happiness_component = cur_happiness * 0.4              # 0-40
	var building_bonus   = min(BuildingManager.placed_buildings.size() * 2.0, 25.0)
	var citizen_bonus    = min(citizens.size() * 2.5, 15.0)
	var reputation_bonus = min(ReputationManager.reputation * 0.1, 20.0)
	demand_score = clamp(happiness_component + building_bonus + citizen_bonus + reputation_bonus, 0.0, 100.0)
	print("[CitizenManager] Demand score: %.1f" % demand_score)

func reset_wage_pressure() -> void:
	var reset_count = 0
	for c in citizens:
		if c.is_employed and c.daily_wage > c.base_daily_wage:
			c.daily_wage = c.base_daily_wage
			reset_count += 1
	if reset_count > 0:
		SignalBus.show_notification.emit("New housing built — wages returned to normal.")
		print("[CitizenManager] Wage pressure reset for %d citizens." % reset_count)

func to_array() -> Array:
	var arr = []
	for c in citizens:
		arr.append(c.to_dict())
	return arr

# Manager-level state that isn't a citizen: without these, a reload reset the
# demand score to 0 (worse arrivals and a "Demand: 0" HUD until the next day
# tick) and restarted the countdown to the next arrival from scratch.
func state_to_dict() -> Dictionary:
	return {"demand_score": demand_score, "arrival_timer": arrival_timer,
		"amenity_score": amenity_score}

func state_from_dict(data: Dictionary) -> void:
	demand_score = clampf(float(data.get("demand_score", 0.0)), 0.0, 100.0)
	arrival_timer = maxf(float(data.get("arrival_timer", 0.0)), 0.0)
	amenity_score = float(data.get("amenity_score", 0.0))

func pending_to_array() -> Array:
	var arr = []
	for n in pending_arrivals:
		arr.append(n.to_dict())
	return arr

func pending_from_array(arr: Array) -> void:
	pending_arrivals.clear()
	for d in arr:
		var n = NPC.new()
		n.from_dict(d)
		_reserve_npc_id(n.id)
		pending_arrivals.append(n)
	emit_signal("arrival_queue_changed")

# Keep _next_npc_id above every id already in play, including the timestamp-style
# ids written by older saves.
func _reserve_npc_id(npc_id: String) -> void:
	if not npc_id.begins_with("npc_"):
		return
	var suffix := npc_id.substr(4)
	if suffix.is_valid_int():
		_next_npc_id = maxi(_next_npc_id, int(suffix) + 1)

func from_array(arr: Array) -> void:
	citizens.clear()
	pending_arrivals.clear()
	_next_npc_id = 0
	emit_signal("arrival_queue_changed")
	for d in arr:
		var c = NPC.new()
		c.from_dict(d)
		_reserve_npc_id(c.id)
		# Migrate pre-ledger saves (no savings key → NAN): grant a nest egg.
		# Legit negative savings (debt) is preserved, not reset.
		if is_nan(c.savings):
			var wd = DataManager.get_wealth_level(c.wealth_level)
			c.savings = float(wd.get("base_rent", 5.0)) * SAVINGS_NEST_EGG_DAYS
		if c.hobby == "":
			c.hobby = _roll_hobby(c.wealth_level)
		citizens.append(c)
