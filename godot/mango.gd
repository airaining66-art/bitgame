extends Control
## 1-2 芒果奇缘 — bathroom reaction level.
## Two icons (mango / water-drop) slide to center each beat; if they match,
## bite (press) on the beat; if they differ, hold off. Biting zooms the mango
## and wall in and the shower droplets vanish — like stepping out to take a
## bite. Hold "savor" notes and the lo-fi BGM come next.

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

# --- tunables (shared with 1-1) ---------------------------------------------
const SLIDE_RATIO := 0.5
const MIN_PERFECT_MS := 140.0
const MIN_GOOD_MS := 260.0
const COUNTDOWN_BEATS := ["3", "2", "1", "START"]
const STAGE_CENTER := Vector2(640, 360)

const TILE_W := 150.0   # icon display size — tweak here if mango reads too big/small
const TILE_H := 150.0
const MANGO := 0
const WATER := 1

const SPACING := 330.0       # pixels per beat of continuous scroll
const JUDGE_OFFSET := 0.75   # a note crosses center at this phase of its cycle
const NOTE_SLOTS := 7        # IconTiles per lane (scroll window)

## Fixed, FINITE chart (composed, not random). Plays once and ends with a
## flourish — after the last note nothing new spawns. Tokens: m=mango press,
## w=water press, -=no-press beat, H=3-beat mango "savor" hold, E=end marker.
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

# --- state ------------------------------------------------------------------
var app
var level: Dictionary
var conductor: Conductor
var lofi: Music

var phase := "idle"
var countdown_start := 0.0
var countdown_step := -1
var health := 3
var score := 0
var combo := 0
var fever_gauge := 0.0   # 0..1; full -> Fever (x2 score + visuals)
var fever_active := false
var fever_time := 0.0
var notes_hit := 0       # for the end-screen accuracy + rank
var notes_missed := 0
var current_beat := 0
var last_judged_beat := -1
var current_beat_data: Dictionary = {}
var prev_beat_data: Dictionary = {}
var queue: Array[Dictionary] = []
var hit_pop := 0.0
var current_hit := false   # current note was hit -> hide it, the fx plays instead
var skip_run := 0
var press_run := 0
var run_kind := 0       # current icon streak (mango/water)
var run_remaining := 0
# Hold "savor" notes: a run of mango beats merged into one held capsule.
var chart_i := 0
var chart_total_beats := 0
var hold_emit_left := 0
var hold_emit_len := 0
var hold_active := false
var hold_filled := 0.0
var hold_head_pop := 0.0   # head/tail mango pop on each savor tick
var key_held := false
var btn_held := false

# --- juice ------------------------------------------------------------------
const ZOOM_OUT := 0.10  # how far the camera zooms when "out of the shower"
var zoom_state := 0.0   # target zoom: set on a mango bite, held until you catch water
var zoom_cur := 0.0     # smoothed toward zoom_state
var bump := 0.0         # tiny per-press bounce
var wetness := 0.45     # shower droplet intensity (water hits raise it, mango clears it)
var hold_dim := 0.0     # darken + vignette during a hold
var shake := 0.0        # miss shake
var bar_flash := 0.0    # center breathing-light hit flash
var bar_color := Color.WHITE
var t := 0.0
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
var score_label: Label
var bpm_label: Label
var hearts: Array = []
var feedback_label: Label
var countdown_label: Label
var hit_button: Button
var fever_overlay: ColorRect
var fever_label: Label
var fever_bar_bg: Panel
var fever_bar_fill: ColorRect
var result_layer: ColorRect
var result_title: Label
var result_grade: Label
var result_eval: Label
var result_score: Label

# --- sfx --------------------------------------------------------------------
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_i := 0
var snd_bite: AudioStreamWAV
var snd_miss: AudioStreamWAV
var snd_anchor: AudioStreamWAV


func now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0


func make_cfg() -> Dictionary:
	return {
		"duration_ms": 45000.0, "start_bpm": 70.0, "end_bpm": 110.0,
		"bpm_curve_exp": 1.6, "subdivisions": 4,
		"press_ratio": 0.6, "max_skip_run": 2, "max_press_run": 3,
	}


