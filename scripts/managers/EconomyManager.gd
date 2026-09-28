extends Node

# Current gold — no cap; the treasury holds as much as the city can earn
var gold: float = 0.0

# Tracking
var total_earned: float = 0.0
var total_spent: float = 0.0
var daily_income: float = 0.0
var daily_expenses: float = 0.0

# Baseline gold the settlement itself brings in, per second. A game day is 60s,
# so this is x60 per day — at 1.0 that was 60/day, which out-earned a level-1
# tavern (33/day) and made the player's first businesses feel pointless. Kept as
# a small floor so a city with no working buildings still trickles. Lives here
# rather than on GameManager so the revenue projection in RevenuePanel can read
# the same number the tick actually uses.
const BASELINE_GOLD_PER_SECOND: float = 0.25

# ── Daily settlement ──────────────────────────────────────────────────────────
# Business revenue does NOT trickle into the treasury. It accrues here all day,
# and at day's end it settles in one lump: the workers are paid out of the day's
# takings first, and the player banks whatever is left. A day where the wage bill
# outruns revenue therefore eats into the treasury, which is the point — payroll
# is settled against what the city actually earned.
var pending_revenue: float = 0.0   # accrued so far today, not yet banked
var _day_purse: float = 0.0        # the takings currently being settled
var _day_revenue: float = 0.0      # what the purse started at, for the summary
var _day_wages: float = 0.0        # wages actually paid this settlement

# Signals
signal gold_changed(new_amount: float)
signal insufficient_funds(amount_needed: float)
signal daily_summary(income: float, expenses: float, net: float)
signal pending_revenue_changed(pending: float)
signal day_settled(revenue: float, wages: float, payout: float)

# Returns the gold banked (always the full amount now the cap is gone) so
# callers written for the old capped behaviour keep working.
func add_gold(amount: float, reason: String = "") -> float:
	gold += amount
	total_earned += amount
	daily_income += amount
	emit_signal("gold_changed", gold)
	if reason != "":
		print("[Economy] +%.1f gold — %s (Total: %.1f)" % [amount, reason, gold])
	return amount

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

# Wages come out of the day's takings first; only once those are exhausted does
# payroll dip into the treasury. A worker goes unpaid only when neither can cover
# them, which is what CitizenManager's ledger treats as a missed wage.
func pay_wage(amount: float, npc_name: String) -> bool:
	if amount <= 0.0:
		return true
	var from_purse = minf(_day_purse, amount)
	var shortfall = amount - from_purse
	if shortfall > 0.0 and not can_afford(shortfall):
		emit_signal("insufficient_funds", shortfall)
		print("[Economy] Cannot pay wage %.1f for %s (purse %.1f, treasury %.1f)" % [
			amount, npc_name, _day_purse, gold
		])
		return false
	_day_purse -= from_purse
	if shortfall > 0.0:
		gold -= shortfall
		emit_signal("gold_changed", gold)
	total_spent += amount
	daily_expenses += amount
	_day_wages += amount
	return true

# ── Settlement lifecycle (driven by GameManager on each new day) ──────────────

# Revenue earned by a business this tick. Counted as earned immediately so the
# HUD and RevenuePanel can show the day building up, but held out of the
# treasury until settlement.
func accrue_revenue(amount: float) -> void:
	if amount <= 0.0:
		return
	pending_revenue += amount
	total_earned += amount
	daily_income += amount
	emit_signal("pending_revenue_changed", pending_revenue)

# Move the day's takings into the purse that payroll draws from.
func begin_day_settlement() -> void:
	_day_purse = pending_revenue
	_day_revenue = pending_revenue
	_day_wages = 0.0
	pending_revenue = 0.0
	emit_signal("pending_revenue_changed", pending_revenue)

# Bank what payroll didn't consume and report the day. The lump was already
# counted into total_earned/daily_income as it accrued, so this only moves gold.
# Wages are reported from what was actually paid, not revenue minus payout —
# those differ whenever payroll had to reach into the treasury.
func finish_day_settlement() -> Dictionary:
	var payout = maxf(_day_purse, 0.0)
	_day_purse = 0.0
	if payout > 0.0:
		gold += payout
		emit_signal("gold_changed", gold)
	var result := {"revenue": _day_revenue, "wages": _day_wages, "payout": payout}
	emit_signal("day_settled", _day_revenue, _day_wages, payout)
	return result

func on_new_day() -> void:
	emit_signal("daily_summary", daily_income, daily_expenses, daily_income - daily_expenses)
	print("[Economy] Day summary — Income: %.1f | Expenses: %.1f | Net: %.1f" % [daily_income, daily_expenses, daily_income - daily_expenses])
	daily_income = 0.0
	daily_expenses = 0.0

func get_gold_display() -> String:
	return "%.0f" % gold
