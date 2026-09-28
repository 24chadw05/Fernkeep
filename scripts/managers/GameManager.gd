extends Node2D

const TILE_SIZE: int = 64

var city_happiness: float = 100.0
var _tick_acc: float = 0.0
var _autosave_acc: float = 0.0
const AUTOSAVE_INTERVAL: float = 300.0  # every 5 minutes

# Travellers: passers-through whose numbers scale with reputation
const TRAVELLER_SCENE: String = "res://scenes/npcs/Traveller.tscn"
const MAX_TRAVELLERS: int = 8
const TRAVELLER_CHECK_INTERVAL: float = 4.0  # how often we top up the road
var _traveller_acc: float = 0.0

# Unix time the app was backgrounded, so the elapsed time can be credited as
# offline earnings when it comes back (0 = not currently backgrounded).
var _paused_at: int = 0

# Every way a session can end has to save. On desktop that's the close button
# (and ESC > Quit). On iOS/Android the OS rarely sends a close request — it
# backgrounds the app and later kills it silently — so pausing/losing focus is
# the last reliable moment to write the save.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST:
			SaveManager.save()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED:
			SaveManager.save()
			_paused_at = int(Time.get_unix_time_from_system())
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			SaveManager.save(-1, true)
		NOTIFICATION_APPLICATION_RESUMED:
			# A suspended app runs no ticks, so without this a player who puts the
			# phone down for an hour and comes back (without the OS killing the
			# app) would earn nothing — the GDD's "your city keeps earning".
			if _paused_at > 0:
				_calculate_offline_earnings(_paused_at)
				_paused_at = 0

func _ready() -> void:
	get_tree().set_auto_accept_quit(false)  # intercept quit so we can auto-save first
	AudioManager.hush(1.5)  # no volley of build thumps while the city is laid out

	get_viewport().physics_object_picking = true

	print("[GameManager] Fernkeep starting...")
	TimeManager.connect("new_day", _on_new_day)
	BuildingManager.connect("building_placed", _on_building_placed)
	BuildingManager.connect("building_removed", _on_building_removed)
	BuildingManager.connect("building_upgraded", _on_building_upgraded)
	CitizenManager.connect("citizen_arrived", _on_citizen_arrived)
	CitizenManager.connect("city_happiness_updated", func(h): city_happiness = h)
	RoadManager.connect("road_painted", _on_road_painted)
	RoadManager.connect("road_erased", _on_road_erased)

	var build_grid = get_node_or_null("BuildGrid")
	if build_grid:
		build_grid.building_moved.connect(_on_building_moved)

	SignalBus.prestige_requested.connect(_on_prestige_requested)

	if SaveManager.pending_new_game:
		SaveManager.pending_new_game = false
		PrestigeManager.reset()   # a true new game wipes Renown too
		_reset_managers()
		_start_fresh()
		TutorialManager.start()   # only a true new game — not prestige, not a load
		return

	if SaveManager.has_save():
		if SaveManager.load_game():
			_rebuild_visuals_from_save()
			_calculate_offline_earnings(SaveManager.last_save_timestamp)
			# Baseline income scales with happiness — start from the loaded
			# city's real value instead of 100% until the next day tick
			city_happiness = CitizenManager.calculate_city_happiness()
			return

	# No save at all: a first-ever launch — exactly who the tutorial is for.
	_start_fresh()
	TutorialManager.start()

func _reset_managers() -> void:
	EconomyManager.gold          = 0.0
	EconomyManager.total_earned  = 0.0
	EconomyManager.total_spent   = 0.0
	EconomyManager.daily_income  = 0.0
	EconomyManager.daily_expenses = 0.0
	EconomyManager.pending_revenue = 0.0
	ProgressionManager.player_level     = 1
	ProgressionManager.current_xp       = 0.0
	ProgressionManager.xp_to_next_level = 100.0
	ProgressionManager.total_xp_earned  = 0.0
	ProgressionManager.town_hall_level  = 1
	BuildingManager.from_array([])
	CitizenManager.from_array([])
	ResourceManager.reset()
	RoadManager.reset()
	MarketManager.reset()
	TimeManager.from_dict({})
	ReputationManager.reset()
	QuestManager.reset()
	RecipeManager.reset()
	ForageManager.reset()
	FishingManager.reset()
	CaravanManager.reset()
	TradePortManager.reset()
	GuildHallManager.reset()
	FestivalManager.reset()
	NewsManager.reset()
	CookingManager.reset()
	TutorialManager.reset()

