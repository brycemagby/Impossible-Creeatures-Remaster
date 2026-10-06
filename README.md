# Impossible Creatures Remake

A fan remake of Relic Entertainment's *Impossible Creatures* (2003), built in **Godot 4** with GDScript.

> This is an unofficial, non-commercial fan project. It is not affiliated with or endorsed by
> Relic Entertainment, Microsoft, or THQ Nordic. No original game assets are included; all art
> and audio in this repository are original placeholders.

![Prototype screenshot](docs/screenshot.png)

## Status

Milestone 1, the **core RTS loop**, is working with placeholder art:

- Top-down RTS camera: keyboard, screen-edge and middle-drag panning, rotation and smooth zoom, clamped to the map
- Unit selection: click, shift-click, drag box, control groups
- Move orders: navmesh pathfinding around obstacles, local avoidance between units, grid formations
- Creature types defined as data (`CreatureStats` resources); the combiner will generate these later
- HUD that shows the current selection, plus a controls cheat sheet
- Headless smoke tests

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
| Right click | Move selected units |
| Esc | Deselect |
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

The test loads the skirmish map and drives selection through real input events. It issues a move
order around obstacles and checks that every unit arrives. It exits non-zero on failure.

## Project layout

```
scenes/
  main.tscn              Test skirmish map (ground, rocks, units, camera, UI)
  camera/rts_camera.tscn Camera rig
  units/creature.tscn    Generic creature unit (placeholder capsule)
  props/rock.tscn        Obstacle
  fx/move_marker.tscn    Move-order feedback ring
scripts/
  autoload/              Global singletons (input bindings)
  camera/                RTS camera
  selection/             Selection + order handling
  units/                 Creature behaviour and CreatureStats data
  ui/                    HUD and drag-select box
resources/creatures/     Placeholder creature stat sheets
tests/                   Headless smoke tests
```

Physics layers: 1 = `world` (ground, obstacles; baked into the navmesh), 2 = `units`.
