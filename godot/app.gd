extends Node
## Autoloaded singleton: shared UI theme (CJK font), the level table, and
## scene-flow helpers (Title -> Level Select -> Game).

var ui_theme: Theme
var levels: Array = []
var current_index := 0


func _ready() -> void:
	_build_theme()
	_build_levels()


func _build_theme() -> void:
	ui_theme = Theme.new()
	# Godot's default font is Latin-only; load a Windows CJK font so Chinese
	# renders everywhere (applied as theme.default_font, inherited by children).
	for path in ["C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/msyhl.ttc",
			"C:/Windows/Fonts/simhei.ttf", "C:/Windows/Fonts/simsun.ttc"]:
		if FileAccess.file_exists(path):
			var f := FontFile.new()
			f.data = FileAccess.get_file_as_bytes(path)
			ui_theme.default_font = f
			return


func _cfg(duration_ms: float) -> Dictionary:
	return {
		"duration_ms": duration_ms,
		"start_bpm": 50.0,
		"end_bpm": 100.0,
		"bpm_curve_exp": 1.6,
		"subdivisions": 4,
		"press_ratio": 0.6,
		"max_skip_run": 2,
		"max_press_run": 3,
	}


func _build_levels() -> void:
	# Only 1-1 is playable for now; the rest are shown on the map but locked.
	levels = [
		{"id": "1-1", "name": "生存之战", "unlocked": true, "cfg": _cfg(45000.0)},
		{"id": "1-2", "name": "芒果奇缘", "unlocked": false, "cfg": _cfg(45000.0)},
		{"id": "1-3", "name": "薛定谔告白", "unlocked": false, "cfg": _cfg(45000.0)},
		{"id": "1-4", "name": "野摊之王", "unlocked": false, "cfg": _cfg(45000.0)},
		{"id": "1-5", "name": "超绝仰卧起", "unlocked": false, "cfg": _cfg(45000.0)},
		{"id": "1-6", "name": "我有一个PLAN", "unlocked": false, "cfg": _cfg(45000.0)},
	]


func current_level() -> Dictionary:
	return levels[current_index]


# --- scene flow -------------------------------------------------------------
func goto_title() -> void:
	get_tree().change_scene_to_file("res://title.tscn")


func goto_levels() -> void:
	get_tree().change_scene_to_file("res://level_select.tscn")


func play_level(index: int) -> void:
	current_index = index
	get_tree().change_scene_to_file("res://main.tscn")
