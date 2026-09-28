extends Node

# QuestManager — drives the quest chains authored in data/quests.json.
# Quests activate automatically when their trigger conditions are met, track
# objective progress through manager signals, and pay out rewards on completion.

signal quest_started(quest: Dictionary)
signal quest_completed(quest: Dictionary)
signal quest_progress(quest_id: String)

# quest_id → {"activated_day": int, "baseline_earned": float, "baseline_spent": float,
#             "counters": {objective_id: float}}
var active_quests: Dictionary = {}
var completed_quests: Array = []
var permanent_unlocks: Array = []       # flags like "passive_trade_route"
var building_cost_reduction: float = 0.0  # from city_bonus rewards (e.g. blacksmith chain)

func _ready() -> void:
	TimeManager.new_day.connect(_on_new_day)
	TimeManager.new_season.connect(func(_s, _y): _check_all())
	BuildingManager.building_placed.connect(func(_b): _check_all())
	BuildingManager.building_upgraded.connect(func(_b): _check_all())
	BuildingManager.resource_produced.connect(_on_resource_produced)
	CitizenManager.citizen_arrived.connect(_on_citizen_arrived)
	CitizenManager.citizen_assigned.connect(func(_n, _b): _check_all())
	CitizenManager.housing_updated.connect(func(): _check_all())
	MarketManager.trade_completed.connect(_on_trade_completed)
	EconomyManager.gold_changed.connect(func(_g): _check_gold_objectives())
	# RecipeManager loads after us — defer these connections one frame
	call_deferred("_connect_late_signals")

func _connect_late_signals() -> void:
	RecipeManager.dish_served.connect(_on_dish_served)
	RecipeManager.potion_crafted.connect(_on_potion_crafted)
	ForageManager.foraged.connect(_on_foraged)
	FishingManager.fish_caught.connect(_on_foraged)
	CaravanManager.caravan_trade.connect(_on_trade_completed)

func _on_foraged(resource_id: String, amount: int) -> void:
	if active_quests.is_empty():
		return
	_credit_counter(["gather"], func(obj): return str(obj.get("ingredient", "")) == resource_id, float(amount))

# ── Public queries ────────────────────────────────────────────────────────────

func is_completed(quest_id: String) -> bool:
	return quest_id in completed_quests

func is_active(quest_id: String) -> bool:
	return active_quests.has(quest_id)

func get_active_quest_ids() -> Array:
	return active_quests.keys()

func get_active_count() -> int:
	return active_quests.size()

func get_cost_multiplier() -> float:
	var mult = 1.0 - building_cost_reduction
	# An architect living in town makes all construction cheaper (special skill)
	for c in CitizenManager.citizens:
		if c.good_skill == "architect":
			mult *= 0.9
			break
	return mult

# ── Trigger evaluation ────────────────────────────────────────────────────────

func _check_all() -> void:
	_activate_eligible_quests()
	_check_active_objectives()

func _activate_eligible_quests() -> void:
	for quest_id in DataManager.get_all_quest_ids():
		if is_completed(quest_id) or is_active(quest_id):
			continue
		var quest = DataManager.get_quest(quest_id)
		if _trigger_met(quest.get("trigger", {})):
			_activate_quest(quest_id, quest)

func _trigger_met(trigger: Dictionary) -> bool:
	if trigger.is_empty():
		return false
	for key in trigger:
		var value = trigger[key]
		match key:
			"event":
				if str(value) == "first_citizen_arrives":
					if CitizenManager.citizens.is_empty():
						return false
				else:
					return false
			"quest_completed":
				if not is_completed(str(value)):
					return false
			"npc_skill", "npc_special_skill":
				if not _city_has_skill(str(value)):
					return false
			"season_start":
				if TimeManager.get_season_name().to_lower() != str(value).to_lower():
					return false
			"building_level":
				var b_id = str(value.get("building", ""))
				var lvl = int(value.get("level", 1))
				if _best_global_level(b_id) < lvl:
					return false
			_:
				return false
	return true

