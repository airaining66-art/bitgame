extends LevelBase
## 1-2 芒果奇缘 — bathroom reaction level.
## Two icons (mango / water-drop) slide to center each beat; if they match,
## bite (press) on the beat; if they differ, hold off. Biting zooms the mango
## and wall in and the shower droplets vanish. Hold "savor" notes + lo-fi BGM.
## (Subclass of LevelBase: only the mango-specific theme/chart/judging/FX live
## here; HUD/Fever/result/countdown/pause/SFX-pool come from the base.)

# --- palette ----------------------------------------------------------------
const COL_INK := Color("2a2a2a")
const COL_MANGO := Color("f3c200")
const COL_MANGO_DK := Color("c98f12")
const COL_MANGO_G := Color("6fa83b")
const COL_WATER := Color("8cc1de")
const COL_WATER_DK := Color("3f7fa6")
const COL_TEXT := Color("2e4a42")
const COL_MUTED := Color("7d968c")
const COL_GREEN := Color("2a8d49")
const COL_RED := Color("d24b4b")
const COL_JUDGE := Color("fff3c0")   # soft warm-white judge glow

# --- tunables ---------------------------------------------------------------
const SLIDE_RATIO := 0.5
const MIN_PERFECT_MS := 140.0
const MIN_GOOD_MS := 260.0
const STAGE_CENTER := Vector2(640, 360)

const TILE_W := 150.0
const TILE_H := 150.0
const MANGO := 0
const WATER := 1

const SPACING := 330.0       # pixels per beat of continuous scroll
const JUDGE_OFFSET := 0.75   # a note crosses center at this phase of its cycle
const NOTE_SLOTS := 7        # IconTiles per lane (scroll window)

## Fixed, FINITE chart. Tokens: m=mango press, w=water press, -=no-press beat,
## H=3-beat mango "savor" hold, E=end marker.
const CHART := [
	"m", "-", "m", "m",
	"w", "w", "-", "w",
	"m", "-", "m", "H",
	"w", "-", "w", "w",
	"m", "m", "-", "m",
	"H", "w", "w", "-",
	"m", "-", "w", "-",
	"m", "m", "H",
	"w", "w", "-", "w",
	"m", "-", "m", "m",
	"w", "H",
	"m", "m", "m", "H",   # final flourish
	"E",
]

# --- mango-specific state ---------------------------------------------------
var lofi: Music
var current_beat := 0
var last_judged_beat := -1
var current_beat_data: Dictionary = {}
var prev_beat_data: Dictionary = {}
var queue: Array[Dictionary] = []
var hit_pop := 0.0
var current_hit := false
var chart_i := 0
var chart_total_beats := 0
var hold_emit_left := 0
var hold_emit_len := 0
var hold_active := false
var hold_filled := 0.0
var hold_head_pop := 0.0
var key_held := false
var btn_held := false

# --- juice ------------------------------------------------------------------
const ZOOM_OUT := 0.10
var zoom_state := 0.0
var zoom_cur := 0.0
var bump := 0.0
var wetness := 0.45
var hold_dim := 0.0
var shake := 0.0
var bar_flash := 0.0
var bar_color := Color.WHITE
var btn_pop := 0.0

# --- nodes ------------------------------------------------------------------
var world: _World
var hold_vignette: _Vignette
var beat_ring: _BeatRing
var track: Control
var mango_icon_tex: Texture2D
var drop_tex: Texture2D
var hold_frame: _HoldFrame
var top_tiles: Array = []
var bottom_tiles: Array = []
var hit_fx: Array = []
var hit_fx_i := 0
var hit_button: Button
var intro_layer: ColorRect
var intro_label: Label

# --- sfx --------------------------------------------------------------------
var snd_bite: AudioStreamWAV
var snd_miss: AudioStreamWAV
var snd_anchor: AudioStreamWAV


# ===========================================================================
# LevelBase hooks
# ===========================================================================
func make_cfg() -> Dictionary:
	return {
		"duration_ms": 45000.0, "start_bpm": 70.0, "end_bpm": 110.0,
		"bpm_curve_exp": 1.6, "subdivisions": 4,
		"press_ratio": 0.6, "max_skip_run": 2, "max_press_run": 3,
	}


