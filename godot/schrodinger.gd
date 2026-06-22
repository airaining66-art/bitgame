extends LevelBase
## 1-3 薛定谔告白 — pixel-art candlelit-dinner confession.
## Two INDEPENDENT lanes scroll intrusive "thoughts": top = food/喜好 (fast,
## eighth grid), bottom = faces/角色 (slow, quarter grid). Each play randomly
## draws today's date (梓涵 / 如烟) + her favourite dish (烤鸡 / 沙拉).
##
## Press rule: a tick is pressable iff a CORRECT icon is at center AND no WRONG
## icon is — only-A ✓, only-C ✓, A+C ✓, but A+wrong-food ✗, wrong-face+C ✗
## (press on a wrong icon = "喊错名字"). The chart (which ticks are pressable)
## is FIXED; the random draw only reskins the sprites.
##
## Mechanics: precise on-beat presses + 双击 (on+off both correct) + 連打-roll
## boxes (free mash, more taps = more score) + 长按 holds (both lanes together).
## Feedback: two diners with speech bubbles — you "say" your press on the left,
## she answers 🙂 / 😐 on the right (emoji.png). Pixel juice: nearest-filtered
## sprites, pixel-block breathing lights, and a zoom-punch on every hit.

# --- palette (warm candlelight) --------------------------------------------
const COL_TEXT := Color("f3e2c7")
const COL_MUTED := Color("b59b78")
const COL_GOLD := Color("f4c45a")
const COL_ROSE := Color("e0708a")
const COL_GREEN := Color("8fcf7a")
const COL_RED := Color("e2584f")
const COL_JUDGE := Color("ffe9b0")

# --- layout / timing --------------------------------------------------------
const CENTER_X := 640.0
const TOP_Y := 235.0          # food lane (fast)
const BOT_Y := 420.0          # face lane (slow)
const TILE := 120.0
const SPACING := 150.0        # pixels per eighth-note of continuous scroll
const LEAD := 6               # eighth-notes of lead-in before the first tick
const JUDGE_E := 1.5          # eighths a tick leads the clock (on-beats hit the kick)
const MIN_PERFECT_MS := 100.0
const MIN_GOOD_MS := 190.0
const MIN_TRAP_MS := 125.0
const BABY_SPEED_SCALE := 1.5
const BABY_RAMP_PER_SEC := 2.8

# Icon cell states / lane categories (also the sprite-sheet row).
const NONE := 0
const CORRECT := 1
const WRONG := 2
const FOOD := 0
const FACE := 1
# Tick kinds.
const K_NORMAL := 0
const K_HOLD := 1
const K_ROLL := 2
const K_BABY := 3
# emoji.png frames (top→bottom): heart / speechless / smiley.
const EMO_HEART := 0
const EMO_AWKWARD := 1
const EMO_SMILE := 2

## Fixed chart. Entries are either a 3-char quarter `[face, top-on, top-off]`
## (c=correct / x=wrong / .=empty), or "HOLD:n" / "ROLL:n" (n beats, both/one
## lane), or "E" (end). Difficulty steps up past 1-1/1-2: denser, more traps,
## plus holds and 連打 rolls.
const CHART := [
	# date-night jitters: staggered face/food calls rather than 1-1 style singles
	"c..", "...", "..c", ".c.", "c.c", "...", "..x", ".cc", "c..",
	# off-beats & double-taps
	"..c", "c.c", ".c.", "...", "..x", ".cc", "...", "c..", "..c", ".cc",
	# traps you must NOT press
	".x.", "c.c", "cx.", "...", "..x", "..c", "x.c", ".cc", "c.x", "...",
	"x..", ".c.", "cx.", "...", "..x", "..c", "...", "BABY:6", "...",
	# 长按: both lanes held together (clean entry), then a breather
	"HOLD:3", "...", "..c", "c.c",
	# fixed-beat 連打 (precise consecutive eighths), with a visible pickup
	"c..", ".cc", ".cc", "...", "..x", "..c", "...",
	# free 連打-roll box (mash!)
	"ROLL:3", "...", "c.c", "..x", "..c", "BABY:6", "...",
	# climax: traps + doubles + a shorter hold
	"..c", "cx.", "...", "..x", ".cc", "x.c", "c.c", ".x.", "c.x", "..c",
	"HOLD:2", ".cc", "...", "..x", "BABY:6", "...",
	# finale wind-down
	"c.c", "...", "..x", "..c", ".c.", "...", "c..", "E",
]

# --- random draw (today's date + favourite) ---------------------------------
const FACE_DATA := [{"name": "梓涵"}, {"name": "如烟"}]   # 0 black hair / 1 white hair
const FOOD_DATA := [{"name": "烤鸡"}, {"name": "沙拉"}]   # 0 roast chicken / 1 salad

var face_correct := 0
var face_wrong := 1
var food_correct := 0
var food_wrong := 1
var girls_tex: Texture2D
var emoji_tex: Texture2D
var baby_tex: Texture2D

# --- grid (built from CHART) ------------------------------------------------
var g_top: Array[int] = []
var g_bot: Array[int] = []
var g_press: Array[bool] = []
var g_kind: Array[int] = []
var judged: Array[bool] = []
var n_ticks := 0
var pass_g := 0
var hold_segs: Array = []       # [{s,e}] inclusive tick range
var roll_segs: Array = []
var baby_segs: Array = []
var hold_done: Array[bool] = []
var hold_started: Array[bool] = []
var roll_done: Array[bool] = []
var baby_done: Array[bool] = []
var baby_started: Array[bool] = []
var romance: Romance

# --- state (level-specific) -------------------------------------------------
var shake := 0.0
var zoom_punch := 0.0
var top_flash := 0.0
var bot_flash := 0.0
var top_flash_col := COL_JUDGE
var bot_flash_col := COL_JUDGE
var btn_pop := 0.0
var key_held := false
var btn_held := false
var extreme_baby_mode := false
var baby_active := false
var baby_idx := -1
var baby_flash := 0.0

# hold / roll runtime
var hold_active := false
var hold_idx := -1
var hold_savor_g := -1
var roll_active := false
var roll_idx := -1
var roll_taps := 0

# speech-bubble state
var idle_side := 0
var bl_kind := "dots"
var bl_timer := 0.0
var br_kind := "dots"
var br_timer := 0.0

# --- nodes ------------------------------------------------------------------
var stage: Control
var dinner: _Dinner
var rings: _Rings
var caps: _Caps
var baby_overlay: ColorRect
var baby_avatar: _BabyIcon
var baby_tiles: Array = []
var bubble_l: _Bubble
var bubble_r: _Bubble
var beat_flash: ColorRect
var top_tiles: Array = []
var bot_tiles: Array = []
var hearts_fx: Array = []
var hearts_fx_i := 0
var hit_button: Button
var hint_panel: Panel
var hint_face: _Icon
var hint_food: _Icon
var hint_label: Label
var intro_layer: ColorRect
var intro_face: _Icon
var intro_food: _Icon
var intro_text: RichTextLabel

# --- sfx --------------------------------------------------------------------
var snd_say: AudioStreamWAV
var snd_miss: AudioStreamWAV
var snd_heart: AudioStreamWAV


func make_cfg() -> Dictionary:
	return {
		"duration_ms": 42000.0, "start_bpm": 84.0, "end_bpm": 116.0,
		"bpm_curve_exp": 1.5, "subdivisions": 4,
	}


# ===========================================================================
# LevelBase hooks
# ===========================================================================
func _auto_finish() -> bool:
	return false   # the chart (pass_g >= n_ticks) ends the level, not the clock


func _make_music() -> Node:
	romance = Romance.new()
	return romance


func _make_heart() -> Control:
	var d := _HeartIcon.new()
	d.custom_minimum_size = Vector2(32, 32)
	return d


func _conf() -> Dictionary:
	return {
		"score_caption": "心动值",
		"text_col": COL_TEXT, "muted_col": COL_MUTED,
		"countdown_col": COL_GOLD, "penalty_col": COL_RED,
		"feedback": {"preset": Control.PRESET_CENTER, "left": -300.0, "right": 300.0, "top": 64.0, "bottom": 124.0},
		"fever_text": "心动 FEVER!!", "fever_font": 64, "fever_col": COL_ROSE, "fever_fill": COL_GOLD,
		"fever_overlay": Color(1.0, 0.5, 0.35), "fever_overlay_a": 0.08,
		"result_bg": Color("2a1018"), "result_border": COL_GOLD,
		"title_col": COL_GOLD, "lose_col": COL_RED,
		"eval_bg": Color("3a1622"), "eval_border": Color("5a2a38"),
		"again_label": "再表白一次",
		"score_fmt": "心动值 %d　命中 %d%%　最高 %d%s",
		"grade_cols": {"S": COL_ROSE, "A": COL_GOLD, "B": COL_GREEN, "C": COL_TEXT, "D": COL_MUTED},
	}


func _build_level() -> void:
	extreme_baby_mode = bool(level.get("extreme_baby_mode", false))
	_build_grid()
	_build_scene()
	_build_button()
	_build_hint()
	_build_intro()


# ===========================================================================
# Grid build (CHART -> per-eighth-tick arrays + hold/roll segments)
# ===========================================================================
func _build_grid() -> void:
	g_top = []
	g_bot = []
	g_kind = []
	hold_segs = []
	roll_segs = []
	baby_segs = []
	for entry in CHART:
		if entry == "E":
			break
		if entry.begins_with("BABY:"):
			if not extreme_baby_mode:
				continue
			var n := int(entry.substr(5))
			var s := g_top.size()
			for b in n:
				for half in 2:
					g_top.append(CORRECT)
					g_bot.append(CORRECT if half == 0 else NONE)
					g_kind.append(K_BABY)
			baby_segs.append({"s": s, "e": g_top.size() - 1})
			continue
		if entry.begins_with("HOLD:"):
			var n := int(entry.substr(5))
			var s := g_top.size()
			for b in n:
				for half in 2:
					g_top.append(CORRECT)
					g_bot.append(CORRECT if half == 0 else NONE)
					g_kind.append(K_HOLD)
			hold_segs.append({"s": s, "e": g_top.size() - 1})
			continue
		if entry.begins_with("ROLL:"):
			var n := int(entry.substr(5))
			var s := g_top.size()
			for b in n:
				for half in 2:
					g_top.append(CORRECT)
					g_bot.append(NONE)
					g_kind.append(K_ROLL)
			roll_segs.append({"s": s, "e": g_top.size() - 1})
			continue
		# normal 3-char quarter
		g_top.append(_tok(entry[1]))
		g_bot.append(_tok(entry[0]))
		g_kind.append(K_NORMAL)
		g_top.append(_tok(entry[2]))
		g_bot.append(NONE)
		g_kind.append(K_NORMAL)
	n_ticks = g_top.size()
	g_press = []
	judged = []
	for g in n_ticks:
		if g_kind[g] == K_BABY:
			g_press.append(true)
		elif g_kind[g] != K_NORMAL:
			g_press.append(false)   # holds/rolls judged separately
		else:
			var hc := g_top[g] == CORRECT or g_bot[g] == CORRECT
			var hw := g_top[g] == WRONG or g_bot[g] == WRONG
			g_press.append(hc and not hw)
		judged.append(false)
	hold_done = []
	hold_started = []
	for i in hold_segs.size():
		hold_done.append(false)
		hold_started.append(false)
	roll_done = []
	for i in roll_segs.size():
		roll_done.append(false)
	baby_done = []
	baby_started = []
	for i in baby_segs.size():
		baby_done.append(false)
		baby_started.append(false)


func _tok(c: String) -> int:
	match c:
		"c": return CORRECT
		"x": return WRONG
		_: return NONE


# ===========================================================================
# Build
# ===========================================================================
func _build_scene() -> void:
	var base := ColorRect.new()
	base.color = Color("140810")
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	girls_tex = _load_tex(["res://assets/girlsphoto.png"])
	emoji_tex = _load_tex(["res://assets/emoji.png"])
	baby_tex = _load_tex(["res://assets/baby.png"])

	stage = Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.pivot_offset = Vector2(640, 360)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

	dinner = _Dinner.new()
	dinner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(dinner)

	# Speech bubbles above the two diners (you on the left, her on the right).
	bubble_l = _Bubble.new()
	bubble_l.sheet = emoji_tex
	bubble_l.size = Vector2(120, 78)
	bubble_l.position = Vector2(250 - 60, 452)
	bubble_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(bubble_l)
	bubble_r = _Bubble.new()
	bubble_r.sheet = emoji_tex
	bubble_r.size = Vector2(120, 78)
	bubble_r.position = Vector2(1030 - 60, 452)
	bubble_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(bubble_r)

	rings = _Rings.new()
	rings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(rings)

	for i in 14:
		top_tiles.append(_make_tile())
	for i in 8:
		bot_tiles.append(_make_tile())

	caps = _Caps.new()
	caps.sheet = girls_tex
	caps.emoji = emoji_tex
	caps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(caps)

	baby_overlay = ColorRect.new()
	baby_overlay.color = Color(0, 0, 0, 0)
	baby_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	baby_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(baby_overlay)

	baby_avatar = _BabyIcon.new()
	baby_avatar.sheet = baby_tex
	baby_avatar.variant = 0
	baby_avatar.size = Vector2(TILE, TILE)
	baby_avatar.pivot_offset = Vector2(TILE, TILE) * 0.5
	baby_avatar.position = Vector2(CENTER_X - TILE * 0.5, BOT_Y - TILE * 0.5)
	baby_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	baby_avatar.visible = false
	stage.add_child(baby_avatar)

	for i in 14:
		var bt := _BabyIcon.new()
		bt.sheet = baby_tex
		bt.variant = 1
		bt.size = Vector2(TILE, TILE)
		bt.pivot_offset = Vector2(TILE, TILE) * 0.5
		bt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bt.visible = false
		stage.add_child(bt)
		baby_tiles.append(bt)

	for i in 8:
		var fx := _HeartFx.new()
		fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fx.visible = false
		stage.add_child(fx)
		hearts_fx.append(fx)

	# Whole-screen beat flash (extra juice), above the field.
	beat_flash = ColorRect.new()
	beat_flash.color = Color(1, 1, 1, 0)
	beat_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	beat_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(beat_flash)


func _make_tile() -> _Icon:
	var tile := _Icon.new()
	tile.sheet = girls_tex
	tile.size = Vector2(TILE, TILE)
	tile.pivot_offset = Vector2(TILE, TILE) * 0.5
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.visible = false
	stage.add_child(tile)
	return tile


func _build_button() -> void:
	hit_button = Button.new()
	hit_button.text = "♥ 表白"
	hit_button.custom_minimum_size = Vector2(220, 88)
	hit_button.add_theme_font_size_override("font_size", 28)
	hit_button.focus_mode = Control.FOCUS_NONE
	hit_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("3a1622")
	normal.set_border_width_all(4)
	normal.border_color = COL_ROSE
	normal.set_corner_radius_all(10)
	hit_button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color("4a1c2c")
	hit_button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = COL_ROSE
	hit_button.add_theme_stylebox_override("pressed", pressed)
	for s in ["font_color", "font_hover_color"]:
		hit_button.add_theme_color_override(s, COL_ROSE)
	hit_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	hit_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hit_button.position = Vector2(-110, -86)
	hit_button.pivot_offset = Vector2(110, 44)
	hit_button.button_down.connect(func() -> void:
		btn_held = true
		_press_down())
	hit_button.button_up.connect(func() -> void:
		btn_held = false
		_press_up())
	add_child(hit_button)


func _build_hint() -> void:
	hint_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2a1018")
	sb.set_border_width_all(2)
	sb.border_color = COL_ROSE
	sb.set_corner_radius_all(6)
	hint_panel.add_theme_stylebox_override("panel", sb)
	hint_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hint_panel.size = Vector2(214, 96)
	hint_panel.position = Vector2(-226, 70)
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_panel)

	var cap := Label.new()
	cap.text = "今晚 · 别想错"
	cap.add_theme_font_size_override("font_size", 14)
	cap.add_theme_color_override("font_color", COL_MUTED)
	cap.position = Vector2(12, 6)
	hint_panel.add_child(cap)

	hint_face = _Icon.new()
	hint_face.sheet = girls_tex
	hint_face.size = Vector2(54, 54)
	hint_face.position = Vector2(12, 32)
	hint_panel.add_child(hint_face)

	hint_food = _Icon.new()
	hint_food.sheet = girls_tex
	hint_food.size = Vector2(54, 54)
	hint_food.position = Vector2(72, 32)
	hint_panel.add_child(hint_food)

	hint_label = Label.new()
	hint_label.add_theme_font_size_override("font_size", 16)
	hint_label.add_theme_color_override("font_color", COL_TEXT)
	hint_label.position = Vector2(134, 34)
	hint_label.size = Vector2(76, 56)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_panel.add_child(hint_label)


func _build_intro() -> void:
	intro_layer = ColorRect.new()
	intro_layer.color = Color(0, 0, 0, 0.62)
	intro_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro_layer.visible = false
	add_child(intro_layer)

	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2a1018")
	sb.set_border_width_all(3)
	sb.border_color = COL_GOLD
	sb.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(500, 430)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.position = Vector2(-250, -215)
	intro_layer.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 28
	vb.offset_top = 26
	vb.offset_right = -28
	vb.offset_bottom = -26
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vb)

	var head := Label.new()
	head.text = "♥ 今晚的约会 ♥"
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", COL_GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(head)

	var icons := HBoxContainer.new()
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	icons.add_theme_constant_override("separation", 22)
	vb.add_child(icons)
	intro_face = _Icon.new()
	intro_face.sheet = girls_tex
	intro_face.custom_minimum_size = Vector2(132, 132)
	icons.add_child(intro_face)
	intro_food = _Icon.new()
	intro_food.sheet = girls_tex
	intro_food.custom_minimum_size = Vector2(110, 110)
	icons.add_child(intro_food)

	intro_text = RichTextLabel.new()
	intro_text.bbcode_enabled = true
	intro_text.fit_content = true
	intro_text.scroll_active = false
	intro_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_text.add_theme_font_size_override("normal_font_size", 22)
	intro_text.add_theme_color_override("default_color", COL_TEXT)
	intro_text.custom_minimum_size = Vector2(440, 120)
	intro_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(intro_text)

	var tip := Label.new()
	tip.text = "空格 / 点击 开始"
	tip.add_theme_font_size_override("font_size", 16)
	tip.add_theme_color_override("font_color", COL_MUTED)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tip)


# ===========================================================================
# Input (level-specific space / mouse-intro; base handles R / Esc / pause)
# ===========================================================================
func _on_space(pressed: bool) -> void:
	if pressed:
		key_held = true
		if phase == "intro":
			_begin_countdown()
		else:
			_press_down()
	else:
		key_held = false
		_press_up()


func _extra_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and phase == "intro":
		_begin_countdown()
		return true
	return false


func is_holding() -> bool:
	return key_held or btn_held


# ===========================================================================
# Judging (two independent lanes, quantised to the eighth grid)
# ===========================================================================
func eighth_dur_ms() -> float:
	return conductor.cycle_duration * 0.5


func clock_e() -> float:
	return 2.0 * (float(conductor.cycle_index) + conductor.beat_phase())


func cross_e(g: int) -> float:
	return float(g) + LEAD + JUDGE_E


func _margin_e() -> float:
	return good_window() / maxf(eighth_dur_ms(), 1.0) + 0.1


func perfect_window() -> float:
	return maxf(MIN_PERFECT_MS, eighth_dur_ms() * 0.20)


func good_window() -> float:
	return maxf(MIN_GOOD_MS, eighth_dur_ms() * 0.48)


func trap_window() -> float:
	return maxf(MIN_TRAP_MS, eighth_dur_ms() * 0.32)


func _press_down() -> void:
	if phase != "running":
		return
	btn_pop = 1.0
	shake = maxf(shake, 2.0)
	bl_kind = "press"   # you "say" your press on the left
	bl_timer = 0.4

	if hold_active:
		return   # already holding — extra taps do nothing

	# 1) free 連打-roll: every tap scores, more = better.
	if roll_active:
		roll_taps += 1
		score += 25 * (2 if fever_active else 1)
		combo += 1
		fever_gauge = minf(1.0, fever_gauge + 0.02)
		zoom_punch = maxf(zoom_punch, 0.03)
		_pop_heart(Vector2(CENTER_X, TOP_Y))
		br_kind = "heart"
		br_timer = 0.28
		bl_kind = "press"
		bl_timer = 0.28
		set_feedback("连击 ×%d!" % roll_taps, COL_GOLD)   # live tap counter
		play_sfx(snd_say, -6.0)
		update_hud()
		return

	# 2) route the press to whichever is NEARER — a normal note or the hold head
	#    (both gated by the good window). This stops a press meant for a note
	#    sitting beside a hold from accidentally grabbing the hold.
	var e := clock_e()
	var g := roundi(e - LEAD - JUDGE_E)
	var gw := good_window()
	var tw := trap_window()
	var best := -1
	var best_err := 1e9
	for cand in [g - 1, g, g + 1]:
		if cand < 0 or cand >= n_ticks or judged[cand] or not g_press[cand]:
			continue
		var err: float = absf(cross_e(cand) - e) * eighth_dur_ms()
		if err <= gw and err < best_err:
			best = cand
			best_err = err

	var hi := _current_hold()
	var hold_err := 1e9
	if hi >= 0 and not hold_done[hi] and not hold_started[hi]:
		hold_err = absf(cross_e(hold_segs[hi]["s"]) - e) * eighth_dur_ms()

	if best >= 0 and best_err <= hold_err:
		judged[best] = true
		_hit(best, best_err <= perfect_window())
		return
	if hold_err <= gw:
		_start_hold(hi)
		return

	# 3) a wrong / un-pressable icon sat at center -> you blurted it.
	for cand in [g - 1, g, g + 1]:
		if cand < 0 or cand >= n_ticks or judged[cand] or g_kind[cand] != K_NORMAL:
			continue
		var err: float = absf(cross_e(cand) - e) * eighth_dur_ms()
		if err <= tw and (g_top[cand] != NONE or g_bot[cand] != NONE):
			judged[cand] = true
			apply_penalty("喊错名字!")
			return

	_whiff()


func _press_up() -> void:
	if phase != "running" or not hold_active:
		return
	var en: int = hold_segs[hold_idx]["e"]
	if cross_e(en) - clock_e() > _margin_e():   # released before the tail
		hold_active = false
		hold_done[hold_idx] = true
		combo = 0
		notes_missed += 1
		if fever_active:
			_end_fever()
		set_feedback("松手太早!", COL_RED)
		br_kind = "awkward"
		br_timer = 0.5
		play_sfx(snd_miss)
		update_hud()


func _hit(g: int, perfect: bool) -> void:
	if g_kind[g] == K_BABY:
		var bi := _baby_index_for_tick(g)
		var is_head := bi >= 0 and g == int(baby_segs[bi]["s"])
		if is_head:
			baby_started[bi] = true
			baby_active = true
			baby_idx = bi
		_add_score(180 if perfect else 120)
		_fever_hit()
		play_sfx(snd_say, -2.0)
		set_feedback("宝宝模式!" if is_head else ("喂奶!" if perfect else "奶瓶!"), COL_GOLD)
		zoom_punch = maxf(zoom_punch, 0.07 if perfect else 0.045)
		baby_flash = 1.0
		br_kind = "heart"
		br_timer = 0.35
		_pop_heart(Vector2(CENTER_X, BOT_Y if is_head else TOP_Y))
		return
	_add_score(150 if perfect else 95)
	_fever_hit()
	play_sfx(snd_say)
	set_feedback("心动!" if perfect else "不错", COL_ROSE if perfect else COL_GREEN)
	zoom_punch = maxf(zoom_punch, 0.05 if perfect else 0.035)
	br_kind = "smile"
	br_timer = 0.45
	if g_top[g] == CORRECT:
		_pop_heart(Vector2(CENTER_X, TOP_Y))
		top_flash = 1.0
		top_flash_col = COL_ROSE
	if g_bot[g] == CORRECT:
		_pop_heart(Vector2(CENTER_X, BOT_Y))
		bot_flash = 1.0
		bot_flash_col = COL_ROSE


func _whiff() -> void:
	combo = 0
	update_hud()
	set_feedback("…", COL_MUTED)
	play_sfx(snd_miss, -14.0)


## Override: add the rose/red flash + shake + bubble FX, then the base penalty.
func apply_penalty(text: String) -> void:
	play_sfx(snd_miss)
	shake = maxf(shake, 10.0)
	top_flash = 1.0
	bot_flash = 1.0
	top_flash_col = COL_RED
	bot_flash_col = COL_RED
	br_kind = "awkward"
	br_timer = 0.6
	super.apply_penalty(text)


func _pop_heart(pos: Vector2) -> void:
	var fx: _HeartFx = hearts_fx[hearts_fx_i]
	hearts_fx_i = (hearts_fx_i + 1) % hearts_fx.size()
	fx.play(pos)


func _on_downbeat(_cycle_index: int) -> void:
	if phase != "running":
		return
	idle_side = 1 - idle_side   # the diners take turns chatting "..."
	var g := roundi(clock_e() - LEAD - JUDGE_E)
	if g >= 0 and g < n_ticks and g_press[g]:
		play_sfx(snd_heart, -12.0)


# ===========================================================================
# Hold / roll runtime
# ===========================================================================
func _current_hold() -> int:
	for hi in hold_segs.size():
		if not hold_done[hi]:
			return hi
	return -1


func _current_roll() -> int:
	for ri in roll_segs.size():
		if not roll_done[ri]:
			return ri
	return -1


func _current_baby() -> int:
	for bi in baby_segs.size():
		if not baby_done[bi]:
			return bi
	return -1


func _baby_index_for_tick(g: int) -> int:
	for bi in baby_segs.size():
		if g >= int(baby_segs[bi]["s"]) and g <= int(baby_segs[bi]["e"]):
			return bi
	return -1


func _start_hold(hi: int) -> void:
	hold_active = true
	hold_idx = hi
	hold_started[hi] = true
	hold_savor_g = -1
	_add_score(120)
	_fever_hit()
	play_sfx(snd_say)
	set_feedback("牵手!", COL_ROSE)
	zoom_punch = maxf(zoom_punch, 0.05)
	br_kind = "smile"
	br_timer = 0.5
	_pop_heart(Vector2(CENTER_X, TOP_Y))
	_pop_heart(Vector2(CENTER_X, BOT_Y))


func _update_hold() -> void:
	var hi := _current_hold()
	if hi < 0:
		return
	var e := clock_e()
	var s: int = hold_segs[hi]["s"]
	var en: int = hold_segs[hi]["e"]
	var margin := _margin_e()
	var u_head := cross_e(s) - e
	var u_tail := cross_e(en) - e

	# auto-start if you were already holding as the head arrived
	if not hold_active and u_head <= 0.0 and u_head > -margin and is_holding():
		_start_hold(hi)

	# savor each internal tick crossed while holding
	if hold_active and hold_idx == hi:
		var cg := roundi(e - LEAD - JUDGE_E)
		if cg > hold_savor_g and cg > s and cg <= en:
			hold_savor_g = cg
			_add_score(40)
			_fever_hit()
			br_kind = "smile"
			br_timer = 0.35
			_pop_heart(Vector2(CENTER_X, BOT_Y))

	# resolve when the tail passes center
	if u_tail < -margin:
		if hold_active and hold_idx == hi:
			_add_score(80)
			set_feedback("完美回应!", COL_ROSE)
			zoom_punch = maxf(zoom_punch, 0.04)
			hold_active = false
		elif not hold_started[hi]:
			apply_penalty("没接住")
		hold_done[hi] = true
		hold_savor_g = -1


func _update_roll() -> void:
	var prev := roll_active
	roll_active = false
	var ri := _current_roll()
	if ri < 0:
		return
	var e := clock_e()
	var s: int = roll_segs[ri]["s"]
	var en: int = roll_segs[ri]["e"]
	var margin := _margin_e()
	var u_head := cross_e(s) - e
	var u_tail := cross_e(en) - e
	if u_head <= 0.2 and u_tail >= -margin:
		roll_active = true
		roll_idx = ri
	if roll_active and not prev:
		set_feedback("连打! 快戳!", COL_GOLD)   # prompt the moment the box opens
	if u_tail < -margin:
		if roll_taps > 0:
			set_feedback("连击 ×%d!" % roll_taps, COL_GOLD)
		roll_done[ri] = true
		roll_taps = 0


func _update_baby(delta: float) -> void:
	baby_active = false
	baby_idx = -1
	var target_scale := 1.0
	var bi := _current_baby()
	if bi >= 0:
		var e := clock_e()
		var s: int = baby_segs[bi]["s"]
		var en: int = baby_segs[bi]["e"]
		var margin := _margin_e()
		var u_tail := cross_e(en) - e
		if baby_started[bi] and u_tail >= -margin:
			baby_active = true
			baby_idx = bi
			target_scale = BABY_SPEED_SCALE
		if u_tail < -margin:
			baby_done[bi] = true
	conductor.tempo_scale = move_toward(conductor.tempo_scale, target_scale, delta * BABY_RAMP_PER_SEC)
	baby_flash = move_toward(baby_flash, 0.0, delta * 4.0)


# ===========================================================================
# Layout (continuous scroll; food from the left, faces from the right)
# ===========================================================================
func layout() -> void:
	var e := clock_e()
	var ti := 0
	var bi := 0
	for g in n_ticks:
		if g_kind[g] != K_NORMAL:
			continue
		var u := cross_e(g) - e
		if u < -2.2 or u > 9.5:
			continue
		if g_top[g] != NONE and not (judged[g] and u < 1.0):
			if ti < top_tiles.size():
				_place(top_tiles[ti], FOOD, g_top[g], CENTER_X - u * SPACING, TOP_Y, u)
				ti += 1
		if g_bot[g] != NONE and not (judged[g] and u < 1.0):
			if bi < bot_tiles.size():
				_place(bot_tiles[bi], FACE, g_bot[g], CENTER_X + u * SPACING, BOT_Y, u)
				bi += 1
	for i in range(ti, top_tiles.size()):
		top_tiles[i].visible = false
	for i in range(bi, bot_tiles.size()):
		bot_tiles[i].visible = false
	_layout_baby(e)
	_layout_caps(e)


func _layout_baby(e: float) -> void:
	if not extreme_baby_mode:
		return
	var visible_baby := false
	var next_baby := _current_baby()
	var ti := 0
	for g in n_ticks:
		if g_kind[g] != K_BABY:
			continue
		var seg_i := _baby_index_for_tick(g)
		if seg_i < 0:
			continue
		var seg_head: int = baby_segs[seg_i]["s"]
		var is_head := g == seg_head
		if not is_head and not baby_started[seg_i]:
			continue
		var u := cross_e(g) - e
		if u < -1.0 or u > 9.5:
			continue
		visible_baby = true
		if not (judged[g] and u < 0.65) and ti < baby_tiles.size():
			var tile: _BabyIcon = baby_tiles[ti]
			tile.variant = 0 if is_head else 1
			tile.visible = true
			var near: float = clampf(1.0 - absf(u), 0.0, 1.0)
			tile.scale = Vector2.ONE * (1.0 + near * 0.18)
			tile.modulate = Color.WHITE.lerp(COL_GOLD, maxf(near, baby_flash) * 0.35)
			var cx := CENTER_X + u * SPACING if is_head else CENTER_X - u * SPACING
			var cy := BOT_Y if is_head else TOP_Y
			tile.position = Vector2(cx - TILE * 0.5, cy - TILE * 0.5)
			ti += 1
	for i in range(ti, baby_tiles.size()):
		baby_tiles[i].visible = false

	if next_baby >= 0:
		var s: int = baby_segs[next_baby]["s"]
		var en: int = baby_segs[next_baby]["e"]
		var u_head := cross_e(s) - e
		var u_tail := cross_e(en) - e
		visible_baby = visible_baby or (baby_started[next_baby] and u_head < 2.5 and u_tail > -1.0)
	if baby_avatar:
		baby_avatar.visible = false
	if baby_overlay:
		var danger := 1.0 if baby_active else 0.0
		var end_flash := 0.0
		if baby_idx >= 0:
			var en2: int = baby_segs[baby_idx]["e"]
			var left_e := cross_e(en2) - e
			if left_e < 2.0:
				end_flash = absf(sin(t * 18.0)) * 0.12
		baby_overlay.color.a = 0.16 * danger + end_flash + baby_flash * 0.08


## Build the hold/roll capsule bars and feed them to the _Caps node.
func _layout_caps(e: float) -> void:
	var hbars := []
	for hi in hold_segs.size():
		if hold_done[hi]:
			continue
		var s: int = hold_segs[hi]["s"]
		var en: int = hold_segs[hi]["e"]
		var u_head := cross_e(s) - e
		var u_tail := cross_e(en) - e
		if u_tail < -1.0 or u_head > 9.5:
			continue
		var hot: bool = hold_active and hold_idx == hi
		# top lane (food, from the left): head clamps at center, tail scrolls in.
		# Late-release leniency can make the tail pass the center; keep the visual
		# pinned at the judgement line instead of growing back in the wrong direction.
		var th := CENTER_X - maxf(0.0, u_head) * SPACING
		var tt := minf(CENTER_X, CENTER_X - u_tail * SPACING)
		hbars.append({"x0": minf(th, tt), "x1": maxf(th, tt), "y": TOP_Y, "head": th,
			"reg": _region(FOOD, food_correct), "hot": hot})
		# bottom lane (face, from the right)
		var bh := CENTER_X + maxf(0.0, u_head) * SPACING
		var bt := maxf(CENTER_X, CENTER_X + u_tail * SPACING)
		hbars.append({"x0": minf(bh, bt), "x1": maxf(bh, bt), "y": BOT_Y, "head": bh,
			"reg": _region(FACE, face_correct), "hot": hot})
	var rbars := []
	for ri in roll_segs.size():
		if roll_done[ri]:
			continue
		var rs: int = roll_segs[ri]["s"]
		var ren: int = roll_segs[ri]["e"]
		var ruh := cross_e(rs) - e
		var rut := cross_e(ren) - e
		if rut < -1.0 or ruh > 9.5:
			continue
		var rhot: bool = roll_active and roll_idx == ri
		var rth := CENTER_X - maxf(0.0, ruh) * SPACING
		var rtt := minf(CENTER_X, CENTER_X - rut * SPACING)
		rbars.append({"x0": minf(rth, rtt), "x1": maxf(rth, rtt), "y": TOP_Y, "head": rth,
			"reg": _region(FOOD, food_correct), "hot": rhot, "taps": roll_taps})
	caps.set_data(hbars, rbars, conductor.pulse() if conductor.running else 0.0)


func _region(cat: int, variant: int) -> Rect2:
	var cw := girls_tex.get_width() * 0.5 if girls_tex else 120.0
	var ch := girls_tex.get_height() * 0.5 if girls_tex else 120.0
	var row := 0 if cat == FACE else 1
	return Rect2(variant * cw, row * ch, cw, ch)


func _place(tile: _Icon, cat: int, state: int, cx: float, cy: float, u: float) -> void:
	var variant := 0
	if cat == FOOD:
		variant = food_correct if state == CORRECT else food_wrong
	else:
		variant = face_correct if state == CORRECT else face_wrong
	tile.set_icon(cat, variant)
	tile.visible = true
	var near: float = clampf(1.0 - absf(u), 0.0, 1.0)
	tile.scale = Vector2.ONE * (1.0 + near * 0.12)
	tile.modulate = Color.WHITE
	if state == WRONG:
		tile.modulate = Color(1.0, 0.74, 0.74, 1.0)
	tile.position = Vector2(cx - TILE * 0.5, cy - TILE * 0.5)


func set_tiles_visible(v: bool) -> void:
	for tile in top_tiles:
		tile.visible = v
	for tile in bot_tiles:
		tile.visible = v
	if not v:
		caps.set_data([], [], 0.0)
	for tile in baby_tiles:
		tile.visible = false
	if baby_avatar:
		baby_avatar.visible = false
	if baby_overlay:
		baby_overlay.color.a = 0.0


# ===========================================================================
# Per-frame (base _process drives countdown / _advance / _juice / fever)
# ===========================================================================
func _advance(delta: float) -> void:
	_update_baby(delta)
	_update_roll()
	_update_hold()
	_sweep_misses()
	layout()
	bpm_label.text = str(roundi(conductor.bpm()))


