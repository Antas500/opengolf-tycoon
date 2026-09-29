extends RefCounted
class_name SeasonSystem
## SeasonSystem - Static class for seasonal calendar and modifiers.
## Season is derived from GameManager.current_day — no stored state.
## Seasons follow the real calendar (see GameCalendar, day 1 = 1 Jan 2000):
## Winter (Dec-Feb), Spring (Mar-May), Summer (Jun-Aug), Fall (Sep-Nov).
##
## Theme-aware: Modifier tables vary per CourseTheme.Type so Desert courses
## peak in winter while Mountain courses peak in summer.

enum Season { SPRING, SUMMER, FALL, WINTER }

const TRANSITION_BLEND_FACTOR: float = 0.34  ## Blend weight at season boundaries (2-day window)

# Theme enum aliases for readable dictionary keys
const _PARKLAND  = CourseTheme.Type.PARKLAND
const _DESERT    = CourseTheme.Type.DESERT
const _LINKS     = CourseTheme.Type.LINKS
const _MOUNTAIN  = CourseTheme.Type.MOUNTAIN
const _CITY      = CourseTheme.Type.CITY
const _RESORT    = CourseTheme.Type.RESORT
const _HEATHLAND = CourseTheme.Type.HEATHLAND
const _WOODLAND  = CourseTheme.Type.WOODLAND
const _TROPICAL  = CourseTheme.Type.TROPICAL
const _MARSHLAND = CourseTheme.Type.MARSHLAND

## Theme-aware spawn rate modifier tables (theme -> {season -> modifier}).
## Fallback row (PARKLAND) matches the original global values.
const THEME_SPAWN_MODIFIERS: Dictionary = {
	_PARKLAND:  {0: 0.9, 1: 1.4, 2: 0.8, 3: 0.3},
	_DESERT:    {0: 0.6, 1: 0.3, 2: 0.9, 3: 1.4},  # Inverted peak
	_LINKS:     {0: 0.8, 1: 1.3, 2: 0.9, 3: 0.4},
	_MOUNTAIN:  {0: 1.0, 1: 1.5, 2: 0.7, 3: 0.1},
	_CITY:      {0: 0.9, 1: 1.2, 2: 1.0, 3: 0.6},  # Stable year-round
	_RESORT:    {0: 1.0, 1: 1.3, 2: 0.8, 3: 1.2},  # Dual peak
	_HEATHLAND: {0: 0.8, 1: 1.3, 2: 0.9, 3: 0.3},
	_WOODLAND:  {0: 1.0, 1: 1.4, 2: 1.1, 3: 0.2},  # Fall foliage boost
	_TROPICAL:  {0: 1.1, 1: 0.8, 2: 1.2, 3: 1.3},  # Inverted peak
	_MARSHLAND: {0: 0.7, 1: 0.9, 2: 0.8, 3: 0.4},
}

## Theme-aware maintenance cost modifier tables.
const THEME_MAINTENANCE_MODIFIERS: Dictionary = {
	_PARKLAND:  {0: 1.1, 1: 1.4, 2: 0.7, 3: 1.1},
	_DESERT:    {0: 0.8, 1: 0.6, 2: 0.8, 3: 1.0},  # Low year-round
	_LINKS:     {0: 1.0, 1: 1.1, 2: 0.8, 3: 1.3},  # Winter wind damage
	_MOUNTAIN:  {0: 1.2, 1: 1.3, 2: 0.8, 3: 1.5},  # Costly winters
	_CITY:      {0: 1.0, 1: 1.2, 2: 0.9, 3: 1.0},
	_RESORT:    {0: 1.1, 1: 1.3, 2: 0.9, 3: 1.2},
	_HEATHLAND: {0: 0.9, 1: 1.1, 2: 0.8, 3: 1.0},
	_WOODLAND:  {0: 1.0, 1: 1.2, 2: 1.0, 3: 0.9},
	_TROPICAL:  {0: 1.3, 1: 1.5, 2: 1.1, 3: 0.9},  # Summer growth
	_MARSHLAND: {0: 1.2, 1: 1.4, 2: 0.9, 3: 1.0},
}