func _conf() -> Dictionary:
	return {
		"score_caption": "爽度",
		"text_col": COL_TEXT, "muted_col": COL_MUTED,
		"countdown_col": COL_TEXT, "penalty_col": COL_WATER_DK,
		"feedback": {"preset": Control.PRESET_BOTTOM_WIDE, "top": -190.0, "bottom": -140.0},
		"fever_text": "FEVER!!", "fever_col": Color("ff7a1a"), "fever_fill": Color("ffcf52"),
		"fever_overlay": Color(1.0, 0.62, 0.12), "fever_overlay_a": 0.10,
		"result_bg": Color("fffdf6"), "result_border": COL_MANGO,
		"title_col": COL_MANGO_DK, "lose_col": COL_WATER_DK,
		"eval_bg": Color("fff7df"), "eval_border": Color("ecd9a0"),
		"again_label": "再来一局",
		"score_fmt": "爽度 %d　命中 %d%%　最高 %d%s",
		"grade_cols": {"S": Color("ff7a1a"), "A": COL_MANGO_DK, "B": COL_GREEN, "C": COL_TEXT, "D": COL_WATER_DK},
	}


func _make_music() -> Node:
	lofi = Music.new()
	return lofi


func _make_heart() -> Control:
	var d := _Droplet.new()
	d.custom_minimum_size = Vector2(30, 38)
	return d


func _build_sfx() -> void:
	# Warm, soft "plop" rather than a rising electronic beep.
	snd_bite = tone(430.0, 300.0, 0.11, "sine", 0.42)
	snd_miss = tone(230.0, 130.0, 0.16, "sine", 0.4)
	snd_anchor = tone(130.0, 60.0, 0.13, "sine", 0.7)   # rhythm-peg kick


func perfect_window() -> float:
	return maxf(MIN_PERFECT_MS, conductor.cycle_duration * 0.14)


func good_window() -> float:
	return maxf(MIN_GOOD_MS, conductor.cycle_duration * 0.28)


func _build_level() -> void:
	_build_world()
	_build_button()
	_build_intro()


func _reset_level() -> void:
	current_beat = 0
	last_judged_beat = -1
	prepare_beats()
	wetness = 0.45
	world.wetness = 0.45
	key_held = false
	btn_held = false
	shake = 0.0
	bar_flash = 0.0
	zoom_state = 0.0
	zoom_cur = 0.0
	bump = 0.0
	hold_dim = 0.0


func _enter_start() -> void:
	_enter_intro()


func _begin_play() -> void:
	current_beat = 0
	last_judged_beat = -1
	set_tiles_visible(true)
	set_feedback("开吃!", COL_MANGO_DK)


func _on_space(pressed: bool) -> void:
	if pressed:
		key_held = true
		if phase == "intro":
			_enter_countdown()
		else:
			_press_down()
	else:
		key_held = false
		_press_up()


func _extra_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and phase == "intro":
		_enter_countdown()
		return true
	return false


func _countdown_tick(last: bool) -> void:
	play_sfx(snd_bite if last else snd_miss, -8.0)


func _advance(_delta: float) -> void:
	layout_notes()
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
	current_hit = false
	if current_beat >= chart_total_beats - 8:
		lofi.finale = true
	if current_beat_data.get("end", false):
		_start_outro()


func _on_downbeat(_cycle_index: int) -> void:
	# A soft kick on every "should-press" beat — the rhythm peg you press to.
	if phase == "running" and current_beat_data.get("should_press", false):
		play_sfx(snd_anchor, -9.0)


func _outro_fx() -> void:
	set_feedback("吃完啦~", COL_MANGO_DK)
	wetness = 0.0
	world.wetness = 0.0
	zoom_state = ZOOM_OUT * 1.7
	bar_color = COL_MANGO
	bar_flash = 1.0
	hit_pop = 1.0
	_spawn_fx(MANGO, Vector2(640.0, 220.0))
	_spawn_fx(MANGO, Vector2(640.0, 500.0))


func _verdict(hearts_lost: int, won: bool) -> Dictionary:
	if won and app and app.extreme:
		match hearts_lost:
			0: return {"rank": "是淋浴还是淋雨", "eval": "I'm singin' in the rain, just singin' in the rain"}
			1: return {"rank": "umbrella", "eval": "Maybe in magazines, but you'll still be my star"}
			_: return {"rank": "血糖战士", "eval": "有点齁住了，看来一天最多吃两个。"}
	elif won:
		match hearts_lost:
			0: return {"rank": "淋浴战神", "eval": "我就是山里最灵活的猴"}
			1: return {"rank": "宣的很", "eval": "差一口就上天了，明天还能上班"}
			_: return {"rank": "节约粮食", "eval": "淋了点水，还能吃"}
	if app and app.extreme:
		return {"rank": "量变累积质变", "eval": "不好，起疹子了，这怕不是过敏啊"}
	return {"rank": "手滑了一下", "eval": "不是哥们你咋掉地上了QAQ"}


