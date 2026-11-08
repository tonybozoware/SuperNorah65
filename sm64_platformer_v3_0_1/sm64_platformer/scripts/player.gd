class_name Player
extends CharacterBody3D
## SM64-style player controller (original implementation).
##
## Movement follows SM64's rules and numbers, plus a set of modern options
## (forgiveness windows, ledge grab, roll, feel tuning) that can each be tuned
## or switched off in the Inspector. Speeds are stored in SM64 units per frame
## (u/f) and the logic is written for 30 ticks per second (Project Settings >
## Physics > Common > Physics Ticks per Second = 30, physics interpolation on).
## 1 u/f = 0.3 m/s. Animation: player_animator.gd. Shadow/dust/rumble: player_fx.gd.

signal landed(impact: float)    # impact = downward speed in u/f
signal pounded
signal wall_kicked
signal ledge_grabbed

enum State {
	IDLE, WALK, BRAKE, SKID, SKID_END, CROUCH, CRAWL, CROUCH_SLIDE, LAND,
	JUMP, DOUBLE_JUMP, TRIPLE_JUMP, LONG_JUMP, BACKFLIP, SIDE_FLIP, WALL_KICK,
	FALL, WALL_BONK, GROUND_POUND, POUND_LAND, DIVE, BELLY_SLIDE, BELLY_GETUP, ROLLOUT,
	ROLL, LEDGE_HANG, LEDGE_CLIMB,
}

const U := 0.3  # m/s per SM64 unit-per-frame
const AIR_STATES := [State.JUMP, State.DOUBLE_JUMP, State.TRIPLE_JUMP, State.LONG_JUMP,
		State.BACKFLIP, State.SIDE_FLIP, State.WALL_KICK, State.FALL, State.WALL_BONK,
		State.GROUND_POUND, State.DIVE, State.ROLLOUT]
const GROUND_STATES := [State.IDLE, State.WALK, State.BRAKE, State.SKID, State.SKID_END,
		State.CROUCH, State.CRAWL, State.CROUCH_SLIDE, State.LAND, State.POUND_LAND,
		State.BELLY_SLIDE, State.BELLY_GETUP, State.ROLL]
const LEDGE_STATES := [State.LEDGE_HANG, State.LEDGE_CLIMB]
const CROUCH_STATES := [State.CROUCH, State.CRAWL, State.CROUCH_SLIDE]
const LOW_SHAPE_STATES := [State.CROUCH, State.CRAWL, State.CROUCH_SLIDE, State.BELLY_SLIDE,
		State.BELLY_GETUP, State.ROLL]
const DIVE_FROM_STATES := [State.JUMP, State.DOUBLE_JUMP, State.TRIPLE_JUMP, State.SIDE_FLIP,
		State.FALL, State.WALL_KICK]
const JUMP_CUT_STATES := [State.JUMP, State.DOUBLE_JUMP]
const APEX_STATES := [State.JUMP, State.DOUBLE_JUMP, State.TRIPLE_JUMP, State.SIDE_FLIP,
		State.BACKFLIP, State.WALL_KICK, State.ROLLOUT]
const LEDGE_GRAB_FROM := [State.JUMP, State.DOUBLE_JUMP, State.FALL, State.WALL_KICK]
const WORLD_MASK := 1 | 8   # world + props

@export_group("Ground (units/frame)")
@export var max_walk_speed := 40.0      # 12 m/s (SM64: 32)
@export var accel_base := 1.55          # SM64: 1.1
@export var accel_falloff := 38.0       # accel = base - speed / falloff (SM64: 43)
@export var over_speed_decel := 1.0
@export var stop_decel := 1.0           # no stick, slow
@export var brake_decel := 4.0          # no stick at speed, and skids
@export var brake_min_speed := 16.0
@export var turn_rate_deg := 11.25      # per frame
@export var skid_min_speed := 16.0
@export var skid_angle_deg := 100.0
@export var skid_exit_speed := 8.0
@export var crawl_mult := 0.08          # crawl ~1 m/s (SM64: 0.1 of a 32 top speed)
@export var slide_friction := 0.92      # crouch-slide speed kept per frame
@export var long_jump_min_speed := 10.0
@export var long_jump_window := 30.0    # frames after starting a crouch slide

@export_group("Air (units/frame)")
@export var gravity := 4.0
@export var long_jump_gravity := 2.0
@export var max_fall_speed := 75.0
@export var air_drag := 0.35
@export var air_accel := 1.5
@export var air_strafe := 10.0
@export var air_speed_cap := 40.0       # matches max_walk_speed (SM64: 32)
@export var long_jump_speed_cap := 48.0
@export var jump_cut_threshold := 20.0  # releasing jump above this speed cuts the rise

@export_group("Jumps (units/frame)")
@export var jump_up := 42.0
@export var double_jump_up := 52.0
@export var triple_jump_up := 69.0
@export var jump_speed_bonus := 0.25
@export var jump_keep_speed := 0.8
@export var triple_min_speed := 20.0
@export var backflip_up := 62.0
@export var backflip_back := -16.0
@export var side_flip_up := 62.0
@export var side_flip_forward := 8.0
@export var long_jump_up := 30.0
@export var long_jump_mult := 1.5
@export var long_jump_max := 48.0
@export var wall_kick_up := 62.0
@export var wall_kick_forward := 24.0
@export var wall_bonk_min_speed := 16.0
@export var wall_kick_window := 5.0     # frames
@export var pound_hang := 10.0          # frames
@export var pound_speed := 50.0
@export var pound_land_frames := 12.0
@export var landing_frames := 4.0
@export var long_jump_landing_frames := 6.0
@export var double_jump_window := 5.0   # frames after a landing ends

@export_group("Dive (units/frame)")
@export var dive_boost := 15.0
@export var dive_max := 48.0
@export var ground_dive_min_speed := 36.0   # about 90% of top speed
@export var ground_dive_min_stick := 0.75
@export var ground_dive_up := 20.0
@export var dive_knockback := -16.0
@export var rollout_up := 30.0
@export var belly_turn_deg := 2.8       # per frame at full stick
@export var belly_getup_frames := 8.0

@export_group("Roll (units/frame)")
@export var roll_start_speed := 34.0    # ~10 m/s
@export var roll_boost := 6.0           # per attack press during a roll
@export var roll_max := 56.0            # ~17 m/s
@export var roll_friction := 0.985      # speed kept per frame on flat ground
@export var roll_min_speed := 8.0       # below this the roll ends in a crouch
@export var roll_turn_deg := 4.0        # per frame at full stick
@export var roll_slope_mult := 1.5

@export_group("Forgiveness")
@export var coyote_frames := 3.6        # 0.12 s
@export var jump_buffer_frames := 4.0   # 0.13 s
@export var crouch_buffer_frames := 3.0 # 0.1 s
@export var dive_buffer_frames := 3.0   # 0.1 s
@export var corner_correction := 0.25   # m
@export var step_height := 0.3          # m, step-up and ledge assist

@export_group("Ledge grab")
@export var ledge_grab_enabled := true
@export var ledge_reach_min := 1.0      # m, ledge top above the feet
@export var ledge_reach_max := 1.95
@export var ledge_hang_drop := 1.55     # m, feet below the ledge top while hanging
@export var ledge_climb_frames := 12.0
@export var ledge_hold_to_climb := 6.0  # frames of holding forward before climbing
@export var ledge_regrab_frames := 10.0

@export_group("Feel tuning")
@export var apex_hang_enabled := true
@export var apex_hang_mult := 0.6       # gravity near the top while holding jump
@export var apex_hang_band := 10.0      # u/f either side of the apex
@export var fast_fall_enabled := true
@export var fast_fall_mult := 1.25      # gravity on the way down
@export var quick_turn_enabled := true
@export var quick_turn_deg := 30.0      # per frame when nearly stopped
@export var slope_momentum_enabled := true
@export var slope_accel := 1.0          # u/f per frame on a 90° slope

@export_group("Controls")
@export var input_follow_rate := 1.0    # rad/s the held stick reference follows the camera

@export_group("Body")
@export var radius := 0.35
@export var stand_height := 1.6
@export var crouch_height := 1.0

@onready var collision: CollisionShape3D = $CollisionShape3D

var state := State.IDLE
var state_frames := 0.0
var facing := 0.0                # yaw in radians, 0 = facing -Z
var forward_speed := 0.0         # u/f along facing
var side_speed := 0.0            # u/f, air strafe only
var vy := 0.0                    # u/f vertical
var stick := 0.0                 # 0..1
var intended_mag := 0.0          # 0..32, SM64 squares the stick
var intended_yaw := 0.0
var jump_pressed := false        # this tick only (raw)
var crouch_pressed := false
var attack_pressed := false
var jump_buffer := 0.0           # frames left on a buffered press
var crouch_buffer := 0.0
var dive_buffer := 0.0
var coyote_timer := 0.0
var landing_from := State.JUMP
var landing_length := 4.0
var double_jump_timer := 0.0
var wall_timer := 0.0
var kick_facing := 0.0
var last_land_speed := 0.0       # u/f downward at the last landing, for the animator
var platform_carry := Vector3.ZERO
var crouched_shape := false
var ledge_top := Vector3.ZERO    # where the player stands after climbing
var ledge_hang_pos := Vector3.ZERO
var ledge_regrab_timer := 0.0

var camera_turned_by_hand := false  # set by the camera rig each frame
var _ref_yaw := 0.0
var _last_stick_angle := 0.0

var _stand_shape := CapsuleShape3D.new()
var _crouch_shape := CapsuleShape3D.new()


func _ready() -> void:
	_stand_shape.radius = radius
	_stand_shape.height = stand_height
	_crouch_shape.radius = radius
	_crouch_shape.height = crouch_height
	_apply_shape(false)


func _physics_process(delta: float) -> void:
	var k := delta * 30.0   # SM64 frames this tick (1.0 at 30 Hz)
	_read_input(k)
	state_frames += k
	wall_timer -= k
	coyote_timer -= k
	ledge_regrab_timer -= k
	if state != State.LAND and double_jump_timer > 0.0:
		double_jump_timer -= k

	match state:
		State.IDLE: _st_idle()
		State.WALK: _st_walk(k)
		State.BRAKE: _st_brake(k)
		State.SKID: _st_skid(k)
		State.SKID_END: _st_skid_end(k)
		State.CROUCH: _st_crouch()
		State.CRAWL: _st_crawl(k)
		State.CROUCH_SLIDE: _st_crouch_slide(k)
		State.LAND: _st_land(k)
		State.POUND_LAND: _st_pound_land()
		State.GROUND_POUND: _st_ground_pound()
		State.WALL_BONK: _st_wall_bonk()
		State.BELLY_SLIDE: _st_belly_slide(k)
		State.BELLY_GETUP: _st_belly_getup()
		State.ROLL: _st_roll(k)
		State.LEDGE_HANG: _st_ledge_hang()
		State.LEDGE_CLIMB: _st_ledge_climb()
		_: _st_air(k)

	if state in LEDGE_STATES:
		_update_shape()
		return   # ledge states place the body directly

	if state in AIR_STATES and state != State.GROUND_POUND:
		_apply_gravity(k)

	if is_on_floor():
		platform_carry = get_platform_velocity()
		platform_carry.y = 0.0
	var h := _dir_of(facing) * forward_speed * U
	if state in AIR_STATES:
		h += _dir_of(facing + PI / 2.0) * side_speed * U
		h += platform_carry
	velocity = Vector3(h.x, vy * U if state in AIR_STATES else 0.0, h.z)
	var was_ground := state in GROUND_STATES
	var before := global_position
	move_and_slide()
	if was_ground and is_on_floor() and is_on_ceiling():
		# Squeezed between floor and a sloped ceiling (e.g. sliding under a ramp):
		# treat the ceiling as a wall instead of being wedged into the ground.
		global_position = Vector3(before.x, maxf(global_position.y, before.y), before.z)
		forward_speed = 0.0
	elif was_ground and is_on_wall() and is_on_floor():
		_try_step_up(Vector3(h.x, 0.0, h.z) * delta)
	_after_move(Vector3(h.x, 0.0, h.z) * delta)
	_update_shape()


# ------------------------------------------------------------------ input
func _read_input(k: float) -> void:
	var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	stick = minf(raw.length(), 1.0)
	intended_mag = 32.0 * stick * stick
	jump_pressed = Input.is_action_just_pressed("jump")
	crouch_pressed = Input.is_action_just_pressed("crouch")
	attack_pressed = Input.is_action_just_pressed("attack")
	jump_buffer = jump_buffer_frames if jump_pressed else jump_buffer - k
	crouch_buffer = crouch_buffer_frames if crouch_pressed else crouch_buffer - k
	dive_buffer = dive_buffer_frames if attack_pressed else dive_buffer - k
	var cam := get_viewport().get_camera_3d()
	var cam_yaw := _ref_yaw
	if cam:
		var cf := -cam.global_basis.z
		cam_yaw = atan2(-cf.x, -cf.z)
	# Hold the camera reference while the stick stays pointed the same way, so the
	# camera adjusting itself (walls, tether drift) doesn't steer the player.
	# It updates when the stick is released, turned noticeably, or the camera is
	# turned by hand, and otherwise follows slowly.
	var stick_angle := atan2(raw.x, -raw.y)
	if stick < 0.2 or absf(angle_difference(stick_angle, _last_stick_angle)) > deg_to_rad(30.0) \
			or camera_turned_by_hand:
		_ref_yaw = cam_yaw
	else:
		_ref_yaw = rotate_toward(_ref_yaw, cam_yaw, input_follow_rate * k / 30.0)
	_last_stick_angle = stick_angle
	if stick < 0.01:
		intended_yaw = facing
		return
	intended_yaw = wrapf(_ref_yaw - stick_angle, -PI, PI)


