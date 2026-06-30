class_name BeatSlotJudgement
extends RefCounted
## Shared judgement state for one-beat-at-a-time chart projections.
## Levels keep their themed feedback; this object owns duplicate-judge guards
## and the common tap/skip/miss timing result.

const RESULT_REPEAT := "repeat"
const RESULT_PERFECT := "perfect"
const RESULT_GOOD := "good"
const RESULT_BAD := "bad"
const RESULT_WRONG := "wrong"
const RESULT_MISS := "miss"
const RESULT_SKIP := "skip"

var judged_slots: Dictionary = {}


func reset() -> void:
	judged_slots = {}


func was_judged(slot_index: int) -> bool:
	return bool(judged_slots.get(slot_index, false))


func mark_judged(slot_index: int) -> void:
	judged_slots[slot_index] = true


func judge_press(slot_index: int, should_press: bool, delta_ms: float,
		perfect_ms: float, good_ms: float) -> Dictionary:
	if was_judged(slot_index):
		return _result(RESULT_REPEAT, delta_ms)
	mark_judged(slot_index)
	if not should_press:
		return _result(RESULT_WRONG, delta_ms)
	if delta_ms <= perfect_ms:
		return _result(RESULT_PERFECT, delta_ms)
	if delta_ms <= good_ms:
		return _result(RESULT_GOOD, delta_ms)
	return _result(RESULT_BAD, delta_ms)


func resolve_slot(slot_index: int, should_press: bool) -> Dictionary:
	if was_judged(slot_index):
		return _result(RESULT_REPEAT, 0.0)
	mark_judged(slot_index)
	return _result(RESULT_MISS if should_press else RESULT_SKIP, 0.0)


func _result(kind: String, delta_ms: float) -> Dictionary:
	return {"result": kind, "delta_ms": delta_ms}
