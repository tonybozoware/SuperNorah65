extends Node3D
## Endless floor for the void stage: an infinite collision plane at y = 0, a large
## glossy black surface that follows the player sideways (so you never reach its
## edge), and water ripples from the player's footsteps, landings and jumps.
## The ripples only appear when the player is standing on the floor itself.
##
## Reflection: a hidden mirror camera, flipped under the floor, renders the scene
## (everything but the floor) into an off-screen image at reduced resolution. The
## floor shader looks up the right pixel of that image for each spot on the floor,
## bends it with the ripples, softens it, dims it like dark water and fades it out
## with distance.

@export var floor_size := 400.0
@export var footstep_strength := 0.6
@export var land_strength := 1.6          # at land_full_impact
@export var land_full_impact := 75.0      # u/f downward
@export var jump_strength := 0.9
@export var foot_spacing := 0.13          # m left/right of centre for each step

@export_group("Reflection")
@export var reflection_enabled := true
@export_range(0.25, 1.0) var reflection_resolution := 0.5   # of the screen size
## Render layer the floor is on; the mirror camera skips it so the floor doesn't
## reflect itself.
@export_range(1, 20) var floor_layer := 20

const MAX_RIPPLES := 24   # must match the ripples array size in void_floor.gdshader

var _player: Player
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _ripples := PackedVector4Array()
var _next := 0
var _left := false
var _time := 0.0
var _reflect_vp: SubViewport
var _mirror: Camera3D


func _ready() -> void:
	# Collision: an infinite plane, so there's nowhere to fall.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	body.add_child(shape)
	add_child(body)

	# Visuals: one big plane that follows the player.
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://levels/void_floor.gdshader")
	var plane := PlaneMesh.new()
	plane.size = Vector2(floor_size, floor_size)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = plane
	_mesh.material_override = _mat
	_mesh.top_level = true
	_mesh.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_mesh)
	_mesh.layers = 1 << (floor_layer - 1)

	if reflection_enabled:
		_make_reflection()
	_mat.set_shader_parameter("reflection_on", reflection_enabled)
	process_priority = 100   # after the camera rig moves the camera each frame

	_ripples.resize(MAX_RIPPLES)
	_mat.set_shader_parameter("ripples", _ripples)
	_find_player.call_deferred()


func _find_player() -> void:
	_player = get_tree().current_scene.find_child("Player", true, false) as Player
	if not _player:
		push_warning("void_floor: no Player found, ripples are off")
		return
	_player.landed.connect(_on_landed)
	_player.jumped.connect(func(_kind: int): _add_at_player(jump_strength, 0.0))
	var visual := _player.get_node_or_null("Visual")
	if visual and visual.has_signal("footstep"):
		visual.connect("footstep", _on_footstep)


func _process(delta: float) -> void:
	_time += delta
	_mat.set_shader_parameter("now", _time)
	if _player:
		var p := _player.get_global_transform_interpolated().origin
		_mesh.global_position = Vector3(p.x, 0.0, p.z)
	if _mirror:
		_update_mirror()


func _make_reflection() -> void:
	_reflect_vp = SubViewport.new()
	_reflect_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_reflect_vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_reflect_vp)
	_mirror = Camera3D.new()
	_mirror.cull_mask = 0xFFFFF & ~(1 << (floor_layer - 1))
	_mirror.current = true
	_reflect_vp.add_child(_mirror)
	_resize_reflection()
	get_viewport().size_changed.connect(_resize_reflection)
	_mat.set_shader_parameter("reflection_tex", _reflect_vp.get_texture())


func _resize_reflection() -> void:
	var size := get_viewport().get_visible_rect().size * reflection_resolution
	_reflect_vp.size = Vector2i(maxi(int(size.x), 16), maxi(int(size.y), 16))


## Put the mirror camera at the main camera's position flipped under the floor
## (y = 0), looking along the flipped view direction. Seen through any floor point,
## it shows exactly what the water would reflect there.
func _update_mirror() -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var t := cam.global_transform
	var pos := Vector3(t.origin.x, -t.origin.y, t.origin.z)
	var fwd := -t.basis.z
	fwd.y = -fwd.y
	var up := Vector3.UP if absf(fwd.y) < 0.99 else Vector3.FORWARD
	_mirror.fov = cam.fov
	_mirror.near = cam.near
	_mirror.far = cam.far
	_mirror.look_at_from_position(pos, pos + fwd, up)
	var vp: Projection = _mirror.get_camera_projection() * Projection(_mirror.global_transform.affine_inverse())
	_mat.set_shader_parameter("mirror_vp", vp)


func _on_footstep(strength: float) -> void:
	_left = not _left
	_add_at_player(footstep_strength * lerpf(0.5, 1.0, strength), foot_spacing if _left else -foot_spacing)


func _on_landed(impact: float) -> void:
	_add_at_player(land_strength * clampf(impact / land_full_impact, 0.3, 1.0), 0.0)


## side: metres to the player's left (+) or right (-), for alternating feet.
func _add_at_player(strength: float, side: float) -> void:
	var p := _player.global_position
	if absf(p.y) > 0.15:
		return   # on a step, platform or in the air, not on the water
	var right := Vector3(cos(_player.facing), 0.0, -sin(_player.facing))
	p -= right * side
	_ripples[_next] = Vector4(p.x, p.z, _time, strength)
	_next = (_next + 1) % MAX_RIPPLES
	_mat.set_shader_parameter("ripples", _ripples)
