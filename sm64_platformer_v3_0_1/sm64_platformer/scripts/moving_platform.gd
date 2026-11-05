extends AnimatableBody3D
## Moves back and forth between its start position and start + offset.

@export var offset := Vector3(-8.0, 0.0, 0.0)
@export var period := 6.0

var _start: Vector3
var _time := 0.0


func _ready() -> void:
	_start = global_position
	process_physics_priority = -10   # move before the player each tick


func _physics_process(delta: float) -> void:
	_time += delta
	global_position = _start + offset * (0.5 - 0.5 * cos(TAU * _time / period))
