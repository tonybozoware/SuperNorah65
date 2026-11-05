extends Node3D
## Odyssey-style follow camera (original implementation).
##
## - Tether: the camera hangs behind on a soft tether instead of steering toward
##   the player's facing, so moving sideways swings it around naturally, running
##   away pulls it along and running toward it pushes it back.
## - Height follows the ground the player stands on and ignores small jumps.
##   While falling, it looks ahead to where the player will land and heads there.
## - It tilts up and down to keep the player framed before it has to move.
## - Three zoom levels (cam_zoom button or mouse wheel).
## - Walls: when the normal spot is blocked or under something (like the raised
##   end of a ramp), the camera first rises, then swings sideways, and only pulls
##   in as a last resort (keeping min_distance when there is room for it).
## - Only big world geometry (layer 1) affects it. Small props (layer 4) are
##   ignored; the player's X-ray silhouette shows through them instead.

@export var target: Player

@export_group("Orbit")
@export var stick_yaw_speed := 2.6       # rad/s at full stick
@export var stick_pitch_speed := 1.6
@export var mouse_sensitivity := 0.003
@export var input_smoothing := 10.0
@export var min_pitch_deg := -55.0
@export var max_pitch_deg := 25.0
@export var default_pitch_deg := -16.0

@export_group("Distance")
@export var near_distance := 3.2         # looking fully up
@export var mid_distance := 6.5          # default pitch
@export var far_distance := 8.5          # looking fully down
@export var zoom_levels: Array[float] = [0.7, 1.0, 1.35]
@export var zoom_index := 1              # start at Normal
@export var zoom_speed := 4.0
@export var tether_return := 1.6         # how fast the tether settles back to length
@export var tether_return_at_speed := 4.0  # extra pull at full run speed
@export var tether_min := 0.65           # fraction of the length it can be pushed in to
@export var tether_max := 1.12           # fraction it can stretch to

@export_group("Follow")
@export var height := 1.3
@export var horizontal_sharpness := 14.0
@export var vertical_sharpness := 3.0
@export var vertical_catch_up := 8.0     # when the focus is well above the player
@export var air_band := 2.5              # rise allowed in a jump before following up
@export var frame_dead_zone := 0.8       # m above/below the focus before the camera tilts

@export_group("Collision")
@export_flags_3d_physics var collision_mask := 1
@export var collision_radius := 0.3
@export var overhead_clearance := 1.5    # m of open space wanted above the camera
@export var min_distance := 2.0
@export var ease_out_speed := 2.5
@export var snap_in_speed := 40.0        # fast ease when a wall pushes in (was instant)
@export var max_turn_deg_per_sec := 900.0  # the view never turns faster than this
@export var max_move_per_sec := 90.0     # nor moves faster than this (m/s), except respawns
@export var max_lift_deg := 55.0         # extra downward look when rising over walls
@export var max_swing_deg := 100.0       # sideways swing along walls (90 = beside the player)

@export_group("Recenter")
@export var recenter_time := 0.25

@onready var cam: Camera3D = $Camera3D

var yaw := 0.0
var pitch := 0.0
var yaw_vel := 0.0
var pitch_vel := 0.0
var mouse_delta := Vector2.ZERO
var ground_y := 0.0
var focus := Vector3.ZERO
var horiz := 0.0            # current tether length (horizontal, before zoom)
var col_frac := 1.0
var recentering := false
var zoom := 1.0
var lift := 0.0             # radians, current wall rise
var _want_lift := 0.0
var _side_cooldown := 0.0   # seconds before the swing may switch sides again
var _swing_side := 1.0
var _orbit := Vector2.ZERO  # tether point (flat), independent of wall adjustments
var _shape := SphereShape3D.new()
var _last_target_pos := Vector3.ZERO
var _aim_y := 0.0
var _cam_pos := Vector3.ZERO
var _cam_fwd := Vector3.FORWARD
var _snap_next := true      # place the camera exactly (start, respawn)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	pitch = deg_to_rad(default_pitch_deg)
	_shape.radius = collision_radius
	zoom_index = clampi(zoom_index, 0, zoom_levels.size() - 1)
	zoom = zoom_levels[zoom_index]
	snap_behind()


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_delta += motion.relative
		return
	var button := event as InputEventMouseButton
	if button and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(zoom_index - 1)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(zoom_index + 1)
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			# A click that recaptures the mouse shouldn't also dive or roll.
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Input.action_release("attack")
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _set_zoom(i: int) -> void:
	zoom_index = clampi(i, 0, zoom_levels.size() - 1)


## Jump straight to the default spot behind the player (start, respawn, teleport).
func snap_behind() -> void:
	if target == null:
		return
	var p := target.global_position
	_last_target_pos = p
	yaw = target.facing
	ground_y = p.y
	focus = p + Vector3.UP * height
	_aim_y = focus.y
	horiz = _distance() * cos(pitch)
	_orbit = Vector2(focus.x, focus.z) + Vector2(sin(yaw), cos(yaw)) * horiz
	col_frac = 1.0
	lift = 0.0
	_want_lift = 0.0
	_snap_next = true
	_place_camera(1.0)