# Candidate plots for scenario buildings — spaced to clear the town hall and
# fit up to 5x4 footprints. Filled in order; invalid/overlapping ones skipped.
const _START_PLOTS: Array = [
	Vector2i(-14, 1), Vector2i(-8, 1), Vector2i(6, 1), Vector2i(12, 1),
	Vector2i(-14, 7), Vector2i(-8, 7), Vector2i(6, 7), Vector2i(12, 7),
]

func _start_fresh() -> void:
	var scenario = PrestigeManager.get_scenario(PrestigeManager.start_scenario)

	# Starting purse and stores for this scenario
	EconomyManager.add_gold(float(scenario.get("gold", 500.0)), "Starting gold")
	for res_id in scenario.get("resources", {}):
		ResourceManager.add(res_id, float(scenario["resources"][res_id]), "Starting stores")

	var bg = get_node_or_null("BuildGrid")

	var th = BuildingManager.place_building_free("town_hall", Vector2i.ZERO)
	if th and bg:
		bg.occupy_cells(th.grid_origin, th.get_size(), th.id)

	# A starter dirt road running across the settlement
	for dx in range(-16, 18):
		RoadManager.paint(Vector2i(dx, 5), "dirt")

	# Signature buildings for the chosen start, dropped into the first free plots
	var plot_idx = 0
	for building_id in scenario.get("buildings", []):
		while plot_idx < _START_PLOTS.size():
			var origin: Vector2i = _START_PLOTS[plot_idx]
			plot_idx += 1
			var bsize = _building_footprint(building_id)
			if bg == null or bg.is_footprint_valid(origin, bsize):
				var b = BuildingManager.place_building_free(building_id, origin)
				if b and bg:
					bg.occupy_cells(b.grid_origin, b.get_size(), b.id)
				break

	if PrestigeManager.prestige_count > 0:
		SignalBus.show_notification.emit("Founded anew: %s  (Renown %.0f, +%.0f%% income)" % [
			scenario.get("name", "New City"), PrestigeManager.renown,
			(PrestigeManager.get_income_multiplier() - 1.0) * 100.0
		])
	print("[GameManager] New game started (%s)." % PrestigeManager.start_scenario)

func _building_footprint(building_id: String) -> Vector2i:
	var s: Array = DataManager.get_building(building_id).get("size", [1, 1])
	return Vector2i(int(s[0]), int(s[1]))

# Prestige: wipe the city but KEEP prestige data (Renown/count already banked),
# then rebuild from the chosen scenario.
func _on_prestige_requested() -> void:
	AudioManager.hush(1.5)
	SignalBus.close_all_panels.emit()
	_clear_world_for_prestige()
	_reset_managers()
	_start_fresh()
	city_happiness = CitizenManager.calculate_city_happiness()
	SaveManager.save()

# Tear down every visual node and grid/road occupancy from the old city so the
# fresh start doesn't collide with or leave behind the previous run.
func _clear_world_for_prestige() -> void:
	for container_name in ["Buildings", "NPCs", "Roads", "Travellers"]:
		var container = get_node_or_null(container_name)
		if container:
			for child in container.get_children():
				# Detach immediately so the fresh city can reuse node names
				# (building nodes are named by id, which resets to b_0)
				container.remove_child(child)
				child.queue_free()
	var build_grid = get_node_or_null("BuildGrid")
	if build_grid:
		build_grid.grid.clear()
	# Road data itself is cleared by _reset_managers() right after this.


func _process(delta: float) -> void:
	_tick_acc += delta
	while _tick_acc >= 1.0:
		_tick_acc -= 1.0
		_income_tick()

	_autosave_acc += delta
	if SaveManager.settings.get("autosave", true) and _autosave_acc >= AUTOSAVE_INTERVAL:
		_autosave_acc = 0.0
		# No notification: every 5 minutes it filled the news log with noise.
		# The HUD's save button flashes instead (SaveManager.saved).
		SaveManager.save(-1, true)

	_traveller_acc += delta
	if _traveller_acc >= TRAVELLER_CHECK_INTERVAL:
		_traveller_acc = 0.0
		_update_travellers()

