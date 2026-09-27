# Elevation Selector Tools

## Plain English

Terrain elevation is sculpted with three selector tools on the Elevation tab,
which replace the old Rolling Hill, Hollow, Raise and Lower tools:

- **Vertex Selector** (`V`) — raises or lowers a single grid vertex by one
  step.
- **Flat Square Selector** (`+`) — takes the S×S square of vertices under the
  cursor, evens it (the lowest vertices are raised up to the square's highest,
  or the highest are lowered down to its lowest), then raises or lowers the
  whole square one step. The square moves as one flat slab.
- **Gradual Square Selector** (`-`) — raises or lowers the middle vertex (odd
  sizes) or the middle 2×2 square of vertices (even sizes), then moves the
  nearby vertices inside the square whenever they would end up more than one
  elevation away per vertex of distance from the changed middle. Repeated
  clicks build a one-step-per-tile pyramid or basin — the terrain stays
  gradual.

While a selector is active, **right clicking raises** the selected terrain and
**left clicking lowers** it. A button press starts a stroke, dragging paints,
and releasing the button ends the stroke. No vertex outside the selection is
ever touched, and vertices under buildings or on unowned land are skipped.
Esc still cancels the tool (right click no longer does).

The two Square Selector tools carry their own **Elevation Brush Size** and
**Elevation Brush Shape** (square or round) controls, kept separate from the
Terrain Brush controls on the Course Terrain tab. Flat offers 1×1 through 9×9;
Gradual offers 2×2 through 9×9 (a one-vertex "middle square" is just the
Vertex tool). Each tool remembers its own size and shape.

Elevation levels are integers from `MIN_ELEVATION` (-5) to `MAX_ELEVATION`
(+5) on the `(grid_width + 1) × (grid_height + 1)` vertex field owned by
`TerrainGrid`.

## Algorithm

### Square area geometry (`ElevationTool.square_offsets`)

An S×S area is centred on the cursor vertex `c`. Offsets run from
`-(S-1)//2` to `S-1 - (S-1)//2`, so odd sizes centre on the cursor vertex and
even sizes centre on the middle 2×2 block. With a round shape, corners are
clipped by a circle of radius `(S-1)/2 + 0.5` around the area centre
(`(0.5, 0.5)` for even sizes):

```gdscript
static func square_offsets(size: int, round_shape: bool) -> Array[Vector2i]:
    var from: int = -int((size - 1) / 2)
    var to: int = size - 1 + from
    var centre: float = 0.5 if size % 2 == 0 else 0.0
    var limit: float = float(size - 1) / 2.0 + 0.5
    for x in range(from, to + 1):
        for y in range(from, to + 1):
            if round_shape:
                var dx: float = float(x) - centre
                var dy: float = float(y) - centre
                if dx * dx + dy * dy > limit * limit:
                    continue
            result.append(Vector2i(x, y))
    return result
```

`square_vertices()` maps the offsets to absolute vertices and drops the ones
off the grid. `middle_vertices()` returns `[c]` for odd sizes and
`{c, c+(1,0), c+(1,1), c+(0,1)}` for even sizes.
`distance_to_middle()` is the Chebyshev distance from a vertex to the middle
vertex or middle block — one per vertex of travel.

### Vertex Selector

```
new_elevation = clamp(old + (1 if raising else -1), MIN, MAX)
```

### Flat Square Selector

Let the selected (editable, on-grid) vertices of the area be `A`, with
`lowest = min A`, `highest = max A`. Every vertex in `A` is set to one
target — "even the square, then shift it" in a single step:

```
target = clamp(highest + 1, MIN, MAX)   # raising  (right click)
target = clamp(lowest  - 1, MIN, MAX)   # lowering (left click)
```

Raising the `{0, 0, 2, 2}` square sends every vertex to 3; lowering it sends
every vertex to -1. An already-even square simply steps up or down. When the
square sits at +5 (raising) or -5 (lowering) the target equals the current
heights and nothing changes.

### Gradual Square Selector

1. **Move the middle as one unit.** Level the middle vertex / middle 2×2
   square, then shift it one step:
   ```
   level  = max middle  (raising)   /  min middle  (lowering)
   middle_target = clamp(level + (1 if raising else -1), MIN, MAX)
   ```
   If no middle vertex changed (already even and at its limit) the stroke is a
   no-op.
2. **Keep the area gradual.** Every other selected vertex `v` is clamped into
   the cone around the new middle height, where `d` is
   `distance_to_middle(v)`:
   ```
   new_elevation = clamp(old, middle_target - d, middle_target + d)
   ```
   So a vertex one away may differ from the middle by at most one, two away by
   at most two, and so on — the one-step-per-tile slope around the change.
   Vertices that already fit the gradient are not touched.

Both tools record each changed vertex as `{position, old_elevation,
new_elevation}` and hand the list to
`UndoManager.record_elevation_stroke()`; undo/redo replays the entries
through `TerrainGrid.set_vertex_elevation()`.

### Input flow (`main.gd`)

- Left press (`select` action) → `_start_elevation_painting(false)` →
  `ElevationTool.set_mode(false)` (LOWERING) + one paint at the nearest
  vertex; right press is intercepted before the cancel action and starts
  `RAISING`. Mouse motion while a button is held paints as the cursor crosses
  new vertices; releasing the button ends the stroke (the tool stays
  selected). Esc still cancels the tool.

## Tuning levers

| Setting | Location | Value | Effect |
| --- | --- | --- | --- |
| Elevation range | `TerrainGrid.MIN_ELEVATION / MAX_ELEVATION` | -5 / +5 | Height limits every tool clamps to |
| Flat sizes | `ElevationTool.FLAT_BRUSH_SIZES` | 1..9 | S×S squares the Flat tool offers |
| Gradual sizes | `ElevationTool.GRADUAL_BRUSH_SIZES` | 2..9 | S×S squares the Gradual tool offers |
| Step size | both `paint_*` paths | 1 | Elevation change per click |
| Round-clip radius | `square_offsets` | `(S-1)/2 + 0.5` | How much the round shape keeps of the square's corners |
| Gradient slope | Gradual cone clamp | 1 per vertex | Max elevation difference per vertex away from the middle |
| Hotkeys | `TerrainToolbar._input` | V / + / - | Vertex / Flat Square / Gradual Square |

Unit tests: `tests/unit/test_elevation_tools.gd` (tool state, area geometry,
all three painters, limits, editability, undo). Integration harness:
`tests/harness/elevation_tools_harness.tscn` (toolbar → input → paint → undo
through the real main scene).
