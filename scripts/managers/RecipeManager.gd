extends Node

# RecipeManager — the kitchen and cauldron of Fernkeep.
# Dishes:  unlocked from recipes.json, assigned to tavern menus (menu_slots per level),
#          served automatically each game day: ingredients → gold + reputation + happiness.
# Potions: crafted at the magic tower with a real-time brew timer; effects are
#          temporary buffs (tracked here) or permanent city bonuses.

signal recipes_updated()
signal dish_served(dish_id: String, building_instance_id: String, gold: float, serves: int)
signal potion_craft_started(potion_id: String, duration: float)
signal potion_crafted(potion_id: String)
signal effects_changed()

var unlocked_dishes: Array = []
var unlocked_potions: Array = []
var discovered_ingredients: Dictionary = {}  # resource_id → true (ever held)
var served_dish_counts: Dictionary = {}      # dish_id → lifetime serves

# Potion crafting — one brew at a time
var crafting_potion_id: String = ""
var craft_time_remaining: float = 0.0
var craft_time_total: float = 0.0

# Active temporary effects (potions AND quest/festival bonuses):
# [{"name": String, "potion_id": String ("" for non-potion), "effect": Dictionary, "remaining": float}]
var active_effects: Array = []

# Permanent city bonuses (potions, quest rewards)
var permanent_happiness_bonus: float = 0.0

# Happiness from today's tavern meals — recalculated every day at serve time
var meal_happiness_bonus: float = 0.0

func _ready() -> void:
	TimeManager.new_day.connect(_on_new_day)
	BuildingManager.building_upgraded.connect(func(_b): refresh_unlocks())
	ResourceManager.resource_changed.connect(_on_resource_changed)
	# Deferred + silent: initial defaults shouldn't queue a wall of toasts
	call_deferred("refresh_unlocks", true)

func _process(delta: float) -> void:
	# Potion brew timer
	if crafting_potion_id != "":
		craft_time_remaining -= delta
		if craft_time_remaining <= 0.0:
			_finish_craft()
	# Temporary effect timers
	if not active_effects.is_empty():
		var expired: Array = []
		for e in active_effects:
			e["remaining"] -= delta
			if e["remaining"] <= 0.0:
				expired.append(e)
		if not expired.is_empty():
			for e in expired:
				active_effects.erase(e)
				SignalBus.show_notification.emit("%s has worn off." % e.get("name", "A potion"))
			emit_signal("effects_changed")

# ── Unlocks ───────────────────────────────────────────────────────────────────

func refresh_unlocks(silent: bool = false) -> void:
	var changed = false
	for dish_id in DataManager.recipes.get("dishes", {}):
		if dish_id == "comment" or dish_id in unlocked_dishes:
			continue
		if _condition_met(DataManager.get_dish(dish_id).get("unlock", "default")):
			unlocked_dishes.append(dish_id)
			changed = true
			if not silent:
				SignalBus.show_notification.emit("New recipe learned: %s!" % DataManager.get_dish(dish_id).get("name", dish_id))
	for potion_id in DataManager.recipes.get("potions", {}):
		if potion_id in unlocked_potions:
			continue
		if _condition_met(DataManager.get_potion(potion_id).get("unlock", "default")):
			unlocked_potions.append(potion_id)
			changed = true
			if not silent:
				SignalBus.show_notification.emit("New potion recipe: %s!" % DataManager.get_potion(potion_id).get("name", potion_id))
	if changed:
		emit_signal("recipes_updated")

func unlock_dish(dish_id: String) -> void:
	if dish_id in unlocked_dishes or DataManager.get_dish(dish_id).is_empty():
		return
	unlocked_dishes.append(dish_id)
	SignalBus.show_notification.emit("New recipe learned: %s!" % DataManager.get_dish(dish_id).get("name", dish_id))
	emit_signal("recipes_updated")

func unlock_potion(potion_id: String) -> void:
	if potion_id in unlocked_potions or DataManager.get_potion(potion_id).is_empty():
		return
	unlocked_potions.append(potion_id)
	SignalBus.show_notification.emit("New potion recipe: %s!" % DataManager.get_potion(potion_id).get("name", potion_id))
	emit_signal("recipes_updated")

