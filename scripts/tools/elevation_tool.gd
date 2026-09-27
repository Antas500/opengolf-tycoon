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
##  - **Flat Square Selector**: raises or lowers the lowest/highest vertices
##    inside the square area until they are all even, then raises or lowers
##    all of the square's vertices by one step.
##  - **Gradual Square Selector**: raises or lowers the middle vertex (odd
##    sizes) or middle square of vertices (even sizes) inside the square
##    area, and moves the nearby vertices inside the area whenever they
##    would come to differ by more than one elevation per vertex of
##    distance from the changing vertex - the terrain stays gradual.
##
## The two Square Selector tools carry their own Elevation Brush Size and
## Elevation Brush Shape (square or round), which are separate from the
## terrain paint brush controls. The toolbar owns those per-tool values and
## pushes them here through set_brush().

enum Tool { NONE, VERTEX, FLAT, GRADUAL }

enum ElevationMode { NONE, RAISING, LOWERING }

const TOOL_VERTEX := "vertex"
const TOOL_FLAT := "flat"
const TOOL_GRADUAL := "gradual"

## Elevation Brush Sizes per tool (S x S vertices).
const FLAT_BRUSH_SIZES: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
const GRADUAL_BRUSH_SIZES: Array[int] = [2, 3, 4, 5, 6, 7, 8, 9]

signal tool_changed(tool: Tool)
signal elevation_mode_changed(mode: ElevationMode)

## The currently selected elevation selector tool.
var tool: Tool = Tool.NONE
## Transient: which mouse button is driving the current stroke. Right click
## raises, left click lowers. NONE while no button is held.
var elevation_mode: ElevationMode = ElevationMode.NONE
var is_painting: bool = false

## Elevation brush of the active Square Selector tool (size in vertices,
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
		Tool.FLAT:
			return FLAT_BRUSH_SIZES
		Tool.GRADUAL:
			return GRADUAL_BRUSH_SIZES
	return []

func set_brush(size: int, square: bool) -> void:
	brush_size = size
	brush_square = square

func set_brush_size(value: int) -> void:
	if value in brush_sizes():
		brush_size = value

func set_brush_square(square: bool) -> void:
	brush_square = square

# =============================================================================
# Square area geometry (testable without a scene tree)
# =============================================================================

