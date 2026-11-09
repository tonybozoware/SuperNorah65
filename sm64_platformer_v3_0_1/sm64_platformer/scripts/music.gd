class_name Music
extends Node
## The game's synths: an analog-style subtractive synth and a drum voice (Pure Data
## patches in res://pd/) plus a DX7 FM synth (the Dexed engine, addons/dexed).
##
## Every sound setting below is in the Inspector. While the game runs, select
## Music in the Remote scene tree and change a value: it is sent straight to the
## synth, so you hear the change immediately.
##
## From any script:
##   music.synth_note(60, 100)      music.synth_note_off(60)
##   music.drum("kick", 120)        ("kick", "snare" or "hat")
##   music.dexed_note(72, 90)       music.dexed_note_off(72)
##   music.set_synth("cutoff", 1200) / music.set_drum("kick_decay", 500)

@export var demo_groove := false     ## a 124 BPM test loop to tweak against (off by default)
@export var bpm := 124.0             ## follows Player > Visual > run_bpm when it can find the player
## Overall level of everything Music plays (all three synths), in dB.
@export_range(-40.0, 6.0) var music_volume_db := -8.0: set = _set_mvol

@export_group("Analog Synth")
@export_range(0.0, 1.0) var osc1_level := 1.0: set = _set_osc1
@export_range(0.0, 1.0) var osc2_level := 0.8: set = _set_osc2
@export_range(0.0, 1.0) var sub_level := 0.4: set = _set_sub
@export_range(0.0, 50.0) var detune_cents := 7.0: set = _set_detune
## Osc 1 and 2 waveform: 0 = saw, 1 = pulse, in between = both mixed.
@export_range(0.0, 1.0) var pulse_mix := 0.0: set = _set_pmix
## Pulse wave duty cycle: 0.5 = square, smaller = thinner and more nasal.
@export_range(0.02, 0.98) var pulse_width := 0.5: set = _set_pw
## Saturation between the oscillators and the filter: 0 = clean, 1 = heavy.
@export_range(0.0, 1.0) var drive := 0.0: set = _set_drive
@export_range(20.0, 12000.0, 1.0, "exp") var cutoff := 700.0: set = _set_cutoff
@export_range(0.0, 1.0) var resonance := 0.35: set = _set_res
@export_range(0.0, 8000.0) var filter_env_amount := 2500.0: set = _set_famt
@export_range(0.0, 1.0) var filter_velocity := 0.5: set = _set_fvel
@export_range(1.0, 3000.0, 1.0, "exp") var filter_attack_ms := 5.0: set = _set_fatt
@export_range(1.0, 3000.0, 1.0, "exp") var filter_decay_ms := 350.0: set = _set_fdec
@export_range(0.0, 1.0) var filter_sustain := 0.25: set = _set_fsus
@export_range(1.0, 5000.0, 1.0, "exp") var filter_release_ms := 300.0: set = _set_frel
@export_range(1.0, 3000.0, 1.0, "exp") var attack_ms := 5.0: set = _set_att
@export_range(1.0, 3000.0, 1.0, "exp") var decay_ms := 300.0: set = _set_dec
@export_range(0.0, 1.0) var sustain := 0.7: set = _set_sus
@export_range(1.0, 5000.0, 1.0, "exp") var release_ms := 300.0: set = _set_rel
@export_range(0.0, 1.5) var synth_volume := 0.6: set = _set_svol

@export_group("Drums")
@export_range(40.0, 400.0) var kick_pitch := 150.0: set = _set_kp
@export_range(20.0, 120.0) var kick_end := 48.0: set = _set_ke
@export_range(5.0, 300.0) var kick_pitch_decay_ms := 60.0: set = _set_kpd
@export_range(30.0, 2000.0, 1.0, "exp") var kick_decay_ms := 380.0: set = _set_kd
@export_range(1.0, 8.0) var kick_drive := 1.5: set = _set_kdr
@export_range(0.0, 1.5) var kick_level := 1.0: set = _set_kl
@export_range(80.0, 400.0) var snare_tone := 190.0: set = _set_st
@export_range(0.0, 1.0) var snare_noise := 0.6: set = _set_sn
@export_range(200.0, 6000.0, 1.0, "exp") var snare_snappy_tone := 900.0: set = _set_ssn
@export_range(30.0, 1000.0, 1.0, "exp") var snare_decay_ms := 180.0: set = _set_sd
@export_range(0.0, 1.5) var snare_level := 0.8: set = _set_sl
@export_range(1000.0, 16000.0, 1.0, "exp") var hat_tone := 7000.0: set = _set_ht
@export_range(10.0, 800.0, 1.0, "exp") var hat_decay_ms := 60.0: set = _set_hd
@export_range(0.0, 1.5) var hat_level := 0.5: set = _set_hl
@export_range(0.0, 1.5) var drums_volume := 0.7: set = _set_dvol

