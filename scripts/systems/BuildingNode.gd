extends Area2D
class_name BuildingNode

# Visual representation of a placed building on the world map.
# Each BuildingNode is spawned by GameManager when a building is placed or loaded from save.
# Click detection uses _unhandled_input + manual bounds check instead of Area2D._input_event,
# because _input_event requires viewport.physics_object_picking = true (off by default in Godot 4).
# The bounds approach also works correctly with camera zoom and Mac trackpad single-tap.

var placed_building: PlacedBuilding = null

# Sprite asset map — add entries here as real sprites are created.
# Any building_id not listed falls back to the white placeholder box.
const SPRITE_MAP: Dictionary = {
	"house":             "res://assets/buildings/House_Cottage.png",
	"town_hall":         "res://assets/buildings/Town_Hall.png",
	"tavern":            "res://assets/buildings/Tavern.png",
	"market":            "res://assets/buildings/Market.png",
	"trade_port":        "res://assets/buildings/Trade_Port.png",
	"guild_hall":        "res://assets/buildings/Guild_Hall.png",
	"magic_tower":       "res://assets/buildings/Magic_Tower.png",
	"farm":              "res://assets/buildings/Farm.png",
	"blacksmith":        "res://assets/buildings/Blacksmith.png",
	"logging_camp":      "res://assets/buildings/Logging_Camp.png",
	"mining_operation":  "res://assets/buildings/Mining_Operation.png",
	"tree":              "res://assets/decor/Tree_1.png",
	"flower_bed":        "res://assets/decor/Flower_Bed.png",
	"well":              "res://assets/buildings/Well_Hay_1.png",
}

func setup(building: PlacedBuilding) -> void:
	placed_building = building
	var bsize   = building.get_size()
	var px_size = Vector2(bsize.x * 64, bsize.y * 64)

	# Collision shape — used for physics queries (not click detection).
	# Centred at px_size / 2 so the top-left corner of the node aligns with the grid origin.
	var shape          = RectangleShape2D.new()
	shape.size         = px_size
	$CollisionShape2D.shape    = shape
	$CollisionShape2D.position = px_size / 2.0

	# Border / selection highlight — resized to match footprint
	$Border.size = px_size

	# Use the chosen variant sprite if set, otherwise fall back to SPRITE_MAP default.
	var sprite_path = building.sprite_path if building.sprite_path != "" else SPRITE_MAP.get(building.building_id, "")
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		$Visual.visible = false   # hide placeholder when a real sprite exists
		$Border.visible = false   # no footprint shading — let the grass show through

		var tex: Texture2D = load(sprite_path)
		var spr            = Sprite2D.new()
		spr.texture        = tex
		spr.centered       = false        # anchor at top-left to match the grid cell
		spr.scale          = px_size / Vector2(tex.get_width(), tex.get_height())
		spr.z_index        = 1            # render above border/shadow
		add_child(spr)
	else:
		# Placeholder: white filled box with a 1 px inset so the border is visible
		$Visual.position = Vector2(1, 1)
		$Visual.size     = px_size - Vector2(2, 2)

	# Name label removed — buildings are identified by their sprite
	$NameLabel.visible = false

	# Prevent world-space Controls from intercepting GUI hover checks
	$Border.mouse_filter    = Control.MOUSE_FILTER_IGNORE
	$Visual.mouse_filter    = Control.MOUSE_FILTER_IGNORE
	$NameLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE

