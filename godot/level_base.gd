class_name LevelBase
extends Control
## Shared framework for every rhythm level. Owns the parts that were copy-pasted
## across 1-1/1-2/1-3: Conductor lifecycle, SFX pool + synth, HUD, Fever, result
## screen + S/A/B/C/D grade, countdown, pause wiring, scoring/penalty bookkeeping,
## and the input/process skeleton. Each level subclasses this and overrides hooks
## for its own theme (`_conf()`), visuals/chart/judging/FX, and SFX — so a level
## file holds ONLY what is unique to it.
##
## Cohesion split: the OUTCOME of a judgement (score/combo/Fever on a hit;
## health/combo/Fever-break on a miss) + timing classification live here; the
## NOTE MODEL (which note is at the line, scroll/park/grid math) stays per-level,
## with per-level tunable windows.

const _LevelChartBridgeScript := preload("res://rhythm/level_chart_bridge.gd")

const COUNTDOWN_BEATS := ["3", "2", "1", "START"]

# --- shared state -----------------------------------------------------------
var app
var level: Dictionary
var conductor: Conductor
var music: Node
var pause_menu: PauseMenu

var phase := "idle"
var countdown_start := 0.0
var countdown_step := -1
var health := 3
var score := 0
var combo := 0
var fever_gauge := 0.0
var fever_active := false
var fever_time := 0.0
var notes_hit := 0
var notes_missed := 0
var t := 0.0

# --- shared HUD / fever / result nodes --------------------------------------
var score_label: Label
var bpm_label: Label
var hearts: Array = []
var feedback_label: Label
var countdown_label: Label
var fever_overlay: ColorRect
var fever_bar_bg: Panel
var fever_bar_fill: ColorRect
var fever_label: Label
var result_layer: ColorRect
var result_title: Label
var result_grade: Label
var result_eval: Label
var result_score: Label

# --- shared sfx pool --------------------------------------------------------
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_i := 0

var _conf_cache: Dictionary = {}


# ===========================================================================
# Lifecycle (template method)
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
	_conf_cache = _conf()

	conductor = Conductor.new()
	conductor.setup(level)
	conductor.auto_finish = _auto_finish()
	add_child(conductor)
	conductor.beat.connect(_on_beat)
	conductor.downbeat.connect(_on_downbeat)
	conductor.subdivision.connect(_on_subdivision)
	conductor.level_finished.connect(_on_level_finished)

	music = _make_music()
	if music:
		add_child(music)
		if music.has_method("setup"):
			music.setup(conductor)

	_build_sfx_pool()
	_build_sfx()
	_build_level()            # subclass: world / tiles / button / chart / level HUD bits
	_build_hud()
	_build_fever()
	_build_result()
	_build_pause()
	start_game()


func now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0


func chart_meta_for(level_id: String) -> Dictionary:
	return _LevelChartBridgeScript.load_meta(level_id, bool(app and app.extreme))


func chart_for(level_id: String):
	return _LevelChartBridgeScript.load_chart(level_id, bool(app and app.extreme))


func chart_sequencer_for(level_id: String, ticks_per_beat := 1):
	return _LevelChartBridgeScript.load_sequencer(level_id, bool(app and app.extreme), ticks_per_beat)


func chart_slots_for(level_id: String, ticks_per_beat: int, map_event: Callable,
		rest_data: Dictionary, end_data: Dictionary) -> Array:
	return _LevelChartBridgeScript.load_discrete_slots(level_id, bool(app and app.extreme),
		ticks_per_beat, map_event, rest_data, end_data)


func setup_chart_music(level_id: String, fallback_script) -> Node:
	var meta := chart_meta_for(level_id)
	_LevelChartBridgeScript.apply_meta_to_level(meta, level, conductor)
	return _LevelChartBridgeScript.make_music_from_meta(meta, fallback_script)


# ===========================================================================
# Overridable hooks (subclass provides the level's identity)
# ===========================================================================
func make_cfg() -> Dictionary:
	return {"duration_ms": 45000.0, "start_bpm": 60.0, "end_bpm": 100.0,
		"bpm_curve_exp": 1.6, "subdivisions": 4}

func _conf() -> Dictionary:
	return {}                                   # theming: colors/captions/labels

func _auto_finish() -> bool:
	return true                                 # 1-3 overrides to false (chart-driven end)

func _make_music() -> Node:
	return null

func _build_level() -> void:
	pass                                        # build the level's world/tiles/button/chart

func _build_sfx() -> void:
	pass                                        # build the level's sounds into the pool

func _reset_level() -> void:
	pass                                        # per-restart gameplay reset

func _enter_start() -> void:
	_enter_countdown()                          # 1-2/1-3 override -> intro; 1-1 -> tutorial