func _city_has_skill(skill: String) -> bool:
	for c in CitizenManager.citizens:
		if c.good_skill == skill:
			return true
	return false

func _best_global_level(building_id: String) -> int:
	var best = 0
	for b in BuildingManager.get_buildings_of_type(building_id):
		best = max(best, b.get_global_level())
	return best

func _activate_quest(quest_id: String, quest: Dictionary) -> void:
	active_quests[quest_id] = {
		"activated_day": TimeManager.current_day,
		"baseline_earned": EconomyManager.total_earned,
		"baseline_spent": EconomyManager.total_spent,
		"counters": {},
	}
	emit_signal("quest_started", quest)
	SignalBus.show_notification.emit("New quest: %s" % quest.get("name", quest_id))
	print("[QuestManager] Activated: %s" % quest_id)
	# The quest may already satisfy its objectives (e.g. building exists)
	_check_quest(quest_id)

# ── Objective progress ────────────────────────────────────────────────────────

# Returns {"current": float, "target": float, "done": bool, "supported": bool}
func get_objective_progress(quest_id: String, objective: Dictionary) -> Dictionary:
	var state: Dictionary = active_quests.get(quest_id, {})
	var counters: Dictionary = state.get("counters", {})
	var obj_id = str(objective.get("id", ""))
	var result = {"current": 0.0, "target": 1.0, "done": false, "supported": true}

	match str(objective.get("type", "")):
		"build":
			result.target = float(objective.get("count", 1))
			result.current = float(BuildingManager.get_count_of_type(str(objective.get("building", ""))))
		"upgrade":
			result.target = float(objective.get("level", 1))
			result.current = float(_best_global_level(str(objective.get("building", ""))))
		"assign":
			result.target = float(objective.get("count", 1))
			result.current = float(_count_assigned(objective))
		"assign_housing":
			result.target = 1.0
			result.current = 1.0 if _skill_holder_housed(str(objective.get("npc_skill", ""))) else 0.0
		"stat":
			result.target = float(objective.get("value", 1))
			result.current = _get_stat(str(objective.get("stat", "")))
		"collect":
			result.target = float(objective.get("amount", 1))
			result.current = EconomyManager.total_earned - float(state.get("baseline_earned", 0.0))
		"spend":
			result.target = float(objective.get("amount", 1))
			result.current = EconomyManager.total_spent - float(state.get("baseline_spent", 0.0))
		"wait":
			result.target = float(objective.get("duration_days", 1))
			result.current = float(TimeManager.current_day - int(state.get("activated_day", 0)))
		"gather", "produce", "serve_dish", "cook", "craft_potion", "accept_arrival", "trade":
			result.target = float(objective.get("count", 1))
			result.current = float(counters.get(obj_id, 0.0))
		_:
			# e.g. dispatch_expedition — system not built yet
			result.supported = false

	result.done = result.supported and result.current >= result.target
	return result

func _count_assigned(objective: Dictionary) -> int:
	var building_type = str(objective.get("building", ""))
	var required_skill = str(objective.get("npc_skill", ""))
	var count = 0
	for b in BuildingManager.get_buildings_of_type(building_type):
		for npc_id in b.assigned_staff:
			var npc = CitizenManager.get_citizen_by_id(npc_id)
			if npc == null:
				continue
			if required_skill == "" or npc.good_skill == required_skill:
				count += 1
	return count

func _skill_holder_housed(skill: String) -> bool:
	for c in CitizenManager.citizens:
		if c.good_skill == skill and c.house_building_id != "":
			return true
	return false

func _get_stat(stat: String) -> float:
	match stat:
		"citizen_count":
			return float(CitizenManager.get_citizen_count())
		"city_happiness":
			return CitizenManager.calculate_city_happiness()
		"reputation":
			return ReputationManager.reputation
		"player_level":
			return float(ProgressionManager.player_level)
	return 0.0

# ── Counter events ────────────────────────────────────────────────────────────

