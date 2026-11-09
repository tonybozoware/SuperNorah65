class_name KitPlayer
extends Node
## Plays the current SoundKit for the player's actions. Lives on Player/Kit.
## Press L (next_kit_key) to switch kits while playing.
##
## Every sound is played by the scene's Instruments node (Pure Data).

@export var kits: Array[SoundKit] = []   ## leave empty to load every kit in kits_folder
@export_dir var kits_folder := "res://kits"
@export var start_kit := 0
@export var next_kit_key: Key = KEY_L
## Print each kit event and note to the Output panel.
@export var log_notes := false

@onready var player: Player = get_parent()

var current := -1
var kit: SoundKit
var run_meter := 0.0      ## 0..1, read by RUN routes
var instruments: Instruments

var _baseline := {}       # Instruments setting -> its Inspector value, for undoing a kit's patch
var _route_last := {}     # Instruments setting -> last value sent by a route
var _gen := {}            # "a60" / "d60" -> note generation (a newer note-on wins)
var _sounding := {}       # keys that are on right now
var _held: Array = []     # [instrument, note, generation] waiting for the next landing
var _land_notes: Array = []   # [instrument, note, generation, fade ms] to fade on the next jump chord
var _sequence := {}       # KitEvent -> next index
var _air_time := 0.0
var _air_jump := -1       # the jump kind that started the current airtime
var _slow_time := 0.0     # s spent slow on the ground
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if Player.State.JUMP != 9 or Player.State.ROLLOUT != 23:
		push_warning("KitPlayer: Player.State changed; update KitEvent.only_from's list")
	if kits.is_empty():
		_load_folder()
	var scene := get_tree().current_scene if get_tree().current_scene else get_tree().root
	instruments = scene.find_child("Instruments", true, false) as Instruments
	var visual := player.get_node_or_null("Visual")
	if visual and visual.has_signal("footstep"):
		visual.connect("footstep", func(s: float): _fire(KitEvent.Event.FOOTSTEP, -1, s))
	if visual and visual.has_signal("roll_step"):
		visual.connect("roll_step", func(s: float, in_air: bool):
			if kit and (not in_air or kit.steps_in_air):
				_fire(KitEvent.Event.ROLL_STEP, -1, s))
	if visual and visual.has_signal("air_step"):
		visual.connect("air_step", func(s: float):
			if kit and kit.steps_in_air:
				_fire(KitEvent.Event.FOOTSTEP, -1, s))
	player.jumped.connect(func(kind: int):
		if kind != Player.State.WALL_KICK:
			_air_jump = kind   # what started this airtime (a wall kick keeps the original)
		_fire(KitEvent.Event.JUMP, kind, 1.0))
	player.landed.connect(_on_landed)
	player.pounded.connect(func(): _fire(KitEvent.Event.POUND_LAND, -1, 1.0))
	player.wall_kicked.connect(func(): _fire(KitEvent.Event.WALL_KICK, -1, 1.0))
	player.ledge_grabbed.connect(func():
		_air_jump = -1
		_release_held()
		_fire(KitEvent.Event.LEDGE_GRAB, -1, 1.0))
	player.wall_hit.connect(func(speed: float): _fire(KitEvent.Event.WALL_HIT, -1, speed))
	player.ceiling_hit.connect(func(speed: float): _fire(KitEvent.Event.CEILING_HIT, -1, speed))
	player.state_changed.connect(_on_state_changed)
	player.respawned.connect(func():
		_air_jump = -1    # a respawn isn't the end of the jump you fell from
		_release_held())
	if not kits.is_empty():
		apply(clampi(start_kit, 0, kits.size() - 1))


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == next_kit_key and not kits.is_empty():
		apply((current + 1) % kits.size())


## Switch to kit number `index`: stop its notes, undo the old patch, apply the new one.
func apply(index: int) -> void:
	_all_notes_off()
	if instruments:
		for prop in _baseline:
			instruments.set(prop, _baseline[prop])
	_route_last.clear()
	_sequence.clear()
	current = index
	kit = kits[index]
	if not instruments:
		push_warning("KitPlayer: no Instruments node in this scene, so '%s' can't play" % kit.kit_name)
	if instruments:
		for prop in kit.patch:
			_set_instruments(prop, kit.patch[prop])
		for route in kit.routes:
			if not _baseline.has(route.target):
				_baseline[route.target] = instruments.get(route.target)
		for e: KitEvent in kit.events:   # copy sounds into the sampler now, not on first play
			if e.instrument == KitEvent.Instrument.SAMPLE and e.stream:
				instruments.load_sample(e.stream)
	print("Sound kit: ", kit.kit_name)


