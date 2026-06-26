class_name BBQMusic
extends Node
## 1-4 烤摊之王 — 维吾尔/新疆烧烤摊舞曲 (chiptune).
## 达普(手鼓)的切分节奏 + 热瓦普亮弹拨主题 + 都塔尔低音持续 + 拍手/铃片,
## 增二度异域音阶(Hijaz / 弗里几亚属)。全部运行时合成,跟着 Conductor 的
## subdivision 走 —— 天然踩点、随提速变快。

const RATE := 44100
const BASE := 261.63  # C4 参考音(各音用 pitch_scale 相对偏移)

## 维吾尔风音阶(以 A 为主音的 Hijaz / 弗里几亚属):A Bb C# D E F G —— 半音
## [0,1,4,5,7,8,10],标志性的增二度在 Bb(1)→C#(4)。
const SCALE := [0, 1, 4, 5, 7, 8, 10]

## 低音和声走向(每小节一个根音,半音 from A):i - i - iv - V
const BASS_ROOT := [0, 0, 5, 7]

## 热瓦普主题钩子 —— 半音 from A4,八分音符一个,4 小节一轮。
## 下行异域跑句(强调增二度)+ 回主音。
const HOOK := [
	# 小节1:高把位下行 A F E D C# D C# Bb
	12, 8, 7, 5, 4, 5, 4, 1,
	# 小节2:回升再落到主音 A C# D E F E D A
	0, 4, 5, 7, 8, 7, 5, 0,
	# 小节3:增二度来回的卖弄句 C# Bb C# F E C# Bb A
	4, 1, 4, 8, 7, 4, 1, 0,
	# 小节4:收束 E D C# D C# Bb C# A
	7, 5, 4, 5, 4, 1, 4, 0,
]

## 达普节奏(4 拍,每拍 4 个十六分位 sub0..3):D=咚(低/重)t=哒(高/轻)。
## 新疆舞曲招牌:反拍上的切分推进 + 第 2、4 拍的回拍。
const DAP := [
	["D", "", "", ""],   # 拍0:重咚落地
	["t", "", "D", ""],  # 拍1:轻起 + "and"上切分一记重咚(推进感)
	["D", "", "t", ""],  # 拍2
	["t", "", "D", "t"], # 拍3:填充滚进下一小节
]

var enabled := true
var players: Array[AudioStreamPlayer] = []
var pi := 0
var hook_i := 0
var finale := false

var s_dum: AudioStreamWAV       # 手鼓低音
var s_tek: AudioStreamWAV       # 手鼓边击
var s_jingle: AudioStreamWAV    # 铃片/沙锤
var s_clap: AudioStreamWAV      # 拍手
var s_rawap: AudioStreamWAV     # 热瓦普弹拨
var s_bass: AudioStreamWAV      # 都塔尔低音
var s_drone: AudioStreamWAV     # 持续音(沙漠氛围)


func _ready() -> void:
	for i in 26:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	# 手鼓:咚 = 低沉下滑正弦 + 一点噪声皮膜；哒 = 短促高边击
	s_dum = _render(150.0, 70.0, 0.16, "sine", 0.95, 0.12, 0.5)
	s_tek = _render(440.0, 300.0, 0.05, "square", 0.5, 0.5, 0.5)
	# 铃片/沙锤:很短的高频噪声
	s_jingle = _render(9000.0, 0.0, 0.03, "noise", 0.22, 1.0, 0.5)
	# 拍手:中频噪声爆裂
	s_clap = _render(1600.0, 900.0, 0.06, "noise", 0.45, 0.9, 0.5)
	# 热瓦普:明亮带嗡音的弹拨(窄占空比方波,快速衰减)
	s_rawap = _render(BASE, 0.0, 0.20, "square", 0.55, 0.04, 0.18)
	# 都塔尔低音:温暖三角波
	s_bass = _render(BASE * 0.5, 0.0, 0.26, "triangle", 0.8, 0.0, 0.5)
	# 持续音:低沉锯齿嗡鸣
	s_drone = _render(BASE * 0.5, 0.0, 0.9, "sawtooth", 0.5, 0.02, 0.5)


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

	# 收尾:撤掉热闹的鼓组,只留持续音 + 慢热瓦普点缀
	if finale:
		if sub == 0:
			if beat == 0:
				_play(s_drone, semi(root - 12), -14.0)
				_play(s_bass, semi(root - 12), -12.0)
			if beat == 0 or beat == 2:
				_play(s_rawap, semi(root + 12), -16.0)
			_play(s_dum, 1.0, -16.0)
		return

	# --- 持续音(沙漠氛围):每小节头补一记 ---
	if beat == 0 and sub == 0:
		_play(s_drone, semi(root - 12), -20.0)

	# --- 达普手鼓 ---
	var hit: String = DAP[beat][sub]
	if hit == "D":
		_play(s_dum, 1.0, -5.0)
	elif hit == "t":
		_play(s_tek, 1.0, -10.0)

	# 铃片:每拍的反拍(sub1/sub3)轻轻撒,off-beat 更亮
	if sub == 1:
		_play(s_jingle, 1.0, -24.0)
	elif sub == 3:
		_play(s_jingle, 1.0, -20.0)

	# 拍手:第 2、4 拍回拍(新疆舞曲招牌)
	if (beat == 1 or beat == 3) and sub == 0:
		_play(s_clap, 1.0, -12.0)

	# --- 低音(都塔尔):落在拍0和拍2,拍3的反拍加个切分推一下 ---
	if sub == 0 and (beat == 0 or beat == 2):
		_play(s_bass, semi(root - 12), -7.0)
	elif sub == 2 and beat == 3:
		_play(s_bass, semi(root - 5), -10.0)

	# --- 热瓦普主题:八分音符跑句(sub0/sub2),反拍稍弱 ---
	if sub == 0 or sub == 2:
		var note: int = HOOK[hook_i % HOOK.size()]
		hook_i += 1
		var vol := -9.0 if sub == 0 else -13.0
		_play(s_rawap, semi(note), vol)
		# 强拍偶尔加个上邻音装饰(热瓦普的小颤音味道)
		if sub == 0 and beat % 2 == 0:
			_play(s_rawap, semi(note + 1), -20.0)


## 收尾华彩:主音和弦扫一记 + 手鼓
func play_outro() -> void:
	for n in [0, 4, 7, 12]:
		_play(s_rawap, semi(n), -9.0)
	_play(s_bass, semi(-12), -7.0)
	_play(s_drone, semi(-12), -12.0)
	_play(s_dum, 1.0, -5.0)
	_play(s_clap, 1.0, -10.0)


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
