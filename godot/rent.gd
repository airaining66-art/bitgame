extends LevelBase

const RhythmChartScript := preload("res://rhythm/rhythm_chart.gd")
const RhythmChartRuntimeScript := preload("res://rhythm/rhythm_chart_runtime.gd")
const JudgementRuntimeScript := preload("res://rhythm/judgement_runtime.gd")
const BeatSlotJudgementScript := preload("res://rhythm/beat_slot_judgement.gd")
## 1-5 鎴跨鐨勪富浜?## Core rule: one button only. Stressful things are handled at the center line:
## bills and scam calls are fanned away, loan requests are guarded. Nice things
## should pass by untouched. Fixed story beats add a boss tap challenge and a
## landlord hold challenge.

# --- palette ----------------------------------------------------------------
const COL_BG_TOP := Color("c9f4df")
const COL_BG_BOT := Color("f7f1cc")
const COL_INK := Color("34524b")
const COL_MUTED := Color("7a9b90")
const COL_CREAM := Color("fff5cf")
const COL_GOLD := Color("f3bd3d")
const COL_ORANGE := Color("ef8a3c")
const COL_GREEN := Color("4fb978")
const COL_BLUE := Color("58bfe8")
const COL_RED := Color("df5a4f")
const COL_DARK := Color("263e3a")

# --- item kinds -------------------------------------------------------------
const BILL := 0
const SCAM := 1
const LOAN := 2
const FOOD := 3
const GAME := 4
const GIRL := 5

const ACTION_NONE := 0
const ACTION_FAN := 1
const ACTION_GUARD := 2

const KIND_NAME := ["账单", "诈骗电话", "朋友借钱", "美食", "游戏", "心动"]
const KIND_ACTION := [ACTION_FAN, ACTION_FAN, ACTION_GUARD, ACTION_NONE, ACTION_NONE, ACTION_NONE]

const CHALLENGE_NONE := 0
const CHALLENGE_BOSS := 1
const CHALLENGE_LANDLORD := 2

# --- layout / timing --------------------------------------------------------
const STRIKE := Vector2(640.0, 338.0)
const TRAVEL_STRESS := 2.05
const TRAVEL_TREAT := 4.0
const R_SPAWN := 840.0
const NOTE_SLOTS := 7
const JUDGE_OFFSET := 0.75
const MIN_PERFECT_MS := 110.0
const MIN_GOOD_MS := 225.0

const STORY_DEFAULT_WARN_BEATS := 2.0
const STORY_DEFAULT_BEATS := 4.0
const STORY_DEFAULT_TAPS := 8
const STORY_DEFAULT_HOLD_MS := 1400.0
const STORY_DEFAULT_LEN := 0.54
const STORY_DEFAULT_CONVERGE_MS := 650.0

# Transitional aliases while the story bars are being folded into the shared
# single/tap/hold model. Keep these here so tuning values have one source.
const BOSS_TAPS := STORY_DEFAULT_TAPS
const BOSS_BEATS := STORY_DEFAULT_BEATS
const LANDLORD_HOLD_MS := STORY_DEFAULT_HOLD_MS
const LANDLORD_BEATS := STORY_DEFAULT_BEATS
const CHALLENGE_WARN_BEATS := STORY_DEFAULT_WARN_BEATS
const CHALLENGE_CONVERGE_MS := STORY_DEFAULT_CONVERGE_MS

# --- state ------------------------------------------------------------------
var rent_music: Node
var current_beat := 0
var current_beat_data: Dictionary = {}
var prev_beat_data: Dictionary = {}
var queue: Array[Dictionary] = []
var active_chart_beats: Array = []
var chart_runtime
var chart_loaded := false
var chart_duration_beats := 0.0
var normal_chart_events: Array[Dictionary] = []
var normal_event_by_id: Dictionary = {}
var judgement_runtime
var beat_judgement := BeatSlotJudgementScript.new()
var chart_i := 0
var spawn_count := 0
var hidden_beat := -999
var key_held := false

var challenge_active := false
var challenge_type := CHALLENGE_NONE
var challenge_started_ms := 0.0
var challenge_duration_ms := 0.0
var challenge_taps := 0
var challenge_hold_ms := 0.0
var challenge_hold_live := false
var challenge_done_this_press := false
var challenge_satisfied := false
var warning_active := false
var warning_type := CHALLENGE_NONE
var warning_started_ms := 0.0
var warning_duration_ms := 0.0
var warning_angle := 0.0
var pending_story_angle := -1.5708
var pending_story_cfg: Dictionary = {}
var current_story_cfg: Dictionary = {}
var story_head_beat := -999.0
var story_tail_beat := -999.0
var story_events: Array[Dictionary] = []
var story_event_i := 0
var active_story_event: Dictionary = {}

# --- juice ------------------------------------------------------------------
var shake := 0.0
var flash := 0.0
var ring_pulse := 0.0
var btn_pop := 0.0

# --- nodes ------------------------------------------------------------------
var stage: Control
var arena: _Arena
var action_tool: _ActionTool
var judge_ring: _JudgeRing
var action_fx: _ActionFx
var item_tiles: Array = []
var hit_button: Button
var intro_layer: ColorRect
var intro_label: Label
var role_sheet: Texture2D
var boss_tex: Texture2D

# --- sfx --------------------------------------------------------------------
var snd_fan: AudioStreamWAV
var snd_guard: AudioStreamWAV
var snd_wrong: AudioStreamWAV
var snd_pass: AudioStreamWAV
var snd_count: AudioStreamWAV
var snd_warn_stress: AudioStreamWAV
var snd_warn_treat: AudioStreamWAV
var snd_tap: AudioStreamWAV
var snd_hold: AudioStreamWAV


# ===========================================================================
# LevelBase hooks
# ===========================================================================
func make_cfg() -> Dictionary:
	var cfg := {
		"duration_ms": 46000.0, "start_bpm": 80.0, "end_bpm": 104.0,
		"bpm_curve_exp": 1.5, "subdivisions": 4,
	}
	var chart_meta := chart_meta_for("1-5")
	for key in ["start_bpm", "end_bpm", "bpm_curve_exp", "subdivisions"]:
		if chart_meta.has(key):
			cfg[key] = chart_meta[key]
	return cfg


func _auto_finish() -> bool:
	return false


func _make_music() -> Node:
	rent_music = setup_chart_music("1-5", RentMusic)
	return rent_music


func _conf() -> Dictionary:
	return {
		"score_caption": "余额",
		"text_col": COL_INK, "muted_col": COL_MUTED,
		"countdown_col": COL_ORANGE, "penalty_col": COL_RED,
		"fever_text": "抗压 FEVER!!", "fever_col": COL_ORANGE, "fever_fill": COL_GOLD,
		"fever_overlay": Color(1.0, 0.74, 0.20), "fever_overlay_a": 0.08,
		"result_bg": Color("fffaf0"), "result_border": COL_GOLD,
		"title_col": COL_GREEN, "lose_col": COL_RED,
		"eval_bg": Color("fff2cf"), "eval_border": Color("e8c675"),
		"again_label": "再来一局",
		"score_fmt": "余额 %d  命中 %d%%  最高 %d%s",
		"grade_cols": {"S": COL_GOLD, "A": COL_GREEN, "B": COL_BLUE, "C": COL_INK, "D": COL_MUTED},
	}


func _build_level() -> void:
	role_sheet = _load_tex([
		"res://assets/rent_characters_sheet_alpha.png",
		"res://assets/rent_characters_sheet.png",
	])
	boss_tex = _load_tex([
		"res://assets/rent_boss_greasy_alpha.png",
		"res://assets/rent_boss_greasy.png",
	])
	_build_scene()
	_build_items()
	_build_action_tool()
	_build_button()
	_build_intro()


func _build_sfx() -> void:
	snd_fan = tone(760.0, 1280.0, 0.08, "sine", 0.45)
	snd_guard = tone(260.0, 140.0, 0.12, "triangle", 0.55)
	snd_wrong = tone(180.0, 80.0, 0.22, "sawtooth", 0.42)
	snd_pass = tone(720.0, 980.0, 0.08, "triangle", 0.38)
	snd_count = tone(440.0, 0.0, 0.07, "sine", 0.4)
	snd_warn_stress = tone(300.0, 880.0, 0.10, "sawtooth", 0.28)
	snd_warn_treat = tone(880.0, 1320.0, 0.12, "sine", 0.24)
	snd_tap = tone(680.0, 1020.0, 0.05, "triangle", 0.34)
	snd_hold = tone(320.0, 460.0, 0.08, "sine", 0.28)


