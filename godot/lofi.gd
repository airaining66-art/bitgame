class_name Music
extends Node
## Southeast-Asian psych-rock kit, driven by the Conductor's subdivisions
## (locks to the beat, follows the tempo ramp). Metallic singing-bowl high tones
## (gamelan-ish ostinato), a hypnotic drone, driving bass + rock drums, a
## fuzzy/wavering psych lead, and the odd bird call. `play_outro()` rings out a
## closing chord so the level doesn't just cut off mid-phrase.
## (Filename/var still "lofi" for wiring; the sound is no longer lo-fi.)

const RATE := 44100
const BASE := 261.63  # C4

## A-minor pentatonic (A C D E G), semitones from C4.
const PENTA := [-3, 0, 2, 4, 7]
## Hypnotic two-chord psych vamp on the roots A and G (semitones from C2).
const ROOTS := [-3, -5]

var enabled := true
var players: Array[AudioStreamPlayer] = []
var pi := 0
var bell_step := 0
var lead_step := 0

var s_bell: AudioStreamWAV
var s_bass: AudioStreamWAV
var s_kick: AudioStreamWAV
var s_snare: AudioStreamWAV
var s_hat: AudioStreamWAV
var s_lead: AudioStreamWAV
var s_drone: AudioStreamWAV
var s_bird: AudioStreamWAV


func _ready() -> void:
	for i in 28:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	s_bell = _render(BASE, 0.0, 0.7, "bell", 0.5, 0.0, 0.0, 0.0)
	s_bass = _render(BASE * 0.25, 0.0, 0.28, "saw", 0.7, 0.0, 0.0, 0.2)
	s_kick = _render(125.0, 45.0, 0.19, "sine", 0.95, 0.0, 0.0, 0.0)
	s_snare = _render(210.0, 150.0, 0.16, "triangle", 0.6, 0.8, 0.0, 0.0)
	s_hat = _render(9500.0, 0.0, 0.025, "noise", 0.28, 1.0, 0.0, 0.0)
	s_lead = _render(BASE, 0.0, 0.5, "saw", 0.45, 0.0, 6.0, 0.5)   # fuzzy, wavering
	s_drone = _render(BASE * 0.5, 0.0, 2.2, "saw", 0.4, 0.0, 0.0, 0.15)
	s_bird = _render(2200.0, 3500.0, 0.07, "sine", 0.4, 0.0, 0.0, 0.0)


var finale := false   # last phrase: wind down so the end is audible


func setup(conductor: Conductor) -> void:
	conductor.subdivision.connect(_on_subdivision)


func reset() -> void:
	bell_step = 0
	lead_step = 0
	finale = false


func _on_subdivision(cycle_index: int, sub: int) -> void:
	if not enabled:
		return
	var bar := int(cycle_index / 4.0)
	var beat := cycle_index % 4
	var root: int = ROOTS[int(bar / 4.0) % ROOTS.size()]

	# Finale: drop the busy parts and ring out a drone + soft tonic bells so the
	# end is clearly audible coming.
	if finale:
		if sub == 0:
			if beat == 0:
				_play(s_drone, semi(ROOTS[0]), -13.0)
				_play(s_bell, semi(PENTA[0] + 12), -11.0)
			elif beat == 2:
				_play(s_bell, semi(PENTA[2] + 12), -13.0)
			_play(s_kick, 1.0, -8.0)
		return

	# Hypnotic drone every two bars.
	if sub == 0 and cycle_index % 8 == 0:
		_play(s_drone, semi(root), -18.0)

	if sub == 0:
		# Rock backbeat + driving bass.
		if beat == 0 or beat == 2:
			_play(s_kick, 1.0, -5.0)
			_play(s_bass, semi(root + (0 if beat == 0 else 7)), -9.0)
		else:
			_play(s_snare, 1.0, -10.0)
		# Sparse, wavering psych lead at the top of each bar.
		if beat == 0:
			var note: int = PENTA[lead_step % PENTA.size()] + 12
			lead_step += 1
			_play(s_lead, semi(note), -12.0)
	else:
		# Shimmering singing-bowl ostinato on the off-beats + hats.
		var bell: int = PENTA[bell_step % PENTA.size()] + 12
		bell_step += 1
		_play(s_bell, semi(bell), -14.0)
		if sub == 1 or sub == 3:
			_play(s_hat, 1.0, -23.0)

	# Occasional bird call.
	if randf() < 0.05:
		_play(s_bird, 1.0 + randf() * 0.5, -16.0)


## Closing flourish — a ringing tonic chord + bowl + bird, for the level end.
func play_outro() -> void:
	_play(s_drone, semi(-3), -14.0)           # A drone
	_play(s_bell, semi(PENTA[0] + 12), -10.0)  # A
	_play(s_bell, semi(PENTA[2] + 12), -11.0)  # D
	_play(s_bell, semi(PENTA[4] + 12), -11.0)  # G
	_play(s_lead, semi(PENTA[0] + 24), -12.0)
	_play(s_bird, 1.3, -14.0)


func semi(semitones: float) -> float:
	return pow(2.0, semitones / 12.0)


func _play(stream: AudioStreamWAV, pitch: float, volume_db: float) -> void:
	if stream == null:
		return
	var p := players[pi]
	pi = (pi + 1) % players.size()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


## 16-bit mono one-shot. wave: bell (inharmonic metal), saw, triangle, sine,
## noise. vibrato (Hz) wavers the pitch; clip adds soft fuzz.
func _render(freq: float, slide: float, dur: float, wave: String, gain: float,
		noise_amt: float, vibrato: float, clip: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var attack := 0.006
	if wave == "bell" or wave == "saw":
		attack = 0.003
	var phase := 0.0
	for i in n:
		var ti := float(i) / RATE
		var f := freq
		if slide > 0.0:
			f = freq * pow(slide / freq, ti / dur)
		if vibrato > 0.0:
			f *= 1.0 + sin(TAU * 5.5 * ti) * (vibrato / 100.0)
		phase += TAU * f / RATE
		var base := 0.0
		match wave:
			"sine": base = sin(phase)
			"triangle": base = asin(sin(phase)) * (2.0 / PI)
			"saw": base = 2.0 * fposmod(phase / TAU, 1.0) - 1.0
			"bell": base = (sin(phase) + 0.6 * sin(phase * 2.76) + 0.4 * sin(phase * 5.4) + 0.25 * sin(phase * 8.9)) * 0.45
			"noise": base = randf_range(-1.0, 1.0)
		var s: float = lerpf(base, randf_range(-1.0, 1.0), noise_amt)
		if clip > 0.0:
			s = clampf(s * (1.0 + clip * 4.0), -1.0, 1.0)
		var env := 0.0
		if ti < attack:
			env = ti / attack
		else:
			# Bell/drone ring out; percussive sounds decay fast.
			var k := 0.0001
			if wave == "bell":
				k = 0.0009
			elif wave == "saw" and dur > 1.0:
				k = 0.02
			env = pow(k, (ti - attack) / maxf(dur - attack, 0.0001))
		data.encode_s16(i * 2, int(clampf(s * gain * env, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = data
	return st
