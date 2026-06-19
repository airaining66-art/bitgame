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

var _term_label: Label
var _term_t := 0.0


func _ready() -> void:
	var app = get_node_or_null("/root/App")
	if app:
		theme = app.ui_theme

	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var levels: Array = app.levels if app else []
	for i in NODE_POS.size():
		var lvl_name := str(levels[i]["name"]) if i < levels.size() else ""
		var lvl_id := str(levels[i]["id"]) if i < levels.size() else "1-%d" % (i + 1)
		var unlocked := bool(levels[i]["unlocked"]) if i < levels.size() else (i == 0)
		_add_node(i, NODE_POS[i], lvl_name, lvl_id, unlocked)

	_build_terminal()

	var hint := Label.new()
	hint.text = "ESC 返回标题"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", COL_LOCKED)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(16, -34)
	add_child(hint)

	queue_redraw()


func _process(delta: float) -> void:
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
		var btn := Button.new()
		btn.flat = true
		btn.size = Vector2(220, 100)
		btn.position = center + Vector2(-110, -66)
		var empty := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(s, empty)
		btn.pressed.connect(func() -> void:
			var app = get_node_or_null("/root/App")
			if app:
				app.play_level(index))
		add_child(btn)


func _build_terminal() -> void:
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.BLACK
	box.add_theme_stylebox_override("panel", sb)
	box.size = Vector2(150, 120)
	box.position = NODE_POS[0] + Vector2(-65, 30)
	add_child(box)

	_term_label = Label.new()
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
