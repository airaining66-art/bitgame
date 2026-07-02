extends LevelBase

const RhythmChartScript := preload("res://rhythm/rhythm_chart.gd")
const BeatSlotJudgementScript := preload("res://rhythm/beat_slot_judgement.gd")
const BBQMusicScript := preload("res://bbq_music.gd")
## 1-4 烤串摊 - night-market BBQ skewer level.
## Ingredients scroll from right to left; press to skewer the next needed item
## shown on the right panel. After completing a skewer, hold the button to flip
## it; timing the flip matters! Flip too early/late = burn penalty.
##
## (Subclass of LevelBase: only the BBQ-specific theme/chart/judging/FX live
## here; HUD/Fever/result/countdown/pause/SFX-pool come from the base.)

# --- palette (night-market BBQ) --------------------------------------------
const COL_FIRE := Color("ff6b2b")
const COL_GOLD := Color("ffc107")
const COL_WARM := Color("f5e6d3")
const COL_MUTED := Color("7a6b5d")
const COL_BURN := Color("3a2a1a")
const COL_GREEN := Color("4caf50")
const COL_RED := Color("e2584f")
const COL_JUDGE := Color("ffe9b0")
const COL_COAL := Color("1a0e08")
const COL_TABLE := Color("3a2018")

# --- ingredients ------------------------------------------------------------
const BEEF     := 0
const PEPPER   := 1
const ONION    := 2
const MUSHROOM := 3
const BREAD    := 4
const LEEK     := 5

const INGREDIENT_NAMES := ["Beef", "Pepper", "Onion", "Mushroom", "Bread", "Leek"]
const INGREDIENT_COLS := [
	Color("c62828"),
	Color("ff6f00"),
	Color("7b1fa2"),
	Color("6d4c41"),
	Color("fff9c4"),
	Color("388e3c"),
]

# --- layout / timing --------------------------------------------------------
const SCROLL_Y := 220.0
const SKEWER_X := 300.0
const ORDER_X := 1020.0
const ORDER_Y := 100.0
const SPACING := 250.0
const TILE_SIZE := 80.0
const NOTE_SLOTS := 7
const JUDGE_OFFSET := 0.75
const MIN_PERFECT_MS := 120.0
const MIN_GOOD_MS := 230.0

var ORDERS: Array = []

# --- BBQ-specific state -----------------------------------------------------
var bbq_music: Node
var current_order_idx := 0
var order_item_idx := 0
var current_beat := 0
var current_beat_data: Dictionary = {}
var prev_beat_data: Dictionary = {}
var queue: Array[Dictionary] = []
var chart_i := 0
var chart_total_beats := 0
var _active_chart_beats: Array = []
var beat_judgement := BeatSlotJudgementScript.new()
var skewer_items: Array[int] = []
var grilled: Array = []

var flip_active := false
var flip_hold_beats := 0
var flip_total_beats := 0.0
var flip_start_clock := 0.0
var flip_judged := false

var key_held := false
var btn_held := false

# --- juice ------------------------------------------------------------------
var shake := 0.0
var fire_pulse := 0.0
var flip_anim := 0.0
var btn_pop := 0.0
var skewer_bounce := 0.0
var coal_pulse := 0.0

# --- nodes ------------------------------------------------------------------
var stage: Control
var scroll_track: Control
var grill_rack: _GrillRack
var order_panel: Control
var order_slots: Array = []
var scroll_tiles: Array = []
var hit_button: Button
var intro_layer: ColorRect
var intro_label: Label
var coals: _Coals
var flip_bar: _FlipBar
var sparks: _Sparks
var complete_pop: _CompletePop
var next_hint: _NextHint
# --- textures ---------------------------------------------------------------
var ingredient_sheet_path := "res://assets/levels/1-4_bbq/bbq_ingredients.png"
var ingredient_sheet: Texture2D
var flip_sheet_path := "res://assets/levels/1-4_bbq/bbq_flip.png"
var flip_sheet: Texture2D
var skewer_stick_path := "res://assets/levels/1-4_bbq/bbq_stick.png"
var skewer_stick_tex: Texture2D
var full_skewer_path := "res://assets/levels/1-4_bbq/bbq_full_skewer.png"
var full_skewer_tex: Texture2D
var bbq_background_path := "res://assets/levels/1-4_bbq/bbq_background.png"
var bbq_background_tex: Texture2D

# --- sfx --------------------------------------------------------------------
var snd_skewer: AudioStreamWAV
var snd_miss: AudioStreamWAV
var snd_flip: AudioStreamWAV
var snd_burn: AudioStreamWAV
var snd_complete: AudioStreamWAV

## Optional external sound paths. Leave blank to use synthesized effects.
var snd_skewer_path := ""
var snd_miss_path := ""
var snd_flip_path := ""
var snd_burn_path := ""
var snd_complete_path := ""


# ===========================================================================
# LevelBase hooks
# ===========================================================================
func make_cfg() -> Dictionary:
	return {
		"duration_ms": 44000.0, "start_bpm": 84.0, "end_bpm": 118.0,
		"bpm_curve_exp": 1.5, "subdivisions": 4,
	}


func _auto_finish() -> bool:
	return false   # chart 濡炵懓宕慨鈺冪磼閹惧瓨灏?

func _make_music() -> Node:
	bbq_music = setup_chart_music("1-4", BBQMusicScript)
	return bbq_music


func _conf() -> Dictionary:
	return {
		"score_caption": "烤串",
		"text_col": COL_WARM, "muted_col": COL_MUTED,
		"countdown_col": COL_FIRE, "penalty_col": COL_RED,
		"fever_text": "FEVER!!", "fever_col": COL_FIRE, "fever_fill": COL_GOLD,
		"fever_overlay": Color(1.0, 0.42, 0.17), "fever_overlay_a": 0.08,
		"result_bg": Color("1a0e08"), "result_border": COL_FIRE,
		"title_col": COL_GOLD, "lose_col": COL_RED,
		"eval_bg": Color("2a1610"), "eval_border": Color("4a2a18"),
		"again_label": "再来一局",
		"score_fmt": "烤串 %d  命中 %d%%  最高 %d%s",
		"grade_cols": {"S": COL_FIRE, "A": COL_GOLD, "B": COL_GREEN, "C": COL_WARM, "D": COL_MUTED},
	}


func _build_level() -> void:
	_load_textures()
	_build_scene()
	_build_scroll_track()
	_build_order_panel()
	_build_skewer()
	_build_next_hint()
	_build_fx()
	_build_button()
	_build_intro()


func _load_textures() -> void:
	if ingredient_sheet_path != "":
		ingredient_sheet = _load_tex([ingredient_sheet_path])
	if flip_sheet_path != "":
		flip_sheet = _load_tex([flip_sheet_path])
	if skewer_stick_path != "":
		skewer_stick_tex = _load_tex([skewer_stick_path])
	if full_skewer_path != "":
		full_skewer_tex = _load_tex([full_skewer_path])
	if bbq_background_path != "":
		bbq_background_tex = _load_tex([bbq_background_path])


