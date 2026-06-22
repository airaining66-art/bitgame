extends LevelBase
## Bit Reaction Rhythm — Level 1.
## Two bits slide to center each beat; press if they match, hold off if they
## differ. Timing -> Perfect / Good / Bad. Everything pulses to the Conductor.

# --- palette (from the web prototype) ---------------------------------------
const COL_BG := Color("f5f5f2")
const COL_INK := Color("21170d")
const COL_GRID := Color("c9c9c4")
const COL_MUTED := Color("77746d")
const COL_ACCENT := Color("d71920")
const COL_GOLD := Color("f6b800")
const COL_GREEN := Color("2a8d49")
const COL_PLAYFIELD := Color("eeeeeb")
const COL_TILE_TEXT := Color("5d5851")
const COL_TILE_BORDER := Color(0.129, 0.090, 0.051, 0.95)

# --- judging windows (1:1 with game.js) -------------------------------------
const SLIDE_RATIO := 0.5
const MIN_PERFECT_MS := 140.0
const MIN_GOOD_MS := 260.0

const TILE_W := 142.0
const TILE_H := 174.0
const TILE_BORDER := 16.0
const TILE_FONT := 110

const STAGE_CENTER := Vector2(640, 360)

# --- tutorial (shown once when entering 1-1) --------------------------------
const TUTORIAL := [
	{"style": "boss", "text": "组长：今天是你试用期的最后一天了\n明天能不能继续上班，就看这个需求你今天写不写的完了"},
	{"style": "player", "text": "我保证完成任务！！\n绝不给组长丢脸！！"},
	{"style": "instruction", "bbcode": "[center]当[color=#d71920]上下数字重合[/color]并[color=#d71920]相同[/color]的时候\n按下下方的按钮吧\n[color=#d71920]不一样[/color]时千万[color=#d71920]不要[/color]按哦[/center]"},
]
const EXTREME_TUTORIAL := [
	{"style": "player", "text": "DDL是今晚12点，燃烧我的腱鞘炎！"},
]

# --- systems ----------------------------------------------------------------
var chiptune: Chiptune
var binary_stream: BinaryStream

# --- game state (level-specific) --------------------------------------------
var combo_scale := 1.0
var current_beat := 0
var last_judged_beat := -1
var current_beat_data: Dictionary = {}
var queue: Array[Dictionary] = []
var beat_outcome := "neutral"  # outcome of the current beat for the binary stream
var skip_run := 0
var press_run := 0

# --- juice ------------------------------------------------------------------
var zoom_punch := 0.0
var shake_amt := 0.0
var bar_flash := 0.0
var bar_color := Color.WHITE

# --- nodes ------------------------------------------------------------------
var stage: Control
var fx_layer: Node2D
var beat_flash: ColorRect
var hearts_box: HBoxContainer
var heart_nodes: Array[Panel] = []
var playfield: Panel
var hit_column: ColorRect
var combo_panel: Control
var combo_word: Label
var combo_count: Label
var hit_button: Button
var tutorial_layer: Control
var tutorial_holder: Control
var tutorial_index := 0
var tutorial_armed := false
var tutorial_steps: Array = []
var tutorial_arrow: Node2D
var tutorial_arrow_base_y := 0.0
var top_tiles: Array = []
var bottom_tiles: Array = []
var pulsers: Array = []         # [{node, intensity}]
var particles: Array[CPUParticles2D] = []
var particle_i := 0

# --- hit feedback sfx (separate from music) ---------------------------------
var snd_hit: AudioStreamWAV
var snd_miss: AudioStreamWAV


func make_cfg() -> Dictionary:
	return {
		"duration_ms": 45000.0, "start_bpm": 50.0, "end_bpm": 100.0,
		"bpm_curve_exp": 1.6, "subdivisions": 4,
		"press_ratio": 0.6, "max_skip_run": 2, "max_press_run": 3,
	}


# ===========================================================================
# LevelBase hooks
# ===========================================================================
func _make_music() -> Node:
	chiptune = Chiptune.new()
	return chiptune


func _conf() -> Dictionary:
	return {
		"score_caption": "SCORE",
		"text_col": COL_INK, "muted_col": COL_MUTED,
		"countdown_col": COL_INK, "penalty_col": COL_ACCENT,
		"fever_text": "FEVER!!", "fever_font": 72, "fever_col": Color("ff7a1a"), "fever_fill": COL_GOLD,
		"fever_overlay": Color(1.0, 0.78, 0.2), "fever_overlay_a": 0.10,
		"result_bg": Color.WHITE, "result_border": Color("252525"),
		"title_col": COL_GOLD, "lose_col": COL_ACCENT,
		"eval_bg": Color("faf8f3"), "eval_border": COL_GRID,
		"again_label": "再来一局",
		"score_fmt": "Score %d　命中 %d%%　最高 %d%s",
		"grade_cols": {"S": Color("ff7a1a"), "A": COL_GOLD, "B": COL_GREEN, "C": COL_INK, "D": COL_ACCENT},
	}


func _build_level() -> void:
	tutorial_steps = EXTREME_TUTORIAL if (app and app.extreme) else TUTORIAL
	tutorial_armed = (app.current_index == 0) if app else true
	_build_ui()


# ===========================================================================
# UI construction
# ===========================================================================
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Everything that should shake / zoom / breathe lives under `stage`.
	stage = Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.pivot_offset = STAGE_CENTER
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

	_build_playfield()
	_build_button()

	# FX (particles) and the whole-screen beat flash sit on top of the stage.
	fx_layer = Node2D.new()
	stage.add_child(fx_layer)
	for i in 8:
		var pr := _make_particles()
		fx_layer.add_child(pr)
		particles.append(pr)

	beat_flash = ColorRect.new()
	beat_flash.color = Color(1, 1, 1, 0)
	beat_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	beat_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(beat_flash)

	_build_tutorial()


func _build_hud() -> void:
	var score_group := _stat_group("SCORE", "0")
	score_group.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	score_group.position = Vector2(20, 10)
	stage.add_child(score_group)
	score_label = score_group.get_meta("value")
	pulsers.append({"node": score_group, "intensity": 0.05})

	var bpm_group := _stat_group("BPM", "50")
	bpm_group.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bpm_group.position = Vector2(-44, 10)
	stage.add_child(bpm_group)
	bpm_label = bpm_group.get_meta("value")
	pulsers.append({"node": bpm_group, "intensity": 0.05})

	hearts_box = HBoxContainer.new()
	hearts_box.add_theme_constant_override("separation", 10)
	hearts_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hearts_box.position = Vector2(-130, 18)
	stage.add_child(hearts_box)
	for i in 3:
		var h := Panel.new()
		h.custom_minimum_size = Vector2(28, 28)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.WHITE
		sb.set_border_width_all(4)
		sb.border_color = COL_ACCENT
		sb.set_corner_radius_all(14)
		h.add_theme_stylebox_override("panel", sb)
		hearts_box.add_child(h)
		heart_nodes.append(h)
	pulsers.append({"node": hearts_box, "intensity": 0.08})


func _stat_group(caption: String, value: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", COL_MUTED)
	box.add_child(cap)
	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 32)
	val.add_theme_color_override("font_color", COL_INK)
	box.add_child(val)
	box.set_meta("value", val)
	return box


