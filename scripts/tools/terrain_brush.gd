extends RefCounted
class_name TerrainBrush
## A continuous sequence of grid stamps, independent of mouse-event frequency.
static func centers(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var span := to - from
	var steps := maxi(absi(span.x), absi(span.y))
	if steps == 0: return [to]
	for i in range(steps + 1):
		var p := Vector2i((Vector2(from).lerp(Vector2(to), float(i) / steps)).round())
		if points.is_empty() or points[-1] != p: points.append(p)
	return points

## Like centers(), but every step moves along one axis only, so consecutive
## stamps always share an edge. Streams need this: a channel only joins
## edge-adjacent stream tiles, so a diagonal stroke would break into pools.
static func centers_4_connected(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	for p in centers(from, to):
		if not points.is_empty():
			var last: Vector2i = points[-1]
			if last.x != p.x and last.y != p.y:
				points.append(Vector2i(p.x, last.y))  # Bridge the diagonal step
		points.append(p)
	return points

## Tile offsets of an S x S stamp. Odd sizes centre on the cursor tile; even
## sizes centre on the vertex at that tile's near corner — the same geometry
## as ElevationTool.tile_offsets, so a 2x2 brush really paints four tiles.
## The round shape keeps tiles whose centre lies within a circle of radius
## S/2 around the middle of the block, clipping the square's corners.
static func offsets(diameter: int, round_shape: bool = true) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	# Keep the anchor and round footprint snapped to whole-tile half sizes.
	@warning_ignore_start("integer_division")
	var half_size: int = diameter / 2
	@warning_ignore_restore("integer_division")
	var from: int = -half_size
	var to: int = diameter - 1 + from
	# Middle of the block in tile-offset space: tile centres sit half a tile
	# along from their offset, so the block's centre is (from + to + 1) / 2.
	var middle: float = float(from + to + 1) * 0.5
	var limit: float = float(half_size)
	for x in range(from, to + 1):
		for y in range(from, to + 1):
			if round_shape:
				var dx: float = float(x) + 0.5 - middle
				var dy: float = float(y) + 0.5 - middle
				if dx * dx + dy * dy > limit * limit:
					continue
			result.append(Vector2i(x, y))
	return result