func _build_sfx() -> void:
	snd_skewer = _load_external_sfx(snd_skewer_path, 520.0, 380.0, 0.10, "sine", 0.45)
	snd_miss = _load_external_sfx(snd_miss_path, 200.0, 100.0, 0.15, "sine", 0.4)
	snd_flip = _load_external_sfx(snd_flip_path, 700.0, 900.0, 0.08, "triangle", 0.5)
	snd_burn = _load_external_sfx(snd_burn_path, 150.0, 80.0, 0.25, "sawtooth", 0.35)
	snd_complete = _load_external_sfx(snd_complete_path, 600.0, 800.0, 0.15, "sine", 0.5)


func _load_external_sfx(path: String, freq: float, slide: float, dur: float,
		wave: String, gain: float) -> AudioStreamWAV:
	if path != "" and ResourceLoader.exists(path):
		var res := load(path)
		if res is AudioStreamWAV:
			return res
	return tone(freq, slide, dur, wave, gain)


func _make_heart() -> Control:
	var d := _FireHeart.new()
	d.custom_minimum_size = Vector2(30, 30)
	return d


func _reset_level() -> void:
	current_order_idx = 0
	order_item_idx = 0
	current_beat = 0
	beat_judgement.reset()
	skewer_items.clear()
	grilled.clear()
	flip_active = false
	flip_hold_beats = 0
	flip_total_beats = 0.0
	flip_start_clock = 0.0
	flip_judged = false
	key_held = false
	btn_held = false
	shake = 0.0
	fire_pulse = 0.0
	flip_anim = 0.0
	btn_pop = 0.0
	skewer_bounce = 0.0
	prepare_beats()
	_update_order_display()


func _enter_start() -> void:
	_enter_intro()


func _begin_play() -> void:
	set_tiles_visible(true)
	set_feedback("开烤！", COL_FIRE)
	_update_order_display()


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
	play_sfx(snd_skewer if last else snd_miss, -8.0)


func _advance(_delta: float) -> void:
	_update_flip_hold()
	_layout_ingredients()
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
	# Let the music prepare its ending once the chart tail is in queue.
	if bbq_music and bbq_music.get("finale") == false:
		for q in queue:
			if q.get("end", false):
				bbq_music.set("finale", true)
				break
	if current_beat_data.get("end", false):
		_start_outro()


func _outro_fx() -> void:
	set_feedback("收摊啦！", COL_GOLD)
	fire_pulse = 1.0
	skewer_bounce = 1.0


func _verdict(hearts_lost: int, won: bool) -> Dictionary:
	if won:
		match hearts_lost:
			0: return {"rank": "烧烤之神", "eval": "火候稳得离谱，一串都没糊。"}
			1: return {"rank": "夜市老手", "eval": "有点烟火气，但还是香。"}
			_: return {"rank": "还能入口", "eval": "糊了几串，摊子还在。"}
	if app and app.extreme:
		return {"rank": "炭火暴走", "eval": "火太大，串没跟上。"}
	return {"rank": "烤糊了", "eval": "这一局烤架赢了。"}


# ===========================================================================
# Beat generation
# ===========================================================================
func make_beat() -> Dictionary:
	if not _active_chart_beats.is_empty():
		if chart_i >= _active_chart_beats.size():
			return {"ingredient": -1, "is_flip": false, "should_press": false, "end": true}
		var beat_data: Dictionary = _active_chart_beats[chart_i]
		chart_i += 1
		return beat_data.duplicate(true)
	return {"ingredient": -1, "is_flip": false, "should_press": false, "end": true}


func _current_needed() -> int:
	if current_order_idx >= ORDERS.size():
		return -1
	var order: Array = ORDERS[current_order_idx]
	if order_item_idx >= order.size():
		return -1
	return order[order_item_idx]


func ensure_queue() -> void:
	while queue.size() < 5:
		queue.append(make_beat())


func prepare_beats() -> void:
	queue = []
	_active_chart_beats = _load_editor_chart_beats()
	if _active_chart_beats.is_empty():
		push_warning("Missing RhythmChart for 1-4; level has no script fallback chart.")
	chart_i = 0
	chart_total_beats = _active_chart_beats.size()
	_build_orders_from_chart()
	ensure_queue()
	current_beat_data = queue.pop_front()
	ensure_queue()


func _build_orders_from_chart() -> void:
	ORDERS.clear()
	var current_order: Array = []
	for beat_data in _active_chart_beats:
		if beat_data.get("is_flip", false):
			if current_order.size() > 0:
				ORDERS.append(current_order.duplicate())
				current_order.clear()
		else:
			var ing := int(beat_data.get("ingredient", -1))
			if ing >= 0 and beat_data.get("should_press", false):
				current_order.append(ing)
	if current_order.size() > 0:
		ORDERS.append(current_order.duplicate())
	if ORDERS.is_empty():
		ORDERS.append([BEEF, PEPPER, ONION])


func _load_editor_chart_beats() -> Array:
	return chart_slots_for("1-4", 1,
		Callable(self, "_chart_note_to_beat"),
		{"ingredient": -1, "is_flip": false, "should_press": false, "_priority": 0},
		{"ingredient": -1, "is_flip": false, "should_press": false, "end": true})


func _chart_note_to_beat(note: Dictionary) -> Dictionary:
	var judge := str(note.get("judge_type", RhythmChartScript.JUDGE_NONE))
	var kind := str(note.get("kind", "rest"))
	if kind == "flip" or judge == RhythmChartScript.JUDGE_HOLD:
		return {"ingredient": -1, "is_flip": true, "should_press": true,
			"flip_len": maxf(0.25, float(note.get("duration_beats", 2.0))),
			"_priority": 3}
	var ing := _kind_to_ingredient(kind)
	return {
		"ingredient": ing,
		"is_flip": false,
		"should_press": judge != RhythmChartScript.JUDGE_NONE and ing >= 0,
		"_priority": 2 if judge != RhythmChartScript.JUDGE_NONE else 1,
	}


func _kind_to_ingredient(kind: String) -> int:
	match kind:
		"beef": return BEEF
		"pepper": return PEPPER
		"onion": return ONION
		"mushroom": return MUSHROOM
		"bread": return BREAD
		"leek": return LEEK
		_: return -1


# ===========================================================================
# Judging
# ===========================================================================
func is_holding() -> bool:
	return key_held or btn_held