## Tournament prestige multipliers per theme x season.
## Higher prestige seasons reward more reputation for hosting tournaments.
const THEME_TOURNAMENT_PRESTIGE: Dictionary = {
	_PARKLAND:  {0: 1.0, 1: 1.0, 2: 1.2, 3: 0.5},  # Fall classic
	_DESERT:    {0: 0.8, 1: 0.5, 2: 1.2, 3: 1.0},  # Fall/winter
	_LINKS:     {0: 0.8, 1: 1.2, 2: 1.0, 3: 0.5},  # Summer Open
	_MOUNTAIN:  {0: 1.0, 1: 1.2, 2: 0.8, 3: 0.5},
	_CITY:      {0: 1.0, 1: 1.0, 2: 1.2, 3: 0.8},  # No deep off-season
	_RESORT:    {0: 0.8, 1: 1.0, 2: 1.0, 3: 1.2},  # Winter prestige
	_HEATHLAND: {0: 0.8, 1: 1.2, 2: 1.0, 3: 0.5},
	_WOODLAND:  {0: 1.0, 1: 1.0, 2: 1.2, 3: 0.5},  # Fall classic
	_TROPICAL:  {0: 0.8, 1: 0.5, 2: 1.0, 3: 1.2},  # Winter prestige
	_MARSHLAND: {0: 0.8, 1: 0.8, 2: 1.2, 3: 0.5},  # Fall classic
}

## Theme weather modifiers: {theme -> {wind_modifier, rain_modifier}}
## Applied on top of base seasonal weather tables.
const THEME_WEATHER_MODIFIERS: Dictionary = {
	_PARKLAND:  {"wind": 1.0, "rain": 1.0},
	_DESERT:    {"wind": 0.8, "rain": 0.3},  # Dry, moderate wind
	_LINKS:     {"wind": 1.5, "rain": 1.2},  # Windy, frequent rain
	_MOUNTAIN:  {"wind": 1.2, "rain": 1.3},  # Variable, more precip
	_CITY:      {"wind": 1.0, "rain": 1.0},
	_RESORT:    {"wind": 1.0, "rain": 1.0},
	_HEATHLAND: {"wind": 1.0, "rain": 1.0},
	_WOODLAND:  {"wind": 1.0, "rain": 1.0},
	_TROPICAL:  {"wind": 0.7, "rain": 1.8},  # Calm but very rainy
	_MARSHLAND: {"wind": 0.9, "rain": 1.4},  # Damp, frequent rain
}

## Season boundaries by calendar date: Winter opens on 1 December, Spring on
## 1 March, Summer on 1 June, Fall on 1 September.
const SEASON_START_MONTHS: Dictionary = {
	Season.WINTER: 12,
	Season.SPRING: 3,
	Season.SUMMER: 6,
	Season.FALL: 9,
}

static func get_season_for_month(month: int) -> int:
	match month:
		3, 4, 5:
			return Season.SPRING
		6, 7, 8:
			return Season.SUMMER
		9, 10, 11:
			return Season.FALL
		_:
			return Season.WINTER

static func get_season(day: int) -> int:
	return get_season_for_month(GameCalendar.get_month(day))

## 1-based day index within the current season (e.g. 1 on the season's first day).
static func get_day_in_season(day: int) -> int:
	return day - get_season_start_day(day) + 1

## Absolute day on which the season containing `day` began.
static func get_season_start_day(day: int) -> int:
	var date := GameCalendar.get_date(day)
	var season := get_season_for_month(int(date.month))
	var start_month: int = SEASON_START_MONTHS[season]
	var year := int(date.year)
	# Winter starts in December of the previous calendar year.
	if season == Season.WINTER and start_month > int(date.month):
		year -= 1
	return GameCalendar._days_from_civil(year, start_month, 1) - GameCalendar._EPOCH_DAYS + 1

