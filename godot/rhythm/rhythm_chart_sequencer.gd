class_name RhythmChartSequencer
extends RefCounted

const ChartScript := preload("res://rhythm/rhythm_chart.gd")

var chart
var ticks_per_beat := 1
var ticks: Array = []


func setup(source_chart, source_ticks_per_beat := 1) -> void:
	chart = source_chart
	ticks_per_beat = maxi(1, source_ticks_per_beat)
	_rebuild()


func tick_count() -> int:
	return ticks.size()


func beat_duration() -> float:
	return chart.duration_beats() if chart else 0.0


func tick_to_beat(tick: int) -> float:
	return float(tick) / float(ticks_per_beat)


func beat_to_tick(beat: float) -> int:
	return maxi(0, roundi(beat * float(ticks_per_beat)))


func events_at_tick(tick: int) -> Array:
	if tick < 0 or tick >= ticks.size():
		return []
	return ticks[tick].get("events", [])


func tick_data(tick: int) -> Dictionary:
	if tick < 0 or tick >= ticks.size():
		return {"tick": tick, "beat": tick_to_beat(tick), "events": []}
	return ticks[tick]


func _rebuild() -> void:
	ticks = []
	if chart == null:
		return
	chart.sort_notes()
	var total_ticks := maxi(1, ceili(chart.duration_beats() * float(ticks_per_beat)))
	for tick in total_ticks:
		ticks.append({"tick": tick, "beat": tick_to_beat(tick), "events": []})
	for note in chart.notes:
		var head := beat_to_tick(float(note.get("beat", 0.0)))
		if head >= ticks.size():
			continue
		var duration_ticks := maxi(0, roundi(float(note.get("duration_beats", 0.0)) * float(ticks_per_beat)))
		var event: Dictionary = note.duplicate(true)
		event["tick"] = head
		event["head_tick"] = head
		event["tail_tick"] = head + duration_ticks
		event["duration_ticks"] = duration_ticks
		event["head_beat"] = tick_to_beat(head)
		ticks[head]["events"].append(event)