func _begin_play() -> void:
	pass                                        # called right after conductor.start()

func _on_space(_pressed: bool) -> void:
	pass                                        # the level's space-key handling

func _extra_input(_event: InputEvent) -> bool:
	return false                                # mouse-intro / tutorial; true = consumed

func _advance(_delta: float) -> void:
	pass                                        # per-frame gameplay: layout + miss-sweep + bpm

func _juice(_delta: float) -> void:
	pass                                        # per-frame visual juice

func _outro_fx() -> void:
	pass                                        # ending burst

func _verdict(_hearts_lost: int, _won: bool) -> Dictionary:
	return {"rank": "", "eval": ""}             # {rank, eval} text per outcome

func _make_heart() -> Control:
	var c := ColorRect.new()                    # subclass returns a themed heart
	c.color = Color("e2584f")
	c.custom_minimum_size = Vector2(28, 28)
	return c

func _set_heart(node: Control, lost: bool) -> void:
	if node.has_method("set_lost"):
		node.set_lost(lost)
	else:
		node.modulate.a = 0.2 if lost else 1.0


# ===========================================================================
# Conductor signal dispatch (default no-ops; subclass overrides what it needs)
# ===========================================================================
func _on_beat(_cycle_index: int) -> void:
	pass

func _on_downbeat(_cycle_index: int) -> void:
	pass

func _on_subdivision(_cycle_index: int, _sub: int) -> void:
	pass

func _on_level_finished() -> void:
	if phase == "running":
		_start_outro()


# ===========================================================================
# SFX (pool + synth shared by every level)
# ===========================================================================
func _build_sfx_pool() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		sfx_players.append(p)


func play_sfx(stream: AudioStreamWAV, volume_db := -3.0) -> void:
	if stream == null:
		return
	var p := sfx_players[sfx_i]
	sfx_i = (sfx_i + 1) % sfx_players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.play()


## 16-bit mono one-shot synth (sine / triangle), pitch-sliding optional.
func tone(freq: float, slide_to: float, dur: float, wave: String, gain: float) -> AudioStreamWAV:
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
			"sawtooth": s = 2.0 * fposmod(phase / TAU, 1.0) - 1.0
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
		if ResourceLoader.exists(p):
			var res := load(p)
			if res is Texture2D:
				return res
		if FileAccess.file_exists(p):
			var img := Image.new()
			if img.load(p) == OK:
				return ImageTexture.create_from_image(img)
	return null


# ===========================================================================
# HUD
# ===========================================================================
func _build_hud() -> void:
	var c := _conf_cache
	var text_col: Color = c.get("text_col", Color.WHITE)
	var muted_col: Color = c.get("muted_col", Color.GRAY)

	var score_group := _stat(c.get("score_caption", "SCORE"), "0", text_col, muted_col)
	score_group.position = Vector2(20, 12)
	add_child(score_group)
	score_label = score_group.get_meta("value")

	var bpm_group := _stat("BPM", str(int(level["start_bpm"])), text_col, muted_col)
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
		var d := _make_heart()
		hearts_box.add_child(d)
		hearts.append(d)

	feedback_label = Label.new()
	feedback_label.add_theme_font_size_override("font_size", 40)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fb: Dictionary = c.get("feedback", {"preset": Control.PRESET_BOTTOM_WIDE, "top": -190.0, "bottom": -140.0})
	feedback_label.set_anchors_and_offsets_preset(int(fb.get("preset", Control.PRESET_BOTTOM_WIDE)))
	if fb.has("left"): feedback_label.offset_left = fb["left"]
	if fb.has("right"): feedback_label.offset_right = fb["right"]
	feedback_label.offset_top = fb.get("top", -190.0)
	feedback_label.offset_bottom = fb.get("bottom", -140.0)
	add_child(feedback_label)

	countdown_label = Label.new()
	countdown_label.text = "3"
	countdown_label.add_theme_font_size_override("font_size", 170)
	countdown_label.add_theme_color_override("font_color", c.get("countdown_col", text_col))
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	countdown_label.visible = false
	add_child(countdown_label)


func _stat(caption: String, value: String, text_col: Color, muted_col: Color) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", muted_col)
	box.add_child(cap)
	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 30)
	val.add_theme_color_override("font_color", text_col)
	box.add_child(val)
	box.set_meta("value", val)
	return box


func set_feedback(text: String, col: Color) -> void:
	feedback_label.text = text
	feedback_label.add_theme_color_override("font_color", col)


func update_hud() -> void:
	score_label.text = str(score)
	for i in hearts.size():
		_set_heart(hearts[i], i >= health)


