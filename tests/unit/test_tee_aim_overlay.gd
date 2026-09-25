extends GutTest
## TeeAimOverlay — the arrow painted in the grass of every tee tile: which tiles
## carry one, which cup it points at, and that the whole marker (shaft, head and
## the two red tee markers) stays inside its own tile.

var grid: TerrainGrid
var overlay: TeeAimOverlay
var course: GameManager.CourseData
var _saved_course
var _saved_grid
var _saved_multi_tee: bool

const TEE := Vector2i(6, 20)
const CUP := Vector2i(30, 20)

func before_each() -> void:
	_saved_course = GameManager.current_course
	_saved_grid = GameManager.terrain_grid
	_saved_multi_tee = GameManager.multi_tee_enabled
	GameManager.multi_tee_enabled = false
	grid = TerrainGrid.new()
	grid.grid_width = 40
	grid.grid_height = 40
	add_child_autofree(grid)
	GameManager.terrain_grid = grid
	overlay = TeeAimOverlay.new()
	grid.add_child(overlay)
	overlay.initialize(grid)
	course = GameManager.CourseData.new()
	GameManager.current_course = course

func after_each() -> void:
	GameManager.current_course = _saved_course
	GameManager.terrain_grid = _saved_grid if is_instance_valid(_saved_grid) else null
	GameManager.multi_tee_enabled = _saved_multi_tee

func _paint_waiting_pair(tee: Vector2i = TEE, cup: Vector2i = CUP) -> void:
	grid.set_tile(tee, TerrainTypes.Type.TEE_BOX)
	grid.set_tile(cup, TerrainTypes.Type.GREEN)
	grid.add_cup_tile(cup)

func _add_hole(tee: Vector2i, cup: Vector2i, extra_tees: Array = []) -> GameManager.HoleData:
	var hole = GameManager.HoleData.new()
	hole.hole_number = course.holes.size() + 1
	hole.tee_position = tee
	hole.green_position = cup
	hole.hole_position = cup
	hole.tee_positions = {"back": tee}
	for i in range(extra_tees.size()):
		hole.tee_positions[["forward", "middle"][i]] = extra_tees[i]
	hole.pin_positions = [cup]
	course.add_hole(hole)
	return hole

func _paint_fairway(tiles: Array) -> void:
	for pos in tiles:
		grid.set_tile(pos, TerrainTypes.Type.FAIRWAY)

## A dogleg from TEE out east, bending north to a green at (30, 34).
func _paint_dogleg() -> void:
	for x in range(4, 22):
		for y in range(19, 22):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.FAIRWAY)
	for y in range(21, 36):
		for x in range(19, 22):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.FAIRWAY)

# --- Which tee tiles get an arrow, and where it points ---

func test_a_tee_box_waiting_for_its_green_aims_at_the_waiting_cup() -> void:
	_paint_waiting_pair()
	overlay.rebuild()
	assert_eq(overlay.aimed_tees(), [TEE], "The waiting tee box gets an arrow")
	assert_eq(overlay.route_for(TEE), [TEE, CUP], "It aims at the waiting cup")

func test_an_open_hole_aims_every_one_of_its_tee_tiles_at_its_cup() -> void:
	_paint_waiting_pair()
	var middle := Vector2i(9, 20)
	var forward := Vector2i(12, 20)
	grid.set_tile(middle, TerrainTypes.Type.TEE_BOX)
	grid.set_tile(forward, TerrainTypes.Type.TEE_BOX)
	grid.remove_cup_tile(CUP)  # Opening a hole consumes the cup marker.
	var hole := _add_hole(TEE, CUP, [forward, middle])
	overlay.rebuild()

	assert_eq(hole.tee_positions.size(), 3)
	assert_eq(overlay.aimed_tees(), [TEE, middle, forward], "Back, forward and middle tees all aim")
	for tee in [TEE, middle, forward]:
		var route := overlay.route_for(tee)
		assert_eq(route[0], tee, "The route starts on its own tee tile")
		assert_eq(route[route.size() - 1], CUP, "The arrow points at the hole's cup")

func test_a_tee_box_with_nothing_to_play_to_carries_no_arrow() -> void:
	grid.set_tile(TEE, TerrainTypes.Type.TEE_BOX)
	overlay.rebuild()
	assert_eq(overlay.aimed_tees(), [])
	assert_eq(overlay.route_for(TEE), [])
	assert_true(overlay.marker_layout(TEE).is_empty())