# ===========================================================================
func _ready() -> void:
	app = get_node_or_null("/root/App")
	if app:
		theme = app.ui_theme
		level = app.active_cfg()
		if level.is_empty():
			level = make_cfg()
	else:
		level = make_cfg()

	conductor = Conductor.new()
	conductor.setup(level)
	add_child(conductor)
	conductor.beat.connect(_on_cycle_advance)
	conductor.level_finished.connect(_on_level_finished)
	conductor.downbeat.connect(_on_downbeat)

	lofi = Music.new()
	add_child(lofi)
	lofi.setup(conductor)

	_build_sfx()
	_build_world()
	_build_hud()
	_build_button()
	_build_fever()
	_build_result()
	start_game()


func _build_fever() -> void:
	# Full-screen warm tint that pulses during Fever.
	fever_overlay = ColorRect.new()
	fever_overlay.color = Color(1.0, 0.62, 0.12, 0.0)
	fever_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fever_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fever_overlay)

	# Fever gauge bar (top-center).
	fever_bar_bg = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.35)
	sb.set_corner_radius_all(7)
	fever_bar_bg.add_theme_stylebox_override("panel", sb)
	fever_bar_bg.position = Vector2(490, 56)
	fever_bar_bg.size = Vector2(300, 14)
	fever_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fever_bar_bg)
	fever_bar_fill = ColorRect.new()
	fever_bar_fill.color = Color("ffcf52")
	fever_bar_fill.position = Vector2(2, 2)
	fever_bar_fill.size = Vector2(0, 10)
	fever_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fever_bar_bg.add_child(fever_bar_fill)

	# "FEVER!" banner.
	fever_label = Label.new()
	fever_label.text = "FEVER!!"
	fever_label.add_theme_font_size_override("font_size", 72)
	fever_label.add_theme_color_override("font_color", Color("ff7a1a"))
	fever_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fever_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	fever_label.offset_top = 92
	fever_label.pivot_offset = Vector2(640, 130)
	fever_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fever_label.visible = false
	add_child(fever_label)


# ===========================================================================
# Build
# ===========================================================================
func _build_world() -> void:
	world = _World.new()                               # wall + droplets + center glow; scales on bite
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.pivot_offset = STAGE_CENTER
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)

	hold_vignette = _Vignette.new()                    # darken + vignette during a hold
	hold_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hold_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(hold_vignette)

	track = Control.new()                              # gameplay layer; sways with the beat (head-bob)
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.pivot_offset = STAGE_CENTER
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(track)

	# Hand+mango art is drawn by _World at the very bottom, behind all gameplay.
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

	# Hit disappear animations (water burst sheet / mango scale-fade), on top.
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


func _build_hud() -> void:
	var score_group := _stat("爽度", "0")
	score_group.position = Vector2(20, 12)
	add_child(score_group)
	score_label = score_group.get_meta("value")

	var bpm_group := _stat("BPM", str(int(level["start_bpm"])))
	bpm_group.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bpm_group.position = Vector2(-40, 12)
	add_child(bpm_group)
	bpm_label = bpm_group.get_meta("value")

	var hearts_box := HBoxContainer.new()
	hearts_box.add_theme_constant_override("separation", 12)
	hearts_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hearts_box.position = Vector2(-130, 16)
	add_child(hearts_box)
	for i in 3:
		var d := _Droplet.new()
		d.custom_minimum_size = Vector2(30, 38)
		hearts_box.add_child(d)
		hearts.append(d)

	feedback_label = Label.new()
	feedback_label.add_theme_font_size_override("font_size", 40)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	feedback_label.offset_top = -190
	feedback_label.offset_bottom = -140
	feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(feedback_label)

	countdown_label = Label.new()
	countdown_label.text = "3"
	countdown_label.add_theme_font_size_override("font_size", 170)
	countdown_label.add_theme_color_override("font_color", COL_TEXT)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(countdown_label)


func _stat(caption: String, value: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", COL_MUTED)
	box.add_child(cap)
	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 30)
	val.add_theme_color_override("font_color", COL_TEXT)
	box.add_child(val)
	box.set_meta("value", val)
	return box


func _build_button() -> void:
	# Beat ring behind the button: large+dim between beats, small+bright on the
	# beat — a visual metronome telling you when to press.
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