# ===========================================================================
# Build
# ===========================================================================
func _build_world() -> void:
	world = _World.new()
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.pivot_offset = STAGE_CENTER
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)

	hold_vignette = _Vignette.new()
	hold_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hold_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(hold_vignette)

	track = Control.new()
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.pivot_offset = STAGE_CENTER
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(track)

	mango_icon_tex = _load_tex(["res://assets/mango.png"])
	drop_tex = _load_tex(["res://assets/drop.png"])
	world.hand_tex = _load_tex(["res://assets/mango_hand.png", "res://assets/mangohand.png"])

	hold_frame = _HoldFrame.new()
	hold_frame.icon_tex = mango_icon_tex
	hold_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hold_frame.visible = false
	hold_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(hold_frame)

	for i in NOTE_SLOTS:
		top_tiles.append(_make_tile())
		bottom_tiles.append(_make_tile())

	for i in 8:
		var fx := _HitFx.new()
		fx.drop_tex = drop_tex
		fx.mango_tex = mango_icon_tex
		fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fx.visible = false
		track.add_child(fx)
		hit_fx.append(fx)


func _make_tile() -> IconTile:
	var tile := IconTile.new()
	tile.size = Vector2(TILE_W, TILE_H)
	tile.icon_tex = mango_icon_tex
	tile.drop_tex = drop_tex
	tile.pivot_offset = Vector2(TILE_W, TILE_H) * 0.5
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(tile)
	return tile


func _build_button() -> void:
	beat_ring = _BeatRing.new()
	beat_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	beat_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(beat_ring)

	hit_button = Button.new()
	hit_button.text = "咬一口"
	hit_button.custom_minimum_size = Vector2(220, 92)
	hit_button.add_theme_font_size_override("font_size", 28)
	hit_button.focus_mode = Control.FOCUS_NONE
	hit_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("fff7df")
	normal.set_border_width_all(14)
	normal.border_color = COL_MANGO
	normal.set_corner_radius_all(44)
	hit_button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color("fff0c2")
	hit_button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = Color("ffe49a")
	pressed.border_color = COL_MANGO_DK
	hit_button.add_theme_stylebox_override("pressed", pressed)
	for s in ["font_color", "font_hover_color", "font_pressed_color"]:
		hit_button.add_theme_color_override(s, COL_MANGO_DK)
	hit_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hit_button.position = Vector2(-110, -116)
	hit_button.pivot_offset = Vector2(110, 46)
	hit_button.button_down.connect(func() -> void:
		btn_held = true
		_press_down())
	hit_button.button_up.connect(func() -> void:
		btn_held = false
		_press_up())
	add_child(hit_button)


func _build_intro() -> void:
	intro_layer = ColorRect.new()
	intro_layer.color = Color(0, 0, 0, 0.55)
	intro_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro_layer.z_index = 5
	intro_layer.visible = false
	add_child(intro_layer)

	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("fff5cc")
	sb.set_border_width_all(4)
	sb.border_color = COL_MANGO_DK
	sb.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(640, 220)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.position = Vector2(-320, -110)
	intro_layer.add_child(card)

	intro_label = Label.new()
	intro_label.add_theme_font_size_override("font_size", 30)
	intro_label.add_theme_color_override("font_color", COL_TEXT)
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
# Beat generation
# ===========================================================================
func make_beat() -> Dictionary:
	if hold_emit_left > 0:
		var pos := hold_emit_len - hold_emit_left
		hold_emit_left -= 1
		return _hold_beat(pos, hold_emit_len)
	if chart_i >= CHART.size():
		return {"top": MANGO, "bottom": MANGO, "should_press": false,
			"hold": false, "hold_pos": 0, "hold_len": 0, "end": true}
	var tok: String = CHART[chart_i]
	chart_i += 1
	match tok:
		"H":
			hold_emit_len = 3
			hold_emit_left = hold_emit_len - 1
			return _hold_beat(0, hold_emit_len)
		"m":
			return {"top": MANGO, "bottom": MANGO, "should_press": true,
				"hold": false, "hold_pos": 0, "hold_len": 0}
		"w":
			return {"top": WATER, "bottom": WATER, "should_press": true,
				"hold": false, "hold_pos": 0, "hold_len": 0}
		"E":
			return {"top": MANGO, "bottom": MANGO, "should_press": false,
				"hold": false, "hold_pos": 0, "hold_len": 0, "end": true}
		_:
			return {"top": MANGO, "bottom": WATER, "should_press": false,
				"hold": false, "hold_pos": 0, "hold_len": 0}


