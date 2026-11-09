class_name Instruments
extends Node
## All of Biryani64's instruments, running together in one Pure Data instance
## (patches in res://pd/, see pd/instruments.pd for the mixer):
## - Analog synth: 2 saw/pulse oscillators + sub + a Plaits oscillator, drive,
##   ladder filter, envelopes
## - Drums: kick, snare, hat
## - Noise, Orchestra Hit, Timpani: one-shot instruments (fixed pitch)
## - Sampler: plays audio files (WAV, Ogg, MP3)
## - Dexed: DX7 FM synth
## Each instrument has a level and a delay send in the Mixer group. The delay is
## Mutable Instruments Clouds as a tape echo (Airwindows tape in its feedback),
## followed by a second Clouds adding grains.
##
## Every setting is in the Inspector. While the game runs, select Instruments in
## the Remote scene tree and change a value: it is sent straight to Pd.
##
## From any script:
##   instruments.synth_note(60, 100)   instruments.synth_note_off(60)
##   instruments.drum("kick", 120)     ("kick", "snare" or "hat")
##   instruments.hit("timpani", 110)   ("noise", "orch" or "timpani")
##   instruments.dexed_note(72, 90)    instruments.dexed_note_off(72)
##   instruments.play_sample(preload("res://my_sound.wav"), 100)
##   instruments.dexed_op_param(1, "output_level", 90) / dexed_global_param("algorithm", 5)

const INSTRUMENTS := ["analog", "drums", "noise", "orch", "timpani", "sampler", "dexed"]
const PATCHES := ["pd/instruments.pd", "pd/analog_synth.pd", "pd/drums.pd", "pd/noise.pd",
		"pd/orch_hit.pd", "pd/timpani.pd", "pd/sampler.pd", "pd/dexed.pd"]

@export var demo_groove := false     ## a 124 BPM test loop to tweak against (off by default)
@export var bpm := 124.0             ## follows Player > Visual > run_bpm when it can find the player
## Overall level of everything the instruments play, in dB.
@export_range(-40.0, 6.0) var volume_db := -8.0: set = _set_vol

@export_group("Mixer")
@export_range(-60.0, 12.0) var analog_level_db := 0.0
@export_range(0.0, 1.0) var analog_send := 0.3
@export_range(-60.0, 12.0) var drums_level_db := 0.0
@export_range(0.0, 1.0) var drums_send := 0.3
@export_range(-60.0, 12.0) var noise_level_db := 0.0
@export_range(0.0, 1.0) var noise_send := 0.3
@export_range(-60.0, 12.0) var orch_level_db := 0.0
@export_range(0.0, 1.0) var orch_send := 0.3
@export_range(-60.0, 12.0) var timpani_level_db := 0.0
@export_range(0.0, 1.0) var timpani_send := 0.3
@export_range(-60.0, 12.0) var sampler_level_db := 0.0
@export_range(0.0, 1.0) var sampler_send := 0.3
@export_range(-60.0, 12.0) var dexed_level_db := 0.0
@export_range(0.0, 1.0) var dexed_send := 0.3

@export_group("Delay (Clouds tape echo)")
## Level of the delay coming back into the mix.
@export_range(0.0, 2.0) var delay_return := 1.0
## Delay time in beats of `bpm` (1 = a quarter note). Clouds' memory holds about 1 s.
@export_range(0.125, 2.0, 0.125) var delay_beats := 1.0
@export_range(0.0, 1.0) var delay_feedback := 0.45   ## how many repeats
## Below 0.5 each repeat gets darker, above 0.5 thinner.
@export_range(0.0, 1.0) var delay_texture := 0.42
@export_range(0.0, 1.0) var delay_smear := 0.15      ## Clouds diffusion (density)
@export_range(0.0, 1.0) var delay_reverb := 0.15
@export_range(0.0, 1.0) var delay_spread := 0.5      ## stereo width
## 0: 16-bit stereo, 1: 16-bit mono, 2: 8-bit stereo, 3: 8-bit mono (grittier, longer).
@export_range(0, 3) var delay_quality := 0
@export_range(0.0, 1.0) var tape_drive := 0.55       ## tape input level (saturation)
@export_range(0.0, 1.0) var tape_soften := 0.6
@export_range(0.0, 1.0) var tape_head_bump := 0.5
@export_range(0.0, 1.0) var tape_flutter := 0.35
@export_range(0.0, 1.0) var tape_output := 0.5

