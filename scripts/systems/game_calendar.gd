extends RefCounted
class_name GameCalendar
## GameCalendar - Static calendar for absolute in-game dates.
##
## The game tracks time as `GameManager.current_day`: a 1-based count of days
## elapsed since the game started. This class converts that count into a real
## Gregorian date. **Day 1 is Saturday, 1 January 2000.**
##
## There are no in-game hours: the course never closes, and each day takes
## GameManager.SECONDS_PER_GAME_DAY real seconds at normal speed.
##
## Conversion uses Howard Hinnant's days_from_civil / civil_from_days
## algorithms, so month lengths and leap years are exact.

## Absolute day number (1-based) of 1 January 2000 — the start of a new game.
const START_YEAR: int = 2000

const MONTH_NAMES_SHORT: Array[String] = [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]
const MONTH_NAMES_LONG: Array[String] = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]
## Weekday names, index 0 = Sunday (see get_weekday()).
const WEEKDAY_NAMES_SHORT: Array[String] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

## Days from 1970-01-01 to 2000-01-01 (the in-game epoch).
const _EPOCH_DAYS: int = 10957

## Returns {year, month, day, weekday} for an absolute 1-based game day.
## month is 1-12, weekday is 0 (Sunday) .. 6 (Saturday).
static func get_date(day: int) -> Dictionary:
	var z: int = _EPOCH_DAYS + maxi(1, day) - 1
	return _civil_from_days(z)

static func get_year(day: int) -> int:
	return int(get_date(day).year)

static func get_month(day: int) -> int:
	return int(get_date(day).month)

static func get_day_of_month(day: int) -> int:
	return int(get_date(day).day)

## 0 = Sunday .. 6 = Saturday. Day 1 (1 Jan 2000) was a Saturday (6).
static func get_weekday(day: int) -> int:
	@warning_ignore_start("integer_division")
	var z: int = _EPOCH_DAYS + maxi(1, day) - 1
	return posmod(z + 4, 7)  # 1970-01-01 was a Thursday
	@warning_ignore_restore("integer_division")

static func is_leap_year(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0

static func get_days_in_month(year: int, month: int) -> int:
	match month:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		4, 6, 9, 11:
			return 30
		2:
			return 29 if is_leap_year(year) else 28
	return 30

static func get_days_in_year(year: int) -> int:
	return 366 if is_leap_year(year) else 365

## True when `day` is December 31 — the last day of its calendar year.
static func is_last_day_of_year(day: int) -> bool:
	var date := get_date(day)
	return int(date.month) == 12 and int(date.day) == 31

## True when `day` is January 1 — the first day of its calendar year.
static func is_first_day_of_year(day: int) -> bool:
	var date := get_date(day)
	return int(date.month) == 1 and int(date.day) == 1

## 1-based day index within the calendar year (1 Jan -> 1).
static func get_day_of_year(day: int) -> int:
	var date := get_date(day)
	var ordinal := int(date.day)
	for m in range(1, int(date.month)):
		ordinal += get_days_in_month(int(date.year), m)
	return ordinal

## Absolute 1-based game day of 1 January of the given calendar year.
static func get_year_start_day(year: int) -> int:
	return _days_from_civil(year, 1, 1) - _EPOCH_DAYS + 1

## Short date for HUD display, e.g. "Sat 1 Jan 2000".
static func format_date(day: int) -> String:
	var date := get_date(day)
	var weekday := WEEKDAY_NAMES_SHORT[get_weekday(day)]
	return "%s %d %s %d" % [weekday, int(date.day), MONTH_NAMES_SHORT[int(date.month) - 1], int(date.year)]

## Long date for panels and summaries, e.g. "Saturday, 1 January 2000".
static func format_date_long(day: int) -> String:
	var date := get_date(day)
	const WEEKDAY_LONG: Array[String] = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
	return "%s, %d %s %d" % [
		WEEKDAY_LONG[get_weekday(day)],
		int(date.day),
		MONTH_NAMES_LONG[int(date.month) - 1],
		int(date.year),
	]

## Compact stamp for histories, e.g. "1 Jan 2000".
static func format_date_short(day: int) -> String:
	var date := get_date(day)
	return "%d %s %d" % [int(date.day), MONTH_NAMES_SHORT[int(date.month) - 1], int(date.year)]

## Month label, e.g. "January 2000".
static func format_month(day: int) -> String:
	var date := get_date(day)
	return "%s %d" % [MONTH_NAMES_LONG[int(date.month) - 1], int(date.year)]

# --- Hinnant's calendar algorithms (days relative to 1970-01-01) ---

static func _days_from_civil(y: int, m: int, d: int) -> int:
	var yy := y - int(m <= 2)
	var era: int = int(floor(float(yy) / 400.0))
	var yoe: int = yy - era * 400
	@warning_ignore_start("integer_division")
	var doy: int = (153 * (m + (-3 if m > 2 else 9)) + 2) / 5 + d - 1
	var doe: int = yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468
	@warning_ignore_restore("integer_division")

static func _civil_from_days(z: int) -> Dictionary:
	var zz := z + 719468
	var era: int = int(floor(float(zz) / 146097.0))
	var doe: int = zz - era * 146097
	@warning_ignore_start("integer_division")
	var yoe: int = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	var y: int = yoe + era * 400
	var doy: int = doe - (365 * yoe + yoe / 4 - yoe / 100)
	var mp: int = (5 * doy + 2) / 153
	var d: int = doy - (153 * mp + 2) / 5 + 1
	var m: int = mp + (3 if mp < 10 else -9)
	@warning_ignore_restore("integer_division")
	return {"year": y + int(m <= 2), "month": m, "day": d}
