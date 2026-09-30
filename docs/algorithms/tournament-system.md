# Tournament System

> **Status:** Active — implemented  
> **Scope:** Tournament tiers, hosting, entry qualification, field generation, multi-round play, cut rules, leaderboard, results, and rewards.

---

## 1. Summary

Tournaments are **management events the owner also plays**. Hosting one is an
immediate action: the click charges the entry fee, fills the field and sends the
first pairings out before the button has finished its press animation. There is no
diary, no "in 30 days", and no separate registration phase.

| Concept | Rule |
|---------|------|
| Start | `host_tournament()` on the click — the event is `IN_PROGRESS` the same frame |
| Field | The tier's nominal entry list, **grown so every open hole seats a pairing** |
| Group size | `TournamentSystem.GROUP_SIZE = 2` — two competitors per hole |
| Owner | Always in the field, at index 0, in the first pairing on hole 1 |
| Round 1 | Live: real `Golfer` nodes on the course, scored hole by hole |
| Rounds 2+ | Headless: `TournamentSimulator.simulate_round()` per competitor |
| Between rounds | Cut line where the tier defines one |
| Completion | Round 1 stays live until every on-course competitor finishes; later rounds simulate immediately |
| Cooldown | `TOURNAMENT_COOLDOWN` days after the event finishes |

```
Host Tournament (click) → charge entry fee → build field (owner + tier pros)
  → pair the field, one pairing per open hole → live round 1, scored as it is played
  → (per round) cut line where defined → rounds 2+ headless, back to back
  → complete → final in-tab leaderboard + results summary → payout → prestige + reputation → cooldown
```

---

## 2. Tournament Tiers

### Tier Configuration

From `TournamentSystem.TIER_DATA` (`scripts/systems/tournament_system.gd`):

| Tier | Rounds | Entry cost | Prize pool | Nominal field | Min holes | Min rating | Min difficulty | Min yardage | Rep reward |
|------|--------|-----------|------------|---------------|-----------|------------|----------------|-------------|------------|
| LOCAL | 1 | $500 | $1,000 | 12 | 4 | 2.0 | — | 1,500 | +15 |
| REGIONAL | 2 | $2,000 | $5,000 | 24 | 9 | 3.0 | 4.0 | 3,000 | +40 |
| NATIONAL | 4 | $10,000 | $25,000 | 48 | 18 | 4.0 | 5.0 | 6,000 | +100 |
| CHAMPIONSHIP | 4 | $50,000 | $100,000 | 72 | 18 | 4.5 | 6.0 | 6,500 | +300 |

`rounds` is `TournamentManager.ROUNDS_PER_TIER`; `min rating` and `min difficulty`
are checked against `GameManager.course_rating` (`overall` and `difficulty`, both on
the 0–5 scale the course rater produces), and `min yardage` against the summed
distance of the *open* holes.

### Tier Progression

Tiers are not unlocked by a switch: a bigger event is simply one your course can
qualify for. `TournamentSystem.get_qualified_tiers()` returns every tier the current
course satisfies and `TournamentPanel` renders one card each, so the ladder is
holes open → rating → difficulty → yardage → money.

---

## 3. Entry Qualification

```
function check_qualification(tier, course_data, course_rating):
    holes = course_data.holes if course_data != null else []   # see "No course data"
    open_holes, total_yardage = count_open(holes), sum_yardage(holes)

    missing = []
    if open_holes < tier.min_holes:      missing.push("Need {min_holes} holes (have {open_holes})")
    if rating.overall < tier.min_rating: missing.push("Need {..} star rating (have {..})")
    if rating.difficulty < tier.min_difficulty: missing.push("Need {..} difficulty (have {..})")
    if total_yardage < tier.min_yardage: missing.push("Need {..} yards (have {..})")
    return { qualified: missing.is_empty(), missing }
```

### The "no course data" dead end

`GameManager.current_course` is null before a course exists — a fresh boot, or a
session that never created one. `check_qualification()` treats that as *no holes*
and falls through to the ordinary requirement line, so the Host button reads
`Need 4 holes (have 0)` instead of "No course data". A greyed-out button must
always name the thing the player can go and do.