func _set_instruments(prop: String, value) -> void:
	if not prop in instruments:
		push_warning("KitPlayer: Instruments has no setting '%s'" % prop)
		return
	if not _baseline.has(prop):
		_baseline[prop] = instruments.get(prop)
	instruments.set(prop, value)


# ------------------------------------------------------------------ live routes
func _physics_process(delta: float) -> void:
	if not kit:
		return
	var speed := absf(player.forward_speed)
	var grounded := player.state not in Player.AIR_STATES and player.state not in Player.LEDGE_STATES
	_slow_time = _slow_time + delta if grounded and speed < kit.run_stop_speed else 0.0
	if speed >= kit.run_hold_speed:
		run_meter += delta / maxf(kit.run_fill_seconds, 0.01)
	elif _slow_time > 0.0 and (player.stick < 0.1 or _slow_time > kit.run_stop_grace):
		# Stopped: slow with the stick let go, or slow for a while (a skid turn with
		# the stick held doesn't count as stopping).
		run_meter -= delta / maxf(kit.run_empty_seconds, 0.01)
	run_meter = clampf(run_meter, 0.0, 1.0)
	_air_time = 0.0 if grounded else _air_time + delta
	if not instruments:
		return
	for route: KitModRoute in kit.routes:
		var x := 0.0
		match route.source:
			KitModRoute.Source.RUN: x = run_meter
			KitModRoute.Source.SPEED: x = speed / player.max_walk_speed
			KitModRoute.Source.FACING_NORTH: x = (cos(player.facing) + 1.0) * 0.5
			KitModRoute.Source.FACING_EAST: x = (1.0 - sin(player.facing)) * 0.5
			KitModRoute.Source.AIRTIME: x = _air_time / maxf(route.airtime_full, 0.01)
			KitModRoute.Source.HEIGHT_SPEED: x = 0.5 + player.vy / (2.0 * player.max_fall_speed)
		var v := route.map(x)
		var last = _route_last.get(route.target)
		if last == null or absf(v - last) > absf(last) * 0.002 + 0.0005:
			_route_last[route.target] = v
			instruments.set(route.target, v)


# ------------------------------------------------------------------ events
func _on_landed(impact: float) -> void:
	_release_held()
	var from := player.state   # still the air state here
	# Diving, ground pounding or bonking out of a triple jump still lands the triple
	# jump (its landing chord), for anything in the same airtime.
	if _air_jump == Player.State.TRIPLE_JUMP:
		from = Player.State.TRIPLE_JUMP
	_air_jump = -1
	_fire(KitEvent.Event.LAND, from, impact)


func _on_state_changed(_from: int, to: int) -> void:
	match to:
		Player.State.DIVE: _fire(KitEvent.Event.DIVE, -1, 1.0)
		Player.State.GROUND_POUND: _fire(KitEvent.Event.GROUND_POUND, -1, 1.0)
		Player.State.SKID: _fire(KitEvent.Event.SKID, -1, absf(player.forward_speed) / player.max_walk_speed)


## Play every event in the kit for this trigger. Events filtered to `from` win over
## the kit's "Any" events for the same trigger.
func _fire(which: int, from: int, amount: float) -> void:
	if not kit:
		return
	var specific: Array[KitEvent] = []
	var any: Array[KitEvent] = []
	for e: KitEvent in kit.events:
		if e.event != which:
			continue
		if e.only_from == -1:
			any.append(e)
		elif e.only_from == from:
			specific.append(e)
	var chosen := specific if not specific.is_empty() else any
	if which == KitEvent.Event.JUMP and _plays_notes(chosen):
		_fade_land_notes()   # the landing chord gives way to the jump chord
		_release_held()      # and so does the previous jump's chord
	for e in chosen:
		_play(e, amount)


func _plays_notes(events: Array[KitEvent]) -> bool:
	for e in events:
		if e.instrument in [KitEvent.Instrument.ANALOG_SYNTH, KitEvent.Instrument.DEXED] and not e.notes.is_empty():
			return true
	return false


func _fade_land_notes() -> void:
	for h in _land_notes:
		var k := _key(h[0], h[1])
		if _gen.get(k, -1) == h[2] and _sounding.has(k):
			if h[0] == KitEvent.Instrument.DEXED:
				instruments.dexed_choke(h[1], h[3])
			else:
				instruments.synth_note_off(h[1])
			_sounding.erase(k)
	_land_notes.clear()


