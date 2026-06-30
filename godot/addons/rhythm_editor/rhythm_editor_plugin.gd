@tool
extends EditorPlugin

const RhythmChartScript := preload("res://rhythm/rhythm_chart.gd")
const ValidatorScript := preload("res://rhythm/rhythm_chart_validator.gd")
const ConductorScript := preload("res://conductor.gd")
const AudioFileMusicScript := preload("res://rhythm/audio_file_music.gd")

var dock: RhythmEditorDock
var bottom_button: Button


func _enter_tree() -> void:
	dock = RhythmEditorDock.new()
	dock.name = "Rhythm Editor"
	bottom_button = add_control_to_bottom_panel(dock, "Rhythm Editor")
	add_tool_menu_item("Open Rhythm Editor", Callable(self, "_show_rhythm_editor"))
	call_deferred("_show_rhythm_editor")


func _exit_tree() -> void:
	remove_tool_menu_item("Open Rhythm Editor")
	if dock:
		remove_control_from_bottom_panel(dock)
		dock.queue_free()
		dock = null
	bottom_button = null


func _show_rhythm_editor() -> void:
	if dock:
		make_bottom_panel_item_visible(dock)


class RhythmEditorDock:
	extends Control

	const CHART_DIR := "res://charts"
	const LEFT_GUTTER := 220.0
	const HEADER_H := 74.0
	const WAVE_H := 138.0
	const TRACK_H := 118.0
	const PX_PER_BEAT := 68.0
	const MIN_PX_PER_BEAT := 34.0
	const MAX_PX_PER_BEAT := 132.0

	var chart
	var chart_path := "res://charts/1-5.chart.json"
	var px_per_beat := PX_PER_BEAT
	var dirty := false
	var autosave_left := -1.0
	var conductor
	var music: Node
	var sfx_players: Array[AudioStreamPlayer] = []
	var sfx_i := 0
	var sfx_tap: AudioStreamWAV
	var sfx_roll: AudioStreamWAV
	var sfx_hold: AudioStreamWAV
	var playing := false
	var playhead_beat := 0.0
	var last_preview_beat := -999.0
	var selected_id := ""

	var level_opt: OptionButton
	var variant_opt: OptionButton
	var chart_opt: OptionButton
	var music_opt: OptionButton
	var music_path_edit: LineEdit
	var judge_opt: OptionButton
	var kind_opt: OptionButton
	var lane_opt: OptionButton
	var top_state_label: Label
	var top_state_opt: OptionButton
	var bottom_state_label: Label
	var bottom_state_opt: OptionButton
	var play_btn: Button
	var save_btn: Button
	var validate_btn: Button
	var remove_btn: Button
	var bpm_spin: SpinBox
	var seconds_spin: SpinBox
	var shift_spin: SpinBox
	var zoom_slider: HSlider
	var snap_spin: SpinBox
	var beat_spin: SpinBox
	var duration_spin: SpinBox
	var need_spin: SpinBox
	var need_ms_spin: SpinBox
	var warn_spin: SpinBox
	var strip_spin: SpinBox
	var scroll: ScrollContainer
	var timeline: TimelineView
	var status: Label


	func _ready() -> void:
		custom_minimum_size = Vector2(960, 540)
		_build_audio()
		_build_ui()
		_load_or_create_chart(chart_path)
		set_process(true)


	func _build_audio() -> void:
		for i in 8:
			var p := AudioStreamPlayer.new()
			add_child(p)
			sfx_players.append(p)
		sfx_tap = _render_tone(760.0, 0.06, "sine", 0.42)
		sfx_roll = _render_tone(980.0, 0.045, "triangle", 0.36)
		sfx_hold = _render_tone(420.0, 0.08, "triangle", 0.40)


	func _build_ui() -> void:
		var root := VBoxContainer.new()
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_theme_constant_override("separation", 0)
		add_child(root)

		var toolbar := HBoxContainer.new()
		toolbar.custom_minimum_size.y = HEADER_H
		toolbar.add_theme_constant_override("separation", 10)
		root.add_child(toolbar)

		toolbar.add_child(_label("Level"))
		level_opt = OptionButton.new()
		level_opt.custom_minimum_size.x = 120
		for id in ["1-1", "1-2", "1-3", "1-4", "1-5", "1-6"]:
			level_opt.add_item(id)
		level_opt.item_selected.connect(_on_level_selected)
		toolbar.add_child(level_opt)

		toolbar.add_child(_label("Mode"))
		variant_opt = OptionButton.new()
		variant_opt.custom_minimum_size.x = 118
		variant_opt.add_item("Normal")
		variant_opt.set_item_metadata(0, "normal")
		variant_opt.add_item("Extreme")
		variant_opt.set_item_metadata(1, "extreme")
		variant_opt.item_selected.connect(_on_variant_selected)
		toolbar.add_child(variant_opt)

		toolbar.add_child(_label("Chart"))
		chart_opt = OptionButton.new()
		chart_opt.custom_minimum_size.x = 210
		chart_opt.item_selected.connect(_on_chart_selected)
		toolbar.add_child(chart_opt)

		toolbar.add_child(_label("Music"))
		music_opt = OptionButton.new()
		music_opt.custom_minimum_size.x = 210
		music_opt.item_selected.connect(_on_music_selected)
		toolbar.add_child(music_opt)

		play_btn = Button.new()
		play_btn.text = "Play"
		play_btn.custom_minimum_size = Vector2(46, 38)
		play_btn.pressed.connect(_toggle_play)
		toolbar.add_child(play_btn)

		save_btn = Button.new()
		save_btn.text = "Save"
		save_btn.pressed.connect(_save_chart)
		toolbar.add_child(save_btn)

		validate_btn = Button.new()
		validate_btn.text = "Validate"
		validate_btn.pressed.connect(_validate_chart)
		toolbar.add_child(validate_btn)

		toolbar.add_child(_vline())
		toolbar.add_child(_label("BPM"))
		bpm_spin = SpinBox.new()
		bpm_spin.min_value = 30
		bpm_spin.max_value = 220
		bpm_spin.step = 0.5
		bpm_spin.custom_minimum_size.x = 82
		bpm_spin.value_changed.connect(_on_bpm_changed)
		toolbar.add_child(bpm_spin)

		toolbar.add_child(_label("Sec"))
		seconds_spin = SpinBox.new()
		seconds_spin.min_value = 5
		seconds_spin.max_value = 600
		seconds_spin.step = 0.5
		seconds_spin.custom_minimum_size.x = 82
		seconds_spin.value_changed.connect(_on_seconds_changed)
		toolbar.add_child(seconds_spin)

		toolbar.add_child(_label("Shift"))
		shift_spin = SpinBox.new()
		shift_spin.min_value = -16
		shift_spin.max_value = 16
		shift_spin.step = 0.25
		shift_spin.value = 0.25
		shift_spin.custom_minimum_size.x = 76
		toolbar.add_child(shift_spin)

		var shift_back := Button.new()
		shift_back.text = "<"
		shift_back.custom_minimum_size = Vector2(34, 38)
		shift_back.pressed.connect(func() -> void: _shift_all_notes(-float(shift_spin.value)))
		toolbar.add_child(shift_back)

		var shift_forward := Button.new()
		shift_forward.text = ">"
		shift_forward.custom_minimum_size = Vector2(34, 38)
		shift_forward.pressed.connect(func() -> void: _shift_all_notes(float(shift_spin.value)))
		toolbar.add_child(shift_forward)

		var music_toolbar := HBoxContainer.new()
		music_toolbar.custom_minimum_size.y = 42
		music_toolbar.add_theme_constant_override("separation", 10)
		root.add_child(music_toolbar)
		music_toolbar.add_child(_label("Song Path"))
		music_path_edit = LineEdit.new()
		music_path_edit.placeholder_text = "res://assets/song.mp3"
		music_path_edit.custom_minimum_size.x = 520
		music_path_edit.text_submitted.connect(func(_text: String) -> void: _use_manual_music_path())
		music_toolbar.add_child(music_path_edit)

		var use_path_btn := Button.new()
		use_path_btn.text = "Use"
		use_path_btn.custom_minimum_size = Vector2(54, 34)
		use_path_btn.pressed.connect(_use_manual_music_path)
		music_toolbar.add_child(use_path_btn)

		var scan_btn := Button.new()
		scan_btn.text = "Scan"
		scan_btn.custom_minimum_size = Vector2(62, 34)
		scan_btn.pressed.connect(func() -> void:
			_refresh_music_options()
			_update_status("Scanned res://assets for audio"))
		music_toolbar.add_child(scan_btn)

		var note_toolbar := HBoxContainer.new()
		note_toolbar.custom_minimum_size.y = HEADER_H
		note_toolbar.add_theme_constant_override("separation", 10)
		root.add_child(note_toolbar)
		toolbar = note_toolbar

		toolbar.add_child(_vline())
		toolbar.add_child(_label("Judge"))
		judge_opt = OptionButton.new()
		for j in [RhythmChartScript.JUDGE_TAP, RhythmChartScript.JUDGE_ROLL, RhythmChartScript.JUDGE_HOLD, RhythmChartScript.JUDGE_NONE]:
			judge_opt.add_item(j)
		judge_opt.item_selected.connect(_sync_selected_from_controls)
		toolbar.add_child(judge_opt)

		toolbar.add_child(_label("Kind"))
		kind_opt = OptionButton.new()
		kind_opt.custom_minimum_size.x = 130
		kind_opt.item_selected.connect(_sync_selected_from_controls)
		toolbar.add_child(kind_opt)

		toolbar.add_child(_label("Lane"))
		lane_opt = OptionButton.new()
		lane_opt.add_item(RhythmChartScript.LANE_NODE)
		lane_opt.add_item(RhythmChartScript.LANE_DECOY)
		lane_opt.item_selected.connect(_sync_selected_from_controls)
		toolbar.add_child(lane_opt)

		top_state_label = _label("Top")
		toolbar.add_child(top_state_label)
		top_state_opt = OptionButton.new()
		top_state_opt.custom_minimum_size.x = 86
		_fill_cell_state_options(top_state_opt)
		top_state_opt.item_selected.connect(_sync_selected_from_controls)
		toolbar.add_child(top_state_opt)

		bottom_state_label = _label("Bottom")
		toolbar.add_child(bottom_state_label)
		bottom_state_opt = OptionButton.new()
		bottom_state_opt.custom_minimum_size.x = 86
		_fill_cell_state_options(bottom_state_opt)
		bottom_state_opt.item_selected.connect(_sync_selected_from_controls)
		toolbar.add_child(bottom_state_opt)

		toolbar.add_child(_label("beat"))
		beat_spin = SpinBox.new()
		beat_spin.min_value = 0
		beat_spin.max_value = 512
		beat_spin.step = 0.25
		beat_spin.custom_minimum_size.x = 86
		beat_spin.value_changed.connect(func(_v: float) -> void: _sync_selected_from_controls())
		toolbar.add_child(beat_spin)

		toolbar.add_child(_label("len"))
		duration_spin = SpinBox.new()
		duration_spin.min_value = 0
		duration_spin.max_value = 64
		duration_spin.step = 0.25
		duration_spin.custom_minimum_size.x = 82
		duration_spin.value_changed.connect(func(_v: float) -> void: _sync_selected_from_controls())
		toolbar.add_child(duration_spin)

		toolbar.add_child(_label("Need"))
		need_spin = SpinBox.new()
		need_spin.min_value = 0
		need_spin.max_value = 64
		need_spin.step = 1
		need_spin.custom_minimum_size.x = 64
		need_spin.value_changed.connect(func(_v: float) -> void: _sync_selected_from_controls())
		toolbar.add_child(need_spin)

		toolbar.add_child(_label("Hold ms"))
		need_ms_spin = SpinBox.new()
		need_ms_spin.min_value = 0
		need_ms_spin.max_value = 5000
		need_ms_spin.step = 50
		need_ms_spin.custom_minimum_size.x = 78
		need_ms_spin.value_changed.connect(func(_v: float) -> void: _sync_selected_from_controls())
		toolbar.add_child(need_ms_spin)

		toolbar.add_child(_label("Warn"))
		warn_spin = SpinBox.new()
		warn_spin.min_value = 0
		warn_spin.max_value = 16
		warn_spin.step = 0.25
		warn_spin.custom_minimum_size.x = 64
		warn_spin.value_changed.connect(func(_v: float) -> void: _sync_selected_from_controls())
		toolbar.add_child(warn_spin)

		toolbar.add_child(_label("Strip"))
		strip_spin = SpinBox.new()
		strip_spin.min_value = 0
		strip_spin.max_value = 4
		strip_spin.step = 0.05
		strip_spin.custom_minimum_size.x = 64
		strip_spin.value_changed.connect(func(_v: float) -> void: _sync_selected_from_controls())
		toolbar.add_child(strip_spin)

		toolbar.add_child(_label("Snap"))
		snap_spin = SpinBox.new()
		snap_spin.min_value = 1
		snap_spin.max_value = 16
		snap_spin.step = 1
		snap_spin.value = 4
		snap_spin.custom_minimum_size.x = 68
		snap_spin.value_changed.connect(_on_snap_changed)
		toolbar.add_child(snap_spin)

		remove_btn = Button.new()
		remove_btn.text = "Delete"
		remove_btn.pressed.connect(_remove_selected)
		toolbar.add_child(remove_btn)

		toolbar.add_child(_vline())
		toolbar.add_child(_label("Zoom"))
		zoom_slider = HSlider.new()
		zoom_slider.min_value = MIN_PX_PER_BEAT
		zoom_slider.max_value = MAX_PX_PER_BEAT
		zoom_slider.step = 1
		zoom_slider.value = px_per_beat
		zoom_slider.custom_minimum_size.x = 120
		zoom_slider.value_changed.connect(_on_zoom_changed)
		toolbar.add_child(zoom_slider)

		scroll = ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(scroll)

		timeline = TimelineView.new()
		timeline.editor = self
		timeline.custom_minimum_size = Vector2(3600, 440)
		timeline.mouse_filter = Control.MOUSE_FILTER_STOP
		timeline.focus_mode = Control.FOCUS_ALL
		scroll.add_child(timeline)

		status = Label.new()
		status.text = "RhythmChart ready"
		status.custom_minimum_size.y = 26
		root.add_child(status)


	func _label(text: String) -> Label:
		var label := Label.new()
		label.text = text
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return label


	func _vline() -> ColorRect:
		var line := ColorRect.new()
		line.color = Color(0.16, 0.12, 0.15, 0.35)
		line.custom_minimum_size = Vector2(2, 38)
		return line


	func _refresh_chart_list() -> void:
		chart_opt.clear()
		var paths := _chart_paths()
		if paths.is_empty():
			chart_opt.add_item(chart_path)
			chart_opt.set_item_metadata(0, chart_path)
			return
		for path in paths:
			chart_opt.add_item(path.get_file())
			chart_opt.set_item_metadata(chart_opt.get_item_count() - 1, path)


	func _chart_paths() -> Array:
		var out := []
		var dir := DirAccess.open(CHART_DIR)
		if dir == null:
			return out
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if not dir.current_is_dir() and name.ends_with(".chart.json"):
				out.append("%s/%s" % [CHART_DIR, name])
			name = dir.get_next()
		dir.list_dir_end()
		out.sort()
		return out


	func _load_or_create_chart(path: String) -> void:
		chart_path = path
		chart = RhythmChartScript.new()
		if FileAccess.file_exists(path):
			chart.load_json_file(path)
		else:
			var level_id := _chart_level_from_path(path)
			var variant := _chart_variant_from_path(path)
			var normal_path := _chart_path_for(level_id, "normal")
			if variant == "extreme" and FileAccess.file_exists(normal_path):
				chart.load_json_file(normal_path)
				chart.meta["variant"] = "extreme"
				chart.meta["level_name"] = "%s Extreme" % str(chart.meta.get("level_name", level_id))
			else:
				chart.set_default_for_level(level_id, variant)
			chart.save_json(path)
		_refresh_chart_list()
		_select_chart_option(path)
		_refresh_kind_options()
		_refresh_music_options()
		_select_level_from_chart()
		_select_variant_from_chart()
		_sync_snap_from_chart()
		if str(chart.meta.get("duration_mode", "")) == "music":
			_set_duration_from_music_if_possible(false)
		_sync_timing_controls_from_chart()
		selected_id = ""
		playhead_beat = 0.0
		dirty = false
		_update_timeline_size()
		_update_validation_status("Loaded %s" % path)


	func _select_chart_option(path: String) -> void:
		for i in chart_opt.get_item_count():
			if str(chart_opt.get_item_metadata(i)) == path:
				chart_opt.select(i)
				return


	func _select_level_from_chart() -> void:
		var level_id := str(chart.meta.get("level_id", "1-5"))
		for i in level_opt.get_item_count():
			if level_opt.get_item_text(i) == level_id:
				level_opt.select(i)
				return


	func _select_variant_from_chart() -> void:
		var variant := str(chart.meta.get("variant", _chart_variant_from_path(chart_path)))
		for i in variant_opt.get_item_count():
			if str(variant_opt.get_item_metadata(i)) == variant:
				variant_opt.select(i)
				return


	func _refresh_kind_options() -> void:
		kind_opt.clear()
		for kind in chart.node_kinds:
			var id := str(kind.get("id", "node"))
			kind_opt.add_item(_kind_display_name(id, str(kind.get("name", id))))
			kind_opt.set_item_metadata(kind_opt.get_item_count() - 1, id)
		_update_level_specific_controls()


	func _fill_cell_state_options(opt: OptionButton) -> void:
		opt.clear()
		opt.add_item("Auto")
		opt.set_item_metadata(0, -1)
		opt.add_item("Empty")
		opt.set_item_metadata(1, 0)
		opt.add_item("Correct")
		opt.set_item_metadata(2, 1)
		opt.add_item("Wrong")
		opt.set_item_metadata(3, 2)


	func _update_level_specific_controls() -> void:
		var show_cells := _is_schrodinger_chart()
		for control in [top_state_label, top_state_opt, bottom_state_label, bottom_state_opt]:
			if control:
				control.visible = show_cells


	func _is_schrodinger_chart() -> bool:
		return chart != null and str(chart.meta.get("level_id", "")) == "1-3"


	func _kind_display_name(id: String, fallback: String) -> String:
		match id:
			"bill": return "Bill"
			"scam": return "Scam"
			"loan": return "Loan"
			"food": return "Food"
			"boss": return "Boss"
			"landlord": return "Landlord"
			"game": return "Game"
			"girl", "heart": return "Heart"
			_: return fallback


	func _refresh_music_options() -> void:
		music_opt.clear()
		var music_defs := [
			{"id": "chiptune", "path": "res://chiptune.gd"},
			{"id": "mango", "path": "res://lofi.gd"},
			{"id": "romance", "path": "res://romance.gd"},
			{"id": "bbq", "path": "res://bbq_music.gd"},
			{"id": "rent", "path": "res://rent_music.gd"},
		]
		music_defs.append_array(_scan_audio_defs("res://assets"))
		var cur_path := str(chart.meta.get("music_path", ""))
		var cur_id := str(chart.meta.get("music_id", "rent"))
		var selected := false
		for data in music_defs:
			music_opt.add_item(data["id"])
			music_opt.set_item_metadata(music_opt.get_item_count() - 1, data)
			if str(data.get("path", "")) == cur_path or data["id"] == cur_id:
				music_opt.select(music_opt.get_item_count() - 1)
				selected = true
		if cur_path != "" and not selected:
			var custom := {"id": cur_path.get_file(), "path": cur_path, "kind": "audio" if _is_audio_path(cur_path) else "script"}
			music_opt.add_item(custom["id"])
			music_opt.set_item_metadata(music_opt.get_item_count() - 1, custom)
			music_opt.select(music_opt.get_item_count() - 1)
		if music_path_edit:
			music_path_edit.text = cur_path


	func _on_chart_selected(index: int) -> void:
		_stop_preview()
		var path := str(chart_opt.get_item_metadata(index))
		_load_or_create_chart(path)


	func _on_level_selected(index: int) -> void:
		var id := level_opt.get_item_text(index)
		var path := _chart_path_for(id, _current_variant())
		_load_or_create_chart(path)


	func _on_variant_selected(_index: int) -> void:
		var path := _chart_path_for(_current_level_id(), _current_variant())
		_load_or_create_chart(path)


	func _on_music_selected(index: int) -> void:
		if not chart:
			return
		var data: Dictionary = music_opt.get_item_metadata(index)
		_apply_music_data(data)


	func _apply_music_data(data: Dictionary) -> void:
		chart.meta["music_id"] = data.get("id", "rent")
		chart.meta["music_path"] = data.get("path", "res://rent_music.gd")
		if _is_audio_path(str(chart.meta.get("music_path", ""))):
			chart.meta["duration_mode"] = "music"
			_set_duration_from_music_if_possible()
		else:
			chart.meta.erase("duration_mode")
		if music_path_edit:
			music_path_edit.text = str(chart.meta.get("music_path", ""))
		_sync_timing_controls_from_chart()
		_mark_dirty()
		_stop_preview()
		_update_timeline_size()


	func _use_manual_music_path() -> void:
		if not chart or music_path_edit == null:
			return
		var path := music_path_edit.text.strip_edges()
		if path == "":
			return
		_apply_music_data({"id": path.get_file(), "path": path, "kind": "audio" if _is_audio_path(path) else "script"})
		_refresh_music_options()


	func _scan_audio_defs(root_path: String) -> Array:
		var out := []
		var dir := DirAccess.open(root_path)
		if dir == null:
			return out
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.begins_with("."):
				name = dir.get_next()
				continue
			var path := "%s/%s" % [root_path, name]
			if dir.current_is_dir():
				out.append_array(_scan_audio_defs(path))
			elif _is_audio_path(path):
				out.append({"id": name, "path": path, "kind": "audio"})
			name = dir.get_next()
		dir.list_dir_end()
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("path", "")) < str(b.get("path", "")))
		return out


	func _sync_snap_from_chart() -> void:
		if not chart:
			return
		var sub := maxi(1, int(chart.meta.get("subdivisions", 4)))
		if snap_spin:
			snap_spin.set_value_no_signal(sub)
		var step := 1.0 / float(sub)
		if beat_spin:
			beat_spin.step = step
		if duration_spin:
			duration_spin.step = step


	func _on_snap_changed(value: float) -> void:
		if not chart:
			return
		var sub := maxi(1, int(roundi(value)))
		chart.meta["subdivisions"] = sub
		_sync_snap_from_chart()
		_mark_dirty()
		if timeline:
			timeline.queue_redraw()


	func _sync_timing_controls_from_chart() -> void:
		if not chart:
			return
		var bpm := float(chart.meta.get("start_bpm", 80.0))
		if bpm_spin:
			bpm_spin.set_value_no_signal(bpm)
		if seconds_spin:
			seconds_spin.set_value_no_signal(chart.duration_seconds())


	func _set_duration_from_music_if_possible(mark := true) -> void:
		if not chart:
			return
		var seconds := _music_length_seconds(str(chart.meta.get("music_path", "")))
		if seconds <= 0.0:
			return
		var bpm := maxf(float(chart.meta.get("start_bpm", 80.0)), 1.0)
		chart.meta["duration_ms"] = seconds * 1000.0
		chart.meta["duration_beats"] = maxf(1.0, seconds * bpm / 60.0)
		if mark:
			_mark_dirty()


	func _music_length_seconds(path: String) -> float:
		if not _is_audio_path(path):
			return 0.0
		var stream := _load_audio_stream(path)
		if stream == null:
			return 0.0
		if stream.has_method("get_length"):
			return maxf(float(stream.get_length()), 0.0)
		return 0.0


	func _is_audio_path(path: String) -> bool:
		var lower := path.to_lower()
		return lower.ends_with(".mp3") or lower.ends_with(".ogg") or lower.ends_with(".wav")


	func _load_audio_stream(path: String) -> AudioStream:
		if path == "":
			return null
		if ResourceLoader.exists(path):
			var res := load(path)
			if res is AudioStream:
				return res
		if FileAccess.file_exists(path):
			var lower := path.to_lower()
			if lower.ends_with(".mp3"):
				return AudioStreamMP3.load_from_file(path)
			if lower.ends_with(".ogg"):
				return AudioStreamOggVorbis.load_from_file(path)
			if lower.ends_with(".wav"):
				return AudioStreamWAV.load_from_file(path)
		return null


	func _on_bpm_changed(value: float) -> void:
		if not chart:
			return
		var bpm: float = maxf(float(value), 1.0)
		chart.meta["start_bpm"] = bpm
		chart.meta["end_bpm"] = bpm
		var seconds: float = chart.duration_seconds()
		chart.meta["duration_ms"] = seconds * 1000.0
		chart.meta["duration_beats"] = maxf(1.0, seconds * bpm / 60.0)
		_sync_timing_controls_from_chart()
		_mark_dirty()
		_stop_preview()
		_update_timeline_size()


	func _on_seconds_changed(value: float) -> void:
		if not chart:
			return
		var seconds: float = maxf(float(value), 0.001)
		chart.meta["duration_ms"] = seconds * 1000.0
		var bpm: float = float(chart.meta.get("start_bpm", 80.0))
		chart.meta["duration_beats"] = maxf(1.0, seconds * bpm / 60.0)
		_sync_timing_controls_from_chart()
		_mark_dirty()
		_stop_preview()
		_update_timeline_size()


	func _shift_all_notes(delta_beats: float) -> void:
		if not chart or is_zero_approx(delta_beats):
			return
		for note in chart.notes:
			note["beat"] = maxf(0.0, float(note.get("beat", 0.0)) + delta_beats)
		chart.sort_notes()
		_mark_dirty()
		_stop_preview()
		_update_timeline_size()


	func _save_chart() -> void:
		if not chart:
			return
		chart.sort_notes()
		var err: Error = chart.save_json(chart_path)
		if err == OK:
			dirty = false
			autosave_left = -1.0
		if err == OK:
			_update_validation_status("Saved %s" % chart_path)
		else:
			_update_status("Save failed: %s" % err)


	func _validate_chart() -> void:
		_update_validation_status("Validated %s" % chart_path)


	func _toggle_play() -> void:
		if playing:
			_stop_preview()
		else:
			_start_preview()


	func _start_preview() -> void:
		if not chart:
			return
		_stop_preview(false)
		conductor = ConductorScript.new()
		add_child(conductor)
		conductor.setup({
			"duration_ms": maxf(chart.duration_seconds() * 1000.0, 1000.0),
			"start_bpm": float(chart.meta.get("start_bpm", 80.0)),
			"end_bpm": float(chart.meta.get("end_bpm", chart.meta.get("start_bpm", 80.0))),
			"bpm_curve_exp": float(chart.meta.get("bpm_curve_exp", 1.0)),
			"subdivisions": int(chart.meta.get("subdivisions", 4)),
		})
		var music_path := str(chart.meta.get("music_path", ""))
		if _is_audio_path(music_path):
			music = AudioFileMusicScript.new()
			music.stream_path = music_path
			add_child(music)
			music.setup(conductor)
		else:
			var music_script := load(music_path)
			if music_script == null:
				_stop_preview()
				return
			music = music_script.new()
			add_child(music)
			if music.has_method("setup"):
				music.setup(conductor)
		last_preview_beat = playhead_beat - 0.01
		var preview_offset_us := int(chart.beat_to_seconds(playhead_beat) * 1000000.0)
		conductor.start()
		conductor.start_us -= preview_offset_us
		playing = true
		play_btn.text = "Pause"
		_update_status("Playing with judgement preview")


	func _stop_preview(reset_button := true) -> void:
		playing = false
		if conductor:
			conductor.stop()
			conductor.queue_free()
			conductor = null
		if music:
			music.queue_free()
			music = null
		if reset_button and play_btn:
			play_btn.text = "Play"
		if reset_button:
			_update_status("Paused")


	func _process(delta: float) -> void:
		if playing and conductor and chart:
			playhead_beat = chart.seconds_to_beat(conductor.time_ms() / 1000.0)
			_preview_judgement_sfx(last_preview_beat, playhead_beat)
			last_preview_beat = playhead_beat
			if playhead_beat > chart.duration_beats():
				playhead_beat = 0.0
				_stop_preview()
		if dirty and autosave_left >= 0.0:
			autosave_left -= delta
			if autosave_left <= 0.0:
				_autosave_chart()
		if timeline:
			timeline.queue_redraw()


	func _preview_judgement_sfx(from_beat: float, to_beat: float) -> void:
		for note in chart.notes:
			var beat := float(note.get("beat", 0.0))
			if beat <= from_beat or beat > to_beat:
				continue
			match str(note.get("judge_type", RhythmChartScript.JUDGE_NONE)):
				RhythmChartScript.JUDGE_TAP:
					_play_sfx(sfx_tap, -8.0)
				RhythmChartScript.JUDGE_ROLL:
					_play_sfx(sfx_roll, -9.0)
				RhythmChartScript.JUDGE_HOLD:
					_play_sfx(sfx_hold, -8.0)


	func _play_sfx(stream: AudioStreamWAV, volume_db: float) -> void:
		if stream == null or sfx_players.is_empty():
			return
		var p := sfx_players[sfx_i]
		sfx_i = (sfx_i + 1) % sfx_players.size()
		p.stream = stream
		p.volume_db = volume_db
		p.play()


	func _render_tone(freq: float, dur: float, wave: String, gain: float) -> AudioStreamWAV:
		var rate := 44100
		var n := int(dur * rate)
		var data := PackedByteArray()
		data.resize(n * 2)
		for i in n:
			var t := float(i) / float(rate)
			var env := 1.0 - float(i) / float(maxi(n, 1))
			var v := sin(TAU * freq * t)
			if wave == "triangle":
				v = 2.0 * absf(2.0 * (freq * t - floor(freq * t + 0.5))) - 1.0
			var s := int(clampf(v * env * gain, -1.0, 1.0) * 32767.0)
			data.encode_s16(i * 2, s)
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = rate
		wav.stereo = false
		wav.data = data
		return wav


	func _update_timeline_size() -> void:
		if not timeline or not chart:
			return
		timeline.custom_minimum_size = Vector2(LEFT_GUTTER + chart.duration_beats() * px_per_beat + 260.0, 430.0)
		timeline.queue_redraw()


	func _on_zoom_changed(value: float) -> void:
		px_per_beat = clampf(value, MIN_PX_PER_BEAT, MAX_PX_PER_BEAT)
		_update_timeline_size()


	func select_note(note_id: String) -> void:
		selected_id = note_id
		var note := _selected_note()
		if note.is_empty():
			return
		beat_spin.set_value_no_signal(float(note.get("beat", 0.0)))
		duration_spin.set_value_no_signal(float(note.get("duration_beats", 0.0)))
		var payload: Dictionary = note.get("payload", {})
		need_spin.set_value_no_signal(float(payload.get("need", 0)))
		need_ms_spin.set_value_no_signal(float(payload.get("need_ms", 0)))
		warn_spin.set_value_no_signal(float(payload.get("warn_beats", 0)))
		strip_spin.set_value_no_signal(float(payload.get("strip_len", 0)))
		_select_cell_state(top_state_opt, payload, "top")
		_select_cell_state(bottom_state_opt, payload, "bottom")
		_select_option_by_text(judge_opt, str(note.get("judge_type", RhythmChartScript.JUDGE_TAP)))
		_select_option_by_metadata(kind_opt, str(note.get("kind", "bill")))
		_select_option_by_text(lane_opt, str(note.get("lane", RhythmChartScript.LANE_NODE)))
		_update_level_specific_controls()
		timeline.queue_redraw()


	func _selected_note() -> Dictionary:
		if not chart:
			return {}
		for note in chart.notes:
			if str(note.get("id", "")) == selected_id:
				return note
		return {}


	func _sync_selected_from_controls(_ignored = null) -> void:
		var note := _selected_note()
		if note.is_empty():
			return
		note["beat"] = float(beat_spin.value)
		note["duration_beats"] = float(duration_spin.value)
		note["judge_type"] = judge_opt.get_item_text(judge_opt.selected)
		note["kind"] = str(kind_opt.get_item_metadata(kind_opt.selected))
		note["lane"] = lane_opt.get_item_text(lane_opt.selected)
		note["track"] = note["lane"]
		var payload: Dictionary = note.get("payload", {}).duplicate(true)
		_set_payload_number(payload, "need", int(need_spin.value))
		_set_payload_number(payload, "need_ms", int(need_ms_spin.value))
		_set_payload_number(payload, "warn_beats", float(warn_spin.value))
		_set_payload_number(payload, "strip_len", float(strip_spin.value))
		if _is_schrodinger_chart():
			_set_payload_cell_state(payload, "top", top_state_opt)
			_set_payload_cell_state(payload, "bottom", bottom_state_opt)
		note["payload"] = payload
		if note["lane"] == RhythmChartScript.LANE_DECOY:
			note["judge_type"] = RhythmChartScript.JUDGE_NONE
			_select_option_by_text(judge_opt, RhythmChartScript.JUDGE_NONE)
		chart.sort_notes()
		_mark_dirty()
		_update_timeline_size()


	func _remove_selected() -> void:
		if selected_id == "" or not chart:
			return
		chart.remove_note(selected_id)
		selected_id = ""
		_mark_dirty()
		_update_timeline_size()


	func add_or_select_at(pos: Vector2, create_if_empty := false) -> bool:
		if not chart:
			return false
		var hit := _hit_note(pos)
		if hit != "":
			select_note(hit)
			return true
		if not create_if_empty:
			selected_id = ""
			timeline.queue_redraw()
			return false
		var beat := _snap_beat(_x_to_beat(pos.x))
		if beat < 0.0:
			return false
		var lane := RhythmChartScript.LANE_NODE if pos.y < WAVE_H + TRACK_H else RhythmChartScript.LANE_DECOY
		var judge := judge_opt.get_item_text(judge_opt.selected)
		if lane == RhythmChartScript.LANE_DECOY:
			judge = RhythmChartScript.JUDGE_NONE
		var kind := str(kind_opt.get_item_metadata(maxi(kind_opt.selected, 0)))
		if _is_schrodinger_chart() and lane == RhythmChartScript.LANE_DECOY and kind == "empty":
			kind = "trap"
		var duration := float(duration_spin.value)
		if judge == RhythmChartScript.JUDGE_HOLD or judge == RhythmChartScript.JUDGE_ROLL:
			duration = maxf(duration, 1.0)
		else:
			duration = 0.0
		var payload := _payload_from_controls({})
		var note: Dictionary = chart.add_note(RhythmChartScript.make_note(beat, judge, lane, kind, duration, payload))
		select_note(str(note["id"]))
		_mark_dirty()
		_update_timeline_size()
		return true


	func drag_selected_to(pos: Vector2) -> void:
		var note := _selected_note()
		if note.is_empty():
			return
		note["beat"] = _snap_beat(_x_to_beat(pos.x))
		note["lane"] = RhythmChartScript.LANE_NODE if pos.y < WAVE_H + TRACK_H else RhythmChartScript.LANE_DECOY
		note["track"] = note["lane"]
		if note["lane"] == RhythmChartScript.LANE_DECOY:
			note["judge_type"] = RhythmChartScript.JUDGE_NONE
		chart.sort_notes()
		_mark_dirty()
		select_note(str(note["id"]))


	func resize_selected_to(pos: Vector2) -> void:
		var note := _selected_note()
		if note.is_empty():
			return
		var beat := float(note.get("beat", 0.0))
		var tail := _snap_beat(_x_to_beat(pos.x))
		note["duration_beats"] = maxf(0.25, tail - beat)
		if str(note.get("judge_type", RhythmChartScript.JUDGE_TAP)) == RhythmChartScript.JUDGE_TAP:
			note["judge_type"] = RhythmChartScript.JUDGE_HOLD
			_select_option_by_text(judge_opt, RhythmChartScript.JUDGE_HOLD)
		_mark_dirty()
		select_note(str(note["id"]))


	func seek_to(pos: Vector2) -> void:
		playhead_beat = clampf(_x_to_beat(pos.x), 0.0, chart.duration_beats())
		last_preview_beat = playhead_beat - 0.01
		timeline.queue_redraw()


	func _hit_note(pos: Vector2) -> String:
		for note in chart.notes:
			var lane_y := _lane_center_y(str(note.get("lane", RhythmChartScript.LANE_NODE)))
			var x := _beat_to_x(float(note.get("beat", 0.0)))
			var len := maxf(16.0, float(note.get("duration_beats", 0.0)) * px_per_beat)
			if Rect2(x - 10.0, lane_y - 20.0, len + 20.0, 40.0).has_point(pos):
				return str(note.get("id", ""))
		return ""


	func _hit_note_tail(pos: Vector2) -> String:
		for note in chart.notes:
			var duration := float(note.get("duration_beats", 0.0))
			if duration <= 0.0:
				continue
			var lane_y := _lane_center_y(str(note.get("lane", RhythmChartScript.LANE_NODE)))
			var tail_x := _beat_to_x(float(note.get("beat", 0.0)) + duration)
			if Rect2(tail_x - 12.0, lane_y - 22.0, 24.0, 44.0).has_point(pos):
				return str(note.get("id", ""))
		return ""


	func _lane_center_y(lane: String) -> float:
		return WAVE_H + TRACK_H * 0.5 if lane == RhythmChartScript.LANE_NODE else WAVE_H + TRACK_H * 1.5


	func _snap_beat(raw: float) -> float:
		var sub := maxf(1.0, float(snap_spin.value if snap_spin else chart.meta.get("subdivisions", 4)))
		return maxf(0.0, round(raw * sub) / sub)


	func _beat_to_x(beat: float) -> float:
		return LEFT_GUTTER + beat * px_per_beat


	func _x_to_beat(x: float) -> float:
		return (x - LEFT_GUTTER) / px_per_beat


	func _select_option_by_text(opt: OptionButton, text: String) -> void:
		for i in opt.get_item_count():
			if opt.get_item_text(i) == text:
				opt.select(i)
				return


	func _select_option_by_metadata(opt: OptionButton, value: String) -> void:
		for i in opt.get_item_count():
			if str(opt.get_item_metadata(i)) == value:
				opt.select(i)
				return


	func _current_level_id() -> String:
		return level_opt.get_item_text(level_opt.selected) if level_opt else "1-5"


	func _current_variant() -> String:
		if variant_opt == null:
			return "normal"
		return str(variant_opt.get_item_metadata(variant_opt.selected))


	func _chart_path_for(level_id: String, variant: String) -> String:
		var suffix := "_extreme" if variant == "extreme" else ""
		return "%s/%s%s.chart.json" % [CHART_DIR, level_id, suffix]


	func _chart_variant_from_path(path: String) -> String:
		return "extreme" if path.get_file().contains("_extreme") else "normal"


	func _chart_level_from_path(path: String) -> String:
		return path.get_file().replace("_extreme.chart.json", "").replace(".chart.json", "")


	func _update_status(text: String) -> void:
		if status:
			status.text = "%s%s" % [text, "  *unsaved" if dirty else ""]


	func _mark_dirty() -> void:
		dirty = true
		autosave_left = 0.35
		if status:
			status.text = "Edited %s  *autosave pending" % chart_path


	func _autosave_chart() -> void:
		if not chart:
			return
		chart.sort_notes()
		var err: Error = chart.save_json(chart_path)
		if err == OK:
			dirty = false
			autosave_left = -1.0
			_update_status("Auto-saved %s" % chart_path)
		else:
			autosave_left = -1.0
			_update_status("Auto-save failed: %s" % err)


	func _update_validation_status(prefix: String) -> void:
		if not chart:
			_update_status(prefix)
			return
		var issues := ValidatorScript.validate(chart)
		if issues.is_empty():
			_update_status("%s | Chart OK" % prefix)
			return
		_update_status("%s | %s" % [prefix, ValidatorScript.summarize(issues, 2)])


	func _set_payload_number(payload: Dictionary, key: String, value) -> void:
		if float(value) <= 0.0:
			payload.erase(key)
		else:
			payload[key] = value


	func _payload_from_controls(base_payload: Dictionary) -> Dictionary:
		var payload := base_payload.duplicate(true)
		_set_payload_number(payload, "need", int(need_spin.value))
		_set_payload_number(payload, "need_ms", int(need_ms_spin.value))
		_set_payload_number(payload, "warn_beats", float(warn_spin.value))
		_set_payload_number(payload, "strip_len", float(strip_spin.value))
		if _is_schrodinger_chart():
			_set_payload_cell_state(payload, "top", top_state_opt)
			_set_payload_cell_state(payload, "bottom", bottom_state_opt)
		return payload


	func _select_cell_state(opt: OptionButton, payload: Dictionary, key: String) -> void:
		if opt == null:
			return
		if not payload.has(key):
			opt.select(0)
			return
		_select_option_by_metadata(opt, str(int(payload.get(key, 0))))


	func _set_payload_cell_state(payload: Dictionary, key: String, opt: OptionButton) -> void:
		if opt == null or opt.selected < 0:
			return
		var value := int(opt.get_item_metadata(opt.selected))
		if value < 0:
			payload.erase(key)
		else:
			payload[key] = value


