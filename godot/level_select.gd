extends Control
## Level-select map: a hand-drawn dashed path winding between the six level
## nodes, a little ship marker, and 1-1's binary terminal. Only 1-1 is
## playable for now; the rest are shown but locked.

const COL_BG := Color("f5f5f2")
const COL_INK := Color("21170d")
const COL_LOCKED := Color("b8b6b0")
const COL_ACCENT := Color("d71920")
const COL_TERM_GREEN := Color("33ff66")

# Node centers, roughly matching the reference sketch (1280x720).
const NODE_POS := [
	Vector2(300, 235),   # 1-1
	Vector2(605, 320),   # 1-2
	Vector2(975, 215),   # 1-3
	Vector2(1035, 545),  # 1-4
	Vector2(615, 470),   # 1-5
	Vector2(255, 600),   # 1-6
]
const SHIP_POS := Vector2(64, 430)

## Mango "being eaten" sheet (5 frames of 150px). Looped on the level buttons.
const MANGO_FRAMES := [0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 4, 4, 3, 2, 1]

var _term_label: Label
var _term_t := 0.0
var _mango_tex: Texture2D
var _anim_t := 0.0
var _unlocked: Array = []
var _armed := false   # ignore clicks for a moment so a leftover release from
                      # the previous scene can't immediately launch a level


func _ready() -> void:
	var app = get_node_or_null("/root/App")
	if app:
		theme = app.ui_theme

	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_mango_tex = _load_tex("res://assets/mango.png")
	# Terminal first so it sits BEHIND the level nodes/buttons (it used to cover
	# and block 1-1's Extreme button).
	_build_terminal()
	var levels: Array = app.levels if app else []
	for i in NODE_POS.size():
		var lvl_name := str(levels[i]["name"]) if i < levels.size() else ""
		var lvl_id := str(levels[i]["id"]) if i < levels.size() else "1-%d" % (i + 1)
		var unlocked := bool(levels[i]["unlocked"]) if i < levels.size() else (i == 0)
		_unlocked.append(unlocked)
		_add_node(i, NODE_POS[i], lvl_name, lvl_id, unlocked)

	var hint := Label.new()
	hint.text = "ESC 返回标题"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", COL_LOCKED)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(16, -34)
	add_child(hint)

	queue_redraw()
	get_tree().create_timer(0.25).timeout.connect(func() -> void: _armed = true)


func _process(delta: float) -> void:
	_anim_t += delta
	queue_redraw()   # animate the mango icons
	# Keep the binary terminal alive.
	_term_t += delta
	if _term_t >= 0.35:
		_term_t = 0.0
		_term_label.text = _binary_rows()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var app = get_node_or_null("/root/App")
		if app:
			app.goto_title()


# ---------------------------------------------------------------------------
func _add_node(index: int, center: Vector2, lvl_name: String, lvl_id: String, unlocked: bool) -> void:
	var col := COL_INK if unlocked else COL_LOCKED

	var name_lbl := Label.new()
	name_lbl.text = lvl_name
	name_lbl.add_theme_font_size_override("font_size", 28)
	name_lbl.add_theme_color_override("font_color", col)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	name_lbl.size = Vector2(220, 38)
	name_lbl.position = center + Vector2(-110, -66)
	add_child(name_lbl)

	var id_lbl := Label.new()
	id_lbl.text = lvl_id
	id_lbl.add_theme_font_size_override("font_size", 52)
	id_lbl.add_theme_color_override("font_color", col)
	id_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	id_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	id_lbl.size = Vector2(220, 60)
	id_lbl.position = center + Vector2(-110, -28)
	add_child(id_lbl)

	if unlocked:
		id_lbl.pivot_offset = id_lbl.size * 0.5
		name_lbl.pivot_offset = name_lbl.size * 0.5
		var btn := Button.new()
		btn.flat = true
		btn.size = Vector2(220, 100)
		btn.position = center + Vector2(-110, -66)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(s, empty)
		# Hover / press feedback animates the level node itself.
		btn.mouse_entered.connect(func() -> void: _node_hover(id_lbl, name_lbl, true))
		btn.mouse_exited.connect(func() -> void: _node_hover(id_lbl, name_lbl, false))
		btn.button_down.connect(func() -> void: _node_scale(id_lbl, name_lbl, 0.92))
		btn.button_up.connect(func() -> void: _node_scale(id_lbl, name_lbl, 1.14))
		btn.pressed.connect(func() -> void:
			var app = get_node_or_null("/root/App")
			if app and _armed:
				app.play_level(index))
		add_child(btn)

		# Extreme-mode button appears once the level is 3-star cleared.
		var app2 = get_node_or_null("/root/App")
		if app2 and app2.is_3star(index):
			var ex := Button.new()
			ex.text = "极限 1.5×"
			ex.custom_minimum_size = Vector2(120, 38)
			ex.position = center + Vector2(-60, 40)
			ex.add_theme_font_size_override("font_size", 18)
			var ec := StyleBoxFlat.new()
			ec.bg_color = Color("3a0c0c")
			ec.set_border_width_all(2)
			ec.border_color = COL_ACCENT
			ec.set_corner_radius_all(8)
			ex.add_theme_stylebox_override("normal", ec)
			var eh := ec.duplicate()
			eh.bg_color = COL_ACCENT
			ex.add_theme_stylebox_override("hover", eh)
			ex.add_theme_stylebox_override("pressed", eh)
			ex.add_theme_color_override("font_color", COL_ACCENT)
			ex.add_theme_color_override("font_hover_color", Color.WHITE)
			ex.focus_mode = Control.FOCUS_NONE
			ex.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			ex.pressed.connect(func() -> void:
				var app = get_node_or_null("/root/App")
				if app and _armed:
					app.play_level(index, true))
			add_child(ex)