func _make_heart() -> Control:
	var d := _CoinHeart.new()
	d.custom_minimum_size = Vector2(30, 30)
	return d


func _reset_level() -> void:
	current_beat = 0
	beat_judgement.reset()
	spawn_count = 0
	hidden_beat = -999
	key_held = false
	_clear_challenge()
	_clear_challenge_warning()
	pending_story_angle = -1.5708
	story_head_beat = -999.0
	story_tail_beat = -999.0
	story_event_i = 0
	active_story_event = {}
	for ev in normal_chart_events:
		ev["judged"] = false
		ev["missed"] = false
		ev["announced"] = false
	shake = 0.0
	flash = 0.0
	ring_pulse = 0.0
	btn_pop = 0.0
	prepare_beats()
	if arena:
		arena.challenge_type = CHALLENGE_NONE
		arena.challenge_active = false
	arena.warning_type = CHALLENGE_NONE
	arena.warning_active = false
	arena.warning_progress = 0.0
	arena.challenge_converge = 0.0
	arena.challenge_time_progress = 0.0
	arena.story_cfg = {}
	arena.story_visible = false
	arena.story_alpha = 0.0
	arena.story_u_head = 999.0
	arena.story_u_tail = 999.0


func _enter_start() -> void:
	_enter_intro()


func _begin_play() -> void:
	set_tiles_visible(true)
	set_feedback("一键应对！", COL_GREEN)


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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if phase == "intro" and event.pressed:
			_enter_countdown()
			return true
	return false


func _countdown_tick(last: bool) -> void:
	play_sfx(snd_pass if last else snd_count, -8.0)


func _advance(delta: float) -> void:
	_update_story_events()
	_update_chart_normal_notes()
	_layout_items()
	_update_challenge_warning(delta)
	_update_challenge(delta)
	_sync_story_bar()
	if chart_loaded and phase == "running" and _chart_clock() >= chart_duration_beats + 0.85 \
			and not warning_active and not challenge_active:
		_start_outro()
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
	if rent_music and rent_music.get("finale") == false:
		for q in queue:
			if q.get("end", false):
				rent_music.set("finale", true)
				break
	if current_beat_data.get("end", false):
		_start_outro()
		return
	var warning := int(current_beat_data.get("warning", CHALLENGE_NONE))
	if warning != CHALLENGE_NONE:
		_start_challenge_warning(warning, float(current_beat_data.get("angle", -1.5708)),
			current_beat_data.get("cfg", {}))
	var bridge := int(current_beat_data.get("challenge", CHALLENGE_NONE))
	if bridge != CHALLENGE_NONE:
		_start_challenge(bridge, current_beat_data.get("cfg", {}))


func _outro_fx() -> void:
	set_feedback("这个月稳住了～", COL_GOLD)
	flash = 1.0


func _verdict(hearts_lost: int, won: bool) -> Dictionary:
	if won:
		match hearts_lost:
			0:
				return {"rank": "房租的主人", "eval": "账单扇走，借钱挡住，钱包还会发光。"}
			1:
				return {"rank": "稳住钱包", "eval": "有点手忙脚乱，但这个月还是你赢。"}
			_:
				return {"rank": "勉强过关", "eval": "生活扑面而来，你还是把门顶住了。"}
	return {"rank": "余额告急", "eval": "压力没挡住，下次把扇子和钱包盾再练熟一点。"}


# ===========================================================================
# Beat generation
# ===========================================================================
func make_beat() -> Dictionary:
	if chart_loaded:
		return _rest_beat()
	if not active_chart_beats.is_empty():
		if chart_i >= active_chart_beats.size():
			return {"kind": -1, "action": ACTION_NONE, "should_press": false, "angle": 0.0, "end": true}
		var beat_data: Dictionary = active_chart_beats[chart_i]
		chart_i += 1
		return beat_data.duplicate(true)
	return {"kind": -1, "action": ACTION_NONE, "should_press": false, "angle": 0.0, "end": true}


func _next_story_angle() -> float:
	var angle := fposmod(float(spawn_count) * 2.3998277 - PI * 0.5, TAU)
	spawn_count += 1
	return angle


func ensure_queue() -> void:
	while queue.size() < 5:
		queue.append(make_beat())


func prepare_beats() -> void:
	queue = []
	chart_loaded = _chart_file_is_valid()
	if not chart_loaded:
		push_warning("Missing RhythmChart for 1-5; level has no script fallback chart.")
	chart_duration_beats = _load_chart_duration_beats()
	normal_chart_events = _load_normal_chart_events()
	story_events = _load_story_chart_events()
	normal_event_by_id = {}
	for ev in normal_chart_events:
		normal_event_by_id[str(ev.get("id", ""))] = ev
	var chart = _load_chart()
	if chart:
		judgement_runtime = JudgementRuntimeScript.new()
		judgement_runtime.setup(chart)
	else:
		judgement_runtime = null
	active_chart_beats = [] if chart_loaded else _load_editor_chart_beats()
	story_event_i = 0
	active_story_event = {}
	for ev in normal_chart_events:
		ev["judged"] = false
		ev["missed"] = false
		ev["announced"] = false
	chart_i = 0
	ensure_queue()
	current_beat_data = queue.pop_front()
	prev_beat_data = {}
	ensure_queue()


func _load_editor_chart_beats() -> Array:
	var chart = chart_for("1-5")
	if chart == null:
		chart_runtime = null
		return []
	chart_runtime = RhythmChartRuntimeScript.new()
	chart_runtime.setup(chart)
	return chart_slots_for(str(chart.meta.get("level_id", "1-5")), 1,
		Callable(self, "_chart_note_to_slot_entries"),
		_rest_slot(),
		{"kind": -1, "action": ACTION_NONE, "should_press": false, "angle": 0.0, "end": true})


func _load_chart() -> RhythmChart:
	return chart_for("1-5")


func _chart_file_is_valid() -> bool:
	return _load_chart() != null


func _load_chart_duration_beats() -> float:
	var chart = _load_chart()
	return chart.duration_beats() if chart else 0.0


func _load_normal_chart_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var chart = _load_chart()
	if chart == null:
		return events
	chart.sort_notes()
	for note in chart.notes:
		if _is_story_chart_note(note):
			continue
		var data := _chart_note_to_beat(note)
		if data.is_empty():
			continue
		data["id"] = str(note.get("id", ""))
		data["beat"] = maxf(0.0, float(note.get("beat", 0.0)))
		data["judge_type"] = str(note.get("judge_type", RhythmChartScript.JUDGE_TAP))
		data["lane"] = str(note.get("lane", RhythmChartScript.LANE_NODE))
		data["judged"] = false
		data["missed"] = false
		data["announced"] = false
		events.append(data)
	return events


func _load_story_chart_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var chart = _load_chart()
	if chart == null:
		return events
	chart.sort_notes()
	for note in chart.notes:
		if not _is_story_chart_note(note):
			continue
		var payload: Dictionary = note.get("payload", {})
		var head := maxf(0.0, float(note.get("beat", 0.0)))
		var active_beats := maxf(0.25, float(note.get("duration_beats", STORY_DEFAULT_BEATS)))
		var warn_beats := maxf(0.0, float(payload.get("warn_beats", STORY_DEFAULT_WARN_BEATS)))
		var cfg := _story_cfg_from_chart_note(note, warn_beats, active_beats)
		events.append({
			"id": str(note.get("id", "")),
			"kind": int(cfg.get("kind", CHALLENGE_BOSS)),
			"warn_start": maxf(0.0, head - warn_beats),
			"head": head,
			"tail": head + active_beats,
			"angle": _next_story_angle(),
			"cfg": cfg,
		})
	return events


func _rest_slot() -> Dictionary:
	var data := _rest_beat()
	data["_priority"] = 0
	return data


func _chart_note_to_slot_entries(note: Dictionary):
	if _is_story_chart_note(note):
		return {}
	var data := _chart_note_to_beat(note)
	if data.is_empty():
		return {}
	data["_priority"] = 2 if bool(data.get("should_press", false)) else 1
	return data


