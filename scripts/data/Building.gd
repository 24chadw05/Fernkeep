extends Resource
class_name PlacedBuilding

var id: String = ""
var building_id: String = ""
var tier: int = 1
var level: int = 1
var grid_origin: Vector2i = Vector2i.ZERO
var assigned_staff: Array = []
var assigned_residents: Array = []  # NPC IDs living here (house buildings only)
var is_active: bool = true
var sprite_path: String = ""  # chosen variant; "" falls back to SPRITE_MAP in BuildingNode
var menu: Array = []  # dish ids on this tavern's menu (tavern buildings only)
var specialization: String = ""  # T3L3 tavern branch: see SPECIALIZATIONS
var taskmaster_cut: float = 0.01  # guild hall: Taskmaster's cut of each deal (1%-10%, raised via promotion)

# The GDD's Tier-3 tavern branch: stay a (grander) tavern, or specialize
# into a cuisine restaurant that champions matching dishes.
const SPECIALIZATIONS: Dictionary = {
	"grand_tavern": {
		"label": "Grand Tavern", "cuisine": "",
		"income_mult": 1.25, "menu_bonus": 2,
		"sprite": "res://assets/buildings/Grand_Tavern.png",
		"blurb": "+25% income and 2 extra menu slots — the biggest common room in the vale.",
	},
	"hearthfire_grill": {
		"label": "Hearthfire Grill", "cuisine": "hearth",
		"income_mult": 1.4, "menu_bonus": 0,
		"sprite": "res://assets/buildings/Restaurant.png",
		"blurb": "+40% income. Meat & fish dishes earn +25% gold and double reputation.",
	},
	"verdant_table": {
		"label": "The Verdant Table", "cuisine": "verdant",
		"income_mult": 1.4, "menu_bonus": 0,
		"sprite": "res://assets/buildings/Restaurant.png",
		"blurb": "+40% income. Garden & forage dishes earn +25% gold and double reputation.",
	},
	"enchanted_bistro": {
		"label": "Enchanted Bistro", "cuisine": "enchanted",
		"income_mult": 1.4, "menu_bonus": 0,
		"sprite": "res://assets/buildings/Restaurant.png",
		"blurb": "+40% income. Enchanted dishes earn +25% gold and double reputation.",
	},
}

func get_spec_info() -> Dictionary:
	return SPECIALIZATIONS.get(specialization, {})

func can_specialize() -> bool:
	return building_id == "tavern" and tier == 3 and level == 3 and specialization == ""

func get_data() -> Dictionary:
	return DataManager.get_building(building_id)

func get_level_data() -> Dictionary:
	return DataManager.get_building_level_data(building_id, tier, level)

# Base revenue before productivity — proportional to gold invested in the
# building (see DataManager.get_base_income_per_minute). The old per-level
# "income_per_minute" JSON values are no longer read.
func get_income_per_minute() -> float:
	var base = DataManager.get_base_income_per_minute(building_id, tier, level)
	return base * float(get_spec_info().get("income_mult", 1.0))

func get_staff_slots() -> int:
	return get_level_data().get("staff_slots", 0)

func get_menu_slots() -> int:
	return int(get_level_data().get("menu_slots", 0)) + int(get_spec_info().get("menu_bonus", 0))

func can_add_menu_dish() -> bool:
	return menu.size() < get_menu_slots()

func add_menu_dish(dish_id: String) -> bool:
	if dish_id in menu or not can_add_menu_dish():
		return false
	menu.append(dish_id)
	return true

func remove_menu_dish(dish_id: String) -> void:
	menu.erase(dish_id)

func get_display_name() -> String:
	var spec = get_spec_info()
	if not spec.is_empty():
		return spec["label"]
	return get_data().get("name", building_id)

func get_size() -> Vector2i:
	var size = get_data().get("size", [1, 1])
	return Vector2i(size[0], size[1])

func get_positions() -> Array:
	return get_data().get("positions", [])

func can_add_staff() -> bool:
	return assigned_staff.size() < get_staff_slots()

func add_staff(npc_id: String) -> bool:
	if not can_add_staff():
		return false
	assigned_staff.append(npc_id)
	return true

func remove_staff(npc_id: String) -> void:
	assigned_staff.erase(npc_id)

func get_housing_capacity() -> int:
	if building_id != "house":
		return 0
	return get_level_data().get("citizen_cap", 0)

func can_add_resident() -> bool:
	return assigned_residents.size() < get_housing_capacity()

func add_resident(npc_id: String) -> bool:
	if not can_add_resident():
		return false
	assigned_residents.append(npc_id)
	return true

func remove_resident(npc_id: String) -> void:
	assigned_residents.erase(npc_id)

func get_global_level() -> int:
	return (tier - 1) * 3 + level

func get_upgrade_cost() -> float:
	var next_level = level + 1
	var next_tier = tier
	if next_level > 3:
		next_level = 1
		next_tier += 1
	if next_tier > 3:
		return -1.0
	var level_data = DataManager.get_building_level_data(building_id, next_tier, next_level)
	if level_data.is_empty():
		return -1.0  # single-level buildings (decor) have nothing to upgrade to
	return float(level_data.get("gold_cost", 0.0)) * QuestManager.get_cost_multiplier()

func to_dict() -> Dictionary:
	return {
		"id": id,
		"building_id": building_id,
		"tier": tier,
		"level": level,
		"grid_origin": [grid_origin.x, grid_origin.y],
		"assigned_staff": assigned_staff.duplicate(),
		"assigned_residents": assigned_residents.duplicate(),
		"is_active": is_active,
		"sprite_path": sprite_path,
		"menu": menu.duplicate(),
		"specialization": specialization,
		"taskmaster_cut": taskmaster_cut,
	}

func from_dict(data: Dictionary) -> void:
	id = data.get("id", "")
	building_id = data.get("building_id", "")
	tier = data.get("tier", 1)
	level = data.get("level", 1)
	var go = data.get("grid_origin", [0, 0])
	grid_origin = Vector2i(go[0], go[1])
	assigned_staff = data.get("assigned_staff", []).duplicate()
	assigned_residents = data.get("assigned_residents", []).duplicate()
	is_active = data.get("is_active", true)
	sprite_path = data.get("sprite_path", "")
	menu = data.get("menu", []).duplicate()
	specialization = str(data.get("specialization", ""))
	taskmaster_cut = float(data.get("taskmaster_cut", 0.01))
