class_name RhythmChartValidator
extends RefCounted
## Human-facing chart checks shared by the editor and runtime.
## Keep messages concrete: a non-programmer should know which note to fix.

const ChartScript := preload("res://rhythm/rhythm_chart.gd")

const VALID_JUDGES := [
	ChartScript.JUDGE_TAP,
	ChartScript.JUDGE_ROLL,
	ChartScript.JUDGE_HOLD,
	ChartScript.JUDGE_NONE,
]


static func validate(chart) -> Array:
	var issues := []
	if chart == null:
		issues.append(_issue("error", "Chart is missing or could not be loaded.", ""))
		return issues
	if not chart.meta.has("level_id"):
		issues.append(_issue("warning", "Missing meta.level_id.", "meta"))
	if not chart.meta.has("music_path"):
		issues.append(_issue("warning", "Missing meta.music_path; runtime will use fallback music.", "meta"))
	var last_beat := -INF
	var ids := {}
	for i in chart.notes.size():
		var note: Dictionary = chart.notes[i]
		var path := "notes[%d]" % i
		var id := str(note.get("id", ""))
		if id == "":
			issues.append(_issue("error", "%s has an empty id." % path, path))
		elif ids.has(id):
			issues.append(_issue("error", "%s duplicates note id %s." % [path, id], path))
		ids[id] = true
		var beat := float(note.get("beat", 0.0))
		if beat < 0.0:
			issues.append(_issue("error", "%s has a negative beat." % path, path))
		if beat < last_beat:
			issues.append(_issue("warning", "%s is out of order; save will sort notes." % path, path))
		last_beat = beat
		var judge := str(note.get("judge_type", ChartScript.JUDGE_TAP))
		if not VALID_JUDGES.has(judge):
			issues.append(_issue("error", "%s uses invalid judge_type '%s'." % [path, judge], path))
		var lane := str(note.get("lane", ChartScript.LANE_NODE))
		if lane == ChartScript.LANE_DECOY and judge != ChartScript.JUDGE_NONE:
			issues.append(_issue("error", "%s is on decoy lane but is not judge_type none." % path, path))
		var duration := float(note.get("duration_beats", 0.0))
		if judge == ChartScript.JUDGE_TAP and duration > 0.0:
			issues.append(_issue("warning", "%s is a tap but has duration; runtime treats it as a point note." % path, path))
		if (judge == ChartScript.JUDGE_ROLL or judge == ChartScript.JUDGE_HOLD) and duration <= 0.0:
			issues.append(_issue("error", "%s is %s but duration_beats is 0." % [path, judge], path))
		if duration < 0.0:
			issues.append(_issue("error", "%s has negative duration_beats." % path, path))
	return issues


static func has_errors(issues: Array) -> bool:
	for issue in issues:
		if str(issue.get("severity", "")) == "error":
			return true
	return false


static func summarize(issues: Array, limit := 3) -> String:
	if issues.is_empty():
		return "Chart OK"
	var parts := []
	for i in mini(limit, issues.size()):
		parts.append(str(issues[i].get("message", "")))
	var more := issues.size() - parts.size()
	if more > 0:
		parts.append("%d more" % more)
	var out := ""
	for i in parts.size():
		if i > 0:
			out += " | "
		out += str(parts[i])
	return out


static func _issue(severity: String, message: String, path: String) -> Dictionary:
	return {"severity": severity, "message": message, "path": path}