### Additional checks in `TournamentManager.can_schedule_tournament(tier)`

```
result = { can_schedule: true, reason: "" }
if state != NONE:                       return { false, "Tournament already running" }
if current_day - last_tournament_end_day < TOURNAMENT_COOLDOWN:
                                        return { false, "Must wait {n} more days" }
GameManager.update_course_rating()      # rates against the current build
if not check_qualification(...).qualified: return { false, missing[0] }
if money < tier.entry_cost:             return { false, "Need $.. to host" }
return result
```

`can_schedule_tournament()` never has side effects — it only re-rates the course.
`TournamentPanel` consumes `reason` as the disabled tooltip, so every rejection is
actionable rather than a dead end.

---

## 4. Hosting

```
function host_tournament(tier) -> bool:
    check = can_schedule_tournament(tier)
    if not check.can_schedule:
        EventBus.notify(check.reason, "warning")
        return false

    GameManager.deduct_money(tier.entry_cost, "Tournament Entry")
    if daily_stats: daily_stats.tournament_entry_fee += tier.entry_cost

    current_tournament_tier = tier
    state = IN_PROGRESS
    total_rounds = ROUNDS_PER_TIER[tier]
    current_round = 0
    tournament_start_day = GameManager.current_day

    tournament_scheduled.emit(tier, tournament_start_day)   # state, not a wait
    EventBus.tournament_scheduled.emit(tier, tournament_start_day)
    _start_tournament()
    return true
```

There is no `schedule_tournament()`: the old "book it and wait" entry point was
replaced by the one that charges and starts, and its enum state is only still read
so a save that holds a `SCHEDULED` event resolves — `_process()` starts it when its
day arrives, and `load_save_data()` downgrades a saved `IN_PROGRESS` event to
`NONE` (a live round is not resumable, and it must not linger after a load).

There is no tournament end date or countdown. The live round remains active until
every course competitor has finished; the round and event then complete from their
scorecards rather than from calendar time.

---

## 5. Field Generation

```
function _start_tournament():
    if GameManager.current_mode != SIMULATING: set_mode(SIMULATING)   # build → play
    _golfer_manager.clear_all_golfers()        # a hosted event owns the course
    reset live state, scorecards, cut lists, leaderboard

    field_size = TournamentSystem.get_field_size(tier, GameManager.get_open_hole_count())
    _sim_field = _build_field(field_size)
    _live_count = min(TournamentSystem.get_live_field_size(open_holes), _sim_field.size())
    register every field entry on the leaderboard     # the owner can find themselves
    _play_round(1)

function _build_field(n):
    field = TournamentSimulator.generate_field(tier, n - 1)   # ids -1, -2, ... downward
    field.push_front(_make_player_sim_golfer())                # id PLAYER_SIM_ID = 0
    return field
```

```
GROUP_SIZE = 2                                        # TournamentSystem
get_live_field_size(open_holes) = max(GROUP_SIZE, open_holes * GROUP_SIZE)
get_field_size(tier, open_holes) = max(TIER_DATA[tier].participant_count,
                                       get_live_field_size(open_holes))
```

Two competitors share a pairing, so the field needs `2 × open holes` bodies to put a
pairing on every hole; the tier's nominal entry list is the floor, never a cap. A
Local event on a 9-hole course therefore fields 18, not 12.

`PLAYER_SIM_ID = 0` is reserved for the owner because `generate_field()` numbers its
golfers `-1, -2, …`, so 0 can never collide. The owner leads the field list, which
puts them in group 0 — the pairing on the first open hole, the one a spectator sees
first and the one the camera finds.

**The owner's entry** is built from `GameManager.player_profile`: the name they chose
and `normalized_skill()` for driving (field 1), accuracy (3), putting (4) and
recovery (8), with `miss_tendency = 0`. Training the golfer on the Player tab
therefore changes their finishing position; a default, untrained profile is a
handicap against a professional field. On the course their golfer carries the
profile's colours via `apply_player_appearance()`.

### Field composition, names, skill floors and marquee golfers

Covered in [Tournament Simulation](tournament-simulation.md) — the same
`TournamentSimulator` generates the field for every tier.

