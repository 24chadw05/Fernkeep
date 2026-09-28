extends Node

# Seasonal festivals — the next GDD feature (Phase 4: "Seasonal festivals as
# playable events"). Each season brings one festival. While its season is
# running the player can HOST it once from the festival banner for a themed
# resource cost, earning gold, a burst of reputation, and a temporary
# city-wide buff. Winter's Frost Festival is the biggest renown event of the year.

signal festival_state_changed()

# Temporary buff lasts this many in-game days after hosting
const BUFF_DAYS: float = 3.0

const FESTIVALS: Dictionary = {
	"Spring": {
		"name": "The Bloom Festival",
		"blurb": "Garland the streets with the first flowers of spring and welcome the season of growth. Citizens love the colour.",
		"cost": {"herbs": 10},
		"reward_gold": 400.0,
		"reward_reputation": 60.0,
		"buff": {"city_happiness_bonus": 8.0, "arrival_chance_bonus": 0.5},
		"buff_name": "Bloom Festival cheer",
		"buff_desc": "+8 city happiness and word spreads faster (more arrivals)",
	},
	"Summer": {
		"name": "The Harvest Fair",
		"blurb": "A grand summer fair of stalls, games and a feast straight from the fields. Trade booms while it lasts.",
		"cost": {"grain": 12, "vegetables": 8},
		"reward_gold": 650.0,
		"reward_reputation": 80.0,
		"buff": {"income_bonus": 0.2, "city_happiness_bonus": 6.0},
		"buff_name": "Harvest Fair bustle",
		"buff_desc": "+20% income and +6 city happiness",
	},
	"Autumn": {
		"name": "The Wanderer's Moon",
		"blurb": "A lantern-lit night market under the autumn moon. Mysterious folk drift in from far roads bearing rare goods.",
		"cost": {"herbs": 8, "fish": 6},
		"reward_gold": 550.0,
		"reward_reputation": 95.0,
		"buff": {"arrival_quality_bonus": 1.0, "rare_find_chance_bonus": 0.15, "city_happiness_bonus": 4.0},
		"buff_name": "Wanderer's Moon fortune",
		"buff_desc": "Wealthier arrivals and better rare finds while foraging",
	},
	"Winter": {
		"name": "The Frost Festival",
		"blurb": "The biggest celebration of the year — bonfires, feasting and songs against the cold. The whole realm hears of it.",
		"cost": {"wood": 15, "fish": 10},
		"reward_gold": 900.0,
		"reward_reputation": 160.0,
		"buff": {"city_happiness_bonus": 12.0, "income_bonus": 0.15},
		"buff_name": "Frost Festival warmth",
		"buff_desc": "+12 city happiness and +15% income against the winter slump",
	},
}

var hosted: bool = false  # has the current season's festival already been hosted?

func _ready() -> void:
	call_deferred("_connect_signals")

func _connect_signals() -> void:
	if not TimeManager.new_season.is_connected(_on_new_season):
		TimeManager.new_season.connect(_on_new_season)

func _on_new_season(_season: String, _year: int) -> void:
	hosted = false
	emit_signal("festival_state_changed")
	var f := current_festival()
	if not f.is_empty():
		SignalBus.show_notification.emit("%s has begun — host it from the festival banner!" % f.get("name", "A festival"))

func current_festival() -> Dictionary:
	return FESTIVALS.get(TimeManager.get_season_name(), {})

func current_festival_name() -> String:
	return current_festival().get("name", "Festival")

# A festival is available to host whenever the season's one hasn't been hosted.
func is_available() -> bool:
	return not hosted and not current_festival().is_empty()

func can_host() -> bool:
	return is_available() and ResourceManager.can_afford_cost(current_festival().get("cost", {}))

# Blocker string for the UI ("" = good to go)
func host_blocker() -> String:
	if hosted:
		return "Already hosted this season"
	var f := current_festival()
	if f.is_empty():
		return "No festival this season"
	if not ResourceManager.can_afford_cost(f.get("cost", {})):
		return "Not enough materials"
	return ""

func host_festival() -> bool:
	if not can_host():
		return false
	var f := current_festival()
	ResourceManager.spend_cost(f.get("cost", {}), "Festival: " + f.get("name", ""))
	EconomyManager.add_gold(float(f.get("reward_gold", 0.0)), "Festival earnings")
	ReputationManager.add_reputation(float(f.get("reward_reputation", 0.0)), f.get("name", "Festival"))
	RecipeManager.add_temp_effect(
		f.get("buff_name", "Festival cheer"),
		f.get("buff", {}),
		BUFF_DAYS * TimeManager.DAY_LENGTH_SECONDS
	)
	hosted = true
	emit_signal("festival_state_changed")
	SignalBus.show_notification.emit("%s! +%.0f gold, +%.0f reputation, and %s." % [
		f.get("name", "Festival"), float(f.get("reward_gold", 0.0)),
		float(f.get("reward_reputation", 0.0)), f.get("buff_desc", "a festive buff")
	])
	print("[FestivalManager] Hosted %s" % f.get("name", ""))
	return true

func reset() -> void:
	hosted = false

func to_dict() -> Dictionary:
	return {"hosted": hosted}

func from_dict(data: Dictionary) -> void:
	hosted = bool(data.get("hosted", false))
	emit_signal("festival_state_changed")