func _is_story_chart_note(note: Dictionary) -> bool:
	var judge := str(note.get("judge_type", RhythmChartScript.JUDGE_NONE))
	var kind_id := str(note.get("kind", ""))
	return (judge == RhythmChartScript.JUDGE_ROLL or judge == RhythmChartScript.JUDGE_HOLD) \
		and (kind_id == "boss" or kind_id == "landlord")


func _chart_note_to_beat(note: Dictionary) -> Dictionary:
	var kind_id := str(note.get("kind", "bill"))
	var k := _chart_kind_to_kind(kind_id)
	if k < 0:
		return {}
	var action: int = ACTION_NONE if str(note.get("judge_type", RhythmChartScript.JUDGE_NONE)) == RhythmChartScript.JUDGE_NONE else KIND_ACTION[k]
	var angle: float = fposmod(float(spawn_count) * 2.3998277 - PI * 0.5, TAU)
	spawn_count += 1
	return {"kind": k, "action": action, "should_press": action != ACTION_NONE, "angle": angle}


func _story_cfg_from_chart_note(note: Dictionary, warn_beats: float, active_beats: float) -> Dictionary:
	var judge := str(note.get("judge_type", RhythmChartScript.JUDGE_ROLL))
	var payload: Dictionary = note.get("payload", {})
	var is_boss: bool = judge == RhythmChartScript.JUDGE_ROLL
	return {
		"kind": CHALLENGE_BOSS if is_boss else CHALLENGE_LANDLORD,
		"warn_beats": float(warn_beats),
		"beats": float(active_beats),
		"need": float(payload.get("need", STORY_DEFAULT_TAPS)) if is_boss else float(payload.get("need_ms", STORY_DEFAULT_HOLD_MS)),
		"strip_len": float(payload.get("strip_len", STORY_DEFAULT_LEN)),
	}


func _chart_kind_to_kind(kind_id: String) -> int:
	match kind_id:
		"bill": return BILL
		"scam": return SCAM
		"loan": return LOAN
		"game": return GAME
		"girl", "heart": return GIRL
		_: return FOOD


func _rest_beat() -> Dictionary:
	return {"kind": -1, "action": ACTION_NONE, "should_press": false, "angle": 0.0}


# ===========================================================================
# Judging
# ===========================================================================
func _press_down() -> void:
	if phase != "running":
		return
	btn_pop = 1.0
	if challenge_active:
		_challenge_press_down()
		return
	if chart_loaded:
		_press_chart_normal()
		return
	if warning_active and _normal_judge_clock_overlaps_story(float(current_beat) + JUDGE_OFFSET):
		return

	var cur := current_beat_data
	var action := int(cur.get("action", ACTION_NONE))
	action_tool.pulse(action)
	play_sfx(snd_guard if action == ACTION_GUARD else snd_fan, -10.0)

	var d := _judge_delta()
	if d > good_window():
		return
	var k := int(cur.get("kind", -1))
	var result := beat_judgement.judge_press(current_beat,
		k >= 0 and action != ACTION_NONE,
		d, perfect_window(), good_window())
	var kind := str(result.get("result", ""))
	if kind == BeatSlotJudgementScript.RESULT_REPEAT:
		return

	if k < 0:
		return
	if kind == BeatSlotJudgementScript.RESULT_WRONG:
		apply_penalty("别碰%s！" % KIND_NAME[k])
	elif kind == BeatSlotJudgementScript.RESULT_PERFECT:
		_handle_item("Perfect", 120, cur)
	else:
		_handle_item("Good", 80, cur)


func _press_chart_normal() -> void:
	if judgement_runtime == null:
		return
	var clock := _chart_clock()
	var radius := good_window() / maxf(conductor.cycle_duration, 1.0)
	var best: Dictionary = judgement_runtime.closest_note(clock, radius,
		[RhythmChartScript.JUDGE_TAP, RhythmChartScript.JUDGE_NONE],
		Callable(self, "_normal_judgement_note_filter"))
	var ev: Dictionary = {}
	if not best.is_empty():
		var best_note: Dictionary = best.get("note", {})
		ev = normal_event_by_id.get(str(best_note.get("id", "")), {})
	action_tool.pulse(int(ev.get("action", ACTION_FAN)) if not ev.is_empty() else ACTION_FAN)
	play_sfx(snd_guard if int(ev.get("action", ACTION_FAN)) == ACTION_GUARD else snd_fan, -10.0)
	if ev.is_empty():
		return
	var hit_note: Dictionary = best["note"]
	judgement_runtime.mark_judged(hit_note)
	ev["judged"] = true
	var k := int(ev.get("kind", -1))
	if k < 0:
		return
	var action := int(ev.get("action", ACTION_NONE))
	if action == ACTION_NONE:
		apply_penalty("别碰%s！" % KIND_NAME[k])
		return
	var error_ms := float(best.get("error_beats", 0.0)) * conductor.cycle_duration
	if error_ms <= perfect_window():
		_handle_item("Perfect", 120, ev)
	else:
		_handle_item("Good", 80, ev)


func _press_up() -> void:
	if challenge_active and challenge_type == CHALLENGE_LANDLORD:
		challenge_hold_live = false


func _handle_item(kind: String, points: int, cur: Dictionary) -> void:
	var action := int(cur.get("action", ACTION_NONE))
	_add_score(points)
	_fever_hit()
	play_sfx(snd_guard if action == ACTION_GUARD else snd_fan)
	var verb := "格挡" if action == ACTION_GUARD else "扇走"
	set_feedback("%s %s" % [kind, verb], COL_GOLD if kind == "Perfect" else COL_GREEN)
	flash = maxf(flash, 0.75 if kind == "Perfect" else 0.45)
	hidden_beat = current_beat
	action_fx.emit(int(cur.get("kind", -1)), STRIKE, action, kind == "Perfect", float(cur.get("angle", 0.0)))


func _resolve_boundary() -> void:
	if phase != "running":
		return
	if chart_loaded:
		return
	var cur := current_beat_data
	if beat_judgement.was_judged(current_beat):
		return
	var k := int(cur.get("kind", -1))
	if k < 0:
		beat_judgement.mark_judged(current_beat)
		return
	if _normal_judge_clock_overlaps_story(float(current_beat) + JUDGE_OFFSET):
		beat_judgement.mark_judged(current_beat)
		return
	var action := int(cur.get("action", ACTION_NONE))
	var result := beat_judgement.resolve_slot(current_beat, action != ACTION_NONE)
	var kind := str(result.get("result", ""))
	if kind == BeatSlotJudgementScript.RESULT_REPEAT:
		return
	if kind == BeatSlotJudgementScript.RESULT_MISS:
		apply_penalty("%s没应对！" % KIND_NAME[k])
	else:
		_keep(k)


func _keep(k: int) -> void:
	_add_score(40)
	_fever_hit()
	play_sfx(snd_pass, -6.0)
	set_feedback("忍住了%s" % KIND_NAME[k], COL_GREEN)


func _judge_delta() -> float:
	return absf(conductor.beat_phase() - JUDGE_OFFSET) * conductor.cycle_duration


func perfect_window() -> float:
	return maxf(MIN_PERFECT_MS, conductor.cycle_duration * 0.13)


func good_window() -> float:
	return maxf(MIN_GOOD_MS, conductor.cycle_duration * 0.26)


func apply_penalty(text: String) -> void:
	play_sfx(snd_wrong)
	shake = maxf(shake, 10.0)
	super.apply_penalty(text)


# ===========================================================================
# Story challenges
# ===========================================================================
func _chart_clock() -> float:
	return float(current_beat) + (conductor.beat_phase() if conductor else 0.0)


