# Buildings on the Grid

> **Source:** `scripts/entities/course_architecture.gd`,
> `scripts/entities/building.gd`, `scripts/ui/placement_preview.gd`,
> `scripts/ui/components/building_tile_art.gd`

## Plain English

Every facility in the game is a little isometric building standing on the tiles
that were bought for it. The clubhouse, the pro shop, the cart shed and the rest
are drawn from their own footprint: their walls run along the same 2:1 diamonds
the terrain draws, their roofs slope with the course's own isometric axes, and
their doors face the edge golfers actually walk to. Nothing is a flat elevation
laid over the grid.

The same routine draws the placed building, the ghost that follows the cursor
before a click, and the little picture on the Buildings tab. A player comparing
the shelf tile with the footprint under the cursor is looking at the same
geometry, scaled.

## The one rule

Everything about a building is authored in **grid space**:

- `x` — tiles across the footprint's own square (`u`)
- `y` — tiles down it (`v`)
- `z` — pixels above the ground

`CourseArchitecture.project_point()` maps a grid point onto the screen through
the terrain's own 2:1 axes, so a wall corner at `(0.4, 0.4)` lands on the tile
corner the course draws there. The projection is written once and shared; a
facility routine never converts between the two spaces itself.

The view can be rotated a quarter turn at a time and every building turns with
it, because `facing` is a rotation inside that same transform rather than a
different set of drawings. `Building.set_position_in_grid()` — which the game
calls on every placed entity after a rotation — hands the new `facing` to the
architecture node, so the walls the player sees are always the ones the
building actually has.

| Piece | What it is |
| --- | --- |
| `grid_origin_offset(size, facing)` | Where grid `(0, 0)` falls in the building node's local space, matching the anchor `Building.set_position_in_grid()` uses |
| `project_point(origin, p, facing)` | Grid point → local draw space |
| `screen_delta(offset)` | A bare grid offset → screen offset (used for extents and shadows) |
| `face_shade(normal)` | How brightly a plane facing a grid direction is lit |
| `Sketch` | The shared drawing surface: `walls`, `hip_roof`, `window_at`, `door_at`, `awning`, `terrace`, `contact_shadow`… |

`Sketch` also keeps the grid-space box of everything it has drawn. That box is
returned by `draw_building()`, and the unit tests use it to hold every facility
to its square at every rotation (`tests/unit/test_isometric_architecture.gd`).
Weather is the one exception: chimney smoke is drawn straight to the canvas, so
a drifting plume never counts as part of the building.

## The footprint on screen

`Building.set_position_in_grid()` positions the node at

```
footprint centre - (size.x * 0.5, size.y)
```

in both views, so the art must be projected around that same anchor rather than
around the footprint's own centre. Getting that wrong slides every building
half a tile across its own square — the failure is invisible on one tile and
obvious on four, which is what `grid_origin_offset()` exists to prevent.

The contact shadow is the footprint diamond itself, nudged in the shadow
direction and drawn at `ShadowSystem.shadow_intensity`, tinted green so it reads
as shade on grass. It is deliberately not a detached oval under the terrace.

## Facilities

Each kind has its own routine, but they all hold to the same scale: a storey is
about 20–30 pixels, doors are 14–17, and windows are placed against the two
walls facing the viewer. A facility fills the tiles it stands on — a one-tile
hut fills its diamond; a six-tile driving range runs along it.

| Kind | What gives it away |
| --- | --- |
| Clubhouse | Paved terrace, stone plinth, hipped roof, chimney, entrance canopy. Tier 2 adds a front range; tier 3 adds a storey and a clock tower that clears the roof behind it |
| Pro Shop | Display window with merchandise, striped awning, bag stand |
| Restaurant | Lit windows with flower boxes, awning, chimney with smoke, terrace table |
| Snack Bar | Serving hatch, menu board, cup badge |
| Driving Range | A row of covered bays with padded dividers and ball baskets |
| Cart Shed | Open bays with parked carts, roof vent, wheel stops |
| Restroom | Two labelled doors, trellis and roses |
| Conservatory | Glazed mullioned walls and a glass lantern roof |
| Tea Pavilion | Corner posts carrying a wide shade roof, tea tables |
| Garden Spa | Bathing pool ringed by loungers |
| Golf Academy | Teaching bays with netting and a sign board |
| Locker Room | Twin doors, club rack, benches |
| Coffee House / Halfway House / Ice Cream Kiosk | A counter, a striped awning, and a landmark: a chimney, a scoop sign, a steam cup |

## What happened to the sprites

Buildings used to be pixel-art sprites (`assets/sprites/buildings/`) pasted on
top of the grid. They were retired with this design: the `Sprite2D` node, the
chimney-offset and window-glow-rectangle tables, and the flat-facade polygon
routines all went with them, and so did the image files. Window glow, lit
windows and chimney smoke are now part of the drawing itself — the same
routine draws a lit or unlit window depending on the weather and the time.

Bench is the one exception. It is a ground fixture, so it still delegates to
`PathFurniture.draw_item()`.
