extends Node
## GameManager - Central game state manager

enum GameMode { MAIN_MENU, BUILDING, SIMULATING, PLAYING, PAUSED }
enum GameSpeed { PAUSED = 0, NORMAL = 1, FAST = 3, ULTRA = 8 }

var player_profile: PlayerGolferProfile = PlayerGolferProfile.new()

var current_mode: GameMode = GameMode.MAIN_MENU
var current_speed: GameSpeed = GameSpeed.NORMAL
var is_paused: bool = false:
	set(value):
		if is_paused == value:
			return
		is_paused = value
		_sync_time_scale()

var current_course: CourseData = null
var course_name: String = "New Course"
var current_theme: int = CourseTheme.Type.PARKLAND
var current_difficulty: int = DifficultyPresets.Preset.NORMAL
var heightmap_noise_seed: int = 0
var tee_booking_interval: int = 90
var colorblind_mode: int = ColorblindMode.Mode.OFF
var invert_zoom_scroll: bool = false
var multi_tee_enabled: bool = false  # Feature toggle: auto-generate forward/middle tees
# Default starting values (overridden by difficulty preset in new_game)
const DEFAULT_STARTING_MONEY: int = 25000
const DEFAULT_STARTING_REPUTATION: float = 50.0

# Operating cost constants
const BASE_DAILY_OVERHEAD: int = 100
const PER_HOLE_DAILY_COST: int = 50

var money: int = DEFAULT_STARTING_MONEY
var reputation: float = DEFAULT_STARTING_REPUTATION
## Absolute 1-based day count. Day 1 is Saturday, 1 January 2000 — see
## GameCalendar for date conversion. There are no in-game hours: the course
## never closes and every day lasts SECONDS_PER_GAME_DAY at normal speed.
var current_day: int = 1

# Reputation decay scales with course quality (stars)
# Legacy rates were tuned per legacy day (1680 real seconds); they are scaled
# into the new day length by DAILY_RATE_SCALE.
const REPUTATION_DAILY_DECAY: float = 0.5  # Baseline at 3 stars

# Stagnation penalty: prevents coasting on few holes forever
const STAGNATION_DAYS_THRESHOLD: int = 28
const STAGNATION_DECAY_PENALTY: float = 0.3
const STAGNATION_REPUTATION_FLOOR: float = 40.0
var _stagnation_hole_count: int = 0
var _stagnation_day_started: int = 1

# Loan system
var loan_balance: int = 0
const MAX_LOAN: int = 50000
const LOAN_ANNUAL_INTEREST_RATE: float = 0.10  # 10% APR, charged at year end

# Historical daily statistics (rolling 30-day window, persisted)
var daily_history: Array = []
const MAX_DAILY_HISTORY: int = 30

# Economic snapshot logging (for balance analysis, disabled by default)
var economic_snapshots_enabled: bool = false
const SNAPSHOT_PATH: String = "user://economic_snapshots.json"

# Green fee pricing
var green_fee: int = 10  # Default $10/hole (auto-clamped by hole count)
const MIN_GREEN_FEE: int = 1
const MAX_GREEN_FEE: int = 200

# Bankruptcy threshold - dynamic based on difficulty preset
var bankruptcy_threshold: int = -1000

# Staff tier system
enum StaffTier { PART_TIME, FULL_TIME, PREMIUM }

const STAFF_TIER_DATA = {
	StaffTier.PART_TIME: {
		"name": "Part-Time Staff",
		"cost_per_hole": 5,
		"condition_modifier": 0.85,
		"satisfaction_modifier": 0.90,
		"description": "Basic maintenance, limited availability"
	},
	StaffTier.FULL_TIME: {
		"name": "Full-Time Staff",
		"cost_per_hole": 10,
		"condition_modifier": 1.0,
		"satisfaction_modifier": 1.0,
		"description": "Standard professional maintenance"
	},
	StaffTier.PREMIUM: {
		"name": "Premium Staff",
		"cost_per_hole": 20,
		"condition_modifier": 1.15,
		"satisfaction_modifier": 1.10,
		"description": "Expert greenskeepers, exceptional service"
	}
}

var current_staff_tier: int = StaffTier.FULL_TIME

# Reference to terrain grid (set by main scene)
var terrain_grid: TerrainGrid = null

# Reference to wind system (set by main scene)
var wind_system: WindSystem = null

# Reference to weather system (set by main scene)
var weather_system: WeatherSystem = null

# Reference to tournament manager (set by main scene)
var tournament_manager: TournamentManager = null

# Reference to entity layer for building queries (set by main scene)
var entity_layer = null

# Shot heatmap tracker (set by main scene)
var shot_heatmap_tracker: ShotHeatmapTracker = null

# Economy system references (set by main scene)
var land_manager: LandManager = null
var staff_manager: StaffManager = null
var weed_manager: WeedManager = null
## The live golfer spawner, used by on-course staff to find customers.
var golfer_manager: GolferManager = null
var marketing_manager: MarketingManager = null

# Daily statistics tracking
var daily_stats: DailyStatistics = DailyStatistics.new()
var yesterday_stats: DailyStatistics = null  # Previous day's stats for comparison

# Year-to-date statistics: daily_stats are accumulated here on every day
# rollover and shown in the year-end summary. previous_year_stats keeps the
# last completed year for trend arrows in that summary.
var yearly_stats: DailyStatistics = DailyStatistics.new()
var previous_year_stats: DailyStatistics = null
var prior_year_stats: DailyStatistics = null  # The year before last (trend arrows in the summary)
var yearly_days: int = 0  # Days accumulated into yearly_stats
var yearly_satisfaction_sum: float = 0.0  # Daily satisfaction samples for the year average
var previous_year_satisfaction: float = -1.0  # Avg satisfaction of the last completed year (-1 = none)

# Per-hole cumulative statistics (persists across days)
var hole_statistics: Dictionary = {}  # hole_number -> HoleStatistics

