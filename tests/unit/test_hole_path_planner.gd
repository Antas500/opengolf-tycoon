extends GutTest
## HolePathPlanner: the expected shot route for a potential (not yet built) hole,
## planned off the main thread and cached until the terrain changes. The route
## must be the one HoleVisualizer draws once the hole is opened.

const TEE := Vector2i(4, 20)
const PAR4_CUP := Vector2i(20, 22)  # ~16 tiles = 354 yds
const PAR5_CUP := Vector2i(28, 22)  # ~24 tiles = 529 yds
const WAIT_SECONDS := 20.0

var grid: TerrainGrid
var planner: HolePathPlanner
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
	add_child_autofree(grid)  # _ready() fills the grid with GRASS.
	GameManager.terrain_grid = grid
	GameManager.current_course = GameManager.CourseData.new()
	GameManager.wind_system = null
	planner = HolePathPlanner.new()

func after_each() -> void:
	planner.shutdown()
	planner = null
	# An earlier suite may have left a freed grid in the global; don't restore it.
	GameManager.terrain_grid = _saved_grid if is_instance_valid(_saved_grid) else null
	GameManager.current_course = _saved_course
	GameManager.wind_system = _saved_wind

## Poll route_for() every frame until the route arrives (or time runs out).
func _await_route(tee: Vector2i, cup: Vector2i, par: int) -> Array[Vector2i]:
	var route: Array[Vector2i] = planner.route_for(grid, tee, cup, par)
	var deadline := Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while route.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		route = planner.route_for(grid, tee, cup, par)
	return route

## The route HoleVisualizer will draw for this tee/cup once the hole is open:
## the cup tile is green by then.
func _opened_hole_route(tee: Vector2i, cup: Vector2i) -> Array[Vector2i]:
	var before := grid.get_tile(cup)
	grid._grid[cup] = TerrainTypes.Type.GREEN
	var hole := GameManager.HoleData.new()
	hole.hole_number = GameManager.current_course.holes.size() + 1
	hole.tee_position = tee
	hole.green_position = cup
	hole.hole_position = cup
	hole.distance_yards = grid.calculate_distance_yards(tee, cup)
	hole.par = GolfRules.calculate_par(hole.distance_yards)
	var route := ShotPathCalculator.calculate_waypoints(hole, grid)
	grid._grid[cup] = before
	return route

func test_par_3_route_is_immediate_and_direct() -> void:
	var cup := Vector2i(12, 20)
	assert_eq(planner.route_for(grid, TEE, cup, 3), [TEE, cup])
	assert_false(planner.is_planning(), "Par 3s never start a task")

func test_par_4_route_is_planned_in_the_background() -> void:
	planner.threaded = true
	var first := planner.route_for(grid, TEE, PAR4_CUP, 4)
	assert_eq(first, [], "Not ready on the first frame: the caller draws a provisional line")
	assert_true(planner.is_planning())
	var route := await _await_route(TEE, PAR4_CUP, 4)
	assert_eq(route.size(), 3, "tee, drive landing, cup")
	assert_eq(route[0], TEE)
	assert_eq(route[route.size() - 1], PAR4_CUP)
	assert_false(planner.is_planning())

func test_route_matches_the_opened_hole() -> void:
	planner.threaded = true
	var par4 := await _await_route(TEE, PAR4_CUP, 4)
	assert_eq(par4, _opened_hole_route(TEE, PAR4_CUP), "Par 4 preview = HoleVisualizer route")
	var par5 := await _await_route(TEE, PAR5_CUP, 5)
	assert_eq(par5.size(), 4, "tee, two landings, cup")
	assert_eq(par5, _opened_hole_route(TEE, PAR5_CUP), "Par 5 preview = HoleVisualizer route")

func test_route_accounts_for_the_tees_open_hole_will_paint() -> void:
	# With multi-tee on, Open Hole paints forward/middle TEE_BOX tiles along the
	# line before HoleVisualizer routes the hole; the preview plans with them too.
	planner.threaded = true
	var extra_tees: Array = [Vector2i(10, 21), Vector2i(8, 20)]
	var route := await _await_route_with(TEE, PAR5_CUP, 5, extra_tees)
	for pos in extra_tees:
		grid._grid[pos] = TerrainTypes.Type.TEE_BOX
	var opened := _opened_hole_route(TEE, PAR5_CUP)
	for pos in extra_tees:
		grid._grid[pos] = TerrainTypes.Type.GRASS
	assert_eq(route, opened, "Preview with the extra tees = opened hole route")
	assert_eq(grid.get_tile(extra_tees[0]), TerrainTypes.Type.GRASS, "Only painted in the copy")

func _await_route_with(tee: Vector2i, cup: Vector2i, par: int, extra_tees: Array) -> Array[Vector2i]:
	var route: Array[Vector2i] = planner.route_for(grid, tee, cup, par, extra_tees)
	var deadline := Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while route.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		route = planner.route_for(grid, tee, cup, par, extra_tees)
	return route

func test_finished_routes_are_cached() -> void:
	planner.threaded = true
	var route := await _await_route(TEE, PAR4_CUP, 4)
	assert_eq(planner.route_for(grid, TEE, PAR4_CUP, 4), route, "Revisiting the tile is instant")
	assert_false(planner.is_planning())