func _income_tick() -> void:
	var happiness_mult = city_happiness / 100.0
	var season_mult = TimeManager.get_income_multiplier()
	# Town income joins the same pot as business revenue and settles with it.
	EconomyManager.accrue_revenue(
		EconomyManager.BASELINE_GOLD_PER_SECOND * happiness_mult * season_mult
		* RecipeManager.get_income_multiplier() * PrestigeManager.get_income_multiplier()
	)
	BuildingManager.collect_income_tick(1.0)
	BuildingManager.collect_resource_tick(1.0)

func _on_new_day(day: int, season: String, year: int) -> void:
	city_happiness = CitizenManager.calculate_city_happiness()
	CitizenManager.update_demand_score()

	# Payday. The day's takings move into the purse, CitizenManager's ledger pays
	# every wage out of it, and whatever survives is banked as one lump sum.
	# EconomyManager.on_new_day() has to come last so the daily summary it prints
	# includes the wages and rent that were settled in between.
	EconomyManager.begin_day_settlement()
	CitizenManager.on_new_day()
	_announce_payout(EconomyManager.finish_day_settlement())

	EconomyManager.on_new_day()
	ProgressionManager.reward_xp("day_survived")
	print("[GameManager] Day %d — %s — Year %d  |  Happiness: %.1f%%  Demand: %.1f" % [
		day, season, year, city_happiness, CitizenManager.demand_score
	])

# A routine payday is shown on the HUD (it pops the banked amount beside the gold
# counter via EconomyManager.day_settled) rather than logged: one entry per game
# day would be 60 news items an hour. Only a day the treasury had to prop up is
# worth a news entry and a toast.
func _announce_payout(books: Dictionary) -> void:
	var revenue: float = books.get("revenue", 0.0)
	var wages: float = books.get("wages", 0.0)
	if wages > revenue + 0.5:
		SignalBus.show_notification_timed.emit(
			"Payday: %.0f earned, %.0f in wages — the treasury covered the %.0f shortfall." % [
				revenue, wages, wages - revenue
			], 3.0
		)

func _on_building_removed(building: PlacedBuilding) -> void:
	var container = get_node_or_null("Buildings")
	if container:
		var node = container.get_node_or_null(building.id)
		if node:
			node.queue_free()
	var build_grid = get_node_or_null("BuildGrid")
	if build_grid:
		build_grid.free_cells(building.grid_origin, building.get_size())

func _on_building_moved(building: PlacedBuilding, _old_origin: Vector2i) -> void:
	var container = get_node_or_null("Buildings")
	if container:
		var node = container.get_node_or_null(building.id)
		if node:
			node.position = Vector2(building.grid_origin.x * TILE_SIZE, building.grid_origin.y * TILE_SIZE)

func _on_building_placed(building: PlacedBuilding) -> void:
	_spawn_building_node(building)
	if building.building_id == "house":
		CitizenManager.reset_wage_pressure()

# Map expansion: taking a building to its max level (global 9) masters it and
# permanently grants the city an extra building plot (BuildingManager counts them).
func _on_building_upgraded(building: PlacedBuilding) -> void:
	_refresh_building_node(building)
	if building.building_id != "town_hall" and building.get_global_level() >= BuildingManager.MAX_GLOBAL_LEVEL:
		SignalBus.show_notification.emit(
			"%s mastered! The city expands — +1 building plot." % building.get_display_name()
		)

# Rebuild a building's map node so sprite/name changes (specialization,
# future tier art) show up immediately.
func _refresh_building_node(building: PlacedBuilding) -> void:
	var container = get_node_or_null("Buildings")
	if not container:
		return
	var node = container.get_node_or_null(NodePath(building.id))
	if node:
		node.name = building.id + "_stale"
		node.queue_free()
	_spawn_building_node(building)

func _on_citizen_arrived(npc: NPC) -> void:
	_spawn_citizen_node(npc)

# ── Road visuals ──────────────────────────────────────────────────────────────

func _on_road_painted(cell: Vector2i, road_type: String) -> void:
	_spawn_road_node(cell, road_type)

func _on_road_erased(cell: Vector2i) -> void:
	_remove_road_node(cell)

