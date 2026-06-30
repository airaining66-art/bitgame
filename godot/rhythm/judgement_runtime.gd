class_name JudgementRuntime
extends RefCounted
## Shared judgement state for RhythmChart notes.
## It owns timing windows and "already judged" bookkeeping; levels decide how a
## judged note looks, sounds, scores, and what its themed verb is.

const ChartScript := preload("res://rhythm/rhythm_chart.gd")

var chart
var judged: Dictionary = {}
var missed: Dictionary = {}


func setup(source_chart) -> void:
	chart = source_chart
	reset()


func reset() -> void:
	judged = {}
	missed = {}
	if chart:
		chart.sort_notes()


func judge_tap(clock_beat: float, perfect_radius: float, good_radius: float,
		filter := Callable()) -> Dictionary:
	var best := _closest_note(clock_beat, good_radius, [ChartScript.JUDGE_TAP], filter)
	if best.is_empty():
		return {"hit": false, "rating": "miss", "note": {}, "error_beats": INF}
	var note: Dictionary = best["note"]
	mark_judged(note)
	var error := float(best["error_beats"])
	return {
		"hit": true,
		"rating": "perfect" if error <= perfect_radius else "good",
		"note": note,
		"error_beats": error,
	}


func judge_roll_tap(clock_beat: float, perfect_radius: float, good_radius: float,
		filter := Callable()) -> Dictionary:
	var best := _closest_note(clock_beat, good_radius, [ChartScript.JUDGE_ROLL], filter)
	if best.is_empty():
		return {"hit": false, "rating": "miss", "note": {}, "error_beats": INF}
	var error := float(best["error_beats"])
	return {
		"hit": true,
		"rating": "perfect" if error <= perfect_radius else "good",
		"note": best["note"],
		"error_beats": error,
	}


func start_hold(clock_beat: float, perfect_radius: float, good_radius: float,
		filter := Callable()) -> Dictionary:
	var best := _closest_note(clock_beat, good_radius, [ChartScript.JUDGE_HOLD], filter)
	if best.is_empty():
		return {"hit": false, "rating": "miss", "note": {}, "error_beats": INF}
	var error := float(best["error_beats"])
	return {
		"hit": true,
		"rating": "perfect" if error <= perfect_radius else "good",
		"note": best["note"],
		"error_beats": error,
	}


func active_hold_notes(clock_beat: float, filter := Callable()) -> Array:
	return _active_segments(clock_beat, [ChartScript.JUDGE_HOLD], filter)


func active_roll_notes(clock_beat: float, filter := Callable()) -> Array:
	return _active_segments(clock_beat, [ChartScript.JUDGE_ROLL], filter)


func sweep_missed_taps(clock_beat: float, miss_radius: float, filter := Callable()) -> Array:
	return sweep_past(clock_beat, miss_radius, [ChartScript.JUDGE_TAP], filter)


func sweep_past(clock_beat: float, miss_radius: float, judge_types: Array,
		filter := Callable()) -> Array:
	var out := []
	if chart == null:
		return out
	for note in chart.notes:
		if not judge_types.has(str(note.get("judge_type", ChartScript.JUDGE_NONE))):
			continue
		if was_judged(note) or was_missed(note) or not _filter_accepts(filter, note):
			continue
		if clock_beat > float(note.get("beat", 0.0)) + miss_radius:
			mark_missed(note)
			out.append(note)
	return out


func closest_note(clock_beat: float, good_radius: float, judge_types: Array,
		filter := Callable()) -> Dictionary:
	return _closest_note(clock_beat, good_radius, judge_types, filter)


func mark_judged(note: Dictionary) -> void:
	judged[str(note.get("id", ""))] = true


func mark_missed(note: Dictionary) -> void:
	missed[str(note.get("id", ""))] = true


func was_judged(note: Dictionary) -> bool:
	return bool(judged.get(str(note.get("id", "")), false))


func was_missed(note: Dictionary) -> bool:
	return bool(missed.get(str(note.get("id", "")), false))


func _closest_note(clock_beat: float, radius: float, judge_types: Array,
		filter: Callable) -> Dictionary:
	if chart == null:
		return {}
	var best: Dictionary = {}
	var best_error := INF
	for note in chart.notes:
		if was_judged(note) or was_missed(note):
			continue
		if not judge_types.has(str(note.get("judge_type", ChartScript.JUDGE_NONE))):
			continue
		if not _filter_accepts(filter, note):
			continue
		var error := absf(clock_beat - float(note.get("beat", 0.0)))
		if error <= radius and error < best_error:
			best_error = error
			best = note
	if best.is_empty():
		return {}
	return {"note": best, "error_beats": best_error}


func _active_segments(clock_beat: float, judge_types: Array, filter: Callable) -> Array:
	var out := []
	if chart == null:
		return out
	for note in chart.notes:
		if was_judged(note) or was_missed(note):
			continue
		if not judge_types.has(str(note.get("judge_type", ChartScript.JUDGE_NONE))):
			continue
		if not _filter_accepts(filter, note):
			continue
		var head := float(note.get("beat", 0.0))
		var tail := head + float(note.get("duration_beats", 0.0))
		if clock_beat >= head and clock_beat <= tail:
			out.append(note)
	return out


func _filter_accepts(filter: Callable, note: Dictionary) -> bool:
	if not filter.is_valid():
		return true
	return bool(filter.call(note))
