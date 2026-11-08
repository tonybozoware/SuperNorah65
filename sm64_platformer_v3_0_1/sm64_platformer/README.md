# Biryani64 (Godot 4.6.2 greybox, SM64-style movement)

Open this folder in Godot 4.6.2 (Project Manager > Import > select `project.godot`), then press F5.
The first open takes a few seconds while Godot imports the project.

## Controls

| Action | Keyboard / mouse | Gamepad |
| --- | --- | --- |
| Move | WASD | Left stick |
| Jump | Space | A / Cross |
| Crouch / ground pound | Shift | Triggers |
| Dive | J or left mouse | X / Square |
| Roll | Hold Shift + J (press J again to speed up) | Hold trigger + X / Square |
| Camera orbit | Mouse or arrow keys | Right stick |
| Crawl | Hold Shift + move | Hold trigger + move |
| Recenter camera | R | LB / L1 |
| Camera zoom (Near / Normal / Far) | Z or mouse wheel | Right stick click (R3) |
| Free the mouse | Esc (click to capture again) | |

Moves: single/double/triple jump (jump again right as you land), long jump
(run, crouch, jump), backflip (stand, crouch, jump), side flip (reverse the
stick at a run, then jump), wall kick (jump into a wall, press jump on contact),
ground pound (crouch in the air), crouch slide (crouch while running), crawl
(hold crouch and move), dive (attack in the air, or from a fast run), belly slide
after a dive, rollout (jump or attack during the belly slide), roll (crouch + attack;
more presses add speed; release crouch to run on), ledge grab (catch a ledge while
falling; forward or jump climbs, back or crouch drops).

Forgiveness and feel options (all in the Player's Inspector, each can be tuned or
switched off): coyote time, jump/crouch/dive buffering, corner correction, step-up
and ledge assist (lips up to 0.3 m), apex hang, faster fall, quicker low-speed
turning, slope momentum. The FX node adds a landing shadow, dust puffs and
controller rumble.

Movement logic runs at 30 ticks per second like SM64 (Project Settings > Physics),
with physics interpolation keeping the visuals smooth. Speeds in `player.gd` are in
SM64 units per frame (1 unit/frame = 0.3 m/s).

## Layout

- `scenes/main.tscn` - main scene: environment, light, stage, player, camera
- `scenes/player.tscn` - CharacterBody3D with a primitive humanoid body under `Visual`
- `scenes/camera_rig.tscn` - follow camera rig
- `levels/test_stage.tscn` - CSG blockout test stage
- `scripts/` - player, player_animator (procedural animation), player_fx (shadow, dust, rumble), camera, moving platform, kill zone
- `materials/` - flat-color materials, no textures

All tuning values are exported variables on the Player and CameraRig nodes.

Collision layers: 1 world (camera collides), 2 player, 3 hazards, 4 props the camera ignores
(floating platforms, moving platform, steps). Put new small props on layer 4.

Camera: tether follow, looks ahead to the landing spot when falling, tilts to keep
you framed, three zoom levels, and avoids walls by rising, then swinging round, then
pulling in only as a last resort. While the camera adjusts itself, a held stick keeps
its direction, so automatic camera moves don't steer you.

## Player model (Norah)

The player uses the Norah model (`models/norah/NorahStarr.glb`), scaled to the
1.6 m collision, guns kept. Untick **Use Model** on Player > Visual to switch
back to the primitive body.

Her clips are used where they fit (idle, walk/run by speed, crouch, jump matched
to the jump arc); other moves reuse the nearest clip plus whole-body motion in
code. Animations added to the .glb with these names are picked up automatically:
Idle, Walk, Run, Skid, Crouch, Crawl, Slide, Jump, DoubleJump, Flip, Fall, Dive,
LedgeHang, LedgeClimb, GroundPound.
