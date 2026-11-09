class_name SoundKit
extends Resource
## A set of sounds for the player's actions, swapped with L (KitPlayer on Player).
## Saved as .tres files in res://kits/. A kit holds:
## - events: what plays on footsteps, jumps, landings, walls and so on
## - patch: Instruments settings applied when the kit is switched on (its starting sound)
## - routes: live links from the player to Instruments settings (how the sound moves)
## - the run meter settings the RUN route source uses

@export var kit_name := "New Kit"
@export var events: Array[KitEvent] = []
## Keep playing footstep (and roll step) events in the air, at the tempo they had on
## the ground (Visual's air_step / roll_step).
@export var steps_in_air := false

@export_group("Patch")
## Instruments setting name -> value, applied when this kit is switched on. Settings the
## previous kit changed go back to their Inspector values first.
@export var patch: Dictionary = {}

@export_group("Live Routes")
@export var routes: Array[KitModRoute] = []

@export_group("Run Meter")
## Fills while forward speed is at least this (u/f; top running speed is 40).
@export var run_hold_speed := 36.0
## Seconds of keeping up speed to fill from empty to full (8 bars at 124 BPM = 15.5).
@export var run_fill_seconds := 15.5
## Below this speed on the ground counts as stopped (u/f). Between the two, it holds.
@export var run_stop_speed := 6.0
## Slow while still holding the stick (a skid turn, a wall) only counts as stopped
## after this many seconds.
@export var run_stop_grace := 1.0
## Seconds to empty from full once stopped.
@export var run_empty_seconds := 0.5
