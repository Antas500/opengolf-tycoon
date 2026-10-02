extends GutTest
## Tests for SeasonSystem — theme-aware seasonal modifiers, blending, and helpers.

# --- Season Calculation (calendar quarters from GameCalendar) ---

func test_get_season_winter_covers_january() -> void:
	# Day 1 = 1 Jan 2000 → Winter (Dec-Feb)
	assert_eq(SeasonSystem.get_season(1), SeasonSystem.Season.WINTER)
	assert_eq(SeasonSystem.get_season(31), SeasonSystem.Season.WINTER, "31 Jan still Winter")
	assert_eq(SeasonSystem.get_season(60), SeasonSystem.Season.WINTER, "29 Feb 2000 (leap) still Winter")

func test_get_season_spring_from_march() -> void:
	assert_eq(SeasonSystem.get_season(61), SeasonSystem.Season.SPRING, "1 Mar 2000 = Spring")
	assert_eq(SeasonSystem.get_season(152), SeasonSystem.Season.SPRING, "31 May 2000 still Spring")

func test_get_season_summer_from_june() -> void:
	assert_eq(SeasonSystem.get_season(153), SeasonSystem.Season.SUMMER, "1 Jun 2000 = Summer")
	assert_eq(SeasonSystem.get_season(244), SeasonSystem.Season.SUMMER, "31 Aug 2000 still Summer")

func test_get_season_fall_from_september() -> void:
	assert_eq(SeasonSystem.get_season(245), SeasonSystem.Season.FALL, "1 Sep 2000 = Fall")
	assert_eq(SeasonSystem.get_season(335), SeasonSystem.Season.FALL, "30 Nov 2000 still Fall")

func test_get_season_winter_from_december() -> void:
	assert_eq(SeasonSystem.get_season(336), SeasonSystem.Season.WINTER, "1 Dec 2000 = Winter again")

func test_get_season_wraps_year() -> void:
	assert_eq(SeasonSystem.get_season(366), SeasonSystem.Season.WINTER, "31 Dec 2000 = Winter")
	assert_eq(SeasonSystem.get_season(367), SeasonSystem.Season.WINTER, "1 Jan 2001 = Winter")
	assert_eq(SeasonSystem.get_season(427), SeasonSystem.Season.SPRING, "1 Mar 2001 = Spring")

func test_get_day_in_season() -> void:
	assert_eq(SeasonSystem.get_day_in_season(61), 1, "1 Mar = day 1 of Spring")
	assert_eq(SeasonSystem.get_day_in_season(152), 92, "31 May = last day of Spring (Mar+Apr+May = 92)")
	assert_eq(SeasonSystem.get_day_in_season(153), 1, "1 Jun = day 1 of Summer")
	assert_eq(SeasonSystem.get_day_in_season(1), 32, "1 Jan = day 32 of Winter (Dec 1 = start)")

func test_get_season_length() -> void:
	assert_eq(SeasonSystem.get_season_length(61), 92, "Spring 2000 (Mar-May) = 92 days")
	assert_eq(SeasonSystem.get_season_length(1), 91, "Winter 1999-2000 (Dec-Feb, leap Feb) = 31+31+29 = 91 days")
	assert_eq(SeasonSystem.get_season_length(731), 90, "Winter 2001-2002 (non-leap Feb) = 31+31+28 = 90 days")

func test_get_year() -> void:
	assert_eq(SeasonSystem.get_year(1), 2000)
	assert_eq(SeasonSystem.get_year(366), 2000, "Dec 31, 2000 still year 2000")
	assert_eq(SeasonSystem.get_year(367), 2001)

# --- Theme-Aware Modifiers (enum keys) ---

func test_spawn_modifier_parkland_matches_original() -> void:
	# Parkland is the default/fallback — should match original global values
	var parkland = CourseTheme.Type.PARKLAND
	assert_almost_eq(SeasonSystem.get_spawn_modifier(SeasonSystem.Season.SPRING, parkland), 0.9, 0.01)
	assert_almost_eq(SeasonSystem.get_spawn_modifier(SeasonSystem.Season.SUMMER, parkland), 1.4, 0.01)
	assert_almost_eq(SeasonSystem.get_spawn_modifier(SeasonSystem.Season.FALL, parkland), 0.8, 0.01)
	assert_almost_eq(SeasonSystem.get_spawn_modifier(SeasonSystem.Season.WINTER, parkland), 0.3, 0.01)

func test_spawn_modifier_desert_inverted() -> void:
	# Desert peaks in winter, low in summer (inverted)
	var desert = CourseTheme.Type.DESERT
	assert_almost_eq(SeasonSystem.get_spawn_modifier(SeasonSystem.Season.WINTER, desert), 1.4, 0.01)
	assert_almost_eq(SeasonSystem.get_spawn_modifier(SeasonSystem.Season.SUMMER, desert), 0.3, 0.01)

