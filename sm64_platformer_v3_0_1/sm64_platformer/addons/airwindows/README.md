# Airwindows bus effects (Biryani64)

Two Airwindows plugins by Chris Johnson (MIT, see LICENSE-MIT-airwindows.txt) as Godot
audio bus effects. Add them to a bus in the Audio tab like any built-in effect.

- **AirwindowsPressure5** - compressor. `pressure` (amount, 0 = off), `speed` (release),
  `mewiness` (how the ratio engages), `pawclaw` (attack character), `output` (0.5 = unity),
  `mix`.
- **AirwindowsADClip8** - clipper/loudenator. `boost` (0-18 dB in), `ceiling`, `mode`
  (Normal, Atten, Clips, Afterburner, Explode, Nuke, Apocalypse, Apotheosis).

They have no look-ahead, so the Master bus keeps Godot's Hard Limiter after them as a
safety. Windows and Linux x86_64 builds; sources in `src.zip` (build with SCons + godot-cpp,
see its `SConstruct`). The VST interface the plugins expect is replaced by a small
stand-in (`aw/audioeffectx.h`).
