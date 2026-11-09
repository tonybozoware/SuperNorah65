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
| Next skin (testing) | K | |
| Next sound kit (testing) | L | |

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

## Audio

The player's sounds come from **sound kits** (`kits/*.tres`), played by Player > Kit
(`scripts/kits/kit_player.gd`). Press L to switch kits; `start_kit` on the Kit node picks
the first one. Each kit holds:
- **Events**: what plays on footsteps, jumps (each kind separately), landings (by what you
  landed from), dives, ground pounds and their landings, wall kicks, ledge grabs, skids,
  running into a wall and hitting a ceiling. An event plays one of the instruments below.
  Synth events have notes (a chord, a random pick or a sequence), a length or "hold until
  land", and a velocity that can follow footstep strength or impact. Events with an "Only
  From" filter replace the kit's "Any" events for that trigger.
- **Patch**: Instruments settings applied when the kit is switched on (the old kit's
  changes go back to the Inspector values first).
- **Live routes**: links from the player to Instruments settings, updated every frame.
  Sources: the run meter, speed, facing (north/east), airtime and vertical speed.
- **Run meter**: fills while you keep near top speed (8 bars by default), holds when you
  slow down, jump or skid-turn, and empties over 0.5 s once you stop (slow with the stick
  let go, or slow for over a second).

Footsteps run at 124 BPM eighth notes at full speed (Player > Visual > `run_bpm`). Each
step lands when the legs are fully out (`step_phase` 0.5; 0 = legs passing under the body),
corrected for the pose smoothing so it matches what you see; the body bob dips on the step
and the void floor's ripples start there too.

Kits:
- **Noise Test Kit**: noise burst on footsteps, orchestra hit on jumps, timpani on landings.
- **Tonal Test Kit** (G13): each footstep is a random 200 ms note from G3 B3 D4 F4 A4 C5 E5
  on the analog synth, using Plaits' Waveshaping model (the wavefolder) as the oscillator
  (50% resonance). The notes carry on in the air at the stride's tempo (the kit's
  `steps_in_air`). Rolling plays the same notes as 100 ms 16ths at top roll speed, slower
  as the roll slows (and on into the air if you roll off an edge). The filter opens from 25% of the cutoff knob as the run meter fills, with
  drive rising alongside it; the fold amount follows facing (north full, east/west half,
  south a clean sine). Chords are on Dexed's SOFT EP with a quick 180 ms
  release: landings play a G major (G3 B3 D4); the triple jump goes G13 (G2 F3 B3 E4 A4 C5)
  > two-octave F major (F3 to F5) > G13 doubled an octave up, and its landing plays a
  two-octave C major (C3 to C5), even if you dive, ground pound or bonk out of it first. Each jump chord holds until you land and cuts the one before;
  a landing chord fades out in 60 ms as soon as the next jump chord starts, so in a chain they
  never pile up. Side flips, backflips and long jumps play an F major (F3 A3 C4),
  held until you land. Wall kicks are silent for now.

## Instruments

The **Instruments** node in both main scenes plays every sound. All instruments run in one
Pure Data instance (patches in `pd/`, mixer in `pd/instruments.pd`):
- **Analog synth** (`analog_synth.pd` + `analog_voice.pd`): 6 voices, two detuned
  oscillators (saw, pulse or a mix, with pulse width) + sub square + a **Plaits**
  oscillator (all 24 Mutable Instruments Plaits models), pre-filter drive, Moog-style ladder
  filter, filter and amp envelopes. Plaits is off until `plaits_level` is above 0.
- **Drums** (`drums.pd`): kick (pitch sweep, drive), snare (tone + noise), hi-hat.
- **Noise** (`noise.pd`): a band-passed noise burst whose filter sweeps down.
- **Orchestra Hit** (`orch_hit.pd`): a C major stab of detuned saws with a closing filter.
- **Timpani** (`timpani.pd`): drum partials with a pitch drop on the strike, felt mallet.
- **Sampler** (`sampler.pd`): plays audio files (WAV, Ogg, MP3, up to 30 s), 8 at a time
  in memory, 6 voices.
- **Dexed** (`dexed.pd`): the DX7 FM engine, loading .syx banks (starter bank:
  `addons/dexed/cartridges/biryani64.syx`).

