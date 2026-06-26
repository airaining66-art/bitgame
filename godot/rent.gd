extends LevelBase
## 1-5 房租的主人 — 节奏天国「武士斩」式。居中武士,敌人沿弧线从左右两侧
## 轮流飞向中央判定点,踩拍出刀劈成两半。
##
## 该砍(房租的敌人):账单 / 电诈电话 / 借钱的朋友 —— 飞到中央时出刀。
## 别砍(心头好):美食 / 游戏卡带 / 心爱的女孩 —— 忍住别砍,让它飞过。
## 砍错(砍了心头好)= 扣血;该砍没砍(敌人飞过)= 扣血。
##
## (LevelBase 子类:只有本关的主题/谱面/判定/特效在这;HUD/Fever/结算/
## 倒计时/暂停/SFX 池来自基类。判定走自己的队列循环,类似 1-4。)

# --- palette ----------------------------------------------------------------
const COL_INK := Color("e8e2d6")     # 主色(纸白/月白)
const COL_RED := Color("e23b3b")     # 刀光红 / 危险
const COL_GOLD := Color("ffcf4d")    # 房租金
const COL_STEEL := Color("c9d2dc")   # 刀身
const COL_DARK := Color("141019")    # 夜色
const COL_MUTED := Color("8a8290")
const COL_GREEN := Color("6bd06b")
const COL_JUDGE := Color("ffe9b0")

# --- item kinds -------------------------------------------------------------
const BILL := 0   # 账单
const SCAM := 1   # 电诈电话
const LOAN := 2   # 借钱
const FOOD := 3   # 美食
const GAME := 4   # 游戏卡带
const GIRL := 5   # 心爱的女孩

const KIND_BAD := [true, true, true, false, false, false]   # true = 该砍
const KIND_NAME := ["账单", "电诈电话", "借钱", "美食", "游戏卡带", "心爱的女孩"]

# --- layout / timing --------------------------------------------------------
const STRIKE := Vector2(640.0, 332.0)   # 中央判定点
const TRAVEL_BAD := 2.0                  # 坏东西:快(飞入拍数少→凶猛直冲)
const TRAVEL_GOOD := 4.0                 # 心头好:慢(老早飘出来,绕着飞)
const R_SPAWN := 820.0                   # 出生点离中心半径(屏外)
const NOTE_SLOTS := 7
const JUDGE_OFFSET := 0.75
const MIN_PERFECT_MS := 110.0
const MIN_GOOD_MS := 220.0

# --- chart ------------------------------------------------------------------
## b=账单 s=电诈 l=借钱(都该砍) f=美食 g=游戏 m=女孩(都别砍) -=空 E=结束
const CHART := [
	# 教学:先来几个账单(该砍)
	"b", "-", "b", "-", "s", "-",
	# 混入心头好(别砍):美食
	"b", "f", "-", "s", "-", "l", "-",
	# 开始混合,逼你分辨
	"b", "-", "g", "s", "-", "b", "m", "-",
	"l", "b", "-", "f", "s", "-", "g", "b", "-",
	# 密集
	"b", "s", "l", "m", "b", "s", "f", "b", "-",
	"s", "b", "g", "l", "b", "m", "s", "b", "-",
	"E",
]

# --- state ------------------------------------------------------------------
var rent_music: RentMusic
var current_beat := 0
var last_judged_beat := -1
var current_beat_data: Dictionary = {}
var prev_beat_data: Dictionary = {}
var queue: Array[Dictionary] = []
var chart_i := 0
var spawn_count := 0
var hidden_beat := -999          # 被砍的那一拍:k==0 的图标隐藏(改由 SliceFx 表现)

var key_held := false

# --- juice ------------------------------------------------------------------
var shake := 0.0
var flash := 0.0                 # 全屏刀光闪
var ring_pulse := 0.0
var btn_pop := 0.0

# --- nodes ------------------------------------------------------------------
var stage: Control
var arena: _Arena
var katana: _Katana
var strike_ring: _StrikeRing
var slice_fx: _SliceFx
var item_tiles: Array = []
var hit_button: Button
var intro_layer: ColorRect
var intro_label: Label

# --- sfx --------------------------------------------------------------------
var snd_slash: AudioStreamWAV
var snd_hit: AudioStreamWAV
var snd_wrong: AudioStreamWAV
var snd_pass: AudioStreamWAV
var snd_count: AudioStreamWAV
var snd_warn_bad: AudioStreamWAV    # 坏东西来袭:紧张"嗖"
var snd_warn_good: AudioStreamWAV   # 心头好飘来:柔"叮"


