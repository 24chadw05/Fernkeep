extends Node

var citizens: Array = []
var pending_arrival: NPC = null

var arrival_timer: float = 0.0
var arrival_interval: float = 45.0

# Demand score (0-100): drives arrival quality independent of player level.
# Updated daily by GameManager.
var demand_score: float = 0.0

signal citizen_arrived(npc: NPC)
signal citizen_assigned(npc: NPC, building_id: String)
signal arrival_pending(npc: NPC)
signal city_happiness_updated(happiness: float)
signal housing_updated()

func _process(delta: float) -> void:
	# Charm potions make word of the city travel faster
	arrival_timer += delta * RecipeManager.get_arrival_rate_multiplier()
	if arrival_timer >= arrival_interval and pending_arrival == null:
		arrival_timer = 0.0
		_try_spawn_arrival()

func _try_spawn_arrival() -> void:
	var npc = _generate_random_npc()
	pending_arrival = npc
	emit_signal("arrival_pending", npc)
	print("[CitizenManager] New arrival pending: %s" % npc.get_full_name())

func accept_arrival(npc: NPC) -> void:
	# Auto-assign to the first available house
	var house = _get_first_available_house()
	if house:
		house.add_resident(npc.id)
		npc.house_building_id = house.id
	# (If no house, NPC is homeless — arrival still allowed, happiness penalised)

	citizens.append(npc)
	pending_arrival = null
	emit_signal("citizen_arrived", npc)
	emit_signal("housing_updated")
	ProgressionManager.reward_xp("npc_arrived")
	EconomyManager.add_gold(npc.daily_payment, "Arrival deposit from " + npc.get_full_name())
	print("[CitizenManager] Accepted: %s (house: %s)" % [npc.get_full_name(), npc.house_building_id])

func decline_arrival(npc: NPC) -> void:
	pending_arrival = null
	print("[CitizenManager] Declined: %s" % npc.get_full_name())

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
	var wd = DataManager.get_wealth_level(npc.wealth_level)
	var fair_wage = float(wd.get("base_rent", 5.0))
	# Set starting wage at 80% of fair wage if not already set
	if npc.daily_wage <= 0.0:
		npc.daily_wage = fair_wage * 0.8
	npc.base_daily_wage = npc.daily_wage
	npc.recalculate_pay_happiness(fair_wage)

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

func calculate_city_happiness() -> float:
	if citizens.is_empty():
		return 100.0
	var total = 0.0
	for c in citizens:
		c.calculate_happiness()
		total += c.happiness
	var avg = total / float(citizens.size())
	# Meals, potions, and permanent blessings lift the whole city
	avg = clampf(avg + RecipeManager.get_city_happiness_bonus(), 0.0, 100.0)
	emit_signal("city_happiness_updated", avg)
	return avg

func on_new_day() -> void:
	var housing_full = (get_available_housing_count() == 0 and citizens.size() > 0)

	for c in citizens:
		c.days_in_town += 1
		if c.is_employed and c.daily_wage > 0.0:
			EconomyManager.pay_wage(c.daily_wage, c.get_full_name())
		# Only collect rent/tax if the NPC has a house
		if c.house_building_id != "":
			match c.housing_type:
				"renter":
					EconomyManager.collect_rent(c.daily_payment, c.get_full_name())
				"owner":
					EconomyManager.collect_tax(c.daily_payment, c.get_full_name())
		# Keep pay_happiness current after any wage pressure changes
		if c.is_employed:
			var wd = DataManager.get_wealth_level(c.wealth_level)
			c.recalculate_pay_happiness(float(wd.get("base_rent", 5.0)))

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

	npc.id = "npc_%d" % Time.get_ticks_msec()
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

	# Housing offer
	var wealth_data = DataManager.get_wealth_level(npc.wealth_level)
	npc.housing_type = "owner" if randi() % 4 == 0 else "renter"
	npc.daily_payment = float(wealth_data.get("base_rent", 5.0))

	return npc

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

func from_array(arr: Array) -> void:
	citizens.clear()
	for d in arr:
		var c = NPC.new()
		c.from_dict(d)
		citizens.append(c)