---

## 6. Pacing and Rounds

There is no calendar phase or deadline. The live first round stays on the course
until every live competitor has holed out. Then the remaining unseated field is
scored, and later rounds (when applicable) are simulated back to back.

| Round | How it is played |
|-------|------------------|
| 1 | Live `Golfer` nodes on the course, pairings seated one per open hole |
| 2..N | Headless `TournamentSimulator.simulate_round()` per eligible competitor, starting as soon as the previous round is scored |

```
function _play_round(n):
    current_round = n
    round_started.emit(...)
    if n == 1: _start_live_round()
    else:      _simulate_round_headless(n)

function _finish_round(moments, was_live):     # the only path that closes a round
    emit the round's moments
    EventBus.tournament_round_completed.emit(tier, n, standings)
    if n == cut_rule.after_round: _apply_cut_line(cut_rule.rule)
    if n >= total_rounds: _complete_tournament(); return
    _play_round(n + 1)
```

The live round advances only when the final on-course competitor holes out
(`_check_live_round_completion()`). There is no day-rollover shortcut; the **Play It
Out** action is an explicit player choice to settle the field early.

### Round 1 — live play

```
_start_live_round():
    _total_groups = ceil(_live_count / GROUP_SIZE)     # one pairing per open hole
    _groups_spawned = 0, _spawn_timer = 0, _live_round_active = true

process(delta):                                        # while the live round runs
    _spawn_timer += delta
    if _spawn_timer >= GROUP_SPAWN_INTERVAL: _spawn_next_group()
```

`GROUP_SPAWN_INTERVAL = 0.5` game-seconds. That is a staggered tee sheet in fast
calendar terms — the whole field is out on the course within a few seconds of
hosting rather than trickling out over minutes.

`_spawn_next_group()` takes the next `GROUP_SIZE` entries of the live slice, spawns
them through `GolferManager.spawn_tournament_golfer(tier, group_id)`, and seats the
pairing on **its own hole**: group *i* plays open hole `i % open_holes`, placed on
that tee by `GolferManager.seat_golfer_at_hole()`. The field therefore opens with two
competitors on every hole instead of a queue behind the first tee. Pairings that
catch the group ahead on a hole wait for it to clear, which is the normal
`GolferManager` etiquette rule — no new logic.

Because a pair starts mid-circuit, a live round **wraps** back to the first tee
(`GolferManager._next_hole_for()`): a competitor plays the open holes forward from
their tee, then from the first tee round to the hole they started on, so every card
covers the circuit exactly once and "to par" means the same thing on every line. A
hole already on the card is never played twice — without that check a pairing that
teed off mid-course went round the turn and then back onto the holes it started on,
making its card longer than the rest of the field's. The owner's own rounds
(`is_owner_round`) never wrap.

The pairing also stays together through the turn.
`GolferManager._get_group_current_hole()` reads the group's hole from the competitor
who is furthest back in the round (fewest holes carded), **not** from the lowest hole
index. Index alone gets the turn wrong once a pair has wrapped: the partner who has
just holed out on the last green stands on hole index 0 while the other is still on
the last hole, and treating index 0 as the group's hole strands that partner — the
turn system stops selecting them, so they never walk round to the first tee at all.

Each live competitor is bound to their node (`TournamentLeaderboard.bind_live_golfer()`)
and scored from `EventBus.golfer_finished_hole`, which records strokes, par, the
holes carded and the hole index.

### Finishing the live round

After all live competitors finish (or the player explicitly chooses **Play It Out**),
remaining entries are settled in one pass (`_finish_live_round()`):

1. pairings whose tee time never came, and the field beyond the live seats, are
   scored headlessly for the whole round;
2. live golfers still out there have **exactly the holes they have not carded**
   filled in headlessly (`TournamentSimulator.simulate_remaining(..., holes_to_play)`,
   wrapping over the open holes), so every card in the field ends up covering the
   circuit once and "to par" means the same thing on every line;
3. the course is cleared of tournament golfers and the round goes to
   `_finish_round(moments, true)`.

### Skip to the end

