extends Node

var tilemap: TileMap

func _ready():
	var root = get_tree().get_root().get_child(0)
	for child in root.get_children():
		if child is TileMap:
			tilemap = child
			break