func _credit_counter(types: Array, matcher: Callable, amount: float) -> void:
	var any_hit = false
	for quest_id in active_quests.keys():
		var quest = DataManager.get_quest(quest_id)
		for objective in quest.get("objectives", []):
			if not (str(objective.get("type", "")) in types):
				continue
			if not matcher.call(objective):
				continue
			var counters: Dictionary = active_quests[quest_id]["counters"]
			var obj_id = str(objective.get("id", ""))
			counters[obj_id] = float(counters.get(obj_id, 0.0)) + amount
			any_hit = true
			emit_signal("quest_progress", quest_id)
	if any_hit:
		_check_active_objectives()

func _on_resource_produced(building_id: String, resource_id: String, amount: float) -> void:
	if active_quests.is_empty():
		return
	# "produce" objectives (e.g. summer harvest: 30 farm ingredients)
	_credit_counter(["produce"], func(obj): return (str(obj.get("building", "")) == "" or str(obj.get("building", "")) == building_id) and (obj.get("ingredient_any", false) or str(obj.get("ingredient", "")) == resource_id), amount)
	# "gather" objectives count any acquisition of the ingredient
	_credit_counter(["gather"], func(obj): return str(obj.get("ingredient", "")) == resource_id, amount)

func _on_trade_completed(kind: String, resource_id: String, quantity: int) -> void:
	if active_quests.is_empty():
		return
	# Gathering by purchase also counts (market orders, caravan buys)
	_credit_counter(["gather"], func(obj): return kind in ["buy", "caravan"] and str(obj.get("ingredient", "")) == resource_id, float(quantity))
	# Trade objectives match by type: "caravan" needs caravan/barter deals,
	# "barter" needs a barter; untyped objectives accept any trade
	_credit_counter(["trade"], func(obj): return _trade_type_matches(str(obj.get("trade_type", "")), kind), 1.0)

func _trade_type_matches(wanted: String, kind: String) -> bool:
	if wanted == "":
		return true
	if wanted == "caravan":
		return kind in ["caravan", "barter"]
	return wanted == kind

func _on_dish_served(dish_id: String, _building_instance_id: String, _gold: float, serves: int) -> void:
	if active_quests.is_empty():
		return
	_credit_counter(["serve_dish"], func(obj): return str(obj.get("dish", "")) == dish_id, float(serves))
	_credit_counter(["cook"], func(obj): return str(obj.get("dish", "")) == dish_id, 1.0)

func _on_potion_crafted(potion_id: String) -> void:
	if active_quests.is_empty():
		return
	_credit_counter(["craft_potion"], func(obj): return str(obj.get("potion", "")) == potion_id, 1.0)

func _on_citizen_arrived(npc: NPC) -> void:
	# Mysterious arrivals = citizens carrying a rare special skill
	_credit_counter(["accept_arrival"], func(obj): return str(obj.get("npc_type", "")) != "mysterious" or npc.is_special_skill, 1.0)
	_check_all()

func _on_new_day(_day: int, _season: String, _year: int) -> void:
	_check_all()

func _check_gold_objectives() -> void:
	# Cheap early-out: only sweep when a collect/spend objective is live
	# (.keys() snapshot — _check_quest may erase completed quests mid-loop)
	for quest_id in active_quests.keys():
		var quest = DataManager.get_quest(quest_id)
		for objective in quest.get("objectives", []):
			if str(objective.get("type", "")) in ["collect", "spend"]:
				_check_quest(quest_id)
				break

# ── Completion ────────────────────────────────────────────────────────────────

func _check_active_objectives() -> void:
	for quest_id in active_quests.keys():
		_check_quest(quest_id)

func _check_quest(quest_id: String) -> void:
	if not active_quests.has(quest_id):
		return
	var quest = DataManager.get_quest(quest_id)
	var objectives: Array = quest.get("objectives", [])
	if objectives.is_empty():
		return
	for objective in objectives:
		var progress = get_objective_progress(quest_id, objective)
		if not progress.supported or not progress.done:
			return
	_complete_quest(quest_id, quest)