## Offsets of an S x S vertex square centred on the cursor vertex. Even sizes
## centre on the middle 2x2 block of vertices, so the offsets run from
## -(S/2 - 1) to S/2. With a round shape the corners are clipped by a circle.
static func square_offsets(size: int, round_shape: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
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

## The S x S square area (or round clip of it) as absolute vertices, clamped
## to the grid.
static func square_vertices(terrain_grid: TerrainGrid, center: Vector2i, size: int,
		round_shape: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset in square_offsets(size, round_shape):
		var vertex: Vector2i = center + offset
		if terrain_grid.is_valid_vertex(vertex):
			result.append(vertex)
	return result

## The middle vertex (odd size) or middle 2x2 square of vertices (even size)
## of the S x S area centred on `center` - what the Gradual tool moves first.
static func middle_vertices(size: int, center: Vector2i) -> Array[Vector2i]:
	if size % 2 == 1:
		return [center]
	var middle: Array[Vector2i] = []
	for offset in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
		middle.append(center + offset)
	return middle

## Chebyshev distance from `vertex` to the middle vertex or middle 2x2 square
## of the S x S area centred on `center`. One per vertex of travel, so a
## gradual surface may differ from the middle by at most `d` elevations.
static func distance_to_middle(vertex: Vector2i, size: int, center: Vector2i) -> int:
	if size % 2 == 1:
		return maxi(absi(vertex.x - center.x), absi(vertex.y - center.y))
	var dx: int = 0
	if vertex.x < center.x:
		dx = center.x - vertex.x
	elif vertex.x > center.x + 1:
		dx = vertex.x - center.x - 1
	var dy: int = 0
	if vertex.y < center.y:
		dy = center.y - vertex.y
	elif vertex.y > center.y + 1:
		dy = vertex.y - center.y - 1
	return maxi(dx, dy)

# =============================================================================
# Painting
# =============================================================================

## Paint at a tile-space point (integers are vertices, `+0.5` are tile centres).
func paint_at_point(grid_point: Vector2, terrain_grid: TerrainGrid,
		entity_layer: EntityLayer = null) -> Array:
	if not _can_paint(terrain_grid):
		return []
	return paint_vertices(terrain_grid.nearest_vertex(grid_point), terrain_grid, entity_layer)

## Paint centred on a tile: snaps to the tile's near vertex like a click at
## the tile centre.
func paint_elevation(grid_pos: Vector2i, terrain_grid: TerrainGrid,
		entity_layer: EntityLayer = null) -> Array:
	if not _can_paint(terrain_grid):
		return []
	if not terrain_grid.is_valid_position(grid_pos):
		return []
	return paint_at_point(Vector2(grid_pos) + Vector2(0.5, 0.5), terrain_grid, entity_layer)

## Paint the selected tool around an explicit vertex. Right click raises,
## left click lowers; vertices outside the selection are never touched.
func paint_vertices(center: Vector2i, terrain_grid: TerrainGrid,
		entity_layer: EntityLayer = null) -> Array:
	if not _can_paint(terrain_grid):
		return []
	if not terrain_grid.is_valid_vertex(center):
		return []
	var raising: bool = is_raising()
	match tool:
		Tool.VERTEX:
			return _paint_vertex(center, terrain_grid, raising, entity_layer)
		Tool.FLAT:
			return _paint_flat(center, terrain_grid, raising, entity_layer)
		Tool.GRADUAL:
			return _paint_gradual(center, terrain_grid, raising, entity_layer)
	return []

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

## Flat Square Selector: even the square first (the lowest vertices are raised
## up to the highest, or the highest are lowered down to the lowest), then
## shift every vertex of the square one step. The whole area ends one step
## above its previous highest (raising) or one step below its previous
## lowest (lowering).
func _paint_flat(center: Vector2i, terrain_grid: TerrainGrid, raising: bool,
		entity_layer: EntityLayer) -> Array:
	var changes: Array = []
	var area: Array[Vector2i] = []
	var lowest: int = terrain_grid.MAX_ELEVATION
	var highest: int = terrain_grid.MIN_ELEVATION
	for vertex in square_vertices(terrain_grid, center, brush_size, brush_square):
		if not _is_vertex_selected(vertex, terrain_grid, entity_layer):
			continue
		area.append(vertex)
		var height: int = terrain_grid.get_vertex_elevation(vertex)
		lowest = mini(lowest, height)
		highest = maxi(highest, height)
	if area.is_empty():
		return changes
	var shift: int = 1 if raising else -1
	var target: int = clampi((highest if raising else lowest) + shift,
			terrain_grid.MIN_ELEVATION, terrain_grid.MAX_ELEVATION)
	for vertex in area:
		_change_vertex(vertex, target, terrain_grid, changes)
	return changes

## Gradual Square Selector: move the middle vertex or middle 2x2 square one
## step, then clamp every other vertex of the area so it cannot differ from
## the new middle height by more than one elevation per vertex of distance.
## Nearby vertices are only moved while that gradient constraint would be
## broken; the rest of the square keeps its shape.
func _paint_gradual(center: Vector2i, terrain_grid: TerrainGrid, raising: bool,
		entity_layer: EntityLayer) -> Array:
	var changes: Array = []
	var area: Array[Vector2i] = []
	for vertex in square_vertices(terrain_grid, center, brush_size, brush_square):
		if _is_vertex_selected(vertex, terrain_grid, entity_layer):
			area.append(vertex)
	if area.is_empty():
		return changes

	var shift: int = 1 if raising else -1
	var middle: Array[Vector2i] = []
	for vertex in middle_vertices(brush_size, center):
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
		var distance: int = distance_to_middle(vertex, brush_size, center)
		var old_height: int = terrain_grid.get_vertex_elevation(vertex)
		var target: int = clampi(old_height,
				middle_target - distance, middle_target + distance)
		if target != old_height:
			_change_vertex(vertex, target, terrain_grid, changes)
	return changes
