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
	for key in data.keys():
		resources[key] = float(data[key])
