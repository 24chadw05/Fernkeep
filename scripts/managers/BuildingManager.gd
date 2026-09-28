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

	var blocker = get_upgrade_blocker(b)
	if blocker != "":
		print("[BuildingManager] Upgrade blocked: %s" % blocker)
		return false

	var level_data = DataManager.get_building_level_data(b.building_id, next_tier, next_level)
	var cost = float(level_data.get("gold_cost", 0)) * QuestManager.get_cost_multiplier()
	var upgrade_resource_cost: Dictionary = level_data.get("resource_cost", {})
	EconomyManager.spend_gold(cost, "Upgrade " + b.get_display_name())
	ResourceManager.spend_cost(upgrade_resource_cost, "Upgrade " + b.get_display_name())
	b.tier = next_tier
	b.level = next_level

	emit_signal("building_upgraded", b)
	ProgressionManager.reward_xp("building_upgraded")
	print("[BuildingManager] Upgraded %s to T%dL%d" % [b.building_id, b.tier, b.level])
	return true

# Why an upgrade can't happen right now — "" means it's allowed. Also gates
# tier jumps behind the tier's unlock_condition (player/town-hall level).
func get_upgrade_blocker(b: PlacedBuilding) -> String:
	var next_level = b.level + 1
	var next_tier = b.tier
	if next_level > 3:
		next_level = 1
		next_tier += 1
	if next_tier > 3:
		return "Already at maximum tier."

	var level_data = DataManager.get_building_level_data(b.building_id, next_tier, next_level)
	if level_data.is_empty():
		return "Nothing to upgrade to."

	# Crossing into a new tier requires meeting that tier's unlock condition
	if next_tier > b.tier:
		var tier_cond = _tier_unlock_condition(b.building_id, next_tier)
		if not ProgressionManager.check_unlock_condition(tier_cond, b.building_id):
			return _unlock_requirement_text(tier_cond)

	var cost = float(level_data.get("gold_cost", 0)) * QuestManager.get_cost_multiplier()
	if not EconomyManager.can_afford(cost):
		return "Not enough gold (need %.0f)." % cost

	var res_cost: Dictionary = level_data.get("resource_cost", {})
	if not ResourceManager.can_afford_cost(res_cost):
		var missing: Array = []
		for r in res_cost:
			var short = int(res_cost[r]) - int(ResourceManager.get_amount(r))
			if short > 0:
				missing.append("%d %s" % [short, ResourceManager.get_item_label(r)])
		return "Not enough resources: need %s." % ", ".join(PackedStringArray(missing))
	return ""

func _tier_unlock_condition(building_id: String, tier: int):
	var data = DataManager.get_building(building_id)
	for t in data.get("tiers", []):
		if int(t.get("tier", 0)) == tier:
			return t.get("unlock_condition", null)
	return null

func _unlock_requirement_text(cond) -> String:
	if cond is Dictionary:
		var parts: Array = []
		if cond.has("player_level"):
			parts.append("player level %d" % int(cond["player_level"]))
		if cond.has("town_hall_level"):
			parts.append("town hall level %d" % int(cond["town_hall_level"]))
		if cond.has("town_hall_tier"):
			parts.append("town hall tier %d" % int(cond["town_hall_tier"]))
		if not parts.is_empty():
			return "Requires " + " and ".join(PackedStringArray(parts)) + "."
	return "Upgrade other buildings first."

func collect_resource_tick(tick_duration_seconds: float) -> void:
	for b in placed_buildings:
		if not b.is_active or b.assigned_staff.is_empty():
			continue
		var production: Dictionary = b.get_level_data().get("resource_production", {})
		if production.is_empty():
			continue
		var yield_mult = get_yield_multiplier(b)
		for resource_id in production:
			var amount = float(production[resource_id]) * b.assigned_staff.size() * (tick_duration_seconds / 60.0) * yield_mult
			ResourceManager.add(resource_id, amount, b.get_display_name())
			emit_signal("resource_produced", b.building_id, resource_id, amount)

# One place for every production multiplier, so live ticks and offline accrual
# can't drift apart. Farms get potion bonuses and the Summer harvest doubling.
func get_yield_multiplier(b: PlacedBuilding) -> float:
	if b.building_id == "farm":
		return RecipeManager.get_farm_yield_multiplier() * TimeManager.get_farm_yield_multiplier()
	return 1.0

const SPECIALIZE_COST: float = 15000.0

# The Tier-3 branch: a maxed tavern becomes a Grand Tavern or a restaurant.
func specialize_tavern(building: PlacedBuilding, spec_id: String) -> bool:
	if not building.can_specialize():
		return false
	if not PlacedBuilding.SPECIALIZATIONS.has(spec_id):
		return false
	if not EconomyManager.spend_gold(SPECIALIZE_COST, "Specialization: " + spec_id):
		SignalBus.show_notification.emit("Not enough gold to specialize (%.0f needed)." % SPECIALIZE_COST)
		return false
	building.specialization = spec_id
	building.sprite_path = building.get_spec_info().get("sprite", "")
	ReputationManager.add_reputation(25.0, "The %s opens its doors!" % building.get_display_name())
	SignalBus.show_notification.emit("✦ The %s opens its doors!" % building.get_display_name())
	emit_signal("building_upgraded", building)
	print("[BuildingManager] Specialized %s → %s" % [building.id, spec_id])
	return true