# Chart-driven ingredient / flip judging.
func _press_down() -> void:
	if phase != "running":
		return
	btn_pop = 1.0
	shake = maxf(shake, 2.0)

	var cur := current_beat_data

	if cur.get("is_flip", false) and not flip_active:
		if beat_judgement.was_judged(current_beat):
			return
		beat_judgement.mark_judged(current_beat)
		_start_flip_hold()
		return

	if flip_active:
		return

	var ing := int(cur.get("ingredient", -1))
	if ing < 0:
		beat_judgement.mark_judged(current_beat)
		return
	var result := beat_judgement.judge_press(current_beat,
		bool(cur.get("should_press", false)), _judge_delta(),
		perfect_window(), good_window())
	var kind := str(result.get("result", ""))
	if kind == BeatSlotJudgementScript.RESULT_REPEAT:
		return
	if kind == BeatSlotJudgementScript.RESULT_WRONG:
		apply_penalty("别乱叉！")
	elif kind == BeatSlotJudgementScript.RESULT_PERFECT:
		reward("Perfect", 120)
	elif kind == BeatSlotJudgementScript.RESULT_GOOD:
		reward("Good", 80)
	else:
		apply_penalty("手慢了")


func _press_up() -> void:
	if phase != "running":
		return
	# Releasing during a flip hold burns the skewer.
	if flip_active:
		_fail_flip()


func _judge_delta() -> float:
	return absf(conductor.beat_phase() - JUDGE_OFFSET) * conductor.cycle_duration


func perfect_window() -> float:
	return maxf(MIN_PERFECT_MS, conductor.cycle_duration * 0.14)


func good_window() -> float:
	return maxf(MIN_GOOD_MS, conductor.cycle_duration * 0.28)


func _beat_clock() -> float:
	return float(current_beat) + (conductor.beat_phase() if conductor else 0.0)


func _update_flip_hold() -> void:
	if not flip_active:
		return
	if _beat_clock() >= flip_start_clock + maxf(flip_total_beats, 0.25):
		_complete_flip()


func _start_flip_hold() -> void:
	flip_active = true
	flip_total_beats = maxf(0.25, float(current_beat_data.get("flip_len", 2.0)))
	flip_hold_beats = ceili(flip_total_beats)
	flip_start_clock = _beat_clock()
	flip_judged = false
	set_feedback("翻面！按住别松", COL_FIRE)
	play_sfx(snd_flip)
	flip_anim = 0.5


func _complete_flip() -> void:
	flip_active = false
	flip_judged = true
	if is_holding():
		_add_score(80)
		_fever_hit()
		play_sfx(snd_complete)
		set_feedback("翻面完成！", COL_GOLD)
		fire_pulse = 1.0
		skewer_bounce = 1.0
		flip_anim = 0.0
		sparks.emit(Vector2(SKEWER_X, SCROLL_Y), COL_GOLD, 26)
		complete_pop.trigger()
		_complete_order()
	else:
		_fail_flip()


func _fail_flip() -> void:
	flip_active = false
	flip_judged = true
	play_sfx(snd_burn)
	set_feedback("翻面失败！", COL_BURN)
	shake = maxf(shake, 12.0)
	combo = 0
	if fever_active:
		_end_fever()
	score = maxi(0, score - 50)
	update_hud()
	flip_anim = 0.0
	_complete_order()


func _resolve_boundary() -> void:
	if phase != "running":
		return
	var cur := current_beat_data
	if beat_judgement.was_judged(current_beat):
		return

	if cur.get("is_flip", false):
		beat_judgement.mark_judged(current_beat)
		if not flip_active:
			_fail_flip()
		return
	if flip_active:
		return

	var ing := int(cur.get("ingredient", -1))
	var result := beat_judgement.resolve_slot(current_beat,
		bool(cur.get("should_press", false)) and ing >= 0)
	var kind := str(result.get("result", ""))
	if kind == BeatSlotJudgementScript.RESULT_REPEAT:
		return
	if kind == BeatSlotJudgementScript.RESULT_MISS:
		order_item_idx += 1
		_update_order_display()
		apply_penalty("漏掉了")
	elif ing >= 0:
		set_feedback("先别叉", COL_MUTED)


func reward(kind: String, points: int) -> void:
	_add_score(points)
	_fever_hit()
	play_sfx(snd_skewer)
	set_feedback("完美" if kind == "Perfect" else "不错", COL_GOLD if kind == "Perfect" else COL_GREEN)
	var ing := int(current_beat_data.get("ingredient", _current_needed()))
	skewer_items.append(ing)
	order_item_idx += 1
	fire_pulse = 1.0
	skewer_bounce = 0.5
	var burst_col := COL_GOLD if kind == "Perfect" else COL_FIRE
	sparks.emit(Vector2(SKEWER_X, SCROLL_Y), burst_col, 14 if kind == "Perfect" else 9)
	_update_order_display()


func _complete_order() -> void:
	current_order_idx += 1
	order_item_idx = 0
	if skewer_items.size() > 0:
		grilled.append(skewer_items.duplicate())
	skewer_items.clear()
	_update_order_display()


func apply_penalty(text: String) -> void:
	play_sfx(snd_miss)
	shake = maxf(shake, 9.0)
	super.apply_penalty(text)


func flash_button() -> void:
	btn_pop = 1.0


# ===========================================================================
# Build
# ===========================================================================
func _build_scene() -> void:
	var world := _NightMarket.new()
	world.bg_tex = bbq_background_tex
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)

	stage = Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.pivot_offset = Vector2(640, 360)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

	coals = _Coals.new()
	coals.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	coals.offset_top = -185
	coals.offset_bottom = -70
	coals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(coals)

	var table := ColorRect.new()
	table.color = Color(COL_TABLE.r, COL_TABLE.g, COL_TABLE.b, 0.0 if bbq_background_tex != null else 1.0)
	table.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	table.offset_top = -60
	table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(table)


func _build_scroll_track() -> void:
	scroll_track = Control.new()
	scroll_track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(scroll_track)

	var judge_line := ColorRect.new()
	judge_line.color = Color(COL_FIRE.r, COL_FIRE.g, COL_FIRE.b, 0.4)
	judge_line.position = Vector2(SKEWER_X - 2, SCROLL_Y - 60)
	judge_line.size = Vector2(4, 120)
	judge_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_track.add_child(judge_line)

	var judge_label := Label.new()
	judge_label.text = "叉取"
	judge_label.add_theme_font_size_override("font_size", 16)
	judge_label.add_theme_color_override("font_color", Color(COL_FIRE.r, COL_FIRE.g, COL_FIRE.b, 0.6))
	judge_label.position = Vector2(SKEWER_X - 24, SCROLL_Y - 80)
	judge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_track.add_child(judge_label)

	for i in NOTE_SLOTS:
		var tile := _IngredientTile.new()
		tile.size = Vector2(TILE_SIZE, TILE_SIZE)
		tile.pivot_offset = Vector2(TILE_SIZE, TILE_SIZE) * 0.5
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.sheet = ingredient_sheet
		tile.flip_tex = flip_sheet
		tile.visible = false
		scroll_track.add_child(tile)
		scroll_tiles.append(tile)

	flip_bar = _FlipBar.new()
	flip_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flip_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flip_bar.visible = false
	scroll_track.add_child(flip_bar)


