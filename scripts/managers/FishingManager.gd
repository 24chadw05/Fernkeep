extends Node

# FishingManager — timing-based fishing trips at the river (GDD minigame #2).
# Trips cost a charge (max 3, +1 per game day) and grant several casts.
# Catches land in ResourceManager, which drives fishing_catch recipe unlocks
# (grilled river fish, smoked lake trout, legendary fish pie) and quest goals.

signal charges_changed(charges: int)
signal fish_caught(resource_id: String, amount: int)

const MAX_CHARGES: int = 3
const CASTS_PER_TRIP: int = 5

# Catch table: id, weight, min player level, catch-zone width (0-1), marker speed
const CATCH_TABLE: Array = [
	{"id": "fish",           "weight": 50, "min_level": 1, "zone": 0.30, "speed": 2.2},
	{"id": "river_fish",     "weight": 30, "min_level": 1, "zone": 0.22, "speed": 2.8},
	{"id": "lake_trout",     "weight": 16, "min_level": 4, "zone": 0.14, "speed": 3.4},
	{"id": "legendary_fish", "weight": 3,  "min_level": 8, "zone": 0.07, "speed": 4.2},
]

var charges: int = MAX_CHARGES
var legendary_caught_total: int = 0

func _ready() -> void:
	TimeManager.new_day.connect(_on_new_day)

func _on_new_day(_day: int, _season: String, _year: int) -> void:
	if charges < MAX_CHARGES:
		charges += 1
		emit_signal("charges_changed", charges)

func can_fish() -> bool:
	return charges > 0

# Consume a charge to start a trip. Returns the number of casts (0 = no charge).
func start_trip() -> int:
	if not can_fish():
		return 0
	charges -= 1
	emit_signal("charges_changed", charges)
	ProgressionManager.reward_xp("fishing_trip")
	print("[FishingManager] Trip started — %d casts, %d charges left" % [CASTS_PER_TRIP, charges])
	return CASTS_PER_TRIP

# Roll which fish is on the line for this bite (level-gated, rarity-weighted).
# The Forager's Eye potion sharpens instincts for rare catches too.
func roll_bite() -> Dictionary:
	var level = ProgressionManager.player_level
	var rare_bonus = RecipeManager.get_rare_find_bonus()
	var pool: Array = []
	var total := 0.0
	for entry in CATCH_TABLE:
		if level < int(entry["min_level"]):
			continue
		var weight = float(entry["weight"])
		if entry["id"] in ["lake_trout", "legendary_fish"]:
			weight *= 1.0 + rare_bonus * 2.0
		pool.append([entry, weight])
		total += weight
	var r = randf() * total
	var cumulative := 0.0
	for pair in pool:
		cumulative += pair[1]
		if r <= cumulative:
			return pair[0]
	return CATCH_TABLE[0]

func land_catch(resource_id: String) -> void:
	ResourceManager.add(resource_id, 1.0, "Caught fishing")
	if resource_id == "legendary_fish":
		legendary_caught_total += 1
		ReputationManager.add_reputation(15.0, "Word spreads of a legendary catch!")
	emit_signal("fish_caught", resource_id, 1)

# ── Save / Load / Reset ───────────────────────────────────────────────────────

func reset() -> void:
	charges = MAX_CHARGES
	legendary_caught_total = 0
	emit_signal("charges_changed", charges)

func to_dict() -> Dictionary:
	return {
		"charges": charges,
		"legendary_caught_total": legendary_caught_total,
	}

func from_dict(data: Dictionary) -> void:
	charges = clampi(int(data.get("charges", MAX_CHARGES)), 0, MAX_CHARGES)
	legendary_caught_total = int(data.get("legendary_caught_total", 0))
	emit_signal("charges_changed", charges)
