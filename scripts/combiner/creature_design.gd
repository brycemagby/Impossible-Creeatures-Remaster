class_name CreatureDesign
extends Resource
## A hybrid: two animals and, for each body part, which of them it comes from.
## CreatureCombiner turns a design into CreatureStats.

enum Slot { HEAD, TORSO, FRONT_LEGS, BACK_LEGS, TAIL, WINGS }

const SLOT_NAMES := ["Head", "Torso", "Front legs", "Back legs", "Tail", "Wings"]
const FROM_A := 0
const FROM_B := 1
## Only valid for wings: the hybrid has none.
const NONE := -1

@export var animal_a: AnimalData
@export var animal_b: AnimalData
## One entry per Slot: FROM_A, FROM_B, or NONE (wings only).
@export var picks: Array[int] = [FROM_A, FROM_A, FROM_B, FROM_B, FROM_A, NONE]
## Overrides the generated name when not empty.
@export var custom_name := ""


static func create(a: AnimalData, b: AnimalData, slot_picks: Array[int], name := "") -> CreatureDesign:
	var design := CreatureDesign.new()
	design.animal_a = a
	design.animal_b = b
	design.picks = slot_picks.duplicate()
	design.custom_name = name
	return design


## The animal [param slot] comes from, or null for missing wings.
func source(slot: Slot) -> AnimalData:
	var pick := picks[slot]
	if pick == NONE:
		return null
	return animal_a if pick == FROM_A else animal_b


func set_pick(slot: Slot, pick: int) -> void:
	if slot == Slot.WINGS:
		var animal: AnimalData = null if pick == NONE else (animal_a if pick == FROM_A else animal_b)
		if animal != null and not animal.has_wings:
			pick = NONE
	elif pick == NONE:
		return
	picks[slot] = pick
	emit_changed()


## Wings can only come from an animal that has them.
func is_valid() -> bool:
	if animal_a == null or animal_b == null or picks.size() != Slot.size():
		return false
	var wings := source(Slot.WINGS)
	return wings == null or wings.has_wings


func display_name() -> String:
	if custom_name != "":
		return custom_name
	return generated_name(animal_a, animal_b)


func duplicate_design() -> CreatureDesign:
	return create(animal_a, animal_b, picks, custom_name)


## Original-game-style portmanteau: the front of A's name + the back of B's.
static func generated_name(a: AnimalData, b: AnimalData) -> String:
	if a == null or b == null:
		return "Hybrid"
	if a == b:
		return a.display_name
	var first := a.display_name.left(ceili(a.display_name.length() / 2.0))
	var second := b.display_name.substr(b.display_name.length() / 2).to_lower()
	return first + second