## Buffered presses: true for a few frames after the press, until used.
func _want_jump() -> bool:
	return jump_buffer > 0.0


func _want_dive() -> bool:
	return dive_buffer > 0.0


func _crouch_held() -> bool:
	return crouch_buffer > 0.0 or Input.is_action_pressed("crouch")


func _held_back() -> bool:
	return stick > 0.01 and absf(angle_difference(facing, intended_yaw)) > deg_to_rad(skid_angle_deg)


# ------------------------------------------------------------------ ground states
func _left_floor() -> bool:
	if not is_on_floor():
		vy = 0.0
		coyote_timer = coyote_frames   # a jump is still allowed for a moment
		_set_state(State.FALL)
		return true
	return false


func _st_idle() -> void:
	forward_speed = 0.0
	if _left_floor():
		return
	if _want_jump():
		_jump_from_ground()
	elif _crouch_held():
		_set_state(State.CROUCH)
	elif stick > 0.01:
		facing = intended_yaw   # starting from rest faces the stick at once
		_set_state(State.WALK)


func _st_walk(k: float) -> void:
	if _left_floor():
		return
	if _want_jump():
		_jump_from_ground()
		return
	if _want_dive() and forward_speed >= ground_dive_min_speed and stick >= ground_dive_min_stick:
		vy = ground_dive_up
		_start_dive()
		return
	if _held_back() and forward_speed >= skid_min_speed:
		_set_state(State.SKID)
		return
	if _crouch_held():
		_set_state(State.CROUCH_SLIDE)
		return
	forward_speed += _slope_accel(1.0) * k
	if stick < 0.01:
		if forward_speed >= brake_min_speed:
			_set_state(State.BRAKE)
			return
		forward_speed = move_toward(forward_speed, 0.0, stop_decel * k)
		if forward_speed <= 0.0:
			_set_state(State.IDLE)
		return
	_update_walk_speed(intended_mag, k)


func _update_walk_speed(target_mag: float, k: float) -> void:
	# target_mag is on SM64's 0..32 stick scale; scale it to this game's top speed.
	var target := minf(target_mag / 32.0 * max_walk_speed, max_walk_speed)
	if forward_speed <= 0.0:
		forward_speed += accel_base * k
	elif forward_speed <= target:
		forward_speed += (accel_base - forward_speed / accel_falloff) * k
	elif not is_on_floor() or get_floor_normal().y >= 0.95 or not slope_momentum_enabled:
		forward_speed -= over_speed_decel * k   # SM64 only bleeds extra speed on flat ground
	forward_speed = minf(forward_speed, 48.0)
	var rate := turn_rate_deg
	if quick_turn_enabled:
		rate = lerpf(quick_turn_deg, turn_rate_deg, clampf(forward_speed / (max_walk_speed * 0.5), 0.0, 1.0))
	facing = rotate_toward(facing, intended_yaw, deg_to_rad(rate) * k)


## Speed gained per frame from the floor's slope (negative uphill).
func _slope_accel(mult: float) -> float:
	if not slope_momentum_enabled or not is_on_floor():
		return 0.0
	var n := get_floor_normal()
	var steep := Vector2(n.x, n.z).length()
	if steep < 0.08:
		return 0.0
	var downhill := Vector3(n.x, 0.0, n.z).normalized()
	return slope_accel * mult * steep * _dir_of(facing).dot(downhill)


func _st_brake(k: float) -> void:
	if _left_floor():
		return
	if _want_jump():
		_jump_from_ground()
		return
	if _crouch_held():
		_set_state(State.CROUCH_SLIDE)
		return
	if stick > 0.01:
		_set_state(State.WALK)
		return
	forward_speed = move_toward(forward_speed, 0.0, brake_decel * k)
	if forward_speed <= 0.0:
		_set_state(State.IDLE)


func _st_skid(k: float) -> void:
	if _left_floor():
		return
	if _want_jump():
		_side_flip()
		return
	if not _held_back():
		_set_state(State.WALK)
		return
	forward_speed = move_toward(forward_speed, 0.0, brake_decel * k)
	if forward_speed <= 0.0:
		facing = wrapf(facing + PI, -PI, PI)
		forward_speed = skid_exit_speed
		_set_state(State.SKID_END)


func _st_skid_end(k: float) -> void:
	if _left_floor():
		return
	if _want_jump():
		_side_flip()
		return
	_update_walk_speed(intended_mag, k)
	if state_frames >= 6.0:
		_set_state(State.WALK)


