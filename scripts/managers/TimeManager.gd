extends Node

const SEASONS = ["Spring", "Summer", "Autumn", "Winter"]
const DAY_LENGTH_SECONDS = 60.0
const DAYS_PER_SEASON = 7

var current_day: int = 1
var current_season_index: int = 0
var current_year: int = 1
var day_timer: float = 0.0

signal new_day(day: int, season: String, year: int)
signal new_season(season: String, year: int)
signal new_year(year: int)

func _process(delta: float) -> void:
	day_timer += delta
	if day_timer >= DAY_LENGTH_SECONDS:
		day_timer -= DAY_LENGTH_SECONDS
		_advance_day()

func _advance_day() -> void:
	current_day += 1
	var day_in_season = (current_day - 1) % DAYS_PER_SEASON
	if day_in_season == 0 and current_day > 1:
		_advance_season()
	emit_signal("new_day", current_day, get_season_name(), current_year)

func _advance_season() -> void:
	current_season_index = (current_season_index + 1) % 4
	if current_season_index == 0:
		current_year += 1
		emit_signal("new_year", current_year)
	emit_signal("new_season", get_season_name(), current_year)
	print("[TimeManager] Season changed to %s, Year %d" % [get_season_name(), current_year])

func get_season_name() -> String:
	return SEASONS[current_season_index]

func get_day_in_season() -> int:
	return ((current_day - 1) % DAYS_PER_SEASON) + 1

func get_income_multiplier() -> float:
	match current_season_index:
		1: return 1.2   # Summer bonus
		3: return 0.85  # Winter penalty
		_: return 1.0

func get_display_string() -> String:
	return "Day %d  •  %s  •  Year %d" % [get_day_in_season(), get_season_name(), current_year]

func to_dict() -> Dictionary:
	return {
		"current_day": current_day,
		"current_season_index": current_season_index,
		"current_year": current_year,
		"day_timer": day_timer,
	}

func from_dict(data: Dictionary) -> void:
	current_day = int(data.get("current_day", 1))
	current_season_index = int(data.get("current_season_index", 0))
	current_year = int(data.get("current_year", 1))
	day_timer = float(data.get("day_timer", 0.0))
