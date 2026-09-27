# Elevation Selector Tools

## Plain English

Terrain elevation is sculpted with three selector tools on the Elevation tab,
which replace the old Rolling Hill, Hollow, Raise and Lower tools:

- **Vertex Selector** (`V`) — raises or lowers a single grid vertex by one
  step.
- **Flat Square Selector** (`+`) — takes the brush's vertices, evens them (the
  lowest are raised up to the highest, or the highest are lowered down to the
  lowest), then raises or lowers the whole brush one step. The brush moves as
  one flat slab.
- **Gradual Square Selector** (`-`) — raises or lowers the middle vertex (even
  sizes) or the four corners of the middle tile (odd sizes), then moves the
  nearby vertices inside the brush whenever they would end up more than one
  elevation away per vertex of distance from the changed middle. Repeated
  clicks build a one-step-per-tile pyramid or basin — the terrain stays
  gradual.

While a selector is active, **right clicking raises** the selected terrain and
**left clicking lowers** it. A button press starts a stroke, dragging paints,
and releasing the button ends the stroke. No vertex outside the selection is
ever touched, and vertices under buildings or on unowned land are skipped.
Esc still cancels the tool (right click no longer does).

The two Square Selector tools share one **Elevation Brush Size** and
**Elevation Brush Shape** (square or round) control pair, kept separate from the
Terrain Brush controls on the Course Terrain tab. Both Flat and Gradual offer
1×1 through 9×9, and switching between them keeps the same size and shape. The
controls stay usable even when neither Square tool is selected.

Both controls ride in the notch between the two Square tiles on the Elevation
tab rather than in a group of their own beside the row: the size stepper
(smaller, the size it paints with, bigger) fills the V above the point where
Flat Square and Gradual Square meet, and the shape toggle fills the V below it.
Each is a half-size selector diamond, drawn the same way the Open Hole action is
drawn on the Course Terrain tab, so the brush sits exactly where the two tools
it belongs to meet.

**Elevation Brush sizes are counted in tiles**, not vertices: a brush reshapes
the tiles it covers by moving their corner vertices, so it always holds one
more vertex than tile per side.

| Brush size | Square shape        | Round (circle) shape |
| ---------- | ------------------- | -------------------- |
| 1×1        | 1 tile, 4 vertices  | 1 tile, 4 vertices   |
| 2×2        | 4 tiles, 9 vertices | 4 tiles, 9 vertices  |
| 3×3        | 9 tiles, 16 vertices | 5 tiles, 12 vertices |
| 4×4        | 16 tiles, 25 vertices | 12 tiles, 21 vertices |
| 5×5        | 25 tiles, 36 vertices | 13 tiles, 24 vertices |
| S×S        | S² tiles, (S+1)² vertices | tiles whose centre lies within S/2 of the middle |

The hover preview tints exactly those tiles and marks exactly those vertices,
so what the player sees under the cursor is what a click reshapes.

Elevation levels are integers from `MIN_ELEVATION` (-5) to `MAX_ELEVATION`
(+5) on the `(grid_width + 1) × (grid_height + 1)` vertex field owned by
`TerrainGrid`.

## Algorithm

### Brush area geometry (`ElevationTool.tile_offsets`)

A brush of size S is anchored on the tile under the cursor (`anchor_tile()`,
the floor of the tile-space point), so the hover preview sits on the tile the
player is pointing at. Its tiles run from `-(S/2)` to `S-1-(S/2)` per axis:
odd sizes centre on the anchor tile, even sizes centre on the vertex at the
anchor tile's near corner. Either way the brush covers S tiles per side, whose
corners are the `(S+1)²` vertices it edits.

With the round shape, a tile is kept when its centre lies inside a circle of
radius `S/2` (integer division) around the middle of the block — the corners
of the square are clipped away:

```gdscript
static func tile_offsets(size: int, square_shape: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var from: int = -(size / 2)
	var to: int = size - 1 + from
	var middle: float = float(from + to + 1) * 0.5   # block centre, tile centres are +0.5
	var limit: float = float(size / 2)
	for x in range(from, to + 1):
		for y in range(from, to + 1):
			if not square_shape:
				var dx: float = float(x) + 0.5 - middle
				var dy: float = float(y) + 0.5 - middle
				if dx * dx + dy * dy > limit * limit:
					continue
			result.append(Vector2i(x, y))
	return result
```

`vertex_offsets()` collects the corners of those tiles (deduplicated), and
`brush_tiles()` / `brush_vertices()` map the offsets onto the grid and drop
everything off it. Because the vertices are derived from the tiles, the
preview's tint and the vertices a click moves can never disagree.

`middle_vertices()` returns `[anchor]` for even sizes and the four corners of
the anchor tile for odd sizes — the block the Gradual tool moves first.
`distance_to_middle()` is the Chebyshev distance from a vertex to that middle
vertex or middle 2×2 block — one per vertex of travel.

### Vertex Selector

```
new_elevation = clamp(old + (1 if raising else -1), MIN, MAX)
```

### Flat Square Selector

Let the selected (editable, on-grid) vertices of the brush be `A`, with
`lowest = min A`, `highest = max A`. Every vertex in `A` is set to one
target — "even the brush, then shift it" in a single step:

```
target = clamp(highest + 1, MIN, MAX)   # raising  (right click)
target = clamp(lowest  - 1, MIN, MAX)   # lowering (left click)
```

Raising the `{0, 0, 2, 2}` brush sends every vertex to 3; lowering it sends
every vertex to -1. An already-even brush simply steps up or down. When the
brush sits at +5 (raising) or -5 (lowering) the target equals the current
heights and nothing changes.

### Gradual Square Selector

1. **Move the middle as one unit.** Level the middle vertex / middle 2×2
   block, then shift it one step:
   ```
   level  = max middle  (raising)   /  min middle  (lowering)
   middle_target = clamp(level + (1 if raising else -1), MIN, MAX)
   ```
   If no middle vertex changed (already even and at its limit) the stroke is a
   no-op.
2. **Keep the brush gradual.** Every other selected vertex `v` is clamped into
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
  `ElevationTool.set_mode(false)` (LOWERING) + one paint; right press is
  intercepted before the cancel action and starts `RAISING`. Mouse motion
  while a button is held paints as the cursor crosses new anchors; releasing
  the button ends the stroke (the tool stays selected). Esc still cancels the
  tool.
- `ElevationTool.anchor_for_tool()` picks the anchor for a cursor point: the
  Vertex Selector snaps to the nearest vertex, while the Square Selectors
  anchor on the tile the point falls in (`anchor_tile()`, its floor). Dragging
  therefore repaints once per tile the cursor enters.

## Tuning levers

| Setting | Location | Value | Effect |
| --- | --- | --- | --- |
| Elevation range | `TerrainGrid.MIN_ELEVATION / MAX_ELEVATION` | -5 / +5 | Height limits every tool clamps to |
| Brush sizes | `ElevationTool.BRUSH_SIZES` | 1..9 | S×S tile brushes Flat and Gradual share |
| Step size | both `paint_*` paths | 1 | Elevation change per click |
| Round-clip radius | `tile_offsets` | `S/2` tiles | How much the round shape keeps of the square's corners |
| Gradient slope | Gradual cone clamp | 1 per vertex | Max elevation difference per vertex away from the middle |
| Hotkeys | `TerrainToolbar._input` | V / + / - | Vertex / Flat Square / Gradual Square |

Unit tests: `tests/unit/test_elevation_tools.gd` (tool state, brush geometry,
all three painters, limits, editability, undo) and
`tests/unit/test_elevation_preview.gd` (the tiles and vertices the hover
preview shows). Integration harness:
`tests/harness/elevation_tools_harness.tscn` (toolbar → input → paint → undo
through the real main scene).