func is_dish_unlocked(dish_id: String) -> bool:
	return dish_id in unlocked_dishes

func is_potion_unlocked(potion_id: String) -> bool:
	return potion_id in unlocked_potions

# Evaluate a recipe unlock condition against current game state.
func _condition_met(condition) -> bool:
	if condition is String:
		return condition == "default"
	if not (condition is Dictionary):
		return false
	for key in condition:
		var value = condition[key]
		match key:
			"quest_completed", "npc_quest":
				if not QuestManager.is_completed(str(value)):
					return false
			"season":
				if TimeManager.get_season_name().to_lower() != str(value).to_lower():
					return false
			"forage_find", "fishing_catch", "market_order":
				if not discovered_ingredients.has(str(value)):
					return false
			"farm_level":
				if get_best_global_level("farm") < int(value):
					return false
			"magic_tower_level":
				if get_best_global_level("magic_tower") < int(value):
					return false
			"magic_tower_tier":
				if get_best_tier("magic_tower") < int(value):
					return false
			"town_hall_tier":
				if get_best_tier("town_hall") < int(value):
					return false
			_:
				return false  # unknown condition key — stay locked
	return true

func get_best_global_level(building_id: String) -> int:
	var best = 0
	for b in BuildingManager.get_buildings_of_type(building_id):
		best = max(best, b.get_global_level())
	return best

func get_best_tier(building_id: String) -> int:
	var best = 0
	for b in BuildingManager.get_buildings_of_type(building_id):
		best = max(best, b.tier)
	return best

func _on_resource_changed(resource_id: String, new_amount: float) -> void:
	if new_amount > 0.0 and not discovered_ingredients.has(resource_id):
		discovered_ingredients[resource_id] = true
		refresh_unlocks()

# ── Daily tavern service ──────────────────────────────────────────────────────

func _on_new_day(_day: int, _season: String, _year: int) -> void:
	_serve_daily_meals()
	refresh_unlocks()  # season changes can unlock seasonal recipes

func _serve_daily_meals() -> void:
	meal_happiness_bonus = 0.0
	for b in BuildingManager.placed_buildings:
		if b.building_id != "tavern" or not b.is_active or b.assigned_staff.is_empty():
			continue
		var serves_per_dish: int = b.assigned_staff.size()
		for dish_id in b.menu:
			var dish = DataManager.get_dish(dish_id)
			if dish.is_empty() or b.tier < int(dish.get("tavern_tier_required", 1)):
				continue
			var ingredients: Dictionary = dish.get("ingredients", {})
			var served = 0
			for _i in range(serves_per_dish):
				if not ResourceManager.can_afford_cost(ingredients):
					break
				ResourceManager.spend_cost(ingredients, "Cooked " + dish.get("name", dish_id))
				served += 1
			if served == 0:
				continue
			var gold = float(dish.get("gold_per_serve", 0.0)) * served
			EconomyManager.add_gold(gold, "%s served %s ×%d" % [b.get_display_name(), dish.get("name", dish_id), served])
			# First-ever serve of a dish earns its full reputation; repeats a trickle
			var first_time = not served_dish_counts.has(dish_id)
			served_dish_counts[dish_id] = int(served_dish_counts.get(dish_id, 0)) + served
			var rep = float(dish.get("reputation_gain", 0))
			if first_time:
				ReputationManager.add_reputation(rep, "First taste of %s" % dish.get("name", dish_id))
			elif rep > 0.0:
				ReputationManager.add_reputation(maxf(rep * 0.15, 0.5), "Serving %s" % dish.get("name", dish_id))
			# The finest dish served today lifts city spirits until tomorrow
			meal_happiness_bonus = maxf(meal_happiness_bonus, float(dish.get("happiness_bonus", 0.0)) * 0.2)
			emit_signal("dish_served", dish_id, b.id, gold, served)

# ── Potion crafting ───────────────────────────────────────────────────────────