# ===========================================================================
# LevelBase hooks
# ===========================================================================
func make_cfg() -> Dictionary:
	return {
		"duration_ms": 46000.0, "start_bpm": 80.0, "end_bpm": 104.0,
		"bpm_curve_exp": 1.5, "subdivisions": 4,
	}


func _auto_finish() -> bool:
	return false   # 谱面驱动结束


func _make_music() -> Node:
	rent_music = RentMusic.new()
	return rent_music


func _conf() -> Dictionary:
	return {
		"score_caption": "房租",
		"text_col": COL_INK, "muted_col": COL_MUTED,
		"countdown_col": COL_RED, "penalty_col": COL_RED,
		"fever_text": "刀魂 FEVER!!", "fever_col": COL_RED, "fever_fill": COL_GOLD,
		"fever_overlay": Color(0.9, 0.15, 0.15), "fever_overlay_a": 0.07,
		"result_bg": COL_DARK, "result_border": COL_RED,
		"title_col": COL_GOLD, "lose_col": COL_RED,
		"eval_bg": Color("1c1622"), "eval_border": Color("3a2a3a"),
		"again_label": "再战一场",
		"score_fmt": "房租 %d　命中 %d%%　最高 %d%s",
		"grade_cols": {"S": COL_RED, "A": COL_GOLD, "B": COL_GREEN, "C": COL_INK, "D": COL_MUTED},
	}


func _build_level() -> void:
	_build_scene()
	_build_items()
	_build_katana()
	_build_button()
	_build_intro()


func _build_sfx() -> void:
	snd_slash = tone(900.0, 1700.0, 0.07, "noise", 0.35)   # 挥刀风声
	snd_hit = tone(520.0, 180.0, 0.12, "sine", 0.5)        # 劈中
	snd_wrong = tone(180.0, 90.0, 0.22, "sawtooth", 0.4)   # 砍错/失误
	snd_pass = tone(700.0, 950.0, 0.08, "triangle", 0.4)   # 守住(忍住)
	snd_count = tone(440.0, 0.0, 0.07, "square", 0.4)
	snd_warn_bad = tone(280.0, 1150.0, 0.11, "sawtooth", 0.32)   # 来袭:上行嗖
	snd_warn_good = tone(880.0, 1480.0, 0.13, "sine", 0.26)      # 飘来:柔叮


func _make_heart() -> Control:
	var d := _CoinHeart.new()
	d.custom_minimum_size = Vector2(30, 30)
	return d


func _reset_level() -> void:
	current_beat = 0
	last_judged_beat = -1
	spawn_count = 0
	hidden_beat = -999
	key_held = false
	shake = 0.0
	flash = 0.0
	ring_pulse = 0.0
	btn_pop = 0.0
	prepare_beats()


func _enter_start() -> void:
	_enter_intro()


func _begin_play() -> void:
	set_tiles_visible(true)
	set_feedback("出刀!", COL_RED)


func _on_space(pressed: bool) -> void:
	if pressed:
		key_held = true
		if phase == "intro":
			_enter_countdown()
		else:
			_press_down()
	else:
		key_held = false


func _extra_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and phase == "intro":
		_enter_countdown()
		return true
	return false


func _countdown_tick(last: bool) -> void:
	play_sfx(snd_hit if last else snd_count, -8.0)


func _advance(_delta: float) -> void:
	_layout_items()
	bpm_label.text = str(roundi(conductor.bpm()))


func _on_beat(_cycle_index: int) -> void:
	if phase != "running":
		return
	_resolve_boundary()
	if phase != "running":
		return
	prev_beat_data = current_beat_data
	current_beat_data = queue.pop_front()
	ensure_queue()
	current_beat += 1
	# 临近谱面结束:音乐提前收束
	if rent_music and not rent_music.finale:
		for q in queue:
			if q.get("end", false):
				rent_music.finale = true
				break
	if current_beat_data.get("end", false):
		_start_outro()


func _outro_fx() -> void:
	set_feedback("收刀~", COL_GOLD)
	flash = 1.0


