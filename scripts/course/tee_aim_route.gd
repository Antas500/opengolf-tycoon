extends RefCounted
class_name TeeAimRoute
## TeeAimRoute - Where the aiming arrow painted on a tee tile points.
##
## A hole that plays straight gets a straight arrow: the route is [tee, cup]. A
## dogleg bends, so the arrow bends too: the route picks up the corner of the
## bend, [tee, corner, cup], and TeeAimOverlay rounds that corner into a curve.
##
## The corner is read off the fairway rather than from the shot planner. A dogleg
## *is* a bend in the fairway, so the fairway's own centre line is the honest
## shape to paint, and it costs one bounded grid scan instead of a ShotAI pass —
## which means the arrow can be rebuilt on every terrain change and can also be
## shown for a waiting tee box whose hole does not exist yet.
##
## The centre line is sampled in bands laid perpendicular to the tee→cup line:
## the centroid of the fairway inside each band follows the fairway as it swings
## around the corner, while a wide, straight fairway keeps its centroid on the
## line and is not mistaken for a dogleg.

## Returned by dogleg_corner() when the hole plays straight (grid coords are never negative).
const NO_CORNER := Vector2i(-1, -1)
## Number of bands the tee→cup line is cut into when sampling the fairway.
const SPINE_BANDS: int = 8
## How far (in tiles) the fairway must leave the tee→cup line before the hole
## counts as a dogleg. 2.5 tiles ≈ 55 yards.
const DOGLEG_MIN_TILES: float = 2.5
## Tiles searched either side of the tee→cup line. A fairway that swings further
## out than this is left to the straight arrow.
const SPINE_SEARCH_MARGIN: int = 6
## The corner must sit in the middle of the hole: a fairway flaring out next to
## the tee or the green is not a dogleg.
const CORNER_BAND_START: float = 0.2
const CORNER_BAND_END: float = 0.8

## Waypoints for the arrow: [tee, cup] straight, [tee, corner, cup] on a dogleg.
## Empty when there is nothing to aim at (no grid, an off-grid tee, tee == cup).
static func aim_route(grid: TerrainGrid, tee: Vector2i, cup: Vector2i) -> Array[Vector2i]:
	var route: Array[Vector2i] = []
	if grid == null or tee == cup:
		return route
	if not grid.is_valid_position(tee) or not grid.is_valid_position(cup):
		return route
	route.append(tee)
	var corner := dogleg_corner(grid, tee, cup)
	if corner != NO_CORNER:
		route.append(corner)
	route.append(cup)
	return route

## The tile where the hole bends, or NO_CORNER when it plays straight.
static func dogleg_corner(grid: TerrainGrid, tee: Vector2i, cup: Vector2i) -> Vector2i:
	var spine := fairway_spine(grid, tee, cup)
	if spine.size() < 3:
		return NO_CORNER  # No fairway to trace, or too little of it to bend.

	var axis := Vector2(cup) - Vector2(tee)
	var length := axis.length()
	if length <= 0.0:
		return NO_CORNER
	var dir := axis / length
	var perpendicular := Vector2(-dir.y, dir.x)

	var best_offset := 0.0
	var corner := NO_CORNER
	for point in spine:
		var relative: Vector2 = point - Vector2(tee)
		var along: float = relative.dot(dir)
		if along < length * CORNER_BAND_START or along > length * CORNER_BAND_END:
			continue
		var offset := absf(relative.dot(perpendicular))
		if offset > best_offset:
			best_offset = offset
			corner = Vector2i(roundi(point.x), roundi(point.y))

	if best_offset < DOGLEG_MIN_TILES:
		return NO_CORNER
	return corner

## Centre line of the fairway from the tee towards the cup, in tile-centre grid
## coordinates. Bands with no fairway in them are skipped, so the line has one
## point per band that carries fairway — and none at all for a hole whose fairway
## is unpainted (par 3s, brand new holes).
static func fairway_spine(grid: TerrainGrid, tee: Vector2i, cup: Vector2i) -> PackedVector2Array:
	var spine := PackedVector2Array()
	if grid == null:
		return spine
	var axis := Vector2(cup) - Vector2(tee)
	var length := axis.length()
	if length <= 0.0:
		return spine
	var dir := axis / length

	var sums: Array[Vector2] = []
	var counts := PackedInt32Array()
	sums.resize(SPINE_BANDS)
	counts.resize(SPINE_BANDS)
	for i in range(SPINE_BANDS):
		sums[i] = Vector2.ZERO
		counts[i] = 0

	var bounds := _search_bounds(grid, tee, cup)
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var pos := Vector2i(x, y)
			if not TerrainTypes.is_fairway(grid.get_tile(pos)):
				continue
			var relative: Vector2 = Vector2(pos) + Vector2(0.5, 0.5) - Vector2(tee)
			var along := relative.dot(dir)
			if along <= 0.0 or along >= length:
				continue
			var band := clampi(int(along / length * float(SPINE_BANDS)), 0, SPINE_BANDS - 1)
			sums[band] += relative
			counts[band] += 1

	for i in range(SPINE_BANDS):
		if counts[i] > 0:
			spine.append(Vector2(tee) + sums[i] / float(counts[i]))
	return spine

## Tiles scanned when tracing the fairway: the tee→cup line, grown by
## SPINE_SEARCH_MARGIN, clipped to the grid.
static func _search_bounds(grid: TerrainGrid, tee: Vector2i, cup: Vector2i) -> Rect2i:
	var min_x := maxi(mini(tee.x, cup.x) - SPINE_SEARCH_MARGIN, 0)
	var min_y := maxi(mini(tee.y, cup.y) - SPINE_SEARCH_MARGIN, 0)
	var max_x := mini(maxi(tee.x, cup.x) + SPINE_SEARCH_MARGIN + 1, grid.grid_width)
	var max_y := mini(maxi(tee.y, cup.y) + SPINE_SEARCH_MARGIN + 1, grid.grid_height)
	return Rect2i(min_x, min_y, maxi(max_x - min_x, 0), maxi(max_y - min_y, 0))
