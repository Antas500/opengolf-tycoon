extends GutTest
## The clubhouse every course has: where it goes when a course starts without
## one, which tile is its front door, how it moves, and why it can never be
## demolished. See CourseClubhouse.

const SIZE := 4

var grid: TerrainGrid
var entities: EntityLayer
var clubhouse: Building
var _saved_terrain_grid
var _saved_entity_layer


func before_each() -> void:
	_saved_terrain_grid = GameManager.terrain_grid
	_saved_entity_layer = GameManager.entity_layer
	grid = TerrainGrid.new()
	grid.grid_width = 40
	grid.grid_height = 32
	add_child_autofree(grid)
	for x in range(grid.grid_width):
		for y in range(grid.grid_height):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.GRASS)
	entities = EntityLayer.new()
	add_child_autofree(entities)
	entities.set_terrain_grid(grid)
	GameManager.terrain_grid = grid
	GameManager.entity_layer = entities
	clubhouse = CourseClubhouse.ensure(grid, entities, Vector2i(10, 10))


func after_each() -> void:
	GameManager.terrain_grid = _saved_terrain_grid if is_instance_valid(_saved_terrain_grid) else null
	GameManager.entity_layer = _saved_entity_layer if is_instance_valid(_saved_entity_layer) else null


# ---------------------------------------------------------------------------
# Placing one
# ---------------------------------------------------------------------------

func test_ensure_places_a_clubhouse_at_the_suggested_tile() -> void:
	assert_not_null(clubhouse, "A course without a clubhouse gets one")
	assert_true(CourseClubhouse.exists(entities))
	assert_eq(clubhouse.building_type, "clubhouse")
	assert_eq(clubhouse.grid_position, Vector2i(10, 10),
		"The suggested tile is the first candidate")
	assert_eq(clubhouse.width, SIZE)
	assert_eq(clubhouse.height, SIZE)
	for tile in clubhouse.get_footprint():
		assert_true(entities.is_tile_occupied_by_building(tile),
			"%s is covered by the clubhouse" % tile)
	assert_false(entities.is_tile_occupied_by_building(Vector2i(10 + SIZE, 10)),
		"and nothing past its footprint is")


func test_ensure_never_duplicates_or_moves_an_existing_clubhouse() -> void:
	var returned := CourseClubhouse.ensure(grid, entities, Vector2i(25, 25))
	assert_same(returned, clubhouse, "The existing clubhouse is returned")
	assert_eq(clubhouse.grid_position, Vector2i(10, 10),
		"and is left exactly where it stood")
	var clubhouses := 0
	for building in entities.get_all_buildings():
		if building.is_clubhouse():
			clubhouses += 1
	assert_eq(clubhouses, 1, "There is only ever one clubhouse")


func test_ensure_skips_a_preferred_tile_that_is_a_playing_surface() -> void:
	var lake := TerrainGrid.new()
	lake.grid_width = 40
	lake.grid_height = 32
	add_child_autofree(lake)
	for x in range(lake.grid_width):
		for y in range(lake.grid_height):
			lake.set_tile(Vector2i(x, y), TerrainTypes.Type.GRASS)
	for x in range(8, 20):
		for y in range(8, 20):
			lake.set_tile(Vector2i(x, y), TerrainTypes.Type.WATER)
	var layer := EntityLayer.new()
	add_child_autofree(layer)
	layer.set_terrain_grid(lake)

	var placed := CourseClubhouse.ensure(lake, layer, Vector2i(10, 10))
	assert_not_null(placed, "The clubhouse is placed even when the pocket is water")
	for tile in placed.get_footprint():
		assert_false(lake.get_tile(tile) in CourseClubhouse.FORBIDDEN_TERRAINS,
			"%s is legal ground" % tile)
		assert_ne(lake.get_tile(tile), TerrainTypes.Type.WATER,
			"nothing is built on the water")
	var distance: int = maxi(absi(placed.grid_position.x - 10),
			absi(placed.grid_position.y - 10))
	assert_lt(distance, 20, "It is searched for just outside the wet pocket")


func test_course_clubhouse_guarantee_leaves_greens_and_tees_alone() -> void:
	var played := TerrainGrid.new()
	played.grid_width = 40
	played.grid_height = 32
	add_child_autofree(played)
	for x in range(12, 28):
		for y in range(12, 28):
			played.set_tile(Vector2i(x, y), TerrainTypes.Type.FAIRWAY)
	for x in range(14, 22):
		for y in range(14, 22):
			played.set_tile(Vector2i(x, y), TerrainTypes.Type.GREEN)
	played.set_tile(Vector2i(18, 24), TerrainTypes.Type.TEE_BOX)
	var layer := EntityLayer.new()
	add_child_autofree(layer)
	layer.set_terrain_grid(played)

	var placed := CourseClubhouse.ensure(played, layer, Vector2i(16, 16))
	assert_not_null(placed)
	for tile in placed.get_footprint():
		var kind: int = played.get_tile(tile)
		assert_ne(kind, TerrainTypes.Type.GREEN, "No clubhouse on a green (%s)" % tile)
		assert_ne(kind, TerrainTypes.Type.TEE_BOX, "No clubhouse on a tee (%s)" % tile)


