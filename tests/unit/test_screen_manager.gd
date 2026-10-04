extends GutTest
## Unit tests for the Screen responsive-layout adapter (pure math + flags).

const ScreenScript := preload("res://scripts/autoload/screen_manager.gd")

func _make_screen() -> Node:
	# A bare instance (not the autoload) so window_size can be set directly.
	return ScreenScript.new()

func test_compute_scale_is_limited_by_smaller_dimension() -> void:
	assert_almost_eq(ScreenScript.compute_scale(Vector2(1600, 1000)), 1.0, 0.0001)
	assert_almost_eq(ScreenScript.compute_scale(Vector2(1366, 768)), 0.768, 0.0001)
	# A very wide window is limited by height; a very tall one by width.
	assert_almost_eq(ScreenScript.compute_scale(Vector2(3200, 1000)), 1.0, 0.0001)
	assert_almost_eq(ScreenScript.compute_scale(Vector2(1600, 2000)), 1.0, 0.0001)
	assert_almost_eq(ScreenScript.compute_scale(Vector2(100, 100)), 0.0625, 0.0001)

func test_world_scale_tracks_reference_view_on_large_windows() -> void:
	# Same course area per inch as the 1600x1000 reference design...
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(1600, 1000)), 1.0, 0.0001)
	# ...and scaled up proportionally on bigger desktops.
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(1920, 1080)), 1.08, 0.001)
	# 1366x768 matches the old fixed-viewport stretch factor exactly.
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(1366, 768)), 0.768, 0.001)
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(2560, 1440)), 1.44, 0.001)

func test_world_scale_never_shrinks_tiles_below_design_size() -> void:
	# Phones and tablets keep 1:1 pixel scale so tiles stay tappable.
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(390, 844)), 1.0, 0.0001)
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(768, 1024)), 1.0, 0.0001)
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(834, 1194)), 1.0, 0.0001)
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(1024, 768)), 0.879, 0.001)
	# Degenerate (test) sizes never go below 1.0.
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(64, 64)), 1.0, 0.0001)

func test_world_scale_is_scale_clamped_by_narrow_window_floor() -> void:
	# world_scale = max(scale, min(1, 900/width))
	for width in [500.0, 768.0, 900.0, 1200.0, 1600.0, 2560.0]:
		var size := Vector2(width, 1000.0)
		var expected: float = maxf(ScreenScript.compute_scale(size), minf(1.0, 900.0 / width))
		assert_almost_eq(ScreenScript.compute_world_scale(size), expected, 0.0001)

func test_compact_flags() -> void:
	var s := _make_screen()
	s.window_size = Vector2(1600, 1000)
	assert_false(s.is_compact())
	assert_false(s.is_portrait())
	assert_true(s.is_landscape())

	s.window_size = Vector2(390, 844)  # Phone portrait
	assert_true(s.is_compact())
	assert_true(s.is_portrait())
	assert_false(s.is_landscape())

	s.window_size = Vector2(812, 375)  # Phone landscape: short window
	assert_true(s.is_compact())
	assert_true(s.is_landscape())

	s.window_size = Vector2(1024, 768)  # Tablet: wide enough, tall enough
	assert_false(s.is_compact())
	s.window_size = Vector2(1024, 600)  # but short windows stay compact
	assert_true(s.is_compact())

func test_apply_size_emits_changed_only_when_values_move() -> void:
	var s := _make_screen()
	var emissions: Array = []
	s.changed.connect(func(size: Vector2, ws: float): emissions.append([size, ws]))
	s.window_size = Vector2(1600, 1000)
	s.world_scale = 1.0
	s.apply_size(Vector2(1600, 1000))
	assert_eq(emissions.size(), 0, "same size + scale must not emit")
	s.apply_size(Vector2(390, 844))
	assert_eq(emissions.size(), 1)
	assert_eq(emissions[0][1], 1.0)
	s.apply_size(Vector2(1920, 1080))
	assert_eq(emissions.size(), 2)
	assert_almost_eq(emissions[1][1], 1.08, 0.001)

func test_available_panel_size_stays_clear_of_bottom_bar() -> void:
	var s := _make_screen()
	s.window_size = Vector2(1600, 1000)
	assert_eq(s.available_panel_size(), Vector2(1568, 1000 - 24 - 198))
	s.window_size = Vector2(390, 844)
	assert_eq(s.available_panel_size(), Vector2(358, 844 - 24 - 198))
	# Tiny windows get a usable floor, not a negative size.
	s.window_size = Vector2(64, 64)
	assert_eq(s.available_panel_size(), Vector2(120, 120))

func test_bottom_bar_height_is_the_ui_constant() -> void:
	var s := _make_screen()
	# bottom_bar_height() is a float, the constant is an int: compare as floats
	# so GUT does not flag the type mismatch.
	assert_eq(s.bottom_bar_height(), float(UIConstants.BOTTOM_BAR_HEIGHT))
	assert_almost_eq(s.hud_bottom_clearance(), UIConstants.BOTTOM_BAR_HEIGHT + 8.0, 0.001)
