extends GutTest
## The size of a golf ball, and the hole cut under the flag that matches it.
##
## Balls used to be drawn at a 4 px radius; they are smaller now. The hole under
## every flag is cut to exactly the ball's width, so the black disc a player
## putts into is as wide as the ball they are putting — under the gold pin of a
## cup still waiting for a tee box and under the red pin of an open hole alike.

const CUP := Vector2i(3, 3)
const OPEN_HOLE_CUP := Vector2i(5, 5)
## What the ball was drawn at before it was shrunk.
const OLD_BALL_RADIUS := 4.0

var grid: TerrainGrid
var overlay: CupOverlay
var _saved_course: GameManager.CourseData

func before_each() -> void:
	_saved_course = GameManager.current_course
	GameManager.current_course = GameManager.CourseData.new()

	grid = TerrainGrid.new()
	grid.grid_width = 8
	grid.grid_height = 8
	add_child_autofree(grid)

	overlay = CupOverlay.new()
	add_child_autofree(overlay)
	overlay.initialize(grid)

func after_each() -> void:
	GameManager.current_course = _saved_course

func _ball() -> Ball:
	var ball := Ball.new()
	add_child_autofree(ball)
	return ball

## The ball's own polygon: the first shape in the visual node the most recent
## _update_visual() built. Every state draws the ball before its shadow, motion
## blur or splash, and the newest visual is always the last child.
func _drawn_ball(ball: Ball) -> Polygon2D:
	var visual := ball.get_child(ball.get_child_count() - 1)
	for node in visual.get_children():
		if node is Polygon2D:
			return node
	return null

func _widest(polygon: Polygon2D) -> float:
	var widest := 0.0
	for point in polygon.polygon:
		widest = maxf(widest, point.length())
	return widest

func _hole_extents(pos: Vector2i) -> Vector2:
	var polygon := CupOverlay.hole_polygon(grid, overlay, pos)
	var center := OverlayGeometry.tile_center(grid, overlay, pos)
	var extents := Vector2.ZERO
	for point in polygon:
		extents.x = maxf(extents.x, absf(point.x - center.x))
		extents.y = maxf(extents.y, absf(point.y - center.y))
	return extents

func _paint_cup(pos: Vector2i) -> void:
	grid.set_tile(pos, TerrainTypes.Type.GREEN)
	assert_true(grid.add_cup_tile(pos))

func _open_hole_at(pos: Vector2i) -> void:
	grid.set_tile(pos, TerrainTypes.Type.GREEN)
	var hole := GameManager.HoleData.new()
	hole.hole_number = GameManager.course_data.holes.size() + 1
	hole.hole_position = pos
	GameManager.course_data.holes.append(hole)

# --- the golf ball -----------------------------------------------------------

func test_the_ball_is_drawn_smaller_than_it_used_to_be() -> void:
	var ball := _ball()
	assert_almost_eq(_widest(_drawn_ball(ball)), Ball.BALL_RADIUS, 0.001,
			"The ball at rest is drawn at Ball.BALL_RADIUS")
	assert_lt(Ball.BALL_RADIUS, OLD_BALL_RADIUS,
			"The ball used to be drawn at a %s px radius" % OLD_BALL_RADIUS)

func test_every_ball_state_draws_a_ball_the_same_size() -> void:
	var ball := _ball()
	for state in [Ball.BallState.IN_FLIGHT, Ball.BallState.IN_WATER,
			Ball.BallState.OUT_OF_BOUNDS, Ball.BallState.ROLLING, Ball.BallState.AT_REST]:
		ball._change_state(state)
		var expected := Ball.FLIGHT_RADIUS if state == Ball.BallState.IN_FLIGHT else Ball.BALL_RADIUS
		assert_almost_eq(_widest(_drawn_ball(ball)), expected, 0.001,
				"State %s keeps the one ball size" % Ball.BallState.keys()[state])
		assert_lt(expected, OLD_BALL_RADIUS + 1.0,
				"State %s is smaller than the old airborne ball" % Ball.BallState.keys()[state])

# --- the hole under the flag -------------------------------------------------

func test_the_hole_is_cut_to_the_golf_balls_width() -> void:
	assert_eq(CupOverlay.hole_radius(), Ball.BALL_RADIUS, "The hole is as wide as the ball")

	_paint_cup(CUP)
	var extents := _hole_extents(CUP)
	assert_almost_eq(extents.x * 2.0, Ball.BALL_RADIUS * 2.0, 0.001,
			"The black disc is exactly the ball's diameter across")
	assert_almost_eq(CupOverlay.hole_radius() * 2.0, Ball.BALL_RADIUS * 2.0, 0.001)

func test_the_hole_lies_flat_on_the_green_rather_than_facing_the_camera() -> void:
	_paint_cup(CUP)
	var extents := _hole_extents(CUP)
	assert_lt(extents.y, extents.x, "The hole is squashed, not a circle on the screen")
	assert_almost_eq(extents.y / extents.x, float(grid.tile_height) / float(grid.tile_width), 0.001,
			"Squashed exactly the way the tile under it is")

func test_every_flag_gets_a_hole_under_it() -> void:
	_paint_cup(CUP)
	_open_hole_at(OPEN_HOLE_CUP)

	var tiles := overlay.hole_tiles()
	assert_has(tiles, CUP, "The waiting cup keeps its hole")
	assert_has(tiles, OPEN_HOLE_CUP, "An open hole's flag stands in a hole too")
	assert_eq(tiles.size(), 2, "One hole per flag")

func test_a_cup_an_open_hole_claims_is_only_cut_once() -> void:
	_paint_cup(CUP)
	_open_hole_at(CUP)
	assert_eq(overlay.hole_tiles(), [CUP], "A tile carries one hole, waiting cup or open hole")

func test_a_course_without_flags_has_no_holes_in_the_ground() -> void:
	assert_eq(overlay.hole_tiles(), [], "Nothing to cut until a cup exists")
