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
   **Green Without Hole** brush and paints at the normal brush size and preset
   shapes, so the player can widen the putting surface around the cup.
3. **Open Hole** (`H` or the toolbar button, enabled only when a pair is ready)
   pairs the single unused tee box with the single unused Green With Hole and
   creates the hole: yardage, par, forward/middle tees, pin rotation set and
   difficulty rating all follow from those two tiles.

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
| Green Without Hole brush | `TerrainToolbar.BRUSH_SIZES` | up to 9×9 |
| Tee box cost / green cost | `TerrainTypes.PROPERTIES` | $12 / $20 per tile |
| Waiting-cup pin color | `CupOverlay.WAITING_PIN_COLOR` | gold |

## Tests

- `tests/unit/test_hole_layout.gd` — the rules above, including claims by existing holes.
- `tests/unit/test_cup_tiles.gd` — cup marker lifecycle, tee index, save round trip.
- `tests/unit/test_hole_creation_tool.gd` — `open_hole()` output and preconditions.
- `tests/integration/hole_creation_flow.gd` — the whole flow through `main.gd`:
  capped tee brush, blocked second tee, cup green, undo/redo of the cup, widening
  the green, Open Hole pairing, and a save/load round trip.
- `tests/integration/generated_course_hole_layout.gd` — Quick Start and all four
  prebuilt packages still deliver every hole and leave nothing waiting.
- `tests/integration/new_game_resets_course.gd` — a second New Game starts from a
  clean grid: no leftover tiles, cups, entities, hole flags, elevation or undo.