@export_group("Grains (Clouds)")
## How much of the echo is replaced by grains (0 = none).
@export_range(0.0, 1.0) var grains_mix := 0.25
@export_range(0.0, 1.0) var grains_position := 0.3
@export_range(0.0, 1.0) var grains_size := 0.35
@export_range(0.0, 1.0) var grains_density := 0.6
@export_range(0.0, 1.0) var grains_texture := 0.6
@export_range(-24.0, 24.0) var grains_pitch := 0.0   ## semitones
@export_range(0.0, 1.0) var grains_spread := 0.7
@export_range(0.0, 1.0) var grains_reverb := 0.1

@export_group("Analog Synth")
@export_range(0.0, 1.0) var osc1_level := 1.0
@export_range(0.0, 1.0) var osc2_level := 0.8
@export_range(0.0, 1.0) var sub_level := 0.4
@export_range(0.0, 50.0) var detune_cents := 7.0
## Osc 1 and 2 waveform: 0 = saw, 1 = pulse, in between = both mixed.
@export_range(0.0, 1.0) var pulse_mix := 0.0
## Pulse wave duty cycle: 0.5 = square, smaller = thinner and more nasal.
@export_range(0.02, 0.98) var pulse_width := 0.5
## Saturation between the oscillators and the filter: 0 = clean, 1 = heavy.
@export_range(0.0, 1.0) var drive := 0.0
@export_range(20.0, 12000.0, 1.0, "exp") var cutoff := 700.0
@export_range(0.0, 1.0) var resonance := 0.35
@export_range(0.0, 8000.0) var filter_env_amount := 2500.0
@export_range(0.0, 1.0) var filter_velocity := 0.5
@export_range(1.0, 3000.0, 1.0, "exp") var filter_attack_ms := 5.0
@export_range(1.0, 3000.0, 1.0, "exp") var filter_decay_ms := 350.0
@export_range(0.0, 1.0) var filter_sustain := 0.25
@export_range(1.0, 5000.0, 1.0, "exp") var filter_release_ms := 300.0
@export_range(1.0, 3000.0, 1.0, "exp") var attack_ms := 5.0
@export_range(1.0, 3000.0, 1.0, "exp") var decay_ms := 300.0
@export_range(0.0, 1.0) var sustain := 0.7
@export_range(1.0, 5000.0, 1.0, "exp") var release_ms := 300.0
@export_range(0.0, 1.5) var synth_volume := 0.6

@export_subgroup("Plaits oscillator")
## Level of the Plaits oscillator in each voice (0 = off, saves CPU).
@export_range(0.0, 1.0) var plaits_level := 0.0
@export_enum("VA + VCF", "Phase Distortion", "6-op FM A", "6-op FM B", "6-op FM C",
		"Wave Terrain", "String Machine", "Chiptune", "Virtual Analog", "Waveshaping",
		"FM", "Grain", "Additive", "Wavetable", "Chords", "Speech", "Swarm", "Noise",
		"Particle", "String", "Modal", "Bass Drum", "Snare Drum", "Hi-Hat") var plaits_model := 8
@export_range(0.0, 1.0) var plaits_harmonics := 0.5
@export_range(0.0, 1.0) var plaits_timbre := 0.5
@export_range(0.0, 1.0) var plaits_morph := 0.5
## On: each note also strikes Plaits (for String, Modal, the drums...), using its own decay.
@export var plaits_triggered := false
@export_range(0.0, 1.0) var plaits_decay := 0.5
@export_range(0.0, 1.0) var plaits_colour := 0.5

