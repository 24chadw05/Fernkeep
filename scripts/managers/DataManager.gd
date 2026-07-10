extends Node

var buildings: Dictionary = {}
var citizens_data: Dictionary = {}
var recipes: Dictionary = {}
var quests: Dictionary = {}

func _ready() -> void:
	_load_json("res://data/buildings.json", buildings)
	_load_json("res://data/citizens.json", citizens_data)
	_load_json("res://data/recipes.json", recipes)
	_load_json("res://data/quests.json", quests)
	print("[DataManager] All data loaded.")

func _load_json(path: String, target: Dictionary) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[DataManager] Could not open: " + path)
		return
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("[DataManager] JSON parse error in %s: %s" % [path, json.get_error_message()])
		return
	target.merge(json.get_data(), true)

# --- Buildings ---

func get_building(id: String) -> Dictionary:
	return buildings.get("buildings", {}).get(id, {})

func get_building_level_data(id: String, tier: int, level: int) -> Dictionary:
	var b = get_building(id)
	if b.is_empty():
		return {}
	for t in b.get("tiers", []):
		if t.get("tier") == tier:
			for l in t.get("levels", []):
				if l.get("level") == level:
					return l
	return {}

func get_all_building_ids() -> Array:
	return buildings.get("buildings", {}).keys()

func get_building_positions(id: String) -> Array:
	return get_building(id).get("positions", [])

# --- Citizens ---

func get_citizen_skill(skill_id: String) -> Dictionary:
	var job_skills = citizens_data.get("job_skills", {})
	if job_skills.has(skill_id):
		return job_skills[skill_id]
	return citizens_data.get("special_skills", {}).get(skill_id, {})

func get_bad_skill(skill_id: String) -> Dictionary:
	return citizens_data.get("bad_skills", {}).get(skill_id, {})

func get_name_pools() -> Dictionary:
	return citizens_data.get("name_pools", {})

func get_wealth_level(level: int) -> Dictionary:
	return citizens_data.get("wealth_levels", {}).get(str(level), {})

func get_arrival_weights(player_level: int) -> Dictionary:
	var w = citizens_data.get("arrival_weights", {})
	if player_level <= 3:
		return w.get("player_level_1_3", {})
	elif player_level <= 6:
		return w.get("player_level_4_6", {})
	elif player_level <= 9:
		return w.get("player_level_7_9", {})
	else:
		return w.get("player_level_10_plus", {})

func get_age_ranges() -> Dictionary:
	return citizens_data.get("age_ranges", {})

func get_all_job_skill_ids() -> Array:
	return citizens_data.get("job_skills", {}).keys()

func get_all_special_skill_ids() -> Array:
	return citizens_data.get("special_skills", {}).keys()

func get_all_bad_skill_ids() -> Array:
	return citizens_data.get("bad_skills", {}).keys()

# --- Recipes ---

func get_dish(id: String) -> Dictionary:
	return recipes.get("dishes", {}).get(id, {})

func get_potion(id: String) -> Dictionary:
	return recipes.get("potions", {}).get(id, {})

func get_recipe(id: String) -> Dictionary:
	var d = get_dish(id)
	return d if not d.is_empty() else get_potion(id)

# --- Quests ---

func get_quest(id: String) -> Dictionary:
	return quests.get("quests", {}).get(id, {})

func get_all_quest_ids() -> Array:
	return quests.get("quests", {}).keys()
