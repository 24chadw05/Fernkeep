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
var daily_payment: float = 0.0  # rent or tax amount
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

# Happiness
var happiness: float = 100.0  # 0-100
var job_fit_bonus: float = 0.0
var pay_happiness: float = 0.0

# Status
var is_employed: bool = false
var days_in_town: int = 0

func calculate_happiness() -> float:
	var base = 50.0
	base += job_fit_bonus
	base += pay_happiness
	if assigned_job == "":
		base -= 10.0
	if house_building_id == "":
		base -= 25.0  # homeless penalty
	happiness = clamp(base, 0.0, 100.0)
	return happiness

# Call this whenever daily_wage changes (assign, raise, daily pressure).
# fair_daily_wage = the wealth_level's base_rent from citizens.json.
func recalculate_pay_happiness(fair_daily_wage: float) -> void:
	if not is_employed or fair_daily_wage <= 0.0:
		pay_happiness = 0.0
		calculate_happiness()
		return
	# At 80% of fair wage: -20, at 100%: +25, at 150%+: +50
	var ratio = daily_wage / fair_daily_wage
	pay_happiness = clamp((ratio - 0.8) * 125.0, -20.0, 50.0)
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
