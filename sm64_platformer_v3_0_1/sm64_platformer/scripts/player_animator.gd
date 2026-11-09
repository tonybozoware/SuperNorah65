extends Node3D
## Player animation. Lives on Player/Visual and reads the player's state.
##
## Whole-body motion (facing, squash, lean, flips, spins) is done in code on
## Visual (pivot at the feet) and on the hip pivot (Body). The primitive body is
## then posed part by part (head, arms, legs) for each state.

const S := Player.State
const GROUND_TILT_STATES := [S.BELLY_SLIDE, S.BELLY_GETUP, S.CROUCH_SLIDE, S.CRAWL, S.ROLL]

@export var pose_sharpness := 18.0

@export_group("Tempo")
## Full-speed run tempo. Each footstep is half a beat, so 124 BPM = 248 steps a minute.
@export var run_bpm := 124.0
@export var steps_per_beat := 2.0
## Where in the stride each footstep (sound, floor ripple, body dip) lands:
## 0 = legs passing straight under the body, 0.5 = legs fully out (one forward,
## one back), in between = partway. Values past 0.5 wrap round to the next pass.
@export_range(0.0, 1.0) var step_phase := 0.5

## Emitted on every footstep while walking or running, at `step_phase` in the stride
## (also the low point of the body's bob). strength = 0..1, how close to full speed.
signal footstep(strength: float)
## Emitted while airborne at the times footsteps would have landed, keeping the
## stride going at the rate you left the ground with (for music that runs on through
## jumps; the floor ripples don't use it). strength = 0..1 as for footstep.
signal air_step(strength: float)
## Emitted while rolling: 16th notes of run_bpm at top roll speed (Player > roll_max),
## proportionally slower as the roll slows. Carries on in the air after rolling off an
## edge (in_air = true). strength = 0..1, roll speed / roll_max.
signal roll_step(strength: float, in_air: bool)

@onready var player: Player = get_parent()
@onready var body: Node3D = $Body
@onready var head: Node3D = $Body/HeadPivot
@onready var arm_l: Node3D = $Body/ArmL
@onready var arm_r: Node3D = $Body/ArmR
@onready var leg_l: Node3D = $Body/LegL
@onready var leg_r: Node3D = $Body/LegR

var _cycle := 0.0
var _stride_rate := 0.0       # radians of stride per second at the last ground step
var _stride_strength := 0.0   # speed ratio at the last ground step
var _roll_phase := 0.0        # counts roll notes (one per 1.0)
var _roll_rate := 0.0         # roll notes per second at the last rolling frame
var _roll_strength := 0.0
var _time := 0.0
var _yaw := 0.0
var _squash := 1.0
var _last_state := -1
var _roll_angle := 0.0
var _state_time := 0.0
var _ground_n := Vector3.UP   # smoothed ground normal the low poses tilt to
var _pose := {
	"lean": 0.0, "roll": 0.0, "body_y": 0.0, "head": 0.0,
	"arm_l": 0.0, "arm_r": 0.0, "arm_l_out": 0.1, "arm_r_out": 0.1,
	"leg_l": 0.0, "leg_r": 0.0,
}


