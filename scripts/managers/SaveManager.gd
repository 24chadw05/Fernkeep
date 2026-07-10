extends Node

const SLOT_COUNT = 3
const LEGACY_SAVE = "user://fernkeep_save.json"
const SETTINGS_PATH = "user://fernkeep_settings.json"
const CURRENT_VERSION = 7

var active_slot: int = 1
var pending_new_game: bool = false
var last_save_timestamp: int = 0  # unix time of the save we just loaded

var settings: Dictionary = {
	"autosave": true,
	"resolution": "1920x1080",
	"last_slot": 1,
}

func _ready() -> void:
	load_settings()
	active_slot = int(settings.get("last_slot", 1))
	_migrate_legacy_save()
	apply_resolution()

# ── Slot paths ─────────────────────────────────────────────────────────────────

func get_slot_path(slot: int) -> String:
	return "user://fernkeep_slot_%d.json" % slot

func _migrate_legacy_save() -> void:
	if not FileAccess.file_exists(LEGACY_SAVE):
		return
	if FileAccess.file_exists(get_slot_path(1)):
		DirAccess.remove_absolute(LEGACY_SAVE)
		return
	var src = FileAccess.open(LEGACY_SAVE, FileAccess.READ)
	if not src:
		return
	var content = src.get_as_text()
	src.close()
	var dst = FileAccess.open(get_slot_path(1), FileAccess.WRITE)
	if dst:
		dst.store_string(content)
		dst.close()
	DirAccess.remove_absolute(LEGACY_SAVE)
	print("[SaveManager] Migrated legacy save to slot 1.")

# ── Slot info ──────────────────────────────────────────────────────────────────

func has_save(slot: int = -1) -> bool:
	var s = slot if slot > 0 else active_slot
	return FileAccess.file_exists(get_slot_path(s))

func get_slot_info(slot: int) -> Dictionary:
	var path = get_slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"exists": false, "name": "Slot %d" % slot, "timestamp": ""}
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {"exists": false, "name": "Slot %d" % slot, "timestamp": ""}
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		return {"exists": true, "name": "Slot %d" % slot, "timestamp": ""}
	var data: Dictionary = json.get_data()
	var meta: Dictionary = data.get("meta", {})
	var ts = int(data.get("timestamp", 0))
	var ts_str = ""
	if ts > 0:
		var dt = Time.get_datetime_dict_from_unix_time(ts)
		ts_str = "%d/%d/%d %02d:%02d" % [dt.month, dt.day, dt.year, dt.hour, dt.minute]
	return {
		"exists": true,
		"name": meta.get("slot_name", "Slot %d" % slot),
		"timestamp": ts_str,
	}

func set_slot_name(slot: int, name: String) -> void:
	var path = get_slot_path(slot)
	if not FileAccess.file_exists(path):
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return
	file.close()
	var data: Dictionary = json.get_data()
	if not data.has("meta"):
		data["meta"] = {}
	data["meta"]["slot_name"] = name
	var wfile = FileAccess.open(path, FileAccess.WRITE)
	if wfile:
		wfile.store_string(JSON.stringify(data, "\t"))
		wfile.close()

# ── Save / Load / Delete ───────────────────────────────────────────────────────

func save(slot: int = -1) -> void:
	var s = slot if slot > 0 else active_slot
	settings["last_slot"] = s
	save_settings()
	var slot_name = get_slot_info(s).get("name", "Slot %d" % s)
	var data = {
		"version": CURRENT_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
		"meta": {"slot_name": slot_name},
		"economy": {
			"gold": EconomyManager.gold,
			"gold_cap": EconomyManager.gold_cap,
			"total_earned": EconomyManager.total_earned,
			"total_spent": EconomyManager.total_spent,
		},
		"progression": {
			"player_level": ProgressionManager.player_level,
			"current_xp": ProgressionManager.current_xp,
			"xp_to_next_level": ProgressionManager.xp_to_next_level,
			"total_xp_earned": ProgressionManager.total_xp_earned,
			"town_hall_level": ProgressionManager.town_hall_level,
		},
		"time": TimeManager.to_dict(),
		"resources": ResourceManager.to_dict(),
		"market": MarketManager.to_dict(),
		"roads": RoadManager.to_dict(),
		"buildings": BuildingManager.to_array(),
		"citizens": CitizenManager.to_array(),
		"reputation": ReputationManager.to_dict(),
		"recipes": RecipeManager.to_dict(),
		"quests": QuestManager.to_dict(),
	}
	var file = FileAccess.open(get_slot_path(s), FileAccess.WRITE)
	if not file:
		push_error("[SaveManager] Could not write slot %d." % s)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("[SaveManager] Saved slot %d (v%d)." % [s, CURRENT_VERSION])

func load_game(slot: int = -1) -> bool:
	var s = slot if slot > 0 else active_slot
	var path = get_slot_path(s)
	if not FileAccess.file_exists(path):
		return false
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("[SaveManager] Parse error in slot %d." % s)
		delete_slot(s)
		return false

	var data: Dictionary = json.get_data()
	last_save_timestamp = int(data.get("timestamp", 0))
	var version = int(data.get("version", 1))

	if version < 2:
		data["time"] = {}
		data["resources"] = {}
	if version < 4:
		data["market"] = {}
	if version < 5:
		data["roads"] = {}
	if version < 7:
		data["reputation"] = {}
		data["recipes"] = {}
		data["quests"] = {}

	var econ: Dictionary = data.get("economy", {})
	EconomyManager.gold = float(econ.get("gold", 0.0))
	EconomyManager.gold_cap = float(econ.get("gold_cap", 10000.0))
	EconomyManager.total_earned = float(econ.get("total_earned", 0.0))
	EconomyManager.total_spent = float(econ.get("total_spent", 0.0))
	EconomyManager.emit_signal("gold_changed", EconomyManager.gold)

	var prog: Dictionary = data.get("progression", {})
	ProgressionManager.player_level = int(prog.get("player_level", 1))
	ProgressionManager.current_xp = float(prog.get("current_xp", 0.0))
	ProgressionManager.xp_to_next_level = float(prog.get("xp_to_next_level", 100.0))
	ProgressionManager.total_xp_earned = float(prog.get("total_xp_earned", 0.0))
	ProgressionManager.town_hall_level = int(prog.get("town_hall_level", 1))

	TimeManager.from_dict(data.get("time", {}))
	ResourceManager.from_dict(data.get("resources", {}))
	MarketManager.from_dict(data.get("market", {}))
	RoadManager.from_dict(data.get("roads", {}))
	BuildingManager.from_array(data.get("buildings", []))
	CitizenManager.from_array(data.get("citizens", []))
	ReputationManager.from_dict(data.get("reputation", {}))
	QuestManager.from_dict(data.get("quests", {}))
	RecipeManager.from_dict(data.get("recipes", {}))

	print("[SaveManager] Loaded slot %d (v%d → v%d)." % [s, version, CURRENT_VERSION])
	return true

func delete_slot(slot: int) -> void:
	var path = get_slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		print("[SaveManager] Deleted slot %d." % slot)

func delete_save() -> void:
	delete_slot(active_slot)

# ── Settings ───────────────────────────────────────────────────────────────────

func save_settings() -> void:
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify(settings, "\t"))
	file.close()

func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		settings.merge(json.get_data(), true)
	file.close()

func apply_resolution() -> void:
	var size: Vector2i
	match settings.get("resolution", "1920x1080"):
		"2560x1440": size = Vector2i(2560, 1440)
		"1280x720":  size = Vector2i(1280, 720)
		_:           size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(size)