The shelf's **Play It Out** button calls `simulate_remaining_and_complete()`: it
starts a `SCHEDULED` event if one is waiting, settles the live round in progress,
scores the remaining rounds headlessly and completes the event. It is bounded by
`total_rounds` so it can never loop.

`EventBus.tournament_simulation_started` is emitted for headless rounds only
(`n > 1`), so the 3D course and camera effects stay tied to golfers who are really
on it.

---

## 7. Cut Rules

From `TournamentManager.CUT_RULES`, applied in `_finish_round()` after the round the
rule follows:

| Tier | Rounds | Cut |
|------|--------|-----|
| LOCAL | 1 | none |
| REGIONAL | 2 | none |
| NATIONAL | 4 | Top 50% + ties after R2 |
| CHAMPIONSHIP | 4 | Top 40 + ties after R2 |

```
function _apply_cut_line(rule):
    standings = _get_standings()           # includes the owner
    keep, cut_score = rule(standings)
    _cut_golfer_ids = field ids at or better than cut_score
    _eliminated_ids = everyone else
    # leaderboard rows are flagged "MC"; cut players are skipped by later rounds
```

Cut golfers keep the score they made; they simply stop playing. `_get_active_field()`
filters them out of headless rounds, and `get_player_standing()` reports
`missed_cut` so the owner's scoreline on the shelf says so too.

---

## 8. Leaderboard

`TournamentLeaderboard` (`scripts/ui/tournament_leaderboard.gd`) shows one row per
field entry, including the owner:

| Column | Rule |
|--------|------|
| Pos | Rank, `T1` on ties |
| Player | Name; the owner's row is gold and carries `(you)` |
| R1..R4 | Score to par per round; `F` on the card of a golfer who has holed out |
| To Par | Cumulative |
| Total | Cumulative strokes |

Row shape: `register_golfer(golfer_id, name, sim_id = -1, is_player = false)`;
`has_golfer()` guards re-registration; `bind_live_golfer(sim_id, golfer_id)` links
the entry's node to its row so live scores flow through `update_score()`.

---

## 9. Results

`_complete_tournament()` assembles `tournament_results`, then clears the course and
resets live state:

```
tournament_results = {
    winner_name, winner_is_player, winning_score, par, scores,
    participant_count, prize_pool, rounds_played, total_rounds,
    all_entries: [{ name, score_to_par, round_scores, total_strokes, total_par,
                    is_player, missed_cut }, ...],
    moments, cut_golfers, eliminated_golfers,
    spectator_revenue, sponsorship_revenue, total_revenue,
    drama_multiplier, prestige_multiplier,
}
```

The winner is the top of `_get_standings()`. `winner_is_player` and each entry's
`is_player` drive the `(you)` marking in `tournament_results_popup.gd`, whose winner
line reads "... wins (you)" when the owner took the event.

Results are not persistent: they live in the `tournament_results` field and the
panel's "Previous Tournament Results" block.

---

## 10. Rewards

```
function _complete_tournament():
    drama = _calculate_drama_multiplier()                  # 1.0 + moments, capped at 1.5
    modify_money(-tier.prize_pool)                         # the course funds the purse
    spectator = int(tier.spectator_revenue * drama)
    modify_money(spectator + tier.sponsorship_revenue)
    daily_stats.tournament_revenue += spectator + tier.sponsorship_revenue

    prestige = SeasonSystem.get_tournament_prestige(current_day, current_theme)
    modify_reputation(int(tier.reputation_reward * prestige))
    _leaderboard.show_final_results()

    tournament_completed.emit(tier, tournament_results)
    EventBus.tournament_completed.emit(tier, tournament_results)
    last_tournament_end_day = GameManager.current_day      # cooldown starts here
    current_speed = _pre_tournament_speed                  # undo the auto fast-forward
    _golfer_manager.remove_tournament_golfers()             # nobody stays on the course
    state = NONE
```

The prize pool is a **cost** the host pays out, not income: a tournament nets
`entry_cost + spectator + sponsorship - prize_pool`, which is why the low tiers are
roughly break-even and the headline money is in the gate.

Course records are untouched by event play: `Golfer.finish_round()` only offers its
score to `GameManager.update_course_record()` when the round began on the first hole
and covered the circuit, and tournament scores are recorded against the field, not
the course.