func _process(delta: float) -> void:
	if target == null:
		return
	var p := target.global_position
	if p.distance_to(_last_target_pos) > 4.0:
		snap_behind()   # the player teleported (respawn)
	_last_target_pos = p
	if Input.is_action_just_pressed("cam_zoom"):
		_set_zoom((zoom_index + 1) % zoom_levels.size())
	zoom = lerpf(zoom, zoom_levels[zoom_index], 1.0 - exp(-zoom_speed * delta))
	_update_focus(delta)
	_update_tether(delta)
	_update_input(delta)
	_place_camera(delta)


func _update_focus(delta: float) -> void:
	var p := target.get_global_transform_interpolated().origin
	if target.is_on_floor() or p.y < ground_y:
		ground_y = p.y
	elif p.y > ground_y + air_band:
		ground_y = p.y - air_band
	elif target.vy < 0.0:
		# Falling: look ahead to the landing spot and start heading down early.
		var land_y := _ground_below(p)
		if land_y < ground_y - 0.5:
			ground_y = lerpf(ground_y, land_y, 1.0 - exp(-5.0 * delta))

	var h := 1.0 - exp(-horizontal_sharpness * delta)
	focus.x = lerpf(focus.x, p.x, h)
	focus.z = lerpf(focus.z, p.z, h)
	var goal_y := ground_y + height
	var vs := vertical_sharpness
	if focus.y - goal_y > 1.0:
		vs = vertical_catch_up   # catch up quickly after big drops
	focus.y = lerpf(focus.y, goal_y, 1.0 - exp(-vs * delta))

	# Tilt (not move) to keep the player framed: aim at the chest once it leaves
	# a dead zone around the focus, up or down.
	var d := (p.y + 1.0) - focus.y
	var aim_goal := focus.y + signf(d) * maxf(absf(d) - frame_dead_zone, 0.0)
	_aim_y = lerpf(_aim_y, aim_goal, 1.0 - exp(-8.0 * delta))


