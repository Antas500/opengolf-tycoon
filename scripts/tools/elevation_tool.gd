extends Node
class_name ElevationTool
## ElevationTool - terrain elevation is sculpted with three selector tools.
##
## While a selector is active, **right clicking raises** the selected terrain
## and **left clicking lowers** it; vertices outside the selection are never
## touched. Buildings pin the ground under them and unowned land cannot be
## reshaped.
##
##  - **Vertex Selector**: raises or lowers a single vertex by one step.
##  - **Flat Square Selector**: raises only the brush's lowest vertices or
##    lowers only its highest ones - the vertices sitting at the extreme of
##    the selection - and each by one elevation level. The rest stay put, so
##    uneven ground levels itself one stroke at a time; on even ground every
##    vertex is at that extreme, so the whole slab steps together.
##  - **Gradual Square Selector**: raises or lowers the middle vertex (even
##    sizes) or the middle 2x2 square of vertices (odd sizes) inside the
##    brush, and moves the nearby vertices inside the brush whenever they
##    would come to differ by more than one elevation per vertex of
##    distance from the changing vertex - the terrain stays gradual.
##
## The two Square Selector tools share one Elevation Brush Size and
## Elevation Brush Shape (square or round), which are separate from the
## terrain paint brush controls. The toolbar owns those shared values and
## pushes them here through set_brush().
##
## Brush sizes are counted in **tiles**, not vertices: the brush reshapes the
## tiles it covers by moving their corner vertices.
##
##  Square shape: 1x1 = 1 tile = 4 vertices, 2x2 = 4 tiles = 9 vertices,
##                3x3 = 9 tiles = 16 vertices, 4x4 = 16 tiles = 25 vertices...
##  Round shape:  1x1 = 1 tile = 4 vertices, 2x2 = 4 tiles = 9 vertices,
##                3x3 = 5 tiles = 12 vertices, 4x4 = 12 tiles = 21 vertices,
##                5x5 = 13 tiles = 24 vertices...
##
## The round shape drops the tiles whose centre falls outside a circle of
## radius S/2 around the middle of the block, so the corners of the square are
## clipped away. The vertices a brush moves are the corners of the tiles it
## keeps, so the hover preview and the selection always agree.

enum Tool { NONE, VERTEX, FLAT, GRADUAL }

enum ElevationMode { NONE, RAISING, LOWERING }

const TOOL_VERTEX := "vertex"
const TOOL_FLAT := "flat"
const TOOL_GRADUAL := "gradual"

## Elevation Brush Sizes shared by the Square Selector tools, in tiles
## (S x S tiles = (S+1)^2 vertices). Flat and Gradual both offer 1x1 through 9x9.
const BRUSH_SIZES: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9]

signal tool_changed(tool: Tool)
signal elevation_mode_changed(mode: ElevationMode)

## The currently selected elevation selector tool.
var tool: Tool = Tool.NONE
## Transient: which mouse button is driving the current stroke. Right click
## raises, left click lowers. NONE while no button is held.
var elevation_mode: ElevationMode = ElevationMode.NONE
var is_painting: bool = false

## Elevation brush of the active Square Selector tool (size in tiles,
## square vs round area). Set by the toolbar when a tool is selected or its
## brush controls change.
var brush_size: int = 3
var brush_square: bool = true


func select_tool(new_tool: Tool) -> void:
	if tool == new_tool:
		return
	tool = new_tool
	elevation_mode = ElevationMode.NONE
	is_painting = false
	tool_changed.emit(tool)

func set_mode(raising: bool) -> void:
	if tool == Tool.NONE:
		return
	elevation_mode = ElevationMode.RAISING if raising else ElevationMode.LOWERING
	elevation_mode_changed.emit(elevation_mode)

## End the current stroke (mouse button released); the tool stays selected.
func stop_stroke() -> void:
	if elevation_mode == ElevationMode.NONE:
		return
	elevation_mode = ElevationMode.NONE
	is_painting = false
	elevation_mode_changed.emit(elevation_mode)

## Fully cancel: deselect the tool (second Esc, or another tool took over).
func cancel() -> void:
	if tool == Tool.NONE and elevation_mode == ElevationMode.NONE:
		return
	tool = Tool.NONE
	elevation_mode = ElevationMode.NONE
	is_painting = false
	tool_changed.emit(tool)
	elevation_mode_changed.emit(elevation_mode)