func _complete_quest(quest_id: String, quest: Dictionary) -> void:
	active_quests.erase(quest_id)
	completed_quests.append(quest_id)
	_apply_rewards(quest.get("rewards", {}), quest)
	ProgressionManager.reward_xp("quest_completed")
	emit_signal("quest_completed", quest)
	SignalBus.show_notification.emit("Quest complete: %s!" % quest.get("name", quest_id))
	print("[QuestManager] Completed: %s" % quest_id)
	RecipeManager.refresh_unlocks()
	# Completing a quest may satisfy the trigger of the next in the chain
	_activate_eligible_quests()

func _apply_rewards(rewards: Dictionary, quest: Dictionary) -> void:
	var quest_name = quest.get("name", "Quest")
	if float(rewards.get("gold", 0)) > 0.0:
		EconomyManager.add_gold(float(rewards["gold"]), "Quest reward: " + quest_name)
	if float(rewards.get("xp", 0)) > 0.0:
		ProgressionManager.add_xp(float(rewards["xp"]), "Quest reward: " + quest_name)
	if float(rewards.get("reputation", 0)) > 0.0:
		ReputationManager.add_reputation(float(rewards["reputation"]), quest_name)
	if rewards.get("unlock_recipe", null) != null:
		RecipeManager.unlock_dish(str(rewards["unlock_recipe"]))
	if rewards.get("unlock_potion", null) != null:
		RecipeManager.unlock_potion(str(rewards["unlock_potion"]))
	if rewards.get("permanent_unlock", null) != null:
		var flag = str(rewards["permanent_unlock"])
		if not (flag in permanent_unlocks):
			permanent_unlocks.append(flag)
	if rewards.get("unlock_building", null) != null:
		var flag = "building_" + str(rewards["unlock_building"])
		if not (flag in permanent_unlocks):
			permanent_unlocks.append(flag)
	# Festival glow: big temporary happiness lift (3 in-game days)
	if float(rewards.get("city_happiness_bonus", 0)) > 0.0:
		RecipeManager.add_temp_effect(
			quest_name + " celebrations",
			{"city_happiness_bonus": float(rewards["city_happiness_bonus"])},
			3.0 * TimeManager.DAY_LENGTH_SECONDS
		)
	if rewards.has("city_bonus"):
		var bonus: Dictionary = rewards["city_bonus"]
		building_cost_reduction += float(bonus.get("building_cost_reduction", 0.0))
	if rewards.has("seasonal_bonus"):
		var sb: Dictionary = rewards["seasonal_bonus"]
		var kind = str(sb.get("type", ""))
		var value = float(sb.get("value", 0.0))
		if kind == "happiness_bonus_permanent":
			RecipeManager.add_permanent_happiness(value)
		elif kind != "":
			RecipeManager.add_temp_effect(
				quest_name + " bonus",
				{kind: value},
				float(sb.get("duration_days", 3)) * TimeManager.DAY_LENGTH_SECONDS
			)
	if rewards.has("loot"):
		for resource_id in rewards["loot"]:
			ResourceManager.add(resource_id, float(rewards["loot"][resource_id]), "Quest loot: " + quest_name)

# ── Save / Load / Reset ───────────────────────────────────────────────────────

func reset() -> void:
	active_quests.clear()
	completed_quests.clear()
	permanent_unlocks.clear()
	building_cost_reduction = 0.0

func to_dict() -> Dictionary:
	return {
		"active_quests": active_quests.duplicate(true),
		"completed_quests": completed_quests.duplicate(),
		"permanent_unlocks": permanent_unlocks.duplicate(),
		"building_cost_reduction": building_cost_reduction,
	}

func from_dict(data: Dictionary) -> void:
	active_quests = data.get("active_quests", {}).duplicate(true)
	completed_quests = data.get("completed_quests", []).duplicate()
	permanent_unlocks = data.get("permanent_unlocks", []).duplicate()
	building_cost_reduction = float(data.get("building_cost_reduction", 0.0))
