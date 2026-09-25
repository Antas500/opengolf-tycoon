# Tee Aim Arrow

## Plain English

Every tee tile is painted with a small arrow in its grass, and a red ball sits on
either side of the shaft — the two tee markers a golfer stands between. The arrow
says where the hole plays: it points at the cup, and on a dogleg it curves the way
the hole bends.

* **Straight hole** — one straight arrow aimed down the tee→cup line.
* **Dogleg** — a curved arrow: the tail leaves the tee along the drive line, the
  bend follows the turn of the hole, and the tip points down the approach line
  into the green.
* **Waiting tee box** — the tee box the player just painted, before the hole is
  opened, already aims at the single waiting green with a hole. It is the same
  arrow the hole gets once the player presses **Open Hole**.
* **Nothing to aim at** — a tee box on a course with no waiting cup and no hole of
  its own is bare: there is no direction to paint until something is there to aim
  at. Auto-generated forward and middle tees each aim at the cup of the hole they
  belong to.

The marker is a *sign*, not a map: it is a fixed-size arrow rather than a
miniature of the hole, so every tee on the course reads the same. Direction comes
off the flat map — elevation lifts the tile the arrow is painted on, and must not
bend the arrow — and then the whole marker (shaft, head and both red balls) is
centred on the tile and scaled into the tile's diamond, the isometric tile being
2:1 and therefore much tighter diagonally than along its axes.

## Algorithm

Three pieces, all driven from the tee tile:

```
TeeAimRoute.aim_route(grid, tee, cup)      -> [tee, cup]        straight hole
                                              [tee, corner, cup] dogleg
TeeAimOverlay.rebuild()                    -> which tee tiles aim at which cup
TeeAimOverlay.marker_layout(tee)           -> the painted geometry
```

### Which tee aims where

`TeeAimOverlay.rebuild()` indexes every hole's cup by tee tile — `hole.tee_position`
plus all of `hole.tee_positions` (back / forward / middle) — and then walks
`TerrainGrid.get_tee_box_tiles()`. A tee box that no hole has claimed aims at the
course's single waiting cup (`HoleLayout.unused_cups()`), and the two cases are
mutually exclusive because opening a hole consumes the cup marker. `TerrainGrid`
runs this rebuild (deferred, coalesced) whenever a tile, the waiting cups or the
holes change, and redraws the overlay when the view rotates or the camera moves.

### Where a dogleg bends: the fairway spine

The corner of a dogleg is read off the fairway rather than from the shot planner: a
dogleg *is* a bend in the fairway, and the fairway costs one bounded grid scan
instead of the ~0.2 s a `ShotAI` pass needs. Sampling is done in bands laid
perpendicular to the tee→cup line:

```
axis          = cup - tee,  dir = axis / |axis|
band(p)       = clamp(floor(((p + 0.5 - tee) · dir) / |axis| * SPINE_BANDS), 0, SPINE_BANDS-1)
spine[i]      = mean of the tile-centre positions of the FAIRWAY tiles in band i
                (bands with no fairway are skipped; FIRM_FAIRWAY counts)
corner        = the spine point furthest off the line, inside the middle 20%…80% of the hole
dogleg        = that offset ≥ DOGLEG_MIN_TILES, else the hole plays straight
```

A wide, straight fairway keeps its centroid on the line and is not mistaken for a
dogleg; a fairway flaring out around the tee or the green is excluded by the
middle-bands rule. Par 3s and brand-new holes have no fairway, so they aim straight.
The search area is the tee→cup line grown by `SPINE_SEARCH_MARGIN`, clipped to the
grid, so the scan stays small on a 128×128 course.

### The painted marker

The two route legs give two directions — `in_dir` (tee → corner, the drive line)
and `out_dir` (corner → cup, the approach line). The marker is then built in a
local frame centred on the tile:

```
turn        = in_dir.angle_to(out_dir)          # 0 (or < TURN_MIN_RADIANS) => straight
chord_dir   = (in_dir + out_dir).normalized()
radius      = ARROW_LENGTH / (2 · sin(|turn| / 2))
tail        = -chord_dir · ARROW_LENGTH / 2
centre      = tail + perp(in_dir) · sign(turn) · radius
shaft       = centre + (tail - centre).rotated(turn · t),  t = 0 … 1   # circular arc
head        = triangle at shaft tip, aiming along the last leg
balls       = shaft point BALL_ANCHOR_FRACTION along, ± perp(shaft) · BALL_OFFSET
```

