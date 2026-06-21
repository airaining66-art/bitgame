class_name Conductor
extends Node
## Single source of truth for tempo and beat timing.
## Everything that should "feel the beat" (music, breathing light, UI pulse)
## reads from here, so it stays decoupled and reusable across levels.
##
## A "cycle" is one gameplay beat: the tile pair slides in over the first half
## and parks for the second half. The player presses at JUDGE_OFFSET (0.75),
## which is also where the musical downbeat (kick) lands — so pressing == kick.

signal beat(cycle_index)               ## cycle boundary — advance the tiles
signal downbeat(cycle_index)           ## the press / kick moment (musical sub 0)
signal subdivision(cycle_index, sub)   ## every 1/subdivisions of a musical beat
signal level_finished

const JUDGE_OFFSET := 0.75

var level: Dictionary = {}
var subdivisions := 4
var tempo_scale := 1.0      # runtime tempo multiplier (1.5 during a baby burst)
var auto_finish := true     # if false, never auto-stop at duration (the chart drives the end)

var running := false
var finished := false
var start_us := 0
var cycle_index := 0
var cycle_start := 0.0      # ms, start of the current cycle
var cycle_duration := 600.0 # ms
var _last_sub := -1


func setup(level_data: Dictionary) -> void:
	level = level_data
	subdivisions = int(level.get("subdivisions", 4))
	process_priority = -10  # run before the main game each frame


func start() -> void:
	start_us = Time.get_ticks_usec()
	running = true
	finished = false
	cycle_index = 0
	cycle_start = 0.0
	cycle_duration = beat_duration_at(0.0)
	_last_sub = -1


func stop() -> void:
	running = false


# --- time / tempo -----------------------------------------------------------
func time_ms() -> float:
	return (Time.get_ticks_usec() - start_us) / 1000.0


func duration_ms() -> float:
	return float(level.get("duration_ms", 60000.0))


func progress() -> float:
	return clampf(time_ms() / duration_ms(), 0.0, 1.0)


func bpm_at(elapsed_ms: float) -> float:
	var s := float(level.get("start_bpm", 50.0))
	var e := float(level.get("end_bpm", 100.0))
	var k := float(level.get("bpm_curve_exp", 1.0))
	var t: float = pow(clampf(elapsed_ms / duration_ms(), 0.0, 1.0), k)
	return (s + (e - s) * t) * tempo_scale


func bpm() -> float:
	return bpm_at(time_ms())


func beat_duration_at(elapsed_ms: float) -> float:
	return 60000.0 / bpm_at(elapsed_ms)


# --- phase helpers ----------------------------------------------------------
func beat_phase() -> float:
	## 0..1 within the current cycle (tile slide phase).
	return (time_ms() - cycle_start) / cycle_duration


func musical_phase() -> float:
	## 0 at the downbeat / press moment, wraps every cycle.
	return fposmod(beat_phase() - JUDGE_OFFSET, 1.0)


func pulse(sharpness := 3.0) -> float:
	## 1.0 on the musical downbeat, decaying to 0 before the next. Drives the
	## "everything flashes to the beat" feel — read it, don't hardcode timers.
	if not running:
		return 0.0
	return pow(1.0 - musical_phase(), sharpness)


func _process(_delta: float) -> void:
	if not running:
		return
	var t := time_ms()

	# Advance whole cycles, recomputing duration at each boundary so the
	# continuous tempo ramp stays accurate (mirrors the original step loop).
	while t - cycle_start >= cycle_duration:
		cycle_start += cycle_duration
		cycle_index += 1
		cycle_duration = beat_duration_at(cycle_start)
		beat.emit(cycle_index)

	# Subdivisions of the musical beat (continuous across cycle boundaries).
	var sub := int(musical_phase() * subdivisions) % subdivisions
	if sub != _last_sub:
		_last_sub = sub
		subdivision.emit(cycle_index, sub)
		if sub == 0:
			downbeat.emit(cycle_index)

	if auto_finish and not finished and progress() >= 1.0:
		finished = true
		running = false
		level_finished.emit()