@export_group("Dexed (DX7)")
## A DX7 bank (.syx). Any 32-voice bank or single voice works, e.g. Dexed's.
@export_file("*.syx") var dexed_cartridge := "res://addons/dexed/cartridges/biryani64.syx": set = _set_cartridge
@export var dexed_program := 0: set = _set_program
@export_range(0.0, 2.0) var dexed_volume := 0.5: set = _set_dvolume
@export_range(1, 32) var dexed_polyphony := 16: set = _set_polyphony

var dexed      ## the DexedSynth stream: call set_op_param / set_global_param on it for deep edits
var _pd_synth  ## AudioStreamPlaybackPD running analog_synth.pd
var _pd_drums  ## AudioStreamPlaybackPD running drums.pd
var _ready_done := false
var _beat_time := 0.0
var _step := 0


func _ready() -> void:
	var visual := get_tree().current_scene.find_child("Visual", true, false)
	if visual and "run_bpm" in visual:
		bpm = visual.get("run_bpm")
	if ClassDB.class_exists("AudioStreamPD"):
		_pd_synth = _start_pd("pd/analog_synth.pd")
		_pd_drums = _start_pd("pd/drums.pd")
	else:
		push_warning("Music: the Pure Data add-on (addons/godot-pd) isn't loaded")
	if ClassDB.class_exists("DexedSynth"):
		dexed = ClassDB.instantiate("DexedSynth")   # cartridge, program, volume etc. arrive via _send_all()
		var p := AudioStreamPlayer.new()
		p.name = "Dexed"
		p.stream = dexed
		p.volume_db = music_volume_db
		add_child(p)
		p.play()
	else:
		push_warning("Music: the Dexed add-on (addons/dexed) isn't loaded")
	_ready_done = true
	_send_all()


func _start_pd(patch: String):
	var p := AudioStreamPlayer.new()
	p.name = patch.get_file().get_basename()
	p.stream = ClassDB.instantiate("AudioStreamPD")
	p.volume_db = music_volume_db
	add_child(p)
	p.play()
	var pb = p.get_stream_playback()
	if pb.open_patch(patch) < 0:
		push_error("Music: couldn't open " + patch)
	return pb


# ------------------------------------------------------------------ playing
func synth_note(note: int, velocity := 100) -> void:
	if _pd_synth:
		_pd_synth.send_list("synth_note", [note, velocity])

func synth_note_off(note: int) -> void:
	synth_note(note, 0)

func synth_all_off() -> void:
	if _pd_synth:
		_pd_synth.send_bang("synth_all_off")

func drum(which: String, velocity := 110) -> void:
	if _pd_drums:
		_pd_drums.send_float("drum_" + which, velocity)

func dexed_note(note: int, velocity := 100) -> void:
	if dexed:
		dexed.note_on(note, velocity)

func dexed_note_off(note: int) -> void:
	if dexed:
		dexed.note_off(note)

## Any analog synth setting by its patch name without the "synth_" prefix.
func set_synth(param: String, value: float) -> void:
	_synth(param, value)

## Any drum setting by its patch name, e.g. "kick_decay".
func set_drum(param: String, value: float) -> void:
	_drum(param, value)


# ------------------------------------------------------------------ demo groove
const BASS := [45, 45, 57, 45, 48, 45, 52, 43]   # one note per beat, A minor
const CHORDS := [[69, 72, 76], [67, 71, 74]]     # Am, G (two bars each)

