extends Node

var placed_buildings: Array = []
var _next_id: int = 0

signal building_placed(building: PlacedBuilding)
signal building_upgraded(building: PlacedBuilding)
signal building_removed(building: PlacedBuilding)
signal income_tick(total: float)
signal resource_produced(building_id: String, resource_id: String, amount: float)

func place_building_free(building_id: String, grid_origin: Vector2i, sprite_path: String = "") -> PlacedBuilding:
	var data = DataManager.get_building(building_id)
	if data.is_empty():
		push_error("[BuildingManager] Unknown building: " + building_id)
		return null
	var building         = PlacedBuilding.new()
	building.id          = "b_%d" % _next_id
	_next_id            += 1
	building.building_id = building_id
	building.tier        = 1
	building.level       = 1
	building.grid_origin = grid_origin
	building.sprite_path = sprite_path
	placed_buildings.append(building)
	emit_signal("building_placed", building)
	print("[BuildingManager] Placed (free) %s at %s" % [building_id, grid_origin])
	return building

func place_building(building_id: String, grid_origin: Vector2i, sprite_path: String = "") -> PlacedBuilding:
	var data = DataManager.get_building(building_id)
	if data.is_empty():
		push_error("[BuildingManager] Unknown building: " + building_id)
		return null

	# Enforce town-hall building-slot limit (town_hall and decor are exempt)
	if building_id != "town_hall" and data.get("category", "") != "decor":
		var limit = get_building_slot_limit()
		var current = get_non_town_hall_count()
		if current >= limit:
			SignalBus.show_notification.emit(
				"Building limit reached (%d/%d). Upgrade the Town Hall to unlock more slots." % [current, limit]
			)
			print("[BuildingManager] Slot limit reached (%d/%d)." % [current, limit])
			return null

	var level_data = DataManager.get_building_level_data(building_id, 1, 1)
	var gold_cost = float(level_data.get("gold_cost", 0)) * QuestManager.get_cost_multiplier()

	if not EconomyManager.can_afford(gold_cost):
		print("[BuildingManager] Cannot afford %s (need %.0f, have %.0f)" % [
			building_id, gold_cost, EconomyManager.gold
		])
		return null

	var resource_cost: Dictionary = level_data.get("resource_cost", {})
	if not ResourceManager.can_afford_cost(resource_cost):
		print("[BuildingManager] Cannot afford resource cost for %s" % building_id)
		return null

	EconomyManager.spend_gold(gold_cost, "Build " + data.get("name", building_id))
	ResourceManager.spend_cost(resource_cost, "Build " + data.get("name", building_id))

	var building         = PlacedBuilding.new()
	building.id          = "b_%d" % _next_id
	_next_id            += 1
	building.building_id = building_id
	building.tier        = 1
	building.level       = 1
	building.grid_origin = grid_origin
	building.sprite_path = sprite_path

	placed_buildings.append(building)
	emit_signal("building_placed", building)
	ProgressionManager.reward_xp("building_placed")

	print("[BuildingManager] Placed %s at %s" % [building_id, grid_origin])
	return building

func upgrade_building(instance_id: String) -> bool:
	var b = get_building_by_id(instance_id)
	if not b:
		return false

	var next_level = b.level + 1
	var next_tier = b.tier
	if next_level > 3:
		next_level = 1
		next_tier += 1
	if next_tier > 3:
		print("[BuildingManager] %s is already max tier." % b.building_id)
		return false

	var level_data = DataManager.get_building_level_data(b.building_id, next_tier, next_level)
	if level_data.is_empty():
		return false

	var cost = float(level_data.get("gold_cost", 0)) * QuestManager.get_cost_multiplier()
	if not EconomyManager.can_afford(cost):
		print("[BuildingManager] Cannot afford upgrade (need %.0f)" % cost)
		return false

	var upgrade_resource_cost: Dictionary = level_data.get("resource_cost", {})
	if not ResourceManager.can_afford_cost(upgrade_resource_cost):
		print("[BuildingManager] Cannot afford resource cost for upgrade of %s" % b.building_id)
		return false

	EconomyManager.spend_gold(cost, "Upgrade " + b.get_display_name())
	ResourceManager.spend_cost(upgrade_resource_cost, "Upgrade " + b.get_display_name())
	b.tier = next_tier
	b.level = next_level

	emit_signal("building_upgraded", b)
	ProgressionManager.reward_xp("building_upgraded")
	print("[BuildingManager] Upgraded %s to T%dL%d" % [b.building_id, b.tier, b.level])
	return true

