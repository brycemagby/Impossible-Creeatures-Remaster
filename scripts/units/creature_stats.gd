class_name CreatureStats
extends Resource
## Data describing a creature type.
##
## Hybrids get theirs from CreatureCombiner.build_stats(); a few
## hand-authored ones (the starting units) are saved as .tres files.

@export var display_name := "Creature"
@export var max_health := 100.0
## Movement speed in metres per second.
@export var move_speed := 6.0
## Uniform scale applied to the placeholder body, collision and avoidance radius.
@export var size := 1.0
## Strength tier from 1 to 5 (hybrids only).
@export var level := 1
## The combiner design this creature was made from, if any. Used to build its model.
@export var design: CreatureDesign

@export_group("Combat")
## Melee armor: flat reduction on every melee hit (it never blocks more than
## Creature.MAX_ARMOR_BLOCK of a hit).
@export var armor := 0.0
## Ranged armor: flat reduction on quills, projectiles and tower beams.
@export var ranged_armor := 0.0
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

@export_group("Abilities")
## Flies over obstacles; only ranged and flying creatures can hit it.
@export var can_fly := false
## Poison damage per second applied by each hit (ignores armor).
@export var poison_dps := 0.0
@export var poison_duration := 0.0
## Sprints at targets a few metres away; the first hit does double damage.
@export var can_charge := false
## Jumps the last few metres to a target.
@export var can_leap := false
## Every few seconds, a screech hurts every enemy close by (ignores armor).
@export var has_sonic := false
## Hits harder for each packmate (another pack hunter) nearby.
@export var pack_hunter := false
## Attacks faster once badly wounded.
@export var has_frenzy := false
## Melee hits also hurt enemies next to the target.
@export var has_trample := false
## Enemies close by deal less damage.
@export var has_stink := false
## Turns invisible to enemies after standing still for a moment.
@export var has_camouflage := false
## Extra armor for each herd mate (another herding creature) nearby.
@export var herding := false


func is_ranged() -> bool:
	return projectile_speed > 0.0
