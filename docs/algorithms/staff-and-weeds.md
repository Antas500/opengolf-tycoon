# Staff on the Course, Designated Areas & Weeds

> **Source:** `scripts/managers/staff_manager.gd`, `scripts/entities/staff_member.gd`,
> `scripts/managers/weed_manager.gd`, `scripts/entities/weed.gd`,
> `scripts/ui/staff_panel.gd`, `scripts/ui/staff_area_overlay.gd`

## Plain English

Hiring an employee no longer just adds a line to a payroll table — the employee
**appears on the course** and walks around their **designated area** looking for
work. There are four job types, and each has a standard and a premium staff type.
The premium hire costs more per day but covers a bigger area, moves faster and
does its job faster.

| Job | Standard | Premium | What they do on the course |
| --- | --- | --- | --- |
| Groundskeepers | Groundskeeper | Technician | Pull weeds that sprout on the turf |
| Greeters | Club Pro | Celebrity | Chat with golfers to cheer them up |
| Marshals | Ranger | Marshall | Talk to groups to keep the pace of play moving |
| Drinks Vendors | Soda Vendor | Cart Refresher | Serve thirsty golfers a drink |

### Designated areas

Every employee owns a circle of grid tiles — their designated area. They only
work on targets inside it, and they wander within it when there is nothing to do.
Areas are drawn on the course as translucent rings. The **Staff** tab's Current
Staff section has an **Area** button per employee; pressing it enters a
click-the-course mode, the employee's ring lights up, and the next left click on
a tile moves their area there. Right click or Escape cancels.

### The Staff tab

The tab now has exactly two sections:

- **Hire Staff** — one row per job with a Standard and a Premium button showing
  the daily wage and the current headcount.
- **Current Staff** — daily payroll, the number of weeds on the course, and a row
  per employee holding their name, staff type, wage, a **Area** button and a
  **Fire** button.

### Weeds

Weeds sprout overnight on owned turf — natural grass, fairways, firm fairways and
the three roughs. Greens, tees and hazards are kept clear so a clump never hides
a cup or blocks a tee shot. Clumps grow taller each day they survive. Hired
groundskeepers walk to the nearest clump inside their area, spend a moment
pulling it, and it disappears.

At the end of each day the course condition is recomputed from the weeds left on
the course, softened by groundskeeper coverage. Condition feeds the star rating's
condition category (see [course-rating.md](course-rating.md)), so an unstaffed
course slowly gets scruffy and a staffed one stays pristine.

---

## Algorithm

### 1. Staff types and tuning

Each of the eight staff types is one entry in `StaffManager.STAFF_DATA`:

| Type | Job | Tier | Salary/day | Area radius (tiles) | Move speed (px/s) | Work speed | Effect |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Groundskeeper | Groundskeeper | Standard | 80 | 6 | 46 | 1.0x | — (pulls weeds) |
| Technician | Groundskeeper | Premium | 155 | 11 | 70 | 1.9x | — |
| Club Pro | Greeter | Standard | 60 | 7 | 48 | 1.0x | +0.06 mood |
| Celebrity | Greeter | Premium | 130 | 12 | 72 | 1.8x | +0.10 mood |
| Ranger | Marshal | Standard | 50 | 8 | 50 | 1.0x | +0.28 pace |
| Marshall | Marshal | Premium | 110 | 13 | 74 | 1.8x | +0.45 pace |
| Soda Vendor | Drinks Vendor | Standard | 40 | 6 | 52 | 1.0x | +0.35 thirst |
| Cart Refresher | Drinks Vendor | Premium | 95 | 12 | 78 | 1.9x | +0.60 thirst |

Two multipliers come out of `work_speed`: the task finishes in
`work_seconds / work_speed` and the effect is applied as
`effect * work_speed`. A premium hire therefore both reaches more golfers and
delivers a stronger service each time.

### 2. The staff member state machine

`StaffMember` runs IDLE → WALKING → WORKING:

```
IDLE      timer counts down, then pick a target
WALKING   move_toward(target, move_speed * delta); on arrival become WORKING
          (or IDLE when the target was just a wander point)
WORKING   timer = work_seconds / work_speed; on completion apply the effect
```

Picking a target (`_choose_task`):

- **Groundskeeper**: `WeedManager.find_closest_weed(my_grid_point, area_radius)`.
- **Greeter**: the golfer inside the area with the lowest mood
  (`1 - current_mood`, with a nudge for thirsty golfers).
- **Marshal**: the golfer inside the area with the lowest pace
  (`needs.pace`, plus 0.5 for a traffic-blocked group).
- **Drinks vendor**: the golfer inside the area with the lowest thirst.
- **Nobody available**: pick a random point in the area
  (`angle = randf() * TAU`, `r = area_radius * sqrt(randf())`) and wander there.

All distances are measured in **grid space** (`TerrainGrid.screen_to_grid_point`),
so the designated area reads as a true circle even though the projected view is
isometric.

A service only lands if the golfer is still within
`SERVICE_RANGE_TILES = 2.5` of the staff member when the work finishes — walking
away mid-conversation means no effect.