func _juice(delta: float) -> void:
	var p := conductor.pulse() if conductor.running else 0.0
	dinner.beat_pulse = p
	dinner.t = t
	dinner.queue_redraw()
	shake = move_toward(shake, 0.0, delta * 55.0)
	zoom_punch = move_toward(zoom_punch, 0.0, delta * 0.32)
	stage.scale = Vector2.ONE * (1.0 + p * 0.022 + zoom_punch)
	stage.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
	beat_flash.color.a = p * 0.05 if conductor.running else 0.0
	top_flash = move_toward(top_flash, 0.0, delta * 2.4)
	bot_flash = move_toward(bot_flash, 0.0, delta * 2.4)
	rings.top_color = COL_JUDGE.lerp(top_flash_col, clampf(top_flash, 0.0, 1.0))
	rings.bot_color = COL_JUDGE.lerp(bot_flash_col, clampf(bot_flash, 0.0, 1.0))
	rings.pulse = p
	rings.queue_redraw()
	_update_bubbles(delta)
	btn_pop = move_toward(btn_pop, 0.0, delta * 5.0)
	hit_button.scale = Vector2.ONE * (1.0 + 0.15 * btn_pop)
	hit_button.modulate = Color.WHITE.lerp(COL_ROSE, btn_pop)


func _update_bubbles(delta: float) -> void:
	bl_timer = maxf(0.0, bl_timer - delta)
	br_timer = maxf(0.0, br_timer - delta)
	var running := phase == "running"
	if bl_timer > 0.0:
		bubble_l.set_state(bl_kind, true)
	else:
		bubble_l.set_state("dots", running and idle_side == 0)
	if br_timer > 0.0:
		bubble_r.set_state(br_kind, true)
	else:
		bubble_r.set_state("dots", running and idle_side == 1)


func _sweep_misses() -> void:
	var e := clock_e()
	var margin := _margin_e()
	while pass_g < n_ticks and e > cross_e(pass_g) + margin:
		if g_press[pass_g] and not judged[pass_g]:
			judged[pass_g] = true
			if g_kind[pass_g] == K_BABY:
				var bi := _baby_index_for_tick(pass_g)
				if bi >= 0 and pass_g == int(baby_segs[bi]["s"]) and not baby_started[bi]:
					for bg in range(int(baby_segs[bi]["s"]), int(baby_segs[bi]["e"]) + 1):
						judged[bg] = true
					baby_done[bi] = true
					baby_active = false
					baby_idx = -1
			apply_penalty("错过")
			if phase != "running":
				return
		pass_g += 1
		if pass_g >= n_ticks - 12:
			romance.finale = true
	if pass_g >= n_ticks and phase == "running":
		_start_outro()


# ===========================================================================
# Phases
# ===========================================================================
func _countdown_tick(last: bool) -> void:
	play_sfx(snd_say if last else snd_heart, -8.0)


func _reset_level() -> void:
	pass_g = 0
	for i in judged.size():
		judged[i] = false
	for i in hold_done.size():
		hold_done[i] = false
		hold_started[i] = false
	for i in roll_done.size():
		roll_done[i] = false
	for i in baby_done.size():
		baby_done[i] = false
		baby_started[i] = false
	hold_active = false
	hold_idx = -1
	hold_savor_g = -1
	roll_active = false
	roll_idx = -1
	roll_taps = 0
	baby_active = false
	baby_idx = -1
	baby_flash = 0.0
	key_held = false
	btn_held = false
	shake = 0.0
	zoom_punch = 0.0
	top_flash = 0.0
	bot_flash = 0.0
	btn_pop = 0.0
	bl_timer = 0.0
	br_timer = 0.0
	_draw_today()


func _enter_start() -> void:
	_enter_intro()


func _draw_today() -> void:
	face_correct = randi() % 2
	face_wrong = 1 - face_correct
	food_correct = randi() % 2
	food_wrong = 1 - food_correct

	hint_face.set_icon(FACE, face_correct)
	hint_food.set_icon(FOOD, food_correct)
	hint_label.text = "%s\n爱吃%s" % [FACE_DATA[face_correct]["name"], FOOD_DATA[food_correct]["name"]]
	intro_face.set_icon(FACE, face_correct)
	intro_food.set_icon(FOOD, food_correct)
	if extreme_baby_mode:
		intro_text.text = "[center]你和[color=#ffd24a]%s[/color]已经结婚三年了，\n她最喜欢吃[color=#ffd24a]%s[/color]。\n现在你们有了一个宝宝，\n[color=#e2584f]如果他饿了，赶紧给他喂奶！[/color][/center]" % [FACE_DATA[face_correct]["name"], FOOD_DATA[food_correct]["name"]]
	else:
		intro_text.text = "[center]你约了心爱的女孩共进晚餐，\n她叫[color=#ffd24a]%s[/color]，她喜欢吃[color=#ffd24a]%s[/color]。\n[color=#e2584f]千万不要乱说话！[/color][/center]" % [FACE_DATA[face_correct]["name"], FOOD_DATA[food_correct]["name"]]


func _enter_intro() -> void:
	phase = "intro"
	intro_layer.visible = true
	countdown_label.visible = false
	set_tiles_visible(false)
	set_feedback("", COL_MUTED)


func _begin_countdown() -> void:
	if phase != "intro":
		return
	intro_layer.visible = false
	phase = "countdown"
	countdown_start = now_ms()
	countdown_step = -1
	countdown_label.visible = true
	set_tiles_visible(false)
	set_feedback("准备", COL_MUTED)


func _begin_play() -> void:
	pass_g = 0
	for i in judged.size():
		judged[i] = false
	set_feedback("表白吧!", COL_ROSE)


func _outro_fx() -> void:
	set_feedback("说出口了…", COL_ROSE)
	set_tiles_visible(false)
	zoom_punch = 0.07
	top_flash = 1.0
	bot_flash = 1.0
	top_flash_col = COL_ROSE
	bot_flash_col = COL_ROSE
	bl_kind = "press"
	bl_timer = 2.0
	br_kind = "smile"
	br_timer = 2.0
	_pop_heart(Vector2(CENTER_X, TOP_Y))
	_pop_heart(Vector2(CENTER_X, BOT_Y))
	_pop_heart(Vector2(CENTER_X, 330.0))


func _verdict(hearts_lost: int, won: bool) -> Dictionary:
	if won and app and app.extreme:
		match hearts_lost:
			0: return {"rank": "平衡大师", "eval": "人有两只手，平衡家庭绰绰有余。"}
			1: return {"rank": "新奇体验", "eval": "咱们今天换个菜尝尝。"}
			_: return {"rank": "亡羊补牢", "eval": "擦擦地板的事儿，别影响心情^^"}
	elif won:
		match hearts_lost:
			0: return {"rank": "告白成功", "eval": "她说「我也是」❤全程甜蜜，稳得一批。"}
			1: return {"rank": "她答应了", "eval": "喜欢的心是藏不住的♥"}
			_: return {"rank": "勉强过关", "eval": "心率180，这么紧张应该被看出来了"}
	if app and app.extreme:
		return {"rank": "为时已晚", "eval": "你不要把奶吐到桌子上的汤里啊！"}
	return {"rank": "当场社死", "eval": "你喊出了别人的名字……改天再约吧。"}


# ===========================================================================
# SFX
# ===========================================================================
func _build_sfx() -> void:
	snd_say = tone(520.0, 660.0, 0.12, "sine", 0.4)
	snd_miss = tone(240.0, 150.0, 0.16, "sine", 0.4)
	snd_heart = tone(120.0, 70.0, 0.12, "sine", 0.7)