@export_group("Drums")
@export_range(40.0, 400.0) var kick_pitch := 150.0
@export_range(20.0, 120.0) var kick_end := 48.0
@export_range(5.0, 300.0) var kick_pitch_decay_ms := 60.0
@export_range(30.0, 2000.0, 1.0, "exp") var kick_decay_ms := 380.0
@export_range(1.0, 8.0) var kick_drive := 1.5
@export_range(0.0, 1.5) var kick_level := 1.0
@export_range(80.0, 400.0) var snare_tone := 190.0
@export_range(0.0, 1.0) var snare_noise := 0.6
@export_range(200.0, 6000.0, 1.0, "exp") var snare_snappy_tone := 900.0
@export_range(30.0, 1000.0, 1.0, "exp") var snare_decay_ms := 180.0
@export_range(0.0, 1.5) var snare_level := 0.8
@export_range(1000.0, 16000.0, 1.0, "exp") var hat_tone := 7000.0
@export_range(10.0, 800.0, 1.0, "exp") var hat_decay_ms := 60.0
@export_range(0.0, 1.5) var hat_level := 0.5
@export_range(0.0, 1.5) var drums_volume := 0.7

@export_group("Noise")
@export_range(100.0, 12000.0, 1.0, "exp") var noise_tone := 2500.0   ## band-pass centre, Hz
@export_range(0.5, 20.0) var noise_q := 2.0
@export_range(0.0, 1.0) var noise_sweep := 0.5     ## filter starts higher and falls to the tone
@export_range(0.0, 1.0) var noise_band := 0.7      ## 0 = raw white noise, 1 = only the band
@export_range(0.5, 200.0, 0.1, "exp") var noise_attack_ms := 1.0
@export_range(5.0, 2000.0, 1.0, "exp") var noise_decay_ms := 60.0
@export_range(0.0, 1.5) var noise_level := 0.45

@export_group("Orchestra Hit")
@export_range(-24.0, 24.0, 1.0) var orch_tune := 0.0   ## semitones from C3
@export_range(0.0, 50.0) var orch_detune_cents := 12.0
@export_range(50.0, 3000.0, 1.0, "exp") var orch_decay_ms := 500.0
@export_range(300.0, 12000.0, 1.0, "exp") var orch_brightness := 5000.0
@export_range(0.0, 1.0) var orch_noise := 0.4
@export_range(0.0, 1.5) var orch_level := 0.55

@export_group("Timpani")
@export_range(40.0, 300.0, 0.1, "exp") var timpani_tune_hz := 98.0   ## 98 = G2
@export_range(100.0, 5000.0, 1.0, "exp") var timpani_decay_ms := 1600.0
@export_range(0.0, 0.5) var timpani_pitch_drop := 0.06
@export_range(0.0, 1.5) var timpani_mallet := 0.6
@export_range(100.0, 4000.0, 1.0, "exp") var timpani_mallet_tone := 700.0
@export_range(0.0, 1.5) var timpani_level := 0.6

@export_group("Sampler")
@export_range(0.0, 1.5) var sampler_level := 1.0

@export_group("Dexed (DX7)")
## A DX7 bank (.syx). Any 32-voice bank or single voice works, e.g. Dexed's.
@export_file("*.syx") var dexed_cartridge := "res://addons/dexed/cartridges/biryani64.syx"
@export var dexed_program := 0
@export_range(0.0, 2.0) var dexed_volume := 0.5
@export_range(1, 32) var dexed_polyphony := 16
## Above 0: every Dexed note-off also fades out over this many ms, a faster release
## than the patch's own. 0 = the patch's release only.
@export_range(0.0, 2000.0, 1.0) var dexed_release_ms := 0.0

