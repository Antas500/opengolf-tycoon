extends RefCounted
class_name OverlayGeometry
## OverlayGeometry - Shared helpers for overlays that draw per-tile shapes.

static func tile_polygon(grid: TerrainGrid, node: CanvasItem, pos: Vector2i) -> PackedVector2Array:
	var poly := grid.tile_polygon(pos)
	for i in range(poly.size()):
		poly[i] = node.to_local(poly[i])
	return poly

static func tile_polyline(grid: TerrainGrid, node: CanvasItem, pos: Vector2i) -> PackedVector2Array:
	var poly := tile_polygon(grid, node, pos)
	poly.append(poly[0])
	return poly

static func tile_center(grid: TerrainGrid, node: CanvasItem, pos: Vector2i) -> Vector2:
	return node.to_local(grid.grid_to_screen_center(pos))

static func point_in_tile(grid: TerrainGrid, node: CanvasItem, pos: Vector2i,
		t: Vector2) -> Vector2:
	return node.to_local(grid.grid_point_to_screen(Vector2(pos) + t))

static func offset_in_tile(grid: TerrainGrid, node: CanvasItem, pos: Vector2i,
		pixel_offset: Vector2) -> Vector2:
	var tile := Vector2(float(grid.tile_width), float(grid.tile_height))
	var t := Vector2(0.5, 0.5)
	if tile.x > 0.0:
		t.x += pixel_offset.x / tile.x
	if tile.y > 0.0:
		t.y += pixel_offset.y / tile.y
	return point_in_tile(grid, node, pos, t)
