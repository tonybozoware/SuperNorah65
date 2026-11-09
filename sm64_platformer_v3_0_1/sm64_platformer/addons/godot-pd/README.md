# Pure Data for Godot (godot-pd)

From https://github.com/evgenykochetkov/godot-pd (MIT, see LICENSE.txt; Pure Data and
libpd are BSD, ELSE is WTFPL, see 3RDPARTY.txt). Built for Windows x86_64, Godot 4.5+.

Two small fixes were made for Biryani64 before building:
- `libpd/cpp/PdTypes.hpp`: patch IDs are turned into text with std::to_string instead of
  a stringstream (the stringstream crashed in testing).
- `src/audio_stream_pd.h`: added `_stop()` and `_is_playing()`, which Godot requires.

- `libpd/cpp/PdBase.hpp`: messages may be up to 8192 items long (was 32), so a whole
  DX7 bank can be sent to [dexed~] in one message.

## Biryani64's built-in Pd objects

Three objects are compiled into this add-on (sources in `biryani_src.zip`, with the
changes to godot-pd itself in its `godot-pd-changes/` folder). They only exist inside the game:
Pure Data on its own will show them as "couldn't create".
- **[plaits~]** - the Mutable Instruments Plaits macro-oscillator (MIT, Emilie Gillet), all
  24 models. Messages: `note`, `model`, `harmonics`, `timbre`, `morph`, `decay`, `colour`,
  `triggered 0/1`, `trig`, `active 0/1`. Outlets: main, aux. Retuned for the game's sample
  rate (Plaits runs at 48 kHz).
- **[clouds~]** - Mutable Instruments Clouds (MIT, Emilie Gillet), stereo, run at its own
  32 kHz with resampling in and out, and with Airwindows ToTape6 (MIT) as a tape stage in
  its feedback path. Messages: `mode` (0 granular, 1 stretch, 2 looping delay, 3 spectral),
  `quality`, `position`, `size`, `density`, `texture`, `blend`, `spread`, `feedback`,
  `reverb`, `pitch`, `freeze`, `delay_ms`, `tape_input`, `tape_soften`, `tape_bump`,
  `tape_flutter`, `tape_output`, `tape_mix`.
- **[dexed~]** - the Dexed DX7 engine (msfa, Apache 2.0). Messages: `note n vel`, `alloff`,
  `choke n ms` (fade a note out), `release ms` (fade every note-off this fast),
  `cartridge <bytes>`, `program`, `volume`, `polyphony`, `op <1-6> <name> <value>`,
  `global <name> <value>`, `raw`, `bend`, `modwheel`.

Licenses: LICENSE-MIT-mutable-instruments.txt, LICENSE-MIT-airwindows.txt,
LICENSE-Apache-2.0-msfa.txt.

Known: Godot reports a few leaked objects when the game quits; harmless. Pd prints
"retrieve: failure to initialize retrieve name" when it starts; also harmless.

Patch paths are relative to the project folder while running from the editor. In an
exported game they are relative to the .exe: copy the `pd/` folder and
`addons/godot-pd/else_subset/` (as `else_subset/`) next to the exported .exe.
