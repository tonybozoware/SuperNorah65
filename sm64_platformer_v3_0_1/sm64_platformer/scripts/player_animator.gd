extends Node3D
## Player animation. Lives on Player/Visual and reads the player's state.
##
## Whole-body motion (facing, squash, lean, flips, spins) is done in code on
## Visual (pivot at the feet) and on the hip pivot (Body). The primitive body is
## then posed part by part (head, arms, legs) for each state.

const S := Player.State

@export var pose_sharpness := 18.0

@onready var player: Player = get_parent()
@onready var body: Node3D = $Body
@onready var head: Node3D = $Body/HeadPivot
@onready var arm_l: Node3D = $Body/ArmL
@onready var arm_r: Node3D = $Body/ArmR
@onready var leg_l: Node3D = $Body/LegL
@onready var leg_r: Node3D = $Body/LegR

var _cycle := 0.0
var _time := 0.0
var _yaw := 0.0
var _squash := 1.0
var _last_state := -1
var _roll_angle := 0.0
var _state_time := 0.0
var _pose := {
	"lean": 0.0, "roll": 0.0, "body_y": 0.0, "head": 0.0,
	"arm_l": 0.0, "arm_r": 0.0, "arm_l_out": 0.1, "arm_r_out": 0.1,
	"leg_l": 0.0, "leg_r": 0.0,
}


func _ready() -> void:
	_yaw = player.facing


func _process(delta: float) -> void:
	_time += delta
	var st := player.state
	# Time in the current state, advanced every displayed frame (not the 30 Hz
	# movement tick) so flips and spins are as smooth as everything else.
	if st != _last_state:
		_on_enter(st)
		_last_state = st
		_state_time = 0.0
	else:
		_state_time += delta
	var t := _state_time

	# Facing: turn quickly rather than snapping (skids, wall kicks).
	_yaw = lerp_angle(_yaw, player.facing, 1.0 - exp(-25.0 * delta))
	rotation.y = _yaw

	if st == S.ROLL:
		_roll_angle = fmod(_roll_angle + delta * player.forward_speed * Player.U / 0.45, TAU)
	else:
		_roll_angle = 0.0
	var target := _target_pose(st, t, delta)
	var spin := _spin(st, t)
	var blend := 1.0 - exp(-pose_sharpness * delta)
	for key in _pose:
		_pose[key] = lerpf(_pose[key], target[key], blend)

	# Squash recovers toward 1 (landings set it lower in _on_enter).
	var squash_target := 0.85 if st in Player.CROUCH_STATES or st == S.ROLL else 1.0
	_squash = lerpf(_squash, squash_target, 1.0 - exp(-12.0 * delta))
	scale = Vector3(1.0 / sqrt(_squash), _squash, 1.0 / sqrt(_squash))

	body.position.y = 0.8 + _pose.body_y
	body.rotation = Vector3(_pose.lean + spin.x, 0.0, _pose.roll + spin.z)
	head.rotation.x = _pose.head
	arm_l.rotation = Vector3(_pose.arm_l, 0.0, _pose.arm_l_out)
	arm_r.rotation = Vector3(_pose.arm_r, 0.0, -_pose.arm_r_out)
	leg_l.rotation.x = _pose.leg_l
	leg_r.rotation.x = _pose.leg_r


func _on_enter(st: int) -> void:
	match st:
		S.LAND:
			var impact := clampf(player.last_land_speed / 75.0, 0.0, 1.0)
			_squash = 0.9 - 0.2 * impact
		S.POUND_LAND:
			_squash = 0.6
		S.SIDE_FLIP:
			_yaw = player.facing   # the flip itself shows the turn


