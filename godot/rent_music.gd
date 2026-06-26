class_name RentMusic
extends Node
## 1-5 房租的主人 — 日式武士 chiptune.
## 太鼓(低/高手鼓)+ 古筝拨弦 hook + 三味线滑音 + 低音,In 阴音阶,
## 紧张带点诙谐。跟着 Conductor 的 subdivision 走(天然踩点、随提速变快)。

const RATE := 44100
const BASE := 261.63  # C4 参考音(各音用 pitch_scale 相对偏移)

## In 阴音阶(都节调式,以 A 为主音):A Bb D E F —— 半音 [0,1,5,7,8]
const SCALE := [0, 1, 5, 7, 8]
## 低音和声根音(每小节一个,半音 from A):i - i - VI - V
const BASS_ROOT := [0, 0, -4, -5]

## 古筝主题钩子(半音 from A4),八分音符一个,4 小节一轮 —— 阴森下行
const HOOK := [
	12, 8, 7, 5, 1, 0, 1, 5,
	7, 8, 12, 8, 7, 5, 1, 0,
	5, 7, 8, 7, 5, 1, 0, 1,
	0, 1, 5, 7, 8, 7, 5, 0,
]

var enabled := true
var players: Array[AudioStreamPlayer] = []
var pi := 0
var hook_i := 0
var finale := false

var s_taiko: AudioStreamWAV    # 大太鼓(低)
var s_tsuzumi: AudioStreamWAV  # 小鼓(高)
var s_koto: AudioStreamWAV     # 古筝拨弦
var s_shami: AudioStreamWAV    # 三味线滑音
var s_bass: AudioStreamWAV     # 低音
var s_shaker: AudioStreamWAV   # 沙锤/铃


func _ready() -> void:
	for i in 24:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	s_taiko = _render(120.0, 55.0, 0.20, "sine", 0.95, 0.15, 0.5)
	s_tsuzumi = _render(520.0, 360.0, 0.07, "sine", 0.6, 0.25, 0.5)
	s_koto = _render(BASE, 0.0, 0.22, "triangle", 0.6, 0.03, 0.5)
	s_shami = _render(BASE, BASE * 1.06, 0.16, "square", 0.45, 0.05, 0.16)
	s_bass = _render(BASE * 0.5, 0.0, 0.24, "triangle", 0.85, 0.0, 0.5)
	s_shaker = _render(7000.0, 0.0, 0.03, "noise", 0.2, 1.0, 0.5)


func setup(conductor: Conductor) -> void:
	conductor.subdivision.connect(_on_subdivision)


func reset() -> void:
	hook_i = 0
	finale = false


func _on_subdivision(cycle_index: int, sub: int) -> void:
	if not enabled:
		return
	var beat := cycle_index % 4
	var bar := int(cycle_index / 4.0)
	var root: int = BASS_ROOT[bar % BASS_ROOT.size()]

	# 收尾:撤掉密集鼓点,留太鼓 + 慢古筝余韵
	if finale:
		if sub == 0:
			if beat == 0:
				_play(s_bass, semi(root - 12), -12.0)
				_play(s_koto, semi(root + 12), -12.0)
			if beat == 0 or beat == 2:
				_play(s_taiko, 1.0, -8.0)
		return

	if sub == 0:
		# 太鼓:1、3 重拍大太鼓,2、4 小鼓
		if beat == 0 or beat == 2:
			_play(s_taiko, 1.0, -5.0)
		else:
			_play(s_tsuzumi, 1.0, -8.0)
		_play(s_bass, semi(root - 12), -7.0)
		# 古筝拨弦 hook
		var note: int = HOOK[hook_i % HOOK.size()]
		hook_i += 1
		_play(s_koto, semi(note), -9.0)
	elif sub == 2:
		# 反拍:沙锤 + 古筝弱音
		_play(s_shaker, 1.0, -22.0)
		var n2: int = HOOK[hook_i % HOOK.size()]
		hook_i += 1
		_play(s_koto, semi(n2), -15.0)
		# 偶尔三味线滑音点缀
		if beat == 3:
			_play(s_shami, semi(SCALE[bar % SCALE.size()] + 12), -14.0)
	else:
		_play(s_shaker, 1.0, -28.0)


## 收尾华彩:主音 + 太鼓一记
func play_outro() -> void:
	for n in [0, 7, 12]:
		_play(s_koto, semi(n), -8.0)
	_play(s_shami, semi(12), -10.0)
	_play(s_bass, semi(-12), -6.0)
	_play(s_taiko, 1.0, -4.0)


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


## 16-bit mono one-shot synth.
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
			"sawtooth": base = 2.0 * ph - 1.0
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