## True while a selector tool is selected (before or during a stroke).
func is_active() -> bool:
	return tool != Tool.NONE

func is_raising() -> bool:
	return elevation_mode == ElevationMode.RAISING

func is_lowering() -> bool:
	return elevation_mode == ElevationMode.LOWERING

func brush_sizes() -> Array[int]:
	match tool:
		Tool.FLAT, Tool.GRADUAL:
			return BRUSH_SIZES
	return []

func set_brush(size: int, square: bool) -> void:
	brush_size = size
	brush_square = square

func set_brush_size(value: int) -> void:
	if value in BRUSH_SIZES:
		brush_size = value

func set_brush_square(square: bool) -> void:
	brush_square = square

# =============================================================================
# Brush geometry (testable without a scene tree)
# =============================================================================

## The tile a tile-space point falls inside - the Square Selectors anchor
## their brush on it, so the brush covers the tile under the cursor.
static func anchor_tile(grid_point: Vector2) -> Vector2i:
	return Vector2i(floori(grid_point.x), floori(grid_point.y))

## Where a brush sits for a cursor point: the Vertex Selector edits the
## nearest vertex, while the Square Selectors centre their tiles on the tile
## the point falls in.
static func anchor_for_tool(grid_point: Vector2, terrain_grid: TerrainGrid,
		brush_tool: Tool) -> Vector2i:
	if brush_tool == Tool.VERTEX:
		return terrain_grid.nearest_vertex(grid_point)
	return anchor_tile(grid_point)

## Tile offsets of an S x S tile brush. Odd sizes centre on the anchor tile;
## even sizes centre on the vertex at the anchor tile's near corner, so they
## cover S tiles per side either way. The round shape keeps only the tiles
## whose centre lies within a circle of radius S/2 around the middle of the
## block, which clips the corners of the square away. Shared with the terrain
## paint brush (`TerrainBrush.offsets`).
static func tile_offsets(size: int, square_shape: bool) -> Array[Vector2i]:
	return TerrainBrush.offsets(size, not square_shape)

