class_name RhythmChartRuntime
extends RefCounted
## Time-query wrapper around RhythmChart.
## Levels should eventually ask this object "what crosses the judgement point"
## instead of each level inventing its own private chart cursor.

const ChartScript := preload("res://rhythm/rhythm_chart.gd")

var chart
var cursor_index := 0
var judged: Dictionary = {}


func setup(source_chart) -> void:
	chart = source_chart
	reset()


func reset() -> void:
	cursor_index = 0
	judged = {}
	if chart:
		chart.sort_notes()


func duration_beats() -> float:
	return chart.duration_beats() if chart else 0.0


func notes_crossed(from_beat: float, to_beat: float, include_decoys := false) -> Array:
	var out := []
	if chart == null:
		return out
	for note in chart.notes:
		var beat := float(note.get("beat", 0.0))
		if beat <= from_beat or beat > to_beat:
			continue
		if not include_decoys and not is_judgement(note):
			continue
		out.append(note)
	return out


func notes_in_window(center_beat: float, radius_beats: float, include_decoys := true) -> Array:
	var out := []
	if chart == null:
		return out
	for note in chart.notes:
		if not include_decoys and not is_judgement(note):
			continue
		var head := float(note.get("beat", 0.0))
		var tail := head + float(note.get("duration_beats", 0.0))
		if tail >= center_beat - radius_beats and head <= center_beat + radius_beats:
			out.append(note)
	return out


func active_segments(clock_beat: float) -> Array:
	var out := []
	if chart == null:
		return out
	for note in chart.notes:
		var kind := str(note.get("judge_type", ChartScript.JUDGE_NONE))
		if kind != ChartScript.JUDGE_HOLD and kind != ChartScript.JUDGE_ROLL:
			continue
		var head := float(note.get("beat", 0.0))
		var tail := head + float(note.get("duration_beats", 0.0))
		if clock_beat >= head and clock_beat <= tail:
			out.append(note)
	return out


func is_judgement(note: Dictionary) -> bool:
	return str(note.get("judge_type", ChartScript.JUDGE_NONE)) != ChartScript.JUDGE_NONE


func is_decoy(note: Dictionary) -> bool:
	return str(note.get("judge_type", ChartScript.JUDGE_NONE)) == ChartScript.JUDGE_NONE


func mark_judged(note: Dictionary) -> void:
	judged[str(note.get("id", ""))] = true


func was_judged(note: Dictionary) -> bool:
	return bool(judged.get(str(note.get("id", "")), false))


static func load_runtime(path: String):
	var rt := RhythmChartRuntime.new()
	var chart = ChartScript.new()
	chart.load_json_file(path)
	rt.setup(chart)
	return rt
