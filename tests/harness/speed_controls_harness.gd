extends Node
## Run: godot --headless --path . res://tests/harness/speed_controls_harness.tscn
##
## Fast (3x) and Ultra (8x) share one fast-forward button. This drives the real
## buttons in the real main scene through real input — no stand-ins — so the
## wiring, the button face, the tooltip and the highlight are all exercised.

var viewport: SubViewport
var main: Node2D
var failures := 0

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 1000)
	viewport.handle_input_locally = true
	add_child(viewport)
	main = load("res://scenes/main/main.tscn").instantiate()
	viewport.add_child(main)
	_run.call_deferred()

func _check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
	print("SPEED: %s: %s" % ["PASS" if ok else "FAIL", description])

## Click a speed-control button the way a player does.
func _click(button: Button) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	viewport.push_input(motion, true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = motion.position
	click.pressed = true
	viewport.push_input(click, true)
	click.pressed = false
	viewport.push_input(click, true)
	await get_tree().process_frame
	await get_tree().process_frame

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	# Drop the main menu so the speed controls are visible and take input.
	main.main_menu.queue_free()
	main.main_menu = null
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	main._set_gameplay_ui_visible(true)
	await get_tree().process_frame
	await get_tree().process_frame

	var buttons: Array = []
	for child in main.speed_controls.get_children():
		buttons.append(String(child.name))
	_check(buttons == ["PauseBtn", "PlayBtn", "FastBtn"],
			"Speed controls hold exactly pause, play and one fast-forward button (%s)" % str(buttons))
	_check(main.speed_controls.get_node_or_null("UltraBtn") == null,
			"No separate ULTRA button is created")

	# Idle: the toggle advertises the tier it starts at, and stays dimmed.
	_check(main.fast_btn.text == ">>", "Idle fast-forward button reads >> (got '%s')" % main.fast_btn.text)
	_check(main.fast_btn.modulate.a < 1.0, "Idle fast-forward button is dimmed")
	_check("Fast (3x)" in main.fast_btn.tooltip_text and "Ultra (8x)" in main.fast_btn.tooltip_text,
			"Idle tooltip teaches both tiers (got '%s')" % main.fast_btn.tooltip_text)

	# First press: Fast, and the shared button lights up.
	await _click(main.fast_btn)
	_check(GameManager.current_speed == GameManager.GameSpeed.FAST,
			"First press runs at Fast (3x)")
	_check(Engine.time_scale == 3.0, "Fast press scales the engine to 3.0 (got %s)" % Engine.time_scale)
	_check(main.fast_btn.text == ">>", "Fast keeps the >> face")
	_check(main.fast_btn.modulate.a == 1.0, "The shared button lights up while Fast runs")
	_check("Ultra (8x)" in main.fast_btn.tooltip_text,
			"Fast tooltip offers Ultra next (got '%s')" % main.fast_btn.tooltip_text)

	# Second press: Ultra on the very same button.
	await _click(main.fast_btn)
	_check(GameManager.current_speed == GameManager.GameSpeed.ULTRA,
			"Second press runs at Ultra (8x)")
	_check(Engine.time_scale == 8.0, "Ultra press scales the engine to 8.0 (got %s)" % Engine.time_scale)
	_check(main.fast_btn.text == ">>>", "Ultra reads >>> (got '%s')" % main.fast_btn.text)
	_check(main.fast_btn.modulate.a == 1.0, "The shared button stays lit at Ultra")
	_check("Fast (3x)" in main.fast_btn.tooltip_text,
			"Ultra tooltip offers Fast next (got '%s')" % main.fast_btn.tooltip_text)

	# Third press: back to Fast — the toggle never escapes the two tiers.
	await _click(main.fast_btn)
	_check(GameManager.current_speed == GameManager.GameSpeed.FAST,
			"Third press drops back to Fast")
	_check(Engine.time_scale == 3.0, "Back to Fast scales the engine to 3.0")
	_check(main.fast_btn.text == ">>", "Fast reads >> again")

	# Pause and play still own their own buttons and clear the highlight.
	await _click(main.pause_btn)
	_check(GameManager.current_speed == GameManager.GameSpeed.PAUSED, "Pause button still pauses")
	_check(Engine.time_scale == 0.0, "Pause freezes the engine")
	_check(main.fast_btn.text == ">>" and main.fast_btn.modulate.a < 1.0,
			"Paused toggle is dimmed and advertises Fast")

	await _click(main.play_btn)
	_check(GameManager.current_speed == GameManager.GameSpeed.NORMAL, "Play button still resumes at 1x")
	_check(Engine.time_scale == 1.0, "Play resumes at real time")

	print("SPEED: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