# Productivity: how hard a business is working, applied on top of base income.
#   per-worker output = 0.5 + happiness/100          (0.5 … 1.5)
#   productivity      = 0.4 + 0.8 × Σ output / slots (0.4 empty … 1.6 full & thrilled)
# Buildings without staff slots (houses, town hall) run at 1.0.
func get_productivity(b: PlacedBuilding) -> float:
	var slots = b.get_staff_slots()
	if slots <= 0:
		return 1.0
	var output = 0.0
	for npc_id in b.assigned_staff:
		var npc = CitizenManager.get_citizen_by_id(npc_id)
		if npc:
			output += 0.5 + npc.happiness / 100.0
	# food/potion "staff productivity" buffs make every worker pull harder
	return (0.4 + 0.8 * (output / slots)) * RecipeManager.get_productivity_multiplier()

# What a building is earning right now, per game-day, before the city-wide
# multipliers (season, potions, prestige). The live tick, the HUD rate, the
# revenue ledger, the inspectors and offline earnings all use this one formula,
# so a building-specific bonus (like tavern takings) can't apply in some places
# and not others.
func get_live_income_per_minute(b: PlacedBuilding) -> float:
	var income = b.get_income_per_minute() * get_productivity(b)
	if b.building_id == "tavern":
		income *= RecipeManager.get_tavern_income_multiplier()
	return income

func collect_income_tick(tick_duration_seconds: float) -> void:
	var total = 0.0
	for b in placed_buildings:
		if not b.is_active:
			continue
		total += get_live_income_per_minute(b) * (tick_duration_seconds / 60.0)
	# Seasons swing all business income (Summer +20%, Winter -15%), potions + prestige Renown stack
	total *= RecipeManager.get_income_multiplier() * TimeManager.get_income_multiplier() * PrestigeManager.get_income_multiplier()
	# Held, not banked: this accrues into the day's takings and settles as one
	# lump at day end, after wages come out of it.
	if total > 0.0:
		EconomyManager.accrue_revenue(total)
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

# A saved sprite must be one that belongs to the building's type. An older build
# let a variant chosen for one building leak onto the next placement, which left
# a Market wearing a house sprite; anything unrecognised now falls back to the
# type's default art instead of disguising the building as something else.
# (Read at runtime rather than preloaded: BuildMenu is a scene script that
# itself uses BuildingManager, and an autoload preloading it would be circular.)
func _sanitize_sprite(b: PlacedBuilding) -> void:
	if b.sprite_path == "":
		return
	var allowed: Array = [BuildingNode.SPRITE_MAP.get(b.building_id, "")]
	var menu_consts: Dictionary = load("res://scripts/ui/BuildMenu.gd").get_script_constant_map()
	for v in menu_consts.get("SPRITE_VARIANTS", {}).get(b.building_id, []):
		allowed.append(v["path"])
	if b.specialization != "":
		allowed.append(str(b.get_spec_info().get("sprite", "")))
	if not allowed.has(b.sprite_path):
		push_warning("[BuildingManager] %s (%s) had sprite %s from another building type; reset to default." % [
			b.id, b.building_id, b.sprite_path])
		b.sprite_path = ""

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

const MAX_GLOBAL_LEVEL: int = 9   # T3L3 — a fully mastered building

# Building slots = the town hall's base plots, expanded by every mastered
# (max-level) building elsewhere in the city. Mastering buildings grows the map.
func get_building_slot_limit() -> int:
	var limit = 0
	for b in placed_buildings:
		if b.building_id == "town_hall":
			limit += b.get_level_data().get("building_slots", 4)
	return max(limit, 4) + get_expansion_points()  # always at least 4 so a fresh game isn't locked

# One expansion point per mastered building (max global level), town hall and
# decor excluded — the town hall drives the base plots, decor isn't a building.
func get_expansion_points() -> int:
	var count = 0
	for b in placed_buildings:
		if b.building_id == "town_hall":
			continue
		if b.get_data().get("category", "") == "decor":
			continue
		if b.get_global_level() >= MAX_GLOBAL_LEVEL:
			count += 1
	return count

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
	# Ids are sparse once buildings have been demolished (b_0, b_1, b_4…), so the
	# next id has to clear the highest one in the save — counting them would hand
	# out an id that's already taken and silently alias two buildings.
	var highest := -1
	for d in arr:
		var b = PlacedBuilding.new()
		b.from_dict(d)
		_sanitize_sprite(b)
		placed_buildings.append(b)
		if b.id.begins_with("b_"):
			highest = maxi(highest, int(b.id.substr(2)))
	_next_id = highest + 1