func _target_pose(st: int, t: float, delta: float) -> Dictionary:
	var p := {
		"lean": 0.0, "roll": 0.0, "body_y": 0.0, "head": 0.0,
		"arm_l": 0.0, "arm_r": 0.0, "arm_l_out": 0.1, "arm_r_out": 0.1,
		"leg_l": 0.0, "leg_r": 0.0,
	}
	var speed_ratio := clampf(player.forward_speed / player.max_walk_speed, 0.0, 1.5)
	var rising := player.vy > 0.0

	match st:
		S.IDLE:
			p.body_y = sin(_time * 2.0) * 0.012
			p.arm_l_out = 0.12 + sin(_time * 2.0) * 0.03
			p.arm_r_out = p.arm_l_out
		S.WALK, S.SKID_END, S.LAND:
			_cycle += delta * lerpf(5.0, 13.0, minf(speed_ratio, 1.0))
			var swing := sin(_cycle) * lerpf(0.35, 1.0, minf(speed_ratio, 1.0)) * minf(speed_ratio * 3.0, 1.0)
			p.leg_l = swing
			p.leg_r = -swing
			p.arm_l = -swing * 0.9
			p.arm_r = swing * 0.9
			p.lean = -0.25 * minf(speed_ratio, 1.0)
			p.body_y = -absf(cos(_cycle)) * 0.06 * minf(speed_ratio, 1.0)
			p.arm_l_out = 0.15
			p.arm_r_out = 0.15
			if st == S.LAND:
				p.body_y -= 0.08
		S.BRAKE, S.SKID:
			p.lean = 0.35
			p.arm_l_out = 1.1
			p.arm_r_out = 1.1
			p.leg_l = -0.5
			p.leg_r = -0.2
			p.body_y = -0.08
		S.CROUCH:
			p.body_y = -0.3
			p.lean = -0.25
			p.leg_l = 1.2
			p.leg_r = 1.2
			p.arm_l = 0.6
			p.arm_r = 0.6
			p.head = 0.2
		S.CRAWL:
			_cycle += delta * lerpf(3.0, 8.0, minf(speed_ratio * 10.0, 1.0))
			var c := sin(_cycle) * 0.35
			p.body_y = -0.38
			p.lean = -1.15
			p.arm_l = 1.5 + c
			p.arm_r = 1.5 - c
			p.leg_l = 0.4 - c
			p.leg_r = 0.4 + c
			p.head = 0.9
		S.CROUCH_SLIDE:
			p.body_y = -0.3
			p.lean = 0.25
			p.leg_l = 1.3
			p.leg_r = 1.1
			p.arm_l = -0.5
			p.arm_r = -0.5
			p.arm_l_out = 0.5
			p.arm_r_out = 0.5
		S.JUMP, S.FALL, S.WALL_KICK:
			if st == S.WALL_KICK and t < 0.15:
				p.leg_l = -0.7
				p.leg_r = -0.4
				p.arm_l = -0.8
				p.arm_r = -0.8
			elif rising and st != S.FALL:
				p.arm_r = 2.8
				p.arm_l = -0.4
				p.leg_l = 0.8
				p.leg_r = -0.2
				p.lean = -0.1
			else:
				p.arm_l = 0.5
				p.arm_r = 0.5
				p.arm_l_out = 1.2
				p.arm_r_out = 1.2
				p.leg_l = 0.35
				p.leg_r = -0.3
		S.DOUBLE_JUMP:
			if rising:
				p.arm_l = 2.9
				p.arm_r = 2.9
				p.arm_l_out = 0.3
				p.arm_r_out = 0.3
				p.leg_l = 1.0
				p.leg_r = 0.5
			else:
				p.arm_l_out = 1.3
				p.arm_r_out = 1.3
				p.leg_l = 0.3
				p.leg_r = -0.3
		S.TRIPLE_JUMP, S.BACKFLIP, S.SIDE_FLIP:
			var flipping := t < _flip_time(st)
			if flipping:
				p.leg_l = 1.7
				p.leg_r = 1.7
				p.arm_l = 1.0
				p.arm_r = 1.0
				p.head = 0.4
				p.body_y = 0.1
			else:
				p.arm_l_out = 1.3
				p.arm_r_out = 1.3
				p.leg_l = 0.3
				p.leg_r = -0.3
		S.LONG_JUMP:
			p.lean = -1.25
			p.arm_l = 3.0
			p.arm_r = 3.0
			p.arm_l_out = 0.15
			p.arm_r_out = 0.15
			p.leg_l = -0.15
			p.leg_r = 0.1
			p.head = -0.9
		S.WALL_BONK:
			p.lean = 0.15
			p.arm_l = 1.4
			p.arm_r = 1.4
			p.arm_l_out = 0.4
			p.arm_r_out = 0.4
			p.leg_l = 0.4
			p.leg_r = 0.1
		S.GROUND_POUND:
			p.leg_l = 1.6
			p.leg_r = 1.6
			p.arm_l = 0.9
			p.arm_r = 0.9
			p.body_y = 0.1
			p.head = 0.3
		S.DIVE:
			# Stretched out, tipping nose-down as the fall speeds up.
			p.lean = lerpf(-1.3, -1.85, clampf(-player.vy / 40.0, 0.0, 1.0))
			p.arm_l = 3.0
			p.arm_r = 3.0
			p.arm_l_out = 0.2
			p.arm_r_out = 0.2
			p.leg_l = -0.15
			p.leg_r = 0.05
			p.head = -1.1
		S.BELLY_SLIDE:
			p.lean = -1.57
			p.body_y = -0.52
			p.arm_l = 3.0
			p.arm_r = 3.0
			p.arm_l_out = 0.3
			p.arm_r_out = 0.3
			p.leg_l = 0.0
			p.leg_r = 0.1
			p.head = -1.2
		S.BELLY_GETUP:
			p.body_y = -0.25
			p.lean = -0.5
			p.leg_l = 0.9
			p.leg_r = 0.6
			p.arm_l = 0.8
			p.arm_r = 0.8
		S.ROLLOUT:
			if t < _flip_time(st):
				p.leg_l = 1.7
				p.leg_r = 1.7
				p.arm_l = 1.0
				p.arm_r = 1.0
				p.head = 0.4
			else:
				p.arm_l_out = 1.2
				p.arm_r_out = 1.2
				p.leg_l = 0.3
				p.leg_r = -0.3
		S.ROLL:
			p.body_y = -0.35
			p.leg_l = 1.8
			p.leg_r = 1.8
			p.arm_l = 1.2
			p.arm_r = 1.2
			p.head = 0.6
		S.LEDGE_HANG:
			p.arm_l = 3.05
			p.arm_r = 3.05
			p.arm_l_out = 0.25
			p.arm_r_out = 0.25
			p.lean = -0.1
			p.leg_l = 0.15 + sin(_time * 3.0) * 0.08
			p.leg_r = -0.05 - sin(_time * 3.0) * 0.08
			p.head = -0.2
		S.LEDGE_CLIMB:
			if t < player.ledge_climb_frames / 30.0 * 0.55:
				p.arm_l = 2.6
				p.arm_r = 2.6
				p.leg_l = 1.3
				p.leg_r = 0.4
				p.lean = -0.35
			else:
				p.body_y = -0.15
				p.arm_l = 0.6
				p.arm_r = 0.6
				p.leg_l = 0.9
				p.leg_r = 0.2
				p.lean = -0.4
		S.POUND_LAND:
			p.body_y = -0.12
			p.leg_l = 0.6
			p.leg_r = 0.6
			p.arm_l_out = 0.9
			p.arm_r_out = 0.9
	return p


func _flip_time(st: int) -> float:
	match st:
		S.TRIPLE_JUMP: return 0.75
		S.BACKFLIP: return 0.8
		S.SIDE_FLIP: return 0.7
		S.ROLLOUT: return 0.5
	return 0.0


## Whole-body rotation for flips (x = somersault, z = cartwheel).
func _spin(st: int, t: float) -> Vector3:
	var ft := _flip_time(st)
	match st:
		S.TRIPLE_JUMP:
			return Vector3(-TAU * _ease(t / ft), 0.0, 0.0)    # forward somersault
		S.BACKFLIP:
			return Vector3(TAU * _ease(t / ft), 0.0, 0.0)     # backward somersault
		S.SIDE_FLIP:
			return Vector3(0.0, 0.0, TAU * _ease(t / ft))     # sideways flip
		S.ROLLOUT:
			return Vector3(-TAU * _ease(t / ft), 0.0, 0.0)    # forward roll
		S.ROLL:
			return Vector3(-_roll_angle, 0.0, 0.0)            # continuous ball roll
		S.GROUND_POUND:
			var hang := player.pound_hang / 30.0
			return Vector3(-TAU * _ease(t / hang), 0.0, 0.0)  # flip, then drop
	return Vector3.ZERO


func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

