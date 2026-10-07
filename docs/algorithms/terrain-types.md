# Terrain Types

> **Source:** `scripts/terrain/terrain_types.gd` (ids, properties, families), `scripts/systems/golf_rules.gd` (lie, distance, roll, penalties), `scripts/systems/shot_ai.gd` (scores, recovery), `scripts/ui/terrain_toolbar.gd` (tiles, hotkeys), `data/terrain_types.json` (mirror)

## Plain English

Every tile of the course is one terrain type. The type decides what it costs to
build and maintain, how well a golfer can strike a ball lying on it, how far a
ball runs after landing on it, whether it is a penalty area, and how the course
surface shader draws it.

The **Course Terrain** tab combines course surfaces, hazards, Flower Bed, the
boulder grounds, and the theme's woodland tiles into one horizontally scrolling
honeycomb. Two interlocking rows keep the course tiles first, with landscaping
extending the right end of each row:

| Row | Course tiles (left to right) |
| --- | --- |
| Top | Tee Box, Green, Bunker, Rough, Pot Bunker, Stream, Water, Out of Bounds |
| Bottom | Fairway, Firm Fairway, Deep Rough, Waste Bunker, Brush, Rocks, Small Boulders, Large Boulders |

The honeycomb width adapts to the theme's tree catalogue while staying two rows
high. The brush controls stay in a column before it. **Open Hole** is a tile too:
a half-size course cell (`OpenHoleNotchButton`) nestled into the notch between
the Tee Box and Green tiles (see `TileHoneycomb.set_notch_child`), the pair the
action opens. It takes no slot, so no tile moves along the rows, and it keeps
the plain `[H]` chip for its caption — a cell that small has no room for the
name, which the tooltip and assistive tech carry. Its ring is gold while a tee
and a cup are waiting to be paired and grey while they are not, so the chip
reports whether a hole can be opened. The Bulldozer is not a course tool at all:
it is pinned to the Improvements and Buildings tabs, whose tiles it can remove.
The Path improvement lives on the Improvements tab instead, drawn as a course
tile in the same honeycomb as the decoration tiles and placed first in the top
row, because it is the improvement players reach for most. Its tile previews
the rough a trail is cut through with the dirt ribbon across it — a path lies on
top of the ground rather than replacing it (see [garden catalog](garden-catalog.md)).
Natural Grass is never painted by generation: it is only the blank canvas a
fresh grid starts from, and terrain generation sweeps it into Rough — the
zero-upkeep base turf of every generated course. Heavy Rough, the woodland
tiles and Empty are placed by generation; the boulder grounds and every tree
species are ordinary painted course tiles, so generation may scatter them like
any other zero-upkeep terrain. Nothing about a wood is a separate object: the
tile is the tree.

### The newer tiles

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
- **Rocks** — Stony ground: the worst lie on the course (0.25), wedge only.
  The surface draws it as a gravelly field of small stones, the finest of the
  three stony looks. Like every course tile it is ground paint: the bulldozer
  never touches course terrain.
- **Small Boulders** — The same stone ground drawn as pebbles with the odd
  larger stone. Identical to Rocks in cost, lie, roll-out, AI score and
  walking; only the stones the shader draws differ.
- **Large Boulders** — The same ground again, crowded with big boulders that
  stand up out of it (so no tile reads as bare gravel). Identical to Rocks in
  every rule and different only in the stones drawn on it.
- **Brush** — Dense scrub (gorse, heather, sagebrush): 0.3 lie, 50% distance,
  wedge only, and it swallows rolling balls. Golfers wade through it slowly.
  Replace it by painting another terrain tile over it; the bulldozer ignores it.
- **Woodland, one tile per species** — Oak, Pine, Maple, Birch, Cactus, Fescue,
  Cattails, Shrub, Palm, Dead Tree and Heather, plus the generic Trees tile for
  canopies the theme picks. Every one of them is the Trees tile with a new
  name: same $10 to paint, no upkeep, same 0.7 lie, same blocked shot, same
  roll-out, same walking, same AI score. Only two things change with the
  species — the sprite the course stands on the tile (`TreeOverlay`) and the
  ground the tile paints under it (`TREE_GROUND_LOOKS`): leaf litter for the
  broadleaves and shrubs, pine needles, bare sand for cactus, palm and dead
  trees, waterlogged silt for cattails, acid peat for heather and dry straw for
  fescue. A theme offers the four or five species that suit it
  (`CourseTheme.get_tree_types()`), so the tab shows a desert full of cacti and
  a links full of fescue without any of them behaving differently.

---

## Algorithm

### 1. Ids and save compatibility

Saves store terrain as raw integers, so new types are only ever appended:

```
EMPTY 0, GRASS 1, FAIRWAY 2, ROUGH 3, HEAVY_ROUGH 4, GREEN 5, TEE_BOX 6,
BUNKER 7, WATER 8, PATH 9, OUT_OF_BOUNDS 10, TREES 11, FLOWER_BED 12,
ROCKS 13, FIRM_FAIRWAY 14, POT_BUNKER 15, STREAM 16, DEEP_ROUGH 17,
WASTE_BUNKER 18, BRUSH 19, SMALL_BOULDERS 20, LARGE_BOULDERS 21,
OAK 22, PINE 23, MAPLE 24, BIRCH 25, CACTUS 26, FESCUE 27, CATTAILS 28,
SHRUB 29, PALM 30, DEAD_TREE 31, HEATHER 32
```