func _node_hover(id_lbl: Label, name_lbl: Label, on: bool) -> void:
	var col := COL_ACCENT if on else COL_INK
	id_lbl.add_theme_color_override("font_color", col)
	name_lbl.add_theme_color_override("font_color", col)
	_node_scale(id_lbl, name_lbl, 1.14 if on else 1.0)


func _node_scale(id_lbl: Label, name_lbl: Label, to: float) -> void:
	var tw := create_tween().set_parallel()
	tw.tween_property(id_lbl, "scale", Vector2.ONE * to, 0.1)
	tw.tween_property(name_lbl, "scale", Vector2.ONE * to, 0.1)


func _build_terminal() -> void:
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.BLACK
	box.add_theme_stylebox_override("panel", sb)
	box.size = Vector2(150, 120)
	box.position = NODE_POS[0] + Vector2(-65, 30)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE   # decorative — never block clicks
	add_child(box)

	_term_label = Label.new()
	_term_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_term_label.add_theme_font_size_override("font_size", 16)
	_term_label.add_theme_color_override("font_color", COL_TERM_GREEN)
	_term_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_term_label.offset_left = 8
	_term_label.offset_top = 6
	_term_label.text = _binary_rows()
	box.add_child(_term_label)


func _binary_rows() -> String:
	var rows := PackedStringArray()
	for r in 5:
		var s := ""
		for c in 10:
			s += "1" if randf() < 0.5 else "0"
		rows.append(s)
	return "\n".join(rows)


# ---------------------------------------------------------------------------
func _draw() -> void:
	# Dashed path through the nodes, with a tail toward the ship.
	for i in NODE_POS.size() - 1:
		_dashed(NODE_POS[i], NODE_POS[i + 1])
	_dashed(NODE_POS[5], Vector2(40, 545))

	# Ship marker (stylised, pointing left).
	draw_colored_polygon(PackedVector2Array([
		SHIP_POS + Vector2(-34, 0),
		SHIP_POS + Vector2(30, -28),
		SHIP_POS + Vector2(14, 0),
		SHIP_POS + Vector2(30, 28),
	]), COL_INK)

	# Animated mango on every level node (the button graphic).
	for i in NODE_POS.size():
		var on: bool = _unlocked[i] if i < _unlocked.size() else (i == 0)
		_mango_icon(NODE_POS[i] + Vector2(0, -104), on)


func _mango_icon(center: Vector2, unlocked: bool) -> void:
	var s := 84.0
	if _mango_tex:
		var frame: int = MANGO_FRAMES[int(_anim_t * 9.0) % MANGO_FRAMES.size()]
		var a := 1.0 if unlocked else 0.4
		draw_texture_rect_region(_mango_tex, Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s)),
			Rect2(frame * 150, 0, 150, 150), Color(1, 1, 1, a))
	else:
		var body := PackedVector2Array()
		for i in 26:
			var ang := TAU * i / 26.0
			body.append(center + Vector2(cos(ang) * 30.0, sin(ang) * 22.0))
		draw_colored_polygon(body, Color("f3c200"))


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			return ImageTexture.create_from_image(img)
	return null


func _dashed(a: Vector2, b: Vector2, dash := 20.0, gap := 14.0, width := 7.0) -> void:
	var dir := (b - a)
	var length := dir.length()
	if length < 0.01:
		return
	dir = dir / length
	var d := 0.0
	while d < length:
		var s := a + dir * d
		var e := a + dir * minf(d + dash, length)
		draw_line(s, e, COL_INK, width)
		d += dash + gap