func _build_order_panel() -> void:
	order_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1a1420")
	sb.set_border_width_all(3)
	sb.border_color = COL_FIRE
	sb.set_corner_radius_all(10)
	order_panel.add_theme_stylebox_override("panel", sb)
	order_panel.custom_minimum_size = Vector2(160, 420)
	order_panel.position = Vector2(ORDER_X, ORDER_Y)
	order_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(order_panel)

	var cap := Label.new()
	cap.text = "订单"
	cap.add_theme_font_size_override("font_size", 18)
	cap.add_theme_color_override("font_color", COL_FIRE)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.position = Vector2(0, 8)
	cap.size = Vector2(160, 24)
	order_panel.add_child(cap)

	var stick := ColorRect.new()
	stick.color = Color("8d6e4c")
	stick.position = Vector2(78, 40)
	stick.size = Vector2(4, 360)
	stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	order_panel.add_child(stick)

	for i in 6:
		var slot := _OrderSlot.new()
		slot.position = Vector2(30, 50 + i * 58)
		slot.size = Vector2(100, 48)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.sheet = ingredient_sheet
		slot.visible = false
		order_panel.add_child(slot)
		order_slots.append(slot)


func _build_skewer() -> void:
	grill_rack = _GrillRack.new()
	grill_rack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grill_rack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grill_rack.stick_tex = skewer_stick_tex
	grill_rack.sheet = ingredient_sheet
	stage.add_child(grill_rack)


func _build_next_hint() -> void:
	# Preview of the next required ingredient or flip action.
	next_hint = _NextHint.new()
	next_hint.position = Vector2(SKEWER_X - 60, SCROLL_Y + 72)
	next_hint.size = Vector2(120, 100)
	next_hint.sheet = ingredient_sheet
	next_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(next_hint)


func _build_fx() -> void:
	sparks = _Sparks.new()
	sparks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sparks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(sparks)

	complete_pop = _CompletePop.new()
	complete_pop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	complete_pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	complete_pop.tex = full_skewer_tex
	complete_pop.anchor_pos = Vector2(SKEWER_X, SCROLL_Y + 40)
	stage.add_child(complete_pop)


func _build_button() -> void:
	hit_button = Button.new()
	hit_button.text = "叉一下"
	hit_button.custom_minimum_size = Vector2(220, 88)
	hit_button.add_theme_font_size_override("font_size", 28)
	hit_button.focus_mode = Control.FOCUS_NONE
	hit_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("1a0e08")
	normal.set_border_width_all(4)
	normal.border_color = COL_FIRE
	normal.set_corner_radius_all(10)
	hit_button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color("2a1a10")
	hit_button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = COL_FIRE
	hit_button.add_theme_stylebox_override("pressed", pressed)
	for s in ["font_color", "font_hover_color"]:
		hit_button.add_theme_color_override(s, COL_FIRE)
	hit_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	hit_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hit_button.position = Vector2(-110, -100)
	hit_button.pivot_offset = Vector2(110, 44)
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
	sb.bg_color = Color("1a0e08")
	sb.set_border_width_all(4)
	sb.border_color = COL_FIRE
	sb.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(640, 220)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.position = Vector2(-320, -110)
	intro_layer.add_child(card)

	intro_label = Label.new()
	intro_label.add_theme_font_size_override("font_size", 26)
	intro_label.add_theme_color_override("font_color", COL_WARM)
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
# Order display
# ===========================================================================
func _update_order_display() -> void:
	for i in order_slots.size():
		var slot: _OrderSlot = order_slots[i]
		if current_order_idx >= ORDERS.size():
			slot.visible = false
			continue
		var order: Array = ORDERS[current_order_idx]
		if i < order.size():
			slot.visible = true
			slot.set_item(order[i], i < order_item_idx, i == order_item_idx)
		else:
			slot.visible = false
	if next_hint:
		var nd := _current_needed()
		var flip_pending := nd < 0 and current_order_idx < ORDERS.size()
		next_hint.set_next(nd, flip_pending)


# ===========================================================================
# Tiles layout
# ===========================================================================
func _layout_ingredients() -> void:
	var bp := conductor.beat_phase()

	if flip_active:
		flip_bar.visible = true
		var total_beats := maxf(flip_total_beats, 0.25)
		var progress := (_beat_clock() - flip_start_clock) / total_beats
		progress = clampf(progress, 0.0, 1.0)
		flip_bar.set_data(SKEWER_X, SCROLL_Y + 60, progress, is_holding())
	else:
		flip_bar.visible = false

	for slot in NOTE_SLOTS:
		var k := slot - 1
		var note := _note_at(k)
		if note.is_empty() or note.get("end", false):
			scroll_tiles[slot].visible = false
			continue
		var ing := int(note.get("ingredient", -1))
		var is_flip: bool = note.get("is_flip", false)
		var bu := float(k) + JUDGE_OFFSET - bp
		if bu < -0.4 or bu > float(NOTE_SLOTS):
			scroll_tiles[slot].visible = false
			continue
		var tile: _IngredientTile = scroll_tiles[slot]
		tile.visible = true
		if is_flip:
			tile.set_flip()
		else:
			var needed := _current_needed()
			tile.set_ingredient(ing, ing == needed and ing >= 0)
		# Snap very small timing jitter to the judge line.
		var half := 17.5 / maxf(conductor.cycle_duration, 1.0)
		var bu_x := bu
		if absf(bu_x) <= half:
			bu_x = 0.0
		else:
			bu_x -= signf(bu_x) * half
		tile.position = Vector2(SKEWER_X + bu_x * SPACING - TILE_SIZE * 0.5,
				SCROLL_Y - TILE_SIZE * 0.5)
		tile.scale = Vector2.ONE


func _note_at(k: int) -> Dictionary:
	if k == -1:
		return prev_beat_data
	if k == 0:
		return current_beat_data
	if k >= 1 and k - 1 < queue.size():
		return queue[k - 1]
	return {}


func set_tiles_visible(v: bool) -> void:
	for tile in scroll_tiles:
		tile.visible = v


# ===========================================================================
# Intro
# ===========================================================================
func _enter_intro() -> void:
	phase = "intro"
	intro_label.text = "按照订单叉食材。\n串满之后按住翻面，别松手。" if not (app and app.extreme) \
		else "极限炭火模式，翻面更要稳。"
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
	fire_pulse = move_toward(fire_pulse, 0.0, delta * 3.0)
	flip_anim = move_toward(flip_anim, 0.0, delta * 2.5)
	btn_pop = move_toward(btn_pop, 0.0, delta * 5.0)
	skewer_bounce = move_toward(skewer_bounce, 0.0, delta * 4.0)
	coal_pulse = p

	stage.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
	coals.pulse = p
	coals.fire_flash = fire_pulse

	if flip_active and is_holding():
		var fl := 0.5 + 0.5 * sin(t * 22.0)
		hit_button.scale = Vector2.ONE * (1.0 + 0.07 * fl)
		hit_button.modulate = Color.WHITE.lerp(COL_FIRE, 0.45 + 0.45 * fl)
	else:
		hit_button.scale = Vector2.ONE * (1.0 + 0.15 * btn_pop)
		hit_button.modulate = Color.WHITE.lerp(COL_FIRE, btn_pop * 0.5)

	grill_rack.grilled = grilled
	grill_rack.current = skewer_items
	grill_rack.bounce = skewer_bounce
	grill_rack.flip_progress = flip_anim
	grill_rack.queue_redraw()


