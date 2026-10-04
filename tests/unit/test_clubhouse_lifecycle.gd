extends GutTest
## Golfers arrive and leave through the clubhouse: a new guest walks from its
## door to the first tee before the turn system can pick them, and a finished
## guest walks home and pays the clubhouse a visit before they are gone.

const CLUBHOUSE_TILE := Vector2i(10, 10)
const TEE := Vector2i(24, 20)
const CUP := Vector2i(34, 20)

var fixture: Node2D
var golfers: GolferManager
var grid: TerrainGrid
var entities: EntityLayer
var clubhouse: Building
var saved: Dictionary


func before_each() -> void:
	saved = {
		"course": GameManager.current_course,
		"grid": GameManager.terrain_grid,
		"entities": GameManager.entity_layer,
		"mode": GameManager.current_mode,
		"money": GameManager.money,
		"stats": GameManager.daily_stats,
	}
	grid = TerrainGrid.new()
	grid.grid_width = 48
	grid.grid_height = 32
	add_child_autofree(grid)
	for x in range(grid.grid_width):
		for y in range(grid.grid_height):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.GRASS)
	grid.set_tile(TEE, TerrainTypes.Type.TEE_BOX)
	grid.set_tile(CUP, TerrainTypes.Type.GREEN)
	entities = EntityLayer.new()
	add_child_autofree(entities)
	entities.set_terrain_grid(grid)
	clubhouse = CourseClubhouse.ensure(grid, entities, CLUBHOUSE_TILE)
	GameManager.terrain_grid = grid
	GameManager.entity_layer = entities
	GameManager.daily_stats = GameManager.DailyStatistics.new()

	var course := GameManager.CourseData.new()
	var hole := GameManager.HoleData.new()
	hole.hole_number = 1
	hole.par = 4
	hole.distance_yards = 400
	hole.tee_position = TEE
	hole.hole_position = CUP
	course.add_hole(hole)
	GameManager.current_course = course

	fixture = Node2D.new()
	add_child_autofree(fixture)
	var container_root := Node2D.new()
	container_root.name = "Entities"
	fixture.add_child(container_root)
	for container_name in ["Golfers", "Balls"]:
		var container := Node2D.new()
		container.name = container_name
		container_root.add_child(container)
	golfers = GolferManager.new()
	fixture.add_child(golfers)
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)


func after_each() -> void:
	golfers.clear_all_golfers()
	GameManager.current_course = saved.course
	GameManager.terrain_grid = saved.grid if is_instance_valid(saved.grid) else null
	GameManager.entity_layer = saved.entities if is_instance_valid(saved.entities) else null
	GameManager.current_mode = saved.mode
	GameManager.money = saved.money
	GameManager.daily_stats = saved.stats


# ---------------------------------------------------------------------------
# Arriving
# ---------------------------------------------------------------------------

func test_new_guests_arrive_from_the_clubhouse_door() -> void:
	var golfer := golfers.spawn_golfer("Arriving guest")
	assert_not_null(golfer)
	var door := CourseClubhouse.front_tile(clubhouse, grid, entities)
	var door_screen := grid.grid_to_screen_center(door)
	assert_eq(golfer.current_state, Golfer.State.WALKING,
		"Guests walk in from the clubhouse rather than appearing on the tee")
	assert_almost_eq(golfer.global_position.x, door_screen.x, 0.01)
	assert_almost_eq(golfer.global_position.y, door_screen.y, 0.01)
	assert_eq(golfer.ball_position, TEE, "Their ball is already on the first tee")
	assert_gt(golfer.path.size(), 0, "with a route to it")
	assert_almost_eq(golfer.path[golfer.path.size() - 1].x,
			grid.grid_to_screen_center(TEE).x, 0.01)

	# Reaching the tee hands them to the turn system, exactly as before.
	golfer._on_reached_destination()
	assert_eq(golfer.current_state, Golfer.State.IDLE,
		"Once at the tee they wait their turn like any other golfer")


func test_an_arriving_golfer_is_not_picked_to_play() -> void:
	var golfer := golfers.spawn_golfer("Late arrival")
	golfers._update_group([golfer] as Array[Golfer])
	assert_ne(golfer.current_state, Golfer.State.PREPARING_SHOT,
		"Nobody tees off straight out of the clubhouse doorway")


func test_spawning_without_a_clubhouse_keeps_the_old_seating() -> void:
	GameManager.entity_layer = null
	var golfer := golfers.spawn_golfer("No clubhouse here")
	assert_eq(golfer.current_state, Golfer.State.IDLE,
		"Without a clubhouse the turn system still seats them, as before")


# ---------------------------------------------------------------------------
# Leaving
# ---------------------------------------------------------------------------

