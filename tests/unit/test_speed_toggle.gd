extends GutTest
## Tests for the combined fast-forward button in the speed controls.
##
## Fast (3x) and Ultra (8x) used to sit on two separate buttons at the bottom
## of the screen. They now share one toggle that steps between the tiers:
## GameManager owns the cycling, and Main derives the button's face and tooltip
## from the tier that is currently running.

const GameManagerScript := preload("res://scripts/autoload/game_manager.gd")
const MainScript := preload("res://scripts/main/main.gd")


func after_each() -> void:
	# Leave the singleton in a clean state for the tests that follow.
	GameManager.is_paused = false
	GameManager.set_mode(GameManager.GameMode.MAIN_MENU)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)


# --- Cycling logic ---

func test_first_press_from_normal_enters_fast() -> void:
	assert_eq(GameManagerScript.next_fast_forward_speed(GameManager.GameSpeed.NORMAL),
			GameManager.GameSpeed.FAST,
			"One press from normal speed starts at Fast (3x)")

func test_first_press_from_paused_enters_fast() -> void:
	assert_eq(GameManagerScript.next_fast_forward_speed(GameManager.GameSpeed.PAUSED),
			GameManager.GameSpeed.FAST,
			"The toggle unpauses into Fast, never straight into the 8x tier")

func test_repeated_presses_swap_between_fast_and_ultra() -> void:
	var speed: int = GameManager.GameSpeed.NORMAL
	var visited: Array = []
	for _press in 4:
		speed = GameManagerScript.next_fast_forward_speed(speed)
		visited.append(speed)
	assert_eq(visited,
			[GameManager.GameSpeed.FAST, GameManager.GameSpeed.ULTRA,
			GameManager.GameSpeed.FAST, GameManager.GameSpeed.ULTRA],
			"Pressing the one button alternates Fast and Ultra forever")

func test_only_the_two_tiers_belong_to_the_toggle() -> void:
	assert_true(GameManagerScript.is_fast_forward_speed(GameManager.GameSpeed.FAST),
			"Fast is a fast-forward tier")
	assert_true(GameManagerScript.is_fast_forward_speed(GameManager.GameSpeed.ULTRA),
			"Ultra is a fast-forward tier")
	assert_false(GameManagerScript.is_fast_forward_speed(GameManager.GameSpeed.NORMAL),
			"Normal speed belongs to the play button")
	assert_false(GameManagerScript.is_fast_forward_speed(GameManager.GameSpeed.PAUSED),
			"Paused belongs to the pause button")


# --- Effect of a press ---

func test_cycle_applies_the_tier_it_switches_to() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)

	GameManager.cycle_fast_forward_speed()
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.FAST)
	assert_eq(Engine.time_scale, 3.0, "Fast must run the simulation at 3x")

	GameManager.cycle_fast_forward_speed()
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.ULTRA)
	assert_eq(Engine.time_scale, 8.0, "Ultra must run the simulation at 8x")

	GameManager.cycle_fast_forward_speed()
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.FAST,
			"A press at Ultra drops back to Fast")
	assert_eq(Engine.time_scale, 3.0)

func test_cycle_emits_the_speed_change_signal() -> void:
	watch_signals(EventBus)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)

	GameManager.cycle_fast_forward_speed()

	assert_signal_emitted_with_parameters(EventBus, "game_speed_changed",
			[GameManager.GameSpeed.FAST],
			"The toggle drives the same signal as the other speed buttons")


# --- Button face ---

func test_button_face_shows_the_running_tier() -> void:
	assert_eq(MainScript.fast_forward_label(GameManager.GameSpeed.NORMAL), ">>",
			"An idle toggle advertises the Fast tier it starts at")
	assert_eq(MainScript.fast_forward_label(GameManager.GameSpeed.FAST), ">>")
	assert_eq(MainScript.fast_forward_label(GameManager.GameSpeed.ULTRA), ">>>",
			"Ultra keeps the familiar three-chevron face")
	assert_eq(MainScript.fast_forward_label(GameManager.GameSpeed.PAUSED), ">>")

func test_button_tooltip_names_the_tier_a_press_switches_to() -> void:
	var at_fast: String = MainScript.fast_forward_tooltip(GameManager.GameSpeed.FAST)
	assert_string_contains(at_fast, "Fast (3x)", "Tooltip names the running tier")
	assert_string_contains(at_fast, "Ultra (8x)", "Tooltip names where the press goes")

	var at_ultra: String = MainScript.fast_forward_tooltip(GameManager.GameSpeed.ULTRA)
	assert_string_contains(at_ultra, "Ultra (8x)", "Tooltip names the running tier")
	assert_string_contains(at_ultra, "Fast (3x)", "Tooltip names where the press goes")

	var idle: String = MainScript.fast_forward_tooltip(GameManager.GameSpeed.NORMAL)
	assert_string_contains(idle, "Fast (3x)", "Idle tooltip teaches the first press")
	assert_string_contains(idle, "Ultra (8x)", "Idle tooltip teaches the second press")


# --- Button width ---

func test_button_keeps_one_width_across_both_faces() -> void:
	# Sized loose, the two faces measure differently: ">>" fits the button's
	# old 28px slot, ">>>" needs more, and every tier toggle would resize the
	# button and nudge the speed-controls row. The lock sizes it for the widest
	# face once so both faces then claim the same width.
	var button := Button.new()
	button.custom_minimum_size = Vector2(28, 24)
	add_child_autofree(button)

	var widths: Dictionary = {}
	for face in [">>", ">>>"]:
		button.text = face
		widths[face] = button.get_combined_minimum_size().x
	assert_gt(widths[">>>"], widths[">>"],
			"The three-chevron face really is the wider one, so the lock is needed")

	button.custom_minimum_size = Vector2(28, 24)
	MainScript.lock_button_width_to_faces(button, [">>", ">>>"])
	for face in [">>", ">>>"]:
		button.text = face
		assert_eq(button.get_combined_minimum_size().x, widths[">>>"],
				"Locked, the %s face keeps the width of the widest face" % face)

func test_width_lock_keeps_the_face_it_was_given() -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(28, 24)
	button.text = ">>"
	add_child_autofree(button)

	MainScript.lock_button_width_to_faces(button, [">>", ">>>"])
	assert_eq(button.text, ">>", "The lock measures both faces but leaves the face it found")
