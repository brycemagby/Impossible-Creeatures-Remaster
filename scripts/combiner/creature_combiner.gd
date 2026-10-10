class_name CreatureCombiner
## Rules that turn a CreatureDesign into CreatureStats and a production cost.
##
## - Torso: health, most of the melee armor and all the ranged armor;
##   dominates overall size; maybe frenzy (gorilla), trample (elephant) or
##   camouflage (chameleon) or herding (bison).
## - Head: bite damage, some armor, maybe poison, a charge (horn), a sonic
##   screech (bat) or pack hunting (wolf).
## - Front legs: claw damage and half the walking speed.
## - Back legs: the other half of the walking speed, maybe a leap.
## - Tail: extra damage, poison (stinger), a ranged attack (quills) or stink
##   (skunk).
## - Wings: flight, but only for hybrids no bigger than MAX_FLYING_SIZE.
## - Swimming comes from the legs: a hybrid with any swimming legs is
##   amphibious; with fins front and back it can only live in water. Legs that
##   don't swim just paddle.
## Legs from a small animal under a big body are slowed down (never below
## MIN_SPEED); legs from a big animal under a small body get a slight boost.
##
## Price and level come from [method power_rating]: roughly the square root of
## effective health times damage per second, so in a fight N creatures of one
## design are about as strong as the same coal spent on any other design.

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
## Swim speed of legs that don't swim (paddling).
const PADDLE_SPEED := 2.5
## No walking hybrid is slower than this, however tiny its legs.
const MIN_SPEED := 3.0
## Power needed for levels 2, 3, 4 and 5.
const LEVEL_THRESHOLDS: Array[float] = [28.0, 38.0, 50.0, 65.0]
## Typical incoming hits and armor that power_rating values a design against.
const REFERENCE_MELEE_HIT := 12.0
const REFERENCE_RANGED_HIT := 10.0
const REFERENCE_ARMOR := 2.0
## Share of incoming damage that is melee (the rest is ranged).
const MELEE_SHARE := 0.6
const COAL_PER_POWER := 3.0
## Echolocation: bat heads see further.
const SONIC_SIGHT_BONUS := 4.0


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
	stats.ranged_armor = torso.ranged_armor

	var leg_speed := (front.front_leg_speed + back.back_leg_speed) / 2.0
	var leg_size := (front.size + back.size) / 2.0
	stats.move_speed = maxf(leg_speed * clampf(leg_size / size, MIN_LEG_LOAD, MAX_LEG_LOAD), MIN_SPEED)

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
	if head.head_ability == AnimalData.Ability.SONIC:
		stats.has_sonic = true
		stats.sight_range += SONIC_SIGHT_BONUS
	stats.pack_hunter = head.head_ability == AnimalData.Ability.PACK
	stats.has_frenzy = torso.torso_ability == AnimalData.Ability.FRENZY
	stats.has_trample = torso.torso_ability == AnimalData.Ability.TRAMPLE and not stats.is_ranged()
	stats.has_camouflage = torso.torso_ability == AnimalData.Ability.CAMOUFLAGE
	stats.herding = torso.torso_ability == AnimalData.Ability.HERDING
	stats.has_electric = torso.torso_ability == AnimalData.Ability.ELECTRIC
	stats.has_stink = tail.tail_ability == AnimalData.Ability.STINK

	if front.swimming != AnimalData.Swimming.NONE or back.swimming != AnimalData.Swimming.NONE:
		stats.can_swim = true
		stats.water_only = front.swimming == AnimalData.Swimming.AQUATIC and back.swimming == AnimalData.Swimming.AQUATIC
		var paddle := func(animal: AnimalData) -> float:
			return animal.swim_speed if animal.swimming != AnimalData.Swimming.NONE else PADDLE_SPEED
		stats.swim_speed = (paddle.call(front) + paddle.call(back)) / 2.0 * clampf(leg_size / size, MIN_LEG_LOAD, MAX_LEG_LOAD)
		if stats.water_only:
			stats.move_speed = stats.swim_speed

	if wings != null and size <= MAX_FLYING_SIZE:
		stats.can_fly = true
		stats.can_leap = false
		# Flyers go over water instead.
		stats.can_swim = false
		stats.water_only = false
		stats.move_speed = maxf(stats.move_speed, wings.flight_speed * clampf(wings.size / size, MIN_LEG_LOAD, 1.0))
		stats.max_health *= FLYER_HEALTH_FACTOR

	stats.max_health = roundf(stats.max_health)
	stats.attack_damage = roundf(stats.attack_damage * 10.0) / 10.0
	stats.level = level_for(power_rating(stats))
	return stats


## A single number for how strong a creature is; drives level and cost.
##
## Fighting strength grows with health times damage, so this is the square root
## of the two: armor counts as the extra health it's worth against typical hits
## (a lot on a big torso, little on a small one). Speed and abilities scale it.
static func power_rating(stats: CreatureStats) -> float:
	var melee_health := stats.max_health * REFERENCE_MELEE_HIT / Creature.damage_after_armor(REFERENCE_MELEE_HIT, stats.armor)
	var ranged_health := stats.max_health * REFERENCE_RANGED_HIT / Creature.damage_after_armor(REFERENCE_RANGED_HIT, stats.ranged_armor)
	var effective_health := lerpf(ranged_health, melee_health, MELEE_SHARE)
	var dps := maxf(stats.attack_damage - REFERENCE_ARMOR, 1.0) / stats.attack_cooldown + stats.poison_dps
	var power := sqrt(effective_health * dps)
	power *= 0.7 + 0.3 * stats.move_speed / 8.0
	if stats.is_ranged():
		power *= 1.3
	if stats.can_fly:
		power *= 1.25
	if stats.can_charge:
		power *= 1.1
	if stats.can_leap:
		power *= 1.1
	if stats.has_sonic:
		power *= 1.15
	if stats.pack_hunter:
		power *= 1.2
	if stats.has_frenzy:
		power *= 1.03
	if stats.has_trample:
		power *= 1.05
	if stats.has_stink:
		power *= 1.14
	if stats.has_camouflage:
		power *= 1.1
	if stats.herding:
		power *= 1.08
	if stats.has_electric:
		power *= 1.15
	if stats.water_only:
		# Stuck in the water: it can only fight what comes near.
		power *= 0.7
	elif stats.can_swim:
		power *= 1.05
	return power


static func level_for(power: float) -> int:
	var level := 1
	for threshold in LEVEL_THRESHOLDS:
		if power >= threshold:
			level += 1
	return mini(level, MAX_LEVEL)


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
	recipe.cost_coal = int(snappedf(power * COAL_PER_POWER, 5.0))
	recipe.cost_electricity = (stats.level - 1) * 35
	recipe.build_time = snappedf(4.0 + power * 0.12, 0.5)
	return recipe