## Inspector setting -> how it reaches Pd: [receiver] sends a float,
## [receiver, method] sends a message, "db" in third place converts dB to gain.
const PARAMS := {
	"osc1_level": ["synth_osc1_level"], "osc2_level": ["synth_osc2_level"],
	"sub_level": ["synth_sub_level"], "detune_cents": ["synth_detune"],
	"pulse_mix": ["synth_pulse_mix"], "pulse_width": ["synth_pulse_width"],
	"drive": ["synth_drive"], "cutoff": ["synth_cutoff"], "resonance": ["synth_resonance"],
	"filter_env_amount": ["synth_filter_env_amount"], "filter_velocity": ["synth_filter_velocity"],
	"filter_attack_ms": ["synth_filter_attack"], "filter_decay_ms": ["synth_filter_decay"],
	"filter_sustain": ["synth_filter_sustain"], "filter_release_ms": ["synth_filter_release"],
	"attack_ms": ["synth_attack"], "decay_ms": ["synth_decay"], "sustain": ["synth_sustain"],
	"release_ms": ["synth_release"], "synth_volume": ["synth_volume"],
	"plaits_level": ["synth_plaits_level"], "plaits_model": ["synth_plaits_model"],
	"plaits_harmonics": ["synth_plaits_harmonics"], "plaits_timbre": ["synth_plaits_timbre"],
	"plaits_morph": ["synth_plaits_morph"], "plaits_triggered": ["synth_plaits_triggered"],
	"plaits_decay": ["synth_plaits_decay"], "plaits_colour": ["synth_plaits_colour"],
	"kick_pitch": ["kick_pitch"], "kick_end": ["kick_end"],
	"kick_pitch_decay_ms": ["kick_pitch_decay"], "kick_decay_ms": ["kick_decay"],
	"kick_drive": ["kick_drive"], "kick_level": ["kick_level"], "snare_tone": ["snare_tone"],
	"snare_noise": ["snare_noise"], "snare_snappy_tone": ["snare_snappy_tone"],
	"snare_decay_ms": ["snare_decay"], "snare_level": ["snare_level"], "hat_tone": ["hat_tone"],
	"hat_decay_ms": ["hat_decay"], "hat_level": ["hat_level"], "drums_volume": ["drums_volume"],
	"noise_tone": ["noise_tone"], "noise_q": ["noise_q"], "noise_sweep": ["noise_sweep"],
	"noise_band": ["noise_band"], "noise_attack_ms": ["noise_attack"],
	"noise_decay_ms": ["noise_decay"], "noise_level": ["noise_level"],
	"orch_tune": ["orch_tune"], "orch_detune_cents": ["orch_detune"],
	"orch_decay_ms": ["orch_decay"], "orch_brightness": ["orch_bright"],
	"orch_noise": ["orch_noise"], "orch_level": ["orch_level"],
	"timpani_tune_hz": ["timpani_tune"], "timpani_decay_ms": ["timpani_decay"],
	"timpani_pitch_drop": ["timpani_pitch_drop"], "timpani_mallet": ["timpani_mallet"],
	"timpani_mallet_tone": ["timpani_mallet_tone"], "timpani_level": ["timpani_level"],
	"sampler_level": ["sampler_level"],
	"delay_return": ["delay_return"], "delay_feedback": ["delay", "feedback"],
	"delay_texture": ["delay", "texture"], "delay_smear": ["delay", "density"],
	"delay_reverb": ["delay", "reverb"], "delay_spread": ["delay", "spread"],
	"delay_quality": ["delay", "quality"], "tape_drive": ["delay", "tape_input"],
	"tape_soften": ["delay", "tape_soften"], "tape_head_bump": ["delay", "tape_bump"],
	"tape_flutter": ["delay", "tape_flutter"], "tape_output": ["delay", "tape_output"],
	"grains_mix": ["grains", "blend"], "grains_position": ["grains", "position"],
	"grains_size": ["grains", "size"], "grains_density": ["grains", "density"],
	"grains_texture": ["grains", "texture"], "grains_pitch": ["grains", "pitch"],
	"grains_spread": ["grains", "spread"], "grains_reverb": ["grains", "reverb"],
	"dexed_program": ["dexed", "program"], "dexed_volume": ["dexed", "volume"],
	"dexed_polyphony": ["dexed", "polyphony"], "dexed_release_ms": ["dexed", "release"],
}

var pd                    ## the AudioStreamPlaybackPD running every patch
var _player: AudioStreamPlayer
var _sent := {}           # setting -> value last sent to Pd
var _beat_time := 0.0
var _step := 0
var _samples := {}        # AudioStream -> [slot, frames, ms]
var _slot_order: Array = []   # streams in slots, played longest ago first
var _bad_samples := {}    # streams that can't be used (warned once)
const SAMPLE_SLOTS := 8


func _ready() -> void:
	var scene := get_tree().current_scene if get_tree().current_scene else get_tree().root
	var visual := scene.find_child("Visual", true, false)
	if visual and "run_bpm" in visual:
		bpm = visual.get("run_bpm")
	if not ClassDB.class_exists("AudioStreamPD"):
		push_warning("Instruments: the Pure Data add-on (addons/godot-pd) isn't loaded")
		return
	_player = AudioStreamPlayer.new()
	_player.name = "Pd"
	_player.stream = ClassDB.instantiate("AudioStreamPD")
	_player.volume_db = volume_db
	add_child(_player)
	_player.play()
	pd = _player.get_stream_playback()
	for patch in PATCHES:
		if pd.open_patch(patch) < 0:
			push_error("Instruments: couldn't open " + patch)
	_load_cartridge()
	flush()


