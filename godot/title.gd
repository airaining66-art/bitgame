extends Control
## Title screen: game name, menu (关卡选择 / 退出游戏), and the signature
## hand-drawn red push button at the bottom (press it to enter level select).

const COL_BG := Color("f5f5f2")
const COL_INK := Color("21170d")
const COL_ACCENT := Color("d71920")
const COL_GOLD := Color("f6b800")


func _ready() -> void:
	var app = get_node_or_null("/root/App")
	if app:
		theme = app.ui_theme

	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var title := Label.new()
	title.text = "动次打次"
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", COL_INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 120
	add_child(title)

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 18)
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.position = Vector2(-110, -40)
	menu.custom_minimum_size = Vector2(220, 0)
	add_child(menu)
	menu.add_child(_menu_button("关卡选择", _on_levels))
	menu.add_child(_menu_button("退出游戏", _on_quit))

	var btn := RedButton.new()
	btn.on_press = _on_levels
	btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	btn.position = Vector2(-140, -210)
	add_child(btn)


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 38)
	var app = get_node_or_null("/root/App")
	if app:
		app.style_button(b, "menu")
	b.pressed.connect(cb)
	return b


func _on_levels() -> void:
	var app = get_node_or_null("/root/App")
	if app:
		app.goto_levels()


func _on_quit() -> void:
	get_tree().quit()


# ---------------------------------------------------------------------------
# Hand-drawn red arcade button, drawn with primitives + a sketchy stand.
# ---------------------------------------------------------------------------
class RedButton:
	extends Control

	const BODY := Color("d71920")
	const BODY_DARK := Color("9c1016")
	const TOP := Color("e8242b")
	const TOP_HOVER := Color("ff3b42")
	const OUTLINE := Color("141414")

	var on_press := Callable()
	var pressed_down := false
	var hovering := false

	func _ready() -> void:
		custom_minimum_size = Vector2(280, 210)
		size = custom_minimum_size
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void:
			hovering = true
			queue_redraw())
		mouse_exited.connect(func() -> void:
			hovering = false
			queue_redraw())

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				pressed_down = true
				queue_redraw()
			elif pressed_down:
				pressed_down = false
				queue_redraw()
				if on_press.is_valid():
					on_press.call()

	func _ellipse(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 44:
			var a := TAU * i / 44.0
			pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
		return pts

	func _outline(pts: PackedVector2Array, col: Color, w: float) -> void:
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, col, w, true)

	func _draw() -> void:
		# Sketchy stand (a few jittered strokes).
		var stand := PackedVector2Array([
			Vector2(46, 150), Vector2(234, 150),
			Vector2(214, 200), Vector2(66, 200), Vector2(46, 150),
		])
		draw_polyline(stand, OUTLINE, 3.0, true)
		draw_line(Vector2(70, 165), Vector2(210, 167), OUTLINE, 2.0)

		var cx := 140.0
		var rx := 86.0
		var ry := 34.0
		var top_y := 78.0 + (10.0 if pressed_down else 0.0)
		var bottom_y := 132.0

		# Cylinder body.
		_outline(_ellipse(Vector2(cx, bottom_y), rx, ry), OUTLINE, 5.0)
		draw_colored_polygon(_ellipse(Vector2(cx, bottom_y), rx, ry), BODY_DARK)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - rx, top_y), Vector2(cx + rx, top_y),
			Vector2(cx + rx, bottom_y), Vector2(cx - rx, bottom_y),
		]), BODY)
		draw_line(Vector2(cx - rx, top_y), Vector2(cx - rx, bottom_y), OUTLINE, 5.0)
		draw_line(Vector2(cx + rx, top_y), Vector2(cx + rx, bottom_y), OUTLINE, 5.0)

		# Red cap (brighter on hover).
		var cap := _ellipse(Vector2(cx, top_y), rx, ry)
		draw_colored_polygon(cap, TOP_HOVER if (hovering and not pressed_down) else TOP)
		_outline(cap, OUTLINE, 6.0)
