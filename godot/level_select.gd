extends Control

const LEVEL_COUNT := 6
const HOVER_SCALE := Vector2(1.08, 1.08)
const PRESS_SCALE := Vector2(0.94, 0.94)
const NORMAL_BRIGHTNESS := 1.0
const NORMAL_SATURATION := 1.0
const HOVER_BRIGHTNESS := 1.16
const HOVER_SATURATION := 1.22
const PRESS_BRIGHTNESS := 0.68
const PRESS_SATURATION := 0.62
const BUTTON_SHADER := """
shader_type canvas_item;

uniform float brightness = 1.0;
uniform float saturation = 1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float gray = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 saturated = mix(vec3(gray), tex.rgb, saturation);
	COLOR = vec4(saturated * brightness, tex.a) * COLOR;
}
"""

var _armed := false
var _level_tweens: Dictionary = {}
var _level_shader: Shader


func _ready() -> void:
	var app = get_node_or_null("/root/App")
	if app:
		theme = app.ui_theme

	_level_shader = Shader.new()
	_level_shader.code = BUTTON_SHADER

	for i in LEVEL_COUNT:
		_setup_level_button(i)

	var exit_button := get_node_or_null("ExitButton") as BaseButton
	if exit_button:
		exit_button.pressed.connect(_goto_title)

	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		_armed = true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_goto_title()


func _goto_title() -> void:
	var app = get_node_or_null("/root/App")
	if app:
		app.goto_title()


func _setup_level_button(index: int) -> void:
	var level_node := get_node_or_null("Cards/Level%d" % [index + 1])
	if not level_node:
		return

	var app = get_node_or_null("/root/App")
	var levels: Array = app.levels if app else []
	var unlocked := bool(levels[index]["unlocked"]) if index < levels.size() else index == 0

	var art := level_node.get_node_or_null("Art") as TextureRect
	if art:
		var normal: Variant = art.get_meta("normal_texture", null)
		var locked: Variant = art.get_meta("locked_texture", null)
		var tex: Variant = normal if unlocked else locked
		if tex is Texture2D:
			art.texture = tex
		art.modulate = Color.WHITE if unlocked else Color(1, 1, 1, 0.45)
		if unlocked:
			art.material = _make_level_button_material()

	var level_control := level_node as Control
	if level_control:
		level_control.pivot_offset = level_control.size * 0.5

	var label := level_node.get_node_or_null("Label") as Label
	if label:
		label.modulate = Color.WHITE if unlocked else Color(1, 1, 1, 0.45)

	var button := level_node.get_node_or_null("Button") as Button
	if not button:
		return
	button.disabled = not unlocked
	var state := {"hovering": false}
	button.mouse_entered.connect(func() -> void:
		state["hovering"] = true
		_apply_level_button_state(index, level_control, art, HOVER_SCALE,
			HOVER_BRIGHTNESS, HOVER_SATURATION))
	button.mouse_exited.connect(func() -> void:
		state["hovering"] = false
		_apply_level_button_state(index, level_control, art, Vector2.ONE,
			NORMAL_BRIGHTNESS, NORMAL_SATURATION))
	button.button_down.connect(func() -> void:
		_apply_level_button_state(index, level_control, art, PRESS_SCALE,
			PRESS_BRIGHTNESS, PRESS_SATURATION))
	button.button_up.connect(func() -> void:
		var hovering := bool(state.get("hovering", false))
		_apply_level_button_state(index, level_control, art,
			HOVER_SCALE if hovering else Vector2.ONE,
			HOVER_BRIGHTNESS if hovering else NORMAL_BRIGHTNESS,
			HOVER_SATURATION if hovering else NORMAL_SATURATION))
	button.pressed.connect(func() -> void:
		var app2 = get_node_or_null("/root/App")
		if app2 and _armed:
			app2.play_level(index))


func _apply_level_button_state(index: int, level_node: Control, art: CanvasItem,
		target_scale: Vector2, target_brightness: float, target_saturation: float) -> void:
	if not level_node:
		return

	var old_tween := _level_tweens.get(index) as Tween
	if old_tween:
		old_tween.kill()

	var tw := create_tween().set_parallel()
	_level_tweens[index] = tw
	tw.tween_property(level_node, "scale", target_scale, 0.1).set_trans(Tween.TRANS_SINE)
	if art and art.material is ShaderMaterial:
		var mat := art.material as ShaderMaterial
		tw.tween_property(mat, "shader_parameter/brightness",
			target_brightness, 0.1).set_trans(Tween.TRANS_SINE)
		tw.tween_property(mat, "shader_parameter/saturation",
			target_saturation, 0.1).set_trans(Tween.TRANS_SINE)


func _make_level_button_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _level_shader
	mat.set_shader_parameter("brightness", NORMAL_BRIGHTNESS)
	mat.set_shader_parameter("saturation", NORMAL_SATURATION)
	return mat
