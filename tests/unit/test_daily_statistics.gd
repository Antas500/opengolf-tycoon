extends GutTest
## Tests for DailyStatistics and HoleStatistics inner classes


# --- DailyStatistics ---

func test_daily_stats_initial_state() -> void:
	var stats = GameManager.DailyStatistics.new()
	assert_eq(stats.revenue, 0)
	assert_eq(stats.golfers_served, 0)
	assert_eq(stats.operating_costs, 0)
	assert_eq(stats.building_revenue, 0)

func test_daily_stats_record_green_fee() -> void:
	var stats = GameManager.DailyStatistics.new()
	stats.record_green_fee(50)
	stats.record_green_fee(30)
	assert_eq(stats.revenue, 80, "Revenue should accumulate")

func test_daily_stats_record_hole_score_hole_in_one() -> void:
	var stats = GameManager.DailyStatistics.new()
	stats.record_hole_score(1, 3)  # Hole-in-one on par 3
	assert_eq(stats.holes_in_one, 1)
	# Hole-in-one is tracked separately, not as eagle
	assert_eq(stats.eagles, 0)

func test_daily_stats_record_hole_score_eagle() -> void:
	var stats = GameManager.DailyStatistics.new()
	stats.record_hole_score(3, 5)  # Eagle on par 5 (score_to_par = -2)
	assert_eq(stats.eagles, 1)

func test_daily_stats_record_hole_score_birdie() -> void:
	var stats = GameManager.DailyStatistics.new()
	stats.record_hole_score(3, 4)  # Birdie on par 4 (score_to_par = -1)
	assert_eq(stats.birdies, 1)

func test_daily_stats_record_hole_score_par() -> void:
	var stats = GameManager.DailyStatistics.new()
	stats.record_hole_score(4, 4)  # Par
	# Par doesn't increment any counter (it's the neutral case)
	assert_eq(stats.birdies, 0)
	assert_eq(stats.bogeys_or_worse, 0)

func test_daily_stats_record_hole_score_bogey() -> void:
	var stats = GameManager.DailyStatistics.new()
	stats.record_hole_score(5, 4)  # Bogey (score_to_par = +1)
	assert_eq(stats.bogeys_or_worse, 1)

func test_daily_stats_record_hole_score_double_bogey() -> void:
	var stats = GameManager.DailyStatistics.new()
	stats.record_hole_score(6, 4)  # Double bogey (score_to_par = +2)
	assert_eq(stats.bogeys_or_worse, 1, "Double bogey counts as bogey_or_worse")

func test_daily_stats_record_round_finished() -> void:
	var stats = GameManager.DailyStatistics.new()
	stats.record_round_finished(72, 72)
	stats.record_round_finished(70, 72)
	assert_eq(stats.golfers_served, 2)
	assert_eq(stats.total_strokes_today, 142)
	assert_eq(stats.total_par_today, 144)

func test_daily_stats_record_golfer_tier() -> void:
	var stats = GameManager.DailyStatistics.new()
	stats.record_golfer_tier(GolferTier.Tier.PRO)
	stats.record_golfer_tier(GolferTier.Tier.PRO)
	stats.record_golfer_tier(GolferTier.Tier.BEGINNER)
	assert_eq(stats.tier_counts[GolferTier.Tier.PRO], 2)
	assert_eq(stats.tier_counts[GolferTier.Tier.BEGINNER], 1)
	assert_eq(stats.tier_counts[GolferTier.Tier.CASUAL], 0)


# --- Profit & Revenue ---

func test_daily_stats_get_profit() -> void:
	var stats = GameManager.DailyStatistics.new()
	stats.revenue = 500
	stats.building_revenue = 100
	stats.operating_costs = 300
	assert_eq(stats.get_profit(), 300, "Profit = revenue + building_revenue - costs")

func test_daily_stats_get_profit_loss() -> void:
	var stats = GameManager.DailyStatistics.new()
	stats.revenue = 100
	stats.building_revenue = 0
	stats.operating_costs = 300
	assert_eq(stats.get_profit(), -200, "Negative profit = loss")

func test_daily_stats_get_total_revenue() -> void:
	var stats = GameManager.DailyStatistics.new()
	stats.revenue = 500
	stats.building_revenue = 200
	assert_eq(stats.get_total_revenue(), 700, "Total revenue includes buildings")


# --- Average Score ---

func test_daily_stats_average_score_to_par_no_data() -> void:
	var stats = GameManager.DailyStatistics.new()
	assert_eq(stats.get_average_score_to_par(), 0.0, "No data should return 0")

