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
- **Begin Tournament:** owner plus all three pros, playing a single stroke-play
  round. This is separate from the management tournament/prize-money system.

All participants play the open holes from the back tees. The player and any opponents
are assigned a shared `group_id`, playing together as a single group just like visitor
groups on the course. They observe standard golf etiquette managed by `GolferManager`:
- The honor system on tee boxes (lowest score on prior hole, or lowest golfer ID on hole 1).
- The away rule through the green (furthest golfer from the pin hits next).
- Clearing etiquette (waiting for groups ahead to clear landing areas or par-3 greens).
- Group badges identifying their group number.

Opponents play in real time alongside the player; their completed-hole scores appear
in the player HUD scorecard. Lowest total wins; equal scores are a tie. Results include
each golfer's hole-by-hole scorecard. Normal hazard penalties, pickup rules, hole
detection, and walking remain in use. Leaving early abandons the round without awarding
a result.

When it is the owner's turn off the green, the owner waits for mouse input while preparing
a shot. The cursor becomes a crosshair and an **aim guide** shows the shot that is being
lined up: the flight arc through the air, the carry point where the ball first lands, and
the roll that follows it. Club selection is automatic by aim distance.

The guide is the *intent*, not a promise: it is computed by the real execution math with
the random error terms removed, so lie, wind, elevation, slope, shape and punch all show
up, while the gaussian miss, hook/slice tendency, chunked distance and shanks do not.
The camera follows the active round participants and refocuses when turns shift; normal
pan/zoom remains available for long shots. On the green the existing AI putting system
takes over, with no click required.

## Algorithm

### Persistent skills

`PlayerGolferProfile` stores ten integer point counts (0–99). The first round
requires spending exactly ten points; every point is a **10 percentage-point
bonus** (0% starting bonus, maximum 990%). Points can be refunded during setup,
but are locked once the first round starts. No extra progression points are
awarded in this implementation. Name and appearance remain editable.

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
Punch multiplies this range by 0.7. Aim is clamped to range and rounded to a tile.
Existing terrain penalties still reduce actual distance.

For shape skill, luck and recovery, the relevant residual inaccuracy/lie penalty
is divided by `1 + bonus`. AI golfers without a player profile are unchanged.

### Shot shapes

Straight and low punch are available on all off-green lies. Fade, draw and high
backspin require tee or fairway; invalid selections reset to straight in both the
HUD and the shot execution guard.

- Fade bends 8 degrees L to R relative to the shot direction.
- Draw bends 8 degrees R to L.
- Backspin reverses rollout by `min(1.5, 0.25 * (1 + bonus))` tiles on green or
  fairway landings, and raises the visual arc by 40%.
- Punch is an independent toggle: 70% range, 35% crosswind displacement,
  30% visual arc height, and 150% normal rollout. When paired with backspin,
  the lower arc and backspin rollout apply.

The aim line interpolates bend from zero to the full angle; the ball animation
adds a lateral mid-flight curve while preserving its computed landing position.

### Aim guide (intended arc and roll)

`AimGuide` (`scripts/ui/aim_guide.gd`) is a `Node2D` child of `PlayerRoundManager`
sitting just above the terrain and below the management UI. Every frame that the owner
is lining up a shot, `PlayerRoundManager.update_aim_guide()` feeds it
`Golfer.preview_shot(mouse_target)`, which:

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

## Validation

`test_player_golfer.gd` covers allocation, refunds, locking, persistence, legacy
saves, bounds, terrain eligibility, input waiting, automatic-green eligibility,
range modifiers, and the deterministic shot preview (same math as execution, no
shank/tendency, shape mirroring, punch roll-out, backspin reversal, and the states
in which no guide is offered). `test_aim_guide.gd` covers the drawn geometry: the
arc starts at the ball, rises above its ground track and ends on the carry point,
the roll trail runs from that carry point to the resting point, fade and draw bend
to opposite sides, punch flattens and backspin lifts the arc, the ground track
follows terrain elevation, and invalid input draws nothing. `test_player_round.gd`
exercises the real setup UI, opponent selection, results/ties, concurrent visitor
activity, shared group ID and etiquette, cancellation, mode changes, the guide
appearing/clearing with the owner's turn, and a real round through swings, flight,
walking and automatic putts.