func _spawn_road_node(cell: Vector2i, road_type: String) -> void:
	var container := get_node_or_null("Roads")
	if not container:
		return
	var node_name := "road_%d_%d" % [cell.x, cell.y]
	if container.has_node(node_name):
		return  # already exists (e.g. double-paint)

	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.centered = false
	var tex: Texture2D = load("res://assets/roads/%s.png" % road_type)
	if tex:
		sprite.texture = tex
		var tex_size := tex.get_size()
		if tex_size.x > 0 and tex_size.y > 0:
			sprite.scale = Vector2(float(TILE_SIZE) / tex_size.x, float(TILE_SIZE) / tex_size.y)
	else:
		# Fallback: colored rect drawn via CanvasItem if texture missing
		push_warning("[GameManager] Road texture not found: %s" % road_type)
	sprite.position = Vector2(cell.x * TILE_SIZE, cell.y * TILE_SIZE)
	container.add_child(sprite)

func _remove_road_node(cell: Vector2i) -> void:
	var container := get_node_or_null("Roads")
	if not container:
		return
	var node := container.get_node_or_null("road_%d_%d" % [cell.x, cell.y])
	if node:
		node.queue_free()

# ── Building / citizen visuals ────────────────────────────────────────────────

func _spawn_building_node(building: PlacedBuilding) -> void:
	var container = get_node_or_null("Buildings")
	if not container:
		return
	var scene = load("res://scenes/buildings/BuildingNode.tscn")
	if not scene:
		push_error("[GameManager] BuildingNode.tscn not found")
		return
	var node: BuildingNode = scene.instantiate()
	node.name = building.id
	node.position = Vector2(building.grid_origin.x * TILE_SIZE, building.grid_origin.y * TILE_SIZE)
	container.add_child(node)
	node.setup(building)

func _spawn_citizen_node(npc: NPC) -> void:
	var container = get_node_or_null("NPCs")
	if not container:
		return
	var scene = load("res://scenes/npcs/Citizen.tscn")
	if not scene:
		return
	var citizen = scene.instantiate()
	citizen.position = Vector2(randf_range(-300, 300), randf_range(-300, 300))
	if citizen.has_method("setup"):
		citizen.setup(npc)
	container.add_child(citizen)

# ── Travellers ────────────────────────────────────────────────────────────────

# A famous city draws more visitors: the number of travellers on the roads at
# once scales with reputation. They only appear once there are roads to travel.
func _desired_traveller_count() -> int:
	if not RoadManager.has_roads():
		return 0
	# One or two wanderers even in a small hamlet, scaling up with the city's
	# fame — a renowned kingdom sees a steady stream of visitors on its roads.
	return clampi(1 + int(ReputationManager.reputation / 250.0), 1, MAX_TRAVELLERS)

func _update_travellers() -> void:
	var container := get_node_or_null("Travellers")
	if not container:
		return
	var desired := _desired_traveller_count()
	# Travellers despawn on their own after their visit, so we only ever top up —
	# one at a time, so they trickle in rather than pop in all at once.
	if container.get_child_count() < desired:
		_spawn_traveller(container)

func _spawn_traveller(container: Node) -> void:
	var start = RoadManager.random_road_cell()
	if start == null:
		return
	var scene = load(TRAVELLER_SCENE)
	if not scene:
		return
	var trav = scene.instantiate()
	trav.position = Vector2(start.x * TILE_SIZE + TILE_SIZE / 2.0, start.y * TILE_SIZE + TILE_SIZE / 2.0)
	if trav.has_method("setup"):
		trav.setup()
	container.add_child(trav)

# ── Offline earnings (GDD: Idle System) ──────────────────────────────────────
# "Offline earnings accrue up to an 8-hour cap (upgradeable to 24h)" — the cap
# grows 2h per Town Hall level, from 8h at level 1 to 24h at level 9.
# "Active play provides roughly 2-3x the income of pure idle" — offline time pays
# OFFLINE_RATE of the live rate, so a player who's present earns 2x from
# buildings alone before minigames, trading and quests are counted.
const OFFLINE_BASE_HOURS: float = 8.0
const OFFLINE_HOURS_PER_TH_LEVEL: float = 2.0
const OFFLINE_RATE: float = 0.5

func get_offline_cap_hours() -> float:
	var th_level := 1
	for b in BuildingManager.get_buildings_of_type("town_hall"):
		th_level = maxi(th_level, b.get_global_level())
	return OFFLINE_BASE_HOURS + OFFLINE_HOURS_PER_TH_LEVEL * float(th_level - 1)