func _st_crouch() -> void:
	forward_speed = 0.0
	if _left_floor():
		return
	if _want_dive():
		_start_roll()
	elif _want_jump() and _can_stand():
		forward_speed = backflip_back
		_launch(State.BACKFLIP, backflip_up)
	elif not _crouch_held() and _can_stand():
		_set_state(State.IDLE)
	elif stick > 0.01:
		_set_state(State.CRAWL)   # also when there's no room to stand up


func _st_crawl(k: float) -> void:
	if _left_floor():
		return
	if _want_dive():
		_start_roll()
		return
	if _want_jump() and _can_stand():
		_single_jump()
		return
	if not _crouch_held() and _can_stand():
		_set_state(State.WALK)
		return
	if stick < 0.01:
		forward_speed = 0.0
		_set_state(State.CROUCH)
		return
	_update_walk_speed(intended_mag * crawl_mult, k)


func _st_crouch_slide(k: float) -> void:
	if _left_floor():
		return
	if _want_dive():
		_start_roll()
		return
	if _want_jump() and _can_stand():
		if state_frames < long_jump_window and forward_speed > long_jump_min_speed:
			forward_speed = minf(forward_speed * long_jump_mult, long_jump_max)
			_launch(State.LONG_JUMP, long_jump_up)
		else:
			_single_jump()
		return
	if not _crouch_held() and _can_stand():
		# Releasing crouch ends the slide at once and keeps the speed (SM64 keeps sliding).
		_set_state(State.WALK)
		return
	var push := intended_mag / 32.0 * cos(angle_difference(facing, intended_yaw))
	forward_speed *= pow(slide_friction + 0.02 * push, k)
	forward_speed += _slope_accel(1.0) * k
	if forward_speed < 1.0:
		forward_speed = 0.0
		_set_state(State.CROUCH)


func _st_land(k: float) -> void:
	if _left_floor():
		return
	double_jump_timer = double_jump_window if landing_from != State.TRIPLE_JUMP else 0.0
	if _want_jump():
		_jump_from_ground()
		return
	if _want_dive() and forward_speed >= ground_dive_min_speed and stick >= ground_dive_min_stick:
		vy = ground_dive_up
		_start_dive()
		return
	if _crouch_held():
		_set_state(State.CROUCH_SLIDE if forward_speed > 0.0 else State.CROUCH)
		return
	if stick > 0.01:
		forward_speed *= pow(0.98, k)
		facing = rotate_toward(facing, intended_yaw, deg_to_rad(turn_rate_deg) * k)
	elif forward_speed >= brake_min_speed:
		forward_speed = move_toward(forward_speed, 0.0, brake_decel * k)
	if state_frames >= landing_length:
		_set_state(State.WALK if forward_speed > 0.0 or stick > 0.01 else State.IDLE)


func _st_pound_land() -> void:
	forward_speed = 0.0
	if _left_floor():
		return
	if state_frames >= pound_land_frames:
		_set_state(State.CROUCH if _crouch_held() else State.IDLE)


# ------------------------------------------------------------------ roll
func _start_roll() -> void:
	dive_buffer = 0.0
	if stick > 0.01:
		facing = intended_yaw
	forward_speed = maxf(forward_speed, roll_start_speed)
	_set_state(State.ROLL)


func _st_roll(k: float) -> void:
	if _left_floor():
		return
	if _want_jump() and _can_stand():
		_launch(State.JUMP, jump_up + jump_speed_bonus * forward_speed)   # keeps the roll speed
		return
	if _want_dive():
		dive_buffer = 0.0
		forward_speed = minf(forward_speed + roll_boost, roll_max)
	if not _crouch_held() and _can_stand():
		_set_state(State.WALK)
		return
	if stick > 0.01:
		var turn := deg_to_rad(roll_turn_deg) * (intended_mag / 32.0) * k
		facing = rotate_toward(facing, intended_yaw, turn)
	forward_speed *= pow(roll_friction, k)
	forward_speed = minf(forward_speed + _slope_accel(roll_slope_mult) * k, roll_max)
	if forward_speed < roll_min_speed:
		_set_state(State.CROUCH)


# ------------------------------------------------------------------ jumps
func _jump_from_ground() -> void:
	jump_buffer = 0.0
	if double_jump_timer > 0.0:
		match landing_from:
			State.JUMP, State.FALL, State.SIDE_FLIP:
				_double_jump()
				return
			State.DOUBLE_JUMP:
				if forward_speed > triple_min_speed:
					forward_speed *= jump_keep_speed
					_launch(State.TRIPLE_JUMP, triple_jump_up)
					return
	_single_jump()


func _single_jump() -> void:
	var up := jump_up + jump_speed_bonus * forward_speed
	forward_speed *= jump_keep_speed
	_launch(State.JUMP, up)


