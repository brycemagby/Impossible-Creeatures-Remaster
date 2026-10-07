class_name CreatureStats
extends Resource
## Data describing a creature type.
##
## For now these are hand-authored placeholders. Later the creature combiner
## will generate these from two parent animals and the chosen body parts.

@export var display_name := "Creature"
@export var max_health := 100.0
## Movement speed in metres per second.
@export var move_speed := 6.0
## Uniform scale applied to the placeholder body, collision and avoidance radius.
@export var size := 1.0

@export_group("Combat")
## Flat reduction applied to every incoming hit (minimum 1 damage gets through).
@export var armor := 0.0
@export var attack_damage := 10.0
## Reach in metres, measured from this creature's edge to the target's edge.
@export var attack_range := 0.6
## Seconds between attacks.
@export var attack_cooldown := 1.0
## 0 = melee (hits instantly). Above 0 = ranged: fires a projectile at this speed.
@export var projectile_speed := 0.0
## Distance at which idle creatures notice and engage enemies.
@export var sight_range := 10.0
## How far an idle creature will chase an enemy it noticed before giving up
## and walking back to where it was standing.
@export var leash_range := 14.0


func is_ranged() -> bool:
	return projectile_speed > 0.0