### 3. Golfer side of a service

Every served golfer gets `staff_help_cooldown = 20s` so one employee cannot park
next to a golfer and spam effects. The golfer methods are:

```
receive_greeting(amount)   → _adjust_mood(amount)                + CHEERED_UP thought
receive_pace_help(amount)  → needs.restore_pace(amount)          + PACED_UP thought
receive_drink(amount)      → needs.restore_thirst(amount)        + REFRESHED thought
```

`restore_thirst` and `restore_pace` return a small extra mood boost (0.04 / 0.03)
and only when the need actually improved, so a fully-quenched golfer gives
nothing back.

### 4. Weed growth

```
grow_daily(open_holes):
    every existing clump: growth = min(1.0, growth + 0.22)
    wanted = max(1, round(open_holes * 0.5))
    for each: try up to 80 random tiles; accept the first with
              terrain in HOST_TURF, no cup/tee, no entity, owned land and no
              existing weed. Stop at MAX_WEEDS = 80.
```

`HOST_TURF` = GRASS, FAIRWAY, FIRM_FAIRWAY, ROUGH, HEAVY_ROUGH, DEEP_ROUGH.

### 5. Course condition from weeds

Computed at end of day in `StaffManager.process_daily_maintenance()`:

```
pressure = weeds / (open_holes * 4.0)            # 1.0 = fully overrun
coverage = min(1.0, groundskeepers / open_holes) # 1.0 = one per hole
target   = clamp(1.0 - pressure * (1.0 - coverage * 0.7), 0.0, 1.0)
course_condition = target
```

A groundskeeper therefore absorbs 70% of a fully-staffed course's weed pressure.
Spawned weeds arrive after payroll, so the condition reported on the end-of-day
summary reflects what was actually left on the course.

### 6. Pace modifier

The marshal contribution to the pace-of-play rating (used by
`CourseRatingSystem` and the waiting-decay relief in `golfer.gd`):

```
modifier = min(1.0, 0.6 + 0.12 * rangers + 0.20 * marshalls)
```

### 7. Persistence

`StaffManager.serialize()` stores the roster (id, type, salary, name,
`area_center` as `{x, y}`, `area_radius`), `course_condition` and
`next_staff_id`. `WeedManager.serialize()` stores `"x,y" → growth` and is saved
alongside it under `weeds`. Deserialization rebuilds the staff bodies and weed
clumps.

### Tuning Levers

| Parameter | Location | Current Value | Effect |
| --- | --- | --- | --- |
| STAFF_DATA | `staff_manager.gd` | 8 entries | Per-type salary, area radius, speed, work speed and effect |
| area_radius | `staff_manager.gd:STAFF_DATA` | 6–13 tiles | Higher = employee covers more ground |
| move_speed | `staff_manager.gd:STAFF_DATA` | 46–78 px/s | Higher = reaches targets faster |
| work_speed | `staff_manager.gd:STAFF_DATA` | 1.0–1.9 | Scales both task duration and effect strength |
| work_seconds | `staff_manager.gd:STAFF_DATA` | 1.6–2.6 s | Base task time before `work_speed` divides it |
| WEEDS_PER_HOLE_FULL_PRESSURE | `weed_manager.gd` | 4.0 | Lower = weeds hurt condition sooner |
| MAX_WEEDS | `weed_manager.gd` | 80 | Ceiling on clumps on the course |
| DAILY_GROWTH | `weed_manager.gd` | 0.22 | How much taller survivors get each day |
| SPAWN_ATTEMPTS | `weed_manager.gd` | 80 | Random tiles tried per new clump |
| HOST_TURF | `weed_manager.gd` | 6 turf types | Terrain weeds may sprout on |
| groundskeeper coverage relief | `staff_manager.gd:process_daily_maintenance()` | 0.7 | Fraction of weed pressure a fully staffed course ignores |
| SERVICE_RANGE_TILES | `staff_member.gd` | 2.5 | How close a golfer must stay for a service to land |
| STAFF_HELP_COOLDOWN_SECONDS | `golfer.gd` | 20 s | Minimum gap between services to one golfer |
| THIRST_DECAY_PER_HOLE | `golfer_needs.gd` | 0.07 | Higher = golfers get thirsty faster |
| THIRST_SATISFACTION_FLOOR | `golfer_needs.gd` | 0.85 | Satisfaction multiplier when bone dry |

## Verification

- `tests/unit/test_staff_manager.gd` — job/tier data, hiring, payroll, areas,
  pace modifier, weed-driven condition, serialization.
- `tests/unit/test_weed_manager.gd` — growth, host-turf rules, removal, pressure,
  serialization.
- `tests/unit/test_staff_panel.gd` — the two-section tab, both hire tiers per job,
  Move Area and Fire buttons.
- `tests/unit/test_staff_service.gd` — greeter/marshal/vendor effects and the
  service cooldown.
- `tests/integration/staff_on_course.gd` — boots the game, hires staff, moves an
  area, and watches a groundskeeper pull a weed.
- `tests/harness/sim_harness.gd` — hires one of every type, moves areas daily and
  exercises save/load across a multi-day run.
