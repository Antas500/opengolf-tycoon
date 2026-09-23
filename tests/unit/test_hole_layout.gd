extends GutTest
## Rules for laying out a hole: single-tile tee boxes and greens with a hole,
## and the pair that Open Hole consumes.

var grid: TerrainGrid
var course: GameManager.CourseData

func before_each() -> void:
	grid = TerrainGrid.new()
	grid.grid_width = 16
	grid.grid_height = 16
	add_child_autofree(grid)
	course = GameManager.CourseData.new()

func _paint_tee(pos: Vector2i) -> void:
	grid.set_tile(pos, TerrainTypes.Type.TEE_BOX)

## Paint green and cut the cup the way the Green tool does.
func _paint_green_with_cup(pos: Vector2i) -> void:
	grid.set_tile(pos, TerrainTypes.Type.GREEN)
	assert_true(grid.add_cup_tile(pos))

func _make_hole(tee: Vector2i, cup: Vector2i) -> GameManager.HoleData:
	var hole = GameManager.HoleData.new()
	hole.hole_number = course.holes.size() + 1
	hole.tee_position = tee
	hole.green_position = cup
	hole.hole_position = cup
	hole.tee_positions = {"back": tee, "middle": tee, "forward": tee}
	hole.pin_positions = [cup]
	course.add_hole(hole)
	return hole

func test_tee_box_is_capped_at_a_single_tile() -> void:
	assert_eq(HoleLayout.max_brush_size(TerrainTypes.Type.TEE_BOX, grid, course), 1)

func test_ordinary_terrain_keeps_the_standard_brush() -> void:
	assert_eq(HoleLayout.max_brush_size(TerrainTypes.Type.FAIRWAY, grid, course),
			HoleLayout.UNLIMITED_BRUSH)
	assert_eq(HoleLayout.max_brush_size(TerrainTypes.Type.BUNKER, grid, course),
			HoleLayout.UNLIMITED_BRUSH)

func test_first_green_is_capped_so_it_can_carry_the_cup() -> void:
	assert_true(HoleLayout.green_places_cup(grid, course))
	assert_eq(HoleLayout.max_brush_size(TerrainTypes.Type.GREEN, grid, course), 1)

func test_later_greens_use_the_standard_brush() -> void:
	_paint_green_with_cup(Vector2i(10, 2))
	assert_false(HoleLayout.green_places_cup(grid, course))
	assert_eq(HoleLayout.max_brush_size(TerrainTypes.Type.GREEN, grid, course),
			HoleLayout.UNLIMITED_BRUSH)

func test_a_tee_box_can_be_placed_on_a_course_with_no_waiting_tee() -> void:
	assert_eq(HoleLayout.unused_tee_boxes(grid, course), [])
	assert_true(HoleLayout.can_place_tee_box(grid, course))
	assert_eq(HoleLayout.tee_placement_blocker(grid, course), "")

func test_a_second_tee_box_is_blocked_while_one_waits() -> void:
	_paint_tee(Vector2i(2, 2))
	assert_eq(HoleLayout.unused_tee_boxes(grid, course), [Vector2i(2, 2)])
	assert_false(HoleLayout.can_place_tee_box(grid, course))
	assert_string_contains(HoleLayout.tee_placement_blocker(grid, course), "already waiting")

func test_a_tee_box_claimed_by_a_hole_no_longer_counts() -> void:
	_paint_tee(Vector2i(2, 2))
	_paint_green_with_cup(Vector2i(10, 2))
	_make_hole(Vector2i(2, 2), Vector2i(10, 2))

	assert_eq(HoleLayout.unused_tee_boxes(grid, course), [])
	assert_true(HoleLayout.can_place_tee_box(grid, course),
			"The tee belongs to hole 1 now, so the next tee box may be painted")

func test_a_waiting_tee_still_blocks_even_after_another_hole_opens() -> void:
	_paint_tee(Vector2i(2, 2))
	_paint_tee(Vector2i(6, 6))
	_paint_green_with_cup(Vector2i(10, 2))
	_make_hole(Vector2i(2, 2), Vector2i(10, 2))

	assert_eq(HoleLayout.unused_tee_boxes(grid, course), [Vector2i(6, 6)])
	assert_false(HoleLayout.can_place_tee_box(grid, course))

