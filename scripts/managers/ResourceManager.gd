extends Node

const DEFAULT_RESOURCES: Dictionary = {
	"wood": 50.0,
	"stone": 30.0,
	"herbs": 0.0,
	"fish": 0.0,
	"grain": 0.0,
	"vegetables": 0.0,
	"enchanted_ore": 0.0,
	"rare_ingredients": 0.0,
}

var resources: Dictionary = DEFAULT_RESOURCES.duplicate()

# Central item registry — display name + icon for every resource in the game.
# Order here = display order in the inventory. Used by InventoryPanel,
# MarketPanel, and anything else that shows items.
const ITEM_INFO: Dictionary = {
	# Raw materials
	"wood":              {"label": "Wood",              "icon": "res://assets/items/wood.png"},
	"stone":             {"label": "Stone",             "icon": "res://assets/items/stone.png"},
	"enchanted_ore":     {"label": "Enchanted Ore",     "icon": "res://assets/items/enchanted_ore.png"},
	# Farm & forage
	"grain":             {"label": "Grain",             "icon": "res://assets/items/grain.png"},
	"vegetables":        {"label": "Vegetables",        "icon": "res://assets/items/vegetables.png"},
	"herbs":             {"label": "Herbs",             "icon": "res://assets/forage/herbs.png"},
	"mushroom":          {"label": "Mushrooms",         "icon": "res://assets/forage/mushroom.png"},
	"wild_honey":        {"label": "Wild Honey",        "icon": "res://assets/forage/wild_honey.png"},
	"basic_fruit":       {"label": "Fruit",             "icon": "res://assets/forage/basic_fruit.png"},
	"better_fruit":      {"label": "Orchard Fruit",     "icon": "res://assets/items/better_fruit.png"},
	"premium_fruit":     {"label": "Premium Fruit",     "icon": "res://assets/items/premium_fruit.png"},
	"seasonal_crops":    {"label": "Seasonal Crops",    "icon": "res://assets/items/seasonal_crops.png"},
	"rare_flowers":      {"label": "Rare Flowers",      "icon": "res://assets/forage/rare_flowers.png"},
	"rare_herbs":        {"label": "Rare Herbs",        "icon": "res://assets/items/rare_herbs.png"},
	# Fish
	"fish":              {"label": "Fish",              "icon": "res://assets/fishing/fish.png"},
	"river_fish":        {"label": "River Fish",        "icon": "res://assets/fishing/river_fish.png"},
	"lake_trout":        {"label": "Lake Trout",        "icon": "res://assets/fishing/lake_trout.png"},
	"legendary_fish":    {"label": "Legendary Fish",    "icon": "res://assets/fishing/legendary_fish.png"},
	# Pantry
	"water":             {"label": "Water",             "icon": "res://assets/items/water.png"},
	"boar_meat":         {"label": "Boar Meat",         "icon": "res://assets/items/boar_meat.png"},
	# Enchanted & legendary
	"enchanted_berries": {"label": "Enchanted Berries", "icon": "res://assets/forage/enchanted_berries.png"},
	"enchanted_mushroom":{"label": "Enchanted Mushroom","icon": "res://assets/forage/enchanted_mushroom.png"},
	"enchanted_crops":   {"label": "Enchanted Crops",   "icon": "res://assets/items/enchanted_crops.png"},
	"enchanted_fruit":   {"label": "Enchanted Fruit",   "icon": "res://assets/items/enchanted_fruit.png"},
	"legendary_herbs":   {"label": "Legendary Herbs",   "icon": "res://assets/items/legendary_herbs.png"},
	"rare_ingredients":  {"label": "Rare Ingredients",  "icon": "res://assets/items/rare_ingredients.png"},
}

func get_item_label(resource_id: String) -> String:
	return ITEM_INFO.get(resource_id, {}).get("label", resource_id.replace("_", " ").capitalize())

func get_item_icon_path(resource_id: String) -> String:
	return ITEM_INFO.get(resource_id, {}).get("icon", "")

signal resource_changed(resource_id: String, new_amount: float)

func reset() -> void:
	resources = DEFAULT_RESOURCES.duplicate()
	for key in resources:
		emit_signal("resource_changed", key, resources[key])

func add(resource_id: String, amount: float, reason: String = "") -> void:
	if not resources.has(resource_id):
		resources[resource_id] = 0.0
	resources[resource_id] += amount
	emit_signal("resource_changed", resource_id, resources[resource_id])
	if reason != "":
		print("[ResourceManager] +%.2f %s — %s" % [amount, resource_id, reason])

func spend(resource_id: String, amount: float, reason: String = "") -> bool:
	if not can_afford(resource_id, amount):
		print("[ResourceManager] Cannot afford %.2f %s (have %.2f)" % [amount, resource_id, get_amount(resource_id)])
		return false
	resources[resource_id] -= amount
	emit_signal("resource_changed", resource_id, resources[resource_id])
	return true

func can_afford(resource_id: String, amount: float) -> bool:
	return resources.get(resource_id, 0.0) >= amount

func can_afford_cost(cost: Dictionary) -> bool:
	for resource_id in cost.keys():
		if not can_afford(resource_id, float(cost[resource_id])):
			return false
	return true

func spend_cost(cost: Dictionary, reason: String = "") -> bool:
	if not can_afford_cost(cost):
		return false
	for resource_id in cost.keys():
		spend(resource_id, float(cost[resource_id]), reason)
	return true

func get_amount(resource_id: String) -> float:
	return resources.get(resource_id, 0.0)

func get_display(resource_id: String) -> String:
	return str(get_amount(resource_id))

func to_dict() -> Dictionary:
	return resources.duplicate()

func from_dict(data: Dictionary) -> void:
	# Autoloads survive the scene reload that switches slots, so the stores have to
	# be wiped first — merging would carry the previous city's goods into this one.
	resources = DEFAULT_RESOURCES.duplicate()
	for key in data.keys():
		resources[key] = float(data[key])
	for key in resources:
		emit_signal("resource_changed", key, resources[key])
