extends Node

# Current gold
var gold: float = 0.0
var gold_cap: float = 10000.0  # upgradeable via treasury

# Tracking
var total_earned: float = 0.0
var total_spent: float = 0.0
var daily_income: float = 0.0
var daily_expenses: float = 0.0

# Signals
signal gold_changed(new_amount: float)
signal insufficient_funds(amount_needed: float)
signal daily_summary(income: float, expenses: float, net: float)

func add_gold(amount: float, reason: String = "") -> void:
	gold = min(gold + amount, gold_cap)
	total_earned += amount
	daily_income += amount
	emit_signal("gold_changed", gold)
	if reason != "":
		print("[Economy] +%.1f gold — %s (Total: %.1f)" % [amount, reason, gold])

func spend_gold(amount: float, reason: String = "") -> bool:
	if not can_afford(amount):
		emit_signal("insufficient_funds", amount)
		print("[Economy] Cannot afford %.1f gold for %s (Have: %.1f)" % [amount, reason, gold])
		return false
	gold -= amount
	total_spent += amount
	daily_expenses += amount
	emit_signal("gold_changed", gold)
	if reason != "":
		print("[Economy] -%.1f gold — %s (Total: %.1f)" % [amount, reason, gold])
	return true

func can_afford(amount: float) -> bool:
	return gold >= amount

func collect_rent(amount: float, npc_name: String) -> void:
	add_gold(amount, "Rent from " + npc_name)

func collect_tax(amount: float, npc_name: String) -> void:
	add_gold(amount, "Tax from " + npc_name)

func pay_wage(amount: float, npc_name: String) -> bool:
	return spend_gold(amount, "Wage for " + npc_name)

func on_new_day() -> void:
	emit_signal("daily_summary", daily_income, daily_expenses, daily_income - daily_expenses)
	print("[Economy] Day summary — Income: %.1f | Expenses: %.1f | Net: %.1f" % [daily_income, daily_expenses, daily_income - daily_expenses])
	daily_income = 0.0
	daily_expenses = 0.0

func upgrade_gold_cap(new_cap: float) -> void:
	gold_cap = new_cap
	print("[Economy] Gold cap upgraded to %.1f" % gold_cap)

func get_gold_display() -> String:
	return "%.0f" % gold
