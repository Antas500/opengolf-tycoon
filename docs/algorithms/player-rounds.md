# Play the Course

## Plain English

The **Play the Course** button is available in building and simulation modes.
At least one open hole is required; owner rounds cannot overlap a management
(revenue) tournament. Unlike prior implementations, starting a round does not pause
the management mode or hide the management HUD. The course simulation, clock,
financials, and visitor golfers continue operating concurrently. Returning restores
the camera and any prior tool states.

The owner chooses a name and the existing shirt, pants, cap, hair and skin colors.
Because baked tier sprites cannot display these colors, the owner uses the
existing procedural golfer renderer. Opponents retain the tier sprites.

Formats:
- **Practice round:** owner only.
- **Play vs a Pro:** choose Alex, Morgan or Riley (each uses the Pro skill tier).

Skill points are allocated on the **Player Skills** page. The button that leads
there badges how many are still unspent, and a round can be started without
spending them — the points stay banked for a later reallocation.

A hosted tournament is a different thing: it starts on the click, and the owner is in
the field as a competitor (see [Tournament System](tournament-system.md)). Because
that pairing is already out on the course, starting an owner round is refused while
an event is live — the warning points at the shelf's **Play It Out** button, which
settles the event and frees the course.

All participants play the open holes from the back tees. The player and any opponents
are assigned a shared `group_id`, playing together as a single group just like visitor
groups on the course. They observe standard golf etiquette managed by `GolferManager`:
- The honor system on tee boxes (lowest score on prior hole, or lowest golfer ID on hole 1).
- The away rule through the green (furthest golfer from the pin hits next).
- Clearing etiquette (waiting for groups ahead to clear landing areas or par-3 greens).
- A name label above every golfer, so the group is told apart by name rather than
  by a badge (`Golfer._refresh_name_label`). Score, hole and group are not drawn
  on the course: the owner's scorecard, the tournament leaderboard and the
  click-through golfer popup carry them.

Opponents play in real time alongside the player; their completed-hole scores appear
in the player HUD scorecard. Lowest total wins; equal scores are a tie. Results include
each golfer's hole-by-hole scorecard. Normal hazard penalties, pickup rules, hole
detection, and walking remain in use. Leaving early abandons the round without awarding
a result.

When it is the owner's turn off the green, the owner waits for mouse input while preparing
a shot. The cursor becomes a crosshair and an **aim guide** shows the shot that is being
lined up: the flight arc through the air, the carry point where the ball first lands, and
the roll that follows it. The mouse picks a tile centre or a tile vertex and the guide shows
the ball coming to rest exactly there. Club selection is automatic by aim distance; when
the club that distance calls for cannot reach the chosen spot, a longer one is used
(see *Aiming at a centre or vertex*).

The guide is the *intent*, not a promise: it is computed by the real execution math with
the random error terms removed, so lie, wind, elevation, slope, shape and punch all show
up, while the gaussian miss, hook/slice tendency, chunked distance and shanks do not.
The camera follows the active round participants and refocuses when turns shift; normal
pan/zoom remains available for long shots. On the green the existing AI putting system
takes over, with no click required.

## Algorithm

### Persistent skills

`PlayerGolferProfile` stores ten integer point counts (0–99). Every point is a
**10 percentage-point bonus** (0% starting bonus, maximum 990%), out of a
ten-point budget. Points save automatically whenever they are changed and take
effect immediately for the player's next shot, with no Save Skills button
required. **Spending the budget is optional:** a Practice Round or Play vs Pro
round starts with any number of points unspent, and no starter diverts to the
Player Skills page when points are waiting. What the removed gate leaves behind
is a badge: the **Player Skills** navigation button carries the number of unspent
points (`PlayerTab.set_unused_skill_points`, refreshed by
`PlayerRoundManager._refresh_skills` and on every page switch) and hides it at
zero. Points can be reallocated across skills at any time (including during an
active round). Name and appearance also remain editable.

The profile is saved under `player_golfer`; older saves receive a fresh profile.
New games reset it. Active rounds are transient, like visitor rounds, and are
not resumed from saves. Loading or changing away from PLAYING cleans up an owner
round. Canceling first-time setup does not commit its draft.

For bonus `b = points * 0.1`, normalized execution skill is:

```
s = 1 - 0.5 / (1 + b)
```

This keeps existing normalized AI formulas below 1 even for a 990% bonus.

