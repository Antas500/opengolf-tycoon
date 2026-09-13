extends RefCounted
class_name OverlayGeometry
## OverlayGeometry - Shared helpers for overlays that draw per-tile shapes.
##
## Overlays draw in their own local space, but tile shapes live in the
## projection's world space. These helpers bridge the two so an overlay renders
## 2:1 diamonds when the course is isometric and squares when it is top-down,
## without each overlay re-implementing (or forgetting) the conversion.

## Tile outline in `node`'s local space, ready for draw_colored_polygon().
static func tile_polygon(grid: TerrainGrid, node: CanvasItem, pos: Vector2i) -> PackedVector2Array:
	var poly := grid.tile_polygon(pos)
	for i in range(poly.size()):
		poly[i] = node.to_local(poly[i])
	return poly


## Closed tile outline, ready for draw_polyline() (which needs the loop closed).
static func tile_polyline(grid: TerrainGrid, node: CanvasItem, pos: Vector2i) -> PackedVector2Array:
	var poly := tile_polygon(grid, node, pos)
	poly.append(poly[0])
	return poly


## Tile centre in `node`'s local space.
static func tile_center(grid: TerrainGrid, node: CanvasItem, pos: Vector2i) -> Vector2:
	return node.to_local(grid.grid_to_screen_center(pos))


## Map a normalised offset within a tile onto the tile's projected shape.
## `t` runs 0..1 across the tile in grid space, so (0.5, 0.5) is the centre and
## (0, 0) / (1, 1) are opposite corners.
##
## This is what lets overlay art authored against a square tile follow the
## diamond: convert a pixel offset with `pixel / tile_size` and the decoration
## lands in the matching spot on the projected tile.
static func point_in_tile(grid: TerrainGrid, node: CanvasItem, pos: Vector2i,
		t: Vector2) -> Vector2:
	return node.to_local(grid.grid_point_to_screen(Vector2(pos) + t))


## Convert a pixel offset authored against a tile-sized square into the
## equivalent point on the projected tile, measured from the tile centre.
static func offset_in_tile(grid: TerrainGrid, node: CanvasItem, pos: Vector2i,
		pixel_offset: Vector2) -> Vector2:
	var tile := Vector2(float(grid.tile_width), float(grid.tile_height))
	var t := Vector2(0.5, 0.5)
	if tile.x > 0.0:
		t.x += pixel_offset.x / tile.x
	if tile.y > 0.0:
		t.y += pixel_offset.y / tile.y
	return point_in_tile(grid, node, pos, t)
