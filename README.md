# Impossible Creatures Remake

A fan remake of Relic Entertainment's *Impossible Creatures* (2003), built in **Godot 4** with GDScript.

> This is an unofficial, non-commercial fan project. It is not affiliated with or endorsed by
> Relic Entertainment, Microsoft, or THQ Nordic. No original game assets are included; all art
> and audio in this repository are original placeholders.

![Prototype screenshot](docs/screenshot.png)

## Status

Milestones 1 (**core RTS loop**) and 2 (**combat**) are working with placeholder art:

- Top-down RTS camera: keyboard, screen-edge and middle-drag panning, rotation and smooth zoom, clamped to the map
- Unit selection: click, shift-click, drag box, control groups
- Move orders: navmesh pathfinding around obstacles, local avoidance between units, grid formations that move at the slowest unit's speed
- Combat: health, armor, melee hits, homing projectiles for ranged units, death animation
- Orders: move, attack, attack-move, stop
- Unit behavior: idle units engage enemies in sight, chase up to a leash range and then return to their post; units fight back when hit and call nearby allies to help
- Enemy AI that defends its camp and sends an attack wave every 90 seconds
- Health bars, plus a HUD showing the selection (with full stats when one unit is selected)
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
| Right click enemy | Attack it |
| F then left click, or Ctrl + right click | Attack-move (fight anything met on the way) |
| H | Stop |
| Esc | Cancel attack-move targeting, otherwise deselect |
| Ctrl+1–9 / 1–9 | Assign / recall control group |
| WASD, arrows, screen edge, middle drag | Pan camera |
| Q / E | Rotate camera |
| Mouse wheel | Zoom |

Keyboard bindings are registered in `scripts/autoload/input_actions.gd`. Any action you define
in **Project Settings → Input Map** with the same name overrides the default.

## Tests

```sh
godot --headless --path . --script res://tests/run_tests.gd
```

The tests load the skirmish map and drive selection and orders through real input events. They
cover movement around obstacles, armor, melee and ranged attacks, auto-targeting, the leash, allies
helping, death, the enemy AI, and a full attack-move battle. They exit non-zero on failure.

## Project layout

```
scenes/
  main.tscn              Test skirmish map (ground, rocks, units, camera, UI)
  camera/rts_camera.tscn Camera rig
  units/creature.tscn    Generic creature unit (placeholder capsule)
  props/rock.tscn        Obstacle
  fx/move_marker.tscn    Order feedback ring
  fx/projectile.tscn     Ranged attack projectile
scripts/
  autoload/              Global singletons (input bindings)
  ai/                    Enemy AI controller
  camera/                RTS camera
  selection/             Selection + order handling
  units/                 Creature behaviour, orders, combat, and CreatureStats data
  ui/                    HUD, health bars, and drag-select box
resources/creatures/     Placeholder creature stat sheets
tests/                   Headless smoke tests
```

Physics layers: 1 = `world` (ground, obstacles; baked into the navmesh), 2 = `units`.
