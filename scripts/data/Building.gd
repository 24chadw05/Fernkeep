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

func get_data() -> Dictionary:
	return DataManager.get_building(building_id)

func get_level_data() -> Dictionary:
	return DataManager.get_building_level_data(building_id, tier, level)

func get_income_per_minute() -> float:
	return get_level_data().get("income_per_minute", 0.0)

func get_staff_slots() -> int:
	return get_level_data().get("staff_slots", 0)

func get_menu_slots() -> int:
	return get_level_data().get("menu_slots", 0)

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
