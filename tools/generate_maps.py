#!/usr/bin/env python3
"""Generates the skirmish map scenes from the layouts below.

Run from the repository root:  python3 tools/generate_maps.py

Each map is a full scene (world, units, camera, AI, HUD). Edit a layout and
re-run to change a map; Godot reloads the .tscn files. Positions are (x, z)
on the ground plane; the playable area is -50..50 on both axes.
"""

from pathlib import Path

LAYOUTS = {
    "scenes/main.tscn": {
        "name": "Island Clearing",
        "ground_color": (0.3, 0.42, 0.2),
        "rocks": [(-12, -6), (10, -4), (-4, -14), (16, 10), (-18, 12), (4, -24), (-26, -20), (24, -18)],
        "coal": [(15, 34), (17, 27), (-15, -34), (-17, -27), (-32, 4), (32, -4)],
        "bases": [
            {"lab": (0, 36), "generator": (-10, 42), "henchmen": [(-3, 31), (-1, 31), (1, 31), (3, 31)], "army": (0, 25)},
            {"lab": (0, -40), "generator": (-10, -43), "henchmen": [(-2, -35), (0, -35), (2, -35)], "army": (0, -31)},
        ],
    },
    "scenes/maps/canyon.tscn": {
        "name": "Canyon",
        "ground_color": (0.52, 0.42, 0.28),
        # A north-south rock wall down the middle with three passes, plus cover.
        "rocks": [(0, z) for z in (-46, -42, -38, -34, -30, -16, -12, -8, 8, 12, 16, 30, 34, 38, 42, 46)]
        + [(-20, -30), (20, 30), (-18, 22), (18, -22), (-12, 4), (12, -4)],
        "coal": [(-36, -14), (-28, 12), (36, 14), (28, -12), (0, -23), (0, 23)],
        "bases": [
            {"lab": (-38, 0), "generator": (-42, 10), "henchmen": [(-33, -3), (-33, -1), (-33, 1), (-33, 3)], "army": (-27, 0)},
            {"lab": (38, 0), "generator": (42, -10), "henchmen": [(33, -2), (33, 0), (33, 2)], "army": (27, 0)},
        ],
    },
    "scenes/maps/crossroads.tscn": {
        "name": "Crossroads",
        "ground_color": (0.36, 0.44, 0.24),
        # Four corner bases; a rock ring in the middle splits the centre coal.
        "rocks": [(0, 0), (5, 5), (-5, -5), (5, -5), (-5, 5), (0, 30), (0, -30), (30, 0), (-30, 0),
                  (18, 18), (-18, 18), (18, -18), (-18, -18)],
        "coal": [(-24, 42), (-42, 22), (24, 42), (42, 22), (24, -42), (42, -22), (-24, -42), (-42, -22),
                 (0, 14), (0, -14), (14, 0), (-14, 0)],
        # Teams 0 and 1 share the south edge, so they are neighbours (allies in 2v2).
        "bases": [
            {"lab": (-38, 38), "generator": (-44, 29), "henchmen": [(-32, 33), (-31, 31), (-33, 31), (-32, 29)], "army": (-26, 26)},
            {"lab": (38, 38), "generator": (44, 29), "henchmen": [(32, 33), (31, 31), (33, 31)], "army": (26, 26)},
            {"lab": (38, -38), "generator": (44, -29), "henchmen": [(32, -33), (31, -31), (33, -31)], "army": (26, -26)},
            {"lab": (-38, -38), "generator": (-44, -29), "henchmen": [(-32, -33), (-31, -31), (-33, -31)], "army": (-26, -26)},
        ],
    },
}


def color(rgb):
    return "Color(%s, %s, %s, 1)" % rgb