func test_a_plain_green_leaves_the_tee_without_an_arrow() -> void:
	# A green without a hole is not a target: only a cup is.
	grid.set_tile(TEE, TerrainTypes.Type.TEE_BOX)
	grid.set_tile(CUP, TerrainTypes.Type.GREEN)
	overlay.rebuild()
	assert_eq(overlay.aimed_tees(), [])

func test_a_dogleg_hole_gets_a_curved_route() -> void:
	_paint_dogleg()
	var cup := Vector2i(30, 34)
	grid.set_tile(TEE, TerrainTypes.Type.TEE_BOX)
	grid.set_tile(cup, TerrainTypes.Type.GREEN)
	_add_hole(TEE, cup)
	overlay.rebuild()

	var route := overlay.route_for(TEE)
	assert_eq(route.size(), 3, "The arrow bends at the corner of the dogleg")
	assert_eq(route[0], TEE)
	assert_eq(route[2], cup)
	assert_ne(route[1], TEE)
	assert_ne(route[1], cup)

func test_a_straight_hole_keeps_the_arrow_straight() -> void:
	for x in range(4, 31):
		grid.set_tile(Vector2i(x, 20), TerrainTypes.Type.FAIRWAY)
	grid.set_tile(TEE, TerrainTypes.Type.TEE_BOX)
	grid.set_tile(CUP, TerrainTypes.Type.GREEN)
	_add_hole(TEE, CUP)
	overlay.rebuild()
	assert_eq(overlay.route_for(TEE).size(), 2, "No corner, no curve")

# --- Keeping up with the course ---

func test_painting_a_cup_gives_the_waiting_tee_its_arrow() -> void:
	grid.set_tile(TEE, TerrainTypes.Type.TEE_BOX)
	overlay.rebuild()
	assert_eq(overlay.aimed_tees(), [], "Nothing to aim at yet")

	grid.set_tile(CUP, TerrainTypes.Type.GREEN)
	grid.add_cup_tile(CUP)
	await wait_frames(2)  # The overlay coalesces rebuilds into one deferred pass.
	assert_eq(overlay.aimed_tees(), [TEE], "The new cup is picked up without help")

func test_deleting_a_hole_removes_its_arrows() -> void:
	_paint_waiting_pair()
	var tool := HoleCreationTool.new()
	add_child_autofree(tool)
	var hole := tool.open_hole(TEE, CUP)
	assert_not_null(hole, "The waiting pair opens a hole")
	assert_eq(course.holes.size(), 1)
	overlay.rebuild()
	assert_eq(overlay.aimed_tees(), [TEE])
	assert_eq(overlay.route_for(TEE), [TEE, CUP])

	course.holes.erase(hole)
	EventBus.hole_deleted.emit(hole.hole_number)
	await wait_frames(2)
	assert_eq(overlay.aimed_tees(), [], "The tee the hole used no longer has a target")

func test_the_arrow_follows_the_day_s_pin() -> void:
	_paint_waiting_pair()
	var moved_cup := Vector2i(30, 26)
	var hole := _add_hole(TEE, CUP)
	hole.pin_positions = [CUP, moved_cup]
	overlay.rebuild()
	assert_eq(overlay.route_for(TEE), [TEE, CUP])

	hole.hole_position = moved_cup
	EventBus.pins_rotated.emit()
	await wait_frames(2)
	assert_eq(overlay.route_for(TEE), [TEE, moved_cup], "A new pin moves the arrow")

# --- The marker stays in the grass of its own tile ---

func test_the_marker_fits_inside_the_tee_tile() -> void:
	_paint_waiting_pair()
	overlay.rebuild()
	_assert_marker_inside_tile(TEE, "isometric")

func test_a_curved_marker_fits_inside_the_tee_tile() -> void:
	_paint_dogleg()
	var cup := Vector2i(30, 34)
	grid.set_tile(TEE, TerrainTypes.Type.TEE_BOX)
	grid.set_tile(cup, TerrainTypes.Type.GREEN)
	_add_hole(TEE, cup)
	overlay.rebuild()
	assert_eq(overlay.route_for(TEE).size(), 3)
	_assert_marker_inside_tile(TEE, "dogleg")

func test_the_marker_fits_in_the_top_down_view_too() -> void:
	_paint_waiting_pair()
	grid.set_view_isometric(false)
	overlay.rebuild()
	_assert_marker_inside_tile(TEE, "top-down")

