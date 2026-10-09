class_name UpgradeData
extends Resource
## A one-off, team-wide improvement bought at a Research Center (creatures),
## a Workshop (Henchmen) or an Aviary (flyers). Effects add up across everything a team owns.

@export var id: StringName
@export var display_name := "Upgrade"
@export_multiline var description := ""
@export var cost_coal := 100
@export var cost_electricity := 0
## Seconds to complete.
@export var duration := 30.0
## Research level (at the Lab) needed before it can be bought.
@export var required_research := 1
## Another upgrade that must be owned first (the previous tier), or empty.
@export var requires: StringName

@export_group("Creature effects")
@export var melee_damage := 0.0
@export var ranged_damage := 0.0
@export var melee_armor := 0.0
@export var ranged_armor := 0.0
## Added to the creature speed multiplier (0.1 = 10% faster).
@export var creature_speed := 0.0

@export_group("Flyer effects")
## Added to flyers' speed multiplier.
@export var flyer_speed := 0.0
## Extra metres flyers see (and spot enemies from).
@export var flyer_sight := 0.0

@export_group("Henchman effects")
## Extra coal per trip.
@export var carry := 0
## Added to the Henchman speed multiplier.
@export var henchman_speed := 0.0
## Fraction taken off the time to mine a load (0.3 = 30% faster).
@export var gather_speed := 0.0
## Added to the construction speed multiplier.
@export var build_speed := 0.0
