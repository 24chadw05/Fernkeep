extends Node

# NewsManager — the city's news log. Every message that used to be a throwaway
# bottom-of-screen toast is archived here so the player can scroll back through
# what happened while they were busy elsewhere.
#
# Read and unread entries are capped independently:
#   • read entries are trimmed to the MAX_READ most recent, so old news you've
#     already seen doesn't pile up;
#   • unread entries accumulate to MAX_UNREAD, so a long absence doesn't quietly
#     drop things you never saw.
# Entries are stored newest-first — that's both the display order and the order
# trimming walks, so the oldest of each kind falls off the end.

const MAX_READ: int = 20
const MAX_UNREAD: int = 100

# Each entry: {"msg": String, "time": int (unix seconds), "urgent": bool, "read": bool}
var entries: Array = []

signal news_added(entry: Dictionary)
signal news_changed()          # list contents shifted (added/trimmed/reset)
signal unread_count_changed(count: int)

# The log subscribes itself rather than being fed by the HUD: autoloads are ready
# before the scene tree, so notifications raised during a manager's _ready (the
# new-game banner, offline earnings) are captured instead of being dropped on the
# floor. The HUD independently listens for the urgent ones to raise a toast.
func _ready() -> void:
	SignalBus.show_notification.connect(func(m): add(m, false))
	SignalBus.show_notification_timed.connect(func(m, _d): add(m, true))

# already_read: for items the player is shown some other way (e.g. the
# welcome-back panel) — archived for reference without bumping the badge.
func add(message: String, urgent: bool = false, already_read: bool = false) -> void:
	var entry := {
		"msg": message,
		"time": int(Time.get_unix_time_from_system()),
		"urgent": urgent,
		"read": already_read,
	}
	entries.push_front(entry)
	_trim()
	emit_signal("news_added", entry)
	emit_signal("news_changed")
	emit_signal("unread_count_changed", get_unread_count())

# Marks a batch read in one pass so the panel emits a single update per scroll
# rather than one per card. Returns true if anything actually changed.
func mark_read(to_mark: Array) -> bool:
	var changed := false
	for entry in to_mark:
		if entry is Dictionary and not entry.get("read", false):
			entry["read"] = true
			changed = true
	if changed:
		_trim()
		emit_signal("news_changed")
		emit_signal("unread_count_changed", get_unread_count())
	return changed

func get_unread_count() -> int:
	var count := 0
	for entry in entries:
		if not entry.get("read", false):
			count += 1
	return count

func has_unread() -> bool:
	return get_unread_count() > 0

# Walks newest-first, keeping a separate running count per kind, and drops an
# entry once its own kind is already full. Read and unread therefore never
# compete for the same budget.
func _trim() -> void:
	var kept: Array = []
	var read_count := 0
	var unread_count := 0
	for entry in entries:
		if entry.get("read", false):
			if read_count >= MAX_READ:
				continue
			read_count += 1
		else:
			if unread_count >= MAX_UNREAD:
				continue
			unread_count += 1
		kept.append(entry)
	entries = kept

# How long ago this entry landed, in the player's terms.
func time_ago(entry: Dictionary) -> String:
	var seconds := int(Time.get_unix_time_from_system()) - int(entry.get("time", 0))
	if seconds < 60:
		return "just now"
	var minutes := seconds / 60
	if minutes < 60:
		return "%d min ago" % minutes
	var hours := minutes / 60
	if hours < 24:
		return "%dh ago" % hours
	return "%dd ago" % (hours / 24)

# ── Save / Load / Reset ───────────────────────────────────────────────────────

func reset() -> void:
	entries.clear()
	emit_signal("news_changed")
	emit_signal("unread_count_changed", 0)

func to_dict() -> Dictionary:
	return {"entries": entries.duplicate(true)}

func from_dict(data: Dictionary) -> void:
	entries.clear()
	for e in data.get("entries", []):
		if e is Dictionary and e.has("msg"):
			entries.append({
				"msg": str(e.get("msg", "")),
				"time": int(e.get("time", 0)),
				"urgent": bool(e.get("urgent", false)),
				"read": bool(e.get("read", false)),
			})
	_trim()
	emit_signal("news_changed")
	emit_signal("unread_count_changed", get_unread_count())