# ===========================================================================
# Inner visual classes
# ===========================================================================

class _IngredientTile:
	extends Control

	var kind := -1
	var is_needed := false
	var is_flip := false
	var sheet: Texture2D
	var flip_tex: Texture2D
	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func set_ingredient(k: int, needed: bool) -> void:
		kind = k
		is_needed = needed
		is_flip = false
		queue_redraw()

	func set_flip() -> void:
		is_flip = true
		kind = -1
		queue_redraw()

	func _draw() -> void:
		if is_flip:
			if flip_tex:
				var fw := flip_tex.get_width() * 0.5
				var fh := float(flip_tex.get_height())
				draw_texture_rect_region(flip_tex, Rect2(Vector2.ZERO, size),
					Rect2(0, 0, fw, fh))
			else:
				var c := size * 0.5
				draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.42, 0.17, 0.53))
				draw_circle(c + Vector2(0, -8), 18.0, Color("ff6b2b"))
				draw_circle(c + Vector2(-10, 4), 10.0, Color("ffc107"))
				draw_circle(c + Vector2(10, 4), 10.0, Color("ffc107"))
				draw_circle(c + Vector2(0, 10), 8.0, Color("ff6b2b"))
			return
		if kind < 0:
			return
		if sheet:
			var fw := sheet.get_width() / 6.0
			var fh := float(sheet.get_height())
			draw_texture_rect_region(sheet, Rect2(Vector2.ZERO, size),
				Rect2(kind * fw, 0, fw, fh))
			return
		var col: Color = INGREDIENT_COLS[kind]
		draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), col)
		var font := ThemeDB.fallback_font
		var name_str: String = INGREDIENT_NAMES[kind]
		var font_size := 18
		var ts := font.get_string_size(name_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, Vector2(size.x * 0.5 - ts.x * 0.5, size.y * 0.5 + ts.y * 0.3),
			name_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size,
			Color.WHITE if col.get_luminance() < 0.5 else Color.BLACK)

	const INGREDIENT_NAMES := ["Beef", "Pepper", "Onion", "Mushroom", "Bread", "Leek"]
	const INGREDIENT_COLS := [
		Color("c62828"), Color("ff6f00"), Color("7b1fa2"),
		Color("6d4c41"), Color("fff9c4"), Color("388e3c"),
	]
	const COL_GOLD := Color("ffc107")


class _OrderSlot:
	extends Control

	var item_kind := -1
	var filled := false
	var current := false
	var sheet: Texture2D
	var t := 0.0

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _process(delta: float) -> void:
		if current:
			t += delta
			queue_redraw()

	func set_item(kind: int, is_filled: bool, is_current: bool) -> void:
		item_kind = kind
		filled = is_filled
		current = is_current
		queue_redraw()

	func _draw() -> void:
		if item_kind < 0:
			return
		if sheet:
			var fw := sheet.get_width() / 6.0
			var fh := float(sheet.get_height())
			if filled:
				draw_texture_rect_region(sheet, Rect2(Vector2.ZERO, size),
					Rect2(item_kind * fw, 0, fw, fh))
			elif current:
				var pl := 0.5 + 0.5 * sin(t * 6.0)
				draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.76, 0.03, 0.25 + 0.25 * pl))
				draw_rect(Rect2(Vector2.ZERO, size), Color("ffc107"), false, 2.0 + 2.0 * pl)
				draw_texture_rect_region(sheet, Rect2(Vector2.ZERO, size),
					Rect2(item_kind * fw, 0, fw, fh), Color(1, 1, 1, 0.6 + 0.4 * pl))
			else:
				draw_texture_rect_region(sheet, Rect2(Vector2.ZERO, size),
					Rect2(item_kind * fw, 0, fw, fh), Color(0.3, 0.3, 0.3, 0.5))
			return
		var col: Color = _OrderSlot.INGREDIENT_COLS[item_kind]
		if filled:
			draw_rect(Rect2(Vector2.ZERO, size), col)
			var font := ThemeDB.fallback_font
			var name_str: String = _OrderSlot.INGREDIENT_NAMES[item_kind]
			draw_string(font, Vector2(size.x * 0.5 - 20, size.y * 0.5 + 6),
				name_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 16,
				Color.WHITE if col.get_luminance() < 0.5 else Color.BLACK)
		elif current:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.76, 0.03, 0.4))
			draw_rect(Rect2(Vector2.ZERO, size), Color("ffc107"), false, 3.0)
			var font := ThemeDB.fallback_font
			var name_str: String = _OrderSlot.INGREDIENT_NAMES[item_kind]
			draw_string(font, Vector2(size.x * 0.5 - 20, size.y * 0.5 + 6),
				name_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color("ffc107"))
		else:
			draw_rect(Rect2(Vector2.ZERO, size), Color(col.r * 0.3, col.g * 0.3, col.b * 0.3, 0.5))
			draw_rect(Rect2(Vector2.ZERO, size), Color("7a6b5d"), false, 2.0)

	const INGREDIENT_NAMES := ["Beef", "Pepper", "Onion", "Mushroom", "Bread", "Leek"]
	const INGREDIENT_COLS := [
		Color("c62828"), Color("ff6f00"), Color("7b1fa2"),
		Color("6d4c41"), Color("fff9c4"), Color("388e3c"),
	]


