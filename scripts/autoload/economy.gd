extends Node
## Per-team resource stockpiles: coal (gathered by Henchmen) and electricity
## (produced by Electrical Generators).

signal changed(team: int)

var _coal := {}
var _electricity := {}
## Per-team multiplier on coal Henchmen deliver (AI difficulty).
var _income := {}


## Clears every stockpile and gives [param teams] their starting resources.
func reset(teams: Array[int], starting_coal: float, starting_electricity: float) -> void:
	_coal.clear()
	_electricity.clear()
	_income.clear()
	for team in teams:
		_coal[team] = starting_coal
		_electricity[team] = starting_electricity
		changed.emit(team)


func coal(team: int) -> float:
	return _coal.get(team, 0.0)


func electricity(team: int) -> float:
	return _electricity.get(team, 0.0)


func add(team: int, coal_amount := 0.0, electricity_amount := 0.0) -> void:
	_coal[team] = coal(team) + coal_amount
	_electricity[team] = electricity(team) + electricity_amount
	changed.emit(team)


func set_income_multiplier(team: int, multiplier: float) -> void:
	_income[team] = multiplier


## Coal delivered by a Henchman, scaled by the team's income multiplier.
func deposit_coal(team: int, amount: float) -> void:
	add(team, amount * _income.get(team, 1.0))


func can_afford(team: int, coal_cost: float, electricity_cost: float) -> bool:
	return coal(team) >= coal_cost and electricity(team) >= electricity_cost


## Deducts the cost if the team can afford it. Returns whether it could.
func spend(team: int, coal_cost: float, electricity_cost: float) -> bool:
	if not can_afford(team, coal_cost, electricity_cost):
		return false
	add(team, -coal_cost, -electricity_cost)
	return true


## Human-readable reason a cost can't be paid, or "" if it can.
func shortfall(team: int, coal_cost: float, electricity_cost: float) -> String:
	if coal(team) < coal_cost:
		return "Not enough coal"
	if electricity(team) < electricity_cost:
		return "Not enough electricity"
	return ""