func _ready() -> void:
	_yaw = player.facing
	player.respawned.connect(func():   # no air steps on the respawn drop
		_stride_rate = 0.0
		_roll_rate = 0.0)


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

	# Lying and low poses tilt to match the ground so they don't sink into slopes;
	# standing, running and air poses stay upright.
	var n_target := Vector3.UP
	if st in GROUND_TILT_STATES and player.is_on_floor():
		var n := player.get_floor_normal()
		if n.y > 0.7:   # walkable ground only (about 45 degrees at most)
			n_target = n
	_ground_n = _ground_n.lerp(n_target, 1.0 - exp(-12.0 * delta)).normalized()
	var tilt := Basis()
	var axis := Vector3.UP.cross(_ground_n)
	if axis.length() > 0.0001:
		tilt = Basis(axis.normalized(), acos(clampf(_ground_n.y, -1.0, 1.0)))

	if st == S.ROLL:
		_roll_angle = fmod(_roll_angle + delta * player.forward_speed * Player.U / 0.45, TAU)
		var ratio := clampf(absf(player.forward_speed) / maxf(player.roll_max, 0.01), 0.0, 1.0)
		if _roll_rate <= 0.0:
			_roll_phase = 0.9999   # a new roll: its first note plays as it starts
		_roll_rate = run_bpm / 60.0 * 4.0 * ratio   # 16ths at top roll speed
		_roll_strength = ratio
		_roll_steps(delta, false)
	elif st in Player.AIR_STATES:
		_roll_angle = 0.0
		_roll_steps(delta, true)   # rolled off an edge: keep the 16ths going
	else:
		_roll_angle = 0.0
		_roll_rate = 0.0
	var target := _target_pose(st, t, delta)
	var spin := _spin(st, t)
	var blend := 1.0 - exp(-pose_sharpness * delta)
	for key in _pose:
		_pose[key] = lerpf(_pose[key], target[key], blend)

	# Squash recovers toward 1 (landings set it lower in _on_enter).
	var squash_target := 0.85 if st in Player.CROUCH_STATES or st == S.ROLL else 1.0
	_squash = lerpf(_squash, squash_target, 1.0 - exp(-12.0 * delta))
	var squash := Vector3(1.0 / sqrt(_squash), _squash, 1.0 / sqrt(_squash))
	transform.basis = tilt * Basis(Vector3.UP, _yaw) * Basis.from_scale(squash)

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
	if st in Player.AIR_STATES:
		_air_steps(delta)
	elif st not in [S.WALK, S.SKID_END, S.LAND]:
		_stride_rate = 0.0   # stopped, crouching, sliding...: nothing to carry into a jump
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
			# One full cycle (TAU) is two steps, so a step every PI radians.
			var top_rate := run_bpm / 60.0 * steps_per_beat * PI
			var prev := _cycle
			var rate := lerpf(5.0, top_rate, minf(speed_ratio, 1.0))   # radians of stride per second
			_cycle += delta * rate
			# The drawn pose trails the target by the smoothing (pose_sharpness): fire the
			# step that much later in the stride, so it lands when you SEE the legs there.
			var step_at := step_phase * PI + atan(rate / maxf(pose_sharpness, 0.01))
			if floorf((_cycle - step_at) / PI) != floorf((prev - step_at) / PI) and speed_ratio > 0.05:
				footstep.emit(minf(speed_ratio, 1.0))
			_stride_rate = rate if speed_ratio > 0.05 else 0.0
			_stride_strength = minf(speed_ratio, 1.0)
			_cycle = fmod(_cycle, TAU)
			var swing := sin(_cycle) * lerpf(0.35, 1.0, minf(speed_ratio, 1.0)) * minf(speed_ratio * 3.0, 1.0)
			p.leg_l = swing
			p.leg_r = -swing
			p.arm_l = -swing * 0.9
			p.arm_r = swing * 0.9
			p.lean = -0.25 * minf(speed_ratio, 1.0)
			# Lowest on the step. The bob moves twice per stride, so its smoothing delay is
			# atan(2 * rate / sharpness) at twice the speed; aim the target that much early.
			var bob_lead := atan(2.0 * rate / maxf(pose_sharpness, 0.01)) * 0.5
			p.body_y = -absf(cos(_cycle - step_at + bob_lead)) * 0.06 * minf(speed_ratio, 1.0)
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
			# Low crawl: legs stretched out behind, hips high enough that hands and
			# feet stay on top of the floor through the whole stroke.
			p.body_y = -0.33
			p.lean = -1.15
			p.arm_l = 1.5 + c
			p.arm_r = 1.5 - c
			p.leg_l = -0.45 - c
			p.leg_r = -0.45 + c
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
			p.head = 0.55        # chin up, looking ahead (positive = head back)
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
			# Flat, Superman-style: body close to horizontal (never past it), head up
			# looking ahead, arms out in front, legs straight back. Dips only a little
			# as the fall speeds up. Held low so the drop into the belly slide is small.
			p.lean = lerpf(-1.4, -1.55, clampf(-player.vy / 40.0, 0.0, 1.0))
			p.body_y = -0.3
			p.arm_l = 3.0
			p.arm_r = 3.0
			p.arm_l_out = 0.25
			p.arm_r_out = 0.25
			p.leg_l = -0.1
			p.leg_r = 0.12
			p.head = 0.8
		S.BELLY_SLIDE:
			# Flat on the belly: chest on the floor (hip pivot at 0.29 m = torso
			# radius), head up and clear of the ground, arms ahead, legs behind.
			p.lean = -PI / 2.0
			p.body_y = -0.51
			p.arm_l = 3.0
			p.arm_r = 3.0
			p.arm_l_out = 0.3
			p.arm_r_out = 0.3
			p.leg_l = -0.05
			p.leg_r = 0.08
			p.head = 0.9
		S.BELLY_GETUP:
			# Pushing up into a crouch; hips high enough that the bent legs and feet
			# stay on top of the floor.
			p.body_y = -0.08
			p.lean = -0.45
			p.leg_l = 1.5
			p.leg_r = 1.1
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


## In the air: keep the stride clock running at the rate it had on the ground and
## emit air_step where the footsteps would fall, so step-driven music carries on.
func _air_steps(delta: float) -> void:
	if _stride_rate <= 0.0:
		return
	var prev := _cycle
	_cycle += delta * _stride_rate
	var step_at := step_phase * PI + atan(_stride_rate / maxf(pose_sharpness, 0.01))
	if floorf((_cycle - step_at) / PI) != floorf((prev - step_at) / PI):
		air_step.emit(_stride_strength)
	_cycle = fmod(_cycle, TAU)


func _roll_steps(delta: float, in_air: bool) -> void:
	if _roll_rate <= 0.0:
		return
	var prev := _roll_phase
	_roll_phase += delta * _roll_rate
	if floorf(_roll_phase) != floorf(prev):
		roll_step.emit(_roll_strength, in_air)
	_roll_phase = fmod(_roll_phase, 1.0)