func _double_jump() -> void:
	var up := double_jump_up + jump_speed_bonus * forward_speed
	forward_speed *= jump_keep_speed
	_launch(State.DOUBLE_JUMP, up)


func _side_flip() -> void:
	if stick > 0.01:
		facing = intended_yaw
	else:
		facing = wrapf(facing + PI, -PI, PI)
	forward_speed = side_flip_forward
	_launch(State.SIDE_FLIP, side_flip_up)


func _launch(new_state: State, up: float) -> void:
	vy = up
	jump_buffer = 0.0
	coyote_timer = 0.0
	double_jump_timer = 0.0
	_set_state(new_state)


# ------------------------------------------------------------------ air states
func _st_air(k: float) -> void:
	if state == State.FALL and coyote_timer > 0.0 and _want_jump():
		_single_jump()   # coyote time: just ran off a ledge
		return
	if _want_dive() and state in DIVE_FROM_STATES:
		_start_dive()
		return
	if crouch_pressed and state not in [State.LONG_JUMP, State.DIVE, State.ROLLOUT]:
		crouch_buffer = 0.0
		forward_speed = 0.0
		side_speed = 0.0
		vy = 0.0
		platform_carry = Vector3.ZERO
		_set_state(State.GROUND_POUND)
		return
	forward_speed = move_toward(forward_speed, 0.0, air_drag * k)
	side_speed = 0.0
	if stick > 0.01:
		var mag := intended_mag / 32.0
		var d := angle_difference(facing, intended_yaw)
		forward_speed += air_accel * cos(d) * mag * k
		side_speed = air_strafe * sin(d) * mag
	var cap := long_jump_speed_cap if state in [State.LONG_JUMP, State.DIVE] else air_speed_cap
	if forward_speed > cap:
		forward_speed -= 1.0 * k
	if forward_speed < -16.0:
		forward_speed += 2.0 * k


func _apply_gravity(k: float) -> void:
	if state == State.LONG_JUMP:
		vy -= long_jump_gravity * k
	elif state in JUMP_CUT_STATES and vy > jump_cut_threshold and not Input.is_action_pressed("jump"):
		vy /= pow(4.0, k)
	else:
		var g := gravity
		if apex_hang_enabled and state in APEX_STATES and absf(vy) < apex_hang_band \
				and Input.is_action_pressed("jump"):
			g *= apex_hang_mult
		elif fast_fall_enabled and vy < 0.0 and state != State.DIVE:
			g *= fast_fall_mult
		vy -= g * k
	vy = maxf(vy, -max_fall_speed)


func _st_wall_bonk() -> void:
	side_speed = 0.0
	if _want_jump() and wall_timer > 0.0:
		facing = kick_facing
		forward_speed = wall_kick_forward
		_launch(State.WALL_KICK, wall_kick_up)
		wall_kicked.emit()
		return
	if wall_timer <= 0.0:
		forward_speed = -8.0   # soft knock back away from the wall
		_set_state(State.FALL)


func _st_ground_pound() -> void:
	forward_speed = 0.0
	side_speed = 0.0
	vy = 0.0 if state_frames < pound_hang else -pound_speed


# ------------------------------------------------------------------ dive
func _start_dive() -> void:
	dive_buffer = 0.0
	forward_speed = minf(forward_speed + dive_boost, dive_max)
	double_jump_timer = 0.0
	_set_state(State.DIVE)


func _st_belly_slide(k: float) -> void:
	if _left_floor():
		return
	if (_want_jump() or _want_dive()) and _can_stand():
		dive_buffer = 0.0
		forward_speed = maxf(forward_speed, 0.0)
		_launch(State.ROLLOUT, rollout_up)
		return
	if stick > 0.01:
		var turn := deg_to_rad(belly_turn_deg) * (intended_mag / 32.0) * k
		facing = rotate_toward(facing, intended_yaw, turn)
	var push := intended_mag / 32.0 * cos(angle_difference(facing, intended_yaw))
	forward_speed *= pow(slide_friction + 0.02 * push, k)
	forward_speed += _slope_accel(1.0) * k
	if is_on_wall():
		forward_speed = 0.0
	if forward_speed < 1.0:
		forward_speed = 0.0
		_set_state(State.BELLY_GETUP)


func _st_belly_getup() -> void:
	forward_speed = 0.0
	if _left_floor():
		return
	if state_frames >= belly_getup_frames:
		# No room to stand (under a low ledge): stay crouched so the player can crawl out.
		_set_state(State.IDLE if _can_stand() else State.CROUCH)


