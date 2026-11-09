extends Node
## Applies a PlayerSkin to the primitive body. Lives on Player/Skin.
##
## - body_material goes on every body part; the plain materials come back when a
##   skin has none.
## - The see-through-walls silhouette is kept by an overlay pass, so a skin's
##   shader doesn't need any stencil code of its own.
## - emitter_scene is instanced on each mounted body part (hands, head, feet...).
## - A skin's video plays on loop (muted) and is fed to its material as a texture.
## - Press next_skin_key (K) to cycle skins while testing.

signal skin_changed(skin: PlayerSkin)

const MOUNT_PATHS := {
	PlayerSkin.Mount.HEAD: "Body/HeadPivot/Head",
	PlayerSkin.Mount.TORSO: "Body/Torso",
	PlayerSkin.Mount.HAND_L: "Body/ArmL/Hand",
	PlayerSkin.Mount.HAND_R: "Body/ArmR/Hand",
	PlayerSkin.Mount.FOOT_L: "Body/LegL/Foot",
	PlayerSkin.Mount.FOOT_R: "Body/LegR/Foot",
}
const XRAY_COLOR := Color(0.35, 0.75, 1.0, 0.75)

## Leave empty to use every skin in skins_folder.
@export var skins: Array[PlayerSkin] = []
@export_dir var skins_folder := "res://skins"
@export var start_skin := 0
@export var next_skin_key: Key = KEY_K

@onready var visual: Node3D = get_node("../Visual")

var current := -1
var _meshes: Array[MeshInstance3D] = []
var _original := {}            # MeshInstance3D -> its plain material
var _emitters: Array[Node] = []
var _light: OmniLight3D
var _xray_overlay: StandardMaterial3D
var _video: VideoStreamPlayer
var _skin: PlayerSkin
var _time := 0.0


func _ready() -> void:
	for node in visual.get_node("Body").find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		_meshes.append(mi)
		_original[mi] = mi.material_override
	if skins.is_empty():
		_load_folder()
	_xray_overlay = _make_xray_overlay()
	_light = OmniLight3D.new()
	_light.visible = false
	_light.shadow_enabled = false
	visual.get_node("Body/Torso").add_child(_light)
	# The video player sits in an off-screen SubViewport: it decodes frames for the
	# material but is never drawn on screen.
	var vp := SubViewport.new()
	vp.size = Vector2i(2, 2)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	_video = VideoStreamPlayer.new()
	_video.loop = true
	_video.volume = 0.0
	vp.add_child(_video)
	if not skins.is_empty():
		apply(clampi(start_skin, 0, skins.size() - 1))


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == next_skin_key and not skins.is_empty():
		apply((current + 1) % skins.size())


func apply(index: int) -> void:
	var skin := skins[index]
	current = index
	_skin = skin
	for e in _emitters:
		e.queue_free()
	_emitters.clear()

	for mi in _meshes:
		if skin.body_material:
			mi.material_override = skin.body_material
			mi.material_overlay = _xray_overlay if skin.keep_xray else null
		else:
			mi.material_override = _original[mi]   # plain materials have the silhouette built in
			mi.material_overlay = null

	if skin.emitter_scene:
		for m in skin.mounts:
			var part := visual.get_node_or_null(MOUNT_PATHS.get(m, "")) as Node3D
			if part:
				var e := skin.emitter_scene.instantiate()
				part.add_child(e)
				_emitters.append(e)

	_video.stop()
	if skin.video:
		_video.stream = skin.video
		_video.play()
		var sm := skin.body_material as ShaderMaterial
		if sm:
			sm.set_shader_parameter(skin.video_uniform, _video.get_video_texture())

	_light.visible = skin.light_energy > 0.0
	_light.light_energy = skin.light_energy
	_light.light_color = skin.light_color
	_light.omni_range = skin.light_range
	skin_changed.emit(skin)
	print("Skin: ", skin.skin_name)


func _process(delta: float) -> void:
	_time += delta
	if _skin and _light.visible and _skin.light_flicker > 0.0:
		var f := 0.5 * sin(_time * 23.0) + 0.3 * sin(_time * 37.0 + 1.3) + 0.2 * sin(_time * 61.0 + 2.1)
		_light.light_energy = _skin.light_energy * (1.0 + f * 0.5 * _skin.light_flicker)


func _load_folder() -> void:
	var files := Array(DirAccess.get_files_at(skins_folder))
	files.sort()
	for f in files:
		var file: String = f.trim_suffix(".remap")   # exported builds list .tres.remap
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var res := load(skins_folder.path_join(file))
		if res is PlayerSkin:
			skins.append(res)


## An invisible pass over the body that marks where the body is visible, plus the
## blue silhouette drawn wherever it is hidden behind something (same as the plain
## materials' built-in silhouette).
func _make_xray_overlay() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0, 0, 0, 0)
	m.stencil_mode = BaseMaterial3D.STENCIL_MODE_XRAY
	m.stencil_color = XRAY_COLOR
	return m