func test_spawn_modifier_default_falls_back_to_parkland() -> void:
	# No theme (-1) should fall back to Parkland
	assert_almost_eq(SeasonSystem.get_spawn_modifier(SeasonSystem.Season.SUMMER, -1), 1.4, 0.01)
	assert_almost_eq(SeasonSystem.get_spawn_modifier(SeasonSystem.Season.SUMMER), 1.4, 0.01)

func test_maintenance_modifier_theme_aware() -> void:
	var mountain = CourseTheme.Type.MOUNTAIN
	assert_almost_eq(SeasonSystem.get_maintenance_modifier(SeasonSystem.Season.WINTER, mountain), 1.5, 0.01, "Mountain winter = costly")
	var desert = CourseTheme.Type.DESERT
	assert_almost_eq(SeasonSystem.get_maintenance_modifier(SeasonSystem.Season.SUMMER, desert), 0.6, 0.01, "Desert summer = cheap")

func test_all_themes_have_spawn_modifiers() -> void:
	# Every CourseTheme.Type value should have an entry in the spawn table
	for theme_val in range(10):
		for season in range(4):
			var mod = SeasonSystem.get_spawn_modifier(season, theme_val)
			assert_gt(mod, 0.0, "Theme %d season %d should have positive spawn modifier" % [theme_val, season])
			assert_lt(mod, 5.0, "Theme %d season %d spawn modifier should be reasonable" % [theme_val, season])

func test_all_themes_have_maintenance_modifiers() -> void:
	for theme_val in range(10):
		for season in range(4):
			var mod = SeasonSystem.get_maintenance_modifier(season, theme_val)
			assert_gt(mod, 0.0, "Theme %d season %d should have positive maintenance modifier" % [theme_val, season])

# --- Blending at Season Boundaries ---

func test_blended_spawn_mid_season_equals_raw() -> void:
	# Mid-season days should return the raw modifier, no blending
	var parkland = CourseTheme.Type.PARKLAND
	for day in [70, 90, 110, 130]:  # arbitrary days mid-Spring (61..152)
		var raw = SeasonSystem.get_spawn_modifier(SeasonSystem.Season.SPRING, parkland)
		var blended = SeasonSystem.get_blended_spawn_modifier(day, parkland)
		assert_almost_eq(blended, raw, 0.001, "Day %d mid-season should equal raw" % day)

func test_blended_spawn_last_day_of_season() -> void:
	# Day 152 (31 May, last day of Spring): should blend toward Summer
	var parkland = CourseTheme.Type.PARKLAND
	var spring_mod = SeasonSystem.get_spawn_modifier(SeasonSystem.Season.SPRING, parkland)  # 0.9
	var summer_mod = SeasonSystem.get_spawn_modifier(SeasonSystem.Season.SUMMER, parkland)  # 1.4
	var blended = SeasonSystem.get_blended_spawn_modifier(152, parkland)
	var expected = lerpf(spring_mod, summer_mod, SeasonSystem.TRANSITION_BLEND_FACTOR)
	assert_almost_eq(blended, expected, 0.001, "Last day of Spring should blend toward Summer")
	assert_gt(blended, spring_mod, "Blended should be higher than pure Spring")
	assert_lt(blended, summer_mod, "Blended should be lower than pure Summer")

func test_blended_spawn_first_day_of_season() -> void:
	# Day 153 (1 Jun, first day of Summer): should blend toward Spring (previous)
	var parkland = CourseTheme.Type.PARKLAND
	var summer_mod = SeasonSystem.get_spawn_modifier(SeasonSystem.Season.SUMMER, parkland)  # 1.4
	var spring_mod = SeasonSystem.get_spawn_modifier(SeasonSystem.Season.SPRING, parkland)  # 0.9
	var blended = SeasonSystem.get_blended_spawn_modifier(153, parkland)
	var expected = lerpf(summer_mod, spring_mod, SeasonSystem.TRANSITION_BLEND_FACTOR)
	assert_almost_eq(blended, expected, 0.001, "First day of Summer should blend toward Spring")
	assert_lt(blended, summer_mod, "Blended should be lower than pure Summer")
	assert_gt(blended, spring_mod, "Blended should be higher than pure Spring")

func test_blended_maintenance_boundary() -> void:
	# Same blending logic should work for maintenance
	var mountain = CourseTheme.Type.MOUNTAIN
	var fall_mod = SeasonSystem.get_maintenance_modifier(SeasonSystem.Season.FALL, mountain)  # 0.8
	var winter_mod = SeasonSystem.get_maintenance_modifier(SeasonSystem.Season.WINTER, mountain)  # 1.5
	var blended = SeasonSystem.get_blended_maintenance_modifier(335, mountain)  # Day 335 = 30 Nov, last day of Fall
	var expected = lerpf(fall_mod, winter_mod, SeasonSystem.TRANSITION_BLEND_FACTOR)
	assert_almost_eq(blended, expected, 0.001, "Last day of Fall->Winter boundary should blend")