func _update_story_events() -> void:
	if story_events.is_empty():
		return
	var clock := _chart_clock()
	if active_story_event.is_empty():
		while story_event_i < story_events.size() and clock >= float(story_events[story_event_i].get("tail", 0.0)) + 0.15:
			story_event_i += 1
		if story_event_i >= story_events.size():
			return
		var ev: Dictionary = story_events[story_event_i]
		var warn_start := float(ev.get("warn_start", 0.0))
		var head := float(ev.get("head", 0.0))
		var tail := float(ev.get("tail", head))
		if clock >= warn_start and clock < head:
			active_story_event = ev
			_start_challenge_warning(int(ev.get("kind", CHALLENGE_BOSS)),
				float(ev.get("angle", -1.5708)), ev.get("cfg", {}), head, tail)
		elif clock >= head and clock < tail:
			active_story_event = ev
			pending_story_angle = float(ev.get("angle", -1.5708))
			_start_challenge(int(ev.get("kind", CHALLENGE_BOSS)), ev.get("cfg", {}), head, tail)
		return
	var active_head := float(active_story_event.get("head", 0.0))
	var active_tail := float(active_story_event.get("tail", active_head))
	if warning_active and clock >= active_head:
		_clear_challenge_warning()
		pending_story_angle = float(active_story_event.get("angle", -1.5708))
		_start_challenge(int(active_story_event.get("kind", CHALLENGE_BOSS)),
			active_story_event.get("cfg", {}), active_head, active_tail)
	elif challenge_active and clock >= active_tail:
		_finish_challenge(challenge_satisfied)
	if clock >= active_tail + 0.15 and not warning_active and not challenge_active:
		active_story_event = {}
		story_event_i += 1


func _start_challenge_warning(kind: int, angle: float, cfg: Dictionary = {},
		head_beat := -999.0, tail_beat := -999.0) -> void:
	warning_active = true
	warning_type = kind
	warning_started_ms = now_ms()
	pending_story_cfg = cfg
	var warn_beats: float = float(cfg.get("warn_beats", CHALLENGE_WARN_BEATS))
	var active_beats: float = float(cfg.get("beats", BOSS_BEATS if kind == CHALLENGE_BOSS else LANDLORD_BEATS))
	warning_duration_ms = conductor.cycle_duration * warn_beats
	warning_angle = angle
	pending_story_angle = angle
	story_head_beat = head_beat if head_beat > -900.0 else _chart_clock() + warn_beats
	story_tail_beat = tail_beat if tail_beat > -900.0 else story_head_beat + active_beats
	arena.warning_active = true
	arena.warning_type = kind
	arena.warning_progress = 0.0
	arena.story_angle = angle
	arena.story_cfg = cfg
	arena.story_visible = true
	arena.story_u_head = story_head_beat - _chart_clock()
	arena.story_u_tail = story_tail_beat - _chart_clock()
	arena.role_sheet = role_sheet
	if kind == CHALLENGE_BOSS:
		set_feedback("上司靠近中...", COL_ORANGE)
	else:
		set_feedback("房东靠近中...", COL_ORANGE)
	play_sfx(snd_warn_stress, -12.0)


func _update_challenge_warning(_delta: float) -> void:
	if not warning_active:
		return
	var clock := _chart_clock()
	var warn_start := story_head_beat - float(pending_story_cfg.get("warn_beats", CHALLENGE_WARN_BEATS))
	var p := clampf((clock - warn_start) / maxf(story_head_beat - warn_start, 0.001), 0.0, 1.0)
	arena.warning_progress = p


func _clear_challenge_warning() -> void:
	warning_active = false
	warning_type = CHALLENGE_NONE
	warning_started_ms = 0.0
	warning_duration_ms = 0.0
	warning_angle = 0.0
	pending_story_cfg = {}
	if arena:
		arena.warning_active = false
		arena.warning_progress = 0.0


func _start_challenge(kind: int, cfg: Dictionary = {}, head_beat := -999.0, tail_beat := -999.0) -> void:
	if challenge_active:
		_finish_challenge(false)
	current_story_cfg = cfg if not cfg.is_empty() else pending_story_cfg
	warning_active = false
	warning_type = CHALLENGE_NONE
	challenge_active = true
	challenge_type = kind
	challenge_started_ms = now_ms()
	challenge_taps = 0
	challenge_hold_ms = 0.0
	challenge_hold_live = false
	challenge_done_this_press = false
	challenge_satisfied = false
	var beats: float = float(current_story_cfg.get("beats", BOSS_BEATS if kind == CHALLENGE_BOSS else LANDLORD_BEATS))
	if head_beat > -900.0:
		story_head_beat = head_beat
	if tail_beat > -900.0:
		story_tail_beat = tail_beat
	challenge_duration_ms = conductor.cycle_duration * beats
	arena.challenge_active = true
	arena.warning_active = false
	arena.challenge_type = kind
	arena.challenge_progress = 0.0
	arena.challenge_converge = 0.0
	arena.challenge_time_progress = 0.0
	arena.story_angle = pending_story_angle
	arena.story_cfg = current_story_cfg
	arena.role_sheet = role_sheet
	arena.boss_tex = boss_tex
	action_tool.pulse(ACTION_NONE)
	if kind == CHALLENGE_BOSS:
		set_feedback("上司来了：连点确认！", COL_ORANGE)
	else:
		set_feedback("房东来了：按住别松！", COL_ORANGE)
	play_sfx(snd_warn_stress, -8.0)


func _sync_story_bar() -> void:
	if not arena:
		return
	if not (warning_active or challenge_active):
		arena.story_visible = false
		return
	var clock := _chart_clock()
	arena.story_visible = true
	arena.story_u_head = story_head_beat - clock
	arena.story_u_tail = story_tail_beat - clock


func _challenge_press_down() -> void:
	if challenge_type == CHALLENGE_BOSS:
		challenge_taps += 1
		var need_taps := int(current_story_cfg.get("need", BOSS_TAPS))
		arena.challenge_progress = clampf(float(challenge_taps) / float(maxi(need_taps, 1)), 0.0, 1.0)
		action_tool.pulse(ACTION_FAN)
		play_sfx(snd_tap, -9.0)
		if challenge_taps >= need_taps:
			challenge_satisfied = true
	elif challenge_type == CHALLENGE_LANDLORD:
		challenge_hold_live = true
		challenge_done_this_press = false
		action_tool.pulse(ACTION_GUARD)
		play_sfx(snd_hold, -10.0)


func _update_challenge(delta: float) -> void:
	if not challenge_active:
		return
	var clock := _chart_clock()
	var beat_span := maxf(story_tail_beat - story_head_beat, 0.001)
	var elapsed_beats := maxf(0.0, clock - story_head_beat)
	var elapsed_ms := elapsed_beats * conductor.cycle_duration
	arena.challenge_converge = clampf(elapsed_ms / CHALLENGE_CONVERGE_MS, 0.0, 1.0)
	arena.challenge_time_progress = clampf(elapsed_beats / beat_span, 0.0, 1.0)
	if challenge_type == CHALLENGE_LANDLORD and challenge_hold_live:
		challenge_hold_ms += delta * 1000.0
		var need_hold := float(current_story_cfg.get("need", LANDLORD_HOLD_MS))
		arena.challenge_progress = clampf(challenge_hold_ms / maxf(need_hold, 1.0), 0.0, 1.0)
		if challenge_hold_ms >= need_hold and not challenge_done_this_press:
			challenge_done_this_press = true
			challenge_satisfied = true
	elif challenge_type == CHALLENGE_BOSS:
		var need_taps := int(current_story_cfg.get("need", BOSS_TAPS))
		arena.challenge_progress = clampf(float(challenge_taps) / float(maxi(need_taps, 1)), 0.0, 1.0)
	if clock >= story_tail_beat:
		_finish_challenge(challenge_satisfied)


func _finish_challenge(success: bool) -> void:
	if not challenge_active:
		return
	var kind := challenge_type
	_clear_challenge()
	arena.challenge_active = false
	arena.challenge_progress = 0.0
	arena.challenge_converge = 0.0
	arena.challenge_time_progress = 0.0
	arena.story_cfg = {}
	arena.story_visible = false
	arena.role_linger = 1.0
	if success:
		_add_score(240 if kind == CHALLENGE_BOSS else 280)
		_fever_hit()
		play_sfx(snd_pass)
		flash = maxf(flash, 0.7)
		set_feedback("连点过关！" if kind == CHALLENGE_BOSS else "稳稳挡住！", COL_GOLD)
	else:
		apply_penalty("上司追问没接住！" if kind == CHALLENGE_BOSS else "房东催租没顶住！")


func _clear_challenge() -> void:
	challenge_active = false
	challenge_type = CHALLENGE_NONE
	challenge_started_ms = 0.0
	challenge_duration_ms = 0.0
	current_story_cfg = {}
	story_head_beat = -999.0
	story_tail_beat = -999.0
	challenge_taps = 0
	challenge_hold_ms = 0.0
	challenge_hold_live = false
	challenge_done_this_press = false
	challenge_satisfied = false


