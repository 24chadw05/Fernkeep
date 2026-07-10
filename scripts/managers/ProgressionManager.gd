extends Node

var player_level: int = 1
var current_xp: float = 0.0
var xp_to_next_level: float = 100.0

var town_hall_level: int = 1
var total_xp_earned: float = 0.0

# XP rewards
const XP_REWARDS = {
	"building_placed":    25.0,
	"building_upgraded":  15.0,
	"npc_arrived":        20.0,
	"quest_completed":    50.0,
	"day_survived":        5.0,
	"trade_completed":    10.0,
	"dish_unlocked":      30.0,
	"season_completed":   75.0,
}

# Unlocks per level
const LEVEL_UNLOCKS = {
	2:  "Second house slot",
	3:  "Market unlocked",
	4:  "Farm unlocked",
	5:  "Second farm slot",
	6:  "Guild hall unlocked",
	7:  "Magic tower unlocked",
	8:  "Third house slot",
	9:  "Tavern upgrade available",
	10: "Map expansion 1",
}

signal level_up(new_level: int, unlock: String)
signal xp_gained(amount: float, new_total: float)

func add_xp(amount: float, reason: String = "") -> void:
	amount *= RecipeManager.get_xp_multiplier()
	current_xp += amount
	total_xp_earned += amount
	emit_signal("xp_gained", amount, current_xp)
	if reason != "":
		print("[Progression] +%.0f XP — %s (%.0f/%.0f)" % [amount, reason, current_xp, xp_to_next_level])
	while current_xp >= xp_to_next_level:
		_level_up()

func _level_up() -> void:
	current_xp -= xp_to_next_level
	player_level += 1
	xp_to_next_level = _calculate_xp_for_level(player_level)
	var unlock = LEVEL_UNLOCKS.get(player_level, "")
	emit_signal("level_up", player_level, unlock)
	print("[Progression] Level up! Now level %d" % player_level)
	if unlock != "":
		print("[Progression] Unlocked: %s" % unlock)

func _calculate_xp_for_level(level: int) -> float:
	# Each level requires more XP — exponential curve
	return 100.0 * pow(level, 1.5)

func reward_xp(event: String) -> void:
	var amount = XP_REWARDS.get(event, 0.0)
	if amount > 0:
		add_xp(amount, event)

func get_level_progress() -> float:
	return current_xp / xp_to_next_level

func get_display_string() -> String:
	return "Level %d (%.0f/%.0f XP)" % [player_level, current_xp, xp_to_next_level]

func check_unlock_condition(condition, building_id: String = "") -> bool:
	if condition == null:
		return true
	# String conditions — "default" or anything unrecognised = unlocked
	if condition is String:
		return true
	if condition is Dictionary:
		if condition.has("player_level") and player_level < int(condition["player_level"]):
			return false
		if condition.has("town_hall_level") and town_hall_level < int(condition["town_hall_level"]):
			return false
		if condition.has("town_hall_tier"):
			var th_tier = 0
			for b in BuildingManager.get_buildings_of_type("town_hall"):
				th_tier = max(th_tier, b.tier)
			if th_tier < int(condition["town_hall_tier"]):
				return false
		if condition.has("special_npc_skill"):
			for c in CitizenManager.citizens:
				if c.good_skill == condition["special_npc_skill"]:
					return true
			return false
		# Dynamic cap: 1 instance at the unlock level, +1 per 5 additional player levels
		if condition.has("count_per_5_levels") and building_id != "":
			var base_level  = int(condition.get("player_level", 1))
			var allowed     = 1 + int((player_level - base_level) / 5)
			if BuildingManager.get_count_of_type(building_id) >= allowed:
				return false
	return true
