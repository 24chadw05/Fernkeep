extends Label

func _ready():
	EconomyManager.connect("gold_changed", _on_gold_changed)
	text = "Gold: " + EconomyManager.get_gold_display()

func _on_gold_changed(_new_amount):
	text = "Gold: " + EconomyManager.get_gold_display()