func _hold_beat(pos: int, length: int) -> Dictionary:
	return {"top": MANGO, "bottom": MANGO, "should_press": true,
		"hold": true, "hold_pos": pos, "hold_len": length}


func ensure_queue() -> void:
	while queue.size() < 5:
		queue.append(make_beat())


func _chart_beats() -> int:
	var n := 0
	for tok in CHART:
		n += 3 if tok == "H" else 1
	return n


func prepare_beats() -> void:
	queue = []
	chart_i = 0
	chart_total_beats = _chart_beats()
	hold_emit_left = 0
	hold_active = false
	hold_filled = 0.0
	hit_pop = 0.0
	prev_beat_data = {}
	ensure_queue()
	current_beat_data = queue.pop_front()
	ensure_queue()


# ===========================================================================
# Judging
# ===========================================================================
func is_holding() -> bool:
	return key_held or btn_held


func _press_down() -> void:
	if phase != "running":
		return
	bump = maxf(bump, 0.022)
	shake = maxf(shake, 2.5)
	var cur := current_beat_data
	if cur.get("hold", false):
		if int(cur.get("hold_pos", 0)) == 0 and not hold_active:
			last_judged_beat = current_beat
			_start_hold()
		return
	if last_judged_beat == current_beat:
		return
	flash_button()
	last_judged_beat = current_beat
	var d := _judge_delta()
	if not cur["should_press"]:
		apply_penalty("不一样!")
		return
	if d <= perfect_window():
		reward("Perfect", 120)
	elif d <= good_window():
		reward("Good", 80)
	else:
		apply_penalty("差点")


func _press_up() -> void:
	if phase != "running" or not hold_active:
		return
	var cur := current_beat_data
	if not cur.get("hold", false):
		return
	var pos := int(cur.get("hold_pos", 0))
	var l := int(cur.get("hold_len", 1))
	var tail_reached := pos >= l - 1 and conductor.beat_phase() >= JUDGE_OFFSET - 0.12
	if not tail_reached:
		hold_active = false
		combo = 0
		notes_missed += 1
		if fever_active:
			_end_fever()
		update_hud()
		set_feedback("回味中断", COL_WATER_DK)


func _judge_delta() -> float:
	return absf(conductor.beat_phase() - JUDGE_OFFSET) * conductor.cycle_duration


func _start_hold() -> void:
	_add_score(100)
	_fever_hit()
	play_sfx(snd_bite)
	set_feedback("回味!", COL_MANGO_DK)
	_hit_feedback(MANGO)
	hold_head_pop = 1.0
	_step_out()
	hold_active = true


func _resolve_boundary() -> void:
	if phase != "running":
		return
	var cur := current_beat_data
	if cur.get("hold", false):
		var l := int(cur.get("hold_len", 1))
		var pos := int(cur.get("hold_pos", 0))
		if pos == 0:
			if not hold_active:
				last_judged_beat = current_beat
				if is_holding():
					_start_hold()
				else:
					apply_penalty("Miss")
		else:
			last_judged_beat = current_beat
			if hold_active:
				_add_score(60)
				_fever_hit()
				play_sfx(snd_bite, -6.0)
				set_feedback("回味…", COL_GREEN)
				_hit_feedback(MANGO)
				hold_head_pop = 1.0
				_step_out()
		if pos == l - 1:
			hold_active = false
	elif last_judged_beat != current_beat:
		last_judged_beat = current_beat
		if cur["should_press"]:
			apply_penalty("Miss")
		else:
			set_feedback("忍住", COL_MUTED)


func reward(kind: String, points: int) -> void:
	var k := int(current_beat_data["top"])
	_add_score(points)
	_fever_hit()
	play_sfx(snd_bite)
	set_feedback(kind, COL_MANGO_DK if kind == "Perfect" else COL_GREEN)
	_hit_feedback(k)
	current_hit = true
	_spawn_fx(k, Vector2(640.0, 220.0))
	_spawn_fx(k, Vector2(640.0, 500.0))
	if k == MANGO:
		_step_out()
	else:
		_step_in()


func _hit_feedback(kind: int) -> void:
	hit_pop = 1.0
	bar_color = COL_MANGO if kind == MANGO else COL_WATER
	bar_flash = 1.0


func _spawn_fx(kind: int, pos: Vector2) -> void:
	var fx: _HitFx = hit_fx[hit_fx_i]
	hit_fx_i = (hit_fx_i + 1) % hit_fx.size()
	fx.play(kind, pos)


