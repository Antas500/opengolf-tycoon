extends GutTest
## One cup per hole, always on the hole's Green With Hole tile.
##
## Pins used to rotate across the green, so golfers putted to a different spot
## each month. Now the cup is cut where the player painted the Green With Hole
## tile and only relocating the whole green moves it.

const TEE := Vector2i(4, 20)
const CUP := Vector2i(30, 20)

var grid: TerrainGrid
var course: GameManager.CourseData
var tool: HoleCreationTool
var _saved_course: GameManager.CourseData
var _saved_grid: TerrainGrid
var _saved_multi_tee: bool

func before_each() -> void:
	grid = TerrainGrid.new()
	grid.grid_width = 40
	grid.grid_height = 40
	add_child_autofree(grid)

	_saved_course = GameManager.current_course
	_saved_grid = GameManager.terrain_grid
	_saved_multi_tee = GameManager.multi_tee_enabled
	course = GameManager.CourseData.new()
	GameManager.current_course = course
	GameManager.terrain_grid = grid
	GameManager.multi_tee_enabled = false

	tool = HoleCreationTool.new()
	add_child_autofree(tool)

func after_each() -> void:
	GameManager.current_course = _saved_course
	GameManager.terrain_grid = _saved_grid if is_instance_valid(_saved_grid) else null
	GameManager.multi_tee_enabled = _saved_multi_tee

func _paint_waiting_pair() -> void:
	grid.set_tile(TEE, TerrainTypes.Type.TEE_BOX)
	grid.set_tile(CUP, TerrainTypes.Type.GREEN)
	grid.add_cup_tile(CUP)

func _open_hole_on_big_green() -> GameManager.HoleData:
	_paint_waiting_pair()
	# A green wide enough that the old quadrant scan would have found
	# several pin positions to rotate through.
	for x in range(CUP.x - 3, CUP.x + 4):
		for y in range(CUP.y - 2, CUP.y + 3):
			if Vector2i(x, y) != CUP:
				grid.set_tile(Vector2i(x, y), TerrainTypes.Type.GREEN)
	return tool.open_hole(TEE, CUP)

func test_the_cup_opens_on_the_green_with_hole_tile() -> void:
	_paint_waiting_pair()
	var hole := tool.open_hole(TEE, CUP)
	assert_not_null(hole, "The waiting pair opens a hole")
	assert_eq(hole.hole_position, CUP, "The cup is cut on the Green With Hole tile")
	assert_eq(hole.hole_position, hole.green_position,
			"The cup sits on the hole's green tile, nowhere else")

func test_a_big_green_still_keeps_a_single_cup() -> void:
	var hole := _open_hole_on_big_green()
	assert_not_null(hole)
	var used := HoleLayout.used_cup_tiles(course)
	assert_eq(used.size(), 1, "A wide green does not grow a rotation set")
	assert_true(used.has(CUP), "The hole claims exactly its own cup tile")

func test_moving_the_green_carries_the_cup_with_it() -> void:
	var hole := _open_hole_on_big_green()
	assert_not_null(hole)
	var visualizer := HoleVisualizer.new()
	add_child_autofree(visualizer)
	visualizer.initialize(hole, grid)

	var new_green := Vector2i(8, 32)
	grid.set_tile(new_green, TerrainTypes.Type.GREEN)
	visualizer.update_green_position(new_green)

	assert_eq(hole.green_position, new_green, "The green moved")
	assert_eq(hole.hole_position, new_green,
			"The cup rides along — the only way to relocate it")