func _build_playfield() -> void:
	playfield = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PLAYFIELD
	sb.set_border_width_all(2)
	sb.border_color = Color("252525")
	playfield.add_theme_stylebox_override("panel", sb)
	playfield.clip_contents = true
	playfield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	playfield.offset_left = 16
	playfield.offset_top = 72
	playfield.offset_right = -16
	playfield.offset_bottom = -150
	playfield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(playfield)

	_grid_line(true, 1.0 / 3.0)
	_grid_line(true, 2.0 / 3.0)
	_grid_line(false, 0.5)

	# Center "breathing light" — pulses white, tints gold on a clean hit and
	# red on a miss. Sits below the tiles so it glows around them.
	hit_column = ColorRect.new()
	hit_column.color = Color(1, 1, 1, 0.3)
	hit_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit_column.anchor_left = 1.0 / 3.0
	hit_column.anchor_right = 2.0 / 3.0
	hit_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	playfield.add_child(hit_column)

	# Binary background animation (top lane), behind the tiles.
	binary_stream = BinaryStream.new()
	binary_stream.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	binary_stream.anchor_bottom = 0.5
	binary_stream.offset_bottom = 0
	binary_stream.mouse_filter = Control.MOUSE_FILTER_IGNORE
	playfield.add_child(binary_stream)

	for i in 3:
		top_tiles.append(_make_tile())
		bottom_tiles.append(_make_tile())

	combo_panel = Control.new()
	combo_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	combo_panel.position = Vector2(24, -120)
	combo_panel.pivot_offset = Vector2(0, 100)
	combo_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	playfield.add_child(combo_panel)
	combo_word = Label.new()
	combo_word.text = "COMBO"
	combo_word.add_theme_font_size_override("font_size", 40)
	combo_panel.add_child(combo_word)
	combo_count = Label.new()
	combo_count.text = "0"
	combo_count.add_theme_font_size_override("font_size", 64)
	combo_count.position = Vector2(0, 44)
	combo_panel.add_child(combo_count)

	feedback_label = Label.new()
	feedback_label.text = "Ready"
	feedback_label.add_theme_font_size_override("font_size", 40)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	feedback_label.offset_top = -64
	feedback_label.offset_bottom = -14
	feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	playfield.add_child(feedback_label)

	countdown_label = Label.new()
	countdown_label.text = "3"
	countdown_label.add_theme_font_size_override("font_size", 180)
	countdown_label.add_theme_color_override("font_color", COL_INK)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	playfield.add_child(countdown_label)


func _grid_line(vertical: bool, frac: float) -> void:
	var line := ColorRect.new()
	line.color = COL_GRID
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if vertical:
		line.anchor_left = frac
		line.anchor_right = frac
		line.offset_left = -1.5
		line.offset_right = 1.5
	else:
		line.anchor_top = frac
		line.anchor_bottom = frac
		line.offset_top = -1.5
		line.offset_bottom = 1.5
	playfield.add_child(line)


func _make_tile() -> Dictionary:
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_border_width_all(int(TILE_BORDER))
	sb.border_color = COL_TILE_BORDER
	panel.add_theme_stylebox_override("panel", sb)
	panel.size = Vector2(TILE_W, TILE_H)
	panel.pivot_offset = Vector2(TILE_W, TILE_H) * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.add_theme_font_size_override("font_size", TILE_FONT)
	label.add_theme_color_override("font_color", COL_TILE_TEXT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(label)
	playfield.add_child(panel)
	return {"panel": panel, "label": label}


func _make_particles() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = 18
	p.lifetime = 0.5
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 480)
	p.initial_velocity_min = 180.0
	p.initial_velocity_max = 360.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	p.color = COL_GOLD
	return p


func _build_button() -> void:
	hit_button = Button.new()
	hit_button.text = "PRESS"
	hit_button.custom_minimum_size = Vector2(240, 96)
	hit_button.add_theme_font_size_override("font_size", 30)
	hit_button.focus_mode = Control.FOCUS_NONE
	hit_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color.WHITE
	normal.set_border_width_all(16)
	normal.border_color = COL_ACCENT
	normal.set_corner_radius_all(48)
	hit_button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color("fff4f4")     # subtle warm tint on hover
	hover.border_color = Color("e8242b")
	hit_button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = Color("ffe0e0")   # clearly pushed
	pressed.border_color = Color("b3151b")
	hit_button.add_theme_stylebox_override("pressed", pressed)
	hit_button.add_theme_color_override("font_color", COL_ACCENT)
	hit_button.add_theme_color_override("font_hover_color", COL_ACCENT)
	hit_button.add_theme_color_override("font_pressed_color", COL_ACCENT)
	hit_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hit_button.position = Vector2(-120, -120)
	hit_button.pivot_offset = Vector2(120, 48)
	hit_button.pressed.connect(_on_press_button)
	stage.add_child(hit_button)


