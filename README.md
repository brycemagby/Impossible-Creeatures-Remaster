# Impossible Creatures Remake

A fan remake of Relic Entertainment's *Impossible Creatures* (2003), built in **Godot 4** with GDScript.

> This is an unofficial, non-commercial fan project. It is not affiliated with or endorsed by
> Relic Entertainment, Microsoft, or THQ Nordic. No original game assets are included; all art
> and audio in this repository are original placeholders.

![Prototype screenshot](docs/screenshot.png)

## Status

Milestones 1 (**core RTS loop**), 2 (**combat**) and 3 (**economy and base building**) are working
with placeholder art:

- Top-down RTS camera: keyboard, screen-edge and middle-drag panning, rotation and smooth zoom, clamped to the map
- Unit selection: click, shift-click, drag box, control groups
- Move orders: navmesh pathfinding around obstacles, local avoidance between units, grid formations that move at the slowest unit's speed
- Combat: health, armor, melee hits, homing projectiles for ranged units, death animation
- Orders: move, attack, attack-move, stop
- Unit behavior: idle units engage enemies in sight, chase up to a leash range and then return to their post; units fight back when hit and call nearby allies to help
- Economy: coal (gathered from coal piles by Henchmen) and electricity (made by Electrical Generators)
- Base building: Lab, Electrical Generator and Creature Chamber, placed with a ghost preview and
  constructed by Henchmen; the navmesh updates as buildings go up or come down
- Production queues (up to 5, cancel refunds), rally points
- Buildings can be attacked and destroyed, and nearby units come to defend them
- Win by destroying every enemy unit and building
- Enemy AI that gathers coal, produces Henchmen and creatures, defends, and sends attack waves
- Health bars, a resource counter, and a command panel with build and production buttons
- Creature types defined as data (`CreatureStats` resources); the combiner will generate these later
- Headless tests

See [docs/ROADMAP.md](docs/ROADMAP.md) for what comes next.

## Running

1. Install [Godot 4.3+](https://godotengine.org/download) (the standard build; .NET isn't needed).
2. Open Godot, click **Import**, and select this folder's `project.godot`.
3. Press **F5** to run the test skirmish map.

## Controls

| Input | Action |
| --- | --- |
| Left click | Select unit (Shift: add/remove) |
| Left drag | Box select (Shift: add) |
| Right click ground | Move selected units |
| Right click enemy unit or building | Attack it |
| Right click coal (Henchmen selected) | Gather coal |
| Right click unfinished building (Henchmen selected) | Help build it |
| Right click with a building selected | Set rally point (click the building itself to clear) |
| Command panel buttons (bottom right) | Build (Henchmen selected) or produce units (building selected) |
| Left click while placing | Place the building (Shift: keep placing) |
| F then left click, or Ctrl + right click | Attack-move (fight anything met on the way) |
| H | Stop |
| Esc | Cancel placement or attack-move targeting, otherwise deselect |
| Ctrl+1–9 / 1–9 | Assign / recall control group |
| WASD, arrows, screen edge, middle drag | Pan camera |
| Q / E | Rotate camera |
| Mouse wheel | Zoom |

Keyboard bindings are registered in `scripts/autoload/input_actions.gd`. Any action you define
in **Project Settings → Input Map** with the same name overrides the default.

## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn
```

The tests load the skirmish map and drive selection and orders through real input events. They
cover movement, combat, the leash, allies helping, the enemy AI, gathering, production, costs and
refunds, building placement and construction, navmesh updates, attacking buildings, victory, and the
HUD buttons. They exit non-zero on failure.

## Project layout

```
scenes/
  main.tscn              Test skirmish map (ground, rocks, units, camera, UI)
  camera/rts_camera.tscn Camera rig
  units/creature.tscn    Generic creature unit (placeholder capsule)
  units/henchman.tscn    Worker unit
  buildings/building.tscn Generic building, sized and coloured from BuildingData
  world/coal_pile.tscn   Coal deposit
  props/rock.tscn        Obstacle
  fx/move_marker.tscn    Order feedback ring
  fx/projectile.tscn     Ranged attack projectile
scripts/
  autoload/              Global singletons (input bindings, Economy)
  ai/                    Enemy AI controller
  buildings/             Building, BuildingData, UnitRecipe, build placement
  game/                  Win condition
  world/                 Coal piles
  camera/                RTS camera
  selection/             Selection + order handling
  units/                 Creature behaviour, orders, combat, Henchman work, CreatureStats data
  ui/                    HUD, health bars, and drag-select box
resources/creatures/     Creature stat sheets
resources/buildings/     Building definitions (cost, size, production)
resources/recipes/       What each unit costs to produce
tests/                   Headless smoke tests
```

Physics layers: 1 = `world` (ground, rocks), 2 = `units`, 3 = `buildings`, 4 = `resources` (coal).
Layers 1, 3 and 4 are baked into the navmesh.

### Costs (placeholder balance)

| | Coal | Electricity | Time |
| --- | --- | --- | --- |
| Henchman | 50 | — | 6 s |
| Runner | 60 | 20 | 8 s |
| Skirmisher | 80 | 40 | 10 s |
| Brute | 120 | 60 | 14 s |
| Electrical Generator (+2 electricity/s) | 150 | — | 18 Henchman-seconds |
| Creature Chamber | 200 | 50 | 30 Henchman-seconds |
| Lab | 400 | — | 45 Henchman-seconds |

Teams start with 300 coal and 100 electricity. Henchmen carry 10 coal per trip.
