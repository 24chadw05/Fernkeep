extends Node

# Reputation — the city's renown, the fourth core stat from the GDD.
# Earned from completed quests, high-prestige meals, and sustained high happiness.
# Drives the demand score (better arrivals) alongside happiness.

var reputation: float = 0.0

signal reputation_changed(new_amount: float)
signal title_changed(new_title: String)

# Reputation thresholds → settlement title, in ascending order
const TITLES = [
	[0,    "Unknown Hamlet"],
	[50,   "Quiet Village"],
	[150,  "Rising Town"],
	[400,  "Prosperous Town"],
	[1000, "Renowned City"],
	[2500, "Legendary Kingdom"],
]

func _ready() -> void:
	TimeManager.new_day.connect(_on_new_day)

func add_reputation(amount: float, reason: String = "") -> void:
	if amount == 0.0:
		return
	if amount > 0.0:
		amount *= RecipeManager.get_reputation_gain_multiplier()   # food/potion buffs
	var old_title = get_title()
	reputation = maxf(0.0, reputation + amount)
	emit_signal("reputation_changed", reputation)
	if reason != "":
		print("[Reputation] %+.1f — %s (Total: %.1f)" % [amount, reason, reputation])
	var new_title = get_title()
	if new_title != old_title:
		emit_signal("title_changed", new_title)
		SignalBus.show_notification.emit("Word spreads — your settlement is now a %s!" % new_title)

func get_title() -> String:
	var title = TITLES[0][1]
	for entry in TITLES:
		if reputation >= float(entry[0]):
			title = entry[1]
	return title

func get_next_title_threshold() -> float:
	for entry in TITLES:
		if reputation < float(entry[0]):
			return float(entry[0])
	return -1.0  # already at max title

# Content cities slowly build renown on their own (needs a real population)
func _on_new_day(_day: int, _season: String, _year: int) -> void:
	if CitizenManager.citizens.size() < 3:
		return
	var happiness = CitizenManager.calculate_city_happiness()
	if happiness >= 90.0:
		add_reputation(3.0, "Citizens praise your city")
	elif happiness >= 75.0:
		add_reputation(1.0, "Content citizens spread the word")

func reset() -> void:
	reputation = 0.0
	emit_signal("reputation_changed", reputation)

func to_dict() -> Dictionary:
	return {"reputation": reputation}

func from_dict(data: Dictionary) -> void:
	reputation = float(data.get("reputation", 0.0))
	emit_signal("reputation_changed", reputation)
