extends Node
class_name ElevationTool
## ElevationTool - Precise vertex-level terrain editing.
##
## Two selector tools replace the old raise/lower/hill/hollow brushes. Both use
## Left-click to lower (-1) and Right-click to raise (+1), and each click only
## touches the selected vertex or square — never the surrounding terrain:
## - VERTEX: adjusts the single grid vertex under the cursor.
## - SQUARE: first levels the hovered square by moving its lowest vertices up
##   (when raising) or its highest vertices down (when lowering); once all four
##   corners are even, the whole square moves together.
## Because edits are exact, players can stack neighbouring vertices into cliffs:
## any height step of TerrainGrid.CLIFF_STEP or more across a tile reads as a
## vertical cliff face in the renderer, the overlays, and the slope helpers.

enum ToolKind {
	NONE,
	VERTEX,
	SQUARE,
}

var tool_kind: ToolKind = ToolKind.NONE

signal elevation_tool_changed(kind: ToolKind)

func start_vertex_selector() -> void:
	tool_kind = ToolKind.VERTEX
	elevation_tool_changed.emit(tool_kind)

func start_square_selector() -> void:
	tool_kind = ToolKind.SQUARE
	elevation_tool_changed.emit(tool_kind)

func cancel() -> void:
	tool_kind = ToolKind.NONE
	elevation_tool_changed.emit(tool_kind)

func is_active() -> bool:
	return tool_kind != ToolKind.NONE

## Paint at a tile-space point (integers are vertices, `+0.5` are tile centres).
## `raising` is true for Right-click (+1) and false for Left-click (-1).
func paint_at_point(grid_point: Vector2, terrain_grid: TerrainGrid, raising: bool,
		entity_layer: EntityLayer = null) -> Array:
	if tool_kind == ToolKind.NONE or terrain_grid == null:
		return []
	match tool_kind:
		ToolKind.VERTEX:
			return paint_vertex(terrain_grid.nearest_vertex(grid_point), terrain_grid,
					raising, entity_layer)
		ToolKind.SQUARE:
			return paint_square(Vector2i(floori(grid_point.x), floori(grid_point.y)),
					terrain_grid, raising, entity_layer)
	return []

## Adjust a single vertex by one step. Only this vertex is ever touched.
func paint_vertex(vertex: Vector2i, terrain_grid: TerrainGrid, raising: bool,
		entity_layer: EntityLayer = null) -> Array:
	if tool_kind != ToolKind.VERTEX or terrain_grid == null:
		return []
	if not terrain_grid.is_valid_vertex(vertex):
		return []
	# Buildings pin the ground under them; unowned land cannot be reshaped.
	if not terrain_grid.is_vertex_editable(vertex, entity_layer, false):
		return []
	var delta: int = 1 if raising else -1
	var old_elevation: int = terrain_grid.get_vertex_elevation(vertex)
	var new_elevation: int = terrain_grid.adjust_vertex_elevation(vertex, delta)
	if new_elevation == old_elevation:
		return []
	return [{
		"position": vertex,
		"old_elevation": old_elevation,
		"new_elevation": new_elevation,
	}]

## Level-then-lift a square: raising moves its lowest corner(s) up, lowering
## moves its highest corner(s) down. When all four corners are even this moves
## the whole square. Pinned (building/unowned) corners still count toward the
## level target but are never moved themselves.
func paint_square(tile: Vector2i, terrain_grid: TerrainGrid, raising: bool,
		entity_layer: EntityLayer = null) -> Array:
	if tool_kind != ToolKind.SQUARE or terrain_grid == null:
		return []
	if not terrain_grid.is_valid_position(tile):
		return []
	var targets: Array[Vector2i] = square_targets(tile, terrain_grid, raising)
	if targets.is_empty():
		return []
	var delta: int = 1 if raising else -1
	var changes: Array = []
	for vertex in targets:
		if not terrain_grid.is_vertex_editable(vertex, entity_layer, false):
			continue
		var old_elevation: int = terrain_grid.get_vertex_elevation(vertex)
		var new_elevation: int = terrain_grid.adjust_vertex_elevation(vertex, delta)
		if new_elevation != old_elevation:
			changes.append({
				"position": vertex,
				"old_elevation": old_elevation,
				"new_elevation": new_elevation,
			})
	return changes

## Corners of `tile` that a paint step would move (before editability checks).
## Raising targets the lowest corner(s); lowering targets the highest.
static func square_targets(tile: Vector2i, terrain_grid: TerrainGrid,
		raising: bool) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	if terrain_grid == null or not terrain_grid.is_valid_position(tile):
		return targets
	var corners: Array[Vector2i] = terrain_grid.vertices_of_tile(tile)
	var heights: Array[int] = []
	for corner in corners:
		heights.append(terrain_grid.get_vertex_elevation(corner))
	var wanted: int = heights.min() if raising else heights.max()
	for i in corners.size():
		if heights[i] == wanted:
			targets.append(corners[i])
	return targets