func _step_out() -> void:
	zoom_state = ZOOM_OUT
	wetness = 0.0
	world.wetness = 0.0


func _step_in() -> void:
	zoom_state = 0.0
	wetness = minf(1.0, wetness + 0.22)
	world.wetness = wetness


func apply_penalty(text: String) -> void:
	play_sfx(snd_miss)
	shake = maxf(shake, 9.0)
	bar_color = COL_RED
	bar_flash = 1.0
	super.apply_penalty(text)


func flash_button() -> void:
	btn_pop = 1.0


# ===========================================================================
# Tiles
# ===========================================================================
func layout_notes() -> void:
	var bp := conductor.beat_phase()

	var segs := []
	if current_beat_data.get("hold", false):
		_add_hold_seg(segs, -int(current_beat_data.get("hold_pos", 0)), int(current_beat_data.get("hold_len", 3)), bp)
	for qi in queue.size():
		var note: Dictionary = queue[qi]
		if note.get("hold", false) and int(note.get("hold_pos", 0)) == 0:
			_add_hold_seg(segs, qi + 1, int(note.get("hold_len", 3)), bp)
	hold_frame.set_segments(segs, hold_active, conductor.pulse(), hold_head_pop)
	hold_frame.visible = not segs.is_empty()

	for slot in NOTE_SLOTS:
		var k := slot - 1
		var note := _note_at(k)
		var bu := float(k) + JUDGE_OFFSET - bp
		if note.is_empty() or note.get("hold", false) or note.get("end", false) \
				or bu < -0.35 or (k == 0 and current_hit):
			top_tiles[slot].visible = false
			bottom_tiles[slot].visible = false
			continue
		var sc := 1.0 + (hit_pop * 0.3 if k == 0 else 0.0)
		_place_note(top_tiles[slot], int(note["top"]), 640.0 - bu * SPACING, 220.0, sc)
		_place_note(bottom_tiles[slot], int(note["bottom"]), 640.0 + bu * SPACING, 500.0, sc)


func _note_at(k: int) -> Dictionary:
	if k == -1:
		return prev_beat_data
	if k == 0:
		return current_beat_data
	if k >= 1 and k - 1 < queue.size():
		return queue[k - 1]
	return {}


func _add_hold_seg(segs: Array, k_head: int, l: int, bp: float) -> void:
	var buh := float(k_head) + JUDGE_OFFSET - bp
	var but_ := float(k_head + l - 1) + JUDGE_OFFSET - bp
	if but_ < -0.15:
		return
	segs.append({
		"th": 640.0 - maxf(0.0, buh) * SPACING,
		"tt": minf(640.0, 640.0 - but_ * SPACING),
		"bh": 640.0 + maxf(0.0, buh) * SPACING,
		"bt": maxf(640.0, 640.0 + but_ * SPACING),
	})


func _place_note(tile: IconTile, kind: int, cx: float, cy: float, sc: float) -> void:
	tile.visible = true
	tile.set_icon(kind)
	tile.scale = Vector2.ONE * sc
	tile.position = Vector2(cx - TILE_W * 0.5, cy - TILE_H * 0.5)
	tile.modulate.a = 1.0


func set_tiles_visible(v: bool) -> void:
	for tile in top_tiles:
		tile.visible = v
	for tile in bottom_tiles:
		tile.visible = v


# ===========================================================================
# Per-frame juice (fever visuals handled by the base)
# ===========================================================================
func _juice(delta: float) -> void:
	var p := conductor.pulse() if conductor.running else 0.0
	zoom_cur = move_toward(zoom_cur, zoom_state, delta * 0.7)
	bump = move_toward(bump, 0.0, delta * 0.5)
	world.scale = Vector2.ONE * (1.0 + p * 0.01 + zoom_cur + bump)
	track.rotation = sin(conductor.musical_phase() * TAU) * 0.02 if conductor.running else 0.0
	shake = move_toward(shake, 0.0, delta * 55.0)
	bar_flash = move_toward(bar_flash, 0.0, delta * 2.2)
	world.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
	world.center_color = COL_JUDGE.lerp(bar_color, clampf(bar_flash, 0.0, 1.0))
	world.center_pulse = p
	var dim_target := 1.0 if (phase == "running" and current_beat_data.get("hold", false)) else 0.0
	hold_dim = move_toward(hold_dim, dim_target, delta * 3.0)
	var beat_dim := (1.0 - p) * 0.13 if conductor.running else 0.0
	hold_vignette.set_intensity(maxf(hold_dim, beat_dim))
	beat_ring.set_pulse(p)
	if hold_active and is_holding():
		var fl := 0.5 + 0.5 * sin(t * 22.0)
		hit_button.scale = Vector2.ONE * (1.0 + 0.07 * fl)
		hit_button.modulate = Color.WHITE.lerp(Color("ffcf52"), 0.45 + 0.45 * fl)
	else:
		btn_pop = move_toward(btn_pop, 0.0, delta * 5.0)
		hit_button.scale = Vector2.ONE * (1.0 + 0.15 * btn_pop)
		hit_button.modulate = Color.WHITE.lerp(Color("ffc83a"), btn_pop)
	hit_pop = move_toward(hit_pop, 0.0, delta * 6.0)
	hold_head_pop = move_toward(hold_head_pop, 0.0, delta * 4.0)