The boulder fields reuse the `rocks` palette key: all three stony grounds
share one base colour and the shader only changes the stones it scatters. The
eleven species likewise reuse the `trees` key — one canopy colour per theme for
their art, swatches and mini map — while the shader works each one up into the
ground that species is planted in (see `TREE_GROUND_LOOKS`).

`CourseSurface.PALETTE_KEYS` holds one theme color key per id. The shader
reads the palette width, so a new type needs a palette key and a color in every
theme (`CourseTheme.get_terrain_colors()` and `TerrainPalette.TERRAIN_COLORS`).

`data/terrain_types.json` mirrors the ids one row each (`id`, `name`, `playable`,
`placement_cost`, `blocks_shots`). Nothing reads it at runtime; it exists for
tools and modders, and `test_json_mirror_lists_every_type` fails if an id goes
missing or its name or cost drifts from `PROPERTIES`.

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
is_rocks(t)       ROCKS, SMALL_BOULDERS, LARGE_BOULDERS
is_tree(t)        TREES, OAK, PINE, MAPLE, BIRCH, CACTUS, FESCUE, CATTAILS,
                  SHRUB, PALM, DEAD_TREE, HEATHER
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
| Trees, and every species tile | 10 | 0 | | | |
| Small Boulders | 8 | 0 | | | |
| Large Boulders | 8 | 0 | | | |
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
| Small Boulders | 0.25 | 0.50 | 0.15× | | −100 | wedge |
| Large Boulders | 0.25 | 0.50 | 0.15× | | −100 | wedge |

ShotAI plays a recovery shot when its lie quality falls below 0.4: deep rough
(0.2), pot bunker (0.15), brush (0.12) and the three stony grounds (0.1) do; waste bunker (0.6)
and firm fairway (1.0) don't. See [shot-accuracy.md](shot-accuracy.md),
[ball-physics.md](ball-physics.md) and
[shot-ai-target-finding.md](shot-ai-target-finding.md).

### 5. Painting

- Every Course Terrain tile replaces every other one, the woodland tiles
  included: `TerrainGrid.set_tile` swaps the ground, dropping the tile's cup,
  tee and walking-path state when the new ground can't keep them. A pine tile
  overwrites water, sand, greens, an oak, or a walking path's host ground
  exactly as Rocks or Wild Flowers do, for its own `placement_cost` and nothing
  more — there is no clearing fee, because there is nothing to clear.
  Buildings and decorations are not course terrain — the bulldozer removes
  those, and a course tile will not paint over them.
- Stream strokes are 4-connected (`TerrainBrush.centers_4_connected()`) so the
  channel never breaks at a diagonal step.
- What you paint is what the tile shows: a species tile draws that species'
  canopy (`TreeOverlay`) on that species' ground, wherever it lands. Old saves
  that planted trees as entities are converted on load — `EntityLayer.deserialize`
  paints the matching species tile for each one — so a saved course loads as
  painted woodland and the tiles are then edited like any other.
- The bulldozer never touches course terrain — its button lives on the
  Improvements and Buildings tabs and only demolishes paths, decorations and
  buildings.

### 6. Rendering

Each type has its own look in `shaders/course_surface.gdshader`; see
[course-surface.md](course-surface.md). Pot Bunker, Stream, Waste Bunker, Rocks,
Small Boulders, Large Boulders, Brush and the twelve woodland tiles are *inset*
terrain, drawn over the turf around them so patches have natural outlines —
a wood ends where its ground does, not at a tile line.

---

## Tuning Levers

| Parameter | Location | Current Value | Effect |
| --- | --- | --- | --- |
| Build / upkeep costs | `terrain_types.gd` PROPERTIES | See table | Economy of each tile |
| Lie / distance modifiers | `golf_rules.gd` | See table | Accuracy and distance from each lie |
| Roll-out multipliers | `GolfRules.get_roll_multiplier()` | See table | How far balls run after landing |
| Ground that catches rolling balls | `GolfRules.catches_rolling_ball()` | Water, stream, OB, bunkers, deep rough, brush | Where rolling balls stop |
| AI terrain scores | `ShotAI.TERRAIN_SCORES` | See table | Where AI golfers aim |
| Hotkeys | `terrain_toolbar.gd` | 9, 0, Shift+2/5/6/7/8/9/0 | Keyboard access to the new tiles (Shift+9 Small Boulders, Shift+0 Large Boulders) |
| Walking speed | `terrain_types.gd` speed_modifier | Deep rough 0.85×, brush 0.75× | Pace of play through long grass and scrub |
| Woodland grounds | `terrain_types.gd` TREE_GROUND_LOOKS, mirrored by `tree_look()` in the shader | litter, needles, sand, silt, peat, straw | What each species is planted in, and which species' grounds meet without a seam |
| Which species a theme grows | `course_theme.gd` get_tree_types() | 4-6 per theme | The tiles that appear on the Course Terrain tab |
