# Hole Creation

## Plain English

A hole is no longer drawn in one wizard pass. The player lays out the two ends with
the ordinary terrain brushes and then opens the hole:

1. **Tee Box** paints exactly one tile. While that tee box is still *unused* — not
   claimed by a hole — no second tee box can be placed, so at most one tee waits on
   the course at any time.
2. **Green** paints a **Green With Hole** when the course has no waiting cup: one
   tile with a cup cut into it, drawn with a gold pin so it is distinguishable from
   the red pins of open holes. Once a cup is waiting, the same Green tool becomes a
   **Green Without Hole** brush and paints with the normal terrain brush size
   and shape, so the player can widen the putting surface around the cup.
3. **Open Hole** (`H` or the toolbar button, enabled only when a pair is ready)
   pairs the single unused tee box with the single unused Green With Hole and
   creates the hole: yardage, par, forward/middle tees, pin rotation set and
   difficulty rating all follow from those two tiles.

While a tee box is waiting and the Green tool is about to cut a cup, the placement
preview shows the **potential hole** under the cursor, before anything is painted.
It draws a dashed path from the waiting tee to the hovered tile, marks the expected
landing zones and the cup with its gold pin, and shows a plaque with the hole number,
par and yardage, e.g. `Hole 3 · Par 4 · 398 yds`. The route comes from the same
shot planner that draws an open hole's path, so the preview is the path the hole
gets once the cup is cut and the hole is opened. When a pair couldn't open, the
path and pin turn red and the plaque explains why:

- the tee and cup are too close together;
- the tile is already green;
- the player doesn't own the land;
- a building or decoration is in the way;
- more than one tee box is waiting.

The path disappears as soon as the cup is cut, when another tool is selected or
the tool is deselected, and when no tee box is waiting.

"Unused" means *not already claimed by a hole*. Auto-generated forward and middle
tees belong to their hole, so they never block the next tee box. Deleting a hole
returns its tee box to the unused pool, so it can be paired with a freshly cut cup
instead of being bulldozed.

Opening a hole consumes the cup marker — the cup becomes the hole's
`hole_position` — so the next green the player paints carries the next hole's cup
and the loop repeats. Painting any other terrain over a Green With Hole removes its
cup. Undo and redo restore the cup with its tile, and waiting cups are part of the
save file.

The brush cap is advisory *and* enforced: the toolbar locks its +/- controls and
shows `1x1` while a capped tool is selected, and `main._paint_terrain_stamp()`
recomputes the cap per stamp, so a drag that paints the first cup continues as an
ordinary green brush for the rest of the stroke.

## Algorithm

`HoleLayout` (`scripts/tools/hole_layout.gd`) is the single source of truth; the
toolbar, the placement preview and the paint path all read the same functions.

```
used_tee_tiles(course)   = { hole.tee_position } ∪ { hole.tee_positions[*] }   for every hole
used_cup_tiles(course)   = { hole.hole_position } ∪ { hole.pin_positions[*] } for every hole
unused_tee_boxes(grid)   = grid.get_tee_box_tiles() − used_tee_tiles
unused_cups(grid)        = grid.get_cup_tiles()   − used_cup_tiles

green_places_cup         = unused_cups.is_empty()
can_place_tee_box        = unused_tee_boxes.is_empty()

max_brush_size(TEE_BOX)  = 1
max_brush_size(GREEN)    = 1 if green_places_cup else UNLIMITED_BRUSH (0)
max_brush_size(other)    = UNLIMITED_BRUSH
```

`TerrainGrid` keeps two indexes in step with `_grid` so these checks are
dictionary lookups rather than grid scans: `_tee_box_tiles` (maintained by
`set_tile()`, rebuilt by `_reindex_tee_boxes()` on load) and `_cup_tiles`
(`add_cup_tile()` / `remove_cup_tile()`, dropped automatically when the tile stops
being `GREEN`).

`open_hole_request()` returns `{ready, reason, tee, cup}`:

| Condition | Result |
|---|---|
| No waiting tee and no waiting cup | not ready — "Paint a tee box (T) and a green (3) to lay out a hole." |
| No waiting tee | not ready — "Paint a tee box to go with the waiting green." |
| No waiting cup | not ready — "Paint a green to cut a cup for the waiting tee box." |
| More than one waiting tee / cup | not ready — "Holes open one at a time: N …" |
| `distance(tee, cup) < MIN_HOLE_TILES` | not ready — "…only X yards apart — a hole needs at least 110 yards." |
| Exactly one of each, far enough apart | ready, with the pair |

`HoleCreationTool.open_hole(tee, cup)` checks those preconditions (tee tile is
`TEE_BOX`, cup tile is `GREEN`, distance ≥ `MIN_HOLE_TILES`) and then builds the
`HoleData`: distance from `calculate_distance_yards()` (22 yd/tile), par from
`GolfRules.calculate_par()`, forward/middle tees from `auto_generate_tee_positions()`
when multi-tee is on, and the pin set from `auto_generate_pin_positions()`. Because
that helper replaces the cup with a quadrant extreme of the green, the builder puts
the player's cup back at the front of `pin_positions` and resets
`current_pin_index = 0`, so the cup the player cut is the cup that opens — daily pin
rotation still cycles the rest.

Generated courses (Quick Start and the four prebuilt packages) share the same
builder through `create_generated_hole(tee, green)`, which skips the
preconditions: those layouts only paint the land the player owns, so a championship
hole that runs off the property still exists as a hole (with the tee surface to be
finished later) rather than silently disappearing.

### Potential hole path

`HoleLayout.potential_hole(tool, grid, course, cup_pos)` decides whether the path is
shown and what it says. `PlacementPreview._update_potential_hole()` calls it every
frame with the hovered tile. It is only called while terrain painting, and never in
elevation, bulldozer, entity-placement or hole-move modes.

```
potential_hole = {}                                   unless all of:
    tool == GREEN
    green_places_cup(grid, course)                    # next green is a Green With Hole
    unused_tee_boxes(grid, course) is not empty       # a tee box is waiting
    grid.is_valid_position(cup_pos)

tee             = nearest unused tee box to cup_pos   (ties → first in sorted order)
distance_yards  = grid.calculate_distance_yards(tee, cup_pos)
par             = GolfRules.calculate_par(distance_yards)
hole_number     = course.holes.size() + 1
extra_tees      = forward/middle tiles auto_generate_tee_positions() would add
                  (multi-tee only; see extra_tee_tiles())
can_cut_cup     = cup_site_blocker(grid, cup_pos) == ""
ready           = can_cut_cup and exactly one tee waits
                  and |cup_pos − tee| ≥ MIN_HOLE_TILES
```

`cup_site_blocker()` mirrors `main._paint_terrain_stamp()`. A stamp skips land the
player doesn't own and tiles under a building or decoration. Painting green onto a
tile that is already green doesn't change the tile, so no cup is cut there either.
On a tile where the cup can be cut, `ready` predicts what `open_hole_request()`
will return once it is cut, and the unit tests check the two agree.

**Route.** `HolePathPlanner` returns the route for the pair. It calls
`ShotPathCalculator.calculate_route()`, the same function
`calculate_waypoints()` → `HoleVisualizer` uses, so the preview and the opened
hole show the same waypoints. The planner makes two adjustments so the routes match:

- `hole_index = −1`: the pair is not in `course.holes` yet, so ShotAI's green-centre
  bias is skipped. Without this it would read `holes[0]` and bend the approach
  toward another hole's green.
- The route is planned on a terrain copy painted the way the course will look once
  the hole opens: the cup tile is green, plus the forward/middle tees on multi-tee
  courses.

ShotAI takes about 0.2 s for a par 4 and 0.4 s for a par 5, which is too slow to
run on the main thread for every tile the cursor crosses. So the planner works like
this:

| Case | What happens |
|---|---|
| Par 3 | `[tee, cup]`, immediately (ShotAI is not consulted) |
| Par 4/5, cached | Cached route, immediately |
| Par 4/5, not cached | `[]` returned, and the preview draws a faded straight line. A `WorkerThreadPool` task plans the route on `TerrainGrid.create_analysis_copy()`, a detached copy of tiles, bunker depths and elevation that never enters the scene tree. One task runs at a time. While it runs, only the newest request is kept, so the route catches up once the cursor settles. |
| No thread support (Web export) | Planned on the main thread once the cursor has rested on the tile for `inline_dwell_msec` |

Routes are cached per `(tee, cup, par, extra tees)`. The cache is dropped whenever
`TerrainGrid.terrain_revision` changes. Every write to tiles, bunker depths or
elevation bumps the revision, including loads and generation that emit no per-tile
signals. A route planned on terrain that changed while the task ran is discarded.

### New Game

Both rules count tiles on the *current* course, so a new game has to start from an
empty grid — a tee box left over from the previous course would block the player's
first tee. `_on_new_game_started()` therefore clears entities and hole flags first
(removing an entity restores the terrain beneath it), then calls
`TerrainGrid.reset_for_new_course()` to put every tile back to `GRASS` and drop the
player-placed marks, bunker depths, sculpted elevation and waiting cups, and finally
clears the undo stack. Natural terrain generation paints over the grid rather than
clearing it, which is what used to let the old course leak through.

## Tuning levers

| Lever | Location | Value |
|---|---|---|
| Minimum tee-to-cup distance | `HoleLayout.MIN_HOLE_TILES` | 5 tiles (110 yd) |
| Yards per tile | `TerrainGrid.calculate_distance_yards()` | 22 yd |
| Tee box brush cap | `HoleLayout.max_brush_size()` | 1×1 |
| Green With Hole brush cap | `HoleLayout.max_brush_size()` | 1×1 |
| Green Without Hole brush | `TerrainToolbar.BRUSH_SIZES` | up to 9×9 (shared terrain brush; no green-specific presets) |
| Tee box cost / green cost | `TerrainTypes.PROPERTIES` | $12 / $20 per tile |
| Waiting-cup pin color | `CupOverlay.WAITING_PIN_COLOR` | gold |
| Potential hole path colors | `PlacementPreview.HOLE_PATH_*` | cream path, red when not ready |
| Potential hole plaque font size | `PlacementPreview.HOLE_PATH_FONT_SIZE` | 13 px, constant on screen |
| Cached potential-hole routes | `HolePathPlanner.MAX_CACHED_ROUTES` | 256 |
| No-thread route delay | `HolePathPlanner.inline_dwell_msec` | 500 ms |

## Tests

- `tests/unit/test_hole_layout.gd` — the rules above, including claims by existing holes.
- `tests/unit/test_cup_tiles.gd` — cup marker lifecycle, tee index, save round trip.
- `tests/unit/test_hole_creation_tool.gd` — `open_hole()` output and preconditions.
- `tests/unit/test_potential_hole.gd` — when the potential hole is shown, which tee
  it pairs with, the yardage, par and hole number it reports, blocked cup sites,
  and multi-tee previews.
- `tests/unit/test_hole_path_planner.gd` — background planning, preview route ==
  opened-hole route (with and without extra tees), caching, invalidation on terrain
  edits, the no-thread fallback, and the detached terrain copy.
- `tests/unit/test_shot_path_calculator.gd` — `calculate_route()` and the
  `hole_index = −1` guard against borrowing another hole's green.
- `tests/integration/hole_creation_flow.gd` — the whole flow through `main.gd`:
  capped tee brush, blocked second tee, cup green, undo/redo of the cup, widening
  the green, Open Hole pairing, and a save/load round trip.
- `tests/integration/hole_path_preview.gd` — the preview through `main.gd` with a
  simulated cursor: when it is hidden or shown, par 3 vs a par 4 planned in the
  background, and the previewed route matching the opened hole's (par 4, and par 5
  with multi-tee).
- `tests/integration/generated_course_hole_layout.gd` — Quick Start and all four
  prebuilt packages still deliver every hole and leave nothing waiting.
- `tests/integration/new_game_resets_course.gd` — a second New Game starts from a
  clean grid: no leftover tiles, cups, entities, hole flags, elevation or undo.