# Course rating (1-5 stars)
var course_rating: Dictionary = {
	"condition": 1.0,
	"design": 1.0,
	"value": 1.0,
	"pace": 1.0,
	"aesthetics": 1.0,
	"overall": 1.0,
	"stars": 1,
	"difficulty": 0.0,
	"slope": 113,
	"course_rating": 72.0
}

# Course records tracking
var course_records: Dictionary = CourseRecords.create_empty_records()

# Expose properties for backward compatibility
var course_data: CourseData:
	get:
		return current_course

var game_mode: GameMode:
	get:
		return current_mode

func get_game_speed_multiplier() -> float:
	if is_paused or current_speed == GameSpeed.PAUSED:
		return 0.0
	return float(current_speed)

## Real seconds per game day at normal speed. Engine.time_scale applies the
## speed multiplier to delta, so FAST (3x) and ULTRA (8x) shorten days too.
const SECONDS_PER_GAME_DAY: float = 3.5
## Length of a legacy day (14 open hours × 120 s/hour = 1680 s). Per-day
## rates tuned for the legacy clock are multiplied by DAILY_RATE_SCALE so the
## real-time pace of the economy is unchanged by the faster calendar.
const LEGACY_DAY_SECONDS: float = 1680.0
const DAILY_RATE_SCALE: float = SECONDS_PER_GAME_DAY / LEGACY_DAY_SECONDS
## Pins rotate monthly now that days fly by.
const PIN_ROTATION_INTERVAL_DAYS: int = 30
## Autosave cadence (days). Annual autosaves also fire on year_ended.
const AUTOSAVE_INTERVAL_DAYS: int = 30

func _ready() -> void:
	print("GameManager initialized")
	# Connect signals for daily statistics tracking
	EventBus.green_fee_paid.connect(_on_green_fee_paid_for_stats)
	EventBus.golfer_finished_hole.connect(_on_golfer_finished_hole_for_stats)
	EventBus.golfer_completed_round.connect(_on_golfer_finished_round_for_stats)
	EventBus.hole_created.connect(_on_hole_created_for_fee_clamp)

func _on_hole_created_for_fee_clamp(_hole_number: int, _par: int, _distance: int) -> void:
	clamp_green_fee_to_max()

func _on_green_fee_paid_for_stats(_golfer_id: int, _golfer_name: String, amount: int) -> void:
	daily_stats.record_green_fee(amount)

func _on_golfer_finished_hole_for_stats(_golfer_id: int, hole_number: int, strokes: int, par: int) -> void:
	daily_stats.record_hole_score(strokes, par)

	# Record per-hole cumulative stats
	# golfer_finished_hole already carries the public, one-based hole number.
	if not hole_statistics.has(hole_number):
		hole_statistics[hole_number] = HoleStatistics.new(hole_number)
	hole_statistics[hole_number].record_score(strokes, par)

func _on_golfer_finished_round_for_stats(_golfer_id: int, total_strokes: int, total_par: int) -> void:
	daily_stats.record_round_finished(total_strokes, total_par)


func _process(delta: float) -> void:
	if current_mode == GameMode.SIMULATING and not is_paused and current_speed != GameSpeed.PAUSED:
		_advance_time(delta)

## Seconds elapsed towards the next day (scaled by Engine.time_scale).
var _day_progress: float = 0.0

func _advance_time(delta: float) -> void:
	# The course never closes: days simply roll over once
	# SECONDS_PER_GAME_DAY seconds have passed. Note: delta is already
	# scaled by Engine.time_scale (set in set_speed).
	_day_progress += delta
	# The while loop keeps rollovers sequential when a frame spans multiple
	# days (e.g. hitches at ULTRA speed). A rollover may pause the game
	# (year-end summary, bankruptcy) — stop advancing immediately if so.
	while _day_progress >= SECONDS_PER_GAME_DAY and not is_paused:
		_day_progress -= SECONDS_PER_GAME_DAY
		_complete_day()

func _complete_day() -> void:
	# Bookkeeping for the day that just finished (operating costs, weed
	# growth, staff payroll, digests) runs synchronously in the handlers.
	EventBus.end_of_day.emit(current_day)
	advance_to_next_day()

func set_mode(new_mode: GameMode) -> void:
	var old_mode = current_mode
	current_mode = new_mode
	# Keep the engine clock in sync (menus and build mode run at real-time speed)
	_sync_time_scale()
	EventBus.game_mode_changed.emit(old_mode, new_mode)

## The speed controls carry a single fast-forward button that owns both
## accelerated tiers, so it steps between them instead of the player hunting
## for a separate ULTRA button.
static func is_fast_forward_speed(speed: int) -> bool:
	"""True while running at one of the accelerated tiers the toggle owns."""
	return speed == GameSpeed.FAST or speed == GameSpeed.ULTRA

static func next_fast_forward_speed(current: int) -> GameSpeed:
	"""Speed the fast-forward button switches to when pressed at `current`.

	From either tier it flips to the other one. From normal or paused it enters
	Fast first, so one press never jumps straight to the 8x tier.
	"""
	if current == GameSpeed.FAST:
		return GameSpeed.ULTRA
	return GameSpeed.FAST

func cycle_fast_forward_speed() -> GameSpeed:
	"""Press the combined fast-forward button: swap between Fast and Ultra."""
	set_speed(next_fast_forward_speed(current_speed))
	return current_speed

func set_speed(new_speed: GameSpeed) -> void:
	current_speed = new_speed
	# Use Engine.time_scale so ALL game systems (golfer movement, ball flight,
	# tweens, timers) scale uniformly — not just the clock.
	# PAUSED drops the scale to 0 so the whole simulation actually stops.
	_sync_time_scale()
	EventBus.game_speed_changed.emit(new_speed)

func toggle_pause() -> void:
	is_paused = not is_paused
	EventBus.pause_toggled.emit(is_paused)

