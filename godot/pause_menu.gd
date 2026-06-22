class_name PauseMenu
extends Control
## Reusable in-game pause overlay, shared by every level. Shows a small 暂停
## button during play; pausing dims the screen and offers 继续 / 再来一次 /
## 返回关卡. It owns NO game state — it just emits signals and the level wires
## them (pause/resume the Conductor, restart, go to level select) and gates its
## own input/processing on `is_paused`.

signal request_pause
signal request_resume
signal request_restart
signal request_quit

var is_paused := false
var _app
var pause_btn: Button
var overlay: ColorRect

const INK := Color("21170d")
const ACCENT := Color("d71920")


func _ready() -> void:
	_app = get_node_or_null("/root/App")
	if _app:
		theme = _app.ui_theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # only the button / overlay catch input
	_build_button()
	_build_overlay()


func _build_button() -> void:
	pause_btn = Button.new()
	pause_btn.text = "‖ 暂停"
	pause_btn.custom_minimum_size = Vector2(86, 34)
	pause_btn.add_theme_font_size_override("font_size", 17)
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pause_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	pause_btn.position = Vector2(16, 70)   # tucked under the top-left score readout
	pause_btn.visible = false
	if _app:
		_app.style_button(pause_btn, "default")
	pause_btn.pressed.connect(toggle)
	add_child(pause_btn)


func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.62)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP   # block the game behind while paused
	overlay.visible = false
	add_child(overlay)

	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("fffdf6")
	sb.set_border_width_all(2)
	sb.border_color = INK
	sb.set_corner_radius_all(12)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(360, 360)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.position = Vector2(-180, -180)
	overlay.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 40
	vb.offset_top = 36
	vb.offset_right = -40
	vb.offset_bottom = -36
	card.add_child(vb)

	var title := Label.new()
	title.text = "暂停"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	vb.add_child(_menu_button("继续", func() -> void: resume()))
	vb.add_child(_menu_button("再来一次", func() -> void:
		resume()
		request_restart.emit()))
	vb.add_child(_menu_button("返回关卡", func() -> void:
		request_quit.emit()))


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 56)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	if _app:
		_app.style_button(b, "default")
	return b


# --- API the level uses -----------------------------------------------------
## Show/hide the pause button (call with `phase == "running"` each frame).
func set_active(v: bool) -> void:
	pause_btn.visible = v and not is_paused


func toggle() -> void:
	if is_paused:
		resume()
	else:
		pause()


func pause() -> void:
	if is_paused:
		return
	is_paused = true
	overlay.visible = true
	pause_btn.visible = false
	request_pause.emit()


func resume() -> void:
	if not is_paused:
		return
	is_paused = false
	overlay.visible = false
	request_resume.emit()
