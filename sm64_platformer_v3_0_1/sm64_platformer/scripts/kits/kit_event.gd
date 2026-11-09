class_name KitEvent
extends Resource
## One sound in a SoundKit: what triggers it, what plays, which notes, how loud,
## and how long. A kit can have several events for the same trigger (they layer).
## An event with a "Only From" filter beats the kit's "Any" events for that trigger,
## so e.g. a triple-jump landing can replace the normal landing sound.

## ROLL_STEP: 16th notes while rolling (see Visual's roll_step).
enum Event { FOOTSTEP, JUMP, LAND, DIVE, GROUND_POUND, POUND_LAND, WALL_KICK,
		LEDGE_GRAB, SKID, WALL_HIT, CEILING_HIT, ROLL_STEP }
## All played by the Instruments node (Pure Data). Sample plays an audio file.
enum Instrument { NOISE, ORCHESTRA_HIT, TIMPANI, SAMPLE, ANALOG_SYNTH, DEXED,
		KICK, SNARE, HAT }
enum NoteMode { CHORD, RANDOM, SEQUENCE }
enum VelocityFrom { FIXED, STRENGTH, IMPACT }

@export var event := Event.FOOTSTEP
## Jump: the kind of jump. Land: the state you landed from. Other events ignore it.
## (Numbers match Player.State.)
@export_enum("Any:-1", "Jump:9", "Double Jump:10", "Triple Jump:11", "Long Jump:12",
		"Backflip:13", "Side Flip:14", "Wall Kick:15", "Fall:16", "Wall Bonk:17",
		"Ground Pound:18", "Dive:20", "Rollout:23") var only_from := -1

@export_group("Sound")
@export var instrument := Instrument.NOISE
## For the Sample instrument: an audio file (WAV, Ogg or MP3, up to 30 s).
@export var stream: AudioStream
## Extra level for Noise, Orchestra Hit, Timpani and Sample, in dB.
@export var volume_db := 0.0

@export_group("Notes")
## MIDI notes (60 = C4) for the analog synth and Dexed.
@export var notes := PackedInt32Array([60])
## Chord: all notes at once. Random: one at random. Sequence: the next one each time.
@export var note_mode := NoteMode.CHORD
## Seconds before the note-off (synths).
@export var length_seconds := 0.5
## Synths: keep the notes on until the next landing (or ledge grab) instead.
## A new held chord also cuts the previous one.
@export var hold_until_land := false
## Synths: fade these notes out when a jump chord plays (for landings in a jump
## chain, so the landing chord doesn't clash with the next jump's chord).
@export var fade_on_next_jump := false
## How fast that fade is, in ms.
@export_range(5.0, 1000.0) var fade_ms := 60.0

@export_group("Velocity")
## Fixed: always velocity_max. Strength: footstep strength (walk to full run).
## Impact: how hard you landed or hit (full at full_impact).
@export var velocity_from := VelocityFrom.FIXED
@export_range(0.0, 127.0) var velocity_min := 100.0
@export_range(0.0, 127.0) var velocity_max := 100.0
## u/f of impact for velocity_max (landings: downward speed, walls: speed into it).
@export var full_impact := 75.0