func test_daily_stats_average_score_to_par() -> void:
	var stats = GameManager.DailyStatistics.new()
	stats.record_round_finished(74, 72)  # +2
	stats.record_round_finished(70, 72)  # -2
	# Total strokes - total par = 144 - 144 = 0, / 2 golfers = 0.0
	assert_eq(stats.get_average_score_to_par(), 0.0, "Average should be even")

func test_daily_stats_average_score_to_par_over() -> void:
	var stats = GameManager.DailyStatistics.new()
	stats.record_round_finished(76, 72)  # +4
	# (76-72) / 1 golfer = 4.0
	assert_eq(stats.get_average_score_to_par(), 4.0)


# --- Operating Costs ---

func _scale_days() -> int:
	return int(round(1.0 / GameManager.DAILY_RATE_SCALE))

func _sum_operating_costs(terrain_cost: int, hole_count: int, building_costs: int) -> Dictionary:
	## Run one legacy-day equivalent of 3.5s game days and total the charges.
	## Whole dollars posted plus leftover carry equal the legacy daily amount
	## (float rounding may leave < $1 in the carry).
	GameManager._daily_charge_carries.clear()
	var stats = GameManager.DailyStatistics.new()
	var totals := {
		"terrain": 0.0,
		"base": 0.0,
		"staff": 0.0,
		"buildings": 0.0,
		"operating": 0.0,
	}
	for _i in _scale_days():
		stats.calculate_operating_costs(terrain_cost, hole_count, building_costs)
		totals["terrain"] += stats.terrain_maintenance
		totals["base"] += stats.base_operating_cost
		totals["staff"] += stats.staff_wages
		totals["buildings"] += stats.building_operating_costs
		totals["operating"] += stats.operating_costs
	totals["terrain"] += float(GameManager._daily_charge_carries.get("terrain", 0.0))
	totals["base"] += float(GameManager._daily_charge_carries.get("base", 0.0))
	totals["staff"] += float(GameManager._daily_charge_carries.get("staff_wages", 0.0))
	totals["buildings"] += float(GameManager._daily_charge_carries.get("buildings", 0.0))
	totals["operating"] = (
		totals["terrain"] + totals["base"] + totals["staff"] + totals["buildings"]
		+ float(GameManager._daily_charge_carries.get("decorations", 0.0))
	)
	return totals

func test_daily_stats_calculate_operating_costs() -> void:
	# Save and restore staff tier, day, theme, and charge carries
	var original_tier = GameManager.current_staff_tier
	var original_day = GameManager.current_day
	var original_theme = GameManager.current_theme
	var original_carries: Dictionary = GameManager._daily_charge_carries.duplicate()
	GameManager.current_staff_tier = GameManager.StaffTier.FULL_TIME  # $10/hole
	GameManager.current_theme = CourseTheme.Type.PARKLAND
	# Mid-Fall 2000 (16 Oct = day 290) has a clean 0.7x Parkland maintenance modifier
	GameManager.current_day = 290

	var totals := _sum_operating_costs(100, 9, 50)

	# terrain = 100 * 0.7 = 70 (Fall modifier) across one legacy day
	assert_almost_eq(totals["terrain"], 70.0, 0.01)
	# base = 100 + 9*50 = 550
	assert_almost_eq(totals["base"], 550.0, 0.01)
	# staff = 9 * 10 = 90
	assert_almost_eq(totals["staff"], 90.0, 0.01)
	assert_almost_eq(totals["buildings"], 50.0, 0.01)
	# total = 70 + 550 + 90 + 50 = 760
	assert_almost_eq(totals["operating"], 760.0, 0.01)

	GameManager.current_staff_tier = original_tier
	GameManager.current_day = original_day
	GameManager.current_theme = original_theme
	GameManager._daily_charge_carries = original_carries

func test_daily_stats_calculate_operating_costs_part_time() -> void:
	var original_tier = GameManager.current_staff_tier
	var original_carries: Dictionary = GameManager._daily_charge_carries.duplicate()
	GameManager.current_staff_tier = GameManager.StaffTier.PART_TIME  # $5/hole

	var totals := _sum_operating_costs(0, 4, 0)

	# base = 100 + 4*50 = 300
	assert_almost_eq(totals["base"], 300.0, 0.01)
	# staff = 4 * 5 = 20
	assert_almost_eq(totals["staff"], 20.0, 0.01)
	# total = 0 + 300 + 20 + 0 = 320
	assert_almost_eq(totals["operating"], 320.0, 0.01)

	GameManager.current_staff_tier = original_tier
	GameManager._daily_charge_carries = original_carries

