# Group Turn Order & Ready Golf

> **Source:** `scripts/managers/golfer_manager.gd` (`_update_group`,
> `_determine_next_golfer_in_group`, `_is_walking_group_clear`,
> `_is_landing_area_clear`, `_advance_golfer`), `scripts/entities/golfer.gd`
> (`take_shot`, `_walk_to_ball`, `_on_reached_destination`)

## Plain English

Golfers play in groups, and the group — not the individual — owns the turn. One
golfer at a time prepares, swings and watches the ball; everybody else waits
their turn. Who goes next follows the usual rules: **honor** off the tee (best
score on the previous hole, first hole in `golfer_id` order) and the **away
rule** through the green (furthest from the cup plays first).

What changed is **what the group waits for**. It used to wait for two things:

1. the shot in progress to come to rest, and
2. every partner to finish *walking* to their ball.

The second one is not a rule, it is dead time. On a four-ball par 4 it meant the
whole group stood still four times a hole while one golfer at a time walked to
their ball, and the pace-of-play complaints ("Waiting for the group ahead") were
really complaints about their own partners' shoes.

Now the group plays **ready golf**: as soon as the previous shot has come to
rest, the next golfer away plays, and the partners carry on walking. A partner on
the move only holds the turn up while they are physically standing where this
ball is going — in the landing zone of a full swing, or on the route of a chip or
putt, so nobody is struck while bending over the cup. They step clear in about a
second and the group goes.

Three things still stop a group, exactly as before:

- **A shot in progress.** Nobody plays while a partner is preparing, swinging or
  watching their ball. That is the "previous golfer has hit their shot" gate.
- **The group ahead.** `_is_landing_area_clear` still refuses a shot whose
  landing cone holds a golfer from an earlier group, and the tee and par-3 rules
  still keep groups apart.
- **A partner in the line.** New, and narrow: a walker inside the landing cone,
  or within a tile of a chip or putt's route.

Off the tee nothing changed at all — every member of the group still tees off in
turn before anybody waits, because that is how a tee box empties.

## Algorithm

`_update_group` runs once per group per frame. The order matters:

```
1. clear traffic_blocked on every member
2. if anybody is PREPARING_SHOT / SWINGING / WATCHING  -> return   (shot in progress)
3. advance a member who has holed out and is IDLE      -> return   (clear the green, one per frame)
4. next_golfer = _determine_next_golfer_in_group(group)            (honor, then away)
5. if next_golfer is teeing, or _is_walking_group_clear(next_golfer, group):
6.     if _is_landing_area_clear(next_golfer, group): _advance_golfer(next_golfer)
7.     else: traffic_blocked = true for the group                  (group ahead in the way)
```

Step 2 is the whole of the turn gate now. Walking is not in that list, so a
walking partner no longer blocks the group; step 5 decides whether *this*
particular shot is safe to play over them.

### The walking-partner check

`_is_walking_group_clear(shooting_golfer, group)` measures the shot the golfer is
about to play (`get_cached_or_compute_shot_target`, the same target
`_is_landing_area_clear` uses) and tests only partners who are **walking** and on
**the same hole**. Partners who have stopped are standing at their own ball —
they never held a shot up and still do not.

A walker's *body* is what a ball would hit, and a walking golfer's body is well
short of the ball they are heading for, so the check reads
`terrain_grid.screen_to_grid_precise(global_position)`, not `ball_position`.

**Short shots** (`shot_distance < GROUP_SHORT_SHOT_DISTANCE_TILES`, i.e. chips
and putts) keep their whole route clear — the ball is on the ground the entire
way, so a partner anywhere near the line is in the way:

```gdscript
if _distance_to_line_segment(partner, origin, target) < GROUP_SHORT_SHOT_CLEARANCE_TILES:
    return false
```

**Everything with air under it** keeps the landing cone clear, with the same
shape `_is_cone_clear_of_golfers` uses for the group ahead:

```gdscript
min_check_distance = shot_distance * 0.6              # nothing lands much shorter
max_check_distance = shot_distance + landing_radius   # landing_radius = 2.0 + 0.3 * distance
if to_partner.dot(direction) < 0.0: continue          # behind the golfer
if not min_check_distance <= |to_partner| <= max_check_distance: continue
if abs(direction.angle_to(to_partner)) > LANDING_CONE_HALF_ANGLE: continue  # PI/4
return false                                          # in the cone: hold the shot
```

Because only walkers are tested, the check cannot deadlock: a partner whose ball
lies inside the cone walks to it, arrives, goes IDLE, and stops being checked.

### Tuning Levers

| Constant | Source | Value | Effect |
| --- | --- | --- | --- |
| `GROUP_SHORT_SHOT_DISTANCE_TILES` | `golfer_manager.gd` | 2.5 tiles (~55 yd) | Longer = more shots treated as chips/putts and judged on their whole route |
| `GROUP_SHORT_SHOT_CLEARANCE_TILES` | `golfer_manager.gd` | 1.0 tile (~22 yd) | Clearance kept around a chip or putt. Bigger = a partner must step further aside; smaller = putts go sooner |
| `LANDING_ZONE_BASE_RADIUS` | `golfer_manager.gd` | 2.0 tiles | Floor of the landing cone a walker must be clear of |
| `LANDING_ZONE_VARIANCE` | `golfer_manager.gd` | 0.3 | Fraction of shot distance added to the cone |
| `LANDING_CONE_HALF_ANGLE` | `golfer_manager.gd` | π/4 | Half-angle of the cone; wider = walkers block from further off the line |
| `PREPARATION_DURATION` | `golfer.gd` | 1.0 s | How long the golfer whose turn it is takes to address the ball |
| `walk_speed` | `golfer.gd` | 100 px/s | How quickly a blocked walker steps clear (≈ one tile per 0.3–0.6 s) |

## Measured effect

`tests/harness/ready_golf_harness.tscn` boots the real game, quick-starts the
nine-hole course, puts one foursome on it with no other tee times booked, and
plays three holes per golfer at ULTRA speed for three seeds. It counts the frames
where the group had a golfer ready to play, a partner still walking, and no shot
in progress — the dead time this change removes:

| | before | after |
| --- | --- | --- |
| ready-but-waiting share of group time | 17.5 %, 18.7 % | 5.3 %, 5.7 %, 8.3 % |
| shots struck while a partner was still walking | 33 of 168, 36 of 183 | 62 of 191, 70 of 184, 69 of 182 |

So two thirds or more of the waiting frames went away, and the share of shots
played while somebody is on the move roughly doubled. The few percent that
remains is real: it is the frames where a walker genuinely is standing in the
line, plus the walk to the next tee after the group has finished a hole.

The harness is a simulation stepped on real frame deltas, so it is not
bit-for-bit repeatable — the same build measures 5–8 % run to run. Read it as a
range against the 17–19 % the old scheduler measured, not as an exact figure.

## Verification

- `tests/unit/test_group_turn_order.gd` — the turn passes while a partner walks;
  the check reads the body, not the ball; a partner at rest never blocks; the
  group still waits for a shot in the air; a walker in the landing zone still
  holds the shot; a putt waits for a partner at the cup and goes when they step
  aside; the tee keeps its free pass.
- `tests/unit/test_tournament_hosting.gd` — drives `_update_group` directly for
  tournament pairings, including the wrap round to the first tee.
- `tests/harness/ready_golf_harness.gd` — the pace measurement above, on the real
  main scene.