func _verdict(hearts_lost: int, won: bool) -> Dictionary:
	if won:
		match hearts_lost:
			0: return {"rank": "房租の主人", "eval": "一刀不错,房东看了都想给你打折"}
			1: return {"rank": "守财剑客", "eval": "差点破财,好在刀快,这月房租稳了"}
			_: return {"rank": "勉强交租", "eval": "砍歪了几刀,押金是保住了"}
	if app and app.extreme:
		return {"rank": "断舍离", "eval": "连心爱的女孩都砍了…你还好吗"}
	return {"rank": "房租没了", "eval": "敌人太多没挡住,这月又要吃土了QAQ"}


# ===========================================================================
# Beat generation
# ===========================================================================
func make_beat() -> Dictionary:
	if chart_i >= CHART.size():
		return {"kind": -1, "bad": false, "should_press": false, "angle": 0.0, "end": true}
	var tok: String = CHART[chart_i]
	chart_i += 1
	if tok == "E":
		return {"kind": -1, "bad": false, "should_press": false, "angle": 0.0, "end": true}
	if tok == "-":
		return {"kind": -1, "bad": false, "should_press": false, "angle": 0.0}
	var k := _tok_kind(tok)
	var bad: bool = KIND_BAD[k]
	# 四面八方:黄金角分散来袭方向(确定性 → 谱面每次一致)
	var angle := fposmod(float(spawn_count) * 2.3998277 - PI * 0.5, TAU)
	spawn_count += 1
	return {"kind": k, "bad": bad, "should_press": bad, "angle": angle}


func _tok_kind(tok: String) -> int:
	match tok:
		"b": return BILL
		"s": return SCAM
		"l": return LOAN
		"f": return FOOD
		"g": return GAME
		"m": return GIRL
		_: return -1


func ensure_queue() -> void:
	while queue.size() < 5:
		queue.append(make_beat())


func prepare_beats() -> void:
	queue = []
	chart_i = 0
	ensure_queue()
	current_beat_data = queue.pop_front()
	prev_beat_data = {}
	ensure_queue()


# ===========================================================================
# Judging
# ===========================================================================
func _press_down() -> void:
	if phase != "running":
		return
	btn_pop = 1.0
	var cur := current_beat_data
	var ck := int(cur.get("kind", -1))
	# 武士朝来袭方向横切(默认朝上)
	katana.slash = 1.0
	katana.slash_angle = float(cur.get("angle", -1.5708)) if ck >= 0 else -1.5708
	play_sfx(snd_slash, -10.0)

	var d := _judge_delta()
	# 太早/太晚:空砍,无害,不消耗这一拍
	if d > good_window():
		return
	if last_judged_beat == current_beat:
		return
	last_judged_beat = current_beat

	var k := int(cur.get("kind", -1))
	if k < 0:
		return   # 砍在空拍(窗口内),无害
	if not bool(cur.get("bad", false)):
		# 砍了心头好 = 失误
		apply_penalty("不能砍%s!" % KIND_NAME[k])
		return
	# 该砍的:按时序给 Perfect/Good
	if d <= perfect_window():
		_slice("Perfect", 120, cur)
	else:
		_slice("Good", 80, cur)


func _slice(kind: String, points: int, cur: Dictionary) -> void:
	_add_score(points)
	_fever_hit()
	play_sfx(snd_hit)
	set_feedback("%s 斩!" % kind, COL_GOLD if kind == "Perfect" else COL_GREEN)
	flash = maxf(flash, 0.8 if kind == "Perfect" else 0.5)
	hidden_beat = current_beat
	slice_fx.emit(int(cur.get("kind", -1)), STRIKE, kind == "Perfect", float(cur.get("angle", 0.0)))


func _resolve_boundary() -> void:
	if phase != "running":
		return
	var cur := current_beat_data
	if last_judged_beat == current_beat:
		return
	last_judged_beat = current_beat
	var k := int(cur.get("kind", -1))
	if k < 0:
		return   # 空拍
	if bool(cur.get("bad", false)):
		# 该砍没砍 -> 房租没了
		apply_penalty("%s没挡住!" % KIND_NAME[k])
	else:
		# 心头好没砍 -> 守住了
		_keep(k)


func _keep(k: int) -> void:
	_add_score(40)
	_fever_hit()
	play_sfx(snd_pass, -6.0)
	set_feedback("守住了 %s" % KIND_NAME[k], COL_GREEN)