class _GrillRack:
	extends Control

	var grilled: Array = []
	var current: Array = []
	var bounce := 0.0
	var flip_progress := 0.0
	var t := 0.0
	var sheet: Texture2D
	var stick_tex: Texture2D

	const BASE_Y := 628.0
	const SLOT_H := 22.0
	const SLOT_W := 40.0
	const START_X := 150.0
	const STEP_X := 88.0
	const RIGHT_LIMIT := 980.0
	const COL_STICK := Color("8d6e4c")
	const INGREDIENT_COLS := [
		Color("c62828"), Color("ff6f00"), Color("7b1fa2"),
		Color("6d4c41"), Color("fff9c4"), Color("388e3c"),
	]

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var rows: Array = []
		for s in grilled:
			rows.append(s)
		var has_live := current.size() > 0
		if has_live:
			rows.append(current)
		var n := rows.size()
		if n == 0:
			return
		var step := STEP_X
		if n > 1:
			step = minf(STEP_X, (RIGHT_LIMIT - START_X) / float(n - 1))
		# Draw the skewer baseline under the visible ingredients.
		var x_end := START_X + step * float(n - 1) + SLOT_W
		draw_line(Vector2(START_X - SLOT_W, BASE_Y + 4.0), Vector2(x_end, BASE_Y + 4.0),
			Color(0.35, 0.18, 0.08, 0.6), 3.0)
		for i in n:
			var live := has_live and i == n - 1
			_draw_skewer(START_X + step * float(i), rows[i], live)

	func _draw_skewer(cx: float, items: Array, live: bool) -> void:
		var cnt := items.size()
		if cnt == 0:
			return
		var top_y := BASE_Y - float(cnt) * SLOT_H - 12.0
		if stick_tex:
			var sw := float(stick_tex.get_width())
			var sh := float(stick_tex.get_height())
			var sy := (BASE_Y - top_y) / sh
			draw_texture_rect(stick_tex,
				Rect2(cx - sw * sy * 0.5, top_y, sw * sy, BASE_Y - top_y), false)
		else:
			draw_rect(Rect2(cx - 2.0, top_y, 4.0, BASE_Y - top_y), COL_STICK)
		var glow := 0.0
		var lift := 0.0
		if live:
			glow = 0.3 + 0.25 * sin(t * 6.0)
			lift = bounce * 4.0
		for j in cnt:
			var ing: int = items[j]
			var y := top_y + 8.0 + float(j) * SLOT_H - lift
			var r := Rect2(cx - SLOT_W * 0.5, y, SLOT_W, SLOT_H * 0.92)
			if sheet:
				var fw := sheet.get_width() / 6.0
				var fh := float(sheet.get_height())
				draw_texture_rect_region(sheet, r, Rect2(ing * fw, 0, fw, fh))
			else:
				draw_rect(r, INGREDIENT_COLS[ing])
			if glow > 0.0:
				draw_rect(r, Color(1.0, 0.5, 0.15, glow * 0.4))


class _NextHint:
	extends Control

	var kind := -1
	var flip_pending := false
	var sheet: Texture2D
	var t := 0.0

	const COL_FIRE := Color("ff6b2b")
	const COL_GOLD := Color("ffc107")
	const COL_WARM := Color("f5e6d3")
	const COL_BG := Color("1a0e08")
	const INGREDIENT_COLS := [
		Color("c62828"), Color("ff6f00"), Color("7b1fa2"),
		Color("6d4c41"), Color("fff9c4"), Color("388e3c"),
	]

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func set_next(k: int, flip: bool) -> void:
		kind = k
		flip_pending = flip
		queue_redraw()

	func _draw() -> void:
		if kind < 0 and not flip_pending:
			return
		var pl := 0.5 + 0.5 * sin(t * 4.0)
		var panel := Rect2(Vector2.ZERO, size)
		draw_rect(panel, Color(COL_BG.r, COL_BG.g, COL_BG.b, 0.82))
		draw_rect(panel, Color(COL_FIRE.r, COL_FIRE.g, COL_FIRE.b, 0.5 + 0.4 * pl), false, 2.0)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(10, 22), "下一个", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_WARM)
		var icon := Rect2(size.x * 0.5 - 28, 32, 56, 56)
		if flip_pending:
			var c := icon.position + icon.size * 0.5
			draw_circle(c, 24.0, Color(COL_FIRE.r, COL_FIRE.g, COL_FIRE.b, 0.25 + 0.3 * pl))
			draw_string(font, Vector2(icon.position.x - 10, c.y + 7), "翻面",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, COL_GOLD)
			return
		if sheet:
			draw_rect(icon.grow(3.0), Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.16 + 0.18 * pl))
			var fw := sheet.get_width() / 6.0
			var fh := float(sheet.get_height())
			draw_texture_rect_region(sheet, icon, Rect2(kind * fw, 0, fw, fh))
		else:
			draw_rect(icon, INGREDIENT_COLS[kind])


class _Coals:
	extends Control

	var pulse := 0.0
	var fire_flash := 0.0
	var t := 0.0
	var embers: Array = []
	var smoke: Array = []
	var overlay_only := true

	func _ready() -> void:
		for i in 30:
			embers.append({
				"x": randf_range(40, 1240),
				"y": randf_range(10, 70),
				"speed": randf_range(30, 80),
				"size": randf_range(3, 8),
				"phase": randf() * TAU,
			})
		for i in 9:
			smoke.append({
				"x": randf_range(80, 1200),
				"y": randf_range(0, 120),
				"speed": randf_range(18, 38),
				"size": randf_range(20, 46),
				"phase": randf() * TAU,
			})

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var w := 1280.0
		var h := 100.0
		if overlay_only:
			_draw_fire_overlay()
			return
		for sm in smoke:
			var sx: float = sm["x"] + sin(t * 0.7 + sm["phase"]) * 18.0
			var sy: float = sm["y"] - fposmod(t * sm["speed"], 180.0)
			var grow: float = 1.0 + (120.0 - sy) / 120.0
			var sa := clampf((sy + 40.0) / 160.0, 0.0, 1.0) * 0.10
			draw_circle(Vector2(sx, sy), sm["size"] * grow, Color(0.7, 0.6, 0.55, sa))
		draw_rect(Rect2(0, 0, w, h), Color("1a0e08"))
		for i in 16:
			var cx := 40.0 + i * 78.0
			var cy := 50.0 + sin(i * 1.3) * 15.0
			var pr := clampf(pulse, 0.0, 1.0)
			var glow := Color(1.0, 0.3, 0.1, 0.3 + pr * 0.4 + fire_flash * 0.3)
			draw_circle(Vector2(cx, cy), 28.0, Color("2a1a10"))
			draw_circle(Vector2(cx, cy), 18.0, glow)
		for e in embers:
			var x: float = e["x"]
			var y: float = e["y"]
			var s: float = e["size"]
			var ph: float = e["phase"]
			y -= t * e["speed"]
			y = fposmod(y, h + 20.0)
			var a := 0.3 + 0.3 * sin(t * 5.0 + ph)
			draw_circle(Vector2(x, y), s, Color(1.0, 0.5, 0.15, a))

	func _draw_fire_overlay() -> void:
		var breath := 0.5 + 0.5 * sin(t * 3.2)
		var beat := clampf(pulse, 0.0, 1.0)
		var flash := clampf(fire_flash, 0.0, 1.0)
		var a := 0.18 + breath * 0.12 + beat * 0.08 + flash * 0.18
		var center := Vector2(640.0, 56.0)
		for i in 9:
			var frac := float(i) / 8.0
			var rx := lerpf(460.0, 140.0, frac)
			var ry := lerpf(56.0, 18.0, frac)
			var col := Color(1.0, lerpf(0.18, 0.72, frac), 0.03, a * (1.0 - frac * 0.78))
			_draw_ellipse(center, rx, ry, col)
		for e in embers:
			var x: float = 205.0 + fposmod(float(e["x"]) + t * 12.0, 870.0)
			var y: float = 24.0 + fposmod(float(e["y"]) - t * e["speed"], 72.0)
			var s: float = float(e["size"]) * 0.55
			var ph: float = e["phase"]
			var ea := (0.12 + 0.25 * sin(t * 5.0 + ph)) * (0.6 + breath * 0.4)
			draw_circle(Vector2(x, y), s, Color(1.0, 0.45, 0.12, ea))

	func _draw_ellipse(center: Vector2, rx: float, ry: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 36:
			var a := TAU * float(i) / 36.0
			pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(pts, col)


class _FireHeart:
	extends Control

	var lost := false

	func set_lost(v: bool) -> void:
		lost = v
		queue_redraw()

	func _draw() -> void:
		var a := 0.22 if lost else 1.0
		var c := size * 0.5
		var r := 11.0
		var col := Color(1.0, 0.42, 0.17, a)
		draw_circle(c + Vector2(-r * 0.5, -r * 0.25), r * 0.5, col)
		draw_circle(c + Vector2(r * 0.5, -r * 0.25), r * 0.5, col)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-r * 0.92, 0.0), c + Vector2(r * 0.92, 0.0), c + Vector2(0, r),
		]), col)
		if not lost:
			draw_circle(c + Vector2(0, -r * 0.6), r * 0.3, Color(1.0, 0.7, 0.2, a))