func _process(delta: float) -> void:
	flush()
	if not demo_groove:
		return
	_beat_time += delta
	var eighth := 30.0 / bpm
	while _beat_time >= eighth:
		_beat_time -= eighth
		_play_step(_step)
		_step = (_step + 1) % 32


## Send every setting that changed since last time (runs each frame and before
## every note, so Inspector edits, kit patches and live routes all reach Pd).
func flush() -> void:
	if not pd:
		return
	for prop: String in PARAMS:
		var v = get(prop)
		if _sent.get(prop) != v:
			_sent[prop] = v
			_send(PARAMS[prop], v)
	for inst: String in INSTRUMENTS:
		var lvl = get(inst + "_level_db")
		if _sent.get(inst + "_level_db") != lvl:
			_sent[inst + "_level_db"] = lvl
			pd.send_float("mix_" + inst + "_level", 0.0 if lvl <= -60.0 else db_to_linear(lvl))
		var snd = get(inst + "_send")
		if _sent.get(inst + "_send") != snd:
			_sent[inst + "_send"] = snd
			pd.send_float("mix_" + inst + "_send", snd)
	var delay_ms := 60000.0 / maxf(bpm, 1.0) * delay_beats
	if _sent.get("delay_ms") != delay_ms:
		_sent["delay_ms"] = delay_ms
		pd.send_message("delay", "delay_ms", [delay_ms])
	if _sent.get("dexed_cartridge") != dexed_cartridge:
		_load_cartridge()


func _send(route: Array, v) -> void:
	var f := float(v) if not v is bool else (1.0 if v else 0.0)
	if route.size() == 1:
		pd.send_float(route[0], f)
	else:
		pd.send_message(route[0], route[1], [f])


func _load_cartridge() -> void:
	_sent["dexed_cartridge"] = dexed_cartridge
	if not pd or dexed_cartridge == "":
		return
	var f := FileAccess.open(dexed_cartridge, FileAccess.READ)
	if not f:
		push_error("Instruments: can't open the Dexed cartridge " + dexed_cartridge)
		return
	var bytes := f.get_buffer(f.get_length())
	var list := []
	list.resize(bytes.size())
	for i in bytes.size():
		list[i] = bytes[i]
	pd.send_message("dexed", "cartridge", list)
	pd.send_message("dexed", "program", [dexed_program])


# ------------------------------------------------------------------ playing
func synth_note(note: int, velocity := 100) -> void:
	if pd:
		flush()
		pd.send_list("synth_note", [note, velocity])

func synth_note_off(note: int) -> void:
	if pd:
		pd.send_list("synth_note", [note, 0])

func synth_all_off() -> void:
	if pd:
		pd.send_bang("synth_all_off")

func drum(which: String, velocity := 110.0) -> void:
	if pd:
		flush()
		pd.send_float("drum_" + which, velocity)

## One-shot instruments: "noise", "orch" or "timpani". Velocity 0-127 (more is louder still).
func hit(which: String, velocity := 110.0) -> void:
	if pd:
		flush()
		pd.send_float(which + "_hit", velocity)

func dexed_note(note: int, velocity := 100) -> void:
	if pd:
		flush()
		pd.send_message("dexed", "note", [note, velocity])

func dexed_note_off(note: int) -> void:
	if pd:
		pd.send_message("dexed", "note", [note, 0])

## Fade a Dexed note out over `ms` (even one already releasing).
func dexed_choke(note: int, ms := 60.0) -> void:
	if pd:
		pd.send_message("dexed", "choke", [note, ms])

func dexed_all_off() -> void:
	if pd:
		pd.send_message("dexed", "alloff", [])

## Deep DX7 edits. op 1..6; names: rate1..4, level1..4, break_point, left_depth,
## right_depth, left_curve, right_curve, rate_scaling, amp_mod_sens, velocity_sens,
## output_level, mode, coarse, fine, detune, enabled.
func dexed_op_param(op: int, name: String, value: int) -> void:
	if pd:
		pd.send_message("dexed", "op", [op, name, value])

