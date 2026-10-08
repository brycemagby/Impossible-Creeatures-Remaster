class_name CreatureCombiner
## Rules that turn a CreatureDesign into CreatureStats and a production cost.
##
## - Torso: health and most of the armor; dominates overall size.
## - Head: bite damage, some armor, maybe poison or a charge (horn).
## - Front legs: claw damage and half the walking speed.
## - Back legs: the other half of the walking speed, maybe a leap.
## - Tail: extra damage, poison (stinger) or a ranged attack (quills).
## - Wings: flight, but only for hybrids no bigger than MAX_FLYING_SIZE.
## Legs from a small animal under a big body are slowed down; legs from a big
## animal under a small body get a slight boost.

const SIZE_WEIGHTS := {
	CreatureDesign.Slot.HEAD: 0.15,
	CreatureDesign.Slot.TORSO: 0.55,
	CreatureDesign.Slot.FRONT_LEGS: 0.15,
	CreatureDesign.Slot.BACK_LEGS: 0.15,
}
const MIN_LEG_LOAD := 0.6
const MAX_LEG_LOAD := 1.15
const QUILL_RANGE := 8.0
const QUILL_SPEED := 20.0
const POISON_DPS := 4.0
const POISON_DURATION := 4.0
const FLYER_HEALTH_FACTOR := 0.85
## Hybrids bigger than this are too heavy for wings to lift.
const MAX_FLYING_SIZE := 1.1
const MAX_LEVEL := 5


static func build_stats(design: CreatureDesign) -> CreatureStats:
	var head := design.source(CreatureDesign.Slot.HEAD)
	var torso := design.source(CreatureDesign.Slot.TORSO)
	var front := design.source(CreatureDesign.Slot.FRONT_LEGS)
	var back := design.source(CreatureDesign.Slot.BACK_LEGS)
	var tail := design.source(CreatureDesign.Slot.TAIL)
	var wings := design.source(CreatureDesign.Slot.WINGS)

	var stats := CreatureStats.new()
	stats.display_name = design.display_name()
	stats.design = design

	var size := 0.0
	for slot: CreatureDesign.Slot in SIZE_WEIGHTS:
		size += design.source(slot).size * SIZE_WEIGHTS[slot]
	stats.size = size

	# A torso keeps most of its health, scaled a little by the hybrid's size.
	stats.max_health = torso.health * lerpf(1.0, size / torso.size, 0.5)
	stats.armor = torso.torso_armor + head.head_armor

	var leg_speed := (front.front_leg_speed + back.back_leg_speed) / 2.0
	var leg_size := (front.size + back.size) / 2.0
	stats.move_speed = leg_speed * clampf(leg_size / size, MIN_LEG_LOAD, MAX_LEG_LOAD)

	stats.attack_cooldown = clampf(1.0 + 0.25 * (size - 1.0), 0.75, 1.5)
	if tail.tail_ability == AnimalData.Ability.QUILLS:
		stats.attack_damage = tail.tail_damage + head.bite_damage * 0.25
		stats.attack_range = QUILL_RANGE
		stats.projectile_speed = QUILL_SPEED
		stats.sight_range = 11.0
	else:
		stats.attack_damage = head.bite_damage + front.claw_damage + tail.tail_damage
		stats.attack_range = 0.5 + 0.2 * size

	if head.head_ability == AnimalData.Ability.POISON or tail.tail_ability == AnimalData.Ability.POISON:
		stats.poison_dps = POISON_DPS
		stats.poison_duration = POISON_DURATION

	# Melee-only abilities: a quill-shooter doesn't charge or leap in.
	if head.head_ability == AnimalData.Ability.CHARGE and not stats.is_ranged():
		stats.can_charge = true
	if back.back_leg_ability == AnimalData.Ability.LEAP and not stats.is_ranged():
		stats.can_leap = true

	if wings != null and size <= MAX_FLYING_SIZE:
		stats.can_fly = true
		stats.can_leap = false
		stats.move_speed = maxf(stats.move_speed, wings.flight_speed * clampf(wings.size / size, MIN_LEG_LOAD, 1.0))
		stats.max_health *= FLYER_HEALTH_FACTOR

	stats.max_health = roundf(stats.max_health)
	stats.attack_damage = roundf(stats.attack_damage * 10.0) / 10.0
	stats.level = level_for(power_rating(stats))
	return stats


## A single number for how strong a creature is; drives level and cost.
static func power_rating(stats: CreatureStats) -> float:
	var dps := stats.attack_damage / stats.attack_cooldown
	var power := stats.max_health / 8.0 + stats.armor * 4.0 + dps * 3.0 + stats.move_speed * 2.5
	power += stats.poison_dps * stats.poison_duration * 0.75
	if stats.is_ranged():
		power += 10.0
	if stats.can_fly:
		power += 12.0
	if stats.can_charge:
		power += 6.0
	if stats.can_leap:
		power += 6.0
	return power


static func level_for(power: float) -> int:
	return clampi(ceili((power - 45.0) / 18.0), 1, MAX_LEVEL)


## Whether [param design] has wings that can't lift it.
static func too_heavy_to_fly(design: CreatureDesign) -> bool:
	if design.source(CreatureDesign.Slot.WINGS) == null:
		return false
	var size := 0.0
	for slot: CreatureDesign.Slot in SIZE_WEIGHTS:
		size += design.source(slot).size * SIZE_WEIGHTS[slot]
	return size > MAX_FLYING_SIZE


static func make_recipe(design: CreatureDesign) -> UnitRecipe:
	var stats := build_stats(design)
	var power := power_rating(stats)
	var recipe := UnitRecipe.new()
	recipe.stats = stats
	recipe.scene = load("res://scenes/units/creature.tscn")
	recipe.cost_coal = int(snappedf(power * 1.5, 5.0))
	recipe.cost_electricity = (stats.level - 1) * 25
	recipe.build_time = snappedf(4.0 + power * 0.08, 0.5)
	return recipe