func _sync_time_scale() -> void:
	"""Keep Engine.time_scale in sync with game mode, speed, and pause state.

	While simulating, the scale is the speed multiplier. When the game is
	paused (pause menu, year-end summary, game over, or the speed
	controls' pause button), the scale is 0 so the entire simulation —
	golfers, balls, shots, tweens, spawn timers — freezes.
	"""
	if current_mode != GameMode.SIMULATING and current_mode != GameMode.PLAYING:
		Engine.time_scale = 1.0
		return
	if is_paused or current_speed == GameSpeed.PAUSED:
		Engine.time_scale = 0.0
	else:
		Engine.time_scale = float(current_speed)

func modify_money(amount: int) -> void:
	var old_money = money
	money += amount
	EventBus.money_changed.emit(old_money, money)

func can_afford(cost: int) -> bool:
	"""Check if a purchase is allowed (not blocked by bankruptcy threshold)."""
	if cost <= 0:
		return true  # Not a purchase
	return money - cost >= bankruptcy_threshold

func is_bankrupt() -> bool:
	return money < bankruptcy_threshold

func take_loan(amount: int) -> bool:
	amount = clampi(amount, 10000, MAX_LOAN)
	if loan_balance + amount > MAX_LOAN:
		EventBus.notify("Maximum loan is $%d" % MAX_LOAN, "error")
		return false
	loan_balance += amount
	modify_money(amount)
	EventBus.log_transaction("Loan taken", amount)
	EventBus.notify("Loan: +$%d (Total debt: $%d)" % [amount, loan_balance], "info")
	return true

func repay_loan(amount: int) -> bool:
	if loan_balance <= 0:
		EventBus.notify("No outstanding loans", "info")
		return false
	amount = mini(amount, loan_balance)
	if not can_afford(amount):
		EventBus.notify("Not enough money to repay", "error")
		return false
	loan_balance -= amount
	modify_money(-amount)
	EventBus.log_transaction("Loan repayment", -amount)
	EventBus.notify("Repaid $%d (Remaining: $%d)" % [amount, loan_balance], "info")
	return true

func _process_loan_interest() -> void:
	if loan_balance <= 0:
		return
	var interest = int(loan_balance * LOAN_ANNUAL_INTEREST_RATE)
	if interest < 1:
		interest = 1
	loan_balance += interest
	EventBus.notify("Annual loan interest: +$%d debt (Balance: $%d)" % [interest, loan_balance], "warning")

func _archive_daily_stats() -> void:
	var satisfaction = 0.5
	if FeedbackManager:
		satisfaction = FeedbackManager.get_satisfaction_rating()
	var season = SeasonSystem.get_season(current_day)
	var entry = {
		"day": current_day,
		"revenue": daily_stats.get_total_revenue(),
		"costs": daily_stats.operating_costs,
		"profit": daily_stats.get_profit(),
		"golfers_served": daily_stats.golfers_served,
		"golfers_arrived": daily_stats.golfers_arrived,
		"satisfaction": satisfaction,
		"reputation": reputation,
		"season": season,
		"tier_counts": daily_stats.tier_counts.duplicate(),
	}
	entry["guest_experience"] = FeedbackManager.visit_summary()
	daily_history.append(entry)
	while daily_history.size() > MAX_DAILY_HISTORY:
		daily_history.pop_front()
	_log_economic_snapshot()

func _log_economic_snapshot() -> void:
	if not economic_snapshots_enabled:
		return
	var snapshot = {
		"day": current_day,
		"money": money,
		"revenue": daily_stats.get_total_revenue(),
		"costs": daily_stats.operating_costs,
		"profit": daily_stats.get_profit(),
		"reputation": reputation,
		"golfers_served": daily_stats.golfers_served,
		"golfers_arrived": daily_stats.golfers_arrived,
		"overall_rating": course_rating.get("overall", 3.0),
		"stars": course_rating.get("stars", 3),
		"hole_count": get_open_hole_count(),
		"green_fee": green_fee,
		"loan_balance": loan_balance,
		"difficulty": DifficultyPresets.to_string_name(current_difficulty),
	}
	var snapshots: Array = []
	if FileAccess.file_exists(SNAPSHOT_PATH):
		var existing_file = FileAccess.open(SNAPSHOT_PATH, FileAccess.READ)
		if existing_file:
			var existing = JSON.parse_string(existing_file.get_as_text())
			existing_file.close()
			if existing is Array:
				snapshots = existing
	snapshots.append(snapshot)
	var file = FileAccess.open(SNAPSHOT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(snapshots, "\t"))
		file.close()

func modify_reputation(amount: float) -> void:
	var old_rep = reputation
	reputation = clamp(reputation + amount, 0.0, 100.0)
	EventBus.reputation_changed.emit(old_rep, reputation)

func set_green_fee(new_fee: int) -> void:
	var old_fee = green_fee
	var effective_max = get_effective_max_green_fee()
	green_fee = clamp(new_fee, MIN_GREEN_FEE, effective_max)
	EventBus.green_fee_changed.emit(old_fee, green_fee)

func get_hole_statistics(hole_number: int) -> HoleStatistics:
	"""Get cumulative statistics for a specific hole"""
	if hole_statistics.has(hole_number):
		return hole_statistics[hole_number]
	return null

func update_course_rating() -> void:
	"""Recalculate course rating based on current state"""
	if not current_course or not terrain_grid:
		return
	course_rating = CourseRatingSystem.calculate_rating(
		terrain_grid, current_course, daily_stats, green_fee, reputation, entity_layer
	)
	EventBus.course_rating_changed.emit(course_rating)

func get_open_hole_count() -> int:
	"""Get the number of open (playable) holes on the course"""
	if not current_course:
		return 0
	return current_course.get_open_holes().size()

func get_effective_max_green_fee() -> int:
	"""Get the maximum green fee allowed based on hole count.
	More holes = higher max fee. Prevents 1-hole courses charging $200."""
	var holes = get_open_hole_count()
	if holes <= 0:
		return MIN_GREEN_FEE
	# $10 per hole, minimum $10
	return max(MIN_GREEN_FEE, min(holes * 10, MAX_GREEN_FEE))

func clamp_green_fee_to_max() -> void:
	"""Re-clamp green fee after hole count changes."""
	var effective_max = get_effective_max_green_fee()
	if green_fee > effective_max:
		set_green_fee(effective_max)

