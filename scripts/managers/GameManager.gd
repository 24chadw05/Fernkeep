extends Node2D

const TILE_SIZE: int = 64

var city_happiness: float = 100.0
var _tick_acc: float = 0.0
var _autosave_acc: float = 0.0
const AUTOSAVE_INTERVAL: float = 300.0  # every 5 minutes

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveManager.save()
		get_tree().quit()

func _ready() -> void:
	get_tree().set_auto_accept_quit(false)  # intercept quit so we can auto-save first

	get_viewport().physics_object_picking = true

	print("[GameManager] Fernkeep starting...")
	TimeManager.connect("new_day", _on_new_day)
	BuildingManager.connect("building_placed", _on_building_placed)
	BuildingManager.connect("building_removed", _on_building_removed)
	CitizenManager.connect("citizen_arrived", _on_citizen_arrived)
	CitizenManager.connect("city_happiness_updated", func(h): city_happiness = h)
	RoadManager.connect("road_painted", _on_road_painted)
	RoadManager.connect("road_erased", _on_road_erased)

	var build_grid = get_node_or_null("BuildGrid")
	if build_grid:
		build_grid.building_moved.connect(_on_building_moved)

	if SaveManager.pending_new_game:
		SaveManager.pending_new_game = false
		_reset_managers()
		_start_fresh()
		return

	if SaveManager.has_save():
		if SaveManager.load_game():
			_rebuild_visuals_from_save()
			_calculate_offline_earnings(SaveManager.last_save_timestamp)
			return

	_start_fresh()

func _reset_managers() -> void:
	EconomyManager.gold          = 0.0
	EconomyManager.gold_cap      = 10000.0
	EconomyManager.total_earned  = 0.0
	EconomyManager.total_spent   = 0.0
	EconomyManager.daily_income  = 0.0
	EconomyManager.daily_expenses = 0.0
	ProgressionManager.player_level     = 1
	ProgressionManager.current_xp       = 0.0
	ProgressionManager.xp_to_next_level = 100.0
	ProgressionManager.total_xp_earned  = 0.0
	ProgressionManager.town_hall_level  = 1
	BuildingManager.from_array([])
	CitizenManager.from_array([])
	ResourceManager.reset()
	TimeManager.from_dict({})
	ReputationManager.reset()
	QuestManager.reset()
	RecipeManager.reset()

func _start_fresh() -> void:
	# A wandering founder's modest purse — enough for a house, a tavern, and a dream
	EconomyManager.add_gold(500.0, "Starting gold")
	ResourceManager.add("wood",  10.0, "Salvaged timber")   # defaults already hold 50 wood / 30 stone

	var bg = get_node_or_null("BuildGrid")

	var th = BuildingManager.place_building_free("town_hall", Vector2i.ZERO)
	if th and bg:
		bg.occupy_cells(th.grid_origin, th.get_size(), th.id)

	# Paint a starter dirt road running past the town hall and the old houses
	for dx in range(-4, 8):
		RoadManager.paint(Vector2i(dx, 4), "dirt")

	# The forgotten hamlet — a couple of crumbling houses already stand here
	for origin in [Vector2i(-4, 1), Vector2i(5, 1)]:
		var house = BuildingManager.place_building_free("house", origin)
		if house and bg:
			bg.occupy_cells(house.grid_origin, house.get_size(), house.id)

	print("[GameManager] New game started.")


func _process(delta: float) -> void:
	_tick_acc += delta
	while _tick_acc >= 1.0:
		_tick_acc -= 1.0
		_income_tick()

	_autosave_acc += delta
	if SaveManager.settings.get("autosave", true) and _autosave_acc >= AUTOSAVE_INTERVAL:
		_autosave_acc = 0.0
		SaveManager.save()
		SignalBus.show_notification.emit("Game auto-saved.")

func _income_tick() -> void:
	var happiness_mult = city_happiness / 100.0
	var season_mult = TimeManager.get_income_multiplier()
	EconomyManager.add_gold(1.0 * happiness_mult * season_mult * RecipeManager.get_income_multiplier())
	BuildingManager.collect_income_tick(1.0)
	BuildingManager.collect_resource_tick(1.0)

func _on_new_day(day: int, season: String, year: int) -> void:
	city_happiness = CitizenManager.calculate_city_happiness()
	CitizenManager.update_demand_score()
	EconomyManager.on_new_day()
	CitizenManager.on_new_day()
	ProgressionManager.reward_xp("day_survived")
	print("[GameManager] Day %d — %s — Year %d  |  Happiness: %.1f%%  Demand: %.1f" % [
		day, season, year, city_happiness, CitizenManager.demand_score
	])

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

func _calculate_offline_earnings(save_timestamp: int) -> void:
	if save_timestamp <= 0:
		return
	var delta = Time.get_unix_time_from_system() - float(save_timestamp)
	if delta < 60.0:
		return  # less than a minute — not worth computing
	var capped_seconds = minf(delta, 8.0 * 3600.0)  # 8-hour cap
	var offline_minutes = capped_seconds / 60.0

	# Sum raw building income (happiness unknown offline, use last known city happiness)
	var income_per_minute = 0.0
	for b in BuildingManager.placed_buildings:
		if b.is_active:
			income_per_minute += b.get_income_per_minute()

	var happiness_mult = maxf(city_happiness / 100.0, 0.1)
	var offline_gold = income_per_minute * offline_minutes * happiness_mult

	if offline_gold >= 1.0:
		EconomyManager.add_gold(offline_gold, "Offline earnings")
		var time_str: String
		if capped_seconds >= 3600.0:
			time_str = "%.1fh" % (capped_seconds / 3600.0)
		else:
			time_str = "%dm" % int(capped_seconds / 60.0)
		# Queue the notification — HUD may not be ready yet so defer one frame
		call_deferred("_notify_offline", offline_gold, time_str)

func _notify_offline(gold: float, time_str: String) -> void:
	SignalBus.show_notification.emit(
		"Welcome back! Collected %.0f gold from %s offline." % [gold, time_str]
	)

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
