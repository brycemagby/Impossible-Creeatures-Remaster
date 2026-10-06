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
