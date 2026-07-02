class_name RhythmChart
extends RefCounted
## Shared chart model for the rhythm editor and future level runtimes.
## The gameplay contract stays small: playable judgement notes are tap/roll/hold.
## Decoy notes are visual timing events with judge_type == "none".

const JUDGE_NONE := "none"
const JUDGE_TAP := "tap"
const JUDGE_ROLL := "roll"
const JUDGE_HOLD := "hold"

const LANE_NODE := "node"
const LANE_DECOY := "decoy"

const DEFAULT_TRACKS := [
	{"id": LANE_NODE, "name": "Node", "color": "#ef4444"},
	{"id": LANE_DECOY, "name": "Non-node", "color": "#777777"},
]

var meta: Dictionary = {
	"version": 1,
	"level_id": "1-5",
	"level_name": "Rent",
	"music_id": "rent",
	"music_path": "res://rent_music.gd",
	"start_bpm": 80.0,
	"end_bpm": 104.0,
	"bpm_curve_exp": 1.5,
	"subdivisions": 4,
	"duration_beats": 64.0,
}
var tracks: Array = DEFAULT_TRACKS.duplicate(true)
var node_kinds: Array = [
	{"id": "bill", "name": "Bill", "color": "#ef4444"},
	{"id": "scam", "name": "Scam", "color": "#f97316"},
	{"id": "loan", "name": "Loan", "color": "#eab308"},
	{"id": "food", "name": "Food", "color": "#22c55e"},
	{"id": "boss", "name": "Boss", "color": "#f43f5e"},
	{"id": "landlord", "name": "Landlord", "color": "#38bdf8"},
]
var notes: Array = []


func set_default_for_level(level_id: String, variant := "normal") -> void:
	meta["level_id"] = level_id
	meta["variant"] = variant
	match level_id:
		"1-1":
			meta["level_name"] = "Binary"
			meta["music_id"] = "neon_pulse"
			meta["music_path"] = "res://assets/music/neon_pulse.mp3"
			meta["duration_mode"] = "music"
			meta["start_bpm"] = 64.0
			meta["end_bpm"] = 64.0
			meta["bpm_curve_exp"] = 1.0
			meta["duration_ms"] = 90000.0
			meta["duration_beats"] = 96.0
			node_kinds = [
				{"id": "bit0", "name": "Bit 0", "color": "#ef4444"},
				{"id": "bit1", "name": "Bit 1", "color": "#f6b800"},
			]
		"1-2":
			meta["level_name"] = "Mango"
			meta["music_id"] = "mango"
			meta["music_path"] = "res://lofi.gd"
			meta["start_bpm"] = 70.0
			meta["end_bpm"] = 110.0
			node_kinds = [
				{"id": "mango", "name": "Mango", "color": "#f3c200"},
				{"id": "water", "name": "Water", "color": "#38bdf8"},
			]
		"1-3":
			meta["level_name"] = "Schrodinger"
			meta["music_id"] = "romance"
			meta["music_path"] = "res://romance.gd"
			meta["start_bpm"] = 84.0
			meta["end_bpm"] = 116.0
			node_kinds = [
				{"id": "food_correct", "name": "Food C", "color": "#f4c45a"},
				{"id": "face_correct", "name": "Face C", "color": "#e0708a"},
				{"id": "both_correct", "name": "Both C", "color": "#8fcf7a"},
				{"id": "trap", "name": "Trap", "color": "#e2584f"},
				{"id": "hold", "name": "Hold", "color": "#38bdf8"},
				{"id": "roll", "name": "Roll", "color": "#f97316"},
				{"id": "baby", "name": "Baby", "color": "#a855f7"},
				{"id": "empty", "name": "Empty", "color": "#777777"},
			]
		"1-4":
			meta["level_name"] = "BBQ"
			meta["music_id"] = "bbq"
			meta["music_path"] = "res://bbq_music.gd"
			meta["start_bpm"] = 84.0
			meta["end_bpm"] = 118.0
			node_kinds = [
				{"id": "beef", "name": "Beef", "color": "#c62828"},
				{"id": "pepper", "name": "Pepper", "color": "#ff6f00"},
				{"id": "onion", "name": "Onion", "color": "#7b1fa2"},
				{"id": "mushroom", "name": "Mushroom", "color": "#6d4c41"},
				{"id": "bread", "name": "Bread", "color": "#fff9c4"},
				{"id": "leek", "name": "Leek", "color": "#388e3c"},
				{"id": "flip", "name": "Flip", "color": "#ffc107"},
				{"id": "rest", "name": "Rest", "color": "#777777"},
			]
		_:
			meta["level_name"] = "Rent"
			meta["music_id"] = "rent"
			meta["music_path"] = "res://rent_music.gd"
			meta["start_bpm"] = 80.0
			meta["end_bpm"] = 104.0
	if variant == "extreme":
		meta["level_name"] = "%s Extreme" % str(meta.get("level_name", level_id))
	notes = [
		make_note(2.0, JUDGE_TAP, LANE_NODE, "bill", 0.0),
		make_note(3.5, JUDGE_NONE, LANE_DECOY, "food", 0.0),
		make_note(5.0, JUDGE_TAP, LANE_NODE, "scam", 0.0),
		make_note(8.0, JUDGE_ROLL, LANE_NODE, "boss", 4.0, {"need": 8}),
		make_note(14.0, JUDGE_HOLD, LANE_NODE, "landlord", 3.0, {"need_ms": 1400}),
	]