func test_daily_stats_calculate_operating_costs_premium() -> void:
	var original_tier = GameManager.current_staff_tier
	var original_carries: Dictionary = GameManager._daily_charge_carries.duplicate()
	GameManager.current_staff_tier = GameManager.StaffTier.PREMIUM  # $20/hole

	var totals := _sum_operating_costs(50, 2, 0)

	# staff = 2 * 20 = 40
	assert_almost_eq(totals["staff"], 40.0, 0.01)

	GameManager.current_staff_tier = original_tier
	GameManager._daily_charge_carries = original_carries


# --- Reset ---

func test_daily_stats_reset() -> void:
	var stats = GameManager.DailyStatistics.new()
	stats.revenue = 1000
	stats.golfers_served = 20
	stats.birdies = 5
	stats.operating_costs = 500
	stats.record_golfer_tier(GolferTier.Tier.PRO)

	stats.reset()

	assert_eq(stats.revenue, 0)
	assert_eq(stats.golfers_served, 0)
	assert_eq(stats.birdies, 0)
	assert_eq(stats.operating_costs, 0)
	assert_eq(stats.tier_counts[GolferTier.Tier.PRO], 0, "Tier counts should reset")


# --- HoleStatistics ---

func test_hole_statistics_initial() -> void:
	var hs = GameManager.HoleStatistics.new(3)
	assert_eq(hs.hole_number, 3)
	assert_eq(hs.total_rounds, 0)
	assert_eq(hs.best_score, -1)

func test_hole_statistics_record_score_eagle() -> void:
	var hs = GameManager.HoleStatistics.new(1)
	hs.record_score(3, 5)  # Eagle on par 5
	assert_eq(hs.eagles, 1)
	assert_eq(hs.total_rounds, 1)
	assert_eq(hs.total_strokes, 3)

func test_hole_statistics_record_score_birdie() -> void:
	var hs = GameManager.HoleStatistics.new(1)
	hs.record_score(3, 4)  # Birdie on par 4
	assert_eq(hs.birdies, 1)

func test_hole_statistics_record_score_par() -> void:
	var hs = GameManager.HoleStatistics.new(1)
	hs.record_score(4, 4)
	assert_eq(hs.pars, 1)

func test_hole_statistics_record_score_bogey() -> void:
	var hs = GameManager.HoleStatistics.new(1)
	hs.record_score(5, 4)
	assert_eq(hs.bogeys, 1)

func test_hole_statistics_record_score_double_bogey() -> void:
	var hs = GameManager.HoleStatistics.new(1)
	hs.record_score(6, 4)
	assert_eq(hs.double_bogeys_plus, 1)

func test_hole_statistics_record_hole_in_one() -> void:
	var hs = GameManager.HoleStatistics.new(1)
	hs.record_score(1, 3)
	assert_eq(hs.holes_in_one, 1)
	assert_eq(hs.eagles, 1, "Hole-in-one also counts as eagle")

func test_hole_statistics_best_score_tracking() -> void:
	var hs = GameManager.HoleStatistics.new(1)
	hs.record_score(5, 4, "Alice")
	assert_eq(hs.best_score, 5)
	assert_eq(hs.best_scorer_name, "Alice")

	hs.record_score(3, 4, "Bob")
	assert_eq(hs.best_score, 3, "Should update to lower score")
	assert_eq(hs.best_scorer_name, "Bob")

	hs.record_score(4, 4, "Carol")
	assert_eq(hs.best_score, 3, "Should NOT update to higher score")
	assert_eq(hs.best_scorer_name, "Bob")

func test_hole_statistics_average_score() -> void:
	var hs = GameManager.HoleStatistics.new(1)
	hs.record_score(4, 4)
	hs.record_score(5, 4)
	hs.record_score(3, 4)
	# Average = (4+5+3)/3 = 4.0
	assert_eq(hs.get_average_score(), 4.0)

func test_hole_statistics_average_score_no_rounds() -> void:
	var hs = GameManager.HoleStatistics.new(1)
	assert_eq(hs.get_average_score(), 0.0)

func test_hole_statistics_average_to_par() -> void:
	var hs = GameManager.HoleStatistics.new(1)
	hs.record_score(5, 4)  # +1
	hs.record_score(3, 4)  # -1
	# Average score = 4.0, par = 4, average to par = 0.0
	assert_eq(hs.get_average_to_par(4), 0.0)

func test_hole_statistics_average_to_par_over() -> void:
	var hs = GameManager.HoleStatistics.new(1)
	hs.record_score(6, 4)
	# Average = 6.0, par = 4, avg to par = +2.0
	assert_eq(hs.get_average_to_par(4), 2.0)