func _ground_below(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.2, p + Vector3.DOWN * 40.0,
			Player.WORLD_MASK, [target.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return p.y - 40.0 if hit.is_empty() else float(hit.position.y)


## The tether point stays where it was; the player moved. Read the new angle and
## length from that, then let the length settle back (faster at speed).
func _update_tether(delta: float) -> void:
	var offset := _orbit - Vector2(focus.x, focus.z)
	if offset.length() > 0.01:
		yaw = atan2(offset.x, offset.y)
		horiz = offset.length()
	var want := _distance() * cos(pitch)
	var speed_ratio := clampf(target.forward_speed / target.max_walk_speed, 0.0, 1.0)
	var rate := tether_return + tether_return_at_speed * speed_ratio
	horiz = lerpf(horiz, want, 1.0 - exp(-rate * delta))
	horiz = clampf(horiz, want * tether_min, want * tether_max)


func _update_input(delta: float) -> void:
	var stick := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	var t := 1.0 - exp(-input_smoothing * delta)
	yaw_vel = lerpf(yaw_vel, -stick.x * stick_yaw_speed, t)
	pitch_vel = lerpf(pitch_vel, -stick.y * stick_pitch_speed, t)
	yaw += yaw_vel * delta - mouse_delta.x * mouse_sensitivity
	pitch += pitch_vel * delta - mouse_delta.y * mouse_sensitivity
	pitch = clampf(pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	var manual := stick.length() > 0.1 or mouse_delta != Vector2.ZERO
	mouse_delta = Vector2.ZERO
	target.camera_turned_by_hand = manual

	if Input.is_action_just_pressed("cam_recenter"):
		recentering = true
	if manual:
		recentering = false
	if recentering:
		yaw = lerp_angle(yaw, target.facing, 1.0 - exp(-3.0 * delta / recenter_time))
		if absf(angle_difference(yaw, target.facing)) < 0.01:
			recentering = false
	_orbit = Vector2(focus.x, focus.z) + Vector2(sin(yaw), cos(yaw)) * horiz


## Distance along the view direction for the current pitch (before zoom).
func _distance() -> float:
	var d := deg_to_rad(default_pitch_deg)
	if pitch <= d:
		return lerpf(mid_distance, far_distance, inverse_lerp(d, deg_to_rad(min_pitch_deg), pitch))
	return lerpf(mid_distance, near_distance, inverse_lerp(d, deg_to_rad(max_pitch_deg), pitch))


## Camera position for a given wall rise and swing.
func _spot(aim: Vector3, extra_lift: float, extra_swing: float) -> Vector3:
	var pch := maxf(pitch - extra_lift, deg_to_rad(-80.0))
	var dist := _distance() * zoom
	var hz := horiz * zoom * cos(pch) / maxf(cos(pitch), 0.2)
	var y := yaw + extra_swing
	return aim + Vector3(sin(y) * hz, -sin(pch) * dist, cos(y) * hz)


## Fraction of the way from aim to pos that is free of big geometry (1 = clear).
func _cast(aim: Vector3, pos: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape
	q.transform = Transform3D(Basis(), aim)
	q.motion = pos - aim
	q.collision_mask = collision_mask
	var res := space.cast_motion(q)
	return 1.0 if res.size() < 2 else res[0]


func _covered(pos: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(pos, pos + Vector3.UP * overhead_clearance, collision_mask)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _is_clear(aim: Vector3, pos: Vector3) -> bool:
	return _cast(aim, pos) > 0.98 and not _covered(pos)


func _place_camera(delta: float) -> void:
	var aim := Vector3(focus.x, maxf(focus.y, _aim_y), focus.z)
	var look := Vector3(focus.x, _aim_y, focus.z)
	_side_cooldown -= delta

	# Find the least-changed clear spot: as is, then rising, then swinging round.
	var want_lift := 0.0
	var want_swing := 0.0
	var found := _is_clear(aim, _spot(aim, 0.0, 0.0))
	if not found and _want_lift > 0.0 and _is_clear(aim, _spot(aim, _want_lift, 0.0)):
		want_lift = _want_lift   # keep the current rise while it still works
		found = true
	if not found:
		var max_lift := deg_to_rad(max_lift_deg)
		for l in [max_lift / 3.0, max_lift * 2.0 / 3.0, max_lift]:
			if _is_clear(aim, _spot(aim, l, 0.0)):
				want_lift = l
				found = true
				break
	if not found:
		var max_sw := deg_to_rad(max_swing_deg)
		# Try the side the camera last swung to first, all the way round, before the
		# other side; right after a switch, don't switch back.
		var sides := [_swing_side, -_swing_side]
		if _side_cooldown > 0.0:
			sides = [_swing_side]
		for side in sides:
			for sw in [max_sw * 0.25, max_sw * 0.5, max_sw * 0.75, max_sw]:
				for l in [0.0, deg_to_rad(max_lift_deg) / 2.0]:
					if not found and _is_clear(aim, _spot(aim, l, sw * side)):
						want_lift = l
						want_swing = sw * side
						found = true
	_want_lift = want_lift

	# Rise: ease toward it, quickly when moving away from a wall, slowly when relaxing.
	var badly_blocked := found and _cast(aim, _spot(aim, lift, 0.0)) < 0.35
	var lift_rate := 6.0 if want_lift > lift else 2.0
	if badly_blocked:
		lift_rate = 20.0   # fast, but eased rather than a jump
	lift = lerpf(lift, want_lift, 1.0 - exp(-lift_rate * delta))

	# Swing: actually turn the camera round (it stays there afterwards, like Odyssey),
	# quickly when the current view is badly blocked.
	if want_swing != 0.0:
		recentering = false   # a wall is in the way: don't fight it
		if signf(want_swing) != _swing_side:
			_swing_side = signf(want_swing)
			_side_cooldown = 1.0
		var rate := 3.5
		if badly_blocked:
			rate = 16.0   # swing round in about 0.1 s instead of cutting
		elif _cast(aim, _spot(aim, lift, 0.0)) < 0.6:
			rate = 8.0
		yaw += clampf(want_swing, -rate * delta, rate * delta)
		_orbit = Vector2(focus.x, focus.z) + Vector2(sin(yaw), cos(yaw)) * horiz

	# Last resort: pull in along the view line (fast ease in, slow ease out).
	var desired := _spot(aim, lift, 0.0)
	var frac := _cast(aim, desired)
	var dist := aim.distance_to(desired)
	if _covered(desired):
		for f in [0.85, 0.7, 0.55, 0.4, 0.25, 0.1]:
			if not _covered(aim.lerp(desired, f)):
				frac = minf(frac, f)
				break
	# Stay at least min_distance away when there's room; in a truly tight spot,
	# come in as close as needed rather than clipping into the wall.
	var min_frac := min_distance / maxf(dist, 0.01)
	if frac < min_frac and _cast(aim, aim.lerp(desired, min_frac)) > 0.98 \
			and not _covered(aim.lerp(desired, min_frac)):
		frac = min_frac
	var in_rate := snap_in_speed if frac < col_frac else ease_out_speed
	col_frac = lerpf(col_frac, frac, 1.0 - exp(-in_rate * delta))

	var pos := aim + (desired - aim) * col_frac
	if _snap_next:
		col_frac = frac
		pos = aim + (desired - aim) * col_frac
	else:
		# Never move faster than the limit in a single frame.
		pos = _cam_pos + (pos - _cam_pos).limit_length(max_move_per_sec * delta)
	var fwd := (look - pos).normalized() if not pos.is_equal_approx(look) else _cam_fwd
	if _snap_next:
		_snap_next = false
	else:
		# Nor turn faster than the limit.
		var max_turn := deg_to_rad(max_turn_deg_per_sec) * delta
		var ang := _cam_fwd.angle_to(fwd)
		if ang > max_turn:
			fwd = _cam_fwd.slerp(fwd, max_turn / ang).normalized()
	_cam_pos = pos
	_cam_fwd = fwd
	cam.global_position = pos
	if absf(fwd.dot(Vector3.UP)) < 0.999:
		cam.look_at(pos + fwd, Vector3.UP)