# ---------------------------------------------------------------------------
# The front door
# ---------------------------------------------------------------------------

func test_front_tile_is_walkable_ground_just_outside_the_footprint() -> void:
	var door := CourseClubhouse.front_tile(clubhouse, grid, entities)
	assert_ne(door, Vector2i(-1, -1), "A clubhouse on grass has a front door")
	var footprint: Array = clubhouse.get_footprint()
	assert_false(door in footprint, "The door is outside the building")
	var touches := false
	for tile in footprint:
		if absi(tile.x - door.x) <= 1 and absi(tile.y - door.y) <= 1:
			touches = true
			break
	assert_true(touches, "and touches its footprint")
	assert_false(entities.is_tile_occupied_by_building(door),
		"Golfers must be able to stand at the door")


func test_front_tile_prefers_the_screen_facing_side() -> void:
	var door := CourseClubhouse.front_tile(clubhouse, grid, entities)
	assert_eq(door, Vector2i(11, 10 + SIZE),
		"The south (screen-facing) edge of the footprint is the entrance")


func test_golfers_walk_out_of_the_front_door_tile() -> void:
	var door := CourseClubhouse.front_tile(clubhouse, grid, entities)
	var tee := Vector2i(20, 20)
	var golfer: Golfer = autofree(Golfer.new())
	golfer.golfer_id = 9001
	golfer.golfer_name = "Arriving guest"
	golfer.begin_arrival_from_clubhouse(door, tee)
	assert_eq(golfer.current_state, Golfer.State.WALKING,
		"Guests walk in from the clubhouse rather than appearing on the tee")
	assert_eq(golfer.ball_position, tee, "but they are already on the tee's clock")
	assert_almost_eq(golfer.global_position.x, grid.grid_to_screen_center(door).x, 0.01)
	assert_almost_eq(golfer.global_position.y, grid.grid_to_screen_center(door).y, 0.01)
	assert_gt(golfer.path.size(), 0, "with a route to the first tee")


func test_a_golfer_whose_round_ends_walks_back_to_the_clubhouse() -> void:
	var saved_layer = GameManager.entity_layer
	GameManager.entity_layer = entities
	var golfer: Golfer = autofree(Golfer.new())
	golfer.golfer_id = 9002
	golfer.golfer_name = "Finishing guest"
	golfer.current_hole = 0
	golfer.current_strokes = 4
	golfer.global_position = grid.grid_to_screen_center(Vector2i(30, 20))
	golfer._begin_departure()
	assert_eq(golfer.current_state, Golfer.State.LEAVING,
		"A finished round walks home through the clubhouse")
	var door := CourseClubhouse.front_tile(clubhouse, grid, entities)
	assert_gt(golfer.path.size(), 0, "with a route to the door")
	var last_leg: Vector2 = golfer.path[golfer.path.size() - 1]
	assert_almost_eq(last_leg.x, grid.grid_to_screen_center(door).x, 0.01)
	assert_almost_eq(last_leg.y, grid.grid_to_screen_center(door).y, 0.01)

	# Arriving at the door pays the visit and then the golfer is gone.
	golfer._arrive_at_clubhouse()
	assert_eq(golfer._departure_phase, 2, "The golfer visits the clubhouse at its door")
	golfer._process_departure(Golfer.CLUBHOUSE_VISIT_SECONDS + 0.01)
	assert_eq(golfer.current_state, Golfer.State.FINISHED,
		"and only then leaves the course")
	GameManager.entity_layer = saved_layer


func test_a_course_without_a_clubhouse_finishes_golfers_where_they_stood() -> void:
	var saved_layer = GameManager.entity_layer
	GameManager.entity_layer = null
	var golfer: Golfer = autofree(Golfer.new())
	golfer.golfer_name = "Unlucky guest"
	golfer._begin_departure()
	assert_eq(golfer.current_state, Golfer.State.FINISHED,
		"With nothing to walk to, the old instant finish is kept")
	GameManager.entity_layer = saved_layer


# ---------------------------------------------------------------------------
# Moving one
# ---------------------------------------------------------------------------

func test_a_legal_move_says_nothing() -> void:
	assert_eq(CourseClubhouse.move_error(grid, entities, clubhouse, Vector2i(24, 8)), "",
		"Grass anywhere on the course takes the clubhouse")
	assert_true(CourseClubhouse.can_move_to(grid, entities, clubhouse, Vector2i(24, 8)))