func test_the_marker_fits_a_tee_tile_on_sculpted_ground() -> void:
	# Corner elevations move the edges of the grass the tile paints, so the fit
	# has to follow the ground rather than the flat diamond.
	_paint_waiting_pair()
	grid.set_vertex_elevation(TEE, 4)
	grid.set_vertex_elevation(TEE + Vector2i(1, 0), -3)
	grid.set_vertex_elevation(TEE + Vector2i(0, 1), 2)
	overlay.rebuild()
	_assert_marker_inside_tile(TEE, "sculpted")

func test_a_tee_tile_folded_by_elevation_shrinks_its_marker() -> void:
	# A cliff edge across one tile folds its projected grass into a sliver, so the
	# marker has less to fit into than the flat diamond suggests.
	_paint_waiting_pair()
	grid.set_vertex_elevation(TEE, 5)
	grid.set_vertex_elevation(TEE + Vector2i(1, 0), -5)
	grid.set_vertex_elevation(TEE + Vector2i(1, 1), 5)
	grid.set_vertex_elevation(TEE + Vector2i(0, 1), -5)
	overlay.rebuild()
	var layout := overlay.marker_layout(TEE)
	assert_false(layout.is_empty(), "The folded tile still gets a marker")
	assert_true(layout.floored, "A folded tile has no interior to fit into")
	assert_almost_eq(layout.scale, TeeAimOverlay.MIN_FIT_SCALE, 0.001)
	_assert_marker_inside_tile(TEE, "folded")

func test_the_marker_never_shrinks_below_the_readable_minimum() -> void:
	# What the layout promises: everything above the minimum is fitted exactly,
	# and a tile with less room than that gets a marker at the minimum size.
	_paint_waiting_pair()
	overlay.rebuild()
	assert_almost_eq(overlay.marker_layout(TEE).scale, overlay.marker_layout(TEE).fit, 0.001,
			"A tile with room keeps the honest fit")
	assert_false(overlay.marker_layout(TEE).floored)

	assert_almost_eq(TeeAimOverlay.fit_scale([], [], Vector2.ZERO, 0.0), 1.0, 0.001,
			"A marker in no tile at all is not touched")
	var tight := [
		{"normal": Vector2(1, 0), "offset": -3.0}, {"normal": Vector2(-1, 0), "offset": -3.0},
		{"normal": Vector2(0, 1), "offset": -3.0}, {"normal": Vector2(0, -1), "offset": -3.0},
	]
	var shaft := [Vector2(-16, 0), Vector2(16, 0)]
	var fit := TeeAimOverlay.fit_scale(tight, [{"points": shaft, "pen": 2.0}], Vector2.ZERO, 2.6)
	assert_lt(fit, TeeAimOverlay.MIN_FIT_SCALE, "A 6px tile has room for nothing")
	assert_almost_eq(TeeAimOverlay.fit_scale(tight, [], Vector2.ZERO, 9.0), 0.0, 0.001,
			"An inset wider than the tile leaves no room at all")

func test_the_marker_is_centred_on_its_tile() -> void:
	_paint_waiting_pair()
	overlay.rebuild()
	var layout := overlay.marker_layout(TEE)
	var centre := overlay.to_local(grid.grid_to_screen_center(TEE))
	var bounds := Rect2(layout.shaft[0], Vector2.ZERO)
	for point in layout.shaft:
		bounds = bounds.expand(point)
	for point in layout.head:
		bounds = bounds.expand(point)
	assert_almost_eq(bounds.get_center().x, centre.x, 1.0)
	assert_almost_eq(bounds.get_center().y, centre.y, 1.0)

func test_the_marker_has_a_head_and_two_red_balls() -> void:
	_paint_waiting_pair()
	overlay.rebuild()
	var layout := overlay.marker_layout(TEE)
	assert_eq(layout.head.size(), 3, "A three-cornered arrow head")
	assert_eq(layout.balls.size(), 2, "A tee marker either side of the arrow")
	var to_tip: Vector2 = layout.head[0] - layout.shaft[layout.shaft.size() - 1]
	assert_lt(to_tip.length(), TeeAimOverlay.HEAD_LENGTH, "The shaft stops under the head")
	# The two markers straddle the shaft, not the same side of it.
	var first_point: Vector2 = layout.shaft[0]
	var last_point: Vector2 = layout.shaft[layout.shaft.size() - 1]
	var shaft_dir := (last_point - first_point).normalized()
	var side := Vector2(-shaft_dir.y, shaft_dir.x)
	var first: float = (layout.balls[0] - first_point).dot(side)
	var second: float = (layout.balls[1] - first_point).dot(side)
	assert_gt(absf(first), TeeAimOverlay.BALL_RADIUS, "Markers sit outside the paint")
	assert_lt(first * second, 0.0, "One either side")

