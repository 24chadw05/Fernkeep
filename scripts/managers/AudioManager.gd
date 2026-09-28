extends Node

# AudioManager — music and sound effects. The audio itself is synthesized by
# tools/audio/generate.py into assets/audio/, in one shared "voice" (lute,
# flute, bells, frame drum) the way tools/art gives the textures one look.
#
# Most sounds are wired here to signals the game already emits, so gameplay
# code rarely has to call play() itself. Every Button in the game clicks
# automatically (see _on_node_added).

const MUSIC_PATH := "res://assets/audio/music/hearth_and_hamlet.wav"
const SFX_DIR := "res://assets/audio/sfx/"
const SFX_NAMES: Array = [
	"click", "open", "close", "build", "upgrade", "coin", "arrival", "notify",
	"error", "level_up", "pop", "splash", "catch", "chop", "sizzle",
	"cook_success", "cook_fail",
]
const VOICES: int = 8            # simultaneous effects before the oldest is reused
const MUSIC_FADE_IN: float = 3.0

var _sfx: Dictionary = {}        # name → AudioStream
var _players: Array = []
var _next_player: int = 0
var _music: AudioStreamPlayer = null
var _quiet_until_msec: int = 0
var _last_played: Dictionary = {}  # name → msec, so bursts of one event don't stack
var _last_pending: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	apply_volumes()

	for n in SFX_NAMES:
		var path = SFX_DIR + n + ".wav"
		if ResourceLoader.exists(path):
			_sfx[n] = load(path)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)

	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_start_music()

	# Every button clicks — including ones panels build at runtime.
	get_tree().node_added.connect(_on_node_added)

	# Gameplay sounds, hung off signals the game already emits.
	BuildingManager.building_placed.connect(func(_b): play("build"))
	BuildingManager.building_upgraded.connect(func(_b): play("upgrade"))
	EconomyManager.day_settled.connect(func(_r, _w, payout): if payout >= 1.0: play("coin"))
	ProgressionManager.level_up.connect(func(_l, _u): play("level_up"))
	CitizenManager.arrival_queue_changed.connect(_on_arrival_queue_changed)
	SignalBus.show_notification_timed.connect(func(_m, _d): play("error"))
	ForageManager.foraged.connect(func(_r, _a): play("pop"))
	_hook_panel_signals()

# ── public API ────────────────────────────────────────────────────────────────

# Play a named effect. pitch_jitter varies repeats (clicks, pops) so they don't
# sound machine-gunned; min_gap_ms drops a repeat of the same sound fired within
# that window (e.g. a batch of buildings placed in one frame at load).
func play(sound: String, pitch_jitter: float = 0.04, min_gap_ms: int = 60) -> void:
	if Time.get_ticks_msec() < _quiet_until_msec:
		return
	var stream = _sfx.get(sound)
	if stream == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(sound, -100000)) < min_gap_ms:
		return
	_last_played[sound] = now
	var p: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % VOICES
	p.stream = stream
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()

# Silence effects for a moment — GameManager calls this while it builds the
# starting city or rebuilds a loaded one, so the player isn't greeted by a
# volley of construction thumps.
func hush(seconds: float) -> void:
	_quiet_until_msec = Time.get_ticks_msec() + int(seconds * 1000.0)

# Settings are stored as linear 0..1 in SaveManager.settings.
func apply_volumes() -> void:
	_set_bus_linear("Music", float(SaveManager.settings.get("music_volume", 0.6)))
	_set_bus_linear("SFX", float(SaveManager.settings.get("sfx_volume", 0.8)))

# ── internals ─────────────────────────────────────────────────────────────────

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

func _set_bus_linear(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	linear = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))

func _start_music() -> void:
	if not ResourceLoader.exists(MUSIC_PATH):
		return
	var stream = load(MUSIC_PATH)
	# The WAV is authored as a seamless loop; make the imported stream loop it
	# end-to-end regardless of the import defaults.
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_music.stream = stream
	_music.volume_db = -40.0
	_music.play()
	create_tween().tween_property(_music, "volume_db", 0.0, MUSIC_FADE_IN)

func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta("_audio_hooked"):
		node.set_meta("_audio_hooked", true)
		node.pressed.connect(func(): play("click", 0.06, 30))

func _on_arrival_queue_changed() -> void:
	# Only ring for a new face at the gates, not when the queue shrinks.
	var n := CitizenManager.get_pending_count()
	if n > _last_pending:
		play("arrival")
	_last_pending = n

# Every SignalBus "open_*" signal is a panel opening; give them all the same
# soft two-note pluck without hand-wiring twenty-odd signals. unbind() drops
# whatever arguments each signal carries.
func _hook_panel_signals() -> void:
	for sig in SignalBus.get_signal_list():
		var sig_name: String = sig["name"]
		if sig_name.begins_with("open_"):
			var cb := func(): play("open", 0.02)
			var n_args: int = sig["args"].size()
			# unbind(0) is an error in Godot, so argument-less signals connect as-is
			SignalBus.connect(sig_name, cb.unbind(n_args) if n_args > 0 else cb)
	SignalBus.close_all_panels.connect(func(): play("close", 0.02, 200))