# ===========================================================================
# Input (level-specific space / tutorial; base handles R / Esc / pause)
# ===========================================================================
func _on_space(pressed: bool) -> void:
	if pressed:
		judge_press()


func _extra_input(event: InputEvent) -> bool:
	if phase == "tutorial" and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			get_viewport().set_input_as_handled()
			_advance_tutorial()
		return true
	return false


func _on_press_button() -> void:
	judge_press()


# ===========================================================================
# Beat generation
# ===========================================================================
## Density-controlled generation: a target press ratio, plus run caps so we
## never get long clumps of the same type (the failure mode of plain coin
## flips). Keeps the chart even but still varied. Tunable per level.
func make_beat() -> Dictionary:
	# Quiet wind-down at the very end so the last press is clearly the last.
	if conductor.running and conductor.progress() > 0.9:
		return {"top": 0, "bottom": 1, "should_press": false}
	var should_press: bool
	if skip_run >= int(level.get("max_skip_run", 2)):
		should_press = true
	elif press_run >= int(level.get("max_press_run", 3)):
		should_press = false
	else:
		should_press = randf() < float(level.get("press_ratio", 0.6))
	if should_press:
		press_run += 1
		skip_run = 0
	else:
		skip_run += 1
		press_run = 0
	var top := 1 if randf() < 0.5 else 0
	return {"top": top, "bottom": top if should_press else 1 - top, "should_press": should_press}


func ensure_queue() -> void:
	while queue.size() < 5:
		queue.append(make_beat())


func prepare_beats() -> void:
	queue = []
	skip_run = 0
	press_run = 0
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


func judge_press() -> void:
	if phase != "running" or last_judged_beat == current_beat:
		return
	flash_button()
	var elapsed := conductor.beat_phase() * conductor.cycle_duration
	var stop_start := conductor.cycle_duration * SLIDE_RATIO
	var judge_center := stop_start + (conductor.cycle_duration - stop_start) * 0.5
	var delta := absf(elapsed - judge_center)
	last_judged_beat = current_beat

	if not current_beat_data["should_press"]:
		_penalty("Wrong", "wrong")
		return
	if delta <= perfect_window():
		reward("Perfect", 120)
	elif delta <= good_window():
		reward("Good", 80)
	else:
		_penalty("Bad", "wrong")


func miss_or_skip_if_needed() -> void:
	if phase != "running" or last_judged_beat == current_beat:
		return
	last_judged_beat = current_beat
	if current_beat_data["should_press"]:
		_penalty("Miss", "miss")
		return
	beat_outcome = "skip"
	set_feedback("Skip", COL_MUTED)


func reward(kind: String, points: int) -> void:
	score += points * (2 if fever_active else 1)   # Fever doubles
	combo += 1
	_fever_hit()
	beat_outcome = "hit"
	play_sfx(snd_hit)
	flash_bar(COL_GOLD)
	burst_hit()
	zoom_punch = maxf(zoom_punch, 0.035 if kind == "Perfect" else 0.022)
	update_hud()
	set_feedback(kind, COL_GOLD if kind == "Perfect" else COL_GREEN)


## main's penalty adds the binary-stream outcome + flash/shake, then the base.
func _penalty(text: String, outcome: String) -> void:
	beat_outcome = outcome
	play_sfx(snd_miss)
	flash_bar(COL_ACCENT)
	shake_amt = maxf(shake_amt, 12.0)
	zoom_punch = minf(zoom_punch, -0.02)
	apply_penalty(text)