# --- How the shaft is built ---

func test_a_straight_hole_draws_a_straight_shaft() -> void:
	var east := Vector2(1.0, 0.0)
	for point in TeeAimOverlay.aim_shaft(east, east, 40.0):
		assert_almost_eq(point.y, 0.0, 0.001, "A straight hole keeps the shaft straight")

func test_a_curved_shaft_leaves_and_arrives_along_the_legs() -> void:
	var east := Vector2(1.0, 0.0)
	var north := Vector2(0.0, 1.0)
	var length := 40.0
	var shaft := TeeAimOverlay.aim_shaft(east, north, length)
	var first := TeeAimOverlay.direction(shaft[0], shaft[1])
	var last := TeeAimOverlay.direction(shaft[shaft.size() - 2], shaft[shaft.size() - 1])
	assert_almost_eq(first.dot(east), 1.0, 0.05, "The tail points back down the drive line")
	assert_almost_eq(last.dot(north), 1.0, 0.05, "The tip points on down the approach line")
	assert_almost_eq(shaft[0].distance_to(shaft[shaft.size() - 1]), length, 0.5,
			"A bend does not make the arrow longer")

func test_a_curved_shaft_bows_towards_the_corner_it_turns_through() -> void:
	var length := 40.0
	# Every direction a tile-scale dogleg can turn in. The arrow has to bend the
	# way the hole bends, never mirrored away from its corner.
	for angle in [30.0, 60.0, 90.0, 120.0, 150.0, -30.0, -60.0, -90.0, -120.0, -150.0]:
		var in_dir := Vector2.RIGHT
		var out_dir := Vector2.RIGHT.rotated(deg_to_rad(angle))
		var shaft := TeeAimOverlay.aim_shaft(in_dir, out_dir, length)
		var tail := shaft[0]
		var tip := shaft[shaft.size() - 1]
		var corner := tail + in_dir * ((tip - tail).cross(out_dir) / in_dir.cross(out_dir))
		var bow := shaft[shaft.size() / 2] - (tail + tip) * 0.5
		assert_gt(bow.dot(corner - (tail + tip) * 0.5), 0.0,
				"A turn of %d° bends toward its corner" % int(angle))

## A tile that could hold the marker at full size must contain all of it; a tile
## whose grass folds to a sliver (the marker hit MIN_FIT_SCALE) has to at least keep
## it on the tile.
func _assert_marker_inside_tile(tee: Vector2i, label: String) -> void:
	var layout := overlay.marker_layout(tee)
	assert_false(layout.is_empty(), "%s: the tee tile has a marker" % label)
	if layout.is_empty():
		return
	var polygon := PackedVector2Array()
	for point in grid.tile_polygon(tee):
		polygon.append(overlay.to_local(point))
	if layout.floored:
		_assert_marker_on_tile(layout, polygon, label)
		return

	for point in layout.shaft:
		assert_true(Geometry2D.is_point_in_polygon(point, polygon),
				"%s: shaft point %s stays in its tile" % [label, point])
	for point in layout.head:
		assert_true(Geometry2D.is_point_in_polygon(point, polygon),
				"%s: arrow head point %s stays in its tile" % [label, point])
	for ball in layout.balls:
		for i in range(8):
			var angle := TAU * float(i) / 8.0
			var edge: Vector2 = ball + Vector2(cos(angle), sin(angle)) * TeeAimOverlay.BALL_RADIUS
			assert_true(Geometry2D.is_point_in_polygon(edge, polygon),
					"%s: tee marker edge %s stays in its tile" % [label, edge])

## The weakest promise for a floored marker: it stays on its own tile.
func _assert_marker_on_tile(layout: Dictionary, polygon: PackedVector2Array, label: String) -> void:
	var box := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		box = box.expand(point)
	for point in layout.shaft:
		assert_true(box.has_point(point), "%s: shaft point %s stays on its tile" % [label, point])
	for point in layout.head:
		assert_true(box.has_point(point), "%s: head point %s stays on its tile" % [label, point])
	for ball in layout.balls:
		assert_true(box.has_point(ball), "%s: red marker %s stays on its tile" % [label, ball])
