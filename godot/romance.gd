class_name Romance
extends Node
## 1-3 薛定谔告白 — bright Japanese-J-pop "romcom OP" chiptune, driven by the
## Conductor's subdivisions (locks to the beat, follows the tempo ramp). A
## square-wave hook over the classic I–V–vi–IV (C G Am F) loop, pulse-wave
## chord stabs, a bouncing bass, and snappy 8-bit drums — cheerful, slightly
## nervous, anime-confession energy. `play_outro()` lands a "ta-da" tonic.

const RATE := 44100
const BASE := 261.63  # C4

## I–V–vi–IV in C, voiced from C4 (semitones).
const PROG := [
	[0, 4, 7],      # C
	[-5, -1, 2],    # G
	[-3, 0, 4],     # Am
	[-7, -3, 0],    # F
]
## Catchy 2-bar hook (eighth-notes, semitones from C); plays over the loop.
const LEAD := [7, 12, 11, 12, 9, 7, 4, 7, 9, 7, 4, 2, 0, 4, 7, 9]

var enabled := true
var players: Array[AudioStreamPlayer] = []
var pi := 0
var lead_i := 0

var s_pad: AudioStreamWAV
var s_lead: AudioStreamWAV
var s_bass: AudioStreamWAV
var s_kick: AudioStreamWAV
var s_snare: AudioStreamWAV
var s_hat: AudioStreamWAV

var finale := false   # last phrase: wind down so the end is audible


func _ready() -> void:
	for i in 26:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	s_pad = _render(BASE, 0.0, 0.32, "pulse", 0.4, 0.0, 0.25)
	s_lead = _render(BASE, 0.0, 0.2, "square", 0.42, 0.0, 0.5)
	s_bass = _render(BASE * 0.5, 0.0, 0.22, "triangle", 0.85, 0.0, 0.5)
	s_kick = _render(125.0, 48.0, 0.16, "sine", 0.95, 0.0, 0.5)
	s_snare = _render(330.0, 200.0, 0.13, "noise", 0.5, 0.9, 0.5)
	s_hat = _render(9000.0, 0.0, 0.025, "noise", 0.24, 1.0, 0.5)


func setup(conductor: Conductor) -> void:
	conductor.subdivision.connect(_on_subdivision)


func reset() -> void:
	lead_i = 0
	finale = false


func _on_subdivision(cycle_index: int, sub: int) -> void:
	if not enabled:
		return
	var bar := int(cycle_index / 4.0)
	var beat := cycle_index % 4
	var chord: Array = PROG[bar % PROG.size()]

	# Finale: drop the drums, ring the chord + a soft hook so the end is clear.
	if finale:
		if sub == 0:
			if beat == 0:
				for n in chord:
					_play(s_pad, semi(n), -15.0)
				_play(s_bass, semi(chord[0] - 12), -11.0)
				_play(s_lead, semi(LEAD[lead_i % LEAD.size()] + 12), -13.0)
				lead_i += 1
			elif beat == 2:
				_play(s_lead, semi(chord[0] + 12), -15.0)
		return

	if sub == 0:
		# Chord stab + four-on-the-floor-ish drums + bass.
		for n in chord:
			_play(s_pad, semi(n), -16.0)
		_play(s_bass, semi(chord[0] - 12), -7.0)
		if beat == 0 or beat == 2:
			_play(s_kick, 1.0, -5.0)
		else:
			_play(s_snare, 1.0, -9.0)
		_play(s_hat, 1.0, -22.0)
		# Square-wave hook on every strong sub.
		_play(s_lead, semi(LEAD[lead_i % LEAD.size()] + 12), -10.0)
		lead_i += 1
	else:
		# Off-beats: hats, a bass octave-bounce, and the hook's syncopation.
		if sub == 2:
			_play(s_hat, 1.0, -24.0)
			_play(s_bass, semi(chord[0], ), -13.0)   # octave-up bounce
			_play(s_lead, semi(LEAD[lead_i % LEAD.size()] + 12), -13.0)
			lead_i += 1
		else:
			_play(s_hat, 1.0, -28.0)


## Closing flourish — a bright "ta-da" tonic chord + high hook note.
func play_outro() -> void:
	for n in [0, 4, 7, 12]:
		_play(s_pad, semi(n), -12.0)
	_play(s_bass, semi(-12), -9.0)
	_play(s_lead, semi(24), -10.0)
	_play(s_kick, 1.0, -6.0)


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


## 16-bit mono one-shot. wave: square / pulse (duty), triangle, sine, noise.
func _render(freq: float, slide: float, dur: float, wave: String, gain: float,
		noise_amt: float, duty: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var attack := 0.004
	var phase := 0.0
	for i in n:
		var ti := float(i) / RATE
		var f := freq
		if slide > 0.0:
			f = freq * pow(slide / freq, ti / dur)
		phase += TAU * f / RATE
		var ph: float = fposmod(phase / TAU, 1.0)
		var base := 0.0
		match wave:
			"sine": base = sin(phase)
			"triangle": base = asin(sin(phase)) * (2.0 / PI)
			"square": base = 1.0 if ph < duty else -1.0
			"pulse": base = 1.0 if ph < duty else -1.0
			"noise": base = randf_range(-1.0, 1.0)
		var s: float = lerpf(base, randf_range(-1.0, 1.0), noise_amt)
		var env := 0.0
		if ti < attack:
			env = ti / attack
		else:
			env = pow(0.0001, (ti - attack) / maxf(dur - attack, 0.0001))
		data.encode_s16(i * 2, int(clampf(s * gain * env, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = data
	return st
