extends Node
## Autoloaded singleton: shared UI theme (CJK font), the level table, and
## scene-flow helpers (Title -> Level Select -> Game).

var ui_theme: Theme
var levels: Array = []
var current_index := 0
var extreme := false                 # current run is Extreme (1.5x speed)
var cleared_3star: Dictionary = {}   # level index -> true once 3-star cleared


func _ready() -> void:
	_build_theme()
	_build_levels()
	_load_progress()


func _load_progress() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://progress.cfg") == OK and cf.has_section("clears"):
		for k in cf.get_section_keys("clears"):
			cleared_3star[int(k)] = true


func _save_progress() -> void:
	var cf := ConfigFile.new()
	for k in cleared_3star:
		cf.set_value("clears", str(k), true)
	cf.save("user://progress.cfg")


## Called by a level on a win. 3-star (no hearts lost) unlocks Extreme mode.
func record_result(index: int, hearts_lost: int) -> void:
	if hearts_lost <= 0 and not cleared_3star.get(index, false):
		cleared_3star[index] = true
		_save_progress()


func is_3star(index: int) -> bool:
	return cleared_3star.get(index, false)


## The current level's config, scaled to 1.5x for an Extreme run.
func active_cfg() -> Dictionary:
	var cfg: Dictionary = current_level().get("cfg", {}).duplicate()
	if extreme:
		cfg["start_bpm"] = float(cfg.get("start_bpm", 50.0)) * 1.5
		cfg["end_bpm"] = float(cfg.get("end_bpm", 100.0)) * 1.5
		cfg["duration_ms"] = float(cfg.get("duration_ms", 45000.0)) / 1.5
	return cfg


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


func _cfg(duration_ms: float, start_bpm := 50.0, end_bpm := 100.0) -> Dictionary:
	return {
		"duration_ms": duration_ms,
		"start_bpm": start_bpm,
		"end_bpm": end_bpm,
		"bpm_curve_exp": 1.6,
		"subdivisions": 4,
		"press_ratio": 0.6,
		"max_skip_run": 2,
		"max_press_run": 3,
	}


func _build_levels() -> void:
	# 1-1 and 1-2 playable; the rest are shown on the map but locked.
	levels = [
		{"id": "1-1", "name": "生存之战", "unlocked": true, "scene": "res://main.tscn", "cfg": _cfg(45000.0)},
		{"id": "1-2", "name": "芒果奇缘", "unlocked": true, "scene": "res://mango.tscn", "cfg": _cfg(45000.0, 70.0, 110.0)},
		{"id": "1-3", "name": "薛定谔告白", "unlocked": false, "scene": "", "cfg": _cfg(45000.0)},
		{"id": "1-4", "name": "野摊之王", "unlocked": false, "scene": "", "cfg": _cfg(45000.0)},
		{"id": "1-5", "name": "超绝仰卧起", "unlocked": false, "scene": "", "cfg": _cfg(45000.0)},
		{"id": "1-6", "name": "我有一个PLAN", "unlocked": false, "scene": "", "cfg": _cfg(45000.0)},
	]


func current_level() -> Dictionary:
	return levels[current_index]


# --- scene flow -------------------------------------------------------------
func goto_title() -> void:
	get_tree().change_scene_to_file("res://title.tscn")


func goto_levels() -> void:
	get_tree().change_scene_to_file("res://level_select.tscn")


func play_level(index: int, ext := false) -> void:
	current_index = index
	extreme = ext
	var scene: String = levels[index].get("scene", "")
	if scene == "":
		scene = "res://main.tscn"
	get_tree().change_scene_to_file(scene)


# --- shared button styling --------------------------------------------------
# Gives every Button a consistent normal / hover / pressed look. Reusable by
# any scene (incl. future levels): call App.style_button(my_button).
const BTN_INK := Color("21170d")
const BTN_ACCENT := Color("d71920")
const BTN_WHITE := Color("ffffff")
const BTN_HOVER := Color("fff0f0")


func _btn_box(bg: Color, border_col: Color, border_w: int, radius: int,
		pad_h: int, pad_top: int, pad_bottom: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border_w)
	sb.border_color = border_col
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_top
	sb.content_margin_bottom = pad_bottom
	return sb


## variant: "default" (filled card button) | "menu" (flat text item).
func style_button(b: Button, variant := "default") -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var accent_soft := BTN_ACCENT
	accent_soft.a = 0.12
	var accent_press := BTN_ACCENT
	accent_press.a = 0.22

	if variant == "menu":
		var empty := StyleBoxFlat.new()
		empty.bg_color = Color(0, 0, 0, 0)
		empty.content_margin_left = 14
		empty.content_margin_right = 14
		empty.content_margin_top = 8
		empty.content_margin_bottom = 8
		b.add_theme_stylebox_override("normal", empty)
		b.add_theme_stylebox_override("focus", empty)
		b.add_theme_stylebox_override("disabled", empty)
		b.add_theme_stylebox_override("hover", _btn_box(accent_soft, BTN_ACCENT, 0, 10, 14, 8, 8))
		b.add_theme_stylebox_override("pressed", _btn_box(accent_press, BTN_ACCENT, 0, 10, 14, 10, 6))
		b.add_theme_color_override("font_color", BTN_INK)
		b.add_theme_color_override("font_hover_color", BTN_ACCENT)
		b.add_theme_color_override("font_pressed_color", BTN_ACCENT)
		b.add_theme_color_override("font_focus_color", BTN_INK)
	else:
		b.add_theme_stylebox_override("normal", _btn_box(BTN_WHITE, BTN_INK, 2, 8, 18, 10, 10))
		b.add_theme_stylebox_override("hover", _btn_box(BTN_HOVER, BTN_ACCENT, 2, 8, 18, 10, 10))
		b.add_theme_stylebox_override("pressed", _btn_box(BTN_ACCENT, BTN_ACCENT, 2, 8, 18, 12, 8))
		b.add_theme_stylebox_override("focus", _btn_box(BTN_WHITE, BTN_INK, 2, 8, 18, 10, 10))
		b.add_theme_color_override("font_color", BTN_INK)
		b.add_theme_color_override("font_hover_color", BTN_ACCENT)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_focus_color", BTN_INK)
