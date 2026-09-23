extends GutTest
## Opening a hole from the tee box and green-with-hole tiles waiting on the course.

const TEE := Vector2i(2, 2)
const CUP := Vector2i(10, 2)

var grid: TerrainGrid
var tool: HoleCreationTool
var _saved_grid: TerrainGrid
var _saved_course: GameManager.CourseData

func before_each() -> void:
	_saved_grid = GameManager.terrain_grid
	_saved_course = GameManager.current_course
	grid = TerrainGrid.new()
	grid.grid_width = 16
	grid.grid_height = 16
	add_child_autofree(grid)
	GameManager.terrain_grid = grid
	GameManager.current_course = GameManager.CourseData.new()
	tool = HoleCreationTool.new()
	add_child_autofree(tool)
	tool.current_hole_number = 1
	# What the player would have painted: one tee box and one green with a hole.
	grid.set_tile(TEE, TerrainTypes.Type.TEE_BOX)
	grid.set_tile(CUP, TerrainTypes.Type.GREEN)
	grid.add_cup_tile(CUP)

func after_each() -> void:
	GameManager.terrain_grid = _saved_grid
	GameManager.current_course = _saved_course

func test_waiting_pair_is_ready_to_open() -> void:
	assert_true(tool.can_open_hole())
	var request := tool.open_hole_request()
	assert_eq(request.tee, TEE)
	assert_eq(request.cup, CUP)

func test_open_hole_builds_the_hole_from_the_pair() -> void:
	watch_signals(tool)
	var hole := tool.open_hole(TEE, CUP)

	assert_not_null(hole)
	assert_eq(hole.hole_number, 1)
	assert_eq(hole.tee_position, TEE)
	assert_eq(hole.green_position, CUP)
	assert_eq(hole.hole_position, CUP)
	assert_eq(hole.distance_yards, 176)  # 8 tiles at 22 yards per tile
	assert_eq(hole.par, 3)
	assert_eq(GameManager.current_course.holes.size(), 1)
	assert_signal_emitted(tool, "hole_created")

func test_opening_a_hole_consumes_the_cup() -> void:
	assert_true(grid.has_cup_tile(CUP))
	tool.open_hole(TEE, CUP)
	assert_false(grid.has_cup_tile(CUP), "The cup now belongs to hole 1")
	assert_eq(HoleLayout.unused_cups(grid, GameManager.current_course), [])
	assert_true(HoleLayout.green_places_cup(grid, GameManager.current_course),
			"The next green the player paints carries the next hole's cup")

func test_opening_a_hole_consumes_the_tee_box() -> void:
	tool.open_hole(TEE, CUP)
	assert_eq(HoleLayout.unused_tee_boxes(grid, GameManager.current_course), [],
			"Back, middle and forward tees all belong to the hole")
	assert_true(HoleLayout.can_place_tee_box(grid, GameManager.current_course))

func test_second_hole_gets_the_next_number() -> void:
	tool.open_hole(TEE, CUP)
	grid.set_tile(Vector2i(2, 12), TerrainTypes.Type.TEE_BOX)
	grid.set_tile(Vector2i(10, 12), TerrainTypes.Type.GREEN)
	grid.add_cup_tile(Vector2i(10, 12))

	var second := tool.open_hole(Vector2i(2, 12), Vector2i(10, 12))
	assert_not_null(second)
	assert_eq(second.hole_number, 2)
	assert_eq(GameManager.current_course.total_par, second.par + 3)

func test_open_hole_needs_a_tee_box_tile() -> void:
	grid.set_tile(TEE, TerrainTypes.Type.FAIRWAY)
	assert_null(tool.open_hole(TEE, CUP))
	assert_eq(GameManager.current_course.holes.size(), 0)

func test_open_hole_needs_a_green_tile() -> void:
	grid.set_tile(CUP, TerrainTypes.Type.ROUGH)
	assert_null(tool.open_hole(TEE, CUP))
	assert_eq(GameManager.current_course.holes.size(), 0)

func test_open_hole_needs_enough_distance() -> void:
	var short_tee := Vector2i(9, 2)
	grid.set_tile(short_tee, TerrainTypes.Type.TEE_BOX)
	assert_null(tool.open_hole(short_tee, CUP))
	assert_eq(GameManager.current_course.holes.size(), 0)

func test_generated_courses_can_open_a_hole_without_a_cup_marker() -> void:
	# Quick Start and the prebuilt packages paint terrain directly and then open
	# holes, so a cup marker is not a precondition.
	grid.clear_cup_tiles()
	assert_false(tool.can_open_hole())
	var hole := tool.open_hole(TEE, CUP)
	assert_not_null(hole)
	assert_eq(GameManager.current_course.holes.size(), 1)

func test_cannot_open_while_a_second_tee_waits() -> void:
	grid.set_tile(Vector2i(6, 10), TerrainTypes.Type.TEE_BOX)
	assert_false(tool.can_open_hole())
	var request := tool.open_hole_request()
	assert_string_contains(request.reason, "one at a time")