# ===========================================================================
# Fever
# ===========================================================================
func _build_fever() -> void:
	var c := _conf_cache
	fever_overlay = ColorRect.new()
	fever_overlay.color = c.get("fever_overlay", Color(1.0, 0.62, 0.12, 0.0))
	fever_overlay.color.a = 0.0
	fever_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fever_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fever_overlay)

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
	fever_bar_fill.color = c.get("fever_fill", Color("ffcf52"))
	fever_bar_fill.position = Vector2(2, 2)
	fever_bar_fill.size = Vector2(0, 10)
	fever_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fever_bar_bg.add_child(fever_bar_fill)

	fever_label = Label.new()
	fever_label.text = c.get("fever_text", "FEVER!!")
	fever_label.add_theme_font_size_override("font_size", c.get("fever_font", 72))
	fever_label.add_theme_color_override("font_color", c.get("fever_col", Color("ff7a1a")))
	fever_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fever_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	fever_label.offset_top = 92
	fever_label.pivot_offset = Vector2(640, 130)
	fever_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fever_label.visible = false
	add_child(fever_label)


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
	set_feedback(_conf_cache.get("fever_text", "FEVER!"), _conf_cache.get("fever_col", Color("ff7a1a")))


func _end_fever() -> void:
	fever_active = false
	fever_gauge = 0.0
	fever_label.visible = false


## Per-frame Fever visuals (called from the base _process).
func _process_fever(p: float, delta: float) -> void:
	if fever_active:
		fever_time -= delta
		if fever_time <= 0.0:
			_end_fever()
	var c := _conf_cache
	fever_overlay.color.a = (c.get("fever_overlay_a", 0.10) + 0.12 * p) if fever_active else 0.0
	fever_bar_fill.size.x = clampf(fever_gauge, 0.0, 1.0) * 296.0
	fever_bar_fill.color = c.get("fever_col", Color("ff7a1a")) if fever_active else c.get("fever_fill", Color("ffcf52"))
	if fever_active:
		fever_label.scale = Vector2.ONE * (1.0 + 0.18 * p)


# ===========================================================================
# Scoring / penalty (shared outcome bookkeeping)
# ===========================================================================
func _add_score(points: int) -> void:
	score += points * (2 if fever_active else 1)   # Fever doubles
	combo += 1
	update_hud()


func apply_penalty(text: String) -> void:
	health -= 1
	combo = 0
	notes_missed += 1
	if fever_active:
		_end_fever()
	update_hud()
	set_feedback(text, _conf_cache.get("penalty_col", Color("d24b4b")))
	if health <= 0:
		end_game(false)


# Timing windows (default formula; subclasses set their own MIN_* + may override).
func perfect_window() -> float:
	return conductor.cycle_duration * 0.14


func good_window() -> float:
	return conductor.cycle_duration * 0.28


func classify(error_ms: float) -> String:
	if error_ms <= perfect_window():
		return "perfect"
	elif error_ms <= good_window():
		return "good"
	return "miss"


# ===========================================================================
# Countdown
# ===========================================================================
func _enter_countdown() -> void:
	phase = "countdown"
	countdown_start = now_ms()
	countdown_step = -1
	countdown_label.visible = true
	set_feedback("准备", _conf_cache.get("muted_col", Color.GRAY))


