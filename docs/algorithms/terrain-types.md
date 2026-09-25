# Terrain Types

> **Source:** `scripts/terrain/terrain_types.gd` (ids, properties, families), `scripts/systems/golf_rules.gd` (lie, distance, roll, penalties), `scripts/systems/shot_ai.gd` (scores, recovery), `scripts/ui/terrain_toolbar.gd` (tiles, hotkeys), `data/terrain_types.json` (mirror)

## Plain English

Every tile of the course is one terrain type. The type decides what it costs to
build and maintain, how well a golfer can strike a ball lying on it, how far a
ball runs after landing on it, whether it is a penalty area, and how the course
surface shader draws it.

The **Course Terrain** tab combines course surfaces, hazards, Flower Bed,
boulders, and theme-specific trees into one horizontally scrolling honeycomb.
Two interlocking rows keep the course tiles first, with landscaping extending
the right end of each row:

| Row | Course tiles (left to right) |
| --- | --- |
| Top | Tee Box, Green, Bunker, Rough, Pot Bunker, Stream, Water |
| Bottom | Fairway, Firm Fairway, Deep Rough, Waste Bunker, Brush, Rocks, Out of Bounds |

The honeycomb width adapts to the theme's tree catalogue while staying two rows
high. Open Hole, Bulldozer, and brush controls remain in a column before it.
Path lives on the Improvements tab alongside Decorations. Grass, Heavy Rough,
Trees and Empty are placed by generation or by entities (a tree stamps Trees,
a boulder stamps Rocks).

### The seven newer tiles

- **Firm Fairway** — Links-style, fast-running turf. The lie is as good as a
  fairway for full swings but tight for wedges (0.92), and a ball that lands on
  it runs 1.6× as far as on fairway. Use it for landing zones that reward (or
  punish) the bounce.
- **Pot Bunker** — A small, deep pit with a stacked-turf face: harsher than any
  bunker (wedge 0.35 / other 0.15, 45% distance). Only a wedge gets out, and the
  ball barely advances. Balls rolling into it are gathered.
- **Stream** — Running water. It takes the same one-stroke penalty and point-of-
  entry drop as Water, but it is narrow and golfers can walk across it, so it
  can cut through the middle of a hole. Paint it in lines: the channel joins
  edge-adjacent stream tiles and opens out where it meets a pond.
- **Deep Rough** — Knee-high unmown grass, harsher than heavy rough (0.4 lie,
  60% distance), and it stops a rolling ball dead. Cheap to paint, no upkeep.
- **Waste Bunker** — Natural sandy scrubland. It is *not* a hazard (no raking,
  the club can be grounded), so it plays like sandy rough (0.8 / 0.7 lie, 85%
  distance) and costs nothing to maintain.
- **Rocks** — Stony ground: the worst lie on the course (0.25), wedge only. A
  boulder standing on other ground also plays as Rocks but keeps its grass look.
  Painting Rocks around a boulder merges it into the rocky ground. The bulldozer
  clears painted Rocks back to grass.
- **Brush** — Dense scrub (gorse, heather, sagebrush): 0.3 lie, 50% distance,
  wedge only, and it swallows rolling balls. Golfers wade through it slowly. The
  bulldozer clears it back to grass.

---

## Algorithm

### 1. Ids and save compatibility

Saves store terrain as raw integers, so new types are only ever appended:

```
EMPTY 0, GRASS 1, FAIRWAY 2, ROUGH 3, HEAVY_ROUGH 4, GREEN 5, TEE_BOX 6,
BUNKER 7, WATER 8, PATH 9, OUT_OF_BOUNDS 10, TREES 11, FLOWER_BED 12,
ROCKS 13, FIRM_FAIRWAY 14, POT_BUNKER 15, STREAM 16, DEEP_ROUGH 17,
WASTE_BUNKER 18, BRUSH 19
```

`CourseSurface.PALETTE_KEYS` holds one theme color key per id. The shader
reads the palette width, so a new type needs a palette key and a color in every
theme (`CourseTheme.get_terrain_colors()` and `TilesetGenerator.TERRAIN_COLORS`).

### 2. Families

Gameplay code asks about families instead of single types, so each variant
behaves like its parent everywhere:

```
is_water(t)       WATER, STREAM                 penalty area, drop at entry
is_out_of_play(t) is_water + OUT_OF_BOUNDS + EMPTY
is_bunker(t)      BUNKER, POT_BUNKER            hazards where the ball plugs
is_sand(t)        is_bunker + WASTE_BUNKER      sand spray, sandy lies
is_fairway(t)     FAIRWAY, FIRM_FAIRWAY         shot shapes, AI bonuses, carries
is_rough(t)       ROUGH, HEAVY_ROUGH, DEEP_ROUGH
```

