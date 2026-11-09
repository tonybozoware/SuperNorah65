class_name PlayerSkin
extends Resource
## A look for the player: a body material, small particle emitters on body parts,
## and an optional glow light. Save skins as .tres files in res://skins/ and the
## Player's Skin node picks them up (sorted by file name; the first is the default).

enum Mount { HEAD, TORSO, HAND_L, HAND_R, FOOT_L, FOOT_R }

@export var skin_name := "Unnamed"
## Material for every body part (any shader). Leave empty to keep the plain
## shirt / skin / pants / shoe colours.
@export var body_material: Material
## Keep the blue see-through-walls silhouette when this skin's material is used.
@export var keep_xray := true

@export_group("Video")
## Optional video played on loop and fed to body_material as a texture
## (e.g. a galaxy). Godot plays Ogg Theora (.ogv) files.
@export var video: VideoStream
## Name of the sampler2D uniform in body_material that receives the video.
@export var video_uniform := &"video_tex"

@export_group("Particles")
## Scene instanced once at each mount below, usually a GPUParticles3D. It follows
## that body part; set its local_coords off so particles trail behind.
@export var emitter_scene: PackedScene
@export var mounts: Array[Mount] = [Mount.HAND_L, Mount.HAND_R, Mount.HEAD, Mount.FOOT_L, Mount.FOOT_R]

@export_group("Light")
@export var light_energy := 0.0          # 0 = no light
@export var light_color := Color(1.0, 0.6, 0.3)
@export var light_range := 3.0
@export_range(0.0, 1.0) var light_flicker := 0.0   # 0 = steady, 1 = strong firelight flicker
