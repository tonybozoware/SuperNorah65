extends Node3D
## Readability and feedback for the player, with no textures:
## - a landing shadow (dark disc) straight below the player
## - dust puffs (small grey spheres) on skids, slides, rolls and hard landings
## - controller rumble on ground pounds, hard landings, wall kicks and ledge grabs
## - a short white-noise pulse on every footstep
## Lives on Player/FX. Everything is built in code so it needs no assets.

@export_group("Shadow")
@export var shadow_enabled := true
@export var shadow_radius := 0.4
@export var shadow_opacity := 0.45
@export var shadow_fade_height := 12.0   # m; the disc shrinks to 35% by this height

@export_group("Dust")
@export var dust_enabled := true
@export var trail_min_speed := 8.0       # u/f
@export var hard_landing_speed := 40.0   # u/f downward

@export_group("Rumble")
@export var rumble_enabled := true

@export_group("Footstep Pulse")
@export var step_pulse_enabled := true
@export var step_pulse_length := 0.035   # s
@export var step_pulse_volume_db := -12.0
@export var step_pulse_min_volume := 0.35  # loudness at a slow walk, 1.0 at full speed

const TRAIL_STATES := [Player.State.SKID, Player.State.BRAKE, Player.State.CROUCH_SLIDE,
		Player.State.BELLY_SLIDE, Player.State.ROLL]

@onready var player: Player = get_parent()

var _shadow: MeshInstance3D
var _trail: CPUParticles3D
var _burst: CPUParticles3D
var _step_player: AudioStreamPlayer


func _ready() -> void:
	_shadow = _make_shadow()
	_trail = _make_dust(false)
	_burst = _make_dust(true)
	player.landed.connect(_on_landed)
	player.pounded.connect(_on_pounded)
	player.wall_kicked.connect(func(): _rumble(0.35, 0.2, 0.1))
	player.ledge_grabbed.connect(func(): _rumble(0.25, 0.0, 0.08))
	_step_player = _make_step_pulse()
	var visual := player.get_node_or_null("Visual")
	if visual and visual.has_signal("footstep"):
		visual.connect("footstep", _on_footstep)


func _process(_delta: float) -> void:
	_update_shadow()
	var feet := player.get_global_transform_interpolated().origin
	_trail.global_position = feet
	_trail.emitting = dust_enabled and player.is_on_floor() \
			and player.state in TRAIL_STATES and player.forward_speed > trail_min_speed


func _update_shadow() -> void:
	if not shadow_enabled:
		_shadow.visible = false
		return
	var from := player.get_global_transform_interpolated().origin + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 40.0,
			Player.WORLD_MASK, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_shadow.visible = false
		return
	_shadow.visible = true
	var n: Vector3 = hit.normal
	var height: float = from.y - 0.3 - hit.position.y
	var s := clampf(1.0 - height / shadow_fade_height * 0.65, 0.35, 1.0)
	var x := n.cross(Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var basis := Basis(x, n, x.cross(n)).scaled(Vector3(s, 1.0, s))
	_shadow.global_transform = Transform3D(basis, hit.position + n * 0.03)


func _on_landed(impact: float) -> void:
	if impact >= hard_landing_speed:
		_puff(10, 1.6)
		_rumble(0.4, 0.3, 0.12)


func _on_pounded() -> void:
	_puff(20, 3.0)
	_rumble(0.6, 0.9, 0.25)


func _puff(amount: int, speed: float) -> void:
	if not dust_enabled:
		return
	_burst.global_position = player.global_position
	_burst.amount = amount
	_burst.initial_velocity_min = speed * 0.6
	_burst.initial_velocity_max = speed
	_burst.restart()


func _on_footstep(strength: float) -> void:
	if not step_pulse_enabled:
		return
	_step_player.volume_db = step_pulse_volume_db + linear_to_db(lerpf(step_pulse_min_volume, 1.0, strength))
	_step_player.play()


## A short burst of white noise with a fast decay, built in code (no audio file).
func _make_step_pulse() -> AudioStreamPlayer:
	var rate := 44100
	var n := int(step_pulse_length * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 64
	for i in n:
		var t := float(i) / n
		var env := minf(t * n / 44.0, 1.0) * pow(1.0 - t, 3.0)   # 1 ms attack, quick decay
		var s := int(clampf(rng.randf_range(-1.0, 1.0) * env, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	var ap := AudioStreamPlayer.new()
	ap.stream = wav
	ap.max_polyphony = 4
	ap.volume_db = step_pulse_volume_db
	add_child(ap)
	return ap


func _rumble(weak: float, strong: float, seconds: float) -> void:
	if not rumble_enabled:
		return
	for pad in Input.get_connected_joypads():
		Input.start_joy_vibration(pad, weak, strong, seconds)


func _make_shadow() -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = shadow_radius
	mesh.bottom_radius = shadow_radius
	mesh.height = 0.01
	mesh.radial_segments = 24
	mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, shadow_opacity)
	mat.no_depth_test = false
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(mi)
	return mi


func _make_dust(one_shot: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	sphere.radial_segments = 8
	sphere.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	sphere.material = mat
	p.mesh = sphere
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.85, 0.82, 0.7))
	ramp.set_color(1, Color(0.85, 0.85, 0.82, 0.0))
	p.color_ramp = ramp
	p.local_coords = false
	p.top_level = true
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.direction = Vector3.UP
	p.spread = 70.0 if not one_shot else 85.0
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	p.lifetime = 0.5
	if one_shot:
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = 16
		p.emitting = false
	else:
		p.amount = 24
		p.initial_velocity_min = 0.4
		p.initial_velocity_max = 1.2
		p.emitting = false
	add_child(p)
	return p
