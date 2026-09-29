# Tournament Simulation System

> Replaces the statistical scoring stub with shot-by-shot headless simulation using the real angular dispersion model, wind system, terrain interactions, and ShotAI decision-making.

## Overview

The TournamentSimulator (`scripts/systems/tournament_simulator.gd`) provides headless shot-by-shot simulation for tournament rounds. It reuses the same shot physics as live golfer play (angular dispersion, club selection, wind effects, terrain penalties) without requiring scene tree nodes.

## Multi-Round Format

| Tier | Rounds | Field (floor) | Cut |
|------|--------|---------------|-----|
| LOCAL | 1 | 12 | None |
| REGIONAL | 2 | 24 | None |
| NATIONAL | 4 | 48 | Top 50% after R2 |
| CHAMPIONSHIP | 4 | 72 | Top 40 + ties after R2 |

The field column is a **floor**: the simulation is asked for
`max(tier field, 2 × open holes)` competitors, because a tournament seats one
pairing (`GROUP_SIZE = 2`) on every open hole of the course.

### Round Pacing
A round runs for one tournament phase (`TOURNAMENT_PHASE_DAYS = 45` fast-calendar
days) and the next round starts the moment the previous one is scored — rounds are
not spread over the calendar. Round 1 is played live on the course; rounds 2+ are
simulated here. Anything the clock catches mid-round has its card completed with
`simulate_remaining()` so every entry in the field is measured over the same
circuit of holes.

## Field Generation

`generate_field(tier, field_size)` builds the professional entrants and numbers them
`-1, -2, …` so id `0` stays free: `TournamentManager` reserves it
(`PLAYER_SIM_ID = 0`) for the owner's entry and pushes it to the front of the field,
which is how the host ends up in the first pairing on the first hole. The owner's
`SimGolfer` takes its name and skills from `GameManager.player_profile`
(`normalized_skill()` for driving, accuracy, putting and recovery) rather than from
the tier distribution, so training the golfer changes tournament results.

## Shot Simulation Pipeline

Each simulated shot follows this pipeline:

### 1. Decision Phase (ShotAI)
```
GolferData snapshot → ShotAI.decide_shot_for() → ShotDecision {target, club, strategy}
```
Uses the same multi-shot planning, candidate evaluation, and risk analysis as live play.

### 2. Shot Execution (Angular Dispersion)
```
total_accuracy = club_accuracy × skill_accuracy × lie_modifier

max_spread_deg = (1.0 - total_accuracy) × 12.0°
spread_std_dev = max_spread / 2.5

base_angle = gaussian_random() × spread_std_dev
tendency_bias = miss_tendency × (1.0 - total_accuracy) × 6.0°
miss_angle = base_angle + tendency_bias

landing = from + rotated_direction × (distance × distance_modifier)
```

### 3. Distance Modifiers
```
distance_modifier = base_variance × terrain_modifier × wind_modifier × elevation_modifier
```

### 4. Post-Landing
Every hole is worth the par of the **back tee** (`_tournament_par()`), which is what
live play scores a hole against too — `HoleData.par` can sit a stroke away from it on
a course whose tee cards were adjusted separately, and mixing the two would make a
round played on the course incomparable with one filled in off it.
- Wind displacement applied
- Rollout estimated (simplified for performance)
- Hazard penalties (water: +1 stroke + drop; OOB: +1 stroke + replay)

### 5. Putting
Uses the probability-based make model from GolfRules:
```
make_rate = exp(-distance_feet × decay_constant × skill_multiplier)
```
Misses use gaussian-distributed distance and lateral errors capped to prevent cascading multi-putt cycles.

## Field Generation

Tournament fields are generated with tier-appropriate skill distributions:

### Tier Composition

| Tier | Casual | Serious | Pro |
|------|--------|---------|-----|
| LOCAL | 50% | 40% | 10% |
| REGIONAL | 20% | 50% | 30% |
| NATIONAL | 5% | 35% | 60% |
| CHAMPIONSHIP | 0% | 20% | 80% |

### Skill Floors
Skills are floored per tournament tier to ensure competitive fields:
- LOCAL: 0.55
- REGIONAL: 0.65
- NATIONAL: 0.75
- CHAMPIONSHIP: 0.85

