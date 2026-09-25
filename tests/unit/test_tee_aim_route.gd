extends GutTest
## TeeAimRoute — the route the aiming arrow painted on a tee tile follows:
## straight at the cup on a straight hole, through the corner on a dogleg.

var grid: TerrainGrid

func before_each() -> void:
	grid = TerrainGrid.new()
	grid.grid_width = 40
	grid.grid_height = 40
	add_child_autofree(grid)

func _paint_fairway(tiles: Array) -> void:
	for pos in tiles:
		grid.set_tile(pos, TerrainTypes.Type.FAIRWAY)

## A straight fairway from (5, 20) to (30, 20), 3 tiles wide.
func _paint_straight_fairway() -> void:
	for x in range(5, 31):
		for y in range(19, 22):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.FAIRWAY)

## The same hole painted as a dogleg: out along y = 20, then north to the green
## at (30, 34). The bend sits around (20, 21).
func _paint_dogleg_fairway() -> void:
	for x in range(5, 22):
		for y in range(19, 22):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.FAIRWAY)
	for y in range(21, 35):
		for x in range(19, 22):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.FAIRWAY)

# --- Straight holes ---

func test_a_hole_without_fairway_aims_straight_at_the_cup() -> void:
	# Par 3s and brand new holes have no fairway to trace.
	assert_eq(TeeAimRoute.aim_route(grid, Vector2i(5, 20), Vector2i(30, 20)),
			[Vector2i(5, 20), Vector2i(30, 20)])

func test_a_straight_fairway_aims_straight_at_the_cup() -> void:
	_paint_straight_fairway()
	assert_eq(TeeAimRoute.dogleg_corner(grid, Vector2i(5, 20), Vector2i(30, 20)),
			TeeAimRoute.NO_CORNER, "A straight fairway is not a dogleg")
	assert_eq(TeeAimRoute.aim_route(grid, Vector2i(5, 20), Vector2i(30, 20)),
			[Vector2i(5, 20), Vector2i(30, 20)])

func test_a_wide_fairway_is_not_mistaken_for_a_dogleg() -> void:
	# The mown corridor is twice as wide as the direct line, but it runs straight
	# down it: the band centroids stay on the line.
	for x in range(5, 31):
		for y in range(14, 27):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.FAIRWAY)
	assert_eq(TeeAimRoute.dogleg_corner(grid, Vector2i(5, 20), Vector2i(30, 20)),
			TeeAimRoute.NO_CORNER)

func test_a_fairway_that_swings_to_one_side_reads_as_a_dogleg() -> void:
	# The corridor runs parallel to the line but well off it: everything in the
	# middle of the hole sits several tiles to the north.
	for x in range(5, 31):
		for y in range(24, 28):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.FAIRWAY)
	var corner := TeeAimRoute.dogleg_corner(grid, Vector2i(5, 20), Vector2i(30, 20))
	assert_ne(corner, TeeAimRoute.NO_CORNER)
	assert_gt(float(corner.y - 20), 2.0, "The corner must sit on the fairway's side")

# --- Doglegs ---

func test_a_dogleg_bends_the_route_at_its_corner() -> void:
	_paint_dogleg_fairway()
	var corner := TeeAimRoute.dogleg_corner(grid, Vector2i(5, 20), Vector2i(30, 34))
	assert_ne(corner, TeeAimRoute.NO_CORNER, "A bent fairway is a dogleg")

	var route := TeeAimRoute.aim_route(grid, Vector2i(5, 20), Vector2i(30, 34))
	assert_eq(route.size(), 3, "The route picks up the corner")
	assert_eq(route[0], Vector2i(5, 20))
	assert_eq(route[1], corner)
	assert_eq(route[2], Vector2i(30, 34))

	# The corner is the far side of the bend, not a point on the tee→cup line.
	var axis := Vector2(Vector2i(30, 34) - Vector2i(5, 20))
	var perpendicular := Vector2(-axis.y, axis.x).normalized()
	var offset: float = absf((Vector2(corner) - Vector2(5, 20)).dot(perpendicular))
	assert_gt(offset, TeeAimRoute.DOGLEG_MIN_TILES)

func test_a_fairway_flaring_out_next_to_the_tee_is_not_a_corner() -> void:
	# A wide apron around the tee and the green, with a straight corridor
	# between them: the bend has to be in the playing part of the hole.
	_paint_straight_fairway()
	for x in range(4, 10):
		for y in range(12, 29):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.FAIRWAY)
	assert_eq(TeeAimRoute.dogleg_corner(grid, Vector2i(5, 20), Vector2i(30, 20)),
			TeeAimRoute.NO_CORNER)

# --- Centre line ---

func test_the_spine_follows_the_fairway_centroid() -> void:
	_paint_straight_fairway()
	var spine := TeeAimRoute.fairway_spine(grid, Vector2i(5, 20), Vector2i(30, 20))
	assert_gt(spine.size(), 3, "A painted fairway gives the spine its bands")
	for point in spine:
		assert_almost_eq(point.y, 20.5, 0.75, "The spine runs down the fairway's centre")
	for i in range(1, spine.size()):
		assert_gt(spine[i].x, spine[i - 1].x, "Bands are sampled from the tee to the cup")

func test_the_spine_has_no_points_without_fairway() -> void:
	# Rough, bunkers and water do not shape the hole: only mown fairway does.
	grid.set_tile(Vector2i(10, 20), TerrainTypes.Type.ROUGH)
	grid.set_tile(Vector2i(11, 20), TerrainTypes.Type.BUNKER)
	assert_eq(TeeAimRoute.fairway_spine(grid, Vector2i(5, 20), Vector2i(30, 20)).size(), 0)

func test_firm_fairway_counts_as_fairway() -> void:
	for x in range(5, 31):
		grid.set_tile(Vector2i(x, 20), TerrainTypes.Type.FIRM_FAIRWAY)
	var spine := TeeAimRoute.fairway_spine(grid, Vector2i(5, 20), Vector2i(30, 20))
	assert_gt(spine.size(), 3)

# --- Degenerate input ---

func test_nothing_to_aim_at_gives_no_route() -> void:
	assert_eq(TeeAimRoute.aim_route(grid, Vector2i(5, 20), Vector2i(5, 20)), [])
	assert_eq(TeeAimRoute.aim_route(grid, Vector2i(-1, 5), Vector2i(5, 20)), [])
	assert_eq(TeeAimRoute.aim_route(grid, Vector2i(5, 20), Vector2i(99, 20)), [])
	assert_eq(TeeAimRoute.aim_route(null, Vector2i(5, 20), Vector2i(30, 20)), [])