The **Mixer** group gives each instrument a level and a delay send. The delay is
Mutable Instruments **Clouds** in looping-delay mode with an Airwindows **ToTape6** tape
stage inside its feedback, so every repeat is saturated, softened and wobbled again; a
second Clouds after it adds grains (`grains_mix`). The delay time follows `bpm` (1 beat by
default; Clouds holds about 1 s). The Master bus (`default_bus_layout.tres`, the Audio tab
at the bottom of the editor) runs Airwindows **Pressure5** (compressor) > **ADClip8**
(clipper) > Godot's Hard Limiter as an inaudible safety.

Every setting is in the Inspector on Instruments. To tweak live, run the game, pick
Instruments in the Remote tree (Scene dock) and change values; they are sent straight to
Pd. `demo_groove` plays a 124 BPM test loop. From scripts: `synth_note(note, vel)`,
`synth_note_off(note)`, `drum("kick"/"snare"/"hat", vel)`, `hit("noise"/"orch"/"timpani",
vel)`, `play_sample(stream, vel)`, `dexed_note(note, vel)`, `dexed_note_off(note)`,
`dexed_op_param(op, name, value)`, `dexed_global_param(name, value)`.

Plaits, Clouds and the Dexed engine are compiled into the godot-pd add-on as Pd objects
([plaits~], [clouds~], [dexed~]); Pressure5 and ADClip8 are in `addons/airwindows`.
Exporting needs the `pd/` folder copied next to the .exe (see addons/godot-pd/README.md).
The patches can be opened in Pure Data itself (the three built-in objects only exist inside
the game); `pd/tools/make_patches.py` regenerates them.

## Maps

- `scenes/main.tscn` - the original test stage (green ground, coloured blocks).
- `scenes/main_void.tscn` - the Void: the same shapes in glossy black on an endless
  glossy black floor in a black void (no edges, no falling off). Footsteps, landings
  and jumps send water ripples across the floor, which bend its reflections. Open the
  scene and press F6 to play it (or set it as the main scene in Project Settings).
  The floor reflects everything above it like dark water: a hidden mirror camera
  renders the scene at half resolution, and the floor shows it dimmed, softened and
  bent by the ripples, fading to black with distance.
  Floor, ripple and reflection settings are on VoidStage > EndlessFloor
  (`levels/void_floor.gd`); look settings (strength, blur, distortion) are on its
  shader, `levels/void_floor.gdshader`.

## Layout

- `scenes/main.tscn` - main scene: environment, light, stage, player, camera
- `scenes/player.tscn` - CharacterBody3D with a primitive humanoid body under `Visual`
- `scenes/camera_rig.tscn` - follow camera rig
- `levels/test_stage.tscn` - CSG blockout test stage
- `scripts/` - player, player_animator (procedural animation), player_fx (shadow, dust, rumble), camera, moving platform, kill zone
- `scripts/kits/`, `kits/` - the sound kit system and the kits
- `scripts/instruments.gd`, `pd/` - the instruments (Pure Data patches)
- `materials/` - flat-color materials, no textures

All tuning values are exported variables on the Player and CameraRig nodes.

Collision layers: 1 world (camera collides), 2 player, 3 hazards, 4 props the camera ignores
(floating platforms, moving platform, steps). Put new small props on layer 4.

Camera: tether follow, looks ahead to the landing spot when falling, tilts to keep
you framed, three zoom levels, and avoids walls by rising, then swinging round, then
pulling in only as a last resort. While the camera adjusts itself, a held stick keeps
its direction, so automatic camera moves don't steer you.

## Skins

The player's look is a swappable skin (`scripts/player_skin.gd`). Each skin is a
`.tres` in `skins/` with a body material (any shader), an optional particle scene
placed on chosen body parts (hands, head, feet, torso) and an optional glow light.
The Skin node on the Player loads every skin in `skins/` in file-name order and
starts with the first (`00_plain.tres`, the original colours). Press K to cycle.
The see-through-walls silhouette is added on top of any skin automatically.
`debug_stripes.*` and `debug_sparks.tscn` are a throwaway test skin.

Skins included: Plain, Debug Stripes, Fire (churning ember body, flame particles on
hands, head and feet, flickering orange light) and two Galaxy skins, each a looping
space video (`skins/videos/*.ogv`, Ogg Theora, muted) wrapped onto the body and locked
to it, with drifting star particles. Glow is on in the main scene's environment so
bright skins bloom.

Credits: the flame particle shader is based on "Fire Shader" by Yui Kinomoto (@arlez80),
MIT License. The galaxy videos come from the uploaded clips "The Sounds of Heaven"
(Rafael Brom) and "Nebula"; check their rights before publishing the game.