# ------------------------------------------------------------------ ledge grab
func _st_ledge_hang() -> void:
	forward_speed = 0.0
	side_speed = 0.0
	vy = 0.0
	velocity = Vector3.ZERO
	global_position = ledge_hang_pos
	if not _ledge_still_there():
		_set_state(State.FALL)
		return
	var along := 0.0
	if stick > 0.01:
		along = cos(angle_difference(facing, intended_yaw)) * stick
	if state_frames < 2.0:
		return
	if jump_pressed or (along > 0.5 and state_frames >= ledge_hold_to_climb):
		jump_buffer = 0.0
		_set_state(State.LEDGE_CLIMB)
	elif along < -0.5 or crouch_pressed:
		crouch_buffer = 0.0
		global_position -= _dir_of(facing) * 0.15
		ledge_regrab_timer = ledge_regrab_frames
		_set_state(State.FALL)


func _st_ledge_climb() -> void:
	velocity = Vector3.ZERO
	var t := clampf(state_frames / ledge_climb_frames, 0.0, 1.0)
	var top_above := Vector3(ledge_hang_pos.x, ledge_top.y + 0.02, ledge_hang_pos.z)
	if t < 0.55:
		global_position = ledge_hang_pos.lerp(top_above, t / 0.55)
	else:
		global_position = top_above.lerp(ledge_top, (t - 0.55) / 0.45)
	if t >= 1.0:
		_set_state(State.IDLE)
		velocity = Vector3.DOWN
		move_and_slide()   # register the floor straight away


## Look for a grabbable ledge in front of the player while falling at a wall.
func _try_ledge_grab() -> bool:
	if not ledge_grab_enabled or ledge_regrab_timer > 0.0:
		return false
	if state not in LEDGE_GRAB_FROM or vy > 4.0:
		return false
	var space := get_world_3d().direct_space_state
	var fwd := _dir_of(facing)
	var chest := global_position + Vector3.UP * 1.1
	var q := PhysicsRayQueryParameters3D.create(chest, chest + fwd * (radius + 0.4), WORLD_MASK, [get_rid()])
	var wall := space.intersect_ray(q)
	if wall.is_empty() or absf(wall.normal.y) > 0.3:
		return false
	var n: Vector3 = Vector3(wall.normal.x, 0.0, wall.normal.z).normalized()
	var probe: Vector3 = wall.position - n * 0.2
	var top_q := PhysicsRayQueryParameters3D.create(
			Vector3(probe.x, global_position.y + ledge_reach_max + 0.3, probe.z),
			Vector3(probe.x, global_position.y + ledge_reach_min - 0.1, probe.z), WORLD_MASK, [get_rid()])
	var top := space.intersect_ray(top_q)
	if top.is_empty() or top.normal.y < 0.8:
		return false
	var reach: float = top.position.y - global_position.y
	if reach < ledge_reach_min or reach > ledge_reach_max:
		return false
	var stand_at: Vector3 = Vector3(wall.position.x, top.position.y, wall.position.z) - n * (radius + 0.15)
	# Room to stand on top?
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = _stand_shape
	sq.transform = Transform3D(Basis(), stand_at + Vector3.UP * (stand_height / 2.0 + 0.05))
	sq.collision_mask = WORLD_MASK
	sq.exclude = [get_rid()]
	if not space.intersect_shape(sq, 1).is_empty():
		return false
	# Don't hang with the feet almost on the floor (e.g. beside a low block): just
	# land instead. The ray starts above the hang spot, since a ray starting inside
	# the floor wouldn't see it.
	var hang_at := Vector3(wall.position.x, top.position.y - ledge_hang_drop, wall.position.z) + n * (radius + 0.03)
	var floor_q := PhysicsRayQueryParameters3D.create(hang_at + Vector3.UP * 1.0, hang_at + Vector3.DOWN * 0.5, WORLD_MASK, [get_rid()])
	if not space.intersect_ray(floor_q).is_empty():
		return false
	facing = _yaw_of(-n)
	ledge_top = stand_at
	ledge_hang_pos = Vector3(wall.position.x, top.position.y - ledge_hang_drop, wall.position.z) + n * (radius + 0.03)
	global_position = ledge_hang_pos
	forward_speed = 0.0
	side_speed = 0.0
	vy = 0.0
	platform_carry = Vector3.ZERO
	_set_state(State.LEDGE_HANG)
	ledge_grabbed.emit()
	return true


func _ledge_still_there() -> bool:
	var space := get_world_3d().direct_space_state
	var from := ledge_top + Vector3.UP * 0.3 + _dir_of(facing) * -0.2
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 0.6, WORLD_MASK, [get_rid()])
	return not space.intersect_ray(q).is_empty()