func _play(e: KitEvent, amount: float) -> void:
	var t := 1.0
	match e.velocity_from:
		KitEvent.VelocityFrom.STRENGTH: t = clampf(amount, 0.0, 1.0)
		KitEvent.VelocityFrom.IMPACT: t = clampf(amount / maxf(e.full_impact, 0.01), 0.0, 1.0)
	var vel := lerpf(e.velocity_min, e.velocity_max, t)
	if not _need_instruments():
		return
	match e.instrument:
		KitEvent.Instrument.NOISE, KitEvent.Instrument.ORCHESTRA_HIT, KitEvent.Instrument.TIMPANI:
			var loud := vel * db_to_linear(e.volume_db)
			instruments.hit(["noise", "orch", "timpani"][e.instrument], loud)
			if log_notes:
				print("kit ", KitEvent.Event.keys()[e.event], " ", KitEvent.Instrument.keys()[e.instrument], " vel ", roundi(loud))
		KitEvent.Instrument.SAMPLE:
			if e.stream:
				instruments.play_sample(e.stream, vel * db_to_linear(e.volume_db))
		KitEvent.Instrument.KICK, KitEvent.Instrument.SNARE, KitEvent.Instrument.HAT:
			instruments.drum(["kick", "snare", "hat"][e.instrument - KitEvent.Instrument.KICK], roundi(vel))
		KitEvent.Instrument.ANALOG_SYNTH, KitEvent.Instrument.DEXED:
			if e.notes.is_empty():
				return
			var picked := PackedInt32Array()
			match e.note_mode:
				KitEvent.NoteMode.CHORD: picked = e.notes
				KitEvent.NoteMode.RANDOM: picked.append(e.notes[_rng.randi() % e.notes.size()])
				KitEvent.NoteMode.SEQUENCE:
					var i: int = _sequence.get(e, 0)
					picked.append(e.notes[i % e.notes.size()])
					_sequence[e] = i + 1
			if log_notes:
				print("kit ", KitEvent.Event.keys()[e.event], " ", KitEvent.Instrument.keys()[e.instrument], " ", picked, " vel ", roundi(vel))
			if e.hold_until_land:
				_release_held()   # a new held chord cuts the previous one
			if e.event == KitEvent.Event.LAND:
				_land_notes.clear()
			for n in picked:
				var gen := _note_on(e.instrument, n, clampi(roundi(vel), 1, 127))
				if e.fade_on_next_jump:
					_land_notes.append([e.instrument, n, gen, e.fade_ms])
				if e.hold_until_land:
					_held.append([e.instrument, n, gen])
					get_tree().create_timer(MAX_HOLD).timeout.connect(_note_off.bind(e.instrument, n, gen))
				else:
					get_tree().create_timer(e.length_seconds).timeout.connect(_note_off.bind(e.instrument, n, gen))


const MAX_HOLD := 10.0   # s; held notes end by then even without a landing

var _warned := false

func _need_instruments() -> bool:
	if not instruments and not _warned:
		_warned = true
		push_warning("KitPlayer: no Instruments node in this scene, so synth sounds are skipped")
	return instruments != null


# ------------------------------------------------------------------ notes
func _key(inst: int, note: int) -> String:
	return ("d" if inst == KitEvent.Instrument.DEXED else "a") + str(note)


## Note-on that restarts the note if it's already sounding. Returns its generation:
## a later note-off only stops the note if no newer note-on has happened since.
func _note_on(inst: int, note: int, vel: int) -> int:
	var k := _key(inst, note)
	if _sounding.has(k):
		_send_off(inst, note)
	var gen: int = _gen.get(k, 0) + 1
	_gen[k] = gen
	_sounding[k] = true
	if inst == KitEvent.Instrument.DEXED:
		instruments.dexed_note(note, vel)
	else:
		instruments.synth_note(note, vel)
	return gen


func _note_off(inst: int, note: int, gen: int) -> void:
	var k := _key(inst, note)
	if _gen.get(k, -1) == gen and _sounding.has(k):
		_send_off(inst, note)
		_sounding.erase(k)


func _send_off(inst: int, note: int) -> void:
	if not instruments:
		return
	if inst == KitEvent.Instrument.DEXED:
		instruments.dexed_note_off(note)
	else:
		instruments.synth_note_off(note)


func _release_held() -> void:
	for h in _held:
		_note_off(h[0], h[1], h[2])
	_held.clear()


func _all_notes_off() -> void:
	for k: String in _sounding.keys():
		_send_off(KitEvent.Instrument.DEXED if k[0] == "d" else KitEvent.Instrument.ANALOG_SYNTH, int(k.substr(1)))
		_gen[k] = _gen.get(k, 0) + 1
	_sounding.clear()
	_held.clear()
	_land_notes.clear()


func _load_folder() -> void:
	var files := Array(DirAccess.get_files_at(kits_folder))
	files.sort()
	for f in files:
		var file: String = f.trim_suffix(".remap")   # exported builds list .tres.remap
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var res := load(kits_folder.path_join(file))
		if res is SoundKit:
			kits.append(res)
