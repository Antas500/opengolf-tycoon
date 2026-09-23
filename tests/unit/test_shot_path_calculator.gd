extends GutTest
## ShotPathCalculator: the expected shot route HoleVisualizer draws for a hole, and
## calculate_route() — the same route for a tee/cup pair that is not a hole yet.

const TEE := Vector2i(4, 20)
const CUP := Vector2i(22, 22)  # ~18 tiles = 398 yds, par 4

var grid: TerrainGrid
var _saved_grid
var _saved_course
var _saved_wind

func before_each() -> void:
	_saved_grid = GameManager.terrain_grid
	_saved_course = GameManager.current_course
	_saved_wind = GameManager.wind_system
	grid = TerrainGrid.new()
	grid.grid_width = 40
	grid.grid_height = 40
	add_child_autofree(grid)
	GameManager.terrain_grid = grid
	GameManager.current_course = GameManager.CourseData.new()
	GameManager.wind_system = null

func after_each() -> void:
	# An earlier suite may have left a freed grid in the global; don't restore it.
	GameManager.terrain_grid = _saved_grid if is_instance_valid(_saved_grid) else null
	GameManager.current_course = _saved_course
	GameManager.wind_system = _saved_wind

func _hole(tee: Vector2i, cup: Vector2i, hole_number: int = 1) -> GameManager.HoleData:
	var hole := GameManager.HoleData.new()
	hole.hole_number = hole_number
	hole.tee_position = tee
	hole.green_position = cup
	hole.hole_position = cup
	hole.distance_yards = grid.calculate_distance_yards(tee, cup)
	hole.par = GolfRules.calculate_par(hole.distance_yards)
	return hole

func test_par_3_is_one_shot_to_the_cup() -> void:
	assert_eq(ShotPathCalculator.calculate_route(TEE, Vector2i(12, 20), 3), [TEE, Vector2i(12, 20)])

func test_par_4_and_5_add_landing_zones() -> void:
	var par4 := ShotPathCalculator.calculate_route(TEE, CUP, 4)
	assert_eq(par4.size(), 3)
	assert_eq(par4[0], TEE)
	assert_eq(par4[2], CUP)
	var par5_cup := Vector2i(30, 22)
	var par5 := ShotPathCalculator.calculate_route(TEE, par5_cup, 5)
	assert_eq(par5.size(), 4)
	assert_eq(par5[3], par5_cup)
	for i in range(1, par5.size()):
		assert_lt(Vector2(par5[i]).distance_to(Vector2(par5_cup)),
				Vector2(par5[i - 1]).distance_to(Vector2(par5_cup)), "Every shot advances")

func test_calculate_waypoints_is_calculate_route_for_the_hole() -> void:
	var hole := _hole(TEE, CUP)
	assert_eq(ShotPathCalculator.calculate_waypoints(hole, grid),
			ShotPathCalculator.calculate_route(TEE, CUP, hole.par, 0, grid))

func test_an_explicit_grid_is_used_instead_of_the_global_one() -> void:
	var expected := ShotPathCalculator.calculate_route(TEE, CUP, 4)
	var copy := grid.create_analysis_copy()
	GameManager.terrain_grid = null
	assert_eq(ShotPathCalculator.calculate_route(TEE, CUP, 4, -1, copy), expected,
			"Planning against a detached copy needs no global grid")
	GameManager.terrain_grid = grid
	copy.free()

func test_a_potential_hole_does_not_borrow_another_holes_green() -> void:
	# ShotAI's green-centre bias pulls approach shots toward holes[hole_index]'s
	# green. A cup that is not a hole yet has no entry there: with hole_index 0 it
	# would borrow hole 1's green; -1 must route as if no hole existed.
	var par5_cup := Vector2i(27, 20)
	var clean := ShotPathCalculator.calculate_route(TEE, par5_cup, 5, 0)

	var hole_one := _hole(Vector2i(2, 2), Vector2i(4, 36))
	GameManager.current_course.add_hole(hole_one)
	var borrowed := ShotPathCalculator.calculate_route(TEE, par5_cup, 5, 0)
	assert_ne(borrowed, clean, "Precondition: hole 1's green bends a borrowed route")
	assert_eq(ShotPathCalculator.calculate_route(TEE, par5_cup, 5, -1), clean,
			"hole_index -1 ignores the course's existing holes")