func process_green_fee_payment(golfer_id: int, golfer_name: String) -> bool:
	"""Process a golfer's green fee payment and return success.
	Revenue = per-hole fee x number of open holes."""
	var holes = get_open_hole_count()
	var total = green_fee * max(holes, 1)

	if current_course:
		for hole in current_course.get_open_holes():
			hole.total_revenue += green_fee
	modify_money(total)
	EventBus.log_transaction("%s paid green fee (%d holes x $%d)" % [golfer_name, holes, green_fee], total)
	EventBus.green_fee_paid.emit(golfer_id, golfer_name, total)
	return true

## Check and update hole records (call when golfer finishes a hole)
## Returns array of record types broken
func check_hole_records(golfer_name: String, hole_number: int, strokes: int) -> Array:
	var records_broken: Array = []

	# Check hole-in-one
	if strokes == 1:
		course_records.total_hole_in_ones += 1
		var entry = CourseRecords.RecordEntry.new(golfer_name, 1, current_day, hole_number)
		course_records.hole_in_ones.append(entry)
		records_broken.append({"type": "hole_in_one", "hole": hole_number})
		EventBus.record_broken.emit("hole_in_one", golfer_name, 1, hole_number)

	# Check best score for this hole
	var current_best = course_records.best_per_hole.get(hole_number)
	if current_best == null or strokes < current_best.value:
		var entry = CourseRecords.RecordEntry.new(golfer_name, strokes, current_day, hole_number)
		course_records.best_per_hole[hole_number] = entry
		if current_best != null:  # Only announce if breaking existing record
			records_broken.append({"type": "hole_record", "hole": hole_number, "strokes": strokes})
			EventBus.record_broken.emit("hole_record", golfer_name, strokes, hole_number)

	return records_broken

## Check if golfer set the course record (call when round finishes)
## Returns true if new course record was set
func check_round_record(golfer_name: String, total_strokes: int, holes_played: int = 0) -> bool:
	# Sanity check: reject impossibly low scores (minimum 1 stroke per hole)
	if holes_played > 0 and total_strokes < holes_played:
		return false
	var current = course_records.lowest_round
	if current == null or total_strokes < current.value:
		course_records.lowest_round = CourseRecords.RecordEntry.new(
			golfer_name, total_strokes, current_day, -1
		)
		EventBus.record_broken.emit("course_record", golfer_name, total_strokes, -1)
		return true
	return false

## Reset course records (for new game)
func reset_course_records() -> void:
	course_records = CourseRecords.create_empty_records()

func new_game(course_name_input: String = "New Course", theme: int = CourseTheme.Type.PARKLAND, difficulty: int = DifficultyPresets.Preset.NORMAL) -> void:
	player_profile = PlayerGolferProfile.new()
	course_name = course_name_input
	current_theme = theme
	current_difficulty = difficulty

	# Apply difficulty preset modifiers
	var diff_mods := DifficultyPresets.get_modifiers(difficulty)
	money = diff_mods.get("starting_money", DEFAULT_STARTING_MONEY)
	bankruptcy_threshold = diff_mods.get("bankruptcy_threshold", -1000)

	reputation = DEFAULT_STARTING_REPUTATION
	# New games begin on the morning of Saturday, 1 January 2000.
	current_day = 1
	_day_progress = 0.0
	# A new game always starts unpaused (stale pause state from a previous session)
	is_paused = false

	current_course = CourseData.new()
	# Apply theme gameplay modifiers
	var modifiers = CourseTheme.get_gameplay_modifiers(theme)
	green_fee = modifiers.get("green_fee_baseline", 30)
	clamp_green_fee_to_max()  # Clamp to what current hole count allows

	daily_stats.reset()
	yesterday_stats = null  # No yesterday on day 1
	yearly_stats.reset()
	previous_year_stats = null
	prior_year_stats = null
	yearly_days = 0
	yearly_satisfaction_sum = 0.0
	previous_year_satisfaction = -1.0
	_daily_charge_carries.clear()
	hole_statistics.clear()  # Clear per-hole stats for new game
	reset_course_records()  # Clear records for new game
	if shot_heatmap_tracker:
		shot_heatmap_tracker.clear()
	loan_balance = 0
	tee_booking_interval = 90
	daily_history.clear()
	FeedbackManager.restore_experience({})
	FeedbackManager.reset_daily_stats()
	_stagnation_hole_count = 0
	_stagnation_day_started = 1
	heightmap_noise_seed = randi()

	# Apply theme colors to tileset generator (with colorblind remapping if active)
	var base_colors := CourseTheme.get_terrain_colors(theme)
	var remapped := ColorblindMode.remap_colors(base_colors, colorblind_mode)
	TilesetGenerator.set_theme_colors(remapped)
	EventBus.theme_changed.emit(theme)

	SaveManager.current_save_name = ""
	set_mode(GameMode.SIMULATING)
	set_speed(GameSpeed.NORMAL)
	EventBus.new_game_started.emit()

## Per-day cost scaling: legacy daily rates (tuned for 1680-second days) are
## scaled to the 3.5-second day via DAILY_RATE_SCALE, then collected in
## per-category float carries so sub-dollar amounts are not rounded away.
## Each category charges whole dollars as soon as its carry reaches $1.
var _daily_charge_carries: Dictionary = {}

func apply_daily_charge(category: String, legacy_daily_amount: float) -> int:
	var carry: float = float(_daily_charge_carries.get(category, 0.0))
	var total := carry + legacy_daily_amount * DAILY_RATE_SCALE
	var charge := int(floor(total))
	_daily_charge_carries[category] = total - charge
	return charge

func get_date_string() -> String:
	"""Current in-game date for HUD display, e.g. \"Sat 1 Jan 2000\"."""
	return GameCalendar.format_date(current_day)

func get_current_year() -> int:
	return GameCalendar.get_year(current_day)