### Marquee Golfers
Championship tournaments feature 4 "marquee" golfers with near-maximum skills (0.93-0.99) and recognizable names.

## Cut Line Mechanics

After round 2, higher-tier tournaments apply a cut:

### NATIONAL: Top 50%
```
cut_count = ceil(field_size / 2)
cut_score = standings[cut_count - 1].score_to_par
# All golfers at or better than cut_score advance (includes ties)
```

### CHAMPIONSHIP: Top 40 + Ties
```
cut_count = 40
cut_score = standings[39].score_to_par
# All golfers at or better than cut_score advance
```

## Dramatic Moment Detection

The simulator detects notable events during play:

| Event | Importance | Detail |
|-------|-----------|--------|
| Hole-in-One | 3 (Critical) | "Hole-in-one on Hole N!" |
| Albatross | 3 (Critical) | "Albatross on Hole N!" |
| Eagle | 2 (High) | "Eagle on Hole N" |

Moments are surfaced via `EventBus.tournament_moment` signal and displayed in the results popup.

### Drama Multiplier
Dramatic moments increase spectator revenue through a multiplier:
- Eagle: +5%
- Hole-in-One: +10%
- Albatross: +15%
- Lead Change: +5%
- Maximum multiplier: 1.5x (50% bonus)

## Performance

Target: Simulate one golfer's 18-hole round in <50ms.

Key optimizations:
- No scene tree nodes or rendering
- Simplified rollout (fraction-based rather than tile-by-tile)
- ShotAI reused as-is (already static)
- Per-shot terrain/wind lookups are fast (dictionary access)

## Integration

### Round 1: Live, Completed Headlessly
Round 1 spawns live golfer nodes on-course with skills matching the generated
SimGolfer field — one pairing per open hole, each seated on its own tee. A pairing
whose round is cut short by the clock (or by the shelf's "Play It Out") has its
missing holes simulated here with `simulate_remaining(golfer, start_hole, strokes,
par, holes_to_play)`; the count argument and the wrap over the open holes are what
keep a half-played card worth the same as a fully played one.

### Rounds 2+: Fully Simulated
Subsequent rounds call `TournamentSimulator.simulate_round()` for each active golfer,
updating the leaderboard with per-round scores.

### Leaderboard
The TournamentLeaderboard shows:
- Multi-round columns (R1, R2, R3, R4) with per-round score-to-par
- Cumulative total score
- Cut line separator between advancing and eliminated golfers
- "MC" (Missed Cut) label for eliminated golfers
- "F" for finished, hole count for in-progress

## Tuning Levers

| Parameter | Location | Default | Effect |
|-----------|----------|---------|--------|
| Skill floor per tier | `TournamentSimulator._get_skill_floor()` | 0.55-0.85 | Minimum skill in field |
| Tier composition | `TournamentSimulator._get_tier_composition()` | See table | Field quality mix |
| Cut rules | `TournamentManager.CUT_RULES` | Top 50%/40+ties | Cut strictness |
| Drama multiplier caps | `TournamentManager._calculate_drama_multiplier()` | 1.5x max | Revenue bonus |
| Max strokes per hole | `GolfRules.get_max_strokes()` | par + 3 | Pickup threshold |
| Rounds per tier | `TournamentManager.ROUNDS_PER_TIER` | 1/2/4/4 | Tournament length |
| Phase length per round | `TournamentManager.TOURNAMENT_PHASE_DAYS` | 45 days | How long round 1 may run live |
| Group size | `TournamentSystem.GROUP_SIZE` | 2 | Competitors per hole, and per pairing |
| Field size | `TournamentSystem.get_field_size()` | max(tier, 2 × holes) | Entries in the field |

## Files

- `scripts/systems/tournament_simulator.gd` — Core headless simulation engine
- `scripts/managers/tournament_manager.gd` — Multi-round lifecycle, cut lines, field management
- `scripts/systems/tournament_system.gd` — Tier data, qualification checks
- `scripts/ui/tournament_leaderboard.gd` — Multi-round leaderboard UI
- `scripts/ui/tournament_results_popup.gd` — Results popup with moments and per-round scores