func test_auto_generated_forward_and_middle_tees_stay_claimed() -> void:
	_paint_tee(Vector2i(2, 2))
	_paint_tee(Vector2i(4, 2))
	_paint_tee(Vector2i(6, 2))
	var hole := _make_hole(Vector2i(2, 2), Vector2i(10, 2))
	hole.tee_positions = {"back": Vector2i(2, 2), "middle": Vector2i(4, 2), "forward": Vector2i(6, 2)}

	assert_eq(HoleLayout.unused_tee_boxes(grid, course), [],
			"Forward and middle tees belong to the hole, so they are not unused")
	assert_true(HoleLayout.can_place_tee_box(grid, course))

func test_a_cup_claimed_by_a_hole_is_not_unused() -> void:
	_paint_green_with_cup(Vector2i(10, 2))
	_paint_green_with_cup(Vector2i(12, 8))
	assert_eq(HoleLayout.unused_cups(grid, course).size(), 2)

	_make_hole(Vector2i(2, 2), Vector2i(10, 2))
	assert_eq(HoleLayout.unused_cups(grid, course), [Vector2i(12, 8)])
	assert_false(HoleLayout.green_places_cup(grid, course))

func test_open_hole_needs_a_tee_and_a_cup() -> void:
	var nothing := HoleLayout.open_hole_request(grid, course)
	assert_false(nothing.ready)
	assert_string_contains(nothing.reason, "tee box")

	_paint_green_with_cup(Vector2i(10, 2))
	var cup_only := HoleLayout.open_hole_request(grid, course)
	assert_false(cup_only.ready)
	assert_string_contains(cup_only.reason, "tee box")

	_paint_tee(Vector2i(2, 2))
	grid.remove_cup_tile(Vector2i(10, 2))
	var tee_only := HoleLayout.open_hole_request(grid, course)
	assert_false(tee_only.ready)
	assert_string_contains(tee_only.reason, "green")

func test_open_hole_pairs_the_single_unused_tee_and_cup() -> void:
	_paint_tee(Vector2i(2, 2))
	_paint_green_with_cup(Vector2i(10, 2))
	var request := HoleLayout.open_hole_request(grid, course)
	assert_true(request.ready, request.reason)
	assert_eq(request.tee, Vector2i(2, 2))
	assert_eq(request.cup, Vector2i(10, 2))

func test_open_hole_refuses_two_waiting_tees() -> void:
	_paint_tee(Vector2i(2, 2))
	_paint_tee(Vector2i(6, 10))
	_paint_green_with_cup(Vector2i(10, 2))
	var request := HoleLayout.open_hole_request(grid, course)
	assert_false(request.ready)
	assert_string_contains(request.reason, "one at a time")

func test_open_hole_refuses_two_waiting_cups() -> void:
	_paint_tee(Vector2i(2, 2))
	_paint_green_with_cup(Vector2i(10, 2))
	_paint_green_with_cup(Vector2i(12, 10))
	var request := HoleLayout.open_hole_request(grid, course)
	assert_false(request.ready)
	assert_string_contains(request.reason, "one at a time")

func test_open_hole_refuses_a_pair_that_is_too_short() -> void:
	_paint_tee(Vector2i(2, 2))
	_paint_green_with_cup(Vector2i(4, 2))
	var request := HoleLayout.open_hole_request(grid, course)
	assert_false(request.ready)
	assert_string_contains(request.reason, "yards")

func test_holes_may_be_laid_out_again_after_a_hole_opens() -> void:
	_paint_tee(Vector2i(2, 2))
	_paint_green_with_cup(Vector2i(10, 2))
	_make_hole(Vector2i(2, 2), Vector2i(10, 2))
	grid.remove_cup_tile(Vector2i(10, 2))  # opening a hole consumes the marker

	assert_true(HoleLayout.can_place_tee_box(grid, course))
	assert_true(HoleLayout.green_places_cup(grid, course))
	assert_false(HoleLayout.open_hole_request(grid, course).ready)