# ===========================================================================
# Layout
# ===========================================================================
func _update_chart_normal_notes() -> void:
	if not chart_loaded or phase != "running" or judgement_runtime == null:
		return
	var clock := _chart_clock()
	var miss_lag_beats := good_window() / maxf(conductor.cycle_duration, 1.0)
	for note in judgement_runtime.sweep_past(clock, miss_lag_beats,
			[RhythmChartScript.JUDGE_TAP, RhythmChartScript.JUDGE_NONE],
			Callable(self, "_normal_judgement_note_filter")):
		var ev: Dictionary = normal_event_by_id.get(str(note.get("id", "")), {})
		if ev.is_empty():
			continue
		ev["missed"] = true
		var k := int(ev.get("kind", -1))
		if k < 0:
			continue
		if int(ev.get("action", ACTION_NONE)) != ACTION_NONE:
			apply_penalty("%s没应对！" % KIND_NAME[k])
		else:
			_keep(k)


func _normal_judgement_note_filter(note: Dictionary) -> bool:
	var note_id := str(note.get("id", ""))
	if not normal_event_by_id.has(note_id):
		return false
	return not _normal_judge_clock_overlaps_story(float(note.get("beat", 0.0)))


func _layout_items() -> void:
	if chart_loaded:
		_layout_chart_normal_items()
		return
	var bp := conductor.beat_phase()
	for slot in NOTE_SLOTS:
		var k := slot - 1
		var note := _note_at(k)
		var tile: _Item = item_tiles[slot]
		if note.is_empty() or note.get("end", false) or int(note.get("kind", -1)) < 0:
			tile.visible = false
			continue
		var judge_clock := float(current_beat + k) + JUDGE_OFFSET
		if _normal_judge_clock_overlaps_story(judge_clock):
			tile.visible = false
			continue
		var action := int(note.get("action", ACTION_NONE))
		var tv := TRAVEL_TREAT if action == ACTION_NONE else TRAVEL_STRESS
		var u := float(k) + JUDGE_OFFSET - bp
		if u > tv + 0.2 or u < -0.8:
			tile.visible = false
			continue
		if k == 0 and hidden_beat == current_beat:
			tile.visible = false
			continue
		if not bool(note.get("announced", false)):
			note["announced"] = true
			play_sfx(snd_warn_treat if action == ACTION_NONE else snd_warn_stress, -13.0)
		tile.visible = true
		tile.set_kind(int(note.get("kind", -1)))
		tile.action = action
		var pos := _path_pos(note, u)
		tile.position = pos - tile.size * 0.5
		var near := clampf(1.0 - absf(u), 0.0, 1.0)
		tile.scale = Vector2.ONE * (0.84 + 0.25 * near)


func _layout_chart_normal_items() -> void:
	var clock := _chart_clock()
	var visible_events: Array[Dictionary] = []
	for ev in normal_chart_events:
		if bool(ev.get("judged", false)) or bool(ev.get("missed", false)):
			continue
		var beat := float(ev.get("beat", 0.0))
		if _normal_judge_clock_overlaps_story(beat):
			continue
		var action := int(ev.get("action", ACTION_NONE))
		var tv := TRAVEL_TREAT if action == ACTION_NONE else TRAVEL_STRESS
		var u := beat - clock
		if u <= tv + 0.2 and u >= -0.8:
			visible_events.append(ev)
	visible_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("beat", 0.0)) < float(b.get("beat", 0.0)))
	for i in item_tiles.size():
		var tile: _Item = item_tiles[i]
		if i >= visible_events.size():
			tile.visible = false
			continue
		var ev: Dictionary = visible_events[i]
		var action := int(ev.get("action", ACTION_NONE))
		if not bool(ev.get("announced", false)):
			ev["announced"] = true
			play_sfx(snd_warn_treat if action == ACTION_NONE else snd_warn_stress, -13.0)
		var u := float(ev.get("beat", 0.0)) - clock
		tile.visible = true
		tile.set_kind(int(ev.get("kind", -1)))
		tile.action = action
		var pos := _path_pos(ev, u)
		tile.position = pos - tile.size * 0.5
		var near := clampf(1.0 - absf(u), 0.0, 1.0)
		tile.scale = Vector2.ONE * (0.84 + 0.25 * near)


func _normal_judge_clock_overlaps_story(judge_clock: float) -> bool:
	if not (warning_active or challenge_active):
		return false
	if story_tail_beat <= story_head_beat:
		return false
	return judge_clock >= story_head_beat and judge_clock < story_tail_beat


func _note_at(k: int) -> Dictionary:
	if k == -1:
		return prev_beat_data
	if k == 0:
		return current_beat_data
	if k >= 1 and k - 1 < queue.size():
		return queue[k - 1]
	return {}


func _path_pos(note: Dictionary, u: float) -> Vector2:
	var action := int(note.get("action", ACTION_NONE))
	var ang := float(note.get("angle", 0.0))
	var tv := TRAVEL_TREAT if action == ACTION_NONE else TRAVEL_STRESS
	var tval := clampf(1.0 - u / tv, 0.0, 1.35)
	var spawn := STRIKE + Vector2(cos(ang), sin(ang)) * R_SPAWN
	if action != ACTION_NONE:
		return spawn.lerp(STRIKE, tval)
	var mid := spawn.lerp(STRIKE, 0.5)
	var ctrl := mid + Vector2(-sin(ang), cos(ang)) * 190.0
	var p := _bezier(spawn, ctrl, STRIKE, tval)
	p += Vector2(sin(tval * TAU * 1.5 + ang) * 11.0, cos(tval * TAU * 1.2) * 9.0) * (1.0 - tval)
	return p


func _bezier(a: Vector2, b: Vector2, c: Vector2, tval: float) -> Vector2:
	var it := 1.0 - tval
	return a * (it * it) + b * (2.0 * it * tval) + c * (tval * tval)


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
	arena.role_sheet = role_sheet
	arena.boss_tex = boss_tex
	add_child(arena)

	stage = Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.pivot_offset = Vector2(640, 360)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

	judge_ring = _JudgeRing.new()
	judge_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	judge_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	judge_ring.center = STRIKE
	stage.add_child(judge_ring)


func _build_items() -> void:
	for i in NOTE_SLOTS:
		var tile := _Item.new()
		tile.size = Vector2(92, 100)
		tile.pivot_offset = Vector2(46, 50)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.visible = false
		stage.add_child(tile)
		item_tiles.append(tile)

	action_fx = _ActionFx.new()
	action_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	action_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(action_fx)


func _build_action_tool() -> void:
	action_tool = _ActionTool.new()
	action_tool.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	action_tool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_tool.strike = STRIKE
	stage.add_child(action_tool)


func _build_button() -> void:
	hit_button = Button.new()
	hit_button.text = "应对一下"
	hit_button.custom_minimum_size = Vector2(220, 80)
	hit_button.add_theme_font_size_override("font_size", 30)
	hit_button.focus_mode = Control.FOCUS_NONE
	hit_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := StyleBoxFlat.new()
	normal.bg_color = COL_CREAM
	normal.set_border_width_all(4)
	normal.border_color = COL_GOLD
	normal.set_corner_radius_all(12)
	hit_button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color("fff9df")
	hit_button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = Color("ffe19a")
	hit_button.add_theme_stylebox_override("pressed", pressed)
	for s in ["font_color", "font_hover_color"]:
		hit_button.add_theme_color_override(s, COL_INK)
	hit_button.add_theme_color_override("font_pressed_color", Color("5d3d1d"))
	hit_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hit_button.position = Vector2(-110, -92)
	hit_button.pivot_offset = Vector2(110, 40)
	hit_button.button_down.connect(_button_down)
	hit_button.button_up.connect(_button_up)
	add_child(hit_button)


func _button_down() -> void:
	key_held = true
	if phase == "intro":
		_enter_countdown()
	else:
		_press_down()


func _button_up() -> void:
	key_held = false
	_press_up()


