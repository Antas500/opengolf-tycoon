extends GutTest
## Tests for GameCalendar — day 1 is Saturday 1 January 2000.

func test_day_one_is_saturday_first_january_2000() -> void:
	var date := GameCalendar.get_date(1)
	assert_eq(int(date["year"]), 2000)
	assert_eq(int(date["month"]), 1)
	assert_eq(int(date["day"]), 1)
	assert_eq(GameCalendar.get_weekday(1), 6, "1 Jan 2000 was a Saturday")
	assert_eq(GameCalendar.format_date(1), "Sat 1 Jan 2000")

func test_february_first_is_day_32() -> void:
	assert_eq(GameCalendar.format_date(32), "Tue 1 Feb 2000")
	assert_eq(GameCalendar.get_month(32), 2)
	assert_eq(GameCalendar.get_day_of_month(32), 1)

func test_leap_day_2000() -> void:
	assert_eq(GameCalendar.format_date(60), "Tue 29 Feb 2000")
	assert_true(GameCalendar.is_leap_year(2000))
	assert_eq(GameCalendar.get_days_in_year(2000), 366)

func test_year_2001_starts_on_day_367() -> void:
	assert_eq(GameCalendar.format_date(366), "Sun 31 Dec 2000")
	assert_eq(GameCalendar.get_year(366), 2000)
	assert_eq(GameCalendar.format_date(367), "Mon 1 Jan 2001")
	assert_eq(GameCalendar.get_year(367), 2001)
	assert_false(GameCalendar.is_leap_year(2001))

func test_get_date_clamps_pre_epoch_days() -> void:
	var clamped := GameCalendar.get_date(-30)
	assert_eq(int(clamped["year"]), 2000)
	assert_eq(int(clamped["month"]), 1)
	assert_eq(int(clamped["day"]), 1)

func test_get_date_raw_keeps_pre_epoch_winter() -> void:
	# Winter containing day 1 starts on 1 Dec 1999 = game day -30.
	var raw := GameCalendar.get_date_raw(-30)
	assert_eq(int(raw["year"]), 1999)
	assert_eq(int(raw["month"]), 12)
	assert_eq(int(raw["day"]), 1)