func _calculate_offline_earnings(save_timestamp: int) -> void:
	if save_timestamp <= 0:
		return
	var delta = Time.get_unix_time_from_system() - float(save_timestamp)
	if delta < 60.0:
		return  # less than a minute — not worth computing
	# Deliveries don't care about the idle cap — the carter arrives regardless.
	MarketManager.advance_orders(delta)
	var cap_hours := get_offline_cap_hours()
	var capped_seconds = minf(delta, cap_hours * 3600.0)
	var offline_minutes = capped_seconds / 60.0

	# Sum building income at saved productivity (staff happiness persists in the save),
	# with the same season/potion multipliers a live tick would apply
	var income_per_minute = 0.0
	for b in BuildingManager.placed_buildings:
		if b.is_active:
			income_per_minute += BuildingManager.get_live_income_per_minute(b)
	income_per_minute *= RecipeManager.get_income_multiplier() * TimeManager.get_income_multiplier() * PrestigeManager.get_income_multiplier()

	# One offline minute is one game day, and a day's revenue settles net of the
	# wage bill — so offline earnings are netted the same way, then paid at the
	# idle rate.
	var wage_bill_per_day = 0.0
	for c in CitizenManager.citizens:
		if c.is_employed:
			wage_bill_per_day += c.daily_wage
	var net_per_day = maxf(income_per_minute - wage_bill_per_day, 0.0)
	var offline_gold = net_per_day * offline_minutes * OFFLINE_RATE
	var banked_gold = EconomyManager.add_gold(offline_gold, "Offline earnings") if offline_gold >= 1.0 else 0.0

	# Resource production accrues offline too, at the same idle rate
	var resources_gained := _accrue_offline_resources(offline_minutes * OFFLINE_RATE)

	if banked_gold >= 1.0 or not resources_gained.is_empty():
		# The HUD and the welcome panel may not exist yet on a cold start — defer.
		call_deferred("_show_welcome_back", {
			"gold": banked_gold,
			"resources": resources_gained,
			"seconds_away": delta,
			"seconds_counted": capped_seconds,
			"cap_hours": cap_hours,
		})

# Runs every producing building's output over the offline window, adding the
# resources straight into ResourceManager (which persists on the next save).
func _accrue_offline_resources(offline_minutes: float) -> Dictionary:
	var gained: Dictionary = {}
	for b in BuildingManager.placed_buildings:
		if not b.is_active or b.assigned_staff.is_empty():
			continue
		var production: Dictionary = b.get_level_data().get("resource_production", {})
		if production.is_empty():
			continue
		var yield_mult = BuildingManager.get_yield_multiplier(b)
		for resource_id in production:
			var amount = float(production[resource_id]) * b.assigned_staff.size() * offline_minutes * yield_mult
			if amount <= 0.0:
				continue
			ResourceManager.add(resource_id, amount, "Offline: " + b.get_display_name())
			gained[resource_id] = gained.get(resource_id, 0.0) + amount
	return gained

# GDD core loop, stage 1 ("Return & collect"): a proper welcome-back moment with
# a collect button, not a line that lands silently in the news log. The summary
# is also archived to the news log so it can be looked up later.
func _show_welcome_back(summary: Dictionary) -> void:
	var parts: Array = []
	if summary.gold >= 1.0:
		parts.append("%.0f gold" % summary.gold)
	for res_id in summary.resources:
		parts.append("%d %s" % [int(summary.resources[res_id]), ResourceManager.get_item_label(res_id)])
	if parts.is_empty():
		return
	NewsManager.add("Welcome back! Collected %s while you were away." % _join_readable(parts), false, true)
	SignalBus.show_welcome_back.emit(summary)

func _join_readable(parts: Array) -> String:
	if parts.size() <= 1:
		return "".join(PackedStringArray(parts))
	if parts.size() == 2:
		return "%s and %s" % [parts[0], parts[1]]
	var head: Array = parts.slice(0, parts.size() - 1)
	return "%s, and %s" % [", ".join(PackedStringArray(head)), parts[parts.size() - 1]]

func _rebuild_visuals_from_save() -> void:
	var build_grid = get_node_or_null("BuildGrid")
	for building in BuildingManager.get_all_buildings():
		_spawn_building_node(building)
		if build_grid:
			build_grid.occupy_cells(building.grid_origin, building.get_size(), building.id)
	for npc in CitizenManager.citizens:
		_spawn_citizen_node(npc)
	for cell in RoadManager.road_cells:
		_spawn_road_node(cell, RoadManager.road_cells[cell])
	print("[GameManager] Visuals rebuilt from save.")