func _build_result() -> void:
	result_layer = ColorRect.new()
	result_layer.color = Color(0, 0, 0, 0.55)
	result_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_layer.visible = false
	add_child(result_layer)

	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("fffdf6")
	sb.set_border_width_all(2)
	sb.border_color = COL_MANGO
	sb.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(480, 430)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.position = Vector2(-240, -215)
	result_layer.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 30
	vb.offset_top = 30
	vb.offset_right = -30
	vb.offset_bottom = -30
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vb)

	# Big letter grade (S/A/B/C/D from accuracy).
	result_grade = Label.new()
	result_grade.add_theme_font_size_override("font_size", 72)
	result_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(result_grade)

	result_title = Label.new()
	result_title.add_theme_font_size_override("font_size", 32)
	result_title.add_theme_color_override("font_color", COL_MANGO_DK)
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(result_title)

	var eval_box := PanelContainer.new()
	var eb := StyleBoxFlat.new()
	eb.bg_color = Color("fff7df")
	eb.set_border_width_all(2)
	eb.border_color = Color("ecd9a0")
	eb.set_corner_radius_all(8)
	eb.content_margin_left = 16
	eb.content_margin_right = 16
	eb.content_margin_top = 14
	eb.content_margin_bottom = 14
	eval_box.add_theme_stylebox_override("panel", eb)
	vb.add_child(eval_box)
	result_eval = Label.new()
	result_eval.add_theme_font_size_override("font_size", 20)
	result_eval.add_theme_color_override("font_color", COL_TEXT)
	result_eval.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_eval.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_eval.custom_minimum_size = Vector2(400, 0)
	eval_box.add_child(result_eval)

	result_score = Label.new()
	result_score.add_theme_font_size_override("font_size", 20)
	result_score.add_theme_color_override("font_color", COL_MUTED)
	result_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(result_score)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(buttons)
	var again := Button.new()
	again.text = "再来一局"
	again.custom_minimum_size = Vector2(180, 50)
	again.add_theme_font_size_override("font_size", 19)
	again.pressed.connect(start_game)
	var back := Button.new()
	back.text = "返回关卡"
	back.custom_minimum_size = Vector2(180, 50)
	back.add_theme_font_size_override("font_size", 19)
	back.pressed.connect(func() -> void:
		if app:
			app.goto_levels())
	if app:
		app.style_button(again, "default")
		app.style_button(back, "default")
	buttons.add_child(again)
	buttons.add_child(back)


# ===========================================================================
# Input
# ===========================================================================
func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()
			if event.pressed:
				key_held = true
				_press_down()
			else:
				key_held = false
				_press_up()
		elif event.pressed and event.keycode == KEY_R:
			start_game()
		elif event.pressed and event.keycode == KEY_ESCAPE and app:
			app.goto_levels()


# ===========================================================================
# Beat generation (mango / water, run-capped density like 1-1)
# ===========================================================================
func make_beat() -> Dictionary:
	# Continue emitting an in-progress hold group.
	if hold_emit_left > 0:
		var pos := hold_emit_len - hold_emit_left
		hold_emit_left -= 1
		return _hold_beat(pos, hold_emit_len)

	# Chart is finite: once it's done, emit invisible "end" rests (no new notes).
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
		_:  # "-" : a no-press beat (top/bottom differ).
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
func perfect_window() -> float:
	return maxf(MIN_PERFECT_MS, conductor.cycle_duration * 0.14)


func good_window() -> float:
	return maxf(MIN_GOOD_MS, conductor.cycle_duration * 0.28)


func is_holding() -> bool:
	return key_held or btn_held


## Press-down: tap-judge a normal note. Holds are judged by holding STATE (not a
## tap): the head can be started early by a press near it; otherwise the beat
## boundary starts it (which also catches "already holding from before").
func _press_down() -> void:
	if phase != "running":
		return
	bump = maxf(bump, 0.022)
	shake = maxf(shake, 2.5)
	var cur := current_beat_data
	if cur.get("hold", false):
		# Early-press tolerance: pressing anytime during the head beat starts it.
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


