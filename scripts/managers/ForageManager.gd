extends Node

# ForageManager — the "Go explore" foraging trip from the GDD.
# Trips cost a charge (max 3, +1 per game day). Each trip scatters seasonal
# gatherables; clicking collects them into ResourceManager, which naturally
# drives RecipeManager forage_find unlocks and quest gather objectives.

signal charges_changed(charges: int)
signal foraged(resource_id: String, amount: int)

const MAX_CHARGES: int = 3

# Weighted spawn pools per season. Enchanted finds require player level 5+
# and are boosted by the Forager's Eye potion (rare_find_chance_bonus).
const COMMON_POOL: Array = [
	["mushroom", 30], ["herbs", 28], ["wild_honey", 14],
]
const SEASON_POOL: Dictionary = {
	"Spring": [["rare_flowers", 14]],
	"Summer": [["wild_honey", 12], ["basic_fruit", 10]],
	"Autumn": [["mushroom", 14], ["herbs", 8]],
	"Winter": [],  # slim pickings — trips are smaller too
}
const ENCHANTED_BY_SEASON: Dictionary = {
	"Spring": "enchanted_berries",
	"Autumn": "enchanted_mushroom",
}
const ENCHANTED_MIN_LEVEL: int = 5
const BASE_ENCHANTED_CHANCE: float = 0.06

var charges: int = MAX_CHARGES

func _ready() -> void:
	TimeManager.new_day.connect(_on_new_day)

func _on_new_day(_day: int, _season: String, _year: int) -> void:
	if charges < MAX_CHARGES:
		charges += 1
		emit_signal("charges_changed", charges)
		if charges == 1:
			SignalBus.show_notification.emit("You feel rested — the forest calls. (1 forage trip ready)")

func can_forage() -> bool:
	return charges > 0

# Consumes a charge and returns the trip's spawns:
# [{"id": String, "enchanted": bool}, ...]  (empty array if no charges)
func start_trip() -> Array:
	if not can_forage():
		return []
	charges -= 1
	emit_signal("charges_changed", charges)

	var season: String = TimeManager.get_season_name()
	var pool: Array = COMMON_POOL.duplicate(true)
	pool.append_array(SEASON_POOL.get(season, []))

	var count: int = randi_range(6, 9) if season == "Winter" else randi_range(9, 13)
	var enchanted_chance: float = BASE_ENCHANTED_CHANCE + RecipeManager.get_rare_find_bonus()
	var enchanted_id: String = ENCHANTED_BY_SEASON.get(season, "")
	var can_enchant: bool = enchanted_id != "" and ProgressionManager.player_level >= ENCHANTED_MIN_LEVEL

	var spawns: Array = []
	for _i in range(count):
		if can_enchant and randf() < enchanted_chance:
			spawns.append({"id": enchanted_id, "enchanted": true})
		else:
			spawns.append({"id": _weighted_pick(pool), "enchanted": false})
	ProgressionManager.reward_xp("foraging_trip")
	print("[ForageManager] Trip started (%s): %d spawns, %d charges left" % [season, spawns.size(), charges])
	return spawns

func collect(resource_id: String, amount: int = 1) -> void:
	ResourceManager.add(resource_id, float(amount), "Foraged")
	emit_signal("foraged", resource_id, amount)

func _weighted_pick(pool: Array) -> String:
	var total = 0
	for entry in pool:
		total += int(entry[1])
	if total <= 0:
		return "mushroom"
	var r = randi() % total
	var cumulative = 0
	for entry in pool:
		cumulative += int(entry[1])
		if r < cumulative:
			return entry[0]
	return pool[0][0]

# ── Save / Load / Reset ───────────────────────────────────────────────────────

func reset() -> void:
	charges = MAX_CHARGES
	emit_signal("charges_changed", charges)

func to_dict() -> Dictionary:
	return {"charges": charges}

func from_dict(data: Dictionary) -> void:
	charges = clampi(int(data.get("charges", MAX_CHARGES)), 0, MAX_CHARGES)
	emit_signal("charges_changed", charges)