## Number of days in the season containing `day` (~90 days).
static func get_season_length(day: int) -> int:
	var start := get_season_start_day(day)
	# Start of the next season = start day of the (current_day + length) lookup,
	# computed by stepping to the same date three months later.
	var date := GameCalendar._civil_from_days(start - 1 + GameCalendar._EPOCH_DAYS - 1)
	var next_month := int(date.month) + 3
	var next_year := int(date.year)
	if next_month > 12:
		next_month -= 12
		next_year += 1
	var next_start: int = GameCalendar._days_from_civil(next_year, next_month, 1) - GameCalendar._EPOCH_DAYS + 1
	return next_start - start

static func get_year(day: int) -> int:
	## Calendar year of the given day (e.g. 2000 for day 1).
	return GameCalendar.get_year(day)

static func get_season_name(season: int) -> String:
	match season:
		Season.SPRING: return "Spring"
		Season.SUMMER: return "Summer"
		Season.FALL: return "Fall"
		Season.WINTER: return "Winter"
	return "Unknown"

## Golfer demand multiplier by season, optionally theme-aware.
## When theme is provided, returns theme-specific modifier. Otherwise falls back
## to PARKLAND (the original global values).
static func get_spawn_modifier(season: int, theme: int = -1) -> float:
	var t = theme if theme >= 0 else 0  # Default to PARKLAND
	if THEME_SPAWN_MODIFIERS.has(t):
		return THEME_SPAWN_MODIFIERS[t].get(season, 1.0)
	return THEME_SPAWN_MODIFIERS[0].get(season, 1.0)

## Maintenance cost multiplier by season, optionally theme-aware.
static func get_maintenance_modifier(season: int, theme: int = -1) -> float:
	var t = theme if theme >= 0 else 0
	if THEME_MAINTENANCE_MODIFIERS.has(t):
		return THEME_MAINTENANCE_MODIFIERS[t].get(season, 1.0)
	return THEME_MAINTENANCE_MODIFIERS[0].get(season, 1.0)

## Blended spawn modifier with 2-day gradual transition at season boundaries.
static func get_blended_spawn_modifier(day: int, theme: int = -1) -> float:
	return _blend_at_boundary(day, func(s): return get_spawn_modifier(s, theme))

## Blended maintenance modifier with 2-day gradual transition.
static func get_blended_maintenance_modifier(day: int, theme: int = -1) -> float:
	return _blend_at_boundary(day, func(s): return get_maintenance_modifier(s, theme))

## Green fee tolerance — how willing golfers are to pay premium pricing.
## Peak-season golfers accept 30% higher fees; off-season golfers expect discounts.
## Maps spawn modifier (demand proxy) to a 0.7–1.3 tolerance range.
static func get_fee_tolerance(day: int, theme: int = -1) -> float:
	var spawn_mod = get_blended_spawn_modifier(day, theme)
	return clampf(0.5 + spawn_mod * 0.55, 0.7, 1.3)

## Tournament prestige modifier — reputation reward scales by season.
static func get_tournament_prestige(day: int, theme: int = -1) -> float:
	var season = get_season(day)
	var t = theme if theme >= 0 else 0
	if THEME_TOURNAMENT_PRESTIGE.has(t):
		return THEME_TOURNAMENT_PRESTIGE[t].get(season, 1.0)
	return 1.0

## Theme weather modifiers for wind and rain probability adjustments.
static func get_theme_weather_modifiers(theme: int = -1) -> Dictionary:
	var t = theme if theme >= 0 else 0
	if THEME_WEATHER_MODIFIERS.has(t):
		return THEME_WEATHER_MODIFIERS[t]
	return {"wind": 1.0, "rain": 1.0}

## Blended weather weights with 2-day transition and theme rain modifier.
static func get_blended_weather_weights(day: int, theme: int = -1) -> Array:
	var base = _blend_array_at_boundary(day, get_weather_weights)

	# Apply theme rain modifier — shifts probability toward/away from rain
	var weather_mods = get_theme_weather_modifiers(theme)
	var rain_mod = weather_mods.get("rain", 1.0)
	if rain_mod != 1.0:
		base = _apply_rain_modifier(base, rain_mod)

	return base