# ===========================================================================
# Inner visual classes
# ===========================================================================
## Candlelit-dinner backdrop: warm gradient, two silhouettes facing each other,
## and a flickering pixel candle that breathes with the beat.
class _Dinner:
	extends Control

	const COL_TOP := Color("2a1220")
	const COL_BOT := Color("140810")
	const COL_TABLE := Color("3a2018")
	const COL_BUST := Color("0e0608")
	const COL_RIM := Color("6a3a2a")

	var beat_pulse := 0.0
	var t := 0.0

	func _draw() -> void:
		var w := 1280.0
		var h := 720.0
		var bands := 24
		for i in bands:
			var f := float(i) / bands
			draw_rect(Rect2(0, f * h, w, h / bands + 1.0), COL_TOP.lerp(COL_BOT, f))
		draw_rect(Rect2(0, 560, w, 160), COL_TABLE)
		draw_line(Vector2(0, 560), Vector2(w, 560), Color(COL_RIM.r, COL_RIM.g, COL_RIM.b, 0.5), 3.0)
		_bust(Vector2(250, 600))
		_bust(Vector2(1030, 600))
		_candle(Vector2(640, 575))

	func _bust(base: Vector2) -> void:
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-95, 60), base + Vector2(-70, -40),
			base + Vector2(70, -40), base + Vector2(95, 60),
		]), COL_BUST)
		draw_circle(base + Vector2(0, -78), 44.0, COL_BUST)
		draw_arc(base + Vector2(0, -78), 44.0, -2.2, -0.4, 16, Color(COL_RIM.r, COL_RIM.g, COL_RIM.b, 0.7), 3.0)

	func _candle(c: Vector2) -> void:
		var pr := clampf(beat_pulse, 0.0, 1.0)
		var flick := 0.85 + 0.15 * sin(t * 23.0) + 0.08 * sin(t * 41.0)
		var glow := Color(1.0, 0.7, 0.32, 1.0)
		for i in 10:
			var rr := (150.0 + pr * 30.0) * (1.0 - i * 0.09) * flick
			var a := (0.05 + pr * 0.06) * float(i + 1) / 10.0
			draw_circle(c + Vector2(0, -30), rr, Color(glow.r, glow.g, glow.b, a))
		draw_rect(Rect2(c.x - 9, c.y - 46, 18, 52), Color("f2e3c0"))
		var px := 5.0
		var fh: int = 4 + int(pr * 3.0 + (flick - 0.85) * 8.0)
		for i in fh:
			var ww: float = px * (3.0 - clampf(float(i) / maxf(fh - 1, 1) * 2.0, 0.0, 2.2))
			var col := Color(1.0, 0.82, 0.34) if i < fh - 2 else Color(1.0, 0.95, 0.72)
			draw_rect(Rect2(c.x - ww * 0.5, c.y - 46 - (i + 1) * px, ww, px), col)


## Two center breathing-lights built from PIXEL BLOCKS (a chunky ring that
## breathes inward on the beat) — one per lane; tints on a hit / penalty.
class _Rings:
	extends Control

	const TOP_Y := 235.0
	const BOT_Y := 420.0
	const CELL := 16.0
	const REACH := 6

	var pulse := 0.0
	var top_color := Color.WHITE
	var bot_color := Color.WHITE
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta

	func _draw() -> void:
		_judge_frame()
		_ring(Vector2(640, TOP_Y), top_color)
		_ring(Vector2(640, BOT_Y), bot_color)

	func _judge_frame() -> void:
		# An "align here" column connecting the two judge rings. Instead of a flat
		# bordered box (reads as a pasted-on UI panel), use a soft spotlight beam +
		# a faint plumb line + crisp pixel corner brackets — intentional, in-style.
		var pr := clampf(pulse, 0.0, 1.0)
		var warm := Color(1.0, 0.92, 0.68)
		var hw := 58.0
		var y0 := TOP_Y - 78.0
		var y1 := BOT_Y + 78.0
		# Soft vertical light beam: brightest at center, fading out (no hard edges).
		var strips := 7
		for i in range(strips):
			var f := (float(i) + 0.5) / float(strips)   # 0..1 across the half-width
			var a := (0.05 + pr * 0.05) * (1.0 - f) * 0.5
			draw_rect(Rect2(640.0 - hw * f, y0, hw * 2.0 * f, y1 - y0), Color(warm.r, warm.g, warm.b, a))
		# Faint plumb line down the center.
		draw_line(Vector2(640.0, y0 + 8.0), Vector2(640.0, y1 - 8.0),
			Color(warm.r, warm.g, warm.b, 0.10 + pr * 0.14), 2.0)
		# Pixel corner brackets — crisp marks, breathe with the beat.
		var bcol := Color(warm.r, warm.g, warm.b, 0.5 + pr * 0.32)
		_bracket(Vector2(640.0 - hw, y0), 1.0, 1.0, bcol)
		_bracket(Vector2(640.0 + hw, y0), -1.0, 1.0, bcol)
		_bracket(Vector2(640.0 - hw, y1), 1.0, -1.0, bcol)
		_bracket(Vector2(640.0 + hw, y1), -1.0, -1.0, bcol)

	func _bracket(corner: Vector2, hdir: float, vdir: float, col: Color) -> void:
		var arm := 24.0
		var th := 6.0
		var hx := corner.x if hdir > 0.0 else corner.x - arm
		draw_rect(Rect2(hx, corner.y - th * 0.5, arm, th), col)            # horizontal arm
		var vy := corner.y if vdir > 0.0 else corner.y - arm
		draw_rect(Rect2(corner.x - th * 0.5, vy, th, arm), col)            # vertical arm

	func _ring(center: Vector2, col: Color) -> void:
		var pr := clampf(pulse, 0.0, 1.0)
		var flick := 0.8 + 0.2 * sin(t * 16.0)
		var rad := lerpf(REACH * CELL * 0.82, REACH * CELL * 0.54, pr)
		for gy in range(-REACH, REACH + 1):
			for gx in range(-REACH, REACH + 1):
				var d := Vector2(gx, gy).length() * CELL
				var band := 1.0 - clampf(absf(d - rad) / (CELL * 1.6), 0.0, 1.0)
				if band <= 0.06:
					continue
				var a := band * (0.12 + pr * 0.6) * flick
				var p := center + Vector2(gx, gy) * CELL
				var sz := CELL * 0.86
				draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(col.r, col.g, col.b, a))


## A drawn icon: one cell of the 2×2 girls sprite sheet (faces top row, foods
## bottom row), nearest-filtered.
class _Icon:
	extends Control

	var sheet: Texture2D
	var cat := 0
	var variant := 0

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func set_icon(c: int, v: int) -> void:
		cat = c
		variant = v
		queue_redraw()

	func _draw() -> void:
		if sheet:
			var cw := sheet.get_width() * 0.5
			var ch := sheet.get_height() * 0.5
			var row := 0 if cat == 1 else 1
			draw_texture_rect_region(sheet, Rect2(Vector2.ZERO, size),
				Rect2(variant * cw, row * ch, cw, ch))
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color("4a3340") if cat == 1 else Color("5a3a2a"))