# ===========================================================================
# Phases (mango-specific overrides)
# ===========================================================================
func _enter_intro() -> void:
	phase = "intro"
	intro_label.text = "我又下单了一箱，根本停不下来！" if (app and app.extreme) else "网上说边洗澡边吃芒果很爽，我看看怎么回事儿"
	intro_layer.visible = true
	countdown_label.visible = false
	hold_frame.visible = false
	set_tiles_visible(false)
	set_feedback("", COL_MUTED)


func _enter_countdown() -> void:
	super()
	if intro_layer:
		intro_layer.visible = false
	hold_frame.visible = false
	set_tiles_visible(false)


# ===========================================================================
# Inner visual classes
# ===========================================================================
## Bathroom wall + steam + running droplets. Lives behind the mango and tiles
## and zooms with them on a bite (parent scales this node).
class _World:
	extends Control

	const TILE := 86.0
	const COL_BG := Color("eaf4ef")
	const COL_WALL := Color("dceee7")
	const COL_WALL2 := Color("d2e7df")
	const COL_GROUT := Color("b1cdc2")
	const COL_WATER := Color("8cc1de")
	const COL_INK := Color("2a2a2a")
	const COL_JUDGE := Color("33dd66")

	const MAX_DROPS := 22

	var droplets: Array = []
	var wetness := 0.45
	var _shown := 0.45
	var center_pulse := 0.0
	var center_color := Color.WHITE
	var hand_tex: Texture2D
	var t := 0.0

	func _ready() -> void:
		for i in MAX_DROPS:
			droplets.append({
				"x": randf_range(30, 1250), "y": randf_range(-400, 720),
				"speed": randf_range(80, 190), "len": randf_range(55, 130),
			})

	func _process(delta: float) -> void:
		t += delta
		_shown = move_toward(_shown, wetness, delta * 2.6)
		for d in droplets:
			d["y"] += d["speed"] * delta
			if d["y"] - d["len"] > 760:
				d["y"] = -d["len"]
				d["x"] = randf_range(30, 1250)
				d["speed"] = randf_range(80, 190)
		queue_redraw()

	func _draw() -> void:
		var w := 1280.0
		var h := 720.0
		draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), COL_BG)
		var cols := int(ceil(w / TILE)) + 1
		var rows := int(ceil(h / TILE)) + 1
		for r in rows:
			for c in cols:
				var col := COL_WALL2 if (r + c) % 2 == 0 else COL_WALL
				draw_rect(Rect2(c * TILE, r * TILE, TILE, TILE), col)
		for c in range(1, cols):
			draw_line(Vector2(c * TILE, 0), Vector2(c * TILE, h), COL_GROUT, 2.0)
		for r in range(1, rows):
			draw_line(Vector2(0, r * TILE), Vector2(w, r * TILE), COL_GROUT, 2.0)
		for i in 7:
			draw_rect(Rect2(0, i * 22, w, 22), Color(1, 1, 1, 0.10 * (1.0 - i / 7.0)))
		if hand_tex:
			var hs := hand_tex.get_size()
			var sc := minf(460.0 / hs.x, 500.0 / hs.y)
			var dst := hs * sc
			var hc := Vector2(640.0, 380.0 + sin(t * 1.6) * 8.0)
			draw_texture_rect(hand_tex, Rect2(hc - dst * 0.5, dst), false)
		_judge_ring(Vector2(640, 220))
		_judge_ring(Vector2(640, 500))
		var span := _shown * MAX_DROPS
		for i in MAX_DROPS:
			var av := clampf(span - i, 0.0, 1.0) * 0.6
			if av <= 0.02:
				continue
			var d: Dictionary = droplets[i]
			var x: float = d["x"]
			var y: float = d["y"]
			var l: float = d["len"]
			draw_line(Vector2(x, y - l), Vector2(x, y), Color(COL_WATER.r, COL_WATER.g, COL_WATER.b, av), 5.0)
			draw_circle(Vector2(x, y), 7.0, Color(COL_WATER.r, COL_WATER.g, COL_WATER.b, minf(av + 0.25, 1.0)))

	func _judge_ring(c: Vector2) -> void:
		var pr := clampf(center_pulse, 0.0, 1.0)
		var flick := 0.8 + 0.2 * sin(t * 17.0)
		var base_r := lerpf(94.0, 74.0, pr)
		for i in 8:
			var rr := base_r * (1.0 - i * 0.11)
			var a := (0.045 + pr * 0.12) * float(i + 1) / 8.0 * flick
			draw_circle(c, rr, Color(center_color.r, center_color.g, center_color.b, a))


