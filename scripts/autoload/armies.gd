extends Node
## Each team's army roster (up to MAX_SIZE hybrid designs) and the production
## recipes generated from it. The player's roster is saved between sessions;
## the enemy uses the presets.

signal changed(team: int)

const MAX_SIZE := 9
const DEFAULT_SAVE_PATH := "user://army.tres"
const ANIMAL_DIR := "res://resources/animals/"
## Starting designs, roughly one per research level so there's always
## something to build: [animal A, animal B, picks (head, torso, front legs,
## back legs, tail, wings), name].
const PRESETS := [
	["cheetah", "cheetah", [0, 0, 0, 0, 0, -1], ""],
	["wolf", "wolf", [0, 0, 0, 0, 0, -1], ""],
	["cheetah", "porcupine", [0, 0, 0, 0, 1, -1], ""],
	["lion", "cheetah", [0, 0, 1, 1, 0, -1], ""],
	["gorilla", "porcupine", [0, 0, 0, 0, 1, -1], ""],
	["lion", "eagle", [0, 0, 1, 0, 0, 1], ""],
	["rhino", "elephant", [0, 1, 0, 0, 1, -1], ""],
	["lion", "scorpion", [0, 0, 1, 0, 1, -1], ""],
]

## Where the player's army is saved (tests point this elsewhere).
var save_path := DEFAULT_SAVE_PATH
var _designs := {}
var _recipes := {}


func _ready() -> void:
	load_player_army()
	set_designs(1, default_designs())


func designs(team: int) -> Array[CreatureDesign]:
	if not _designs.has(team):
		# Every computer opponent uses the presets.
		set_designs(team, default_designs())
	var result: Array[CreatureDesign] = []
	result.assign(_designs.get(team, []))
	return result


func set_designs(team: int, new_designs: Array) -> void:
	var valid: Array[CreatureDesign] = []
	for design: CreatureDesign in new_designs:
		if design != null and design.is_valid() and valid.size() < MAX_SIZE:
			valid.append(design)
	_designs[team] = valid
	_recipes.erase(team)
	changed.emit(team)


## Production recipes for [param team]'s roster, in roster order.
func recipes(team: int) -> Array[UnitRecipe]:
	if not _recipes.has(team):
		var list: Array[UnitRecipe] = []
		for design in designs(team):
			list.append(CreatureCombiner.make_recipe(design))
		_recipes[team] = list
	var result: Array[UnitRecipe] = []
	result.assign(_recipes[team])
	return result


func default_designs() -> Array[CreatureDesign]:
	var result: Array[CreatureDesign] = []
	for preset in PRESETS:
		var picks: Array[int] = []
		picks.assign(preset[2])
		result.append(CreatureDesign.create(animal(preset[0]), animal(preset[1]), picks, preset[3]))
	return result


## Every animal available to the combiner, sorted by name.
func all_animals() -> Array[AnimalData]:
	var result: Array[AnimalData] = []
	for file in DirAccess.get_files_at(ANIMAL_DIR):
		# Exported builds list remapped resources with a .remap suffix.
		file = file.trim_suffix(".remap")
		if file.ends_with(".tres"):
			result.append(load(ANIMAL_DIR + file))
	result.sort_custom(func(a: AnimalData, b: AnimalData) -> bool: return a.display_name < b.display_name)
	return result


func animal(file_name: String) -> AnimalData:
	return load(ANIMAL_DIR + file_name + ".tres")


func save_player_army() -> Error:
	var roster := ArmyRoster.new()
	roster.designs = designs(0)
	return ResourceSaver.save(roster, save_path)


## Loads the saved army, falling back to the presets if there is none.
func load_player_army() -> void:
	var roster: ArmyRoster = null
	if ResourceLoader.exists(save_path):
		roster = ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as ArmyRoster
	if roster != null and not roster.designs.is_empty():
		set_designs(0, roster.designs)
	else:
		set_designs(0, default_designs())