## Cumulative weather probability thresholds per season
## Order: [SUNNY, PARTLY_CLOUDY, CLOUDY, LIGHT_RAIN, RAIN, HEAVY_RAIN]
static func get_weather_weights(season: int) -> Array:
	match season:
		Season.SPRING:
			return [0.25, 0.50, 0.65, 0.80, 0.93, 1.0]
		Season.SUMMER:
			return [0.55, 0.80, 0.90, 0.95, 0.98, 1.0]
		Season.FALL:
			return [0.30, 0.55, 0.75, 0.88, 0.96, 1.0]
		Season.WINTER:
			return [0.15, 0.35, 0.60, 0.78, 0.92, 1.0]
	return [0.40, 0.70, 0.85, 0.93, 0.98, 1.0]

static func get_season_color(season: int) -> Color:
	match season:
		Season.SPRING: return Color(0.4, 0.8, 0.4)
		Season.SUMMER: return Color(0.9, 0.85, 0.3)
		Season.FALL: return Color(0.85, 0.55, 0.25)
		Season.WINTER: return Color(0.6, 0.7, 0.85)
	return Color.WHITE

## Blend a float modifier at season boundaries (day counts vary by season
## length, so boundary detection compares `day` against the season edges).
## getter takes a season int and returns the modifier float for that season.
static func _blend_at_boundary(day: int, getter: Callable) -> float:
	var season = get_season(day)
	var current_val = getter.call(season)

	if day + 1 == get_season_start_day(day) + get_season_length(day):
		var next_val = getter.call((season + 1) % 4)
		return lerpf(current_val, next_val, TRANSITION_BLEND_FACTOR)

	if day == get_season_start_day(day):
		var prev_val = getter.call((season + 3) % 4)
		return lerpf(current_val, prev_val, TRANSITION_BLEND_FACTOR)

	return current_val

## Blend an array modifier at season boundaries (2-day transition window).
## getter takes a season int and returns an Array for that season.
static func _blend_array_at_boundary(day: int, getter: Callable) -> Array:
	var season = get_season(day)
	var current_arr = getter.call(season)

	if day + 1 == get_season_start_day(day) + get_season_length(day):
		var next_arr = getter.call((season + 1) % 4)
		return _lerp_array(current_arr, next_arr, TRANSITION_BLEND_FACTOR)

	if day == get_season_start_day(day):
		var prev_arr = getter.call((season + 3) % 4)
		return _lerp_array(current_arr, prev_arr, TRANSITION_BLEND_FACTOR)

	return current_arr

## Lerp two arrays element-wise.
static func _lerp_array(a: Array, b: Array, t: float) -> Array:
	var result: Array = []
	for i in range(mini(a.size(), b.size())):
		result.append(lerpf(a[i], b[i], t))
	return result

## Apply rain modifier to cumulative weather thresholds.
## rain_mod > 1.0 compresses the sunny portion (more rain).
## rain_mod < 1.0 expands the sunny portion (less rain).
static func _apply_rain_modifier(thresholds: Array, rain_mod: float) -> Array:
	if thresholds.size() < 6:
		return thresholds
	# Convert cumulative to individual probabilities
	var probs: Array = [thresholds[0]]
	for i in range(1, thresholds.size()):
		probs.append(thresholds[i] - thresholds[i - 1])
	# Scale rain probabilities (indices 3-5: LIGHT_RAIN, RAIN, HEAVY_RAIN)
	for i in range(3, probs.size()):
		probs[i] *= rain_mod
	# Normalize back to 1.0
	var total = 0.0
	for p in probs:
		total += p
	if total <= 0:
		return thresholds
	for i in range(probs.size()):
		probs[i] /= total
	# Convert back to cumulative
	var result: Array = [probs[0]]
	for i in range(1, probs.size()):
		result.append(result[i - 1] + probs[i])
	result[result.size() - 1] = 1.0  # Ensure last is exactly 1.0
	return result