# ------------------------------------------------------------------ collision helpers
func _after_move(h_motion: Vector3) -> void:
	if state not in AIR_STATES:
		return
	if is_on_ceiling() and vy > 0.0:
		if not _try_corner_correct():
			vy = 0.0
	if is_on_floor() and vy <= 0.0:
		_land()
		return
	if not is_on_wall() or state in [State.WALL_BONK, State.GROUND_POUND]:
		return
	# Ledge assist: a lip within step height in front of a falling player pops it up.
	if vy <= 0.0 and _try_step_up(h_motion):
		return
	if _try_ledge_grab():
		return
	var n := get_wall_normal()
	var into_wall := _dir_of(facing).dot(Vector3(n.x, 0.0, n.z).normalized()) < -0.3
	if into_wall and state == State.DIVE:
		# Diving into a wall knocks you back, with no wall-kick window.
		vy = minf(vy, 0.0)
		forward_speed = dive_knockback
		platform_carry = Vector3.ZERO
		_set_state(State.FALL)
	elif into_wall and forward_speed > wall_bonk_min_speed:
		var away := Vector3(n.x, 0.0, n.z).normalized()
		kick_facing = _yaw_of(_dir_of(facing).bounce(away))
		facing = wrapf(kick_facing + PI, -PI, PI)   # face the wall while stuck to it
		forward_speed = 0.0
		platform_carry = Vector3.ZERO
		wall_timer = wall_kick_window
		_set_state(State.WALL_BONK)


## Nudge sideways around a ceiling edge hit while rising. True if it worked.
func _try_corner_correct() -> bool:
	var t := global_transform
	for dist in [0.08, 0.16, corner_correction]:
		for i in 8:
			var a := TAU * i / 8.0
			var d: Vector3 = Vector3(cos(a), 0.0, sin(a)) * float(dist)
			if test_move(t, d):
				continue
			if not test_move(t.translated(d), Vector3.UP * 0.25):
				global_position += d
				return true
	return false


## Climb onto a lip up to step_height in front of the player. True if it worked.
func _try_step_up(h_motion: Vector3) -> bool:
	if h_motion.length() < 0.001:
		return false
	var t := global_transform
	if test_move(t, Vector3.UP * step_height):
		return false
	var t2 := t.translated(Vector3.UP * step_height)
	var fwd := h_motion.normalized() * maxf(h_motion.length(), 0.12)
	if test_move(t2, fwd):
		return false
	var t3 := t2.translated(fwd)
	var col := KinematicCollision3D.new()
	if not test_move(t3, Vector3.DOWN * (step_height + 0.05), col):
		return false
	if col.get_normal().y < 0.7:
		return false
	var drop := col.get_travel().length()
	if step_height - drop < 0.03:
		return false   # nothing to step onto, just a wall
	global_position = t3.origin + col.get_travel()
	return true


func _land() -> void:
	last_land_speed = -vy
	vy = 0.0
	side_speed = 0.0
	platform_carry = Vector3.ZERO
	coyote_timer = 0.0
	landed.emit(last_land_speed)
	if state == State.GROUND_POUND:
		_set_state(State.POUND_LAND)
		pounded.emit()
		return
	if state == State.DIVE:
		forward_speed = maxf(forward_speed, 0.0)
		_set_state(State.BELLY_SLIDE)
		return
	if state in [State.BACKFLIP, State.WALL_BONK]:
		forward_speed = 0.0
	forward_speed = maxf(forward_speed, 0.0)
	landing_from = state if state != State.WALL_KICK else State.FALL
	landing_length = long_jump_landing_frames if state == State.LONG_JUMP else landing_frames
	_set_state(State.LAND)


func _can_stand() -> bool:
	if not crouched_shape:
		return true
	return not test_move(global_transform, Vector3.UP * (stand_height - crouch_height))


func _update_shape() -> void:
	var want := state in LOW_SHAPE_STATES
	if want != crouched_shape and (want or _can_stand()):
		_apply_shape(want)


func _apply_shape(crouched: bool) -> void:
	crouched_shape = crouched
	var s := _crouch_shape if crouched else _stand_shape
	collision.shape = s
	collision.position.y = s.height / 2.0


# ------------------------------------------------------------------ helpers
func _set_state(new_state: State) -> void:
	if new_state != state:
		state = new_state
		state_frames = 0.0


func respawn(at: Vector3) -> void:
	global_position = at
	velocity = Vector3.ZERO
	forward_speed = 0.0
	side_speed = 0.0
	vy = 0.0
	platform_carry = Vector3.ZERO
	jump_buffer = 0.0
	coyote_timer = 0.0
	_set_state(State.FALL)
	reset_physics_interpolation()


func _dir_of(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _yaw_of(v: Vector3) -> float:
	return atan2(-v.x, -v.z)