func _judge_delta() -> float:
	return absf(conductor.beat_phase() - JUDGE_OFFSET) * conductor.cycle_duration


func perfect_window() -> float:
	return maxf(MIN_PERFECT_MS, conductor.cycle_duration * 0.13)


func good_window() -> float:
	return maxf(MIN_GOOD_MS, conductor.cycle_duration * 0.26)


func apply_penalty(text: String) -> void:
	play_sfx(snd_wrong)
	shake = maxf(shake, 11.0)
	super.apply_penalty(text)


# ===========================================================================
# Layout (arc)
# ===========================================================================
func _layout_items() -> void:
	var bp := conductor.beat_phase()
	for slot in NOTE_SLOTS:
		var k := slot - 1
		var note := _note_at(k)
		var tile: _Item = item_tiles[slot]
		if note.is_empty() or note.get("end", false) or int(note.get("kind", -1)) < 0:
			tile.visible = false
			continue
		var bad := bool(note.get("bad", false))
		var tv: float = TRAVEL_BAD if bad else TRAVEL_GOOD
		var u := float(k) + JUDGE_OFFSET - bp
		if u > tv + 0.2 or u < -0.8:
			tile.visible = false
			continue
		if k == 0 and hidden_beat == current_beat:
			tile.visible = false
			continue
		# 进场报一次来袭音(坏=嗖,好=叮)
		if not bool(note.get("announced", false)):
			note["announced"] = true
			play_sfx(snd_warn_bad if bad else snd_warn_good, -12.0)
		tile.visible = true
		tile.set_kind(int(note.get("kind", -1)))
		tile.bad = bad
		var pos := _path_pos(note, u)
		tile.position = pos - tile.size * 0.5
		# 临近判定点放大一点
		var near := clampf(1.0 - absf(u), 0.0, 1.0)
		tile.scale = Vector2.ONE * (0.85 + 0.25 * near)


func _note_at(k: int) -> Dictionary:
	if k == -1:
		return prev_beat_data
	if k == 0:
		return current_beat_data
	if k >= 1 and k - 1 < queue.size():
		return queue[k - 1]
	return {}


func _path_pos(note: Dictionary, u: float) -> Vector2:
	var bad := bool(note.get("bad", false))
	var ang := float(note.get("angle", 0.0))
	var tv: float = TRAVEL_BAD if bad else TRAVEL_GOOD
	var t := clampf(1.0 - u / tv, 0.0, 1.35)
	var spawn := STRIKE + Vector2(cos(ang), sin(ang)) * R_SPAWN
	if bad:
		# 凶猛直冲
		return spawn.lerp(STRIKE, t)
	# 心头好:绕个弧 + 轻飘
	var mid := spawn.lerp(STRIKE, 0.5)
	var ctrl := mid + Vector2(-sin(ang), cos(ang)) * 190.0
	var p := _bezier(spawn, ctrl, STRIKE, t)
	p += Vector2(sin(t * TAU * 1.5 + ang) * 11.0, cos(t * TAU * 1.2) * 9.0) * (1.0 - t)
	return p


