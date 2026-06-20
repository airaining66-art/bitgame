class_name Chiptune
extends Node
## Procedural 8-bit music driven entirely by the Conductor's beat signals.
## Because it reacts to subdivisions (not a fixed track), it stays locked to
## the gameplay beat and follows the tempo ramp for free. Reusable per level.

const RATE := 44100
const BASE_SQUARE := 261.63  # C4 for the arp
const BASE_BASS := 65.41     # C2 for the bass

## 8-bar progression in A minor with a Dm–E turnaround (less repetitive than a
## 4-bar loop). arp = semitones from C4, root = semitones from C2.
const CHORDS := [
	{"arp": [-3, 0, 4, 12], "root": 9},   # Am
	{"arp": [5, 9, 12, 17], "root": 5},   # F
	{"arp": [0, 4, 7, 12], "root": 0},    # C
	{"arp": [7, 11, 14, 19], "root": 7},  # G
	{"arp": [-3, 0, 4, 12], "root": 9},   # Am
	{"arp": [5, 9, 12, 17], "root": 5},   # F
	{"arp": [2, 5, 9, 14], "root": 2},    # Dm
	{"arp": [4, 8, 11, 16], "root": 4},   # E  (dominant)
]

## Lead melody, one slot per beat over the 8 bars (semitones from C4; REST = silent).
const REST := 99
const MELODY := [
	9, REST, 12, REST,    # Am: A . C .
	14, REST, 12, REST,   # F:  D . C .
	7, REST, 4, REST,     # C:  G . E .
	2, REST, 7, REST,     # G:  D . G .
	9, REST, 12, REST,    # Am
	17, REST, 14, REST,   # F:  F . D .
	14, REST, 9, REST,    # Dm: D . A .
	11, REST, 8, REST,    # E:  B . G# .
]

var enabled := true
var finale := false   # last phrase wind-down
var players: Array[AudioStreamPlayer] = []
var pi := 0
var arp_step := 0

var s_kick: AudioStreamWAV
var s_snare: AudioStreamWAV
var s_hat: AudioStreamWAV
var s_square: AudioStreamWAV
var s_bass: AudioStreamWAV


func _ready() -> void:
	for i in 18:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		players.append(p)
	s_kick = _render(150.0, 48.0, 0.14, "triangle", 0.9, 0.0)
	s_snare = _render(190.0, 120.0, 0.13, "triangle", 0.7, 0.8)
	s_hat = _render(8000.0, 0.0, 0.03, "noise", 0.4, 1.0)
	s_square = _render(BASE_SQUARE, 0.0, 0.20, "square", 0.7, 0.0)
	s_bass = _render(BASE_BASS, 0.0, 0.24, "triangle", 0.85, 0.0)


func setup(conductor: Conductor) -> void:
	conductor.subdivision.connect(_on_subdivision)


func reset() -> void:
	arp_step = 0
	finale = false


func _on_subdivision(cycle_index: int, sub: int) -> void:
	if not enabled:
		return
	var bar := int(cycle_index / 4.0)
	var chord: Dictionary = CHORDS[bar % CHORDS.size()]
	var arp: Array = chord["arp"]

	# Finale: drop the busy bed, ring out the root + a kick so the end is heard.
	if finale:
		if sub == 0:
			_play(s_bass, semi_to_pitch(chord["root"]), -7.0)
			if cycle_index % 2 == 0:
				_play(s_kick, 1.0, -4.0)
				_play(s_square, semi_to_pitch(chord["arp"][0]), -13.0)
		return

	# Arp alternates ascending / descending each bar so the bed keeps moving.
	var idx := arp_step % arp.size()
	if bar % 2 == 1:
		idx = arp.size() - 1 - idx
	arp_step += 1
	var arp_semi: int = arp[idx]

	# Drum fill across the turnaround bar (every 4th bar).
	var is_fill := (bar % 4 == 3) and (cycle_index % 4 == 3)

	if sub == 0:
		# Lead melody on the downbeat; falls back to the arp note on a rest.
		var note: int = MELODY[cycle_index % MELODY.size()]
		if note != REST:
			_play(s_square, semi_to_pitch(note + 12), -9.0)
		else:
			_play(s_square, semi_to_pitch(arp_semi), -15.0)
		_play(s_kick, 1.0, -4.0)
		_play(s_bass, semi_to_pitch(chord["root"]), -9.0)
	else:
		_play(s_square, semi_to_pitch(arp_semi), -15.0)
		if is_fill:
			_play(s_snare, 1.0, -12.0)
		elif sub == 2:
			_play(s_snare, 1.0, -8.0)
			_play(s_hat, 1.0, -19.0)
		else:
			_play(s_hat, 1.0, -21.0)


func semi_to_pitch(semitones: int) -> float:
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


## Build a one-shot 16-bit mono WAV. noise_amt blends in white noise (drums);
## slide > 0 gives an exponential pitch drop (kick).
func _render(freq: float, slide: float, dur: float, wave: String, gain: float,
		noise_amt: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var attack := 0.004
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := freq
		if slide > 0.0:
			f = freq * pow(slide / freq, t / dur)
		phase += TAU * f / RATE
		var base := 0.0
		match wave:
			"sine": base = sin(phase)
			"triangle": base = asin(sin(phase)) * (2.0 / PI)
			"square": base = 1.0 if sin(phase) >= 0.0 else -1.0
			"sawtooth": base = 2.0 * fposmod(phase / TAU, 1.0) - 1.0
			"noise": base = randf_range(-1.0, 1.0)
		var s: float = lerpf(base, randf_range(-1.0, 1.0), noise_amt)
		var env := 0.0
		if t < attack:
			env = t / attack
		else:
			env = pow(0.0001, (t - attack) / maxf(dur - attack, 0.0001))
		data.encode_s16(i * 2, int(clampf(s * gain * env, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = data
	return st