## A mango or water-drop game tile.
class IconTile:
	extends Control

	const COL_MANGO := Color("f3c200")
	const COL_MANGO_G := Color("6fa83b")
	const COL_WATER := Color("8cc1de")
	const COL_INK := Color("2a2a2a")

	var kind := 0
	var icon_tex: Texture2D
	var drop_tex: Texture2D

	func set_icon(k: int) -> void:
		kind = k
		queue_redraw()

	func _draw() -> void:
		var tex: Texture2D = icon_tex if kind == 0 else drop_tex
		if tex:
			draw_texture_rect_region(tex, Rect2(Vector2.ZERO, size), Rect2(0, 0, 150, 150))
			return
		var c := size * 0.5
		if kind == 0:
			_blob(c, size.x * 0.42, size.y * 0.4, COL_MANGO, 3.0)
			_blob(c + Vector2(-size.x * 0.2, size.y * 0.02), size.x * 0.17, size.y * 0.18, COL_MANGO_G, 0.0)
		else:
			var ctr := c + Vector2(0, size.y * 0.1)
			draw_circle(ctr, size.x * 0.3, COL_WATER)
			draw_arc(ctr, size.x * 0.3, 0, TAU, 28, COL_INK, 3.0)

	func _blob(center: Vector2, rx: float, ry: float, col: Color, outline_w: float) -> void:
		var pts := PackedVector2Array()
		for i in 30:
			var a := TAU * i / 30.0
			pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(pts, col)
		if outline_w > 0.0:
			var closed := pts.duplicate()
			closed.append(pts[0])
			draw_polyline(closed, COL_INK, outline_w)


## Hit disappear animation.
class _HitFx:
	extends Control

	const DUR := 0.34
	const SIZE := 168.0

	var drop_tex: Texture2D
	var mango_tex: Texture2D
	var kind := 0
	var fx_pos := Vector2.ZERO
	var life := 0.0
	var active := false

	func play(k: int, p: Vector2) -> void:
		kind = k
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
		var tex: Texture2D = mango_tex if kind == 0 else drop_tex
		if tex == null:
			return
		var f := clampf(life / DUR, 0.0, 1.0)
		var frame := clampi(int(f * 5.0), 0, 4)
		var a := 1.0 if f < 0.6 else (1.0 - (f - 0.6) / 0.4)
		var dst := Vector2(SIZE, SIZE) * (1.0 + f * 0.3)
		draw_texture_rect_region(tex, Rect2(fx_pos - dst * 0.5, dst),
			Rect2(frame * 150, 0, 150, 150), Color(1, 1, 1, a))