def build(layout):
    ext = []
    ids = {}

    def add(kind, path, key):
        ids[key] = f"{len(ext) + 1}_{key}"
        ext.append((kind, path, ids[key]))

    add("Script", "res://scripts/main.gd", "main")
    add("PackedScene", "res://scenes/props/rock.tscn", "rock")
    add("PackedScene", "res://scenes/units/henchman.tscn", "henchman_scene")
    add("Resource", "res://resources/creatures/henchman.tres", "henchman")
    add("PackedScene", "res://scenes/camera/rts_camera.tscn", "camera")
    add("Script", "res://scripts/selection/selection_manager.gd", "selection")
    add("Script", "res://scripts/ui/selection_box.gd", "box")
    add("Script", "res://scripts/ui/hud.gd", "hud")
    add("Script", "res://scripts/ai/ai_controller.gd", "ai")
    add("Script", "res://scripts/ui/health_bars.gd", "health_bars")
    add("PackedScene", "res://scenes/buildings/building.tscn", "building")
    for b in ("lab", "house", "generator", "creature_chamber", "workshop", "research_center", "soundbeam_tower"):
        add("Resource", f"res://resources/buildings/{b}.tres", "b_" + b)
    add("Script", "res://scripts/buildings/building_data.gd", "building_data")
    add("PackedScene", "res://scenes/world/coal_pile.tscn", "coal_pile")
    add("Script", "res://scripts/buildings/build_placer.gd", "build_placer")
    add("Script", "res://scripts/game/game_rules.gd", "game_rules")
    add("Script", "res://scripts/game/fog_of_war.gd", "fog")
    add("Shader", "res://shaders/fog_ground.gdshader", "fog_shader")
    add("Script", "res://scripts/ui/minimap.gd", "minimap")

    sub_resources = 8
    o = [f"[gd_scene load_steps={len(ext) + sub_resources + 1} format=3]\n"]
    for kind, path, rid in ext:
        o.append(f'[ext_resource type="{kind}" path="{path}" id="{rid}"]')
    o.append(f'''
[sub_resource type="ProceduralSkyMaterial" id="ProceduralSkyMaterial_sky"]
sky_top_color = Color(0.38, 0.56, 0.78, 1)
sky_horizon_color = Color(0.72, 0.78, 0.8, 1)
ground_horizon_color = Color(0.72, 0.78, 0.8, 1)

[sub_resource type="Sky" id="Sky_main"]
sky_material = SubResource("ProceduralSkyMaterial_sky")

[sub_resource type="Environment" id="Environment_main"]
background_mode = 2
sky = SubResource("Sky_main")
ambient_light_source = 3
ambient_light_energy = 0.5
tonemap_mode = 2

[sub_resource type="NavigationMesh" id="NavigationMesh_map"]
resource_local_to_scene = true
geometry_parsed_geometry_type = 1
geometry_collision_mask = 13
cell_size = 0.25
cell_height = 0.25
agent_height = 1.5
agent_radius = 0.5
agent_max_climb = 0.25
region_min_size = 30.0

[sub_resource type="BoxShape3D" id="BoxShape3D_ground"]
size = Vector3(100, 1, 100)

[sub_resource type="ShaderMaterial" id="ShaderMaterial_ground"]
render_priority = 0
shader = ExtResource("{ids["fog_shader"]}")
shader_parameter/albedo = {color(layout["ground_color"])}

[sub_resource type="PlaneMesh" id="PlaneMesh_ground"]
material = SubResource("ShaderMaterial_ground")
size = Vector2(100, 100)
subdivide_width = 20
subdivide_depth = 20

[node name="Main" type="Node3D"]
script = ExtResource("{ids["main"]}")

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment_main")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.866025, -0.353553, 0.353553, 0, 0.707107, 0.707107, -0.5, -0.612372, 0.612372, 0, 20, 0)
shadow_enabled = true
directional_shadow_max_distance = 120.0

[node name="NavigationRegion3D" type="NavigationRegion3D" parent="."]
navigation_mesh = SubResource("NavigationMesh_map")

[node name="Ground" type="StaticBody3D" parent="NavigationRegion3D"]

[node name="CollisionShape3D" type="CollisionShape3D" parent="NavigationRegion3D/Ground"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.5, 0)
shape = SubResource("BoxShape3D_ground")

[node name="MeshInstance3D" type="MeshInstance3D" parent="NavigationRegion3D/Ground"]
mesh = SubResource("PlaneMesh_ground")

[node name="Rocks" type="Node3D" parent="NavigationRegion3D"]
''')
    for n, (x, z) in enumerate(layout["rocks"], 1):
        o.append(f'[node name="Rock{n}" parent="NavigationRegion3D/Rocks" instance=ExtResource("{ids["rock"]}")]\n'
                 f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, 0, {z})\n')
    o.append('[node name="CoalPiles" type="Node3D" parent="NavigationRegion3D"]\n')
    for n, (x, z) in enumerate(layout["coal"], 1):
        o.append(f'[node name="CoalPile{n}" parent="NavigationRegion3D/CoalPiles" instance=ExtResource("{ids["coal_pile"]}")]\n'
                 f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, 0, {z})\n')
    # Buildings live under the navigation region so rebakes include them.
    o.append('[node name="Buildings" type="Node3D" parent="NavigationRegion3D" groups=["building_container"]]\n')
    for team, base in enumerate(layout["bases"]):
        for kind in ("lab", "generator"):
            x, z = base[kind]
            o.append(f'[node name="Team{team}{kind.capitalize()}" parent="NavigationRegion3D/Buildings" instance=ExtResource("{ids["building"]}")]\n'
                     f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, 0, {z})\n'
                     f'data = ExtResource("{ids["b_" + kind]}")' + (f"\nteam = {team}" if team else "") + "\n")
    o.append('[node name="Units" type="Node3D" parent="." groups=["unit_container"]]\n')
    for team, base in enumerate(layout["bases"]):
        for n, (x, z) in enumerate(base["henchmen"], 1):
            o.append(f'[node name="Team{team}Henchman{n}" parent="Units" instance=ExtResource("{ids["henchman_scene"]}")]\n'
                     f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, 0, {z})\n'
                     f'stats = ExtResource("{ids["henchman"]}")' + (f"\nteam = {team}" if team else "") + "\n")
    for team, base in enumerate(layout["bases"]):
        ax, az = base["army"]
        lx, lz = base["lab"]
        # Start locations are public knowledge (the AI uses them to look for enemies).
        o.append(f'[node name="ArmySpawn{team}" type="Marker3D" parent="."]\n'
                 f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {ax}, 0, {az})\n')
        o.append(f'[node name="StartLocation{team}" type="Marker3D" parent="." groups=["start_locations"]]\n'
                 f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {lx}, 0, {lz})\n'
                 f'metadata/team = {team}\n')
    cx, cz = layout["bases"][0]["army"]
    cz += 3 if cz > 0 else -3
    o.append(f'''[node name="RTSCamera" parent="." instance=ExtResource("{ids["camera"]}")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {cx}, 0, {cz})

[node name="BuildPlacer" type="Node3D" parent="."]
script = ExtResource("{ids["build_placer"]}")

[node name="SelectionManager" type="Node" parent="." node_paths=PackedStringArray("camera", "selection_box", "build_placer")]
script = ExtResource("{ids["selection"]}")
camera = NodePath("../RTSCamera/Camera3D")
selection_box = NodePath("../UI/SelectionBox")
build_placer = NodePath("../BuildPlacer")
buildable = Array[ExtResource("{ids["building_data"]}")]([ExtResource("{ids["b_lab"]}"), ExtResource("{ids["b_house"]}"), ExtResource("{ids["b_generator"]}"), ExtResource("{ids["b_creature_chamber"]}"), ExtResource("{ids["b_workshop"]}"), ExtResource("{ids["b_research_center"]}"), ExtResource("{ids["b_soundbeam_tower"]}")])

[node name="EnemyAI" type="Node" parent="."]
script = ExtResource("{ids["ai"]}")

[node name="GameRules" type="Node" parent="."]
script = ExtResource("{ids["game_rules"]}")

[node name="FogOfWar" type="Node" parent="." node_paths=PackedStringArray("ground")]
script = ExtResource("{ids["fog"]}")
ground = NodePath("../NavigationRegion3D/Ground/MeshInstance3D")

[node name="UI" type="CanvasLayer" parent="."]

[node name="HealthBars" type="Control" parent="UI" node_paths=PackedStringArray("camera")]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("{ids["health_bars"]}")
camera = NodePath("../../RTSCamera/Camera3D")

[node name="HUD" type="Control" parent="UI" node_paths=PackedStringArray("selection_manager", "game_rules")]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("{ids["hud"]}")
selection_manager = NodePath("../../SelectionManager")
game_rules = NodePath("../../GameRules")

[node name="SelectionLabel" type="Label" parent="UI/HUD"]
layout_mode = 0
offset_left = 16.0
offset_top = 12.0
offset_right = 916.0
offset_bottom = 160.0
theme_override_colors/font_outline_color = Color(0, 0, 0, 1)
theme_override_constants/outline_size = 4
text = "No units selected"

[node name="ControlsLabel" type="Label" parent="UI/HUD"]
layout_mode = 1
anchors_preset = 2
anchor_top = 1.0
anchor_bottom = 1.0
offset_left = 232.0
offset_top = -222.0
offset_right = 976.0
offset_bottom = -12.0
grow_vertical = 0
theme_override_colors/font_outline_color = Color(0, 0, 0, 1)
theme_override_constants/outline_size = 4
text = "Left click / drag: select   Shift: add   Double click / Ctrl + click: all of a type
Right click: move / attack / gather coal (Henchmen) / set rally point (building)
Shift + right click: queue order   Period: idle Henchman   Home: Lab   Space: last alert
F + click or Ctrl + right click: attack-move   P + click: patrol   G: hold   H: stop   Esc: cancel
Ctrl+1-9: set control group   1-9: recall group   Minimap: click to look, right click to order
WASD / arrows / screen edge / middle drag: pan   Q / E: rotate   Wheel: zoom
Z X C V B N M: command buttons   Shift + button: make 5"
vertical_alignment = 2

[node name="Minimap" type="Control" parent="UI/HUD" node_paths=PackedStringArray("camera_rig", "selection_manager", "fog")]
layout_mode = 1
anchors_preset = 2
anchor_top = 1.0
anchor_bottom = 1.0
offset_left = 16.0
offset_top = -216.0
offset_right = 216.0
offset_bottom = -16.0
grow_vertical = 0
script = ExtResource("{ids["minimap"]}")
camera_rig = NodePath("../../../RTSCamera")
selection_manager = NodePath("../../../SelectionManager")
fog = NodePath("../../../FogOfWar")
ground_color = {color(layout["ground_color"])}

[node name="SelectionBox" type="Control" parent="UI"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("{ids["box"]}")
''')
    return "\n".join(o)


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    for path, layout in LAYOUTS.items():
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(build(layout))
        print(f"wrote {path} ({layout['name']})")