class _FlipBar:
	extends Control

	const BAR_W := 220.0
	const BAR_H := 40.0
	const COL_BG := Color("1a0e08")
	const COL_FILL := Color("ff6b2b")
	const COL_FILL_HOT := Color("ffc107")
	const COL_FRAME := Color("8d6e4c")
	const COL_INK := Color("0a0a0a")

	var cx := 300.0
	var cy := 280.0
	var progress := 0.0
	var holding := false

	func set_data(x: float, y: float, prog: float, is_held: bool) -> void:
		cx = x
		cy = y
		progress = clampf(prog, 0.0, 1.0)
		holding = is_held
		queue_redraw()

	func _draw() -> void:
		var x0 := cx - BAR_W * 0.5
		var y0 := cy - BAR_H * 0.5
		var r := BAR_H * 0.5

		draw_circle(Vector2(x0, cy), r, COL_BG)
		draw_circle(Vector2(x0 + BAR_W, cy), r, COL_BG)
		draw_rect(Rect2(x0, y0, BAR_W, BAR_H), COL_BG)

		# 濠靛鍋勯崢鏍嚄鐠虹儤鎶勯柨娑樼墣缁绘ɑ鎯旈敂鑲╃
		if progress > 0.01:
			var fill_w := BAR_W * progress
			var fill_col := COL_FILL_HOT if holding else COL_FILL
			draw_circle(Vector2(x0, cy), r, fill_col)
			draw_circle(Vector2(x0 + fill_w, cy), r, fill_col)
			draw_rect(Rect2(x0, y0, fill_w, BAR_H), fill_col)

		var ow := 4.0
		draw_arc(Vector2(x0, cy), r, PI * 0.5, PI * 1.5, 20, COL_INK, ow)
		draw_arc(Vector2(x0 + BAR_W, cy), r, -PI * 0.5, PI * 0.5, 20, COL_INK, ow)
		draw_line(Vector2(x0, y0), Vector2(x0 + BAR_W, y0), COL_INK, ow)
		draw_line(Vector2(x0, y0 + BAR_H), Vector2(x0 + BAR_W, y0 + BAR_H), COL_INK, ow)

		draw_arc(Vector2(x0, cy), r - 2.5, PI * 0.5, PI * 1.5, 20, COL_FRAME, 2.5)
		draw_arc(Vector2(x0 + BAR_W, cy), r - 2.5, -PI * 0.5, PI * 0.5, 20, COL_FRAME, 2.5)
		draw_line(Vector2(x0, y0 + 2.5), Vector2(x0 + BAR_W, y0 + 2.5), COL_FRAME, 2.5)
		draw_line(Vector2(x0, y0 + BAR_H - 2.5), Vector2(x0 + BAR_W, y0 + BAR_H - 2.5), COL_FRAME, 2.5)

		var font := ThemeDB.fallback_font
		var text := "按住翻面" if progress < 1.0 else "完成！"
		var col := Color("f5e6d3") if holding else Color("7a6b5d")
		draw_string(font, Vector2(cx - 50, cy + 6), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)


class _Sparks:
	extends Control

	var parts: Array = []

	func _process(delta: float) -> void:
		if parts.is_empty():
			return
		var alive: Array = []
		for p in parts:
			p["life"] -= delta
			if p["life"] <= 0.0:
				continue
			var vel: Vector2 = p["vel"]
			vel.y += 480.0 * delta
			p["vel"] = vel
			p["pos"] = Vector2(p["pos"]) + vel * delta
			alive.append(p)
		parts = alive
		queue_redraw()

	func emit(at: Vector2, col: Color, n: int) -> void:
		for i in n:
			var ang := randf_range(-PI, 0.0)
			var spd := randf_range(120.0, 340.0)
			var life := randf_range(0.3, 0.7)
			parts.append({
				"pos": at,
				"vel": Vector2(cos(ang), sin(ang)) * spd,
				"life": life,
				"max": life,
				"size": randf_range(2.0, 5.0),
				"col": col,
			})
		queue_redraw()

	func _draw() -> void:
		for p in parts:
			var a: float = clampf(p["life"] / p["max"], 0.0, 1.0)
			var c: Color = p["col"]
			draw_circle(p["pos"], p["size"] * a + 1.0, Color(c.r, c.g, c.b, a))
			draw_circle(p["pos"], p["size"] * a * 0.5, Color(1, 1, 1, a * 0.8))


class _CompletePop:
	extends Control

	const DUR := 0.95

	var tex: Texture2D
	var anchor_pos := Vector2.ZERO
	var t := -1.0   # <0 閻炴稏鍔庨妵姘跺嫉椤忓懐璐熸繛?
	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func trigger() -> void:
		t = 0.0
		queue_redraw()

	func _process(delta: float) -> void:
		if t < 0.0:
			return
		t += delta
		if t >= DUR:
			t = -1.0
		queue_redraw()

	func _draw() -> void:
		if t < 0.0 or tex == null:
			return
		var k := t / DUR
		var scl := 0.6 + 0.5 * minf(k * 4.0, 1.0)
		var alpha := 1.0
		if k > 0.55:
			alpha = 1.0 - (k - 0.55) / 0.45
		var rise := -70.0 * k
		var base := 230.0 / float(tex.get_height())
		var w := tex.get_width() * base * scl
		var h := tex.get_height() * base * scl
		var pos := anchor_pos + Vector2(-w * 0.5, -h * 0.5 + rise)
		var glow := clampf(alpha, 0.0, 1.0) * 0.5
		draw_circle(anchor_pos + Vector2(0, rise), w * 0.7,
			Color(1.0, 0.76, 0.1, glow * 0.3))
		draw_texture_rect(tex, Rect2(pos, Vector2(w, h)), false,
			Color(1, 1, 1, clampf(alpha, 0.0, 1.0)))