func is_crafting() -> bool:
	return crafting_potion_id != ""

func get_craft_progress() -> float:
	if not is_crafting() or craft_time_total <= 0.0:
		return 0.0
	return 1.0 - (craft_time_remaining / craft_time_total)

# Returns "" if craftable, otherwise a human-readable reason.
func get_craft_blocker(potion_id: String) -> String:
	var potion = DataManager.get_potion(potion_id)
	if potion.is_empty():
		return "Unknown potion."
	if is_crafting():
		return "The cauldron is busy."
	if not is_potion_unlocked(potion_id):
		return "Recipe not yet discovered."
	var tier_req = int(potion.get("magic_tower_tier_required", 1))
	if get_best_tier("magic_tower") < tier_req:
		return "Requires a Tier %d Magic Tower." % tier_req
	if not ResourceManager.can_afford_cost(potion.get("ingredients", {})):
		return "Missing ingredients."
	return ""

func start_craft(potion_id: String) -> bool:
	if get_craft_blocker(potion_id) != "":
		return false
	var potion = DataManager.get_potion(potion_id)
	ResourceManager.spend_cost(potion.get("ingredients", {}), "Brewing " + potion.get("name", potion_id))
	crafting_potion_id = potion_id
	craft_time_total = float(potion.get("craft_time_seconds", 30.0))
	craft_time_remaining = craft_time_total
	emit_signal("potion_craft_started", potion_id, craft_time_total)
	SignalBus.show_notification.emit("Brewing %s..." % potion.get("name", potion_id))
	return true

func _finish_craft() -> void:
	var potion_id = crafting_potion_id
	crafting_potion_id = ""
	craft_time_remaining = 0.0
	var potion = DataManager.get_potion(potion_id)
	if potion.is_empty():
		return
	var effect: Dictionary = potion.get("effect", {})
	if potion.get("effect_type", "temporary") == "permanent":
		_apply_permanent_effect(effect)
	else:
		active_effects.append({
			"name": potion.get("name", potion_id),
			"potion_id": potion_id,
			"effect": effect.duplicate(),
			"remaining": float(potion.get("duration_minutes", 10.0)) * 60.0,
		})
	SignalBus.show_notification.emit("%s is ready! %s" % [potion.get("name", potion_id), potion.get("description", "")])
	emit_signal("potion_crafted", potion_id)
	emit_signal("effects_changed")

func _apply_permanent_effect(effect: Dictionary) -> void:
	if effect.has("gold_cap_increase"):
		EconomyManager.upgrade_gold_cap(EconomyManager.gold_cap + float(effect["gold_cap_increase"]))
	if effect.has("city_happiness_bonus_permanent"):
		permanent_happiness_bonus += float(effect["city_happiness_bonus_permanent"])

# Non-potion buffs (quest rewards, festival bonuses) share the effect pipeline
func add_temp_effect(display_name: String, effect: Dictionary, duration_seconds: float) -> void:
	active_effects.append({
		"name": display_name,
		"potion_id": "",
		"effect": effect.duplicate(),
		"remaining": duration_seconds,
	})
	emit_signal("effects_changed")

func add_permanent_happiness(amount: float) -> void:
	permanent_happiness_bonus += amount

# ── Effect queries (read by other managers) ───────────────────────────────────

func _sum_effect(key: String) -> float:
	var total = 0.0
	for e in active_effects:
		total += float(e["effect"].get(key, 0.0))
	return total

func get_income_multiplier() -> float:
	return 1.0 + _sum_effect("income_bonus")

func get_xp_multiplier() -> float:
	return 1.0 + _sum_effect("xp_gain_bonus")

func get_farm_yield_multiplier() -> float:
	return 1.0 + _sum_effect("farm_yield_bonus")

func get_arrival_rate_multiplier() -> float:
	return 1.0 + _sum_effect("arrival_chance_bonus")

func get_arrival_quality_bonus() -> int:
	return int(_sum_effect("arrival_quality_bonus"))

