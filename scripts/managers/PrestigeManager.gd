extends Node

# Prestige — the Phase-4 endgame reset. Once the town hall reaches Tier 3 the
# player can "found anew": the city wipes back to a fresh start, but they keep
# a permanent Renown bonus (a stacking income multiplier) and pick an alternate
# start scenario that reshapes the opening city.

const PRESTIGE_TOWN_HALL_LEVEL: int = 7   # global level 7 = Tier 3 reached
const RENOWN_INCOME_PER_POINT: float = 0.02  # each Renown point = +2% permanent income

# Alternate starts (GDD). Each reshapes the opening city and adds a signature perk.
const SCENARIOS: Dictionary = {
	"hamlet": {
		"name": "The Forgotten Hamlet",
		"blurb": "A humble start — a couple of crumbling houses and a dream.",
		"gold": 500.0,
		"resources": {"wood": 10.0},
		"buildings": ["house", "house"],
	},
	"ruined_castle": {
		"name": "The Ruined Castle",
		"blurb": "Old stone walls and a full coffer, but few homes still stand.",
		"gold": 1500.0,
		"resources": {"stone": 120.0, "wood": 40.0},
		"buildings": ["house"],
	},
	"dwarven_camp": {
		"name": "The Dwarven Mining Camp",
		"blurb": "Little gold, but a working mine and a mountain of ore.",
		"gold": 300.0,
		"resources": {"stone": 100.0, "enchanted_ore": 25.0},
		"buildings": ["mining_operation", "house"],
	},
	"elven_outpost": {
		"name": "The Elven Outpost",
		"blurb": "Nestled in the greenwood — rich in herbs, timber, and a farm.",
		"gold": 400.0,
		"resources": {"wood": 80.0, "herbs": 50.0},
		"buildings": ["farm", "house", "house"],
	},
	"merchant_republic": {
		"name": "The Merchant Republic",
		"blurb": "Coin to spare and a market already trading on day one.",
		"gold": 2500.0,
		"resources": {},
		"buildings": ["market", "house"],
	},
}

var prestige_count: int = 0
var renown: float = 0.0
var start_scenario: String = "hamlet"

signal prestige_stats_changed()

# The permanent income multiplier all earnings are scaled by.
func get_income_multiplier() -> float:
	return 1.0 + renown * RENOWN_INCOME_PER_POINT

func can_prestige() -> bool:
	return ProgressionManager.town_hall_level >= PRESTIGE_TOWN_HALL_LEVEL

# Renown banked for founding anew right now — rewards a bigger, more developed city.
func renown_reward() -> float:
	var buildings = BuildingManager.placed_buildings.size()
	var reward = ProgressionManager.player_level * 1.0 \
		+ buildings * 2.0 \
		+ ProgressionManager.town_hall_level * 3.0 \
		+ CitizenManager.citizens.size() * 1.0
	return floorf(reward)

func get_scenario(scenario_id: String) -> Dictionary:
	return SCENARIOS.get(scenario_id, SCENARIOS["hamlet"])

# Bank the renown, remember the chosen start, then let GameManager wipe & rebuild.
func execute_prestige(scenario_id: String) -> void:
	if not SCENARIOS.has(scenario_id):
		scenario_id = "hamlet"
	renown += renown_reward()
	prestige_count += 1
	start_scenario = scenario_id
	emit_signal("prestige_stats_changed")
	print("[Prestige] Founded anew (#%d) as '%s'. Renown now %.0f (+%.0f%% income)." % [
		prestige_count, scenario_id, renown, (get_income_multiplier() - 1.0) * 100.0
	])
	SignalBus.prestige_requested.emit()

# Only a brand-new game wipes prestige progress — prestiging itself keeps it.
func reset() -> void:
	prestige_count = 0
	renown = 0.0
	start_scenario = "hamlet"
	emit_signal("prestige_stats_changed")

func to_dict() -> Dictionary:
	return {
		"prestige_count": prestige_count,
		"renown": renown,
		"start_scenario": start_scenario,
	}

func from_dict(data: Dictionary) -> void:
	prestige_count = int(data.get("prestige_count", 0))
	renown = float(data.get("renown", 0.0))
	start_scenario = str(data.get("start_scenario", "hamlet"))
	emit_signal("prestige_stats_changed")
