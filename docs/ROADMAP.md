# Roadmap

A rough plan. Each milestone should be playable on its own.

## M1 — Core RTS loop ✅
Camera, selection, control groups, pathfinding, avoidance, formations, placeholder units.

## M2 — Combat
- Health, damage, death, and health bars
- Attack-move and targeted attack orders, auto-acquiring nearby enemies
- Melee and ranged attacks, armour
- Basic enemy AI that defends and counter-attacks

## M3 — Economy and base building
- Resources: coal and electricity
- Henchmen: gather coal, construct buildings
- Buildings: Lab, Creature Chamber, Electrical Generator, Lightning Rod, and so on
- Placing buildings (with a ghost preview) and updating the navmesh at runtime
- Production queues and rally points

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