func _process(delta: float) -> void:
	if not demo_groove:
		return
	_beat_time += delta
	var eighth := 30.0 / bpm
	while _beat_time >= eighth:
		_beat_time -= eighth
		_play_step(_step)
		_step = (_step + 1) % 32


func _play_step(s: int) -> void:
	var beat := floori(s / 2.0)
	if s % 2 == 0:
		if beat % 2 == 0:
			drum("kick", 120)
		else:
			drum("snare", 105)
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


# ------------------------------------------------------------------ sending
func _synth(name: String, v: float) -> void:
	if _ready_done and _pd_synth:
		_pd_synth.send_float("synth_" + name, v)

func _drum(name: String, v: float) -> void:
	if _ready_done and _pd_drums:
		_pd_drums.send_float(name, v)

func _send_all() -> void:
	for prop in get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_EDITOR:
			set(prop.name, get(prop.name))   # runs each setter once with the Inspector value

func _set_osc1(v): osc1_level = v; _synth("osc1_level", v)
func _set_osc2(v): osc2_level = v; _synth("osc2_level", v)
func _set_sub(v): sub_level = v; _synth("sub_level", v)
func _set_detune(v): detune_cents = v; _synth("detune", v)
func _set_pmix(v): pulse_mix = v; _synth("pulse_mix", v)
func _set_pw(v): pulse_width = v; _synth("pulse_width", v)
func _set_drive(v): drive = v; _synth("drive", v)
func _set_cutoff(v): cutoff = v; _synth("cutoff", v)
func _set_res(v): resonance = v; _synth("resonance", v)
func _set_famt(v): filter_env_amount = v; _synth("filter_env_amount", v)
func _set_fvel(v): filter_velocity = v; _synth("filter_velocity", v)
func _set_fatt(v): filter_attack_ms = v; _synth("filter_attack", v)
func _set_fdec(v): filter_decay_ms = v; _synth("filter_decay", v)
func _set_fsus(v): filter_sustain = v; _synth("filter_sustain", v)
func _set_frel(v): filter_release_ms = v; _synth("filter_release", v)
func _set_att(v): attack_ms = v; _synth("attack", v)
func _set_dec(v): decay_ms = v; _synth("decay", v)
func _set_sus(v): sustain = v; _synth("sustain", v)
func _set_rel(v): release_ms = v; _synth("release", v)
func _set_svol(v): synth_volume = v; _synth("volume", v)
func _set_kp(v): kick_pitch = v; _drum("kick_pitch", v)
func _set_ke(v): kick_end = v; _drum("kick_end", v)
func _set_kpd(v): kick_pitch_decay_ms = v; _drum("kick_pitch_decay", v)
func _set_kd(v): kick_decay_ms = v; _drum("kick_decay", v)
func _set_kdr(v): kick_drive = v; _drum("kick_drive", v)
func _set_kl(v): kick_level = v; _drum("kick_level", v)
func _set_st(v): snare_tone = v; _drum("snare_tone", v)
func _set_sn(v): snare_noise = v; _drum("snare_noise", v)
func _set_ssn(v): snare_snappy_tone = v; _drum("snare_snappy_tone", v)
func _set_sd(v): snare_decay_ms = v; _drum("snare_decay", v)
func _set_sl(v): snare_level = v; _drum("snare_level", v)
func _set_ht(v): hat_tone = v; _drum("hat_tone", v)
func _set_hd(v): hat_decay_ms = v; _drum("hat_decay", v)
func _set_hl(v): hat_level = v; _drum("hat_level", v)
func _set_dvol(v): drums_volume = v; _drum("drums_volume", v)

func _set_mvol(v):
	music_volume_db = v
	for c in get_children():
		if c is AudioStreamPlayer:
			c.volume_db = v

func _set_cartridge(v):
	dexed_cartridge = v
	if _ready_done and dexed and v != "":
		if dexed.load_cartridge(v) > 0:
			dexed.set_program(dexed_program)

func _set_polyphony(v):
	dexed_polyphony = v
	if _ready_done and dexed:
		dexed.polyphony = v

func _set_program(v):
	dexed_program = v
	if _ready_done and dexed:
		dexed.set_program(v)

func _set_dvolume(v):
	dexed_volume = v
	if _ready_done and dexed:
		dexed.volume = v