func update_countdown(now: float) -> void:
	var step_ms := 60000.0 / float(level["start_bpm"])
	var elapsed := now - countdown_start
	var step := mini(int(elapsed / step_ms), COUNTDOWN_BEATS.size() - 1)
	if step != countdown_step:
		countdown_step = step
		countdown_label.text = COUNTDOWN_BEATS[step]
		countdown_label.pivot_offset = countdown_label.size * 0.5
		countdown_label.scale = Vector2(0.72, 0.72)
		_countdown_tick(step == COUNTDOWN_BEATS.size() - 1)
		var tw := create_tween()
		tw.tween_property(countdown_label, "scale", Vector2.ONE, 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if elapsed >= step_ms * COUNTDOWN_BEATS.size():
		begin_run()


func _countdown_tick(_last: bool) -> void:
	pass                                        # subclass plays its count-in blip


func begin_run() -> void:
	phase = "running"
	countdown_label.visible = false
	conductor.start()
	_begin_play()


# ===========================================================================
# Pause
# ===========================================================================
func _build_pause() -> void:
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.request_pause.connect(func() -> void: conductor.pause())
	pause_menu.request_resume.connect(func() -> void: conductor.resume())
	pause_menu.request_restart.connect(start_game)
	pause_menu.request_quit.connect(func() -> void:
		if app:
			app.goto_levels())


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
	conductor.stop()
	conductor.tempo_scale = 1.0
	if music and music.has_method("reset"):
		music.reset()
	result_layer.visible = false
	bpm_label.text = str(int(level["start_bpm"]))
	_reset_level()
	update_hud()
	_enter_start()


func _start_outro() -> void:
	if phase != "running":
		return
	phase = "outro"
	conductor.stop()
	conductor.tempo_scale = 1.0
	_end_fever()
	if music and music.has_method("play_outro"):
		music.play_outro()
	_outro_fx()
	get_tree().create_timer(2.2).timeout.connect(func() -> void:
		if is_instance_valid(self):
			end_game(true))


func end_game(won: bool) -> void:
	phase = "won" if won else "lost"
	conductor.stop()
	conductor.tempo_scale = 1.0
	if won and app:
		app.record_result(app.current_index, 3 - health)   # 0 lost -> unlock Extreme
	var c := _conf_cache
	var v := _verdict(3 - health, won)
	result_title.text = v.get("rank", "")
	result_eval.text = v.get("eval", "")
	var tcol: Color = c.get("title_col", Color.WHITE) if won else c.get("lose_col", c.get("title_col", Color.WHITE))
	result_title.add_theme_color_override("font_color", v.get("color", tcol))

	# Letter grade from accuracy.
	var acc := float(notes_hit) / maxf(float(notes_hit + notes_missed), 1.0)
	var gcols: Dictionary = c.get("grade_cols", {})
	var grade := "D"
	if acc >= 0.97: grade = "S"
	elif acc >= 0.88: grade = "A"
	elif acc >= 0.75: grade = "B"
	elif acc >= 0.55: grade = "C"
	result_grade.text = grade
	result_grade.add_theme_color_override("font_color", gcols.get(grade, Color.WHITE))

	var new_best := false
	var best := score
	if app:
		new_best = app.record_score(app.current_index, score)
		best = app.get_best(app.current_index)
	var best_tag := "  ★新纪录!" if new_best else ""
	var fmt: String = c.get("score_fmt", "Score %d　命中 %d%%　最高 %d%s")
	result_score.text = fmt % [score, roundi(acc * 100.0), best, best_tag]
	result_layer.visible = true


# ===========================================================================
# Result screen
# ===========================================================================
func _build_result() -> void:
	var c := _conf_cache
	result_layer = ColorRect.new()
	result_layer.color = Color(0, 0, 0, 0.55)
	result_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_layer.visible = false
	add_child(result_layer)

	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = c.get("result_bg", Color.WHITE)
	sb.set_border_width_all(2)
	sb.border_color = c.get("result_border", Color("252525"))
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

	result_grade = Label.new()
	result_grade.add_theme_font_size_override("font_size", 72)
	result_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(result_grade)

	result_title = Label.new()
	result_title.add_theme_font_size_override("font_size", 32)
	result_title.add_theme_color_override("font_color", c.get("title_col", Color("f6b800")))
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(result_title)

	var eval_box := PanelContainer.new()
	var eb := StyleBoxFlat.new()
	eb.bg_color = c.get("eval_bg", Color("faf8f3"))
	eb.set_border_width_all(2)
	eb.border_color = c.get("eval_border", Color("c9c9c4"))
	eb.set_corner_radius_all(8)
	eb.content_margin_left = 16
	eb.content_margin_right = 16
	eb.content_margin_top = 14
	eb.content_margin_bottom = 14
	eval_box.add_theme_stylebox_override("panel", eb)
	vb.add_child(eval_box)
	result_eval = Label.new()
	result_eval.add_theme_font_size_override("font_size", 20)
	result_eval.add_theme_color_override("font_color", c.get("text_col", Color("21170d")))
	result_eval.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_eval.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_eval.custom_minimum_size = Vector2(400, 0)
	eval_box.add_child(result_eval)

	result_score = Label.new()
	result_score.add_theme_font_size_override("font_size", 20)
	result_score.add_theme_color_override("font_color", c.get("muted_col", Color("77746d")))
	result_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(result_score)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(buttons)
	var again := Button.new()
	again.text = c.get("again_label", "再来一局")
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
# Input / process skeletons
# ===========================================================================
func _input(event: InputEvent) -> void:
	if _extra_input(event):
		return
	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()
			if not pause_menu.is_paused:
				_on_space(event.pressed)
		elif event.pressed and event.keycode == KEY_R:
			start_game()
		elif event.pressed and event.keycode == KEY_ESCAPE:
			if phase == "running":
				pause_menu.toggle()
			elif app:
				app.goto_levels()


func _process(delta: float) -> void:
	t += delta
	pause_menu.set_active(phase == "running")
	if phase == "countdown":
		update_countdown(now_ms())
	elif phase == "running" and not pause_menu.is_paused:
		_advance(delta)
	var p := conductor.pulse() if conductor.running else 0.0
	_juice(delta)
	_process_fever(p, delta)
