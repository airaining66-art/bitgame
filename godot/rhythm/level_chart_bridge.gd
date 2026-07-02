class_name LevelChartBridge
extends RefCounted

const ChartScript := preload("res://rhythm/rhythm_chart.gd")
const SequencerScript := preload("res://rhythm/rhythm_chart_sequencer.gd")
const ValidatorScript := preload("res://rhythm/rhythm_chart_validator.gd")
const AudioFileMusicScript := preload("res://rhythm/audio_file_music.gd")


static func chart_path(level_id: String, extreme: bool) -> String:
	var suffix := "_extreme" if extreme else ""
	return "res://charts/%s%s.chart.json" % [level_id, suffix]


static func chart_exists(level_id: String, extreme: bool) -> bool:
	return FileAccess.file_exists(chart_path(level_id, extreme))


static func load_chart(level_id: String, extreme: bool):
	var path := chart_path(level_id, extreme)
	if not FileAccess.file_exists(path):
		if extreme:
			push_warning("Missing Extreme RhythmChart: %s" % path)
		return null
	var chart = ChartScript.new()
	chart.load_json_file(path)
	_apply_music_duration_to_chart(chart)
	var issues := ValidatorScript.validate(chart)
	for issue in issues:
		var msg := str(issue.get("message", ""))
		if str(issue.get("severity", "")) == "error":
			push_error(msg)
		else:
			push_warning(msg)
	return chart


static func _apply_music_duration_to_chart(chart) -> void:
	if chart == null or str(chart.meta.get("duration_mode", "")) != "music":
		return
	var music_ms := music_length_ms(chart.meta)
	if music_ms <= 0.0:
		return
	var bpm := maxf(float(chart.meta.get("start_bpm", 80.0)), 1.0)
	chart.meta["duration_ms"] = music_ms
	chart.meta["duration_beats"] = maxf(1.0, music_ms * bpm / 60000.0)


static func load_sequencer(level_id: String, extreme: bool, ticks_per_beat := 1):
	var chart = load_chart(level_id, extreme)
	if chart == null:
		return null
	var sequencer = SequencerScript.new()
	sequencer.setup(chart, ticks_per_beat)
	return sequencer


static func load_discrete_slots(level_id: String, extreme: bool, ticks_per_beat: int,
		map_event: Callable, rest_data: Dictionary, end_data: Dictionary) -> Array:
	var sequencer = load_sequencer(level_id, extreme, ticks_per_beat)
	return build_discrete_slots(sequencer, map_event, rest_data, end_data)


static func load_meta(level_id: String, extreme: bool) -> Dictionary:
	var chart = load_chart(level_id, extreme)
	return chart.meta.duplicate(true) if chart else {}


static func apply_meta_to_level(meta: Dictionary, level: Dictionary, conductor = null) -> void:
	for key in ["duration_ms", "start_bpm", "end_bpm", "bpm_curve_exp", "subdivisions"]:
		if meta.has(key):
			level[key] = meta[key]
	var music_ms := music_length_ms(meta)
	if music_ms > 0.0 and str(meta.get("duration_mode", "")) == "music":
		level["duration_ms"] = music_ms
	if not meta.has("duration_ms") and meta.has("duration_beats") and meta.has("start_bpm"):
		var start := float(meta.get("start_bpm", 80.0))
		var end := float(meta.get("end_bpm", start))
		var curve_exp := maxf(float(meta.get("bpm_curve_exp", 1.0)), 0.001)
		var avg_bpm := start + (end - start) / (curve_exp + 1.0)
		level["duration_ms"] = float(meta["duration_beats"]) * 60000.0 / maxf(avg_bpm, 1.0)
	if conductor:
		conductor.setup(level)


static func make_music_from_meta(meta: Dictionary, fallback_script) -> Node:
	var music_path := str(meta.get("music_path", ""))
	if _is_audio_path(music_path):
		var audio_node = AudioFileMusicScript.new()
		audio_node.stream_path = music_path
		audio_node.fade_in_seconds = float(meta.get("fade_in_seconds", 0.0))
		audio_node.fade_out_seconds = float(meta.get("fade_out_seconds", 0.0))
		return audio_node
	if music_path != "" and ResourceLoader.exists(music_path):
		var script = load(music_path)
		if script:
			var node = script.new()
			if node is Node:
				return node
	return fallback_script.new()


static func music_length_ms(meta: Dictionary) -> float:
	var music_path := str(meta.get("music_path", ""))
	if not _is_audio_path(music_path):
		return 0.0
	var stream := _load_audio_stream(music_path)
	if stream == null:
		return 0.0
	if stream.has_method("get_length"):
		return maxf(float(stream.get_length()) * 1000.0, 0.0)
	return 0.0


static func _is_audio_path(path: String) -> bool:
	var lower := path.to_lower()
	return lower.ends_with(".mp3") or lower.ends_with(".ogg") or lower.ends_with(".wav")


static func _load_audio_stream(path: String) -> AudioStream:
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


static func build_discrete_slots(sequencer, map_event: Callable, rest_data: Dictionary,
		end_data: Dictionary) -> Array:
	if sequencer == null:
		return []
	var slots := []
	for tick in sequencer.tick_count():
		slots.append(rest_data.duplicate(true))
	for tick in sequencer.tick_count():
		for event in sequencer.events_at_tick(tick):
			var mapped = map_event.call(event)
			var entries: Array = mapped if typeof(mapped) == TYPE_ARRAY else [mapped]
			for entry in entries:
				if typeof(entry) != TYPE_DICTIONARY or entry.is_empty():
					continue
				var target: int = tick + int(entry.get("_offset", 0))
				if target < 0 or target >= slots.size():
					continue
				var current: Dictionary = slots[target]
				if int(entry.get("_priority", 1)) >= int(current.get("_priority", 0)):
					slots[target] = entry.duplicate(true)
	for i in slots.size():
		slots[i].erase("_priority")
		slots[i].erase("_offset")
	var end := end_data.duplicate(true)
	end.erase("_priority")
	end.erase("_offset")
	slots.append(end)
	return slots
