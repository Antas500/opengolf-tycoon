# Play the Course

## Plain English

The **Play the Course** button is available in building and simulation modes.
At least one open hole is required; owner rounds cannot overlap a management
(revenue) tournament. Setup and play suspend the management clock, spawning and
visitor processing. Returning restores the previous mode, speed and camera.
Management tools are deselected and locked while the owner round is open.

The owner chooses a name and the existing shirt, pants, cap, hair and skin colors.
Because baked tier sprites cannot display these colors, the owner uses the
existing procedural golfer renderer. Opponents retain the tier sprites.

Formats:
- **Practice round:** owner only.
- **Play vs a Pro:** choose Alex, Morgan or Riley (each uses the Pro skill tier).
- **Begin Tournament:** owner plus all three pros, playing a single stroke-play
  round. This is separate from the management tournament/prize-money system.

All participants play the open holes from the back tees. Opponents play
concurrently; their completed-hole scores appear in the HUD. Lowest total wins;
equal scores are a tie. Results include each golfer's hole-by-hole scorecard.
The normal hazard penalties, pickup rule, hole detection and walking remain in
use. Leaving early abandons the round without awarding a result.

The owner waits for a mouse click while preparing an off-green shot. The cursor
becomes a crosshair and a projected carry line shows the selected aim and shape.
The line is an estimate, not a guaranteed landing point: lie, skill, wind,
elevation and rollout still apply. Club selection is automatic by aim distance.
The camera follows the owner while walking and refocuses when their state changes;
normal pan/zoom remains available for long shots. On the green the existing AI
putting system takes over, with no click required.

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

### State and cleanup

`PlayerRoundManager` advances its participants via the existing
`GolferManager._advance_golfer` when they are IDLE. PREPARING_SHOT waits only for
an owner off-green; ordinary AI and green putting retain their preparation timer.
`play_shot` rejects input while swinging/walking/watching, when paused, off-map,
or aimed at the ball itself, preventing double-click extra strokes.

Owner-round golfers use the tournament spawning path to avoid entrance fees and
closing-time restrictions, but have their own lifecycle flag to avoid automatic
manager removal before the results screen. Cleanup removes their balls through
the normal golfer-left signal and restores suspended visitors.

## Tuning Levers

| Parameter | Location | Default |
| --- | --- | --- |
| Initial points / point cap | `player_golfer_profile.gd` | 10 / 99 |
| Normalized baseline | `normalized_skill()` | 0.5 |
| Carry range factor | `Golfer._get_skill_distance_factor()` | 0.7 |
| Shape bend | `Golfer._calculate_shot()` and round `_draw()` | ±8° |
| Punch range / wind / roll | `player_aim()` / `_calculate_shot()` | 0.7 / 0.35 / 1.5 |
| Backspin distance | `Golfer._calculate_shot()` | 0.25–1.5 tiles |

## Validation

`test_player_golfer.gd` covers allocation, refunds, locking, persistence, legacy
saves, bounds, terrain eligibility, input waiting, automatic-green eligibility
and range modifiers. `test_player_round.gd` exercises the real setup UI, opponent
selection, results/ties, visitor restoration, cancellation, mode changes, and a
real round through swings, flight, walking and automatic putts.
