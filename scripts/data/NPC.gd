extends Resource
class_name NPC

# Basic info
var id: String = ""
var first_name: String = ""
var last_name: String = ""
var age: int = 0
var wealth_level: int = 0  # 1-10, affects housing offer and skill rarity

# Housing
var housing_type: String = "renter"  # "renter" or "owner"
var housing_plot: Vector2i = Vector2i.ZERO
var daily_payment: float = 0.0  # rent or tax actually charged (capped at 35% of pay)
var base_daily_payment: float = 0.0  # the wealth-based offer before the affordability cap
var house_building_id: String = ""  # which placed house they live in

# Skills
var good_skill: String = ""
var bad_skill: String = ""
var is_special_skill: bool = false

# Job
var assigned_job: String = ""
var job_building_id: String = ""
var daily_wage: float = 0.0
var base_daily_wage: float = 0.0  # wage when first hired — raises are capped at +15% of this

# Personal life
var savings: float = 0.0     # personal gold; wages in, living costs out
var kids: int = 0            # each kid costs KID_COST gold/day (CitizenManager)
var hobby: String = ""       # id into citizens.json "hobbies"
var last_ledger: Dictionary = {}  # yesterday's money flow, shown in CitizenPanel

# Happiness components — the daily ledger pass in CitizenManager fills the
# city/lifestyle ones in; calculate_happiness() just sums them.
var happiness: float = 100.0  # 0-100
var job_fit_bonus: float = 0.0    # skill matches the job        (-15 … +25)
var pay_happiness: float = 0.0    # wage vs fair wage for level  (-20 … +25)
var housing_bonus: float = 0.0    # house tier/level quality     (0 … +8)
var amenity_bonus: float = 0.0    # town variety/decor/roads/pop (0 … +15)
var comfort_bonus: float = 0.0    # savings buffer + funded hobby (0 … +22)
var needs_penalty: float = 0.0    # skipped rent/food/kids/hobby (0 … +39)
var treat_days: int = 0           # days left of cheer from a meal cooked for them
const TREAT_BONUS: float = 8.0

# Status
var is_employed: bool = false
var days_in_town: int = 0

func calculate_happiness() -> float:
	var base = 35.0
	base += job_fit_bonus
	base += pay_happiness
	if assigned_job == "":
		base -= 10.0
	if house_building_id == "":
		base -= 25.0  # homeless penalty
	else:
		base += housing_bonus
	base += amenity_bonus
	base += comfort_bonus
	base -= needs_penalty
	if treat_days > 0:
		base += TREAT_BONUS
	happiness = clamp(base, 0.0, 100.0)
	return happiness

# Call this whenever daily_wage changes (assign, raise, daily pressure).
# fair_daily_wage = CitizenManager.get_fair_wage() — scales with workplace level.
func recalculate_pay_happiness(fair_daily_wage: float) -> void:
	if not is_employed or fair_daily_wage <= 0.0:
		pay_happiness = 0.0
		calculate_happiness()
		return
	# At 80% of fair wage: neutral; at 105%+: +25; below 60%: -20
	var ratio = daily_wage / fair_daily_wage
	pay_happiness = clamp((ratio - 0.8) * 100.0, -20.0, 25.0)
	calculate_happiness()

func get_full_name() -> String:
	return first_name + " " + last_name

func to_dict() -> Dictionary:
	return {
		"id": id,
		"first_name": first_name,
		"last_name": last_name,
		"age": age,
		"wealth_level": wealth_level,
		"housing_type": housing_type,
		"housing_plot": [housing_plot.x, housing_plot.y],
		"daily_payment": daily_payment,
		"base_daily_payment": base_daily_payment,
		"house_building_id": house_building_id,
		"good_skill": good_skill,
		"bad_skill": bad_skill,
		"is_special_skill": is_special_skill,
		"assigned_job": assigned_job,
		"job_building_id": job_building_id,
		"daily_wage": daily_wage,
		"base_daily_wage": base_daily_wage,
		"job_fit_bonus": job_fit_bonus,
		"pay_happiness": pay_happiness,
		"happiness": happiness,
		"is_employed": is_employed,
		"days_in_town": days_in_town,
		"savings": savings,
		"kids": kids,
		"hobby": hobby,
		"last_ledger": last_ledger.duplicate(),
		"housing_bonus": housing_bonus,
		"amenity_bonus": amenity_bonus,
		"comfort_bonus": comfort_bonus,
		"needs_penalty": needs_penalty,
		"treat_days": treat_days,
	}

func from_dict(data: Dictionary):
	id = data.get("id", "")
	first_name = data.get("first_name", "")
	last_name = data.get("last_name", "")
	age = data.get("age", 0)
	wealth_level = data.get("wealth_level", 1)
	housing_type = data.get("housing_type", "renter")
	var plot = data.get("housing_plot", [0, 0])
	housing_plot = Vector2i(plot[0], plot[1])
	daily_payment = data.get("daily_payment", 0.0)
	base_daily_payment = data.get("base_daily_payment", daily_payment)
	house_building_id = data.get("house_building_id", "")
	good_skill = data.get("good_skill", "")
	bad_skill = data.get("bad_skill", "")
	is_special_skill = data.get("is_special_skill", false)
	assigned_job = data.get("assigned_job", "")
	job_building_id = data.get("job_building_id", "")
	daily_wage = data.get("daily_wage", 0.0)
	base_daily_wage = data.get("base_daily_wage", daily_wage)
	job_fit_bonus = data.get("job_fit_bonus", 0.0)
	pay_happiness = data.get("pay_happiness", 0.0)
	happiness = data.get("happiness", 100.0)
	is_employed = data.get("is_employed", false)
	days_in_town = data.get("days_in_town", 0)
	savings = float(data.get("savings", NAN))  # NAN → pre-ledger save, migrated by CitizenManager (negatives are legit debt)
	kids = int(data.get("kids", 0))
	hobby = str(data.get("hobby", ""))
	last_ledger = data.get("last_ledger", {}).duplicate()
	housing_bonus = float(data.get("housing_bonus", 0.0))
	amenity_bonus = float(data.get("amenity_bonus", 0.0))
	comfort_bonus = float(data.get("comfort_bonus", 0.0))
	needs_penalty = float(data.get("needs_penalty", 0.0))
	treat_days = int(data.get("treat_days", 0))
