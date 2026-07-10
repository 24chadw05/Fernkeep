extends TileMap

const STATIC_SOURCE = 1
const GRASS_SIZE    = 125
const EDGE_WIDTH    = 25
const ROAD_WIDTH    = 10
const ROAD_CENTER   = 0

# -------------------------------------------------------------------
# Tile atlas coordinates in FERN_static_atlas.png (1088x64, 64x64 tiles)
# Single row of 17 tiles (cols 0-16, all at row 0):
#   Cols  0-10 : green grass variants (main terrain)
#   Cols 11-12 : sandy/tan coast transition
#   Cols 13-14 : olive/brown earth
#   Col  15    : near-black void/deep water
#   Col  16    : dark teal water
# -------------------------------------------------------------------

# Green grass variants — cols 0-10
const GRASS_TILES: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
	Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0),
	Vector2i(8, 0), Vector2i(9, 0), Vector2i(10, 0),
]
# Sandy coast transition — cols 11-12
const SAND_TILES: Array[Vector2i] = [
	Vector2i(11, 0), Vector2i(12, 0),
]
# Dark teal water — col 16
const WATER_TILE  = Vector2i(16, 0)
const ROAD_TILE   = Vector2i(2, 0)   # solid grass for road strip
const BORDER_TILE = Vector2i(15, 0)  # near-black edge border

func _ready() -> void:
	generate_world()

func get_coast_offset(coord: int, seed_mult: float) -> int:
	var noise_val = sin(coord * 0.3 * seed_mult) * 2 + sin(coord * 0.7 * seed_mult) * 1.5
	return int(noise_val)

func generate_world() -> void:
	var total_size = GRASS_SIZE + EDGE_WIDTH
	for x in range(-total_size, total_size):
		for y in range(-total_size, total_size):
			var coast_s = get_coast_offset(x, 1.0)
			var coast_w = get_coast_offset(y, 2.0)
			place_tile(x, y, coast_s, coast_w)

func place_tile(x: int, y: int, coast_s: int, coast_w: int) -> void:
	var grass_s =  GRASS_SIZE + coast_s
	var grass_w = -GRASS_SIZE + coast_w

	# --- north border (road strip + water beyond) ---
	if y < -GRASS_SIZE:
		var half = ROAD_WIDTH / 2
		if x >= ROAD_CENTER - half and x <= ROAD_CENTER + half:
			set_cell(0, Vector2i(x, y), STATIC_SOURCE, ROAD_TILE)
		else:
			set_cell(0, Vector2i(x, y), STATIC_SOURCE, BORDER_TILE)
		return

	# --- east border ---
	if x > GRASS_SIZE:
		set_cell(0, Vector2i(x, y), STATIC_SOURCE, BORDER_TILE)
		return

	# --- south coast ---
	if y > grass_s:
		var dist = y - grass_s
		var sand = SAND_TILES[abs(x + y) % SAND_TILES.size()]
		if dist < 5:
			set_cell(0, Vector2i(x, y), STATIC_SOURCE, sand)
		else:
			set_cell(0, Vector2i(x, y), STATIC_SOURCE, WATER_TILE)
		return

	# --- west coast ---
	if x < grass_w:
		var dist = grass_w - x
		var sand = SAND_TILES[abs(x + y) % SAND_TILES.size()]
		if dist < 5:
			set_cell(0, Vector2i(x, y), STATIC_SOURCE, sand)
		else:
			set_cell(0, Vector2i(x, y), STATIC_SOURCE, WATER_TILE)
		return

	# --- main grass ---
	set_cell(0, Vector2i(x, y), STATIC_SOURCE, GRASS_TILES[abs(x * 3 + y * 7) % GRASS_TILES.size()])