func _build_intro() -> void:
	intro_layer = ColorRect.new()
	intro_layer.color = Color(0, 0, 0, 0.42)
	intro_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro_layer.z_index = 5
	intro_layer.visible = false
	add_child(intro_layer)

	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("fff8dc")
	sb.set_border_width_all(4)
	sb.border_color = COL_GOLD
	sb.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(760, 250)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.position = Vector2(-380, -125)
	intro_layer.add_child(card)

	intro_label = Label.new()
	intro_label.add_theme_font_size_override("font_size", 25)
	intro_label.add_theme_color_override("font_color", COL_INK)
	intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	intro_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro_label.offset_left = 36
	intro_label.offset_right = -36
	card.add_child(intro_label)

	var hint := Label.new()
	hint.text = "空格 / 点击 开始"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", COL_CREAM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -34
	intro_layer.add_child(hint)


# ===========================================================================
# Intro
# ===========================================================================
func _enter_intro() -> void:
	phase = "intro"
	intro_label.text = "月底到了，压力从四面八方飞来。\n账单和诈骗电话：按键扇走。\n朋友借钱：按键格挡。\n美食、游戏和心动：忍住别按。\n上司剧情要连点，房东剧情要长按。"
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
	judge_ring.pulse = p
	action_tool.advance(delta)

	hit_button.scale = Vector2.ONE * (1.0 + 0.14 * btn_pop)
	hit_button.modulate = Color.WHITE.lerp(Color("ffe19a"), btn_pop * 0.65)


# ===========================================================================
# Inner visual classes
# ===========================================================================
class _Item:
	extends Control

	var kind := -1
	var action := ACTION_NONE
	var t := 0.0

	const ACC := [
		Color("df5a4f"), Color("ef8a3c"), Color("e8bd42"),
		Color("f19a4a"), Color("58bfe8"), Color("ec6f9c"),
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
		var stress := action != ACTION_NONE
		var off := Vector2(sin(t * 42.0), cos(t * 48.0)) * 1.5 if stress else Vector2(sin(t * 3.0), 0.0) * 2.2
		draw_set_transform(off, 0.0, Vector2.ONE)
		var w := size.x
		var h := size.y
		var acc: Color = ACC[kind]
		draw_rect(Rect2(4, 4, w - 8, h - 8), Color("fff8e8"))
		draw_rect(Rect2(4, 4, w - 8, h - 8), Color("42645a"), false, 3.0)
		draw_rect(Rect2(4, 4, w - 8, 16), acc)
		match kind:
			BILL:
				_draw_bill(acc)
			SCAM:
				_draw_phone(acc)
			LOAN:
				_draw_friend(acc)
			FOOD:
				_draw_food(acc)
			GAME:
				_draw_game(acc)
			GIRL:
				_draw_heart(acc)

	func _draw_bill(acc: Color) -> void:
		for i in 3:
			draw_line(Vector2(22, 38 + i * 13), Vector2(70, 38 + i * 13), Color("9fb8ab"), 3.0)
		draw_circle(Vector2(66, 70), 10, acc)
		draw_string(ThemeDB.fallback_font, Vector2(61, 75), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)

	func _draw_phone(acc: Color) -> void:
		draw_rect(Rect2(31, 30, 30, 52), Color("f4fbf8"))
		draw_rect(Rect2(31, 30, 30, 52), Color("42645a"), false, 3.0)
		draw_circle(Vector2(46, 72), 3, acc)
		draw_arc(Vector2(46, 52), 22, -0.8, 0.8, 18, acc, 4.0)
		draw_arc(Vector2(46, 52), 31, -0.8, 0.8, 18, Color(acc.r, acc.g, acc.b, 0.45), 3.0)

	func _draw_friend(acc: Color) -> void:
		draw_circle(Vector2(46, 42), 15, Color("ffe2bd"))
		draw_circle(Vector2(38, 40), 3, Color("33443e"))
		draw_circle(Vector2(54, 40), 3, Color("33443e"))
		draw_arc(Vector2(46, 50), 8, 0.2, PI - 0.2, 12, Color("33443e"), 2.0)
		draw_rect(Rect2(25, 62, 42, 20), acc)
		draw_rect(Rect2(57, 57, 18, 12), Color("fff2aa"))
		draw_string(ThemeDB.fallback_font, Vector2(61, 68), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("8a6b1b"))

	func _draw_food(acc: Color) -> void:
		draw_arc(Vector2(46, 60), 27, 0, PI, 28, Color("8d5c32"), 9.0)
		draw_arc(Vector2(46, 58), 24, 0, PI, 28, Color("fff0cc"), 10.0)
		draw_line(Vector2(30, 45), Vector2(70, 31), Color("8d5c32"), 3.0)
		draw_line(Vector2(30, 50), Vector2(72, 39), Color("8d5c32"), 3.0)
		draw_circle(Vector2(42, 54), 4, acc)

	func _draw_game(acc: Color) -> void:
		draw_rect(Rect2(23, 40, 46, 32), Color("eef7ff"))
		draw_rect(Rect2(23, 40, 46, 32), Color("42645a"), false, 3.0)
		draw_rect(Rect2(31, 48, 16, 10), acc)
		draw_circle(Vector2(57, 54), 4, Color("ffcf4d"))
		draw_circle(Vector2(65, 62), 4, Color("ec6f9c"))

	func _draw_heart(acc: Color) -> void:
		draw_circle(Vector2(39, 45), 12, acc)
		draw_circle(Vector2(53, 45), 12, acc)
		draw_colored_polygon(PackedVector2Array([Vector2(28, 49), Vector2(64, 49), Vector2(46, 77)]), acc)
		draw_circle(Vector2(42, 43), 3, Color.WHITE)


class _ActionTool:
	extends Control

	var strike := Vector2(640, 338)
	var action := ACTION_NONE
	var burst := 0.0
	var t := 0.0

	func pulse(a: int) -> void:
		action = a
		burst = 1.0
		queue_redraw()

	func advance(delta: float) -> void:
		t += delta
		if burst > 0.0:
			burst = move_toward(burst, 0.0, delta * 4.2)
			queue_redraw()

	func _draw() -> void:
		var base := Vector2(strike.x, 632.0)
		draw_circle(base, 64.0, Color(1.0, 0.85, 0.35, 0.12))
		if action == ACTION_GUARD:
			_draw_guard(base)
		else:
			_draw_fan(base)
		if burst > 0.0:
			var a := burst
			if action == ACTION_GUARD:
				draw_arc(strike, 74.0 + 18.0 * a, -PI * 0.9, -PI * 0.1, 30, Color(0.35, 0.75, 0.9, a), 8.0)
				draw_arc(strike, 50.0 + 10.0 * a, -PI * 0.9, -PI * 0.1, 30, Color(1, 1, 1, a), 3.0)
			else:
				for i in 4:
					var ang := -PI * 0.82 + i * 0.34
					var p1 := strike + Vector2(cos(ang), sin(ang)) * (44 + i * 8)
					var p2 := p1 + Vector2(cos(ang), sin(ang)) * (170.0 * a)
					draw_line(p1, p2, Color(1.0, 1.0, 1.0, 0.75 * a), 5.0)
					draw_line(p1, p2, Color(0.45, 0.9, 0.75, 0.45 * a), 11.0)

	func _draw_fan(base: Vector2) -> void:
		var fan := PackedVector2Array([
			base + Vector2(-54, 8),
			base + Vector2(-22, -58),
			base + Vector2(38, -48),
			base + Vector2(58, 20),
			base + Vector2(4, 42),
		])
		draw_colored_polygon(fan, Color("fff1bd"))
		draw_polyline(fan + PackedVector2Array([fan[0]]), Color("b7822c"), 4.0)
		for i in 5:
			var a := -2.25 + i * 0.33
			draw_line(base + Vector2(-30, 18), base + Vector2(cos(a), sin(a)) * 62.0, Color("e2bd67"), 2.0)
		draw_line(base + Vector2(-30, 18), base + Vector2(-72, 72), Color("8b5c2d"), 11.0)
		draw_line(base + Vector2(-30, 18), base + Vector2(-72, 72), Color("b98544"), 5.0)

	func _draw_guard(base: Vector2) -> void:
		draw_circle(base + Vector2(0, -16), 48.0, Color("bdebd8"))
		draw_circle(base + Vector2(0, -16), 48.0, Color("42645a"), false, 4.0)
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-24, -34), base + Vector2(24, -34),
			base + Vector2(20, -5), base + Vector2(0, 20), base + Vector2(-20, -5),
		]), Color("fff2b0"))
		draw_polyline(PackedVector2Array([
			base + Vector2(-24, -34), base + Vector2(24, -34),
			base + Vector2(20, -5), base + Vector2(0, 20), base + Vector2(-20, -5),
			base + Vector2(-24, -34),
		]), Color("d59d32"), 3.0)