---

## 11. UI Integration

### Tournament panel

`scripts/ui/tournament_panel.gd` renders one card per qualified tier with its
requirements and a **Host Tournament** button wired to `host_tournament()`; the
button's tooltip reads "Starts right away — you are in the field" when it is live.
Disabled buttons carry `can_schedule_tournament().reason`, one requirement at a time.

While an event runs, the tier cards are replaced by a single in-progress card: the
tier, current round, the owner's own scoreline (`You: -2 · rank 3 of 24 · 7
holes in (round 1)`), and the **Play It Out** shortcut. The live scorecard docks to
the top-left corner of the screen (`ScoresDock`, over the course view) while the shot
controls stay on the Play Course aiming page in the bottom bar. After completion, the
final leaderboard remains in that corner until the player returns to the course setup.
During the cooldown the panel shows one line and no tier cards at all.

The panel refreshes through `_process()`: `hole_created`, `hole_deleted`,
`hole_toggled`, `money_changed`, `day_changed`, `new_game_started` and
`load_completed` only set `_refresh_pending`, consumed at most every
`REFRESH_INTERVAL = 0.5` s and only while the panel is in the tree. Rebuilding the
whole shelf per signal was visible stutter on the frame a hole was toggled.

### Leaderboard and results

`TournamentLeaderboard` (`scripts/ui/tournament_leaderboard.gd`) is docked in the
top-left score corner (`ScoresDock`) for live scores and final standings, with
per-round scores, cut status, and the owner's row in gold. While docked it measures
its field and grows to fit, up to `DOCK_BODY_MAX_HEIGHT`, then scrolls. The post-event `TournamentResultsPopup`
continues to show highlights and the financial summary after the tournament.

### Event feed

`EventFeedManager._on_tournament_scheduled()` returns early when the event's start
day is today or earlier — which is every hosted event — so the feed carries one
"tournament started" line rather than a scheduled/started pair whose first entry
names a day that has already passed. A `SCHEDULED` event restored from an old save
still announces its future start day.

---

## 12. Tuning Knobs

| What | Where | Default | Notes |
|------|-------|---------|-------|
| Group size | `TournamentSystem.GROUP_SIZE` | 2 | Pairings per hole; also the field's growth rate |
| Live seats | `TournamentSystem.get_live_field_size()` | holes × 2 | Golfers that get a body on the course |
| Field size | `TournamentSystem.get_field_size()` | max(tier, live) | Nominal tier list is a floor |
| Rounds per tier | `TournamentManager.ROUNDS_PER_TIER` | 1/2/4/4 | Event length |
| Live round completion | `TournamentManager._check_live_round_completion()` | all live golfers finish | No calendar deadline |
| Pairing interval | `TournamentManager.GROUP_SPAWN_INTERVAL` | 0.5 s | Game-seconds between tee times |
| Cooldown | `TournamentManager.TOURNAMENT_COOLDOWN` | 45 | Days before the next event |
| Cut rules | `TournamentManager.CUT_RULES` | 50%/40+ties after R2 | Field reduction |
| Tier data | `TournamentSystem.TIER_DATA` | see §2 | Cost, prize, requirements |

Verified end to end by `tests/unit/test_tournament_hosting.gd` and by
`tests/harness/tournament_harness.tscn` (headless: host a two-round Regional event on
a quick-start course and print the field, the pairs per hole, the owner's card and
the results).

---

## 13. Files

- `scripts/systems/tournament_system.gd` — tiers, qualification, group size, field sizing
- `scripts/managers/tournament_manager.gd` — hosting, rounds, live scoring, cut, completion
- `scripts/systems/tournament_simulator.gd` — field generation and headless rounds
- `scripts/managers/golfer_manager.gd` — tournament spawning, seating, hole progression
- `scripts/ui/tournament_panel.gd` — hosting UI and the in-progress shelf
- `scripts/ui/tournament_leaderboard.gd` — live leaderboard
- `scripts/ui/tournament_results_popup.gd` — end-of-event results
- `docs/specs/completed/tournaments-multi-round.md` — the multi-round feature spec
