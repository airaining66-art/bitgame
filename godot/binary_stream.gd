class_name BinaryStream
extends Control
## Background binary animation (the level's story flavour). Types one digit per
## beat, left to right like a terminal, with a blinking cursor. The colour
## records the player's outcome — gold = clean hit, red = miss / wrong,
## dim = neutral. Pure error-rate visualisation, decoupled from everything else.

const MAX_DIGITS := 42        # trimmed from the front so the newest stays on screen
const FONT_SIZE := 40

const COL_NEUTRAL := Color(0.42, 0.40, 0.36, 0.5)
const COL_GOLD := Color("f6b800")
const COL_RED := Color("d71920")

var _rich: RichTextLabel
var _entries: Array = []       # [{ch, hex}]
var _cursor_on := true
var _cursor_t := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rich = RichTextLabel.new()
	_rich.bbcode_enabled = true
	_rich.scroll_active = false
	_rich.fit_content = false
	_rich.autowrap_mode = TextServer.AUTOWRAP_OFF  # single line, never wraps
	_rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rich.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_rich.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rich.offset_left = 18
	_rich.offset_right = -18
	_rich.offset_top = 84           # nudge down toward the top-lane center
	add_child(_rich)
	_render()


func _process(delta: float) -> void:
	_cursor_t += delta
	if _cursor_t >= 0.5:
		_cursor_t = 0.0
		_cursor_on = not _cursor_on
		_render()


func clear() -> void:
	_entries.clear()
	_render()


## outcome: "hit" | "miss" | "wrong" | "skip" | "neutral"
func push(bit: int, outcome: String) -> void:
	var col := COL_NEUTRAL
	match outcome:
		"hit": col = COL_GOLD
		"miss", "wrong": col = COL_RED
	_entries.append({"ch": str(bit), "hex": col.to_html(true)})
	if _entries.size() > MAX_DIGITS:
		_entries.pop_front()
	_render()


func _render() -> void:
	var s := ""
	for e in _entries:
		s += "[color=#%s]%s[/color]" % [e["hex"], e["ch"]]
	if _cursor_on:
		s += "[color=#%s]_[/color]" % COL_NEUTRAL.to_html(true)
	_rich.text = s
