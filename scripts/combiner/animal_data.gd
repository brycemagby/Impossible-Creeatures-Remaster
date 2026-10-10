class_name AnimalData
extends Resource
## One animal the combiner can draw body parts from. Each section describes
## what that body part contributes when chosen for a hybrid.

enum Ability { NONE, POISON, QUILLS, CHARGE, LEAP, SONIC, PACK, FRENZY, TRAMPLE, STINK, CAMOUFLAGE, HERDING, ELECTRIC }
## How an animal's legs cope with water: not at all, swimming as well as
## walking, or fins only (no walking).
enum Swimming { NONE, AMPHIBIOUS, AQUATIC }

@export var display_name := "Animal"
## Used to colour this animal's parts on hybrid models.
@export var color := Color.WHITE
## Body scale relative to a lion-sized animal.
@export var size := 1.0

@export_group("Head")
@export var bite_damage := 5.0
@export var head_armor := 0.0
## POISON (venomous bite), CHARGE (horn rush), SONIC (screech) or PACK
## (hunts better with packmates).
@export var head_ability: Ability = Ability.NONE

@export_group("Torso")
@export var health := 100.0
## Melee armor from the torso (the head adds some too).
@export var torso_armor := 0.0
## Ranged armor from the torso: thick hides and shells shrug off quills.
@export var ranged_armor := 0.0
## FRENZY (fights faster when wounded), TRAMPLE (melee hits splash),
## CAMOUFLAGE (vanishes while standing still), HERDING (tougher in a herd) or
## ELECTRIC (shocks stun).
@export var torso_ability: Ability = Ability.NONE

@export_group("Legs")
## Damage added by the front legs (claws, pincers, fists, talons).
@export var claw_damage := 3.0
@export var front_leg_speed := 6.0
@export var back_leg_speed := 6.0
## LEAP (powerful hind legs) or NONE.
@export var back_leg_ability: Ability = Ability.NONE
## AMPHIBIOUS legs swim and walk; AQUATIC ones (fins) only swim.
@export var swimming: Swimming = Swimming.NONE
## Speed in deep water for legs that swim.
@export var swim_speed := 0.0

@export_group("Tail")
@export var tail_damage := 0.0
## POISON (stinger), QUILLS (ranged attack) or STINK (weakens nearby enemies).
@export var tail_ability: Ability = Ability.NONE

@export_group("Wings")
@export var has_wings := false
@export var flight_speed := 0.0