class _JudgeRing:
	extends Control

	var center := Vector2(640, 338)
	var pulse := 0.0

	func _draw() -> void:
		var r := 44.0 + pulse * 7.0
		var a := 0.36 + 0.35 * pulse
		draw_arc(center, r, 0, TAU, 44, Color(1.0, 0.78, 0.24, a), 3.0)
		draw_arc(center, r - 8.0, 0, TAU, 44, Color(0.29, 0.72, 0.47, a * 0.65), 2.0)
		draw_line(center + Vector2(-10, 0), center + Vector2(10, 0), Color(1, 1, 1, a), 2.0)
		draw_line(center + Vector2(0, -10), center + Vector2(0, 10), Color(1, 1, 1, a), 2.0)


class _ActionFx:
	extends Control

	var parts: Array = []

	const ACC := [
		Color("df5a4f"), Color("ef8a3c"), Color("e8bd42"),
		Color("f19a4a"), Color("58bfe8"), Color("ec6f9c"),
	]

	func emit(kind: int, at: Vector2, action: int, perfect: bool, angle: float) -> void:
		var col: Color = ACC[kind] if kind >= 0 else Color.WHITE
		var power := 360.0 if perfect else 270.0
		var axis := Vector2(cos(angle), sin(angle))
		if action == ACTION_GUARD:
			parts.append({"pos": at, "vel": -axis * power, "life": 0.55, "max": 0.55, "col": Color("58bfe8"), "guard": true})
			parts.append({"pos": at, "vel": axis * 120.0 + Vector2(0, -80), "life": 0.7, "max": 0.7, "col": col})
		else:
			for i in 5:
				var spread := Vector2(-sin(angle), cos(angle)).rotated(randf_range(-0.45, 0.45))
				parts.append({"pos": at, "vel": spread * randf_range(160.0, power) - axis * 110.0, "life": 0.65, "max": 0.65, "col": col})
		queue_redraw()

	func _process(delta: float) -> void:
		if parts.is_empty():
			return
		var alive: Array = []
		for p in parts:
			p["life"] -= delta
			if p["life"] <= 0.0:
				continue
			p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * delta
			if not p.get("guard", false):
				p["vel"] = Vector2(p["vel"]) + Vector2(0, 420.0) * delta
			alive.append(p)
		parts = alive
		queue_redraw()

	func _draw() -> void:
		for p in parts:
			var a: float = clampf(p["life"] / p["max"], 0.0, 1.0)
			var pos: Vector2 = p["pos"]
			var c: Color = p["col"]
			if p.get("guard", false):
				draw_arc(pos, 58.0 * a + 22.0, -PI * 0.85, -PI * 0.15, 28, Color(c.r, c.g, c.b, a), 7.0)
				draw_arc(pos, 40.0 * a + 16.0, -PI * 0.85, -PI * 0.15, 28, Color(1, 1, 1, a), 2.0)
			else:
				draw_circle(pos, 9.0 + 8.0 * a, Color(c.r, c.g, c.b, a * 0.85))
				draw_circle(pos + Vector2(4, -4), 3.0, Color(1, 1, 1, a))