| Skill | Effect |
| --- | --- |
| Power Hitter | Adds to all non-putter club range factors |
| Long Driver | Adds to driver range factor |
| Accurate Driver | Driver / fairway wood execution accuracy |
| Accurate Irons | Iron / wedge execution accuracy |
| Accurate Putter | Existing automatic putting skill |
| Draw Shot / Fade Shot | Reduces inaccuracy when that shape is selected |
| High Backspin Shot | Reduces inaccuracy and increases reverse rollout |
| Recovery Skills | Reduces the lie accuracy penalty |
| Luck | Reduces remaining execution inaccuracy (including shank probability) |

Player maximum carry is `club.max_distance * 0.7 * (1 + power_bonus +
long_driver_bonus)`, with long-driver bonus included only for the driver.
Punch multiplies this range by 0.7. The tile-based aim (`player_aim()`, used by
`play_shot()` / `preview_shot()`) clamps to range and rounds to a tile; the mouse-driven
guide instead solves for a centre or vertex (see *Aiming at a centre or vertex*).
Existing terrain penalties still reduce actual distance.

For shape skill, luck and recovery, the relevant residual inaccuracy/lie penalty
is divided by `1 + bonus`. AI golfers without a player profile are unchanged.

### Shot shapes

`ShotTypeBar` (`scripts/ui/components/shot_type_bar.gd`) runs one button per
shot type along the top of the Play Course page — straight, fade, draw, high
backspin, and low punch — above the scrolling control columns, so the whole set
is visible and the shot being lined up is the lit button. The buttons are
mutually exclusive (`ButtonGroup`), and a press writes the shape index onto
`Golfer.player_shape`; hovering one shows its effect. The row greys out while
the owner waits for their turn, and a shot the current lie forbids is disabled
in place (rather than hidden, so the option is still discoverable).

Straight and low punch are available on all off-green lies. Fade, draw and high
backspin require tee or fairway; invalid selections reset to straight in both the
row and the shot execution guard, and the row mirrors that fallback so the lit
button is always the shot `play_shot()` will hit.

- Fade bends 8 degrees L to R relative to the shot direction.
- Draw bends 8 degrees R to L.
- Backspin reverses rollout by `min(1.5, 0.25 * (1 + bonus))` tiles on green or
  fairway landings, and raises the visual arc by 40%.
- Low punch is selected like any other shot shape: 70% range, 35% crosswind
  displacement, 30% visual arc height, and 150% normal rollout. It cannot be
  combined with fade, draw, or backspin.

The aim line interpolates bend from zero to the full angle; the ball animation
adds a lateral mid-flight curve while preserving its computed landing position.

### Aim guide (intended arc and roll)

`AimGuide` (`scripts/ui/aim_guide.gd`) is a `Node2D` child of `PlayerRoundManager`
sitting just above the terrain and below the management UI. Every frame that the owner
is lining up a shot, `PlayerRoundManager.update_aim_guide()` snaps the mouse to a tile
centre or vertex and feeds it to `Golfer.preview_shot_to_rest()` (next section), the
resting-point version of `Golfer.preview_shot(tile)`. Both run the execution math the
same way; `preview_shot()`:

1. clamps the mouse aim the same way `play_shot()` does (club by distance, punch and
   skill range, illegal shapes reset to straight),
2. runs `_calculate_shot(..., deterministic := true)` and `_calculate_rollout(..., true)`,
   which substitute expected values for every random term:

| Random term | Real shot | Preview |
| --- | --- | --- |
| Swing distance variance (`randf_range`) | sampled per club | midpoint of the range |
| Miss angle (`_gaussian_random() * spread_std_dev`) | sampled | 0 |
| Miss tendency (`miss_tendency * (1 - acc) * 6°`) | applied | 0 |
| Shank (`(1 - acc) * 4%`) | possible | never |
| Distance loss (chunk/top) | sampled | 0 |
| Rollout fraction (`randf() * 0.6 + randf() * 0.4`) | sampled | 0.5 (its mean) |

Everything else — lie and terrain distance modifiers, wind head/tail and crosswind,
elevation, landing-terrain rollout multipliers, slope pull, hazard stops, shape bend,
punch scaling and backspin reversal — is intent and is applied. The preview therefore
returns the exact dictionary shape the execution path returns, plus the walked
`roll_path` waypoints, club/yardage readouts and a `blocked` flag (the ball would
finish in water, OB, a bunker or a flower bed).

The guide draws in world space, matching the ball animation so that the arc predicts
what the player sees:

- **Arc** — straight interpolation from ball to carry point, plus the fade/draw bend
  (`±8°`, converted from a grid delta into a screen offset so it survives view
  rotation) and the cosmetic wind drift, both swelling as `sin(πt)` and decaying to
  zero at landing, minus an arc height of `min(carry_screen_distance * 0.3, 150px)`
  scaled ×0.3 for punch and ×1.4 for backspin — the same curves and numbers as
  `Ball._process_flight()` and `BallManager._on_ball_shot_precise()`.
- **Ground track** — a faint terrain-following line under the arc (elevation
  displacement comes from `TerrainGrid.grid_to_screen_precise()`), which shows the
  shot's path over raised ground.
- **Carry ring** — the landing point, drawn at the end of the arc.
- **Roll trail** — dotted blue along the actual rollout waypoints, so it visibly stops
  short in rough, plugs into a bunker or bends with slope. It turns red when the ball
  would finish in a hazard, and turns violet with a back-pointing arrow for backspin
  (where the ball rolls back toward the player).
- **Labels** — club, expected carry, punch/fade/draw/backspin and "out of range"
  (with a red X at the raw mouse target when the aim had to be reined in), plus the
  roll distance and hazard caption at the resting point.

Because the guide is deterministic, the drawn arc and roll do not flicker while the
mouse moves. It re-runs the math each frame, so it also updates live when the player
changes shape, toggles punch or a new day brings different wind.

### Aiming at a centre or vertex

The mouse does not aim at a free point. It picks one of the terrain's *anchors* — a tile
centre or a tile vertex — and the guide shows the ball coming to **rest** on it. Every
centre and every vertex of the map has to be pickable, and has to be reachable by some
club, so that the player can point the line wherever they can hit the ball.

**Snapping.** `TerrainGrid.snap_world_to_tile_anchor(world_pos)` finds the surface point
under the pointer (an elevation ray march, so sculpted ground is hit where it is drawn)
and compares the screen distance to the centre and four vertices of that tile and of its
eight neighbours, after elevation displacement and view rotation. The nearest anchor
wins, so hovering exactly over an anchor picks it in every camera orientation. The
far-edge vertices lie on the map's boundary, half of their catchment off the map, so a
pointer up to `ANCHOR_RIM_MARGIN` (0.5 tile) beyond the edge still picks the rim anchor
nearest to it; further out there is nothing to aim at and the guide clears.

**Solving for the launch point.** `preview_shot_to_rest(anchor, type)` and
`play_shot_to_rest(anchor)` invert the deterministic flight-and-roll model with
`_solve_aim_for_rest()`. For one club:

1. Aim at the anchor (limited to the club's `player_max_distance()`), run the shot and
   move the aim by the miss, `aim += anchor - predicted_rest`. Up to
   `REST_SOLVE_ITERATIONS` (12) passes; it stops once the ball rests within
   `REST_SOLVE_EXACT_ERROR` (0.02 tile) of the anchor. The closest shot seen is kept,
   not the last one.
2. The resting point is not a smooth function of the aim: landing in a bunker or water
   stops the ball dead, the green rolls faster than the fairway, and a roll shorter than
   0.15 tile is dropped. At such an edge the resting point jumps, and the fixed-point
   pass bounces from one side to the other without settling. The solver remembers the
   latest shot that rests short of the anchor and the latest that rests long of it and
   bisects between them (up to `REST_SOLVE_BISECTIONS`, 14), which closes on the real
   solution where the resting point is continuous and otherwise on the edge of the jump.
3. The shot lands *on* the anchor when the best resting point is within
   `REST_SOLVE_TOLERANCE` (0.12 tile) of it.

**Choosing the club.** `select_club()` proposes a club from the distance (driver from 9
tiles, fairway wood from 8, iron from 5, wedge below), but the proposal only counts if
that club can actually bring the ball to rest on the anchor. The distance bands were
drawn for the AI's ranges, but the owner's are 0.7 times the table (before skills), so
each club's reach can end before the next band begins. With no skill points the wedge
stops at 3.5 tiles (a full-swing wedge rolls almost nothing) while the iron's band only
starts at 5, and the iron (aim range 6.3 plus about 0.6 of roll) stops near 6.9 while the
fairway wood's band starts at 8. The anchors in such a gap used to be reported as "out of
range" while a longer club reached them easily, and the guide jumped to a different
anchor, which is what made some centres and vertices impossible to point at. The solver
therefore tries the proposed club, then each longer club (nearest first), then the
shorter ones, and plays the first that lands within the tolerance. When no club does, the
proposal is kept unless another club ends at least `CLUB_SWITCH_MARGIN` (0.05 tile)
closer. Every anchor inside the bag's reach (the driver's range plus its roll) therefore
has a club that lands on it, bar the places the terrain itself leaves a gap (below); the
club named on the guide is the club the swing uses.

