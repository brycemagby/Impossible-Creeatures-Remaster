class_name AnimalData
extends Resource
## One animal the combiner can draw body parts from. Each section describes
## what that body part contributes when chosen for a hybrid.

enum Ability { NONE, POISON, QUILLS, CHARGE, LEAP }

@export var display_name := "Animal"
## Used to colour this animal's parts on hybrid models.
@export var color := Color.WHITE
## Body scale relative to a lion-sized animal.
@export var size := 1.0

@export_group("Head")
@export var bite_damage := 5.0
@export var head_armor := 0.0
## POISON (venomous bite) or CHARGE (horn rush).
@export var head_ability: Ability = Ability.NONE

@export_group("Torso")
@export var health := 100.0
## Melee armor from the torso (the head adds some too).
@export var torso_armor := 0.0
## Ranged armor from the torso: thick hides and shells shrug off quills.
@export var ranged_armor := 0.0

@export_group("Legs")
## Damage added by the front legs (claws, pincers, fists, talons).
@export var claw_damage := 3.0
@export var front_leg_speed := 6.0
@export var back_leg_speed := 6.0
## LEAP (powerful hind legs) or NONE.
@export var back_leg_ability: Ability = Ability.NONE

@export_group("Tail")
@export var tail_damage := 0.0
## POISON (stinger) or QUILLS (ranged attack).
@export var tail_ability: Ability = Ability.NONE

@export_group("Wings")
@export var has_wings := false
@export var flight_speed := 0.0
