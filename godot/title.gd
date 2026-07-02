extends Control


func _ready() -> void:
	var app = get_node_or_null("/root/App")
	if app:
		theme = app.ui_theme

	var start_button := get_node_or_null("StartButton") as BaseButton
	if start_button:
		start_button.pressed.connect(_on_levels)

	var exit_button := get_node_or_null("ExitButton") as BaseButton
	if exit_button:
		exit_button.pressed.connect(_on_quit)


func _on_levels() -> void:
	var app = get_node_or_null("/root/App")
	if app:
		app.goto_levels()


func _on_quit() -> void:
	get_tree().quit()