func collect_resource_tick(tick_duration_seconds: float) -> void:
	for b in placed_buildings:
		if not b.is_active or b.assigned_staff.is_empty():
			continue
		var production: Dictionary = b.get_level_data().get("resource_production", {})
		if production.is_empty():
			continue
		var yield_mult = RecipeManager.get_farm_yield_multiplier() if b.building_id == "farm" else 1.0
		for resource_id in production:
			var amount = float(production[resource_id]) * b.assigned_staff.size() * (tick_duration_seconds / 60.0) * yield_mult
			ResourceManager.add(resource_id, amount, b.get_display_name())
			emit_signal("resource_produced", b.building_id, resource_id, amount)

func collect_income_tick(tick_duration_seconds: float) -> void:
	var total = 0.0
	for b in placed_buildings:
		if not b.is_active:
			continue
		var income = b.get_income_per_minute() * (tick_duration_seconds / 60.0)
		# Staff happiness scales income: 0% happiness → 50% output, 100% → 150%
		var slots = b.get_staff_slots()
		if slots > 0 and not b.assigned_staff.is_empty():
			var avg_h = 0.0
			var counted = 0
			for npc_id in b.assigned_staff:
				var npc = CitizenManager.get_citizen_by_id(npc_id)
				if npc:
					avg_h += npc.happiness
					counted += 1
			if counted > 0:
				avg_h /= counted
				income *= 0.5 + (avg_h / 100.0)
		total += income
	total *= RecipeManager.get_income_multiplier()
	if total > 0.0:
		EconomyManager.add_gold(total)
	emit_signal("income_tick", total)

func remove_building(instance_id: String) -> void:
	var b = get_building_by_id(instance_id)
	if not b:
		return
	for npc_id in b.assigned_staff.duplicate():
		CitizenManager.unassign_from_building(npc_id)
	for npc_id in b.assigned_residents.duplicate():
		CitizenManager.unassign_housing(npc_id)
	placed_buildings.erase(b)
	emit_signal("building_removed", b)
	print("[BuildingManager] Removed %s (%s)" % [b.building_id, instance_id])

func get_building_by_id(instance_id: String) -> PlacedBuilding:
	for b in placed_buildings:
		if b.id == instance_id:
			return b
	return null

func get_buildings_of_type(building_id: String) -> Array:
	return placed_buildings.filter(func(b): return b.building_id == building_id)

func get_count_of_type(building_id: String) -> int:
	return get_buildings_of_type(building_id).size()

func has_building_type(building_id: String) -> bool:
	return get_count_of_type(building_id) > 0

func get_total_citizen_cap() -> int:
	var cap = 0
	for b in placed_buildings:
		if b.building_id == "town_hall":
			cap += b.get_level_data().get("citizen_cap", 0)
	return cap

func get_housing_buildings() -> Array:
	return placed_buildings.filter(func(b): return b.building_id == "house")

func get_total_housing_capacity() -> int:
	var cap = 0
	for b in placed_buildings:
		cap += b.get_housing_capacity()
	return cap

func get_available_housing_count() -> int:
	var available = 0
	for b in placed_buildings:
		if b.building_id == "house":
			available += max(0, b.get_housing_capacity() - b.assigned_residents.size())
	return available

func get_building_slot_limit() -> int:
	var limit = 0
	for b in placed_buildings:
		if b.building_id == "town_hall":
			limit += b.get_level_data().get("building_slots", 4)
	return max(limit, 4)  # always at least 4 so a fresh game isn't locked

func get_non_town_hall_count() -> int:
	# Decor doesn't consume building slots
	var count = 0
	for b in placed_buildings:
		if b.building_id == "town_hall":
			continue
		if b.get_data().get("category", "") == "decor":
			continue
		count += 1
	return count

func get_all_buildings() -> Array:
	return placed_buildings.duplicate()

func to_array() -> Array:
	var arr = []
	for b in placed_buildings:
		arr.append(b.to_dict())
	return arr

func from_array(arr: Array) -> void:
	placed_buildings.clear()
	for d in arr:
		var b = PlacedBuilding.new()
		b.from_dict(d)
		placed_buildings.append(b)
	_next_id = placed_buildings.size()