func advance_to_next_day() -> void:
	"""Roll over into the next calendar day after end-of-day bookkeeping.
	Called automatically every SECONDS_PER_GAME_DAY seconds — the course never
	closes, so there is no summary pause except at the end of the year."""
	# Reputation decay scales with course quality and difficulty
	# Below 3 stars: accelerated. Above 3: reduced. Always present.
	if reputation > 0:
		var stars = course_rating.get("stars", 3)
		var decay: float
		if stars < 3:
			decay = 1.0
		elif stars == 3:
			decay = 0.5
		elif stars == 4:
			decay = 0.25
		else:
			decay = 0.1
		var diff_mods := DifficultyPresets.get_modifiers(current_difficulty)
		decay *= diff_mods.get("reputation_decay_multiplier", 1.0)
		modify_reputation(-decay * DAILY_RATE_SCALE)

	# Stagnation penalty: courses that don't expand slowly lose reputation
	var current_hole_count = get_open_hole_count()
	if current_hole_count != _stagnation_hole_count:
		_stagnation_hole_count = current_hole_count
		_stagnation_day_started = current_day
	var stagnation_days = current_day - _stagnation_day_started
	if stagnation_days > STAGNATION_DAYS_THRESHOLD and reputation > STAGNATION_REPUTATION_FLOOR:
		modify_reputation(-STAGNATION_DECAY_PENALTY * DAILY_RATE_SCALE)

	# Detect season change for next day
	var old_season = SeasonSystem.get_season(current_day)
	var new_season = SeasonSystem.get_season(current_day + 1)
	if old_season != new_season:
		EventBus.season_changed.emit(old_season, new_season)

	# Check for upcoming seasonal events (two-week advance warning)
	var upcoming = SeasonalEvents.get_upcoming_events(current_day, 15)
	for entry in upcoming:
		if entry.days_until <= 14:
			EventBus.seasonal_event_upcoming.emit(entry.event.name, entry.days_until)

	# Archive today's stats for analytics (rolling 30-day history)
	_archive_daily_stats()

	# Accumulate the finished day into the year-to-date totals
	_accumulate_yearly_stats()

	# Save yesterday's stats before resetting
	yesterday_stats = DailyStatistics.new()
	yesterday_stats.golfers_arrived = daily_stats.golfers_arrived
	yesterday_stats.hired_staff_payroll = daily_stats.hired_staff_payroll
	yesterday_stats.marketing_cost = daily_stats.marketing_cost
	yesterday_stats.revenue = daily_stats.revenue
	yesterday_stats.building_revenue = daily_stats.building_revenue
	yesterday_stats.operating_costs = daily_stats.operating_costs
	yesterday_stats.terrain_maintenance = daily_stats.terrain_maintenance
	yesterday_stats.base_operating_cost = daily_stats.base_operating_cost
	yesterday_stats.staff_wages = daily_stats.staff_wages
	yesterday_stats.building_operating_costs = daily_stats.building_operating_costs
	yesterday_stats.golfers_served = daily_stats.golfers_served
	yesterday_stats.tournament_revenue = daily_stats.tournament_revenue
	yesterday_stats.tournament_entry_fee = daily_stats.tournament_entry_fee
	yesterday_stats.holes_in_one = daily_stats.holes_in_one
	yesterday_stats.eagles = daily_stats.eagles
	yesterday_stats.birdies = daily_stats.birdies
	yesterday_stats.pars = daily_stats.pars
	yesterday_stats.bogeys_or_worse = daily_stats.bogeys_or_worse
	yesterday_stats.total_strokes_today = daily_stats.total_strokes_today
	yesterday_stats.total_par_today = daily_stats.total_par_today
	yesterday_stats.tier_counts = daily_stats.tier_counts.duplicate()

	# Reset daily statistics for the new day
	daily_stats.reset()

	var day_ending := current_day
	current_day += 1
	EventBus.day_changed.emit(current_day)
	# Wind drifts daily via WindSystem's day_changed signal handler
	# Rotate pin positions monthly so putts are not chased across the green
	if current_day % PIN_ROTATION_INTERVAL_DAYS == 0:
		_rotate_pin_positions()

	# Year rollover: December 31 has just completed. Park the year's totals
	# for the summary panel, charge annual loan interest, and let the UI show
	# the year-end summary (which pauses the game).
	if GameCalendar.is_first_day_of_year(current_day):
		_roll_over_year(GameCalendar.get_year(day_ending))

func _rotate_pin_positions() -> void:
	if not current_course:
		return
	var any_rotated := false
	for hole in current_course.holes:
		if hole.pin_positions.size() > 1:
			hole.current_pin_index = (hole.current_pin_index + 1) % hole.pin_positions.size()
			hole.hole_position = hole.pin_positions[hole.current_pin_index]
			any_rotated = true
	if any_rotated:
		EventBus.pins_rotated.emit()

## Add the day that just finished into the year-to-date totals.
func _accumulate_yearly_stats() -> void:
	yearly_stats.accumulate_from(daily_stats)
	yearly_days += 1
	if FeedbackManager:
		yearly_satisfaction_sum += FeedbackManager.get_satisfaction_rating()

## Calendar year rollover (after December 31 completes). Runs once the day has
## already incremented to January 1 of the new year.
func _roll_over_year(finished_year: int) -> void:
	# Annual loan interest
	_process_loan_interest()

	# Park the completed year for the summary panel and next year's trends
	prior_year_stats = previous_year_stats
	previous_year_stats = yearly_stats
	previous_year_satisfaction = (
		yearly_satisfaction_sum / float(yearly_days) if yearly_days > 0 else 0.5)
	yearly_stats = DailyStatistics.new()
	yearly_days = 0
	yearly_satisfaction_sum = 0.0

	EventBus.year_ended.emit(finished_year)

func can_start_playing() -> bool:
	"""Check if the course is ready to start playing (has at least one open hole)"""
	if not current_course:
		return false
	return current_course.get_open_holes().size() > 0

