class_name UpgradeData
extends Resource
## A one-off, team-wide improvement bought at a Workshop.

@export var id: StringName
@export var display_name := "Upgrade"
@export_multiline var description := ""
@export var cost_coal := 100
@export var cost_electricity := 0
## Seconds to complete at the Workshop.
@export var duration := 30.0
## Research level needed before it can be bought.
@export var required_research := 1