# ===========================================================================
# HUD
# ===========================================================================
func update_hud() -> void:
	score_label.text = str(score)
	for i in heart_nodes.size():
		heart_nodes[i].modulate.a = 0.18 if i >= health else 1.0
	combo_count.text = str(combo)
	var tier := 0
	if combo >= 100: tier = 4
	elif combo >= 60: tier = 3
	elif combo >= 20: tier = 2
	elif combo >= 10: tier = 1
	combo_scale = 1.0 + mini(int(combo / 10.0), 10) * 0.055
	var col := COL_MUTED
	match tier:
		1: col = Color("fafafa")
		2: col = Color("ffe35c")
		3: col = COL_GOLD
		4: col = Color("ff4ad8")
	combo_word.add_theme_color_override("font_color", col)
	combo_count.add_theme_color_override("font_color", col)


func flash_button() -> void:
	var tw := create_tween()
	tw.tween_property(hit_button, "scale", Vector2(0.94, 0.94), 0.04)
	tw.tween_property(hit_button, "scale", Vector2.ONE, 0.08)


# ===========================================================================
# Tiles
# ===========================================================================
func layout_tiles(p: float) -> void:
	var w := playfield.size.x
	var h := playfield.size.y
	var move := minf(p / SLIDE_RATIO, 1.0)
	var top_x := [
		lerpf(0.16, 0.5, move) * w,
		lerpf(-0.18, 0.16, move) * w,
		lerpf(-0.52, -0.18, move) * w,
	]
	var bottom_x := [
		lerpf(0.84, 0.5, move) * w,
		lerpf(1.18, 0.84, move) * w,
		lerpf(1.52, 1.18, move) * w,
	]
	var beats := [current_beat_data, queue[0], queue[1]]
	var top_y := h * 0.25
	var bottom_y := h * 0.75
	for i in 3:
		var beat: Dictionary = beats[i]
		var preview := i > 0
		_place_tile(top_tiles[i], beat["top"], top_x[i], top_y, preview)
		_place_tile(bottom_tiles[i], beat["bottom"], bottom_x[i], bottom_y, preview)


func _place_tile(tile: Dictionary, value: int, cx: float, cy: float, preview: bool) -> void:
	var panel: Panel = tile["panel"]
	tile["label"].text = str(value)
	panel.position = Vector2(cx - TILE_W * 0.5, cy - TILE_H * 0.5)
	panel.modulate.a = 0.42 if preview else 1.0


func set_tiles_visible(v: bool) -> void:
	for t in top_tiles:
		t["panel"].visible = v
	for t in bottom_tiles:
		t["panel"].visible = v


# ===========================================================================
# Main loop
# ===========================================================================
func _advance(_delta: float) -> void:
	layout_tiles(clampf(conductor.beat_phase(), 0.0, 1.0))
	bpm_label.text = str(roundi(conductor.bpm()))


func _juice(delta: float) -> void:
	if phase == "tutorial" and is_instance_valid(tutorial_arrow):
		tutorial_arrow.position.y = tutorial_arrow_base_y + sin(Time.get_ticks_msec() * 0.006) * 11.0
	_update_juice(delta)


func _on_beat(_cycle_index: int) -> void:
	if phase != "running":
		return
	miss_or_skip_if_needed()
	if phase != "running":
		return
	binary_stream.push(current_beat_data["top"], beat_outcome)
	beat_outcome = "neutral"
	current_beat_data = queue.pop_front()
	ensure_queue()
	current_beat += 1
	if conductor.progress() > 0.85:
		chiptune.finale = true   # audible wind-down before the level ends


func _countdown_tick(last: bool) -> void:
	flash_bar(COL_GOLD if last else Color.WHITE)
	play_sfx(snd_hit if last else snd_miss, -8.0)


# ===========================================================================
# Phase transitions
# ===========================================================================
func _reset_level() -> void:
	current_beat = 0
	last_judged_beat = -1
	beat_outcome = "neutral"
	prepare_beats()
	binary_stream.clear()
	layout_tiles(1.0)


