extends Node3D
## Player animation. Lives on Player/Visual and reads the player's state.
##
## Whole-body motion (facing, squash, lean, flips, spins) is done in code on
## Visual (pivot at the feet) and on the hip pivots (Body / ModelPivot).
##
## With use_model on, the Norah model plays her clips for each state:
## idle, walk/run blended by speed, crouch, and the jump clip matched to the
## jump arc. States without a clip of their own reuse the nearest clip plus the
## whole-body motion. Clips added later are picked up automatically by name
## (see CLIP_WISHES), e.g. "Fall", "LedgeHang", "Slide", "Skid", "Flip".
##
## With use_model off, the primitive body is posed part by part instead.

const S := Player.State

@export var pose_sharpness := 18.0

@export_group("Model")
@export var use_model := true
@export var crossfade := 0.15
@export var walk_ref_speed := 0.61     # m/s the Walk clip covers at normal speed (measured)
@export var run_ref_speed := 2.07      # m/s the Run clip covers at normal speed (measured)
@export var walk_run_switch := 3.0     # m/s
@export var max_clip_speed := 2.4      # cap so the run doesn't look frantic at top speed

## Preferred clip names per role, first match wins. Add clips with these names in
## Blender and they are used automatically; the last name is Norah's fallback.
const CLIP_WISHES := {
	"idle": ["Idle", "IdlePose_Norah"],
	"walk": ["Walk", "Walk_Norah"],
	"run": ["Run", "Run_Norah"],
	"skid": ["Skid", "Run_Norah"],
	"crouch": ["Crouch", "CrouchCoverIdle_Norah"],
	"crawl": ["Crawl", "CrouchCoverIdle_Norah"],
	"slide": ["Slide", "CrouchCover_Norah"],
	"jump": ["Jump", "JumpAcross_Norah"],
	"double_jump": ["DoubleJump", "Jump", "JumpAcross_Norah"],
	"flip": ["Flip", "Jump", "JumpAcross_Norah"],
	"fall": ["Fall", "Jump", "JumpAcross_Norah"],
	"dive": ["Dive", "Jump", "JumpAcross_Norah"],
	"ledge_hang": ["LedgeHang", "Jump", "JumpAcross_Norah"],
	"ledge_climb": ["LedgeClimb", "Crouch", "CrouchCoverIdle_Norah"],
	"ground_pound": ["GroundPound", "Jump", "JumpAcross_Norah"],
}
const LOOPING := ["idle", "walk", "run", "crouch", "crawl", "fall", "ledge_hang", "skid"]

@onready var player: Player = get_parent()
@onready var body: Node3D = $Body
@onready var head: Node3D = $Body/HeadPivot
@onready var arm_l: Node3D = $Body/ArmL
@onready var arm_r: Node3D = $Body/ArmR
@onready var leg_l: Node3D = $Body/LegL
@onready var leg_r: Node3D = $Body/LegR
@onready var model_pivot: Node3D = get_node_or_null("ModelPivot")

var _ap: AnimationPlayer
var _clips := {}          # role -> clip name that exists
var _current_clip := ""

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
	if model_pivot:
		_ap = model_pivot.find_child("AnimationPlayer", true, false)
	var model_ok := use_model and _ap != null
	body.visible = not model_ok
	if model_pivot:
		model_pivot.visible = model_ok
	if not model_ok:
		return
	for role in CLIP_WISHES:
		for name in CLIP_WISHES[role]:
			if _ap.has_animation(name):
				_clips[role] = name
				# Only loop dedicated clips, or Norah's own looping ones (idle/walk/run/crouch).
				if role in LOOPING and (name == CLIP_WISHES[role][0] or role in ["idle", "walk", "run", "crouch", "crawl"]):
					_ap.get_animation(name).loop_mode = Animation.LOOP_LINEAR
				break
	_xray_materials(model_pivot)


