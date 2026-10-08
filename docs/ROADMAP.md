# Roadmap

A rough plan. Each milestone should be playable on its own.

## M1 — Core RTS loop ✅
Camera, selection, control groups, pathfinding, avoidance, formations, placeholder units.

## M2 — Combat ✅
Health, armor, melee and ranged (projectile) attacks, death, health bars, attack and attack-move
orders, stop, auto-targeting with a leash, allies helping when attacked, group-speed formations, and
an enemy AI that defends and sends waves.

Follow-ups — all done:
- Smarter target choice ✅ (armor-aware, finishes wounded targets, focus fire with nearby allies)
- Ranged units keeping their distance ✅ (kite away from melee attackers, then keep shooting)
- Hold-position (G) and patrol (P) orders ✅
- Abilities ✅ (arrived with the combiner in M4: poison, quills, flight, charge, leap)

## M3 — Economy and base building ✅
Coal and electricity, Henchmen that gather and build, Lab / Electrical Generator / Creature Chamber,
placement with a ghost preview and runtime navmesh rebakes, production queues with refunds, rally
points, destructible buildings, victory and defeat, and an enemy AI that runs an economy.

Follow-up pass ✅: research levels 1–5 at the Lab gate creature production, and the enemy AI builds
its own Creature Chamber and Generators, researches (saving up once its army is big enough), and
produces the strongest creatures it has unlocked.

Follow-ups:
- Enemy AI that expands to more coal ✅ (new Labs at unclaimed coal, saving up for them)
- More buildings from the original: Workshop ✅ and Soundbeam Tower ✅; Lightning Rod, Aviary and
  Water Chamber still to come (the Water Chamber needs water on the maps first)
- Research ✅ and upgrades ✅: tiered creature upgrades at the Research Center (melee/ranged damage
  and melee/ranged armor), Henchman upgrades at the Workshop; research levels stay at the Lab
- AoE2-style QoL: population and Houses ✅, Research Center ✅, split melee/ranged armor ✅; idle
  Henchman key, under-attack alerts, select-all-of-type, queued orders and hotkeys next
- Minimap ✅ (M6)

## M4 — The creature combiner ✅
8 animals with per-part stats, combination rules (size, leg load, level and cost), abilities from
parts (flying, poison, ranged quills), hybrid models assembled from parts, a combiner screen with a
live preview, saved armies of up to 9 that the Creature Chamber produces, smarter target choice, and
a main menu.

Polish pass ✅: 12 animals (added Wolf, Kangaroo, Bat, Crocodile), charge and leap abilities, and
matches start with a budgeted army from each side's roster.

Follow-ups:
- More abilities from the original (swimming, sonic, electric, herding, stink...)
- Water, so swimmers and the Water Chamber make sense; Aviary for flyers

## M5 — Creature visuals
- Modular, rigged animal parts that can be attached to each other
- Shared animation set (idle, walk, attack, death) that works on hybrid bodies
- Low-poly stylised art direction that's achievable for a small team

## M6 — Skirmish ✅
Fog of war (per team, the AI included), minimap with camera jump and orders, a smarter AI (defends,
attacks scouted targets or the likely enemy base, growing waves, rebuilds), Easy/Normal/Hard, a
second map (Canyon), and a skirmish setup screen.

Follow-ups:
- Hide coal piles and rocks under unexplored fog; "last seen" ghosts for destroyed enemy buildings ✅
- AI that expands to distant coal with a second Lab, retreats wounded units, and focuses fire ✅
  (Labs now heal nearby creatures, which is where wounded AI creatures retreat to)
- More maps, 2v2 / free-for-all with more AI players ✅ (Crossroads, up to 4 players, alliances)
- Pause menu, game speed setting, end-of-match statistics ✅

## Later
- Single-player campaign (an original story in the spirit of the 1930s pulp-adventure setting)
- Multiplayer (Godot high-level multiplayer, deterministic lockstep or server-authoritative)
- Modding support: data-driven animals and maps
