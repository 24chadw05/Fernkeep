extends Node

const SLOT_COUNT = 3
const LEGACY_SAVE = "user://fernkeep_save.json"
const SETTINGS_PATH = "user://fernkeep_settings.json"
const CURRENT_VERSION = 18

var active_slot: int = 1
var pending_new_game: bool = false

signal game_loaded()
signal saved(slot: int, is_autosave: bool)
var last_save_timestamp: int = 0  # unix time of the save we just loaded

# Camera view from the last load. The camera lives in the scene, not here, so it
# applies this itself when game_loaded fires (see CameraController).
var camera_state: Dictionary = {}

var settings: Dictionary = {
	"autosave": true,
	"resolution": "1920x1080",
	"last_slot": 1,
	"music_volume": 0.6,   # linear 0..1, applied by AudioManager
	"sfx_volume": 0.8,
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

# A slot counts as saved if either the main file or its backup exists: if the
# game died between the two renames in _write_atomically, only the .bak is left,
# and treating that as "empty" would start a new city over the player's save.
func has_save(slot: int = -1) -> bool:
	var s = slot if slot > 0 else active_slot
	var path = get_slot_path(s)
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")

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
	_write_atomically(path, JSON.stringify(data, "\t"))

# ── Save / Load / Delete ───────────────────────────────────────────────────────

func save(slot: int = -1, is_autosave: bool = false) -> void:
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
			"total_earned": EconomyManager.total_earned,
			"total_spent": EconomyManager.total_spent,
			"daily_income": EconomyManager.daily_income,
			"daily_expenses": EconomyManager.daily_expenses,
			"pending_revenue": EconomyManager.pending_revenue,
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
		"pending_arrivals": CitizenManager.pending_to_array(),
		"citizen_state": CitizenManager.state_to_dict(),
		"camera": _capture_camera(),
		"reputation": ReputationManager.to_dict(),
		"recipes": RecipeManager.to_dict(),
		"quests": QuestManager.to_dict(),
		"forage": ForageManager.to_dict(),
		"fishing": FishingManager.to_dict(),
		"caravan": CaravanManager.to_dict(),
		"trade_port": TradePortManager.to_dict(),
		"prestige": PrestigeManager.to_dict(),
		"guild_hall": GuildHallManager.to_dict(),
		"festival": FestivalManager.to_dict(),
		"news": NewsManager.to_dict(),
		"cooking": CookingManager.to_dict(),
		"tutorial": TutorialManager.to_dict(),
	}
	if _write_atomically(get_slot_path(s), JSON.stringify(data, "\t")):
		print("[SaveManager] Saved slot %d (v%d)." % [s, CURRENT_VERSION])
		emit_signal("saved", s, is_autosave)