class _Arena:
	extends Control

	var pulse := 0.0
	var flash := 0.0
	var t := 0.0
	var papers: Array = []
	var role_sheet: Texture2D
	var boss_tex: Texture2D
	var challenge_active := false
	var challenge_type := CHALLENGE_NONE
	var challenge_progress := 0.0
	var challenge_converge := 0.0
	var challenge_time_progress := 0.0
	var warning_active := false
	var warning_type := CHALLENGE_NONE
	var warning_progress := 0.0
	var story_angle := -1.5708
	var story_cfg: Dictionary = {}
	var story_visible := false
	var story_alpha := 0.0
	var story_u_head := 999.0
	var story_u_tail := 999.0
	var role_linger := 0.0

	func _ready() -> void:
		for i in 16:
			papers.append({
				"x": randf_range(0, 1280),
				"y": randf_range(0, 720),
				"spd": randf_range(16, 48),
				"sway": randf() * TAU,
				"size": randf_range(9, 22),
			})

	func _process(delta: float) -> void:
		t += delta
		role_linger = move_toward(role_linger, 0.0, delta * 0.8)
		story_alpha = move_toward(story_alpha, 1.0 if story_visible else 0.0, delta * 5.5)
		queue_redraw()

	func _draw() -> void:
		var w := 1280.0
		var h := 720.0
		for i in 14:
			var frac := float(i) / 13.0
			draw_rect(Rect2(0, i * h / 14.0, w, h / 14.0 + 1), COL_BG_TOP.lerp(COL_BG_BOT, frac))
		_draw_grid(w, h)
		_draw_room(w, h)
		_draw_floaters(h)
		draw_circle(Vector2(640, 338), 126.0, Color(1.0, 0.85, 0.35, 0.04 + flash * 0.11))
		_draw_role()
		if story_visible or story_alpha > 0.01:
			_draw_judgement_strip()
		if flash > 0.0:
			draw_rect(Rect2(0, 0, w, h), Color(1.0, 0.93, 0.55, flash * 0.10))

	func _draw_grid(w: float, h: float) -> void:
		for x in range(0, int(w) + 1, 72):
			draw_line(Vector2(x, 0), Vector2(x, h), Color(1, 1, 1, 0.32), 2.0)
			draw_line(Vector2(x + 2, 0), Vector2(x + 2, h), Color(0.3, 0.7, 0.58, 0.10), 1.0)
		for y in range(0, int(h) + 1, 72):
			draw_line(Vector2(0, y), Vector2(w, y), Color(1, 1, 1, 0.32), 2.0)
			draw_line(Vector2(0, y + 2), Vector2(w, y + 2), Color(0.3, 0.7, 0.58, 0.10), 1.0)

	func _draw_room(w: float, h: float) -> void:
		draw_rect(Rect2(0, h - 112, w, 112), Color("a5d9b8"))
		draw_rect(Rect2(0, h - 104, w, 104), Color("76bd92"))
		for i in 9:
			var x := i * 160.0 - 30.0
			draw_circle(Vector2(x, h - 62), 66.0, Color("4ea86e"))
			draw_circle(Vector2(x + 62, h - 46), 52.0, Color("3b915d"))
		draw_rect(Rect2(0, h - 16, w, 16), Color("3f7355"))

	func _draw_floaters(h: float) -> void:
		for pp in papers:
			var px: float = pp["x"] + sin(t * 0.7 + pp["sway"]) * 22.0
			var py: float = fposmod(pp["y"] + t * pp["spd"], h + 40.0)
			var sz: float = pp["size"]
			draw_rect(Rect2(px, py, sz, sz * 1.28), Color(1.0, 0.96, 0.72, 0.16))
			draw_line(Vector2(px + 3, py + 5), Vector2(px + sz - 3, py + 5), Color(0.45, 0.65, 0.55, 0.16), 1.0)

	func _draw_role() -> void:
		var active_a := 1.0 if challenge_active else (0.72 if warning_active else role_linger)
		if active_a <= 0.01:
			return
		var kind := _visible_story_kind()
		if kind == CHALLENGE_BOSS:
			var p := clampf(warning_progress, 0.0, 1.0)
			var x := lerpf(-250.0, 326.0, 1.0 - pow(1.0 - p, 3.0)) if warning_active and not challenge_active else 326.0
			var dst := Rect2(Vector2(x, 88), Vector2(372, 486))
			if boss_tex:
				draw_texture_rect(boss_tex, dst, false, Color(1, 1, 1, active_a))
			else:
				_draw_sheet_role(0, dst, active_a)
			return
		var lp := clampf(warning_progress, 0.0, 1.0)
		var lx := lerpf(1300.0, 890.0, 1.0 - pow(1.0 - lp, 3.0)) if warning_active and not challenge_active else 890.0
		_draw_sheet_role(1, Rect2(Vector2(lx, 128), Vector2(300, 300)), active_a)

	func _draw_sheet_role(idx: int, dst: Rect2, active_a: float) -> void:
		if role_sheet:
			var cols := 2
			var rows := 2
			var cell := Vector2(role_sheet.get_width() / cols, role_sheet.get_height() / rows)
			var src := Rect2(Vector2((idx % cols) * cell.x, int(idx / cols) * cell.y), cell)
			draw_texture_rect_region(role_sheet, dst, src, Color(1, 1, 1, active_a))
		else:
			draw_circle(dst.get_center(), 84, Color("fff2bd", active_a))
			draw_circle(dst.get_center() + Vector2(0, -24), 44, Color("ffe0bd", active_a))

	func _draw_judgement_strip() -> void:
		var kind := _visible_story_kind()
		if not challenge_active:
			var pulse_a := 0.07 + 0.05 * absf(sin(t * 10.0))
			draw_rect(Rect2(0, 0, 1280, 720), Color(1.0, 0.74, 0.20, pulse_a * (1.0 - warning_progress * 0.35) * story_alpha))
		if story_u_tail < -0.75 or story_u_head > TRAVEL_STRESS + 0.65:
			return
		var strip := _story_strip_points_from_beat_u(maxf(0.0, story_u_head), maxf(0.0, story_u_tail))
		_draw_story_ribbon(strip, (1.0 if challenge_active else 0.78) * story_alpha)
		if challenge_active:
			if kind == CHALLENGE_BOSS:
				_draw_tap_progress(challenge_progress, story_alpha)
			else:
				_draw_hold_fill(strip, challenge_progress, story_alpha)
		else:
			_draw_warning_marker(Vector2(strip[0]), kind, story_alpha)
		draw_arc(Vector2(640, 338), 48.0 + 5.0 * pulse, 0, TAU, 38, Color(1.0, 0.86, 0.03, 0.55 * story_alpha), 3.0)

	func _visible_story_kind() -> int:
		return challenge_type if challenge_active else warning_type

	func _story_point_from_beat_u(beat_u: float) -> Vector2:
		var target := STRIKE
		var dir := Vector2(cos(story_angle), sin(story_angle))
		if dir.length() < 0.01:
			dir = Vector2(1, -0.25).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var curve := 170.0 if _visible_story_kind() == CHALLENGE_BOSS else -170.0
		var spawn := target + dir * 900.0
		var c1 := target + dir * 210.0 + perp * curve
		var c2 := target + dir * 610.0 + perp * curve * 0.72
		var ratio := beat_u / TRAVEL_STRESS
		if ratio > 1.0:
			return spawn + dir * R_SPAWN * (ratio - 1.0)
		return _cubic(spawn, c2, c1, target, clampf(1.0 - ratio, 0.0, 1.0))

	func _story_strip_points_from_beat_u(head_u: float, tail_u: float) -> Array:
		var out := []
		var a := minf(head_u, tail_u)
		var b := maxf(head_u, tail_u)
		for i in 14:
			var f := float(i) / 13.0
			out.append(_story_point_from_beat_u(lerpf(a, b, f)))
		return out

	func _cubic(a: Vector2, b: Vector2, c: Vector2, d: Vector2, u: float) -> Vector2:
		var it := 1.0 - u
		return a * it * it * it + b * 3.0 * it * it * u + c * 3.0 * it * u * u + d * u * u * u

	func _draw_story_ribbon(points: Array, active_a: float) -> void:
		if points.size() < 2:
			return
		var curve := PackedVector2Array()
		for p in points:
			curve.append(p)
		draw_polyline(curve, Color(0.78, 0.48, 0.05, active_a * 0.42), 34.0)
		draw_polyline(curve, Color(1.0, 0.86, 0.03, active_a), 25.0)
		draw_polyline(curve, Color(1.0, 0.97, 0.70, active_a), 15.0)
		draw_polyline(curve, Color(1.0, 0.86, 0.03, active_a), 4.0)
		for i in range(2, points.size() - 2, 3):
			var p0: Vector2 = points[i]
			var p1: Vector2 = points[i + 1]
			draw_line(p0, p1, Color(0.54, 0.62, 0.42, active_a * 0.65), 3.0)
		_draw_strip_end(Vector2(points[0]), active_a, true)
		_draw_strip_end(Vector2(points[points.size() - 1]), active_a, false)

	func _draw_tap_progress(progress: float, alpha := 1.0) -> void:
		var p := clampf(progress, 0.0, 1.0)
		var col := Color("ffcf4d").lerp(Color("fff7b0"), 0.35 + p * 0.45)
		col.a *= alpha
		draw_arc(STRIKE, 62.0, -PI * 0.5, -PI * 0.5 + TAU * p, 40, col, 7.0)
		draw_arc(STRIKE, 71.0 + 4.0 * absf(sin(t * 9.0)), 0, TAU, 40, Color(1, 1, 1, (0.28 + p * 0.18) * alpha), 3.0)

	func _draw_hold_fill(points: Array, progress: float, alpha := 1.0) -> void:
		var fill_path := []
		var end_i := clampi(ceili(float(points.size() - 1) * clampf(progress, 0.0, 1.0)), 1, points.size() - 1)
		for i in end_i + 1:
			fill_path.append(points[i])
		var fill := PackedVector2Array()
		for p in fill_path:
			fill.append(p)
		if fill.size() >= 2:
			draw_polyline(fill, Color("58bfe8", 0.50 * alpha), 19.0)
			draw_polyline(fill, Color("fff7a8", 0.72 * alpha), 8.0)
		draw_arc(STRIKE, 62.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(progress, 0.0, 1.0), 40, Color("58bfe8", alpha), 7.0)

	func _draw_warning_marker(pos: Vector2, kind: int, alpha := 1.0) -> void:
		var col := Color("ffcf4d") if kind == CHALLENGE_BOSS else Color("58bfe8")
		draw_circle(pos, 30.0, Color("e5483f", 0.95 * alpha))
		col.a *= alpha
		draw_circle(pos, 22.0, col)
		draw_circle(pos + Vector2(-5, -6), 7.0, Color(1, 1, 1, 0.56 * alpha))
		draw_arc(pos, 34.0 + 7.0 * absf(sin(t * 8.0)), 0, TAU, 26, Color(1, 1, 1, 0.55 * alpha), 3.0)

	func _draw_strip_end(pos: Vector2, alpha: float, head: bool) -> void:
		var col := Color("ffcf4d") if head else Color("fff7b0")
		draw_circle(pos, 28.0, Color("e5483f", 0.95 * alpha))
		draw_circle(pos, 21.0, col)
		draw_circle(pos, 12.0, Color("fff5cf", 0.95 * alpha))
		draw_arc(pos, 30.0, 0, TAU, 26, Color("6e4a28", 0.55 * alpha), 3.0)

	func _draw_pressure_node(pos: Vector2, finished: bool, hot: bool, alpha: float) -> void:
		var r := 23.0 + (4.0 * absf(sin(t * 7.0)) if hot else 0.0)
		draw_circle(pos, r + 6.0, Color(0.9, 0.1, 0.12, 0.95 * alpha))
		draw_circle(pos, r, Color("ffcf4d") if finished else Color("d5c1a1", alpha))
		var skin := Color("c49a72", alpha)
		for i in 4:
			draw_circle(pos + Vector2(-10 + i * 7, -7 + sin(t * 6.0 + i) * 1.0), 6.5, skin)
		draw_colored_polygon(PackedVector2Array([
			pos + Vector2(-17, -2), pos + Vector2(18, -4), pos + Vector2(16, 13), pos + Vector2(-14, 15),
		]), Color("b98761", alpha))
		draw_arc(pos, r + 1.0, 0.2, TAU - 0.4, 22, Color("6e4a28", alpha), 3.0)

	func _strip_front(points: Array) -> Vector2:
		return Vector2(points[0]) if not points.is_empty() else STRIKE

	func _sample_strip(points: Array, u: float) -> Vector2:
		if points.is_empty():
			return Vector2.ZERO
		var f := clampf(u, 0.0, 1.0) * float(points.size() - 1)
		var i := mini(floori(f), points.size() - 1)
		var j := mini(i + 1, points.size() - 1)
		return Vector2(points[i]).lerp(Vector2(points[j]), f - float(i))


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
			draw_string(ThemeDB.fallback_font, c + Vector2(-5, 5), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.4, 0.28, 0.05, a))
