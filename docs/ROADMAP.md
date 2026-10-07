# Roadmap

A rough plan. Each milestone should be playable on its own.

## M1 — Core RTS loop ✅
Camera, selection, control groups, pathfinding, avoidance, formations, placeholder units.

## M2 — Combat ✅
Health, armor, melee and ranged (projectile) attacks, death, health bars, attack and attack-move
orders, stop, auto-targeting with a leash, allies helping when attacked, group-speed formations, and
an enemy AI that defends and sends waves.

Follow-ups for later milestones:
- Smarter target choice (focus fire on weak targets, ranged units keeping their distance)
- Hold-position and patrol orders
- Damage types and abilities (these arrive with the combiner, M4)

## M3 — Economy and base building ✅
Coal and electricity, Henchmen that gather and build, Lab / Electrical Generator / Creature Chamber,
placement with a ghost preview and runtime navmesh rebakes, production queues with refunds, rally
points, destructible buildings, victory and defeat, and an enemy AI that runs an economy.

Follow-ups:
- Enemy AI that builds new buildings and expands to more coal
- More buildings from the original (Workshop for upgrades, Lightning Rod, Soundbeam Tower, Aviary,
  Water Chamber)
- Research and upgrades (tie into creature levels in M4)
- Minimap (M6)

## M4 — The creature combiner
- Animal definitions: stats and abilities for each body part (head, torso, front legs, back legs, tail, wings, claws)
- Combination rules that generate a `CreatureStats` from two animals and the chosen parts
- Combiner UI with a live stat preview, and saving and loading army rosters
- Abilities that come from specific parts: flying, swimming, poison, sonic, leap, and so on
- Research levels that gate which creatures can be built

## M5 — Creature visuals
- Modular, rigged animal parts that can be attached to each other
- Shared animation set (idle, walk, attack, death) that works on hybrid bodies
- Low-poly stylised art direction that's achievable for a small team

## M6 — Skirmish
- Fog of war, minimap
- Skirmish AI that builds an economy and an army
- Several maps, win and loss conditions

## Later
- Single-player campaign (an original story in the spirit of the 1930s pulp-adventure setting)
- Multiplayer (Godot high-level multiplayer, deterministic lockstep or server-authoritative)
- Modding support: data-driven animals and maps