## Late-release tolerance: a hold only breaks if you release BEFORE the tail
## mango reaches center (last beat at/after phase 0.75). Releasing after is fine.
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


## Resolve the beat that just ended (called on the cycle boundary).
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
					_start_hold()          # held through without a fresh press
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
			hold_active = false            # hold complete
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
	# The struck note disappears (with its animation); the tile is hidden.
	current_hit = true
	_spawn_fx(k, Vector2(640.0, 220.0))
	_spawn_fx(k, Vector2(640.0, 500.0))
	# Switch-mode background: biting a mango steps you OUT of the shower (zoom in
	# + clear droplets, and it STAYS zoomed); catching water steps back under it.
	if k == MANGO:
		_step_out()
	else:
		_step_in()


## Screen feedback for a hit: note pop + center breathing-light flash.
func _hit_feedback(kind: int) -> void:
	hit_pop = 1.0
	bar_color = COL_MANGO if kind == MANGO else COL_WATER
	bar_flash = 1.0


func _spawn_fx(kind: int, pos: Vector2) -> void:
	var fx: _HitFx = hit_fx[hit_fx_i]
	hit_fx_i = (hit_fx_i + 1) % hit_fx.size()
	fx.play(kind, pos)


func _add_score(points: int) -> void:
	score += points * (2 if fever_active else 1)   # Fever doubles
	combo += 1
	update_hud()


## A clean hit: count it (for accuracy) and charge the Fever gauge.
func _fever_hit() -> void:
	notes_hit += 1
	if not fever_active:
		fever_gauge = minf(1.0, fever_gauge + 0.06)
		if fever_gauge >= 1.0:
			_enter_fever()


func _enter_fever() -> void:
	fever_active = true
	fever_time = 6.0
	fever_label.visible = true
	set_feedback("FEVER!", Color("ff7a1a"))


func _end_fever() -> void:
	fever_active = false
	fever_gauge = 0.0
	fever_label.visible = false


## Mango bite — step out of the shower: zoom in (and STAY) + clear the droplets.
func _step_out() -> void:
	zoom_state = ZOOM_OUT
	wetness = 0.0
	world.wetness = 0.0


## Water — step back under the showerhead: zoom back to normal + more droplets.
func _step_in() -> void:
	zoom_state = 0.0
	wetness = minf(1.0, wetness + 0.22)
	world.wetness = wetness


func apply_penalty(text: String) -> void:
	health -= 1
	combo = 0
	notes_missed += 1
	if fever_active:
		_end_fever()   # a miss kills Fever
	play_sfx(snd_miss)
	shake = maxf(shake, 9.0)
	bar_color = COL_RED
	bar_flash = 1.0
	update_hud()
	set_feedback(text, COL_WATER_DK)
	if health <= 0:
		end_game(false)


func _on_downbeat(_cycle_index: int) -> void:
	# A soft kick on every "should-press" beat — the rhythm peg you press to.
	if phase == "running" and current_beat_data.get("should_press", false):
		play_sfx(snd_anchor, -9.0)


func flash_button() -> void:
	btn_pop = 1.0  # quick press-pop (driven in _process)


# ===========================================================================
# HUD
# ===========================================================================
func set_feedback(text: String, col: Color) -> void:
	feedback_label.text = text
	feedback_label.add_theme_color_override("font_color", col)


func update_hud() -> void:
	score_label.text = str(score)
	for i in hearts.size():
		hearts[i].set_lost(i >= health)


# ===========================================================================
# Tiles
# ===========================================================================
## Continuous horizontal scroll (Taiko-style) for single notes. Hold notes:
## the HEAD scrolls in then STOPS at center; the TAIL keeps scrolling in and the
## bar SHRINKS until the tail meets the head.
func layout_notes() -> void:
	var bp := conductor.beat_phase()   # 0..1 within the current cycle

	# Hold bars: the current hold (head offset = -hold_pos) + any upcoming ones.
	var segs := []
	if current_beat_data.get("hold", false):
		_add_hold_seg(segs, -int(current_beat_data.get("hold_pos", 0)), int(current_beat_data.get("hold_len", 3)), bp)
	for qi in queue.size():
		var note: Dictionary = queue[qi]
		if note.get("hold", false) and int(note.get("hold_pos", 0)) == 0:
			_add_hold_seg(segs, qi + 1, int(note.get("hold_len", 3)), bp)
	hold_frame.set_segments(segs, hold_active, conductor.pulse(), hold_head_pop)
	hold_frame.visible = not segs.is_empty()

	# Non-hold notes: one IconTile per slot. A note vanishes once it's past the
	# judge zone (bu < -0.35) or once it's been hit (the fx plays instead).
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


