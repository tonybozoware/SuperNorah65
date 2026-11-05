extends Area3D
## Respawns the player at the spawn marker when they fall into this area.

@export var spawn: Marker3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		(body as Player).respawn(spawn.global_position)