func get_city_happiness_bonus() -> float:
	return permanent_happiness_bonus + meal_happiness_bonus + _sum_effect("city_happiness_bonus")

# ── Display helpers ───────────────────────────────────────────────────────────

func pretty_name(id: String) -> String:
	return id.replace("_", " ").capitalize()

# Human-readable unlock requirement for locked recipes (shown greyed-out in UI)
func describe_unlock(condition) -> String:
	if not (condition is Dictionary):
		return ""
	var parts: Array = []
	for key in condition:
		var value = condition[key]
		match key:
			"quest_completed", "npc_quest":
				var quest = DataManager.get_quest(str(value))
				parts.append("complete \"%s\"" % quest.get("name", pretty_name(str(value))))
			"season":
				parts.append("%s season" % pretty_name(str(value)))
			"forage_find", "fishing_catch", "market_order":
				parts.append("obtain %s" % pretty_name(str(value)))
			"farm_level":
				parts.append("Farm level %d" % int(value))
			"magic_tower_level":
				parts.append("Magic Tower level %d" % int(value))
			"magic_tower_tier":
				parts.append("Magic Tower tier %d" % int(value))
			"town_hall_tier":
				parts.append("Town Hall tier %d" % int(value))
	if parts.is_empty():
		return ""
	return "Requires: " + ", ".join(PackedStringArray(parts))

# ── Save / Load / Reset ───────────────────────────────────────────────────────

func reset() -> void:
	unlocked_dishes.clear()
	unlocked_potions.clear()
	discovered_ingredients.clear()
	served_dish_counts.clear()
	crafting_potion_id = ""
	craft_time_remaining = 0.0
	craft_time_total = 0.0
	active_effects.clear()
	permanent_happiness_bonus = 0.0
	meal_happiness_bonus = 0.0
	refresh_unlocks(true)
	emit_signal("effects_changed")

func to_dict() -> Dictionary:
	var effects_out: Array = []
	for e in active_effects:
		effects_out.append({
			"name": e.get("name", ""),
			"potion_id": e.get("potion_id", ""),
			"effect": e["effect"].duplicate(),
			"remaining": e["remaining"],
		})
	return {
		"unlocked_dishes": unlocked_dishes.duplicate(),
		"unlocked_potions": unlocked_potions.duplicate(),
		"discovered_ingredients": discovered_ingredients.duplicate(),
		"served_dish_counts": served_dish_counts.duplicate(),
		"crafting_potion_id": crafting_potion_id,
		"craft_time_remaining": craft_time_remaining,
		"craft_time_total": craft_time_total,
		"active_effects": effects_out,
		"permanent_happiness_bonus": permanent_happiness_bonus,
		"meal_happiness_bonus": meal_happiness_bonus,
	}

func from_dict(data: Dictionary) -> void:
	unlocked_dishes = data.get("unlocked_dishes", []).duplicate()
	unlocked_potions = data.get("unlocked_potions", []).duplicate()
	discovered_ingredients = data.get("discovered_ingredients", {}).duplicate()
	served_dish_counts = data.get("served_dish_counts", {}).duplicate()
	crafting_potion_id = str(data.get("crafting_potion_id", ""))
	craft_time_remaining = float(data.get("craft_time_remaining", 0.0))
	craft_time_total = float(data.get("craft_time_total", 0.0))
	permanent_happiness_bonus = float(data.get("permanent_happiness_bonus", 0.0))
	meal_happiness_bonus = float(data.get("meal_happiness_bonus", 0.0))
	active_effects.clear()
	for e in data.get("active_effects", []):
		var potion_id = str(e.get("potion_id", ""))
		var potion = DataManager.get_potion(potion_id)
		var effect: Dictionary = potion.get("effect", e.get("effect", {}))
		if effect.is_empty():
			continue
		active_effects.append({
			"name": str(e.get("name", potion.get("name", "Bonus"))),
			"potion_id": potion_id,
			"effect": effect.duplicate(),
			"remaining": float(e.get("remaining", 0.0)),
		})
	refresh_unlocks(true)  # picks up any defaults missing from older saves
	emit_signal("effects_changed")