**When the anchor cannot be reached.** The guide still ends on an anchor: the one nearest
to where the ball would actually rest. Two reasons are told apart. *Out of range* means
the aim is already at the club's maximum (the red X marks the anchor that was asked for).
*Terrain limited* means the aim had range to spare but the ball cannot stop there: a ball
that carries a bunker rolls on past its far edge, so the tiles just behind it are not
places the ball can come to rest.

### State and cleanup

The player round integrates directly with `GolferManager`'s group turn scheduler
(`_update_group`), assigning the player and their playing partners a shared `group_id`.
PREPARING_SHOT waits only for an owner off-green; ordinary AI and green putting retain
their preparation timer. `play_shot` rejects input while swinging/walking/watching, when
paused, off-map, or aimed at the ball itself, preventing double-click extra strokes.

Owner-round golfers use the tournament spawning path to avoid entrance fees and
closing-time restrictions, with `is_owner_round` set to true so that `PlayerRoundManager`
manages round completion and results display. Visitors and course simulation remain
active throughout the round. Cleanup removes the owner group participants and balls
while leaving normal visitors unperturbed.

## Tuning Levers

| Parameter | Location | Default |
| --- | --- | --- |
| Initial points / point cap | `player_golfer_profile.gd` | 10 / 99 |
| Normalized baseline | `normalized_skill()` | 0.5 |
| Carry range factor | `Golfer._get_skill_distance_factor()` | 0.7 |
| Shape bend | `Golfer.shape_bend_degrees()` (`PLAYER_SHAPE_BEND_DEG`) | ±8° |
| Punch range / wind / roll | `player_max_distance()` / `_calculate_shot()` | 0.7 / 0.35 / 1.5 |
| Backspin distance | `Golfer._calculate_shot()` | 0.25–1.5 tiles |
| Guide arc height ratio / cap | `AimGuide.ARC_HEIGHT_RATIO` / `MAX_ARC_HEIGHT` | 0.3 / 150px |
| Guide bend factor | `AimGuide.BEND_FACTOR` (matches `BallManager`) | 0.06 |
| Guide roll dot spacing / radius | `AimGuide._draw_dotted_trail()` | 9px / 2.4px |
| Shortest captioned roll | `AimGuide._draw_labels()` | 5 yd |
| Anchor lands on target within | `Golfer.REST_SOLVE_TOLERANCE` | 0.12 tile |
| Solve stops refining within | `Golfer.REST_SOLVE_EXACT_ERROR` | 0.02 tile |
| Fixed-point passes / bisections | `Golfer.REST_SOLVE_ITERATIONS` / `REST_SOLVE_BISECTIONS` | 12 / 14 |
| Club change needs to end this much closer | `Golfer.CLUB_SWITCH_MARGIN` | 0.05 tile |
| Clubs tried, shortest reach first | `Golfer.OWNER_CLUB_LADDER` | wedge, iron, fairway wood, driver |
| Pointer tolerance past the map edge | `TerrainGrid.ANCHOR_RIM_MARGIN` | 0.5 tile |

## Validation

`test_player_golfer.gd` covers allocation, refunds, locking, persistence, legacy
saves, bounds, terrain eligibility, input waiting, automatic-green eligibility,
range modifiers, and the deterministic shot preview (same math as execution, no
shank/tendency, shape mirroring, punch roll-out, backspin reversal, and the states
in which no guide is offered). It also scans every centre and vertex inside the
driver's range and requires each to be aimable, covers the club hand-over between the
clubs' ranges, the out-of-range and terrain-limited reports, and the solver's handling of
jumps in the resting point (the smallest visible roll, a bunker strip).
`test_aim_guide.gd` covers the drawn geometry: the arc starts at the ball, rises above
its ground track and ends on the carry point, the roll trail runs from that carry point
to the resting point, fade and draw bend to opposite sides, punch flattens and backspin
lifts the arc, the ground track follows terrain elevation, and invalid input draws
nothing; and the snapping: every centre and vertex, rim included, picks itself on flat
and sculpted terrain in all four orientations. `test_player_round.gd` exercises the real
setup UI, opponent selection, results/ties, concurrent visitor activity, shared group ID
and etiquette, cancellation, mode changes, the guide appearing/clearing with the owner's
turn, the guide pointing at tiles that sit between two clubs' ranges, and a real round
through swings, flight, walking and automatic putts.