## The vertices a brush moves: the corners of the tiles it covers. An S x S
## tile brush therefore holds (S+1) x (S+1) vertices - 1x1 = 4, 2x2 = 9,
## 3x3 = 16, 4x4 = 25 - and a round brush only the corners of the tiles it
## keeps.
static func vertex_offsets(size: int, square_shape: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var seen := {}
	for tile in tile_offsets(size, square_shape):
		for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var offset: Vector2i = tile + corner
			if seen.has(offset):
				continue
			seen[offset] = true
			result.append(offset)
	return result

## The S x S block of tiles (or its round clipping) anchored on `anchor`,
## clipped to the grid. This is what the hover preview tints.
static func brush_tiles(terrain_grid: TerrainGrid, anchor: Vector2i, size: int,
		square_shape: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if terrain_grid == null:
		return result
	for offset in tile_offsets(size, square_shape):
		var tile: Vector2i = anchor + offset
		if terrain_grid.is_valid_position(tile):
			result.append(tile)
	return result

## The vertices the brush moves: every corner of its tiles, deduplicated and
## clipped to the grid.
static func brush_vertices(terrain_grid: TerrainGrid, anchor: Vector2i, size: int,
		square_shape: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if terrain_grid == null:
		return result
	var seen := {}
	for tile in brush_tiles(terrain_grid, anchor, size, square_shape):
		for vertex in terrain_grid.vertices_of_tile(tile):
			if terrain_grid.is_valid_vertex(vertex) and not seen.has(vertex):
				seen[vertex] = true
				result.append(vertex)
	return result

## The middle vertex (even sizes) or the middle 2x2 square of vertices (odd
## sizes) of the brush anchored on `anchor` - what the Gradual tool moves
## first. Even sizes centre the brush on a vertex; odd sizes centre it on the
## anchor tile, whose four corners are the middle block.
static func middle_vertices(size: int, anchor: Vector2i) -> Array[Vector2i]:
	if size % 2 == 0:
		return [anchor]
	var middle: Array[Vector2i] = []
	for offset in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
		middle.append(anchor + offset)
	return middle

## Chebyshev distance from `vertex` to the middle vertex (even sizes) or the
## middle 2x2 square of vertices (odd sizes) of the brush anchored on
## `anchor`. One per vertex of travel, so a gradual surface may differ from
## the middle by at most `d` elevations.
static func distance_to_middle(vertex: Vector2i, size: int, anchor: Vector2i) -> int:
	if size % 2 == 0:
		return maxi(absi(vertex.x - anchor.x), absi(vertex.y - anchor.y))
	var dx: int = 0
	if vertex.x < anchor.x:
		dx = anchor.x - vertex.x
	elif vertex.x > anchor.x + 1:
		dx = vertex.x - anchor.x - 1
	var dy: int = 0
	if vertex.y < anchor.y:
		dy = anchor.y - vertex.y
	elif vertex.y > anchor.y + 1:
		dy = vertex.y - anchor.y - 1
	return maxi(dx, dy)

# =============================================================================
# Painting
# =============================================================================

## Paint at a tile-space point (integers are vertices, `+0.5` are tile
## centres). The Vertex Selector snaps to the nearest vertex; the Square
## Selectors anchor their tiles on the tile the point falls in.
func paint_at_point(grid_point: Vector2, terrain_grid: TerrainGrid,
		entity_layer: EntityLayer = null) -> Array:
	if not _can_paint(terrain_grid):
		return []
	var anchor: Vector2i = anchor_for_tool(grid_point, terrain_grid, tool)
	if tool == Tool.VERTEX:
		return paint_at_vertex(anchor, terrain_grid, entity_layer)
	return paint_at_tile(anchor, terrain_grid, entity_layer)

## Paint centred on a tile: the Square Selectors' brush is anchored on it.
func paint_elevation(grid_pos: Vector2i, terrain_grid: TerrainGrid,
		entity_layer: EntityLayer = null) -> Array:
	if tool == Tool.VERTEX:
		return paint_at_vertex(grid_pos, terrain_grid, entity_layer)
	return paint_at_tile(grid_pos, terrain_grid, entity_layer)

## Paint with the brush anchored on the tile `anchor`. Right click raises,
## left click lowers; vertices outside the selection are never touched.
func paint_at_tile(anchor: Vector2i, terrain_grid: TerrainGrid,
		entity_layer: EntityLayer = null) -> Array:
	if not _can_paint(terrain_grid):
		return []
	if not terrain_grid.is_valid_position(anchor):
		return []
	var raising: bool = is_raising()
	match tool:
		Tool.VERTEX:
			return _paint_vertex(anchor, terrain_grid, raising, entity_layer)
		Tool.FLAT:
			return _paint_flat(anchor, terrain_grid, raising, entity_layer)
		Tool.GRADUAL:
			return _paint_gradual(anchor, terrain_grid, raising, entity_layer)
	return []

## Paint the Vertex Selector, whose whole selection is one vertex.
func paint_at_vertex(vertex: Vector2i, terrain_grid: TerrainGrid,
		entity_layer: EntityLayer = null) -> Array:
	if not _can_paint(terrain_grid):
		return []
	if not terrain_grid.is_valid_vertex(vertex):
		return []
	return _paint_vertex(vertex, terrain_grid, is_raising(), entity_layer)

func _can_paint(terrain_grid: TerrainGrid) -> bool:
	return tool != Tool.NONE and elevation_mode != ElevationMode.NONE and terrain_grid != null

func _is_vertex_selected(vertex: Vector2i, terrain_grid: TerrainGrid,
		entity_layer: EntityLayer) -> bool:
	# Buildings pin the ground under them; unowned land cannot be reshaped.
	return terrain_grid.is_vertex_editable(vertex, entity_layer, false)

func _change_vertex(vertex: Vector2i, target: int, terrain_grid: TerrainGrid,
		changes: Array) -> void:
	var old_elevation: int = terrain_grid.get_vertex_elevation(vertex)
	var new_elevation: int = clampi(target, terrain_grid.MIN_ELEVATION, terrain_grid.MAX_ELEVATION)
	if new_elevation == old_elevation:
		return
	terrain_grid.set_vertex_elevation(vertex, new_elevation)
	changes.append({
		"position": vertex,
		"old_elevation": old_elevation,
		"new_elevation": new_elevation
	})

## Vertex Selector: one vertex, one step.
func _paint_vertex(center: Vector2i, terrain_grid: TerrainGrid, raising: bool,
		entity_layer: EntityLayer) -> Array:
	var changes: Array = []
	if not _is_vertex_selected(center, terrain_grid, entity_layer):
		return changes
	var delta: int = 1 if raising else -1
	_change_vertex(center, terrain_grid.get_vertex_elevation(center) + delta, terrain_grid, changes)
	return changes

## Flat Square Selector: one stroke nudges only the vertices at the extreme of
## the selection, and each by a single level - raising lifts just the brush's
## lowest vertices, lowering trims just its highest ones. Every other vertex
## keeps its height, so uneven ground levels itself one stroke at a time. On
## even ground every vertex is both lowest and highest, so the whole brush
## steps up or down together as one flat slab.
func _paint_flat(anchor: Vector2i, terrain_grid: TerrainGrid, raising: bool,
		entity_layer: EntityLayer) -> Array:
	var changes: Array = []
	var area: Array[Vector2i] = []
	var lowest: int = terrain_grid.MAX_ELEVATION
	var highest: int = terrain_grid.MIN_ELEVATION
	for vertex in brush_vertices(terrain_grid, anchor, brush_size, brush_square):
		if not _is_vertex_selected(vertex, terrain_grid, entity_layer):
			continue
		area.append(vertex)
		var height: int = terrain_grid.get_vertex_elevation(vertex)
		lowest = mini(lowest, height)
		highest = maxi(highest, height)
	if area.is_empty():
		return changes
	# Only the vertices on the relevant edge of the selection move, one level
	# per stroke: the lowest ones when raising, the highest ones when lowering.
	var edge: int = lowest if raising else highest
	for vertex in area:
		if terrain_grid.get_vertex_elevation(vertex) != edge:
			continue
		_change_vertex(vertex, edge + (1 if raising else -1), terrain_grid, changes)
	return changes

## Gradual Square Selector: move the middle vertex or middle 2x2 square one
## step, then clamp every other vertex of the brush so it cannot differ from
## the new middle height by more than one elevation per vertex of distance.
## Nearby vertices are only moved while that gradient constraint would be
## broken; the rest of the brush keeps its shape.
func _paint_gradual(anchor: Vector2i, terrain_grid: TerrainGrid, raising: bool,
		entity_layer: EntityLayer) -> Array:
	var changes: Array = []
	var area: Array[Vector2i] = []
	for vertex in brush_vertices(terrain_grid, anchor, brush_size, brush_square):
		if _is_vertex_selected(vertex, terrain_grid, entity_layer):
			area.append(vertex)
	if area.is_empty():
		return changes

	var shift: int = 1 if raising else -1
	var middle: Array[Vector2i] = []
	for vertex in middle_vertices(brush_size, anchor):
		if area.has(vertex):
			middle.append(vertex)
	if middle.is_empty():
		return changes

	# The middle moves as one unit: level it, then shift it one step.
	var level: int = terrain_grid.MIN_ELEVATION if raising else terrain_grid.MAX_ELEVATION
	for vertex in middle:
		var height: int = terrain_grid.get_vertex_elevation(vertex)
		level = maxi(level, height) if raising else mini(level, height)
	var middle_target: int = clampi(level + shift, terrain_grid.MIN_ELEVATION,
			terrain_grid.MAX_ELEVATION)
	var middle_moved := false
	for vertex in middle:
		var old_elevation: int = terrain_grid.get_vertex_elevation(vertex)
		if middle_target != old_elevation:
			middle_moved = true
			_change_vertex(vertex, middle_target, terrain_grid, changes)
	if not middle_moved:
		# The middle is already at its limit and even - nothing to propagate.
		return changes

	# Keep the area gradual around the new middle height.
	for vertex in area:
		if middle.has(vertex):
			continue
		var distance: int = distance_to_middle(vertex, brush_size, anchor)
		var old_height: int = terrain_grid.get_vertex_elevation(vertex)
		var target: int = clampi(old_height,
				middle_target - distance, middle_target + distance)
		if target != old_height:
			_change_vertex(vertex, target, terrain_grid, changes)
	return changes