func test_terrain_edits_invalidate_the_cache() -> void:
	planner.threaded = true
	await _await_route(TEE, PAR4_CUP, 4)
	var revision := grid.terrain_revision
	grid.set_tile(Vector2i(10, 30), TerrainTypes.Type.BUNKER)
	assert_gt(grid.terrain_revision, revision)
	assert_eq(planner.route_for(grid, TEE, PAR4_CUP, 4), [], "Replanned for the new terrain")
	var route := await _await_route(TEE, PAR4_CUP, 4)
	assert_eq(route[route.size() - 1], PAR4_CUP)

func test_only_the_latest_request_is_planned_next() -> void:
	planner.threaded = true
	planner.route_for(grid, TEE, PAR4_CUP, 4)  # Starts a task.
	var skipped := Vector2i(21, 22)
	planner.route_for(grid, TEE, skipped, 4)  # Queued...
	var latest := Vector2i(22, 24)
	planner.route_for(grid, TEE, latest, 4)  # ...then superseded.
	var route := await _await_route(TEE, latest, 4)
	assert_eq(route[route.size() - 1], latest)
	assert_false(planner.is_planning(), "The superseded tile was never planned")

func test_cancel_pending_drops_the_queued_request() -> void:
	planner.threaded = true
	planner.route_for(grid, TEE, PAR4_CUP, 4)
	planner.route_for(grid, TEE, PAR5_CUP, 5)
	planner.cancel_pending()
	var deadline := Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while planner.is_planning() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		planner.poll()
	assert_false(planner.is_planning())
	assert_eq(planner.route_for(grid, TEE, PAR4_CUP, 4).size(), 3,
			"The running task still finished and cached its route")

func test_the_live_grid_is_never_touched() -> void:
	planner.threaded = true
	var revision := grid.terrain_revision
	await _await_route(TEE, PAR4_CUP, 4)
	assert_eq(grid.get_tile(PAR4_CUP), TerrainTypes.Type.GRASS, "The cup tile is only green in the copy")
	assert_eq(grid.terrain_revision, revision)

func test_without_threads_the_route_waits_for_the_cursor_to_rest() -> void:
	planner.threaded = false
	planner.inline_dwell_msec = 150
	assert_eq(planner.route_for(grid, TEE, PAR4_CUP, 4), [], "Sweeping cursor: no stall")
	assert_eq(planner.route_for(grid, TEE, Vector2i(21, 22), 4), [], "Moved: dwell restarts")
	await get_tree().create_timer(0.2).timeout
	assert_eq(planner.route_for(grid, TEE, PAR4_CUP, 4), [], "Back on the first tile: dwell restarts")
	await get_tree().create_timer(0.2).timeout
	var route := planner.route_for(grid, TEE, PAR4_CUP, 4)
	assert_eq(route, _opened_hole_route(TEE, PAR4_CUP), "Planned inline once the cursor rested")
	assert_false(planner.is_planning())

func test_shutdown_waits_for_the_running_task() -> void:
	planner.threaded = true
	planner.route_for(grid, TEE, PAR5_CUP, 5)
	assert_true(planner.is_planning())
	planner.shutdown()
	assert_false(planner.is_planning())
	assert_eq(planner.route_for(grid, TEE, Vector2i(12, 20), 3).size(), 2, "Still usable afterwards")

func test_analysis_copy_is_detached() -> void:
	grid.set_tile(Vector2i(5, 5), TerrainTypes.Type.BUNKER)
	grid.set_bunker_depth(Vector2i(5, 5), 1)
	grid.set_vertex_elevation(Vector2i(6, 6), 3)
	var copy := grid.create_analysis_copy()
	assert_eq(copy.get_tile(Vector2i(5, 5)), TerrainTypes.Type.BUNKER)
	assert_eq(copy.get_bunker_depth(Vector2i(5, 5)), 1)
	assert_eq(copy.get_vertex_elevation(Vector2i(6, 6)), 3)
	assert_eq(copy.terrain_revision, grid.terrain_revision)
	assert_false(copy.is_inside_tree())
	copy.set_analysis_tile(Vector2i(5, 5), TerrainTypes.Type.GREEN)
	assert_eq(grid.get_tile(Vector2i(5, 5)), TerrainTypes.Type.BUNKER, "Writes stay in the copy")
	grid.set_tile(Vector2i(7, 7), TerrainTypes.Type.WATER)
	assert_eq(copy.get_tile(Vector2i(7, 7)), TerrainTypes.Type.GRASS, "Later edits don't leak in")
	copy.free()

func test_every_kind_of_terrain_write_bumps_the_revision() -> void:
	var r := grid.terrain_revision
	grid.set_tile(Vector2i(3, 3), TerrainTypes.Type.FAIRWAY)
	assert_gt(grid.terrain_revision, r, "set_tile")
	r = grid.terrain_revision
	grid.set_tile(Vector2i(3, 3), TerrainTypes.Type.FAIRWAY)
	assert_eq(grid.terrain_revision, r, "A no-op paint is not a change")
	grid.set_bunker_depth(Vector2i(3, 3), 1)
	assert_gt(grid.terrain_revision, r, "set_bunker_depth")
	r = grid.terrain_revision
	grid.set_vertex_elevation(Vector2i(3, 3), 2)
	assert_gt(grid.terrain_revision, r, "set_vertex_elevation")
	r = grid.terrain_revision
	grid.deserialize({"4,4": TerrainTypes.Type.WATER})
	assert_gt(grid.terrain_revision, r, "deserialize (load)")
	r = grid.terrain_revision
	grid.deserialize_elevation({})
	assert_gt(grid.terrain_revision, r, "deserialize_elevation (load)")
	r = grid.terrain_revision
	grid.deserialize_bunker_depth({})
	assert_gt(grid.terrain_revision, r, "deserialize_bunker_depth (load)")
