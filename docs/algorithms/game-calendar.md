# Game Calendar & Day Tempo

> **Source:** `scripts/systems/game_calendar.gd` and `scripts/autoload/game_manager.gd`

## Plain English

OpenGolf Tycoon runs on a real Gregorian calendar. New games begin on the
morning of **Saturday, 1 January 2000**. There is no day/night cycle and no
opening/closing window — the course never closes, so golfers keep arriving and
playing around the clock.

Each game day lasts **3.5 real seconds at normal speed** (scaled by the game
speed setting, so FAST halves it to ~1.17 s and ULTRA to ~0.44 s) before the
calendar rolls over to the next day.

Days roll over silently — economies settle, weeds sprout, weather drifts — but
the game never pauses except at the end of the year. When 31 December
completes, a **Year in Review** summary pauses the game, shows the year's
aggregated revenue/costs/profit, satisfaction and notable scores, and charges
annual loan interest (10% APR on the outstanding balance).

### Why real-time parity matters

The old clock ran 14 open hours at 2 minutes per game hour: one legacy day
took 1680 real seconds. The new day takes 3.5 seconds — roughly **1/480th** of
the old day. Per-day rates tuned for the legacy clock would be 480× too fast
if reused as-is, so legacy per-day rates are multiplied by
`GameManager.DAILY_RATE_SCALE` (≈ 1/480) before being applied. That keeps the
*real-time* pace of the economy (money per second, weeds per second,
reputation decay per second) exactly as tuned:

```
DAILY_RATE_SCALE = SECONDS_PER_GAME_DAY / LEGACY_DAY_SECONDS
                 = 3.5 / 1680.0  ≈  1/480
```

Charges that are too small to round to a whole dollar per day (e.g. a
municipal nine's $0.04/day staff wage) use a per-category float carry
(`GameManager.apply_daily_charge`) so small courses aren't free.

---

## Algorithm

### 1. Date arithmetic (GameCalendar)

Day 1 is anchored to the proleptic Gregorian date 1 Jan 2000 using Howard
Hinnant's civil-date algorithms:

```
_days_from_civil(y, m, d)  = days since 1970-01-01 for that date
_civil_from_days(z)        = inverse
_EPOCH_DAYS = _days_from_civil(2000, 1, 1) = 10957

get_date(day) → _civil_from_days(day - 1 + _EPOCH_DAYS)
get_weekday(day) → (day - 1 + 6) % 7    # day 1 was a Saturday (6)
get_year/get_month/get_day_of_year derived from get_date()
is_leap_year(y) → y%4==0 and (y%100!=0 or y%400==0)
```

Formatting helpers: `format_date` → "Sat 1 Jan 2000",
`format_date_short` → "1 Jan 2000", `format_date_long` →
"Saturday, January 1, 2000", `format_month` → "January 2000".

### 2. Day rollover (GameManager)

```gdscript
_day_progress += delta            # delta already scaled by Engine.time_scale
while _day_progress >= SECONDS_PER_GAME_DAY and not is_paused:
    _day_progress -= SECONDS_PER_GAME_DAY
    _complete_day()

func _complete_day():
    EventBus.end_of_day.emit(current_day)   # bookkeeping: costs, payroll, weeds
    advance_to_next_day()                   # stats archive, year rollover checks
```

`advance_to_next_day()` also handles the year boundary: when the new day is
1 January it parks the completed year's stats in `previous_year_stats`,
charges annual loan interest, and emits `EventBus.year_ended(finished_year)`
— which main.gd answers by pausing and opening `YearSummaryPanel`.

### 3. Yearly aggregation

`daily_stats` resets every day (powering the financial panel's year-to-date
view when combined with `yearly_stats`). On each rollover,
`yearly_stats.accumulate_from(daily_stats)` and the daily satisfaction sample
is added to `yearly_satisfaction_sum`. At year end:

```
prior_year_stats           = previous_year_stats   # keep one more year for trends
previous_year_stats        = yearly_stats
previous_year_satisfaction = yearly_satisfaction_sum / yearly_days
yearly_stats = new DailyStatistics;  yearly_days = 0;  yearly_satisfaction_sum = 0
```

---

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `SECONDS_PER_GAME_DAY` | 3.5 s | Real seconds per game day at NORMAL |
| `LEGACY_DAY_SECONDS` | 1680 s | Old 6 AM–8 PM day length (rate scaling reference) |
| `DAILY_RATE_SCALE` | ≈ 1/480 | Legacy per-day → new per-day rate factor |
| `AUTOSAVE_INTERVAL_DAYS` | 30 | Autosave every ~month + at year end |
| `LOAN_ANNUAL_INTEREST_RATE` | 10% | Charged on loan balance at year end |

---

## What replaced the old day/night cycle

| Old | New |
|---|---|
| 6 AM – 8 PM open hours, golfers leave at close | Course never closes; spawning is continuous |
| `EndOfDaySummary` every day (paused) | Silent daily rollover; `YearSummaryPanel` at year end |
| Hourly `hour_changed` ticks (sun arc, drift) | Daily `day_changed`; weather/wind evolve daily |
| DayNightSystem CanvasModulate tint by hour | WeatherTintSystem — fixed daylight, dimmed by weather |
| Window glow at 5 PM | Window glow when weather is CLOUDY or worse |
| 5% loan interest every 7 days | 10% APR loan interest at year end |
| Day = integer, Season = 7-day blocks on a 28-day year | Gregorian calendar; seasons = calendar quarters |