# Crash-safe write. The new save goes to a .tmp file first and only replaces the
# real one once it's fully on disk; the previous good save is kept as .bak. A
# power loss or crash mid-write therefore leaves the old save intact instead of a
# half-written file that fails to parse on the next launch.
func _write_atomically(path: String, text: String) -> bool:
	var tmp = path + ".tmp"
	var file = FileAccess.open(tmp, FileAccess.WRITE)
	if not file:
		push_error("[SaveManager] Could not open %s for writing (error %d)." % [tmp, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.flush()
	var write_err = file.get_error()
	file.close()
	if write_err != OK:
		push_error("[SaveManager] Write failed for %s (error %d); keeping previous save." % [tmp, write_err])
		DirAccess.remove_absolute(tmp)
		return false
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path + ".bak")
		DirAccess.rename_absolute(path, path + ".bak")
	var err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("[SaveManager] Could not move %s into place (error %d)." % [tmp, err])
		return false
	return true

func _capture_camera() -> Dictionary:
	var cam = get_tree().get_first_node_in_group("save_camera") if get_tree() else null
	if cam == null:
		return {}
	return {"x": cam.position.x, "y": cam.position.y, "zoom": cam.zoom.x}

func load_game(slot: int = -1) -> bool:
	var s = slot if slot > 0 else active_slot
	var path = get_slot_path(s)
	var data = _read_save(path)
	if data == null:
		# The main file is missing or unreadable. Fall back to the previous good
		# save rather than throwing the player's city away. The damaged file is
		# set aside (not deleted) so it can still be inspected or recovered.
		data = _read_save(path + ".bak")
		if data == null:
			return false
		if FileAccess.file_exists(path):
			DirAccess.rename_absolute(path, path + ".corrupt")
		push_warning("[SaveManager] Slot %d was damaged; restored from its backup." % s)
		call_deferred("_notify_restored_from_backup")
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
	if version < 8:
		data["forage"] = {}
	if version < 9:
		data["fishing"] = {}
	if version < 10:
		data["caravan"] = {}
	if version < 11:
		data["pending_arrivals"] = []
	if version < 12:
		data["trade_port"] = {}
	if version < 13:
		data["prestige"] = {}
	if version < 14:
		data["guild_hall"] = {}
	if version < 15:
		data["festival"] = {}
	if version < 16:
		data["news"] = {}
	if version < 17:
		data["citizen_state"] = {}
		data["camera"] = {}
	if version < 18:
		data["cooking"] = {}
		data["tutorial"] = {}   # existing players never see the tutorial

	var econ: Dictionary = data.get("economy", {})
	EconomyManager.gold = float(econ.get("gold", 0.0))
	EconomyManager.total_earned = float(econ.get("total_earned", 0.0))
	EconomyManager.total_spent = float(econ.get("total_spent", 0.0))
	EconomyManager.daily_income = float(econ.get("daily_income", 0.0))
	EconomyManager.daily_expenses = float(econ.get("daily_expenses", 0.0))
	# Pre-v16 saves predate daily settlement and simply start the day empty.
	EconomyManager.pending_revenue = float(econ.get("pending_revenue", 0.0))
	EconomyManager.emit_signal("gold_changed", EconomyManager.gold)
	EconomyManager.emit_signal("pending_revenue_changed", EconomyManager.pending_revenue)

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
	CitizenManager.pending_from_array(data.get("pending_arrivals", []))
	CitizenManager.state_from_dict(data.get("citizen_state", {}))
	camera_state = data.get("camera", {})
	ReputationManager.from_dict(data.get("reputation", {}))
	QuestManager.from_dict(data.get("quests", {}))
	RecipeManager.from_dict(data.get("recipes", {}))
	ForageManager.from_dict(data.get("forage", {}))
	FishingManager.from_dict(data.get("fishing", {}))
	CaravanManager.from_dict(data.get("caravan", {}))
	TradePortManager.from_dict(data.get("trade_port", {}))
	PrestigeManager.from_dict(data.get("prestige", {}))
	GuildHallManager.from_dict(data.get("guild_hall", {}))
	FestivalManager.from_dict(data.get("festival", {}))
	NewsManager.from_dict(data.get("news", {}))
	CookingManager.from_dict(data.get("cooking", {}))
	TutorialManager.from_dict(data.get("tutorial", {}))

	print("[SaveManager] Loaded slot %d (v%d → v%d)." % [s, version, CURRENT_VERSION])
	emit_signal("game_loaded")
	return true

# Returns the parsed save Dictionary, or null if the file is missing/unreadable/
# not a save. Never deletes anything.
func _read_save(path: String):
	if not FileAccess.file_exists(path):
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK or not (json.get_data() is Dictionary):
		push_error("[SaveManager] Could not parse %s (line %d: %s)." % [
			path, json.get_error_line(), json.get_error_message()
		])
		return null
	return json.get_data()

func _notify_restored_from_backup() -> void:
	SignalBus.show_notification_timed.emit(
		"Your save file was damaged — restored from the previous save.", 4.0
	)

func delete_slot(slot: int) -> void:
	var path = get_slot_path(slot)
	var removed := false
	for suffix in ["", ".bak", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
			removed = true
	if removed:
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