class TimelineView:
	extends Control

	var editor: RhythmEditorDock
	var dragging := false
	var drag_mode := ""


	func _gui_input(event: InputEvent) -> void:
		if editor == null or editor.chart == null:
			return
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.ctrl_pressed:
				editor.zoom_slider.value = minf(editor.zoom_slider.max_value, editor.px_per_beat + 6.0)
				accept_event()
				return
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.ctrl_pressed:
				editor.zoom_slider.value = maxf(editor.zoom_slider.min_value, editor.px_per_beat - 6.0)
				accept_event()
				return
			if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				var hit := editor._hit_note(event.position)
				if hit != "":
					editor.selected_id = hit
					editor._remove_selected()
				return
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					if event.position.y < RhythmEditorDock.WAVE_H:
						editor.seek_to(event.position)
						drag_mode = "seek"
					else:
						var tail_hit := editor._hit_note_tail(event.position)
						if tail_hit != "":
							editor.select_note(tail_hit)
							drag_mode = "resize"
						else:
							var active := editor.add_or_select_at(event.position, event.shift_pressed)
							drag_mode = "move" if active else ""
						dragging = drag_mode != ""
					grab_focus()
				else:
					dragging = false
					drag_mode = ""
		elif event is InputEventMouseMotion and dragging:
			if drag_mode == "resize":
				editor.resize_selected_to(event.position)
			elif drag_mode == "move":
				editor.drag_selected_to(event.position)
			elif drag_mode == "seek":
				editor.seek_to(event.position)
		elif event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
				editor._remove_selected()
				accept_event()
			elif event.keycode == KEY_SPACE:
				editor._toggle_play()
				accept_event()


	func _draw() -> void:
		if editor == null or editor.chart == null:
			return
		var chart = editor.chart
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), Color("fbfaf7"))
		_draw_left_labels(h)
		_draw_grid(chart)
		_draw_wave(chart)
		_draw_notes(chart)
		_draw_playhead(chart)


	func _draw_left_labels(h: float) -> void:
		draw_rect(Rect2(0, 0, RhythmEditorDock.LEFT_GUTTER, h), Color("f2efe8"))
		draw_line(Vector2(RhythmEditorDock.LEFT_GUTTER, 0), Vector2(RhythmEditorDock.LEFT_GUTTER, h), Color("25131d"), 3.0)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(22, 44), "Music", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("25131d"))
		draw_string(font, Vector2(24, RhythmEditorDock.WAVE_H + 74), "Node", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("25131d"))
		draw_string(font, Vector2(24, RhythmEditorDock.WAVE_H + RhythmEditorDock.TRACK_H + 74), "Non-node", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("25131d"))
		draw_rect(Rect2(34, 26, 96, 72), Color("fffefa"), false, 4.0)
		draw_string(font, Vector2(62, 76), "M", HORIZONTAL_ALIGNMENT_LEFT, -1, 54, Color("25131d"))


	func _draw_grid(chart) -> void:
		var dur: float = chart.duration_beats()
		var bottom := size.y
		var sub := maxi(1, int(chart.meta.get("subdivisions", 4)))
		for tick in int(ceil(dur * float(sub))) + 1:
			var beat := float(tick) / float(sub)
			var x := editor._beat_to_x(beat)
			var whole := tick % sub == 0
			var strong := whole and int(roundi(beat)) % 4 == 0
			var alpha := 0.82 if strong else (0.36 if whole else 0.13)
			var width := 3.0 if strong else (1.5 if whole else 1.0)
			draw_line(Vector2(x, 0), Vector2(x, bottom), Color("25131d", alpha), width)
			if strong:
				draw_string(ThemeDB.fallback_font, Vector2(x + 6, 22), str(int(roundi(beat))), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("25131d", 0.55))
		for y in [RhythmEditorDock.WAVE_H, RhythmEditorDock.WAVE_H + RhythmEditorDock.TRACK_H,
				RhythmEditorDock.WAVE_H + RhythmEditorDock.TRACK_H * 2.0]:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color("25131d"), 4.0)


	func _draw_wave(chart) -> void:
		var y_mid := RhythmEditorDock.WAVE_H * 0.52
		var points := PackedVector2Array()
		var music_hash := str(chart.meta.get("music_id", "rent")).hash()
		var x0 := RhythmEditorDock.LEFT_GUTTER + 18.0
		var x1 := size.x - 28.0
		for i in 420:
			var t := float(i) / 419.0
			var x := lerpf(x0, x1, t)
			var amp := sin(t * TAU * 8.0 + float(music_hash % 17)) * 22.0
			amp += sin(t * TAU * 21.0 + float(music_hash % 11)) * 11.0
			amp += sin(t * TAU * 43.0) * 5.0
			points.append(Vector2(x, y_mid + amp))
		draw_polyline(points, Color("1238ff"), 4.0)


	func _draw_notes(chart) -> void:
		for note in chart.notes:
			_draw_note(note)


	func _draw_note(note: Dictionary) -> void:
		var lane := str(note.get("lane", RhythmChartScript.LANE_NODE))
		var y := editor._lane_center_y(lane)
		var x := editor._beat_to_x(float(note.get("beat", 0.0)))
		var duration := float(note.get("duration_beats", 0.0))
		var len := maxf(12.0, duration * editor.px_per_beat)
		var color := _kind_color(str(note.get("kind", "bill")))
		var selected := str(note.get("id", "")) == editor.selected_id
		if str(note.get("judge_type", RhythmChartScript.JUDGE_NONE)) == RhythmChartScript.JUDGE_NONE:
			color = Color("777777")
		if duration > 0.0:
			draw_line(Vector2(x, y), Vector2(x + len, y), color, 8.0)
			for dx in range(14, int(len), 30):
				draw_line(Vector2(x + dx, y - 3), Vector2(x + dx + 12, y - 3), Color(1, 1, 1, 0.72), 3.0)
		else:
			draw_line(Vector2(x - 10, y), Vector2(x + 10, y), color, 5.0)
		draw_circle(Vector2(x, y), 9.0 if selected else 6.0, color)
		if duration > 0.0:
			draw_circle(Vector2(x + len, y), 7.0, color)
		if selected:
			draw_arc(Vector2(x, y), 15.0, 0, TAU, 24, Color("25131d"), 2.0)


	func _kind_color(kind_id: String) -> Color:
		for kind in editor.chart.node_kinds:
			if str(kind.get("id", "")) == kind_id:
				return Color(str(kind.get("color", "#ef4444")))
		return Color("ef4444")


	func _draw_playhead(chart) -> void:
		var x := editor._beat_to_x(editor.playhead_beat)
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color("777777"), 4.0)
		var tri := PackedVector2Array([
			Vector2(x - 14, 0),
			Vector2(x + 14, 0),
			Vector2(x, 34),
		])
		draw_colored_polygon(tri, Color("ef3340"))