func _enter_start() -> void:
	# First visit to 1-1 plays the tutorial; otherwise straight to the count-in.
	if tutorial_armed:
		tutorial_armed = false
		_enter_tutorial()
	else:
		_enter_countdown()


func _enter_countdown() -> void:
	super()
	set_tiles_visible(false)
	set_feedback("Ready", COL_MUTED)


func _begin_play() -> void:
	current_beat = 0
	last_judged_beat = -1
	set_tiles_visible(true)
	set_feedback("Start", COL_MUTED)


# ===========================================================================
# Tutorial (three dialog beats, then the count-in)
# ===========================================================================
func _build_tutorial() -> void:
	tutorial_layer = Control.new()
	tutorial_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tutorial_layer.visible = false
	tutorial_layer.gui_input.connect(_on_tutorial_input)
	add_child(tutorial_layer)

	# Dim layer behind the dialog boxes to push the background back.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_layer.add_child(dim)

	tutorial_holder = Control.new()
	tutorial_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tutorial_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_layer.add_child(tutorial_holder)

	var hint := Label.new()
	hint.text = "（点击任意处继续）"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", COL_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -28
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_layer.add_child(hint)


func _enter_tutorial() -> void:
	phase = "tutorial"
	countdown_label.visible = false
	set_tiles_visible(true)
	set_feedback("", COL_MUTED)
	tutorial_index = 0
	tutorial_layer.visible = true
	_show_tutorial_step(0)


func _on_tutorial_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance_tutorial()


func _advance_tutorial() -> void:
	tutorial_index += 1
	if tutorial_index >= tutorial_steps.size():
		tutorial_layer.visible = false
		_enter_countdown()
	else:
		_show_tutorial_step(tutorial_index)


func _show_tutorial_step(i: int) -> void:
	for c in tutorial_holder.get_children():
		c.queue_free()
	tutorial_arrow = null
	var step: Dictionary = tutorial_steps[i]
	match step["style"]:
		"boss":
			_tut_box(step["text"], Color.BLACK, Color.WHITE, false,
				Vector2(300, 470), Vector2(680, 150), 28, HORIZONTAL_ALIGNMENT_LEFT)
		"player":
			_tut_box(step["text"], Color.WHITE, COL_INK, true,
				Vector2(310, 250), Vector2(660, 200), 40, HORIZONTAL_ALIGNMENT_CENTER)
		"instruction":
			_tut_instruction(step["bbcode"])


func _tut_box(text: String, bg: Color, fg: Color, border: bool, pos: Vector2,
		box_size: Vector2, font: int, halign: int) -> void:
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if border:
		sb.set_border_width_all(6)
		sb.border_color = COL_INK
	box.add_theme_stylebox_override("panel", sb)
	box.position = pos
	box.size = box_size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_holder.add_child(box)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font)
	lbl.add_theme_color_override("font_color", fg)
	lbl.horizontal_alignment = halign
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.offset_left = 26
	lbl.offset_right = -26
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lbl)


func _tut_instruction(bbcode: String) -> void:
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_border_width_all(5)
	sb.border_color = COL_INK
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(260, 150)
	box.size = Vector2(760, 300)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_holder.add_child(box)

	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.scroll_active = false
	rich.add_theme_font_size_override("normal_font_size", 36)
	rich.add_theme_color_override("default_color", COL_INK)
	rich.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rich.offset_left = 26
	rich.offset_right = -26
	rich.offset_top = 40
	rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rich.text = bbcode
	box.add_child(rich)

	# Big red down-arrow pointing at the PRESS button, bouncing in _process.
	tutorial_arrow = _make_arrow()
	tutorial_arrow_base_y = 560.0
	tutorial_arrow.position = Vector2(640, tutorial_arrow_base_y)
	tutorial_holder.add_child(tutorial_arrow)


