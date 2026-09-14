extends RefCounted
class_name SculptedTerrain
## Rounded, editable landforms sculpted into the vertex height field.

static func delta_for(offset: Vector2i, radius: int, amount: int) -> int:
	if radius < 1:
		return 0
	var distance: float = Vector2(offset).length() / float(radius)
	var falloff: float = pow(maxf(0.0, 1.0 - distance * distance), 2.0)
	return roundi(float(amount) * falloff)

static func sculpt_radius(brush_size: int) -> int:
	return maxi(3, brush_size / 2)

static func affected_vertices(grid: TerrainGrid, center_vertex: Vector2i, radius: int,
		amount: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not grid or radius < 1:
		return result
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var offset := Vector2i(x, y)
			if delta_for(offset, radius, amount) == 0:
				continue
			var vertex: Vector2i = center_vertex + offset
			if grid.is_valid_vertex(vertex):
				result.append(vertex)
	return result

static func stamp(grid: TerrainGrid, center_vertex: Vector2i, radius: int, amount: int,
		entities: EntityLayer = null) -> Array:
	var changes: Array = []
	if not grid or radius < 1:
		return changes
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var vertex := center_vertex + Vector2i(x, y)
			if not grid.is_valid_vertex(vertex):
				continue
			if not grid.is_vertex_editable(vertex, entities, true):
				continue
			var delta := delta_for(Vector2i(x, y), radius, amount)
			if delta == 0:
				continue
			var old := grid.get_vertex_elevation(vertex)
			var height := clampi(old + delta, grid.MIN_ELEVATION, grid.MAX_ELEVATION)
			if height != old:
				grid.set_vertex_elevation(vertex, height)
				changes.append({"position": vertex, "old_elevation": old, "new_elevation": height})
	return changes

static func stamp_at_tile(grid: TerrainGrid, center_tile: Vector2i, radius: int, amount: int,
		entities: EntityLayer = null) -> Array:
	if not grid:
		return []
	return stamp(grid, tile_to_vertex(grid, center_tile), radius, amount, entities)

static func tile_to_vertex(grid: TerrainGrid, tile: Vector2i) -> Vector2i:
	return grid.nearest_vertex(Vector2(tile) + Vector2(0.5, 0.5))