class _NightMarket:
	extends Control

	const COL_SKY_TOP := Color("0a0e1a")
	const COL_SKY_BOT := Color("1a1428")
	const COL_LANTERN := Color("ff8c42")
	const COL_BUILDING := Color("0d0a14")
	const COL_BUILDING2 := Color("12101c")
	const COL_AWNING := Color("5c1a1a")
	const COL_AWNING2 := Color("1a3a5c")
	const COL_GROUND := Color("1a0e08")
	const COL_STAR := Color("f5e6d3")

	var bg_tex: Texture2D
	var stars: Array = []
	var lanterns: Array = []
	var far_windows: Array = []
	var near_windows: Array = []
	var t := 0.0

	func _ready() -> void:
		for i in 40:
			stars.append({
				"x": randf_range(10, 1270),
				"y": randf_range(10, 280),
				"size": randf_range(1.0, 2.5),
				"phase": randf() * TAU,
				"speed": randf_range(1.5, 4.0),
			})
		for i in 7:
			lanterns.append({
				"x": randf_range(60, 1220),
				"y": randf_range(180, 320),
				"size": randf_range(10, 18),
				"phase": randf() * TAU,
				"color": COL_LANTERN if randf() > 0.4 else Color("e84545"),
			})
		_gen_far_windows()
		_gen_near_windows()

	func _gen_far_windows() -> void:
		var far_y := 340.0
		var far_buildings := [80, 140, 60, 200, 100, 160, 70, 120, 180, 90, 150, 110, 130]
		var x := 0.0
		for bw in far_buildings:
			var bh := float(bw) * 1.2 + 40.0
			for wy in range(int(far_y - bh + 10), int(far_y - 10), 18):
				for wx in range(int(x + 6), int(x + bw - 4), 14):
					if randf() > 0.55:
						far_windows.append({
							"rect": Rect2(float(wx), float(wy), 6, 8),
							"alpha": randf_range(0.05, 0.2),
						})
			x += float(bw) + 2

	func _gen_near_windows() -> void:
		var near_y := 380.0
		var near_buildings := [120, 80, 160, 60, 140, 100, 180, 70, 130, 90]
		var x := -20.0
		for bw in near_buildings:
			var bh := float(bw) * 0.8 + 60.0
			for wy in range(int(near_y - bh + 14), int(near_y - 10), 22):
				for wx in range(int(x + 10), int(x + bw - 2), 18):
					if randf() > 0.6:
						near_windows.append({
							"rect": Rect2(float(wx), float(wy), 8, 10),
							"alpha": randf_range(0.08, 0.3),
						})
			x += float(bw) + 4

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var w := 1280.0
		var h := 720.0
		if bg_tex:
			draw_texture_rect(bg_tex, Rect2(Vector2.ZERO, Vector2(w, h)), false)
			return

		for i in 12:
			var frac := float(i) / 12.0
			var col := COL_SKY_TOP.lerp(COL_SKY_BOT, frac)
			draw_rect(Rect2(0, i * h / 12.0, w, h / 12.0 + 1), col)

		for s in stars:
			var a := 0.3 + 0.5 * (0.5 + 0.5 * sin(t * s["speed"] + s["phase"]))
			draw_circle(Vector2(s["x"], s["y"]), s["size"],
				Color(COL_STAR.r, COL_STAR.g, COL_STAR.b, a))

		_draw_buildings()

		for la in lanterns:
			var lx: float = la["x"] + sin(t * 0.8 + la["phase"]) * 3.0
			var ly: float = la["y"] + sin(t * 1.2 + la["phase"] * 1.3) * 2.0
			var ls: float = la["size"]
			var lc: Color = la["color"]
			draw_circle(Vector2(lx, ly), ls * 3.0,
				Color(lc.r, lc.g, lc.b, 0.08 + 0.04 * sin(t * 2.0 + la["phase"])))
			draw_circle(Vector2(lx, ly), ls, lc)
			draw_circle(Vector2(lx, ly - ls * 0.2), ls * 0.7,
				Color(lc.r + 0.1, lc.g + 0.1, lc.b + 0.05, 0.7))
			draw_line(Vector2(lx, ly - ls), Vector2(lx, ly - ls - 12),
				Color("8d6e4c"), 1.5)

		_draw_awnings()

		draw_rect(Rect2(0, h - 160, w, 160), COL_GROUND)
		for i in 8:
			var y := h - 160.0 + i * 20.0
			draw_line(Vector2(0, y), Vector2(w, y),
				Color(0.12, 0.07, 0.04, 0.3), 1.0)

		for i in 6:
			var a := 0.06 * (1.0 - float(i) / 6.0)
			draw_rect(Rect2(0, h - 100 - i * 30, w, 30),
				Color(1.0, 0.42, 0.17, a))

	func _draw_buildings() -> void:
		var far_y := 340.0
		var far_buildings := [80, 140, 60, 200, 100, 160, 70, 120, 180, 90, 150, 110, 130]
		var x := 0.0
		for bw in far_buildings:
			var bh := float(bw) * 1.2 + 40.0
			draw_rect(Rect2(x, far_y - bh, float(bw) + 4, bh + 20), COL_BUILDING2)
			x += float(bw) + 2
		for win in far_windows:
			draw_rect(win["rect"], Color(1.0, 0.85, 0.4, win["alpha"]))

		var near_y := 380.0
		var near_buildings := [120, 80, 160, 60, 140, 100, 180, 70, 130, 90]
		x = -20.0
		for bw in near_buildings:
			var bh := float(bw) * 0.8 + 60.0
			draw_rect(Rect2(x, near_y - bh, float(bw) + 8, bh + 30), COL_BUILDING)
			x += float(bw) + 4
		for win in near_windows:
			draw_rect(win["rect"], Color(1.0, 0.85, 0.4, win["alpha"]))

	func _draw_awnings() -> void:
		var ay := 400.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(0, ay), Vector2(320, ay), Vector2(280, ay + 50), Vector2(0, ay + 50),
		]), COL_AWNING)
		for i in range(0, 320, 40):
			var frac := float(i) / 320.0
			var top_x := float(i)
			var bot_x := lerpf(float(i), 280.0, frac)
			draw_line(Vector2(top_x, ay), Vector2(bot_x, ay + 50),
				Color("8b2020") if (i / 40) % 2 == 0 else Color("6b1818"), 3.0)

		draw_colored_polygon(PackedVector2Array([
			Vector2(960, ay), Vector2(1280, ay), Vector2(1280, ay + 50), Vector2(1000, ay + 50),
		]), COL_AWNING2)
		for i in range(960, 1280, 40):
			var frac := float(i - 960) / 320.0
			var top_x := float(i)
			var bot_x := lerpf(1000.0, 1280.0, frac)
			draw_line(Vector2(top_x, ay), Vector2(bot_x, ay + 50),
				Color("1a4a6c") if ((i - 960) / 40) % 2 == 0 else Color("143a5c"), 3.0)