## algorithm (1..32), feedback, osc_sync, lfo_speed, lfo_delay, lfo_pitch_depth,
## lfo_amp_depth, lfo_sync, lfo_wave, lfo_pitch_sens, transpose, pitch_rate1..4, pitch_level1..4
func dexed_global_param(name: String, value: int) -> void:
	if pd:
		pd.send_message("dexed", "global", [name, value])

## Play an audio file (WAV, Ogg, MP3; up to 30 s) through the sampler, mixed down to mono.
func play_sample(stream: AudioStream, velocity := 100.0) -> void:
	if not pd:
		return
	var info = load_sample(stream)
	if info:
		flush()
		pd.send_list("sampler_play", [info[1], info[2], velocity, info[0]])

## Copy a sound into one of the sampler's slots (done automatically on first play).
## Returns [slot, frames, ms], or null if the sound can't be used.
func load_sample(stream: AudioStream):
	if not pd or not stream or _bad_samples.has(stream):
		return null
	if _samples.has(stream):
		_slot_order.erase(stream)
		_slot_order.append(stream)
		return _samples[stream]
	var length := stream.get_length() if stream else 0.0
	if length <= 0.0 or length > 30.0:
		push_warning("Instruments: the sampler needs a sound between 0 and 30 s long: " + str(stream.resource_path))
		_bad_samples[stream] = true
		return null
	# Decode with Godot itself, so any format works (WAV, compressed WAV, Ogg, MP3).
	var rate := AudioServer.get_mix_rate()
	var frames := int(ceil(length * rate))
	var playback := stream.instantiate_playback()
	playback.start(0.0)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var done := 0
	while done < frames:
		var chunk: PackedVector2Array = playback.mix_audio(1.0, mini(4096, frames - done))
		if chunk.is_empty():
			break
		for v in chunk:
			samples[done] = (v.x + v.y) * 0.5
			done += 1
	playback.stop()
	frames = done
	if frames == 0:
		_bad_samples[stream] = true
		return null
	samples.resize(frames)
	var slot := _samples.size()
	if slot >= SAMPLE_SLOTS:   # all full: reuse the slot of the sound played longest ago
		var old = _slot_order.pop_front()
		slot = _samples[old][0]
		_samples.erase(old)
	var name := "smp%d" % slot
	pd.resize_array(name, frames)
	var arr: Array[float] = []
	arr.assign(samples)
	pd.write_array(name, arr, frames, 0)
	var info := [slot, frames, frames * 1000.0 / rate]
	_samples[stream] = info
	_slot_order.append(stream)
	return info

## Any analog synth setting by its patch name without the "synth_" prefix.
func set_synth(param: String, value: float) -> void:
	if pd:
		pd.send_float("synth_" + param, value)

## Any drum setting by its patch name, e.g. "kick_decay".
func set_drum(param: String, value: float) -> void:
	if pd:
		pd.send_float(param, value)


# ------------------------------------------------------------------ demo groove
const BASS := [45, 45, 57, 45, 48, 45, 52, 43]   # one note per beat, A minor
const CHORDS := [[69, 72, 76], [67, 71, 74]]     # Am, G (two bars each)

func _play_step(s: int) -> void:
	var beat := floori(s / 2.0)
	if s % 2 == 0:
		drum("kick" if beat % 2 == 0 else "snare", 120 if beat % 2 == 0 else 105)
		var n: int = BASS[beat % BASS.size()]
		synth_note(n, 100)
		get_tree().create_timer(30.0 / bpm * 0.8).timeout.connect(synth_note_off.bind(n))
	drum("hat", 70 if s % 2 == 1 else 45)
	if s % 16 == 0:
		var chord: Array = CHORDS[floori(s / 16.0) % CHORDS.size()]
		for n in chord:
			dexed_note(n, 85)
		get_tree().create_timer(60.0 / bpm * 3.5).timeout.connect(func():
			for n in chord:
				dexed_note_off(n))


func _set_vol(v: float) -> void:
	volume_db = v
	if _player:
		_player.volume_db = v