func _make_arrow() -> Node2D:
	var root := Node2D.new()
	var pts := PackedVector2Array([
		Vector2(-16, -52), Vector2(16, -52), Vector2(16, 2),
		Vector2(42, 2), Vector2(0, 56), Vector2(-42, 2), Vector2(-16, 2),
	])
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = COL_ACCENT
	root.add_child(poly)
	var outline := Line2D.new()
	outline.points = pts
	outline.closed = true
	outline.width = 5.0
	outline.default_color = COL_INK
	root.add_child(outline)
	return root


func _on_level_finished() -> void:
	if phase == "running":
		end_game(true)


func _verdict(hearts_lost: int, won: bool) -> Dictionary:
	if won and app and app.extreme:
		match hearts_lost:
			0: return {"rank": "PERFECT", "color": COL_GOLD, "eval": "成功上线，组织会记住你的好"}
			1: return {"rank": "GREAT", "color": COL_GREEN, "eval": "12：00：59也算12点，不超时"}
			_: return {"rank": "CLEAR", "color": COL_INK, "eval": "管它怎么跑，能跑就行"}
	elif won:
		match hearts_lost:
			0: return {"rank": "PERFECT", "color": COL_GOLD, "eval": "你简直就是天才，人类荣光永不灭"}
			1: return {"rank": "GREAT", "color": COL_GREEN, "eval": "有点小bug，无伤大雅，明天继续上班"}
			_: return {"rank": "CLEAR", "color": COL_INK, "eval": "你应该学习一下怎么使用大模型了"}
	var ev := "这是新来的claude，你明天不用来上班了" if (app and app.extreme) else "内核崩溃，重新编译再来一次"
	return {"rank": "GAME OVER", "color": COL_ACCENT, "eval": ev}


# ===========================================================================
# Juice — driven every frame by conductor.pulse()
# ===========================================================================
func _update_juice(delta: float) -> void:
	var p := conductor.pulse()

	# Whole-screen beat flash + stage breathing (everything pulses to the beat).
	beat_flash.color.a = p * 0.05
	zoom_punch = move_toward(zoom_punch, 0.0, delta * 0.25)
	shake_amt = move_toward(shake_amt, 0.0, delta * 60.0)
	stage.scale = Vector2.ONE * (1.0 + p * 0.012 + zoom_punch)
	stage.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amt

	# Per-element pulse pops.
	for pl in pulsers:
		var n: Control = pl["node"]
		n.pivot_offset = n.size * 0.5
		n.scale = Vector2.ONE * (1.0 + p * pl["intensity"])
	combo_panel.scale = Vector2.ONE * combo_scale * (1.0 + p * 0.05)

	# Breathing light: white base pulse, tinted toward the last judge result.
	bar_flash = move_toward(bar_flash, 0.0, delta * 2.0)
	var c: Color = Color.WHITE.lerp(bar_color, bar_flash)
	hit_column.color = Color(c.r, c.g, c.b, 0.22 + p * 0.4 + bar_flash * 0.2)


func flash_bar(col: Color) -> void:
	bar_color = col
	bar_flash = 1.0


func burst_hit() -> void:
	var cx := playfield.position.x + playfield.size.x * 0.5
	_emit_particles(Vector2(cx, playfield.position.y + playfield.size.y * 0.25))
	_emit_particles(Vector2(cx, playfield.position.y + playfield.size.y * 0.75))


func _emit_particles(pos: Vector2) -> void:
	var pr := particles[particle_i]
	particle_i = (particle_i + 1) % particles.size()
	pr.position = pos
	pr.restart()
	pr.emitting = true


# ===========================================================================
# Hit-feedback SFX (distinct from the music)
# ===========================================================================
func _build_sfx() -> void:
	snd_hit = tone(720.0, 1100.0, 0.09, "triangle", 0.5)
	snd_miss = tone(200.0, 80.0, 0.16, "sawtooth", 0.45)