func test_blended_winter_to_spring_wraps() -> void:
	# Day 60 (29 Feb 2000, last day of Winter) should blend toward Spring (wraps around)
	var parkland = CourseTheme.Type.PARKLAND
	var winter_mod = SeasonSystem.get_spawn_modifier(SeasonSystem.Season.WINTER, parkland)  # 0.3
	var spring_mod = SeasonSystem.get_spawn_modifier(SeasonSystem.Season.SPRING, parkland)  # 0.9
	var blended = SeasonSystem.get_blended_spawn_modifier(60, parkland)
	var expected = lerpf(winter_mod, spring_mod, SeasonSystem.TRANSITION_BLEND_FACTOR)
	assert_almost_eq(blended, expected, 0.001, "29 Feb Winter->Spring wrap should blend")

# --- Fee Tolerance ---

func test_fee_tolerance_peak_season() -> void:
	# Parkland Summer (day 170 = 18 Jun, mid-season): spawn_mod = 1.4, tolerance = clamp(0.5 + 1.4*0.55, 0.7, 1.3)
	var tol = SeasonSystem.get_fee_tolerance(170, CourseTheme.Type.PARKLAND)
	assert_almost_eq(tol, 1.27, 0.01, "Peak summer tolerance should be ~1.27")

func test_fee_tolerance_off_season() -> void:
	# Parkland Winter (day 20 = 20 Jan, mid-season): spawn_mod = 0.3, tolerance = clamp(0.5 + 0.3*0.55, 0.7, 1.3) = 0.665 -> clamped to 0.7
	var tol = SeasonSystem.get_fee_tolerance(20, CourseTheme.Type.PARKLAND)
	assert_almost_eq(tol, 0.7, 0.01, "Off-season tolerance should clamp to 0.7")

func test_fee_tolerance_range() -> void:
	# Fee tolerance should always be in [0.7, 1.3] for any theme/day combo
	for theme_val in range(10):
		for day in range(1, 366):
			var tol = SeasonSystem.get_fee_tolerance(day, theme_val)
			assert_gte(tol, 0.7, "Theme %d day %d: fee tolerance should be >= 0.7" % [theme_val, day])
			assert_lte(tol, 1.3, "Theme %d day %d: fee tolerance should be <= 1.3" % [theme_val, day])

# --- Tournament Prestige ---

func test_tournament_prestige_themed() -> void:
	# Parkland Fall = 1.2x prestige
	var prestige = SeasonSystem.get_tournament_prestige(247, CourseTheme.Type.PARKLAND)  # Day 247 = 3 Sep, Fall day 3
	assert_almost_eq(prestige, 1.2, 0.01)

func test_tournament_prestige_off_season() -> void:
	# Parkland Winter = 0.5x prestige
	var prestige = SeasonSystem.get_tournament_prestige(20, CourseTheme.Type.PARKLAND)
	assert_almost_eq(prestige, 0.5, 0.01)

# --- Weather Modifiers ---

func test_theme_weather_modifiers_desert() -> void:
	var mods = SeasonSystem.get_theme_weather_modifiers(CourseTheme.Type.DESERT)
	assert_almost_eq(mods["wind"], 0.8, 0.01)
	assert_almost_eq(mods["rain"], 0.3, 0.01)

func test_theme_weather_modifiers_links() -> void:
	var mods = SeasonSystem.get_theme_weather_modifiers(CourseTheme.Type.LINKS)
	assert_almost_eq(mods["wind"], 1.5, 0.01)
	assert_almost_eq(mods["rain"], 1.2, 0.01)

func test_theme_weather_modifiers_default_is_standard() -> void:
	var mods = SeasonSystem.get_theme_weather_modifiers(-1)
	assert_almost_eq(mods["wind"], 1.0, 0.01)
	assert_almost_eq(mods["rain"], 1.0, 0.01)

func test_blended_weather_weights_valid_probabilities() -> void:
	# For all themes and days, blended weather weights should be valid cumulative probs
	for theme_val in [0, 1, 2, 8]:  # Parkland, Desert, Links, Tropical
		for day in [20, 60, 61, 170]:  # mid-season, boundary, boundary, mid-season
			var weights = SeasonSystem.get_blended_weather_weights(day, theme_val)
			assert_eq(weights.size(), 6, "Should have 6 weather thresholds")
			assert_gt(weights[0], 0.0, "First threshold should be positive")
			assert_almost_eq(weights[5], 1.0, 0.001, "Last threshold should be 1.0")
			# Should be monotonically increasing
			for i in range(1, weights.size()):
				assert_gte(weights[i], weights[i - 1], "Thresholds should be non-decreasing")

# --- TRANSITION_BLEND_FACTOR constant ---

func test_blend_factor_constant_exists() -> void:
	assert_almost_eq(SeasonSystem.TRANSITION_BLEND_FACTOR, 0.34, 0.001)