static func make_note(beat: float, judge_type: String, lane: String, kind: String,
		note_duration_beats := 0.0, payload := {}) -> Dictionary:
	return {
		"id": _new_id(),
		"beat": beat,
		"duration_beats": note_duration_beats,
		"judge_type": judge_type,
		"lane": lane,
		"kind": kind,
		"track": lane,
		"payload": payload.duplicate(true),
	}


static func _new_id() -> String:
	return "%d-%d" % [Time.get_ticks_usec(), randi() % 100000]


func load_json_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Invalid RhythmChart JSON: %s" % path)
		return
	from_dict(parsed)


func save_json(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	return OK


func from_dict(data: Dictionary) -> void:
	meta = data.get("meta", meta).duplicate(true)
	tracks = data.get("tracks", tracks).duplicate(true)
	node_kinds = data.get("node_kinds", node_kinds).duplicate(true)
	notes = []
	for raw in data.get("notes", []):
		if typeof(raw) == TYPE_DICTIONARY:
			notes.append(normalize_note(raw))
	sort_notes()


func to_dict() -> Dictionary:
	return {
		"meta": meta,
		"tracks": tracks,
		"node_kinds": node_kinds,
		"notes": notes,
	}


func normalize_note(raw: Dictionary) -> Dictionary:
	var note := {
		"id": str(raw.get("id", _new_id())),
		"beat": float(raw.get("beat", 0.0)),
		"duration_beats": maxf(0.0, float(raw.get("duration_beats", 0.0))),
		"judge_type": str(raw.get("judge_type", JUDGE_TAP)),
		"lane": str(raw.get("lane", LANE_NODE)),
		"kind": str(raw.get("kind", "bill")),
		"track": str(raw.get("track", raw.get("lane", LANE_NODE))),
		"payload": raw.get("payload", {}).duplicate(true),
	}
	if note["lane"] == LANE_DECOY:
		note["judge_type"] = JUDGE_NONE
	return note


func add_note(note: Dictionary) -> Dictionary:
	var n := normalize_note(note)
	notes.append(n)
	sort_notes()
	return n


func remove_note(note_id: String) -> void:
	for i in range(notes.size() - 1, -1, -1):
		if str(notes[i].get("id", "")) == note_id:
			notes.remove_at(i)


func sort_notes() -> void:
	notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("beat", 0.0)) < float(b.get("beat", 0.0)))


func duration_beats() -> float:
	var d := float(meta.get("duration_beats", 64.0))
	for note in notes:
		d = maxf(d, float(note.get("beat", 0.0)) + float(note.get("duration_beats", 0.0)) + 4.0)
	return d


func duration_seconds() -> float:
	if meta.has("duration_ms"):
		return maxf(float(meta.get("duration_ms", 1000.0)) / 1000.0, 0.001)
	var avg_bpm := _average_bpm()
	return duration_beats() * 60.0 / maxf(avg_bpm, 1.0)


func beat_to_seconds(beat: float) -> float:
	var target := clampf(beat, 0.0, duration_beats())
	var total_seconds := duration_seconds()
	var lo := 0.0
	var hi := 1.0
	for i in 32:
		var mid := (lo + hi) * 0.5
		if _beats_at_progress(mid, total_seconds) < target:
			lo = mid
		else:
			hi = mid
	return total_seconds * ((lo + hi) * 0.5)


func seconds_to_beat(seconds: float) -> float:
	var total_seconds := duration_seconds()
	var progress := clampf(seconds / maxf(total_seconds, 0.001), 0.0, 1.0)
	return _beats_at_progress(progress, total_seconds)


func _average_bpm() -> float:
	var start := float(meta.get("start_bpm", 80.0))
	var end := float(meta.get("end_bpm", start))
	var curve_exp := maxf(float(meta.get("bpm_curve_exp", 1.0)), 0.001)
	return start + (end - start) / (curve_exp + 1.0)


func _beats_at_progress(progress: float, total_seconds: float) -> float:
	var x := clampf(progress, 0.0, 1.0)
	var start := float(meta.get("start_bpm", 80.0))
	var end := float(meta.get("end_bpm", start))
	var curve_exp := maxf(float(meta.get("bpm_curve_exp", 1.0)), 0.001)
	var bpm_integral := start * x + (end - start) * pow(x, curve_exp + 1.0) / (curve_exp + 1.0)
	return total_seconds * bpm_integral / 60.0


func judgement_notes() -> Array:
	return notes.filter(func(note: Dictionary) -> bool:
		return str(note.get("judge_type", JUDGE_NONE)) != JUDGE_NONE)