func start_simulation() -> bool:
	"""Attempt to start the simulation mode"""
	if not can_start_playing():
		EventBus.notify("Need at least one hole to start playing!", "error")
		return false

	set_mode(GameMode.SIMULATING)
	set_speed(GameSpeed.NORMAL)
	EventBus.notify("Golf course opened!", "info")
	return true

func stop_simulation() -> void:
	"""Legacy: kept for save compat. Day always runs — resumes instead of pausing."""
	set_mode(GameMode.SIMULATING)
	set_speed(GameSpeed.NORMAL)
	EventBus.notify("Tycoon mode — build while you play!", "info")

func get_maintenance_multiplier() -> float:
	"""Get the combined maintenance cost multiplier from theme and difficulty."""
	var theme_mods := CourseTheme.get_gameplay_modifiers(current_theme)
	var diff_mods := DifficultyPresets.get_modifiers(current_difficulty)
	return theme_mods.get("maintenance_cost_multiplier", 1.0) * diff_mods.get("maintenance_multiplier", 1.0)

func get_spawn_rate_multiplier() -> float:
	"""Get the difficulty-adjusted golfer spawn rate multiplier."""
	var diff_mods := DifficultyPresets.get_modifiers(current_difficulty)
	return diff_mods.get("spawn_rate_multiplier", 1.0)

func set_colorblind_mode(mode: int) -> void:
	"""Set colorblind mode and refresh terrain visuals."""
	colorblind_mode = mode
	# Re-apply theme colors through the colorblind filter
	var base_colors := CourseTheme.get_terrain_colors(current_theme)
	var remapped := ColorblindMode.remap_colors(base_colors, colorblind_mode)
	TilesetGenerator.set_theme_colors(remapped)
	EventBus.theme_changed.emit(current_theme)

func _exit_tree() -> void:
	# Disconnect signals to prevent memory leaks and double-callbacks on reload
	if EventBus.green_fee_paid.is_connected(_on_green_fee_paid_for_stats):
		EventBus.green_fee_paid.disconnect(_on_green_fee_paid_for_stats)
	if EventBus.golfer_finished_hole.is_connected(_on_golfer_finished_hole_for_stats):
		EventBus.golfer_finished_hole.disconnect(_on_golfer_finished_hole_for_stats)
	if EventBus.golfer_completed_round.is_connected(_on_golfer_finished_round_for_stats):
		EventBus.golfer_completed_round.disconnect(_on_golfer_finished_round_for_stats)
	if EventBus.hole_created.is_connected(_on_hole_created_for_fee_clamp):
		EventBus.hole_created.disconnect(_on_hole_created_for_fee_clamp)

class CourseData:
	var name: String = "New Course"
	var holes: Array = []
	var buildings: Array = []
	var terrain_data: Dictionary = {}
	var total_par: int = 0
	
	func add_hole(hole: HoleData) -> void:
		holes.append(hole)
		_recalculate_par()
	
	func _recalculate_par() -> void:
		total_par = 0
		for hole in holes:
			total_par += hole.par

	func get_open_holes() -> Array:
		var open: Array = []
		for hole in holes:
			if hole.is_open:
				open.append(hole)
		return open

	func toggle_hole_open(hole_number: int) -> bool:
		for hole in holes:
			if hole.hole_number == hole_number:
				hole.is_open = not hole.is_open
				EventBus.hole_toggled.emit(hole_number, hole.is_open)
				return hole.is_open
		return false

