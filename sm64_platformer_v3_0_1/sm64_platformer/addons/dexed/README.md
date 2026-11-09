# Dexed (DX7 FM synth) for Godot

`DexedSynth` is an AudioStream that plays DX7 sounds. It uses the synth engine from
[Dexed](https://github.com/asb2m10/dexed) (the `msfa` engine, Apache License 2.0, see
LICENSE-Apache-2.0.txt). Dexed's plugin/UI code (GPL) is not included.

Built for Windows x86_64 against Godot 4.5+ (works in 4.6).

## Use
The Music node (`scripts/music.gd`) sets one up for you. By hand:

    var synth = DexedSynth.new()
    $AudioStreamPlayer.stream = synth
    $AudioStreamPlayer.play()
    synth.load_cartridge("res://addons/dexed/cartridges/biryani64.syx")
    synth.set_program(0)
    synth.note_on(60, 100)
    synth.note_off(60)

## Calls
- `note_on(note, velocity)`, `note_off(note)`, `all_notes_off()`
- `load_cartridge(path)` - any DX7 32-voice bank or single-voice .syx (e.g. Dexed's banks)
- `get_program_names()`, `set_program(i)`, `get_voice_name()`, `set_voice_name(name)`
- `set_op_param(op, name, value)` / `get_op_param(op, name)`, op = 1..6, name one of:
  rate1..rate4, level1..level4, break_point, left_depth, right_depth, left_curve,
  right_curve, rate_scaling, amp_mod_sens, velocity_sens, output_level, mode, coarse,
  fine, detune, enabled. Ranges are the DX7's (0-99 for most).
- `set_global_param(name, value)`: algorithm (1-32), feedback (0-7), osc_sync,
  lfo_speed, lfo_delay, lfo_pitch_depth, lfo_amp_depth, lfo_sync, lfo_wave (0-5),
  lfo_pitch_sens, transpose (24 = none), pitch_rate1..4, pitch_level1..4
- `get_voice_data()` / `set_voice_data(bytes)` (156 bytes), `export_voice_sysex()`
  (save with FileAccess to a .syx file Dexed can open)
- Properties: `volume`, `polyphony` (1-32), `cartridge_path`
- `set_pitch_bend(-1..1)`, `set_mod_wheel(0..127)`

Changes apply to playing notes immediately. Standard tuning only.

Give each AudioStreamPlayer its own DexedSynth: one synth shared by two players is
advanced by both, so its notes would run at double speed.

## Starter bank
`cartridges/biryani64.syx`: SOFT EP, FM BASS, GLASS BELL, SINE, then INIT voices.
Original voices made for this project (`src/make_bank.py`).

## Rebuilding
`src/` has the source and SConstruct (needs godot-cpp 4.5 and SCons). Built with
llvm-mingw for Windows.
