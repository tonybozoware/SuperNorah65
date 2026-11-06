# SM64-Style Platformer (Godot 4.6.2 greybox)

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
| Hoverboard on / off | F | B / Circle |
| Boost (on the board) | Shift | Triggers |

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

## Hoverboard

Press F (B / Circle) to summon the board, on the ground or in the air; press it
again to step off and keep your speed. Riding: the stick steers (wide, momentum-heavy
turns that drift at speed), pull the stick back to brake and then reverse slowly,
hold Shift / a trigger to boost (the meter drains in about 3 s and refills after
you let go), hold jump to crouch and charge, then let go to jump: a quick tap jumps about 2.2 m, a full 0.35 s charge 4.5 m, and the board drifts down slower than it rises (long drops speed back up after 1.5 s) (the pads flash when it's full). Letting go just after riding off an edge still jumps. In the air, the left
stick steers and the right stick (arrow keys) does tricks: sideways to spin, up/down to
flip, diagonals for both, faster the further you push; the mouse still turns the camera; land a trick of 300
degrees or more to refill part of the boost meter. Slopes speed you up and slow you
down more than on foot. The board holds its height briefly over drops. Glancing off
a wall slides you along it; hitting one head-on at speed knocks you off.

Test course: east of the main stage (keep running along +X past the ramps), with a
kicker ramp over a 6 m gap, then a plateau with a long ramp to ride up or down.

Skate plaza: west of the main stage (head along -X). Half pipe (stairs up to the east
deck), sunken bowl, spine, quarter pipes along the north edge, funbox with kickers and a
ledge, a stair set with a down-ledge, and a long wide ledge. Orange pieces (ledges and
coping) throw sparks when you ride along them; there is no grind mode, just ride along the
top and keep your balance. The board rides any surface it's lined up with, so curves carry
you up to vertical; a sharp corner from flat ground is still a wall (head-on at speed
knocks you off). On steep walls you need about 4 m/s to stay on. Going straight up a
vertical keeps you lined up so you drop back in; hold the left stick toward the deck as
you launch to fly out onto it instead. Rolling slowly over a lip drops you in down the wall.

All board tuning is in the Player's Inspector under "Hoverboard (m/s)"; the camera's
speed pull-back and FOV are under "Board speed" on the CameraRig; the trail is on FX.
Clips named BoardStance (standing) and BoardCrouch (charging) in the .glb are used
automatically; until then Norah stands in her Idle pose and crouches with her crouch clip.

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
LedgeHang, LedgeClimb, GroundPound, BoardStance, BoardCrouch.
