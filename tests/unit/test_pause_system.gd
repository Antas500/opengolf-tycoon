extends GutTest
## Tests for the pause system — Pause button (speed controls) and Pause menu
## must actually freeze the game, not just stop the clock.
##
## GameManager._sync_time_scale() keeps Engine.time_scale in sync:
##   - non-simulation modes (main menu, build) run at real-time speed (1.0)
##   - is_paused == true OR current_speed == PAUSED freezes everything (0.0)
##   - otherwise the scale is the speed multiplier (1 / 3 / 8)


func after_each() -> void:
	# Leave the singleton in a clean, unpaused state for other tests
	GameManager.is_paused = false
	GameManager.set_mode(GameManager.GameMode.MAIN_MENU)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)


# --- Pause button (speed controls) ---

func test_speed_paused_freezes_the_engine() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	assert_eq(Engine.time_scale, 1.0, "Normal speed should run at 1x")

	GameManager.set_speed(GameManager.GameSpeed.PAUSED)
	assert_eq(Engine.time_scale, 0.0, "PAUSED speed must freeze the engine (delta = 0)")

func test_speed_resume_restores_prior_speed() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.ULTRA)
	assert_eq(Engine.time_scale, 8.0, "Ultra speed should run at 8x")

	GameManager.set_speed(GameManager.GameSpeed.PAUSED)
	assert_eq(Engine.time_scale, 0.0, "Pause button must freeze the game")

	GameManager.set_speed(GameManager.GameSpeed.ULTRA)
	assert_eq(Engine.time_scale, 8.0, "Resuming must restore the previous speed")

func test_speed_normal_after_pause_runs_at_one() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.PAUSED)
	assert_eq(Engine.time_scale, 0.0)

	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	assert_eq(Engine.time_scale, 1.0, "Play button must resume at 1x")


# --- Pause flag (pause menu, end-of-day summary, game over) ---

func test_is_paused_freezes_the_engine() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	assert_eq(Engine.time_scale, 1.0)

	GameManager.is_paused = true
	assert_eq(Engine.time_scale, 0.0, "is_paused (pause menu) must freeze the engine")

	GameManager.is_paused = false
	assert_eq(Engine.time_scale, 1.0, "Unpausing must restore the previous speed")

func test_is_paused_keeps_prior_speed_intact() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.FAST)

	GameManager.is_paused = true
	assert_eq(Engine.time_scale, 0.0, "Paused game must freeze even at fast speed")
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.FAST,
		"Pausing via the menu must not change the selected speed")

	GameManager.is_paused = false
	assert_eq(Engine.time_scale, 3.0, "Resume must restore the fast speed")

func test_double_set_is_paused_is_idempotent() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)

	GameManager.is_paused = true
	GameManager.is_paused = true
	assert_eq(Engine.time_scale, 0.0)

	GameManager.is_paused = false
	GameManager.is_paused = false
	assert_eq(Engine.time_scale, 1.0)

func test_toggle_pause_flips_freeze_state() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)

	GameManager.toggle_pause()
	assert_true(GameManager.is_paused)
	assert_eq(Engine.time_scale, 0.0, "toggle_pause must freeze the engine")

	GameManager.toggle_pause()
	assert_false(GameManager.is_paused)
	assert_eq(Engine.time_scale, 1.0, "toggle_pause again must resume")


# --- Combined state ---

func test_speed_pause_then_menu_pause_then_resume() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)

	# User hits the || button (speed PAUSED, is_paused untouched)
	GameManager.set_speed(GameManager.GameSpeed.PAUSED)
	assert_eq(Engine.time_scale, 0.0)
	assert_false(GameManager.is_paused)

	# Then opens the pause menu (is_paused = true, speed still PAUSED)
	GameManager.is_paused = true
	assert_eq(Engine.time_scale, 0.0)

	# Resuming from the menu only clears is_paused — the speed is still
	# PAUSED, so the game must stay frozen (the || button is still highlighted)
	GameManager.is_paused = false
	assert_eq(Engine.time_scale, 0.0, "Game stays paused while speed is still PAUSED")

	# Finally the user clicks Play
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	assert_eq(Engine.time_scale, 1.0)

func test_menu_pause_then_speed_pause_then_resume() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)

	# User opens the pause menu (is_paused = true)
	GameManager.is_paused = true
	assert_eq(Engine.time_scale, 0.0)

	# Closes the menu via Resume
	GameManager.is_paused = false
	assert_eq(Engine.time_scale, 1.0, "Resume must restore play")


# --- Mode interactions ---

func test_main_menu_runs_at_real_time() -> void:
	GameManager.set_mode(GameManager.GameMode.MAIN_MENU)
	GameManager.set_speed(GameManager.GameSpeed.ULTRA)
	assert_eq(Engine.time_scale, 1.0, "Main menu must not run at simulation speed")

func test_new_simulation_mode_uses_current_speed() -> void:
	GameManager.set_mode(GameManager.GameMode.MAIN_MENU)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	assert_eq(Engine.time_scale, 1.0)

	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	assert_eq(Engine.time_scale, 1.0, "Entering simulation must run at the selected speed")


# --- Speed multiplier helper ---

func test_get_game_speed_multiplier_reports_zero_when_paused() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	assert_eq(GameManager.get_game_speed_multiplier(), 1.0)

	GameManager.set_speed(GameManager.GameSpeed.PAUSED)
	assert_eq(GameManager.get_game_speed_multiplier(), 0.0,
		"Speed PAUSED must report a zero multiplier")
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)

	GameManager.is_paused = true
	assert_eq(GameManager.get_game_speed_multiplier(), 0.0,
		"is_paused must report a zero multiplier")