A circular arc keeps the arrow the same length as a straight one and turns it by
exactly the hole's own bend, so a 90° dogleg reads as a quarter-turn arrow and a
45° dogleg as a gentler curve — and the tip always points down the approach line.

The marker is then centred on the tile — by the box of what is actually painted,
head included — and scaled to fit the shape the tile's grass covers. That shape is
the tile's *projected* outline (`TerrainGrid.tile_polygon()`): a 2:1 diamond in the
isometric view, leaning and stretching with the corner elevations of sculpted
ground, and a square in the top-down view. Each of its four edges becomes an
outward line `n·p + offset ≤ 0`, and each painted part (shaft, head, red markers)
reaches `n·point + pen` toward an edge, so:

```
gap(edge)   = -(n·centre + offset) - SAFE_INSET      # room from the tile centre to that edge
scale       = min(1, min over edges and parts of  gap(edge) / (n·point + pen))
```

A pen shrinks with the marker (the painter scales its own line widths), so it
divides the same way. The red markers' 2.5 px radius is what makes them the
binding constraint on a diagonal arrow: a 16 px-tall diamond leaves much less room
sideways than along its axes, so a diagonal arrow ends up a little smaller than an
axis-aligned one — exactly as much as the tile demands, and no more, because the
scale never goes above 1. The two directions are drawn with two different
outlines, too: in the top-down view the tile is a square and every arrow fits at
full size, while in the isometric view the same arrow is fitted to the diamond.

Two tile shapes have no honest fit at all, and both stop at `MIN_FIT_SCALE`
instead of shrinking into an unreadable speck — the marker then laps a pixel or two
over the tile edge:

* **A folded tile** — a cliff edge steeper than the tile is wide pulls its corners
  past each other, so its outline crosses itself and has no dependable inside.
  Detected by the corners no longer all turning the same way (`_is_convex()`), which
  is also why the fit uses edge *lines* rather than the polygon: for the convex
  outline every normal tile has, they are the same region.
* **A sliver tile** — a tile leaning hard to one side can leave less room at its
  centre than the arrow head needs.

That is a deliberate trade: a marker that hangs a pixel or two into the neighbouring
tile still tells the golfer where the hole plays, and a marker scaled down to a
speck does not.

## Tuning Levers

| Lever | Location | Value | What changing it does |
|---|---|---|---|
| `SPINE_BANDS` | `tee_aim_route.gd` | 8 | How finely the fairway is sampled along the hole |
| `DOGLEG_MIN_TILES` | `tee_aim_route.gd` | 2.5 | How far the fairway must leave the tee→cup line before a hole counts as a dogleg (2.5 tiles ≈ 55 yards) |
| `SPINE_SEARCH_MARGIN` | `tee_aim_route.gd` | 6 | How far either side of the line fairway is searched |
| `CORNER_BAND_START/END` | `tee_aim_route.gd` | 0.2 / 0.8 | How much of the hole's middle must carry the bend |
| `ARROW_LENGTH` | `tee_aim_overlay.gd` | 32 | Painted arrow length before the tile fit |
| `TURN_MIN_RADIANS` | `tee_aim_overlay.gd` | 0.05 | Below this turn the arrow is drawn straight |
| `SHAFT_WIDTH` / `EDGE_WIDTH` | `tee_aim_overlay.gd` | 3.6 / 5.2 | Paint width, and the dark rim that keeps it readable on dark turf |
| `HEAD_LENGTH` / `HEAD_HALF` | `tee_aim_overlay.gd` | 8.6 / 5.0 | Arrow head size |
| `BALL_RADIUS` / `BALL_OFFSET` | `tee_aim_overlay.gd` | 2.5 / 6.8 | Red tee markers: size, and how far they straddle the shaft |
| `BALL_ANCHOR_FRACTION` | `tee_aim_overlay.gd` | 0.5 | Where along the shaft the markers sit |
| `SAFE_INSET` | `tee_aim_overlay.gd` | 2.6 | Pixels kept between the paint and the tile edge |
| `MIN_FIT_SCALE` | `tee_aim_overlay.gd` | 0.45 | Smallest the marker is ever drawn; a tile with less room than this gets a minimum-size marker instead of an unreadable speck |
| `PAINT_COLOR` / `BALL_COLOR` | `tee_aim_overlay.gd` | off-white / red | The painted arrow and the two tee markers |
| `Z_INDEX` | `tee_aim_overlay.gd` | 6 | Paint order: terrain, this overlay, then golfers and the ball |