## Add a hold-bar segment: head (offset k_head beats from current) approaches
## center and STOPS there; the tail (l-1 beats later) keeps scrolling in.
func _add_hold_seg(segs: Array, k_head: int, l: int, bp: float) -> void:
	var buh := float(k_head) + JUDGE_OFFSET - bp           # head beats until center
	var but_ := float(k_head + l - 1) + JUDGE_OFFSET - bp   # tail beats until center
	if but_ < -0.15:
		return   # tail reached center -> hold finished, hide the bar
	segs.append({
		"th": 640.0 - maxf(0.0, buh) * SPACING,            # head clamps at center
		"tt": minf(640.0, 640.0 - but_ * SPACING),         # tail scrolls in
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
# Main loop
# ===========================================================================
func _process(delta: float) -> void:
	t += delta
	if phase == "countdown":
		update_countdown(now_ms())
	elif phase == "running":
		layout_notes()
		bpm_label.text = str(roundi(conductor.bpm()))

	var p := conductor.pulse() if conductor.running else 0.0
	# Zoom is a STATE (held until you catch water), plus a tiny per-press bounce.
	zoom_cur = move_toward(zoom_cur, zoom_state, delta * 0.7)
	bump = move_toward(bump, 0.0, delta * 0.5)
	world.scale = Vector2.ONE * (1.0 + p * 0.01 + zoom_cur + bump)
	# Head-bob: the track rocks gently once per beat.
	track.rotation = sin(conductor.musical_phase() * TAU) * 0.02 if conductor.running else 0.0
	# Miss shake + center judge-zone breathing light.
	shake = move_toward(shake, 0.0, delta * 55.0)
	bar_flash = move_toward(bar_flash, 0.0, delta * 2.2)
	world.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
	# Green judge rings: pulse with the beat, tint toward the hit colour on a hit.
	world.center_color = COL_JUDGE.lerp(bar_color, clampf(bar_flash, 0.0, 1.0))
	world.center_pulse = p
	# Darken + vignette: a hold spotlights hard; normal play gets a subtle
	# beat-synced dim (darker between beats) that pops the breathing lights.
	var dim_target := 1.0 if (phase == "running" and current_beat_data.get("hold", false)) else 0.0
	hold_dim = move_toward(hold_dim, dim_target, delta * 3.0)
	var beat_dim := (1.0 - p) * 0.13 if conductor.running else 0.0
	hold_vignette.set_intensity(maxf(hold_dim, beat_dim))
	# Button beat-ring metronome (same pulse as the judge rings).
	beat_ring.set_pulse(p)
	# Button: continuous flicker (scale + colour) while holding a savor note;
	# otherwise a quick press-pop.
	if hold_active and is_holding():
		var fl := 0.5 + 0.5 * sin(t * 22.0)
		hit_button.scale = Vector2.ONE * (1.0 + 0.07 * fl)
		hit_button.modulate = Color.WHITE.lerp(Color("ffcf52"), 0.45 + 0.45 * fl)
	else:
		btn_pop = move_toward(btn_pop, 0.0, delta * 5.0)
		hit_button.scale = Vector2.ONE * (1.0 + 0.15 * btn_pop)          # punch UP on press
		hit_button.modulate = Color.WHITE.lerp(Color("ffc83a"), btn_pop)  # + gold flash
	hit_pop = move_toward(hit_pop, 0.0, delta * 6.0)
	hold_head_pop = move_toward(hold_head_pop, 0.0, delta * 4.0)

	# Fever: timed; the screen tints + pulses and the banner throbs.
	if fever_active:
		fever_time -= delta
		if fever_time <= 0.0:
			_end_fever()
	fever_overlay.color.a = (0.10 + 0.12 * p) if fever_active else 0.0
	fever_bar_fill.size.x = clampf(fever_gauge, 0.0, 1.0) * 296.0
	fever_bar_fill.color = Color("ff7a1a") if fever_active else Color("ffcf52")
	if fever_active:
		fever_label.scale = Vector2.ONE * (1.0 + 0.18 * p)


func _on_cycle_advance(_cycle_index: int) -> void:
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
	# Wind the music down over the final beats, then end on the chart's end-marker.
	if current_beat >= chart_total_beats - 8:
		lofi.finale = true
	if current_beat_data.get("end", false):
		_start_outro()


func update_countdown(now: float) -> void:
	var step_ms := 60000.0 / float(level["start_bpm"])
	var elapsed := now - countdown_start
	var step := mini(int(elapsed / step_ms), COUNTDOWN_BEATS.size() - 1)
	if step != countdown_step:
		countdown_step = step
		countdown_label.text = COUNTDOWN_BEATS[step]
		countdown_label.pivot_offset = countdown_label.size * 0.5
		countdown_label.scale = Vector2(0.72, 0.72)
		play_sfx(snd_bite if step == COUNTDOWN_BEATS.size() - 1 else snd_miss, -8.0)
		var tw := create_tween()
		tw.tween_property(countdown_label, "scale", Vector2.ONE, 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if elapsed >= step_ms * COUNTDOWN_BEATS.size():
		begin_run()


# ===========================================================================
# Phases
# ===========================================================================
func start_game() -> void:
	health = 3
	score = 0
	combo = 0
	fever_gauge = 0.0
	fever_active = false
	fever_label.visible = false
	notes_hit = 0
	notes_missed = 0
	current_beat = 0
	last_judged_beat = -1
	conductor.stop()
	if lofi:
		lofi.reset()
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
	result_layer.visible = false
	bpm_label.text = str(int(level["start_bpm"]))
	update_hud()
	_enter_countdown()


func _enter_countdown() -> void:
	phase = "countdown"
	countdown_start = now_ms()
	countdown_step = -1
	countdown_label.visible = true
	hold_frame.visible = false
	set_tiles_visible(false)
	set_feedback("准备", COL_MUTED)


func begin_run() -> void:
	phase = "running"
	current_beat = 0
	last_judged_beat = -1
	countdown_label.visible = false
	set_tiles_visible(true)
	set_feedback("开吃!", COL_MANGO_DK)
	conductor.start()


func _on_level_finished() -> void:
	if phase == "running":
		_start_outro()


## Ending flourish — stop judging, ring out a closing chord, hold a final bite
## (so the music + game don't just cut off mid-phrase), then show the result.
func _start_outro() -> void:
	if phase != "running":
		return
	phase = "outro"
	conductor.stop()
	_end_fever()
	lofi.play_outro()
	set_feedback("吃完啦~", COL_MANGO_DK)
	wetness = 0.0
	world.wetness = 0.0
	zoom_state = ZOOM_OUT * 1.7
	bar_color = COL_MANGO
	bar_flash = 1.0
	hit_pop = 1.0
	_spawn_fx(MANGO, Vector2(640.0, 220.0))
	_spawn_fx(MANGO, Vector2(640.0, 500.0))
	get_tree().create_timer(2.2).timeout.connect(func() -> void:
		if is_instance_valid(self):
			end_game(true))


func end_game(won: bool) -> void:
	phase = "won" if won else "lost"
	conductor.stop()
	if won and app:
		app.record_result(app.current_index, 3 - health)   # 0 lost -> unlock Extreme
	var rank := ""
	var verdict := ""
	if won:
		match 3 - health:
			0:
				rank = "PERFECT"
				verdict = "淋浴配芒果，人生巅峰享受"
			1:
				rank = "GREAT"
				verdict = "差一口就上天了，明天还能上班"
			_:
				rank = "CLEAR"
				verdict = "至少芒果没掉地上"
		result_title.add_theme_color_override("font_color", COL_MANGO_DK)
	else:
		rank = "GAME OVER"
		verdict = "芒果都凉了，重新来过吧"
		result_title.add_theme_color_override("font_color", COL_WATER_DK)
	result_title.text = rank
	result_eval.text = verdict
	# Letter grade from accuracy + personal best.
	var acc := float(notes_hit) / maxf(float(notes_hit + notes_missed), 1.0)
	var grade := "D"
	var gcol := COL_WATER_DK
	if acc >= 0.97: grade = "S"; gcol = Color("ff7a1a")
	elif acc >= 0.88: grade = "A"; gcol = COL_MANGO_DK
	elif acc >= 0.75: grade = "B"; gcol = COL_GREEN
	elif acc >= 0.55: grade = "C"; gcol = COL_TEXT
	result_grade.text = grade
	result_grade.add_theme_color_override("font_color", gcol)
	var new_best := false
	var best := score
	if app:
		new_best = app.record_score(app.current_index, score)
		best = app.get_best(app.current_index)
	var best_tag := "  ★新纪录!" if new_best else ""
	result_score.text = "爽度 %d　命中 %d%%　最高 %d%s" % [score, roundi(acc * 100.0), best, best_tag]
	result_layer.visible = true


# ===========================================================================
# SFX
# ===========================================================================
func _build_sfx() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		sfx_players.append(p)
	# Warm, soft "plop" (sine, pitch dropping) rather than a rising electronic beep.
	snd_bite = _gen_tone(430.0, 300.0, 0.11, "sine", 0.42)
	snd_miss = _gen_tone(230.0, 130.0, 0.16, "sine", 0.4)
	# Soft kick anchor placed on every should-press beat (the rhythm peg).
	snd_anchor = _gen_tone(130.0, 60.0, 0.13, "sine", 0.7)


func play_sfx(stream: AudioStreamWAV, volume_db := -3.0) -> void:
	if stream == null:
		return
	var p := sfx_players[sfx_i]
	sfx_i = (sfx_i + 1) % sfx_players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.play()


func _gen_tone(freq: float, slide_to: float, dur: float, wave: String, gain: float) -> AudioStreamWAV:
	var rate := 44100
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var attack := 0.012
	var phase := 0.0
	for i in n:
		var ti := float(i) / rate
		var f := freq
		if slide_to > 0.0:
			f = freq * pow(slide_to / freq, ti / dur)
		phase += TAU * f / rate
		var s := 0.0
		match wave:
			"sine": s = sin(phase)
			"triangle": s = asin(sin(phase)) * (2.0 / PI)
		var env := 0.0
		if ti < attack:
			env = ti / attack
		else:
			env = pow(0.0001, (ti - attack) / maxf(dur - attack, 0.0001))
		data.encode_s16(i * 2, int(clampf(s * gain * env, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	return st


func _load_tex(paths: Array) -> Texture2D:
	for p in paths:
		# Prefer the imported resource (works on export, no error spam).
		if ResourceLoader.exists(p):
			var res := load(p)
			if res is Texture2D:
				return res
		# Fallback: a loose PNG that hasn't been imported yet.
		if FileAccess.file_exists(p):
			var img := Image.new()
			if img.load(p) == OK:
				return ImageTexture.create_from_image(img)
	return null


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
	var wetness := 0.45     # target intensity, set by the game
	var _shown := 0.45      # smoothed toward wetness
	var center_pulse := 0.0 # center judge-zone breathing light
	var center_color := Color.WHITE
	var hand_tex: Texture2D # hand+mango art, drawn at the BOTTOM (behind gameplay)
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
		# Hand + mango art — bottom layer (above the wall, behind all gameplay UI).
		if hand_tex:
			var hs := hand_tex.get_size()
			var sc := minf(460.0 / hs.x, 500.0 / hs.y)
			var dst := hs * sc
			var hc := Vector2(640.0, 380.0 + sin(t * 1.6) * 8.0)
			draw_texture_rect(hand_tex, Rect2(hc - dst * 0.5, dst), false)
		# Center judge rings — one per lane, where the icons meet. They breathe
		# with the beat (big+dim between, small+bright on the beat) so they read
		# as "press now", and tint toward center_color on a hit. (Replaces the
		# level-1 center breathing bar.)
		_judge_ring(Vector2(640, 220))
		_judge_ring(Vector2(640, 500))
		# Running droplets: count + alpha scale with wetness, each fading in/out
		# smoothly as the level "gets wetter" or is cleared by a mango bite.
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

	## Soft self-lit glow halo that breathes with the beat and flickers; tints on
	## a hit. Built from concentric circles for a blurred edge.
	func _judge_ring(c: Vector2) -> void:
		var pr := clampf(center_pulse, 0.0, 1.0)
		var flick := 0.8 + 0.2 * sin(t * 17.0)
		var base_r := lerpf(94.0, 74.0, pr)        # breathe with the beat
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
		# Both icons are 5-frame 150px sheets; the static tile is frame 0.
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


## Hit disappear animation: a pressed water-drop plays the 5-frame burst sheet
## then fades; a pressed mango scales up and fades out.
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
		# Pressed mango (eaten sheet) / water (burst sheet): play 5 frames + grow.
		var tex: Texture2D = mango_tex if kind == 0 else drop_tex
		if tex == null:
			return
		var f := clampf(life / DUR, 0.0, 1.0)
		var frame := clampi(int(f * 5.0), 0, 4)
		var a := 1.0 if f < 0.6 else (1.0 - (f - 0.6) / 0.4)
		var dst := Vector2(SIZE, SIZE) * (1.0 + f * 0.3)
		draw_texture_rect_region(tex, Rect2(fx_pos - dst * 0.5, dst),
			Rect2(frame * 150, 0, 150, 150), Color(1, 1, 1, a))


## Hold "savor" note: a rigid rounded capsule with a mango at EACH end, drawn
## per visible hold group. It scrolls as one unit (the head/tail x come from the
## continuous scroll), and breathes (vertical scale + brightness) with the beat.
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
	var segments: Array = []   # [{th,tt,bh,bt}, ...]  head/tail x per lane
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
		var fillc := (COL_FILL if hot else COL_DIM).lerp(Color.WHITE, pr * 0.55)  # flash with the beat
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
		# Mangoes at each end: head (fixed at center) pops on each savor + breathes;
		# tail breathes with the beat. (So the icons on the bar are alive.)
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


## Placeholder hand+mango, shown until the PNG asset is present.
class _PlaceholderMango:
	extends Control

	const MANGO := Color("f3c200")
	const MANGO_G := Color("6fa83b")
	const SKIN := Color("e8c79c")
	const INK := Color("2a2a2a")

	func _draw() -> void:
		var c := size * 0.5
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-150, 40), c + Vector2(-110, 150), c + Vector2(70, 150),
			c + Vector2(120, 70), c + Vector2(60, -10), c + Vector2(-90, -10),
		]), SKIN)
		_blob(c + Vector2(10, -30), 150, 96, MANGO)
		_blob(c + Vector2(-70, 0), 70, 70, MANGO_G)
		draw_arc(c + Vector2(10, -30), 150, -1.4, 1.4, 28, INK, 3.0)

	func _blob(center: Vector2, rx: float, ry: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 32:
			var a := TAU * i / 32.0
			pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(pts, col)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, INK, 2.5)


## Dim + vignette overlay (drawn over the wall, behind the gameplay) used to
## spotlight a hold note.
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
		# Edge bands build up darker corners (a soft vignette).
		var bands := 14
		var depth := 190.0
		for i in bands:
			var a := intensity * 0.30 * (1.0 - float(i) / bands)
			var col := Color(0, 0, 0, a)
			var d := depth * (1.0 - float(i) / bands)
			draw_rect(Rect2(0, 0, w, d), col)                 # top
			draw_rect(Rect2(0, h - d, w, d), col)             # bottom
			draw_rect(Rect2(0, 0, d, h), col)                 # left
			draw_rect(Rect2(w - d, 0, d, h), col)             # right


## Breathing beat ring behind the PRESS button: large + dim between beats,
## small + bright on the beat (a visual metronome).
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
		var rad := lerpf(128.0, 74.0, pr)        # big between beats, small on the beat
		var a := lerpf(0.10, 0.5, pr)            # dim between beats, bright on the beat
		draw_circle(CENTER, rad, Color(COL.r, COL.g, COL.b, a * 0.5))
		draw_arc(CENTER, rad, 0, TAU, 48, Color(COL.r, COL.g, COL.b, a), 5.0)
