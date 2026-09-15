extends Node
class_name ElevationTool
## ElevationTool - Raises/lowers the grid vertices under the cursor.

enum ElevationMode {
	NONE,
	RAISING,
	LOWERING
}

const SCULPT_AMOUNT: int = 3

var elevation_mode: ElevationMode = ElevationMode.NONE
var is_painting: bool = false
var sculpted := false

signal elevation_mode_changed(mode: ElevationMode)

func start_raising() -> void:
	sculpted = false
	elevation_mode = ElevationMode.RAISING
	elevation_mode_changed.emit(elevation_mode)

func start_lowering() -> void:
	sculpted = false
	elevation_mode = ElevationMode.LOWERING
	elevation_mode_changed.emit(elevation_mode)

func cancel() -> void:
	elevation_mode = ElevationMode.NONE
	is_painting = false
	elevation_mode_changed.emit(elevation_mode)

func is_active() -> bool:
	return elevation_mode != ElevationMode.NONE

## Vertex radius covered by a brush whose tile diameter is `brush_size`.
static func brush_radius(brush_size: int) -> int:
	return maxi(1, int(ceil(float(maxi(1, brush_size)) * 0.5)))

static func brush_vertices(terrain_grid: TerrainGrid, center: Vector2i, brush_size: int,
		sculpted_brush: bool = false) -> Array[Vector2i]:
	if sculpted_brush:
		return SculptedTerrain.affected_vertices(terrain_grid, center,
				SculptedTerrain.sculpt_radius(brush_size), SCULPT_AMOUNT)

	var radius: int = brush_radius(brush_size)
	var limit: float = float(radius) + 0.25
	var vertices: Array[Vector2i] = []
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			if Vector2(x, y).length() > limit:
				continue
			var vertex: Vector2i = center + Vector2i(x, y)
			if terrain_grid.is_valid_vertex(vertex):
				vertices.append(vertex)
	return vertices

## Paint at a tile-space point (integers are vertices, `+0.5` are tile centres).
func paint_at_point(grid_point: Vector2, terrain_grid: TerrainGrid, brush_size: int = 1,
		entity_layer: EntityLayer = null) -> Array:
	if elevation_mode == ElevationMode.NONE or terrain_grid == null:
		return []
	return paint_vertices(terrain_grid.nearest_vertex(grid_point), terrain_grid, brush_size, entity_layer)

func paint_elevation(grid_pos: Vector2i, terrain_grid: TerrainGrid, brush_size: int = 1,
		entity_layer: EntityLayer = null) -> Array:
	if elevation_mode == ElevationMode.NONE or terrain_grid == null:
		return []
	if not terrain_grid.is_valid_position(grid_pos):
		return []
	return paint_at_point(Vector2(grid_pos) + Vector2(0.5, 0.5), terrain_grid, brush_size, entity_layer)

## Paint around an explicit vertex.
func paint_vertices(center: Vector2i, terrain_grid: TerrainGrid, brush_size: int = 1,
		entity_layer: EntityLayer = null) -> Array:
	if elevation_mode == ElevationMode.NONE or terrain_grid == null:
		return []
	if not terrain_grid.is_valid_vertex(center):
		return []

	if sculpted:
		return SculptedTerrain.stamp(terrain_grid, center,
				SculptedTerrain.sculpt_radius(brush_size),
				SCULPT_AMOUNT if elevation_mode == ElevationMode.RAISING else -SCULPT_AMOUNT,
				entity_layer)

	var change_amount: int = 1 if elevation_mode == ElevationMode.RAISING else -1
	var changes: Array = []

	for vertex in brush_vertices(terrain_grid, center, brush_size, false):
		# Buildings pin the ground under them; unowned land cannot be reshaped.
		if not terrain_grid.is_vertex_editable(vertex, entity_layer, false):
			continue
		var old_elevation: int = terrain_grid.get_vertex_elevation(vertex)
		var new_elevation: int = terrain_grid.adjust_vertex_elevation(vertex, change_amount)
		if new_elevation != old_elevation:
			changes.append({
				"position": vertex,
				"old_elevation": old_elevation,
				"new_elevation": new_elevation
			})

	return changes