func test_finishing_guests_walk_home_and_visit_before_leaving() -> void:
	clubhouse.upgrade_level = 2  # Clubhouse with Pro Shop: it earns per guest
	var income := clubhouse.get_income_per_golfer()
	assert_gt(income, 0, "The upgraded clubhouse is the one that pays")

	var golfer := golfers.spawn_golfer("Finishing guest")
	golfer.current_hole = 0
	golfer.current_strokes = 4
	golfer.global_position = grid.grid_to_screen_center(TEE)
	var money_before := GameManager.money
	var revenue_before := clubhouse.total_revenue

	golfer._begin_departure()
	assert_eq(golfer.current_state, Golfer.State.LEAVING,
		"A finished round walks home through the clubhouse")
	assert_eq(golfer._departure_phase, 1)
	assert_eq(GameManager.money, money_before,
		"No visit is paid while the golfer is still on the course")
	var door := CourseClubhouse.front_tile(clubhouse, grid, entities)
	var door_screen := grid.grid_to_screen_center(door)
	var last_leg: Vector2 = golfer.path[golfer.path.size() - 1]
	assert_almost_eq(last_leg.x, door_screen.x, 0.01)
	assert_almost_eq(last_leg.y, door_screen.y, 0.01)

	golfer._arrive_at_clubhouse()
	assert_eq(golfer._departure_phase, 2, "The golfer visits at the door")
	assert_eq(GameManager.money, money_before + income,
		"The clubhouse is paid when the golfer actually gets there")
	assert_eq(clubhouse.total_revenue, revenue_before + income)
	assert_gt(golfer.needs.energy, 0.0, "and the visit restores the guest")

	golfer._process_departure(Golfer.CLUBHOUSE_VISIT_SECONDS + 0.01)
	assert_eq(golfer.current_state, Golfer.State.FINISHED,
		"Only once the visit ends is the golfer gone")


func test_a_group_walks_home_together_and_then_leaves_the_course() -> void:
	var first := golfers.spawn_golfer("First home")
	var second := golfers.spawn_golfer("Last home", 0.5, first.group_id)
	assert_eq(first.group_id, second.group_id)
	for golfer in [first, second]:
		golfer.current_hole = 0
		golfer.current_strokes = 4
		golfer.global_position = grid.grid_to_screen_center(TEE)
		golfer.finish_round()

	assert_eq(first.current_state, Golfer.State.LEAVING, "The group walks home")
	assert_true(golfers.get_active_golfers().has(first),
		"Nobody is taken off the course while they are still walking")

	# The first arrival waits at the door for the rest of the group.
	first._arrive_at_clubhouse()
	first._process_departure(Golfer.CLUBHOUSE_VISIT_SECONDS + 0.01)
	assert_eq(first.current_state, Golfer.State.FINISHED, "The first golfer is inside")
	assert_true(golfers.get_active_golfers().has(first),
		"but the group waits for the golfer still walking home")

	# The last one in is the one that takes the group off the course.
	second._arrive_at_clubhouse()
	second._process_departure(Golfer.CLUBHOUSE_VISIT_SECONDS + 0.01)
	await wait_seconds(1.5)  # The manager's send-off pause before removal
	assert_false(golfers.get_active_golfers().has(first),
		"The whole group leaves once the last golfer is inside")
	assert_false(golfers.get_active_golfers().has(second))


func test_a_lone_golfer_leaves_the_course_after_the_walk_home() -> void:
	var golfer := golfers.spawn_golfer("On my own")
	golfer.current_hole = 0
	golfer.current_strokes = 4
	golfer.global_position = grid.grid_to_screen_center(TEE)
	golfer.finish_round()
	assert_eq(golfer.current_state, Golfer.State.LEAVING)
	golfer._arrive_at_clubhouse()
	golfer._process_departure(Golfer.CLUBHOUSE_VISIT_SECONDS + 0.01)
	assert_eq(golfer.current_state, Golfer.State.FINISHED)
	await wait_seconds(1.5)
	assert_false(golfers.get_active_golfers().has(golfer),
		"A golfer who has gone inside is taken off the course")


func test_golfers_heading_home_free_up_the_course() -> void:
	var golfer := golfers.spawn_golfer("Heading home")
	golfer._change_state(Golfer.State.LEAVING)
	assert_true(GolferManager._is_off_the_course(golfer),
		"A golfer walking home is no longer in play")
	assert_false(golfer.is_staff_service_available(),
		"and on-course staff leave them alone")
	assert_true(golfers._is_hole_clear_of_earlier_golfers(golfer.current_hole),
		"they do not hold the hole they just finished")

	for i in range(golfers.get_max_concurrent_golfers() + 2):
		var extra := golfers.spawn_golfer("Filler %d" % i)
		extra._change_state(Golfer.State.LEAVING)
	assert_false(golfers._is_at_golfer_cap(),
		"a group walking home does not count against the course")


func test_golfers_walking_home_do_not_start_amenity_visits() -> void:
	var registry: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]
	entities.place_building("coffee_house", Vector2i(30, 24), registry)
	var golfer := golfers.spawn_golfer("Snack seeker")
	golfer.global_position = grid.grid_to_screen_center(Vector2i(30, 24))
	golfer._change_state(Golfer.State.LEAVING)
	golfer._check_building_proximity()
	assert_eq(golfer._amenity_phase, 0,
		"A golfer on the way home keeps walking past the coffee house")