class HoleData:
	var hole_number: int = 1
	var par: int = 4
	var tee_position: Vector2i = Vector2i.ZERO
	var green_position: Vector2i = Vector2i.ZERO
	var hole_position: Vector2i = Vector2i.ZERO  # Actual cup position on green
	var fairway_tiles: Array = []
	var hazard_tiles: Array = []
	var distance_yards: int = 0
	var is_open: bool = true  # Whether the hole is open for play
	var difficulty_rating: float = 1.0  # Hole difficulty (1.0-10.0)
	var stroke_index: int = 0  # Handicap allocation ranking (1=hardest, N=easiest), derived from difficulty_rating
	var total_revenue: int = 0  # Cumulative green fee revenue attributed to this hole
	var par_override: int = -1  # -1 = auto par from distance, >0 = manual override

	# Multiple tee boxes: forward (red), middle (white), back (blue)
	var tee_positions: Dictionary = {}  # {"forward": Vector2i, "middle": Vector2i, "back": Vector2i}
	var par_by_tee: Dictionary = {}     # {"forward": int, "middle": int, "back": int}

	# Pin positions: up to 4 locations on the green, rotated daily
	var pin_positions: Array = []       # Array[Vector2i]
	var current_pin_index: int = 0

	## Keep tee_position synced with back tee (backward compat for 30+ consumers)
	func sync_tee_positions() -> void:
		if tee_positions.has("back"):
			tee_position = tee_positions["back"]

	## Keep hole_position synced with current pin (backward compat for 30+ consumers)
	func sync_pin_position() -> void:
		if pin_positions.size() > 0 and current_pin_index < pin_positions.size():
			hole_position = pin_positions[current_pin_index]

	## Return the appropriate tee position for a golfer tier
	func get_tee_for_tier(tier: int) -> Vector2i:
		if tee_positions.is_empty():
			return tee_position
		match tier:
			GolferTier.Tier.BEGINNER:
				return tee_positions.get("forward", tee_position)
			GolferTier.Tier.CASUAL:
				if randf() < 0.5:
					return tee_positions.get("forward", tee_position)
				return tee_positions.get("middle", tee_position)
			GolferTier.Tier.SERIOUS:
				if randf() < 0.5:
					return tee_positions.get("middle", tee_position)
				return tee_positions.get("back", tee_position)
			GolferTier.Tier.PRO:
				return tee_positions.get("back", tee_position)
			_:
				return tee_position

	## Auto-generate forward (60%) and middle (75%) tee positions along tee-to-green line
	func auto_generate_tee_positions(grid: TerrainGrid) -> void:
		if not grid:
			return
		var back_tee = tee_position
		var green = green_position
		var direction = Vector2(green - back_tee)
		var length = direction.length()
		if length < 2.0:
			# Hole too short to differentiate tees
			tee_positions = {"forward": back_tee, "middle": back_tee, "back": back_tee}
			return

		# Forward tee at 60% of distance, middle at 75%
		var forward_t = 0.4  # 60% of distance means 40% along tee→green
		var middle_t = 0.25  # 75% of distance means 25% along tee→green
		var forward_pos = Vector2i(Vector2(back_tee) + direction * forward_t)
		var middle_pos = Vector2i(Vector2(back_tee) + direction * middle_t)

		# Ensure positions are valid grid positions
		if grid.is_valid_position(forward_pos):
			tee_positions["forward"] = forward_pos
		else:
			tee_positions["forward"] = back_tee
		if grid.is_valid_position(middle_pos):
			tee_positions["middle"] = middle_pos
		else:
			tee_positions["middle"] = back_tee
		tee_positions["back"] = back_tee

	## Auto-generate up to 4 pin positions spread across the green
	func auto_generate_pin_positions(grid: TerrainGrid) -> void:
		if not grid:
			return
		# Find all green tiles using flood fill from green_position
		var green_tiles: Array = []
		var to_check: Array = [green_position]
		var checked: Dictionary = {}
		while to_check.size() > 0 and green_tiles.size() < 100:
			var pos = to_check.pop_front()
			if checked.has(pos):
				continue
			checked[pos] = true
			if not grid.is_valid_position(pos):
				continue
			if grid.get_tile(pos) != TerrainTypes.Type.GREEN:
				continue
			green_tiles.append(pos)
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var neighbor = pos + offset
				if not checked.has(neighbor):
					to_check.append(neighbor)

		if green_tiles.size() == 0:
			pin_positions = [hole_position]
			return

		if green_tiles.size() <= 2:
			# Too small for multiple pins — use center only
			pin_positions = [hole_position]
			return

		# Compute green center
		var center = Vector2.ZERO
		for tile in green_tiles:
			center += Vector2(tile)
		center /= float(green_tiles.size())

		# Direction from tee to green for front/back orientation
		var tee_dir = Vector2(green_position - tee_position).normalized()
		var perp_dir = Vector2(-tee_dir.y, tee_dir.x)

		# Score each green tile by quadrant (front-left, front-right, back-left, back-right)
		var quadrants: Dictionary = {"fl": [], "fr": [], "bl": [], "br": []}
		for tile in green_tiles:
			var rel = Vector2(tile) - center
			var front_back = rel.dot(tee_dir)  # positive = toward tee (front), negative = away (back)
			var left_right = rel.dot(perp_dir)  # positive = left, negative = right
			var key = ("f" if front_back >= 0 else "b") + ("l" if left_right >= 0 else "r")
			quadrants[key].append(tile)

		# Pick the tile furthest from center in each populated quadrant
		var pins: Array = []
		for qkey in ["fl", "fr", "bl", "br"]:
			var tiles = quadrants[qkey]
			if tiles.size() == 0:
				continue
			var best_tile = tiles[0]
			var best_dist: float = 0.0
			for tile in tiles:
				var dist = Vector2(tile).distance_to(center)
				if dist > best_dist:
					best_dist = dist
					best_tile = tile
			pins.append(best_tile)

		# Ensure current hole_position is included (or at least the first pin)
		if pins.size() == 0:
			pins = [hole_position]
		pin_positions = pins
		current_pin_index = 0
		hole_position = pin_positions[0]

	## Recalculate par for each tee position based on distance
	func recalculate_par_by_tee(grid: TerrainGrid) -> void:
		if not grid or tee_positions.is_empty():
			return
		for tee_key in tee_positions:
			var tee_pos = tee_positions[tee_key]
			var dist = grid.calculate_distance_yards(tee_pos, green_position)
			par_by_tee[tee_key] = GolfRules.calculate_par(dist)

	## Get par for a specific tee key ("forward", "middle", "back")
	func get_par_for_tee(tee_key: String) -> int:
		if par_by_tee.has(tee_key):
			return par_by_tee[tee_key]
		return par