Walking is the exception: golfers path around ponds, OB and off-property land
but cross streams.

### 3. Costs and properties

| Terrain | Build $ | Upkeep $/day | Hazard | Penalty | Walk speed |
| ------- | ------- | ------------ | ------ | ------- | ---------- |
| Fairway | 5 | 1 | | | |
| Firm Fairway | 6 | 1 | | | |
| Rough | 2 | 0 | | | |
| Deep Rough | 1 | 0 | | | 0.85× |
| Green | 20 | 2 | | | |
| Tee Box | 12 | 1 | | | |
| Waste Bunker | 6 | 0 | | | |
| Brush | 3 | 0 | | | 0.75× |
| Bunker | 10 | 1 | yes | | |
| Pot Bunker | 18 | 2 | yes | | |
| Water | 20 | 1 | yes | 1 (drop at entry) | |
| Stream | 15 | 1 | yes | 1 (drop at entry) | |
| Rocks | 8 | 0 | | | |
| Out of Bounds | 0 | 0 | | 1 (stroke and distance) | |

Upkeep is summed over player-placed tiles and scaled as described in
[economy.md](economy.md).

### 4. Shot rules

| Terrain | Lie (wedge / other) | Distance | Roll-out | Ball stops here when rolling | ShotAI score | Recovery clubs |
| ------- | ------------------- | -------- | -------- | ---------------------------- | ------------ | -------------- |
| Fairway | 1.0 | 1.0 | 1.0× | | +150 | |
| Firm Fairway | 0.92 / 1.0 | 1.0 | 1.6× | | +145 | |
| Rough | 0.75 | 0.85 | 0.3× | | +10 | |
| Deep Rough | 0.4 | 0.60 | 0.06× | yes | −45 | wedge, iron |
| Waste Bunker | 0.8 / 0.7 | 0.85 | 0.3× | | −10 | |
| Brush | 0.3 | 0.50 | 0.05× | yes | −85 | wedge |
| Bunker | 0.6 / 0.4 (deep 0.45 / 0.25) | 0.75 (deep 0.60) | no roll | yes | −50 | wedge, iron |
| Pot Bunker | 0.35 / 0.15 | 0.45 | no roll | yes | −90 | wedge |
| Stream | — (penalty) | — | no roll | yes | −1000 | — |
| Rocks | 0.25 | 0.50 | 0.15× | | −100 | wedge |

ShotAI plays a recovery shot when its lie quality falls below 0.4: deep rough
(0.2), pot bunker (0.15), brush (0.12) and rocks (0.1) do; waste bunker (0.6)
and firm fairway (1.0) don't. See [shot-accuracy.md](shot-accuracy.md),
[ball-physics.md](ball-physics.md) and
[shot-ai-target-finding.md](shot-ai-target-finding.md).

### 5. Painting

- Built surfaces (fairways, bunkers, water, stream, tee, green) clear trees and
  boulders they're painted over; natural ground (rough, deep rough, brush, rocks)
  grows around them.
- Stream strokes are 4-connected (`TerrainBrush.centers_4_connected()`) so the
  channel never breaks at a diagonal step.
- Boulders can stand on grass, fairways, roughs and unoccupied painted Rocks.
  Trees can stand on grass, fairways, roughs and path. Both keep off sand, brush
  and water, because their spot draws native grass.
- The bulldozer removes painted Rocks and Brush for $10 a tile, leaving grass.

### 6. Rendering

Each type has its own look in `shaders/course_surface.gdshader`; see
[course-surface.md](course-surface.md). Pot Bunker, Stream, Waste Bunker, Rocks
and Brush are *inset* terrain, drawn over the turf around them so patches have
natural outlines.

---

## Tuning Levers

| Parameter | Location | Current Value | Effect |
| --- | --- | --- | --- |
| Build / upkeep costs | `terrain_types.gd` PROPERTIES | See table | Economy of each tile |
| Lie / distance modifiers | `golf_rules.gd` | See table | Accuracy and distance from each lie |
| Roll-out multipliers | `GolfRules.get_roll_multiplier()` | See table | How far balls run after landing |
| Ground that catches rolling balls | `GolfRules.catches_rolling_ball()` | Water, stream, OB, bunkers, deep rough, brush | Where rolling balls stop |
| AI terrain scores | `ShotAI.TERRAIN_SCORES` | See table | Where AI golfers aim |
| Hotkeys | `terrain_toolbar.gd` | 9, 0, Shift+2/5/6/7/8 | Keyboard access to the new tiles |
| Walking speed | `terrain_types.gd` speed_modifier | Deep rough 0.85×, brush 0.75× | Pace of play through long grass and scrub |