## Give the model the same see-through-walls silhouette as the primitive body.
func _xray_materials(node: Node) -> void:
	for child in node.get_children():
		var mi := child as MeshInstance3D
		if mi and mi.mesh:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i) as BaseMaterial3D
				if mat:
					var copy := mat.duplicate() as BaseMaterial3D
					copy.stencil_mode = BaseMaterial3D.STENCIL_MODE_XRAY
					copy.stencil_color = Color(0.35, 0.75, 1.0, 0.75)
					mi.set_surface_override_material(i, copy)
		_xray_materials(child)


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
	if model_pivot and model_pivot.visible:
		# The model's own clips already crouch and lean, so only add whole-body motion
		# the clips don't have.
		var lean: float = _pose.lean
		var body_y: float = _pose.body_y
		if st in [S.CROUCH, S.CRAWL, S.CROUCH_SLIDE, S.BELLY_GETUP, S.POUND_LAND, S.LEDGE_CLIMB]:
			lean *= 0.3
			body_y = 0.0
		model_pivot.position.y = 0.8 + body_y
		model_pivot.rotation = Vector3(lean + spin.x, 0.0, _pose.roll + spin.z)
		_update_clip(st)
		return
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


# ------------------------------------------------------------------ model clips
func _update_clip(st: int) -> void:
	var v := player.forward_speed * Player.U   # m/s
	match st:
		S.IDLE:
			_loop("idle", 1.0)
		S.WALK, S.LAND, S.SKID_END:
			if v < 0.3:
				_loop("idle", 1.0)
			elif v < walk_run_switch:
				_loop("walk", clampf(v / walk_ref_speed, 0.6, 2.0))
			else:
				_loop("run", clampf(v / run_ref_speed, 1.0, max_clip_speed))
		S.BRAKE, S.SKID:
			_hold("skid", 0.25)
		S.CROUCH, S.BELLY_GETUP, S.POUND_LAND, S.ROLL:
			_loop("crouch", 1.0)
		S.CRAWL:
			_loop("crawl", 1.5)
		S.CROUCH_SLIDE:
			_hold("slide", -1.0)
		S.DIVE, S.BELLY_SLIDE:
			_hold("dive", 0.35)
		S.LEDGE_HANG:
			_hold("ledge_hang", 0.25)
		S.LEDGE_CLIMB:
			_loop("ledge_climb", 1.0)
		S.FALL:
			if _clips.get("fall", "") != _clips.get("jump", ""):
				_loop("fall", 1.0)
			else:
				_air("jump")
		S.DOUBLE_JUMP:
			_air("double_jump")
		S.TRIPLE_JUMP, S.BACKFLIP, S.SIDE_FLIP, S.ROLLOUT:
			_air("flip")
		S.GROUND_POUND:
			_hold("ground_pound", 0.3)
		_:
			_air("jump")


func _play(role: String) -> String:
	var clip: String = _clips.get(role, "")
	if clip == "":
		return ""
	if clip != _current_clip:
		_ap.play(clip, crossfade)
		_current_clip = clip
	return clip


func _loop(role: String, speed: float) -> void:
	if _play(role) != "":
		_ap.speed_scale = speed


## True when the role has its own clip (first wish), not a stand-in from another role.
func _dedicated(role: String, clip: String) -> bool:
	return clip == CLIP_WISHES[role][0]


## Hold one frame of a stand-in clip (time < 0 = its last frame). A dedicated clip
## for the role plays normally instead.
func _hold(role: String, time: float) -> void:
	var clip := _play(role)
	if clip == "":
		return
	if _dedicated(role, clip):
		_ap.speed_scale = 1.0
		return
	var length := _ap.get_animation(clip).length
	# Keep the player running (speed 1) so the crossfade from the previous clip
	# finishes; pausing it froze the blend halfway. Pin the playhead each frame.
	_ap.speed_scale = 1.0
	# Stay a little short of the end so the clip never "finishes" and stops.
	_ap.seek(clampf(length - 0.05 if time < 0.0 else time, 0.0, length - 0.05), true)


## Match the stand-in jump clip to the jump arc: rising early in the clip, the top
## in the middle, falling later. A dedicated clip (Jump, DoubleJump, Flip) plays
## through normally instead.
func _air(role: String) -> void:
	var clip := _play(role)
	if clip == "":
		return
	if _dedicated(role, clip):
		_ap.speed_scale = 1.0
		return
	var length := _ap.get_animation(clip).length
	var f := clampf(remap(player.vy, 40.0, -40.0, 0.15, 0.85), 0.15, 0.85)
	_ap.speed_scale = 1.0   # see _hold: keeps crossfades running
	_ap.seek(length * f, true)