## DailyStatistics - Tracks statistics for the current day
class DailyStatistics:
	var revenue: int = 0  # Green fees collected today
	var golfers_arrived: int = 0
	var hired_staff_payroll: int = 0
	var marketing_cost: int = 0
	var golfers_served: int = 0  # Number of golfers who finished their round
	var holes_in_one: int = 0
	var eagles: int = 0  # Par - 2 (or better on par 5s)
	var birdies: int = 0  # Par - 1
	var pars: int = 0  # Par scores
	var bogeys_or_worse: int = 0  # Par + 1 or worse (for pace indicator)
	var total_strokes_today: int = 0  # For calculating average score
	var total_par_today: int = 0  # For calculating average score
	var operating_costs: int = 0  # Total operating costs (sum of below)

	# Operating cost breakdown
	var terrain_maintenance: int = 0  # Cost from terrain upkeep
	var base_operating_cost: int = 0  # Fixed daily cost based on course size
	var staff_wages: int = 0  # Staff costs based on number of holes
	var building_operating_costs: int = 0  # Daily costs from buildings
	var decoration_operating_costs: int = 0  # Daily costs from decorations

	# Building revenue from amenities
	var building_revenue: int = 0

	# Tournament financials
	var tournament_revenue: int = 0  # Spectator + sponsorship income
	var tournament_entry_fee: int = 0  # Cost to host tournament

	# Golfer tier counts
	var tier_counts: Dictionary = {
		GolferTier.Tier.BEGINNER: 0,
		GolferTier.Tier.CASUAL: 0,
		GolferTier.Tier.SERIOUS: 0,
		GolferTier.Tier.PRO: 0,
	}

	func reset() -> void:
		revenue = 0
		golfers_arrived = 0
		hired_staff_payroll = 0
		marketing_cost = 0
		golfers_served = 0
		holes_in_one = 0
		eagles = 0
		birdies = 0
		pars = 0
		bogeys_or_worse = 0
		building_revenue = 0
		tournament_revenue = 0
		tournament_entry_fee = 0
		total_strokes_today = 0
		total_par_today = 0
		operating_costs = 0
		terrain_maintenance = 0
		base_operating_cost = 0
		staff_wages = 0
		building_operating_costs = 0
		decoration_operating_costs = 0
		tier_counts = {
			GolferTier.Tier.BEGINNER: 0,
			GolferTier.Tier.CASUAL: 0,
			GolferTier.Tier.SERIOUS: 0,
			GolferTier.Tier.PRO: 0,
		}

	## Calculate operating costs based on terrain and course size.
	## Rates are legacy per-day numbers scaled into the 3.5-second day via
	## GameManager.apply_daily_charge (DAILY_RATE_SCALE + carry), so the
	## real-time pace of the economy matches the legacy 6 AM–8 PM clock.
	## terrain_cost: total maintenance cost from terrain grid
	## hole_count: number of holes on the course
	## building_costs: total operating costs from all buildings
	func calculate_operating_costs(terrain_cost: int, hole_count: int, building_costs: int = 0, decoration_costs: int = 0) -> void:
		# Terrain maintenance from actual tiles, scaled by theme-aware seasonal modifier
		var season = SeasonSystem.get_season(GameManager.current_day)
		var season_mod = SeasonSystem.get_maintenance_modifier(season, GameManager.current_theme)
		terrain_maintenance = GameManager.apply_daily_charge("terrain", terrain_cost * season_mod)

		# Base operating cost
		base_operating_cost = GameManager.apply_daily_charge(
			"base", GameManager.BASE_DAILY_OVERHEAD + (hole_count * GameManager.PER_HOLE_DAILY_COST))

		# Staff wages based on tier
		var tier_data = GameManager.STAFF_TIER_DATA.get(GameManager.current_staff_tier, {})
		var cost_per_hole = tier_data.get("cost_per_hole", 10)
		staff_wages = GameManager.apply_daily_charge("staff_wages", hole_count * cost_per_hole)

		# Building operating costs (daily upkeep for amenities)
		building_operating_costs = GameManager.apply_daily_charge("buildings", building_costs)

		# Decoration operating costs (daily upkeep for decorations)
		decoration_operating_costs = GameManager.apply_daily_charge("decorations", decoration_costs)

		# Total
		operating_costs = terrain_maintenance + base_operating_cost + staff_wages + building_operating_costs + decoration_operating_costs

	func get_profit() -> int:
		return revenue + building_revenue + tournament_revenue - operating_costs - tournament_entry_fee

	## Add every field of another period's stats into this one. Used to build
	## the year-to-date totals from daily stats on each rollover.
	func accumulate_from(other: DailyStatistics) -> void:
		revenue += other.revenue
		golfers_arrived += other.golfers_arrived
		hired_staff_payroll += other.hired_staff_payroll
		marketing_cost += other.marketing_cost
		golfers_served += other.golfers_served
		holes_in_one += other.holes_in_one
		eagles += other.eagles
		birdies += other.birdies
		pars += other.pars
		bogeys_or_worse += other.bogeys_or_worse
		building_revenue += other.building_revenue
		tournament_revenue += other.tournament_revenue
		tournament_entry_fee += other.tournament_entry_fee
		total_strokes_today += other.total_strokes_today
		total_par_today += other.total_par_today
		operating_costs += other.operating_costs
		terrain_maintenance += other.terrain_maintenance
		base_operating_cost += other.base_operating_cost
		staff_wages += other.staff_wages
		building_operating_costs += other.building_operating_costs
		decoration_operating_costs += other.decoration_operating_costs
		for tier in tier_counts:
			tier_counts[tier] += int(other.tier_counts.get(tier, 0))

	func get_total_revenue() -> int:
		return revenue + building_revenue + tournament_revenue

	func get_average_score_to_par() -> float:
		if total_par_today == 0:
			return 0.0
		return float(total_strokes_today - total_par_today) / float(golfers_served) if golfers_served > 0 else 0.0

	func record_hole_score(strokes: int, par: int) -> void:
		var classification = GolfRules.classify_score(strokes, par)
		match classification:
			"hole_in_one": holes_in_one += 1
			"eagle": eagles += 1
			"birdie": birdies += 1
			"par": pars += 1
			"bogey", "double_bogey_plus": bogeys_or_worse += 1

	func record_round_finished(total_strokes: int, total_par: int) -> void:
		golfers_served += 1
		total_strokes_today += total_strokes
		total_par_today += total_par

	func record_green_fee(amount: int) -> void:
		golfers_arrived += 1
		revenue += amount

	func record_golfer_tier(tier: int) -> void:
		if tier in tier_counts:
			tier_counts[tier] += 1

## HoleStatistics - Tracks cumulative statistics for a single hole
class HoleStatistics:
	var hole_number: int = 0
	var total_rounds: int = 0
	var total_strokes: int = 0
	var eagles: int = 0
	var birdies: int = 0
	var pars: int = 0
	var bogeys: int = 0
	var double_bogeys_plus: int = 0
	var holes_in_one: int = 0
	var best_score: int = -1
	var best_scorer_name: String = ""

	func _init(hole_num: int = 0) -> void:
		hole_number = hole_num

	func record_score(strokes: int, par: int, golfer_name: String = "") -> void:
		total_rounds += 1
		total_strokes += strokes
		var classification = GolfRules.classify_score(strokes, par)
		match classification:
			"hole_in_one":
				holes_in_one += 1
				eagles += 1  # Hole-in-one counts as eagle or better
			"eagle": eagles += 1
			"birdie": birdies += 1
			"par": pars += 1
			"bogey": bogeys += 1
			"double_bogey_plus": double_bogeys_plus += 1

		# Track best score
		if best_score < 0 or strokes < best_score:
			best_score = strokes
			best_scorer_name = golfer_name

	func get_average_score() -> float:
		if total_rounds == 0:
			return 0.0
		return float(total_strokes) / float(total_rounds)

	func get_average_to_par(par: int) -> float:
		if total_rounds == 0:
			return 0.0
		return get_average_score() - float(par)