func test_moving_the_clubhouse_relocates_the_same_building() -> void:
	clubhouse.upgrade_level = 2
	clubhouse.total_revenue = 1234
	var old_pos := clubhouse.grid_position
	assert_true(CourseClubhouse.move_to(entities, clubhouse, Vector2i(24, 8)),
		"A legal move goes through")
	assert_eq(clubhouse.grid_position, Vector2i(24, 8))
	assert_eq(clubhouse.upgrade_level, 2, "Its upgrades come along")
	assert_eq(clubhouse.total_revenue, 1234, "and so does its history")
	assert_same(CourseClubhouse.find(entities), clubhouse, "Still the same clubhouse")
	assert_false(entities.is_tile_occupied_by_building(old_pos),
		"The old tiles are free again")
	assert_true(entities.is_tile_occupied_by_building(Vector2i(26, 10)),
		"The building answers at its new tile")
	assert_false(entities.buildings.has(old_pos), "The dictionary moved with it")


func test_the_move_is_announced_for_anyone_drawing_the_grounds() -> void:
	watch_signals(entities)
	CourseClubhouse.move_to(entities, clubhouse, Vector2i(24, 8))
	assert_signal_emitted(entities, "building_moved")
	var args: Array = get_signal_parameters(entities, "building_moved")
	assert_eq(args[1], Vector2i(10, 10), "The move reports where it left")
	assert_eq(args[2], Vector2i(24, 8), "and where it landed")


func test_move_errors_explain_why_not() -> void:
	assert_eq(CourseClubhouse.move_error(grid, entities, clubhouse, clubhouse.grid_position),
		"The clubhouse is already there.")
	assert_eq(CourseClubhouse.move_error(grid, entities, clubhouse, Vector2i(38, 30)),
		"The whole clubhouse must fit on the course.")

	grid.set_tile(Vector2i(24, 8), TerrainTypes.Type.WATER)
	assert_eq(CourseClubhouse.move_error(grid, entities, clubhouse, Vector2i(24, 8)),
		"Move it off the greens, tees, sand and water.")
	var error := CourseClubhouse.move_error(grid, entities, clubhouse, Vector2i(24, 8))
	assert_false(error.is_empty())

	grid.set_tile(Vector2i(24, 8), TerrainTypes.Type.GRASS)
	var registry: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]
	var restroom = entities.place_building("restroom", Vector2i(25, 9), registry)
	assert_not_null(restroom, "The fixture's other building is placed")
	assert_eq(CourseClubhouse.move_error(grid, entities, clubhouse, Vector2i(24, 8)),
		"Move the footprint clear of the other building.")

	var decorations: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/decorations.json"))["decorations"]
	grid.set_tile(Vector2i(30, 20), TerrainTypes.Type.GRASS)
	entities.place_decoration("park_bench", Vector2i(30, 20), decorations)
	assert_eq(CourseClubhouse.move_error(grid, entities, clubhouse, Vector2i(30, 20)),
		"Remove the decoration in this footprint first.")

	grid.set_tile(Vector2i(34, 24), TerrainTypes.Type.GRASS)
	entities.place_tree(Vector2i(34, 24), "oak")
	assert_eq(CourseClubhouse.move_error(grid, entities, clubhouse, Vector2i(34, 24)),
		"Clear the tree first: paint another Course Terrain tile over it.")


func test_move_to_refuses_an_illegal_tile() -> void:
	grid.set_tile(Vector2i(24, 8), TerrainTypes.Type.WATER)
	var before := clubhouse.grid_position
	assert_false(CourseClubhouse.move_to(entities, clubhouse, Vector2i(24, 8)),
		"Moving onto water is refused")
	assert_eq(clubhouse.grid_position, before, "and the clubhouse does not budge")


# ---------------------------------------------------------------------------
# Never demolished
# ---------------------------------------------------------------------------

func test_remove_building_refuses_the_clubhouse() -> void:
	entities.remove_building(clubhouse.grid_position)
	assert_true(is_instance_valid(clubhouse), "The clubhouse survives the bulldozer")
	assert_true(CourseClubhouse.exists(entities), "and the course keeps its clubhouse")
	assert_true(entities.is_tile_occupied_by_building(clubhouse.grid_position))


func test_destroy_refuses_a_required_building_but_force_still_clears_it() -> void:
	clubhouse.destroy()
	assert_false(clubhouse.is_queued_for_deletion(),
		"destroy() alone never takes the clubhouse off the course")
	clubhouse.destroy(true)
	assert_true(clubhouse.is_queued_for_deletion(),
		"Teardown flows (clear_all) may force it off")


func test_optional_buildings_are_still_demolishable() -> void:
	var registry: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]
	var coffee = entities.place_building("coffee_house", Vector2i(30, 4), registry)
	entities.remove_building(coffee.grid_position)
	assert_true(coffee.is_queued_for_deletion(), "Only the clubhouse is protected")