func _bezier(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var it := 1.0 - t
	return a * (it * it) + b * (2.0 * it * t) + c * (t * t)


func set_tiles_visible(v: bool) -> void:
	for tile in item_tiles:
		tile.visible = v


# ===========================================================================
# Build
# ===========================================================================
func _build_scene() -> void:
	arena = _Arena.new()
	arena.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(arena)

	stage = Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.pivot_offset = Vector2(640, 360)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

	# 中央判定环(敌人飞到这里出刀)
	strike_ring = _StrikeRing.new()
	strike_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	strike_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strike_ring.center = STRIKE
	stage.add_child(strike_ring)


func _build_items() -> void:
	for i in NOTE_SLOTS:
		var tile := _Item.new()
		tile.size = Vector2(88, 96)
		tile.pivot_offset = Vector2(44, 48)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.visible = false
		stage.add_child(tile)
		item_tiles.append(tile)

	# 砍开特效层(在图标之上)
	slice_fx = _SliceFx.new()
	slice_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slice_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(slice_fx)


func _build_katana() -> void:
	katana = _Katana.new()
	katana.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	katana.mouse_filter = Control.MOUSE_FILTER_IGNORE
	katana.strike = STRIKE
	stage.add_child(katana)


func _build_button() -> void:
	hit_button = Button.new()
	hit_button.text = "出刀!"
	hit_button.custom_minimum_size = Vector2(220, 84)
	hit_button.add_theme_font_size_override("font_size", 30)
	hit_button.focus_mode = Control.FOCUS_NONE
	hit_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := StyleBoxFlat.new()
	normal.bg_color = COL_DARK
	normal.set_border_width_all(4)
	normal.border_color = COL_RED
	normal.set_corner_radius_all(10)
	hit_button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color("2a1622")
	hit_button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = COL_RED
	hit_button.add_theme_stylebox_override("pressed", pressed)
	for s in ["font_color", "font_hover_color"]:
		hit_button.add_theme_color_override(s, COL_RED)
	hit_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	hit_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hit_button.position = Vector2(-110, -96)
	hit_button.pivot_offset = Vector2(110, 42)
	hit_button.button_down.connect(func() -> void:
		_press_down())
	add_child(hit_button)


func _build_intro() -> void:
	intro_layer = ColorRect.new()
	intro_layer.color = Color(0, 0, 0, 0.6)
	intro_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro_layer.z_index = 5
	intro_layer.visible = false
	add_child(intro_layer)

	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_DARK
	sb.set_border_width_all(4)
	sb.border_color = COL_RED
	sb.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(720, 240)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.position = Vector2(-360, -120)
	intro_layer.add_child(card)

	intro_label = Label.new()
	intro_label.add_theme_font_size_override("font_size", 25)
	intro_label.add_theme_color_override("font_color", COL_INK)
	intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	intro_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro_label.offset_left = 34
	intro_label.offset_right = -34
	card.add_child(intro_label)

	var hint := Label.new()
	hint.text = "空格 / 点击 开始"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", COL_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -34
	intro_layer.add_child(hint)


# ===========================================================================
# Intro
# ===========================================================================
func _enter_intro() -> void:
	phase = "intro"
	intro_label.text = "月底了,房租的敌人从四面八方飞来!\n凶猛直冲的[账单·电诈·借钱]——出刀劈了它;\n慢悠悠飘来的[美食·游戏·心爱的女孩]——千万别砍!" \
		if not (app and app.extreme) else "极限:敌人更快更密,看准快慢、听声辨位,别手软!"
	intro_layer.visible = true
	countdown_label.visible = false
	set_tiles_visible(false)
	set_feedback("", COL_MUTED)


func _enter_countdown() -> void:
	super()
	if intro_layer:
		intro_layer.visible = false
	set_tiles_visible(false)


# ===========================================================================
# Per-frame juice
# ===========================================================================
func _juice(delta: float) -> void:
	var p := conductor.pulse() if conductor.running else 0.0
	shake = move_toward(shake, 0.0, delta * 55.0)
	flash = move_toward(flash, 0.0, delta * 3.2)
	btn_pop = move_toward(btn_pop, 0.0, delta * 5.0)

	stage.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
	arena.pulse = p
	arena.flash = flash
	strike_ring.pulse = p
	katana.advance(delta)

	hit_button.scale = Vector2.ONE * (1.0 + 0.15 * btn_pop)
	hit_button.modulate = Color.WHITE.lerp(COL_RED, btn_pop * 0.5)


# ===========================================================================
# Inner visual classes
# ===========================================================================

## 飞来的物件卡片(账单/电诈/借钱/美食/游戏/女孩)
class _Item:
	extends Control

	var kind := -1
	var bad := false
	var t := 0.0

	const SYM := ["￥", "诈", "借", "餐", "游", "爱"]
	const ACC := [
		Color("e23b3b"),   # 账单 红
		Color("ff7043"),   # 电诈 橙红
		Color("ffca28"),   # 借钱 黄
		Color("ff9800"),   # 美食 橙
		Color("42a5f5"),   # 游戏 蓝
		Color("ec407a"),   # 女孩 粉
	]

	func set_kind(k: int) -> void:
		if k != kind:
			kind = k
			queue_redraw()

	func _process(delta: float) -> void:
		t += delta
		if visible:
			queue_redraw()

	func _draw() -> void:
		if kind < 0:
			return
		# 动势:坏东西高频抖(凶),心头好慢摇(柔)
		var off := Vector2(sin(t * 47.0), cos(t * 53.0)) * 1.7 if bad \
			else Vector2(sin(t * 3.0), 0.0) * 2.6
		draw_set_transform(off, 0.0, Vector2.ONE)
		var w := size.x
		var h := size.y
		var acc: Color = ACC[kind]
		# 卡片
		draw_rect(Rect2(3, 3, w - 6, h - 6), Color("f3ece0"))
		draw_rect(Rect2(3, 3, w - 6, h - 6), Color("2b2018"), false, 3.0)
		# 顶条
		draw_rect(Rect2(3, 3, w - 6, 14), acc)
		# 大符号
		var font := ThemeDB.fallback_font
		var sym: String = SYM[kind]
		var fs := 40
		var ts := font.get_string_size(sym, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, Vector2(w * 0.5 - ts.x * 0.5, h * 0.5 + ts.y * 0.28 + 6),
			sym, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, acc)


## 武士刀:中下方竖刀,出刀时一道斜向刀光扫过判定点
class _Katana:
	extends Control

	var strike := Vector2(640, 332)
	var slash := 0.0            # 1 -> 0
	var slash_angle := -1.5708  # 来袭方向(横切垂直于它)

	func advance(delta: float) -> void:
		if slash > 0.0:
			slash = move_toward(slash, 0.0, delta * 4.5)
			queue_redraw()

	func _draw() -> void:
		var base := Vector2(strike.x, 700.0)
		# 刀柄
		draw_line(base, base + Vector2(0, -46), Color("2b2018"), 12.0)
		# 刀身(底部指向中心)
		var blade_top := Vector2(strike.x, strike.y + 58.0)
		draw_line(base + Vector2(0, -44), blade_top, Color("c9d2dc"), 8.0)
		draw_line(base + Vector2(0, -44), blade_top, Color("eef3f8"), 3.0)
		# 出刀:朝来袭方向横切的刀光(垂直于来袭方向)
		if slash > 0.0:
			var a := slash
			var perp := Vector2(-sin(slash_angle), cos(slash_angle))
			var p1 := strike - perp * 300.0 * a
			var p2 := strike + perp * 300.0 * a
			draw_line(p1, p2, Color(0.9, 0.23, 0.23, a * 0.8), 14.0 * a + 2.0)
			draw_line(p1, p2, Color(1, 1, 1, a), 6.0 * a + 1.0)


## 中央判定环(敌人飞到这里)
class _StrikeRing:
	extends Control

	var center := Vector2(640, 332)
	var pulse := 0.0

	func _draw() -> void:
		var r := 46.0 + pulse * 8.0
		var a := 0.35 + 0.35 * pulse
		# 外光晕
		draw_arc(center, r, 0, TAU, 40, Color(1.0, 0.82, 0.4, a * 0.7), 3.0)
		draw_arc(center, r - 7.0, 0, TAU, 40, Color(0.9, 0.23, 0.23, a * 0.5), 2.0)
		# 中心准星
		draw_line(center + Vector2(-10, 0), center + Vector2(10, 0), Color(1, 1, 1, a), 2.0)
		draw_line(center + Vector2(0, -10), center + Vector2(0, 10), Color(1, 1, 1, a), 2.0)


## 砍开特效:把物件分成两半飞散 + 白色刀闪
class _SliceFx:
	extends Control

	var parts: Array = []

	const ACC := [
		Color("e23b3b"), Color("ff7043"), Color("ffca28"),
		Color("ff9800"), Color("42a5f5"), Color("ec407a"),
	]

	func emit(kind: int, at: Vector2, perfect: bool, angle: float) -> void:
		var col: Color = ACC[kind] if kind >= 0 else Color.WHITE
		var spread := 320.0 if perfect else 240.0
		var axis := Vector2(cos(angle), sin(angle))   # 两半沿来袭轴分开
		for s in [-1.0, 1.0]:
			parts.append({
				"pos": at + axis * (s * 8.0),
				"vel": axis * (s * spread) + Vector2(0, -90),
				"rot": 0.0,
				"rspd": s * 7.0,
				"life": 0.7, "max": 0.7,
				"col": col,
			})
		# 刀闪(横切方向)
		parts.append({
			"pos": at, "vel": Vector2.ZERO, "rot": 0.0, "rspd": 0.0,
			"life": 0.18, "max": 0.18, "col": Color.WHITE, "flash": true, "ang": angle,
		})
		queue_redraw()

	func _process(delta: float) -> void:
		if parts.is_empty():
			return
		var alive: Array = []
		for p in parts:
			p["life"] -= delta
			if p["life"] <= 0.0:
				continue
			if not p.get("flash", false):
				var vel: Vector2 = p["vel"]
				vel.y += 620.0 * delta
				p["vel"] = vel
				p["pos"] = Vector2(p["pos"]) + vel * delta
				p["rot"] = float(p["rot"]) + float(p["rspd"]) * delta
			alive.append(p)
		parts = alive
		queue_redraw()

	func _draw() -> void:
		for p in parts:
			var a: float = clampf(p["life"] / p["max"], 0.0, 1.0)
			if p.get("flash", false):
				var fp: Vector2 = p["pos"]
				var fa: float = p.get("ang", 0.0)
				var perp := Vector2(-sin(fa), cos(fa)) * 300.0
				draw_line(fp - perp, fp + perp, Color(1, 1, 1, a), 8.0)
				continue
			var c: Color = p["col"]
			var pos: Vector2 = p["pos"]
			var rot: float = p["rot"]
			# 半块碎片(旋转的小方)
			var hw := 22.0
			var pts := PackedVector2Array()
			for corner in [Vector2(-hw, -hw), Vector2(hw, -hw), Vector2(hw, hw), Vector2(-hw, hw)]:
				pts.append(pos + corner.rotated(rot))
			draw_colored_polygon(pts, Color(c.r, c.g, c.b, a))


## 夜色道场背景:渐变夜空 + 大月 + 远景 + 飘落账单
class _Arena:
	extends Control

	var pulse := 0.0
	var flash := 0.0
	var t := 0.0
	var papers: Array = []

	const COL_TOP := Color("0a0a14")
	const COL_BOT := Color("1c1424")

	func _ready() -> void:
		for i in 14:
			papers.append({
				"x": randf_range(0, 1280),
				"y": randf_range(0, 720),
				"spd": randf_range(20, 60),
				"sway": randf() * TAU,
				"size": randf_range(10, 22),
			})

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var w := 1280.0
		var h := 720.0
		# 夜空渐变
		for i in 12:
			var frac := float(i) / 12.0
			draw_rect(Rect2(0, i * h / 12.0, w, h / 12.0 + 1), COL_TOP.lerp(COL_BOT, frac))
		# 大月(挪到右上,别压判定点)
		var moon := Vector2(1010, 150)
		draw_circle(moon, 95.0, Color(0.95, 0.9, 0.8, 0.05))
		draw_circle(moon, 74.0, Color(0.98, 0.95, 0.88, 0.16))
		draw_circle(moon - Vector2(22, 10), 60.0, COL_TOP.lerp(COL_BOT, 0.5))
		# 判定点柔和聚光,聚焦中央
		draw_circle(Vector2(640, 332), 120.0, Color(1.0, 0.85, 0.5, 0.04 + flash * 0.12))
		# 远景屋檐剪影
		draw_rect(Rect2(0, h - 150, w, 150), Color("0d0a14"))
		for i in 9:
			var bx := i * 150.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(bx - 10, h - 150), Vector2(bx + 75, h - 186),
				Vector2(bx + 160, h - 150),
			]), Color("0a0810"))
		# 地面光带
		for i in 5:
			var a := 0.05 * (1.0 - float(i) / 5.0)
			draw_rect(Rect2(0, h - 120 - i * 26, w, 26), Color(0.9, 0.2, 0.2, a))
		# 飘落的账单(氛围)
		for pp in papers:
			var px: float = pp["x"] + sin(t * 0.7 + pp["sway"]) * 22.0
			var py: float = fposmod(pp["y"] + t * pp["spd"], h + 40.0)
			var sz: float = pp["size"]
			draw_rect(Rect2(px, py, sz, sz * 1.3), Color(0.9, 0.88, 0.82, 0.08))


## 钱币血量图标(存款):满=金币￥,失去=暗
class _CoinHeart:
	extends Control

	var lost := false

	func set_lost(v: bool) -> void:
		lost = v
		queue_redraw()

	func _draw() -> void:
		var a := 0.22 if lost else 1.0
		var c := size * 0.5
		draw_circle(c, 12.0, Color(0.78, 0.6, 0.15, a))
		draw_circle(c, 9.0, Color(1.0, 0.82, 0.3, a))
		if not lost:
			var font := ThemeDB.fallback_font
			draw_string(font, c + Vector2(-5, 5), "￥", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(0.4, 0.28, 0.05, a))