## Hold / roll capsules. Hold = rose capsule on BOTH lanes with the correct icon
## at the head; roll (連打) = gold capsule on the food lane with hearts + tap
## count. Bars are fed in each frame from the game.
class _Caps:
	extends Control

	const ICON := 104.0
	const COL_INK := Color("1a0e10")
	const EMO_HEART := 0

	var sheet: Texture2D    # girls
	var emoji: Texture2D
	var hold_bars: Array = []
	var roll_bars: Array = []
	var pulse := 0.0

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func set_data(h: Array, r: Array, p: float) -> void:
		hold_bars = h
		roll_bars = r
		pulse = p
		queue_redraw()

	func _draw() -> void:
		for b in hold_bars:
			_bar(b, Color("e0708a"), Color("ffd0dc"))
			_icon(b)
		for b in roll_bars:
			_bar(b, Color("f4c45a"), Color("ffe9b0"))
			_hearts(b)
			_icon(b)

	func _bar(b: Dictionary, edge: Color, fill: Color) -> void:
		var pr := clampf(pulse, 0.0, 1.0)
		var x0: float = b["x0"]
		var x1: float = b["x1"]
		var y: float = b["y"]
		var hot: bool = b.get("hot", false)
		var r := 70.0 * (0.84 + 0.2 * pr) * 0.5
		var fc := fill if hot else fill.darkened(0.25)
		fc.a = 0.9 if hot else 0.7
		draw_circle(Vector2(x0, y), r, fc)
		draw_circle(Vector2(x1, y), r, fc)
		draw_rect(Rect2(x0, y - r, x1 - x0, r * 2.0), fc)
		var ow := 5.0 if hot else 4.0
		draw_arc(Vector2(x0, y), r, PI * 0.5, PI * 1.5, 24, edge, ow)
		draw_arc(Vector2(x1, y), r, -PI * 0.5, PI * 0.5, 24, edge, ow)
		draw_line(Vector2(x0, y - r), Vector2(x1, y - r), edge, ow)
		draw_line(Vector2(x0, y + r), Vector2(x1, y + r), edge, ow)

	func _icon(b: Dictionary) -> void:
		if sheet == null:
			return
		var reg: Rect2 = b["reg"]
		var head: float = b["head"]
		var y: float = b["y"]
		var s := ICON
		draw_texture_rect_region(sheet, Rect2(Vector2(head, y) - Vector2(s, s) * 0.5, Vector2(s, s)), reg)

	func _hearts(b: Dictionary) -> void:
		if emoji == null:
			return
		var x0: float = b["x0"]
		var x1: float = b["x1"]
		var y: float = b["y"]
		var ch := emoji.get_height() / 3.0
		var ew := float(emoji.get_width())
		var reg := Rect2(0, EMO_HEART * ch, ew, ch)
		var hh := 36.0
		var hw := hh * ew / ch     # keep the heart's aspect ratio
		var n := 3
		for i in n:
			var fx: float = lerpf(x0 + 40.0, x1 - 40.0, float(i + 1) / float(n + 1))
			draw_texture_rect_region(emoji, Rect2(Vector2(fx, y - 66.0) - Vector2(hw, hh) * 0.5, Vector2(hw, hh)), reg)


## A speech bubble above a diner. Shows idle "..." or an emoji / your ♥ press.
class _Bubble:
	extends Control

	const COL_FILL := Color("fdf6ea")
	const COL_INK := Color("2a1018")

	var sheet: Texture2D    # emoji
	var kind := "dots"
	var on := false

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func set_state(k: String, vis: bool) -> void:
		if kind == k and on == vis:
			return
		kind = k
		on = vis
		queue_redraw()

	func _draw() -> void:
		if not on:
			return
		var w := size.x
		var bh := size.y - 14.0
		# pixel speech bubble: a bordered box + a little tail
		draw_rect(Rect2(0, 0, w, bh), COL_FILL)
		draw_rect(Rect2(0, 0, w, bh), COL_INK, false, 3.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(w * 0.5 - 11, bh - 1), Vector2(w * 0.5 + 11, bh - 1), Vector2(w * 0.5, bh + 13),
		]), COL_FILL)
		var c := Vector2(w * 0.5, bh * 0.5)
		match kind:
			"dots":
				for i in 3:
					draw_circle(c + Vector2((i - 1) * 16.0, 0), 5.0, COL_INK)
			"press":
				_heart(c, 27.0, Color("e0708a"))
			"smile":
				_emoji(c, 2)
			"awkward":
				_emoji(c, 1)
			"heart":
				_emoji(c, 0)

	func _emoji(c: Vector2, frame: int) -> void:
		if sheet == null:
			_heart(c, 26.0, Color("e0708a"))
			return
		var ch := sheet.get_height() / 3.0
		var ew := float(sheet.get_width())
		# Bigger, and keep the source frame's aspect ratio so it isn't stretched.
		var dh := 56.0
		var dw := dh * ew / ch
		draw_texture_rect_region(sheet, Rect2(c - Vector2(dw, dh) * 0.5, Vector2(dw, dh)),
			Rect2(0, frame * ch, ew, ch))

	func _heart(c: Vector2, r: float, col: Color) -> void:
		draw_circle(c + Vector2(-r * 0.5, -r * 0.25), r * 0.5, col)
		draw_circle(c + Vector2(r * 0.5, -r * 0.25), r * 0.5, col)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-r * 0.92, 0.0), c + Vector2(r * 0.92, 0.0), c + Vector2(0, r),
		]), col)


## Floating heart burst on a clean hit / tap.
class _HeartFx:
	extends Control

	const DUR := 0.5
	var fx_pos := Vector2.ZERO
	var life := 0.0
	var active := false

	func play(p: Vector2) -> void:
		fx_pos = p
		life = 0.0
		active = true
		visible = true

	func _process(delta: float) -> void:
		if not active:
			return
		life += delta
		if life >= DUR:
			active = false
			visible = false
		queue_redraw()

	func _draw() -> void:
		if not active:
			return
		var f := clampf(life / DUR, 0.0, 1.0)
		var a := 1.0 - f
		var pos := fx_pos + Vector2(0, -60.0 * f)
		var sc := 1.0 + f * 0.6
		_heart(pos, 24.0 * sc, Color(0.88, 0.32, 0.46, a))

	func _heart(c: Vector2, r: float, col: Color) -> void:
		draw_circle(c + Vector2(-r * 0.5, -r * 0.25), r * 0.5, col)
		draw_circle(c + Vector2(r * 0.5, -r * 0.25), r * 0.5, col)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-r * 0.92, 0.0), c + Vector2(r * 0.92, 0.0), c + Vector2(0, r),
		]), col)


## baby.png: 1x2 horizontal sheet, left = baby, right = bottle.
class _BabyIcon:
	extends Control

	var sheet: Texture2D
	var variant := 0

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _draw() -> void:
		if sheet:
			var cw := sheet.get_width() * 0.5
			var ch := float(sheet.get_height())
			draw_texture_rect_region(sheet, Rect2(Vector2.ZERO, size),
				Rect2(variant * cw, 0, cw, ch))
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color("fdf6ea"))


## Heart "health" icon.
class _HeartIcon:
	extends Control

	var lost := false

	func set_lost(v: bool) -> void:
		lost = v
		queue_redraw()

	func _draw() -> void:
		var a := 0.22 if lost else 1.0
		var col := Color(0.88, 0.32, 0.46, a)
		var c := size * 0.5
		var r := 11.0
		draw_circle(c + Vector2(-r * 0.5, -r * 0.25), r * 0.5, col)
		draw_circle(c + Vector2(r * 0.5, -r * 0.25), r * 0.5, col)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-r * 0.92, 0.0), c + Vector2(r * 0.92, 0.0), c + Vector2(0, r),
		]), col)