## Hold "savor" capsule with a mango at each end.
class _HoldFrame:
	extends Control

	const TOP_Y := 220.0
	const BOTTOM_Y := 500.0
	const H := 168.0
	const ICON := 130.0
	const COL_FRAME := Color("f3c200")
	const COL_FILL := Color("ffd66b")
	const COL_DIM := Color("e6d7a8")
	const COL_INK := Color("2a2a2a")

	var icon_tex: Texture2D
	var segments: Array = []
	var hot := false
	var pulse := 0.0
	var head_pop := 0.0

	func set_segments(segs: Array, h: bool, pl: float, hp: float) -> void:
		segments = segs
		hot = h
		pulse = pl
		head_pop = hp
		queue_redraw()

	func _draw() -> void:
		for s in segments:
			_bar(s["th"], s["tt"], TOP_Y)
			_bar(s["bh"], s["bt"], BOTTOM_Y)

	func _bar(head_x: float, tail_x: float, cy: float) -> void:
		var x0 := minf(head_x, tail_x)
		var x1 := maxf(head_x, tail_x)
		var pr := clampf(pulse, 0.0, 1.0)
		var r := H * (0.86 + 0.22 * pr) * 0.5
		var fillc := (COL_FILL if hot else COL_DIM).lerp(Color.WHITE, pr * 0.55)
		draw_circle(Vector2(x0, cy), r, fillc)
		draw_circle(Vector2(x1, cy), r, fillc)
		draw_rect(Rect2(x0, cy - r, x1 - x0, r * 2.0), fillc)
		var ow := 5.0 if hot else 4.0
		draw_arc(Vector2(x0, cy), r, PI * 0.5, PI * 1.5, 26, COL_INK, ow)
		draw_arc(Vector2(x1, cy), r, -PI * 0.5, PI * 0.5, 26, COL_INK, ow)
		draw_line(Vector2(x0, cy - r), Vector2(x1, cy - r), COL_INK, ow)
		draw_line(Vector2(x0, cy + r), Vector2(x1, cy + r), COL_INK, ow)
		draw_arc(Vector2(x0, cy), r - 2.5, PI * 0.5, PI * 1.5, 26, COL_FRAME, 2.5)
		draw_arc(Vector2(x1, cy), r - 2.5, -PI * 0.5, PI * 0.5, 26, COL_FRAME, 2.5)
		draw_line(Vector2(x0, cy - r + 2.5), Vector2(x1, cy - r + 2.5), COL_FRAME, 2.5)
		draw_line(Vector2(x0, cy + r - 2.5), Vector2(x1, cy + r - 2.5), COL_FRAME, 2.5)
		_mango(head_x, cy, 1.0 + pr * 0.12 + head_pop * 0.4)
		_mango(tail_x, cy, 1.0 + pr * 0.12)

	func _mango(x: float, cy: float, scale: float) -> void:
		if not icon_tex:
			return
		var s := ICON * scale
		draw_texture_rect_region(icon_tex, Rect2(Vector2(x, cy) - Vector2(s, s) * 0.5, Vector2(s, s)),
			Rect2(0, 0, 150, 150))


## Water-drop "heart" for health.
class _Droplet:
	extends Control

	const COL_WATER := Color("8cc1de")
	const COL_INK := Color("2a2a2a")
	var lost := false

	func set_lost(v: bool) -> void:
		lost = v
		queue_redraw()

	func _draw() -> void:
		var a := 0.2 if lost else 1.0
		var c := Color(COL_WATER.r, COL_WATER.g, COL_WATER.b, a)
		var ctr := size * 0.5 + Vector2(0, 4)
		draw_circle(ctr, 11.0, c)
		draw_colored_polygon(PackedVector2Array([
			ctr + Vector2(-8, 0), ctr + Vector2(0, -16), ctr + Vector2(8, 0),
		]), c)
		draw_arc(ctr, 11.0, 0, TAU, 22, Color(COL_INK.r, COL_INK.g, COL_INK.b, a), 2.0)


## Dim + vignette overlay used to spotlight a hold note.
class _Vignette:
	extends Control

	var intensity := 0.0

	func set_intensity(v: float) -> void:
		if absf(v - intensity) > 0.001:
			intensity = v
			queue_redraw()

	func _draw() -> void:
		if intensity <= 0.01:
			return
		var w := 1280.0
		var h := 720.0
		draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, intensity * 0.32))
		var bands := 14
		var depth := 190.0
		for i in bands:
			var a := intensity * 0.30 * (1.0 - float(i) / bands)
			var col := Color(0, 0, 0, a)
			var d := depth * (1.0 - float(i) / bands)
			draw_rect(Rect2(0, 0, w, d), col)
			draw_rect(Rect2(0, h - d, w, d), col)
			draw_rect(Rect2(0, 0, d, h), col)
			draw_rect(Rect2(w - d, 0, d, h), col)


## Breathing beat ring behind the PRESS button.
class _BeatRing:
	extends Control

	const CENTER := Vector2(640, 650)
	const COL := Color("f6b800")

	var pulse := 0.0

	func set_pulse(v: float) -> void:
		pulse = v
		queue_redraw()

	func _draw() -> void:
		var pr := clampf(pulse, 0.0, 1.0)
		var rad := lerpf(128.0, 74.0, pr)
		var a := lerpf(0.10, 0.5, pr)
		draw_circle(CENTER, rad, Color(COL.r, COL.g, COL.b, a * 0.5))
		draw_arc(CENTER, rad, 0, TAU, 48, Color(COL.r, COL.g, COL.b, a), 5.0)
