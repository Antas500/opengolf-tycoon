extends GutTest
## The potential hole the Green tool previews while a tee box waits: when it is
## shown, which tee it pairs with, the numbers it reports, and why a pair may not
## open yet (HoleLayout.potential_hole() / cup_site_blocker()).

var grid: TerrainGrid
var course: GameManager.CourseData
var _saved_land
var _saved_entities
var _saved_multi_tee: bool

func before_each() -> void:
	_saved_land = GameManager.land_manager
	_saved_entities = GameManager.entity_layer
	_saved_multi_tee = GameManager.multi_tee_enabled
	# Unit grids have no land parcels or entities: every tile can take a cup.
	GameManager.land_manager = null
	GameManager.entity_layer = null
	GameManager.multi_tee_enabled = false
	grid = TerrainGrid.new()
	grid.grid_width = 32
	grid.grid_height = 32
	add_child_autofree(grid)
	course = GameManager.CourseData.new()

func after_each() -> void:
	GameManager.land_manager = _saved_land
	GameManager.entity_layer = _saved_entities
	GameManager.multi_tee_enabled = _saved_multi_tee

func _paint_tee(pos: Vector2i) -> void:
	grid.set_tile(pos, TerrainTypes.Type.TEE_BOX)

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

func _potential(cup: Vector2i, tool: int = TerrainTypes.Type.GREEN) -> Dictionary:
	return HoleLayout.potential_hole(tool, grid, course, cup)

# --- When the potential hole exists ---

func test_shown_for_the_green_tool_while_a_tee_waits() -> void:
	_paint_tee(Vector2i(2, 2))
	var hole := _potential(Vector2i(12, 2))
	assert_false(hole.is_empty(), "Green With Hole + waiting tee shows the path")
	assert_eq(hole.tee, Vector2i(2, 2))
	assert_eq(hole.cup, Vector2i(12, 2))

func test_hidden_without_a_waiting_tee() -> void:
	assert_eq(_potential(Vector2i(12, 2)), {}, "No tee box on the course")
	_paint_tee(Vector2i(2, 2))
	_paint_green_with_cup(Vector2i(20, 2))
	_make_hole(Vector2i(2, 2), Vector2i(20, 2))
	grid.remove_cup_tile(Vector2i(20, 2))  # Opening the hole consumed the cup.
	assert_eq(_potential(Vector2i(12, 12)), {}, "The only tee box already belongs to a hole")

func test_hidden_once_the_cup_is_placed() -> void:
	_paint_tee(Vector2i(2, 2))
	_paint_green_with_cup(Vector2i(12, 2))
	assert_eq(_potential(Vector2i(20, 8)), {},
			"A cup is waiting, so the Green tool paints a Green Without Hole")

func test_hidden_for_every_other_tool() -> void:
	_paint_tee(Vector2i(2, 2))
	for tool in [TerrainTypes.Type.TEE_BOX, TerrainTypes.Type.FAIRWAY,
			TerrainTypes.Type.BUNKER, TerrainTypes.Type.ROUGH, -1]:
		assert_eq(_potential(Vector2i(12, 2), tool), {}, "tool %d shows no hole path" % tool)

func test_hidden_off_the_grid() -> void:
	_paint_tee(Vector2i(2, 2))
	assert_eq(_potential(Vector2i(-1, 4)), {})
	assert_eq(_potential(Vector2i(4, 32)), {})

# --- What it reports ---

func test_reports_the_numbers_open_hole_will_use() -> void:
	_paint_tee(Vector2i(2, 2))
	var par3 := _potential(Vector2i(10, 2))  # 8 tiles
	assert_eq(par3.distance_yards, 176)
	assert_eq(par3.par, 3)
	assert_eq(par3.distance_yards, grid.calculate_distance_yards(Vector2i(2, 2), Vector2i(10, 2)))
	assert_eq(par3.par, HoleCreationTool.calculate_par(par3.distance_yards))
	assert_true(par3.ready, par3.reason)
	assert_eq(par3.reason, "")
	assert_true(par3.can_cut_cup)

	assert_eq(_potential(Vector2i(17, 2)).par, 4, "15 tiles = 330 yds")
	assert_eq(_potential(Vector2i(25, 2)).par, 5, "23 tiles = 506 yds")

func test_numbers_the_hole_after_the_existing_ones() -> void:
	_paint_tee(Vector2i(2, 2))
	assert_eq(_potential(Vector2i(12, 2)).hole_number, 1)

	_paint_green_with_cup(Vector2i(12, 2))
	_make_hole(Vector2i(2, 2), Vector2i(12, 2))
	grid.remove_cup_tile(Vector2i(12, 2))
	_paint_tee(Vector2i(2, 20))
	var second := _potential(Vector2i(14, 20))
	assert_eq(second.tee, Vector2i(2, 20), "Pairs with the new tee, not hole 1's")
	assert_eq(second.hole_number, 2)

func test_too_short_is_shown_but_not_ready() -> void:
	_paint_tee(Vector2i(2, 2))
	var short := _potential(Vector2i(5, 2))  # 3 tiles = 66 yds
	assert_false(short.is_empty(), "The path still follows the cursor")
	assert_eq(short.distance_yards, 66)
	assert_false(short.ready)
	assert_true(short.can_cut_cup, "The cup can be cut — Open Hole just refuses the pair")
	assert_string_contains(short.reason, "110")

func test_minimum_distance_is_the_open_hole_minimum() -> void:
	_paint_tee(Vector2i(2, 2))
	assert_true(_potential(Vector2i(7, 2)).ready, "Exactly MIN_HOLE_TILES apart opens")
	assert_false(_potential(Vector2i(6, 2)).ready)
	assert_eq(HoleLayout.min_hole_yards(), 110)

func test_matches_open_hole_request_once_the_cup_is_cut() -> void:
	_paint_tee(Vector2i(2, 2))
	for cup in [Vector2i(4, 3), Vector2i(12, 2), Vector2i(20, 20)]:
		var predicted := _potential(cup)
		_paint_green_with_cup(cup)
		var request := HoleLayout.open_hole_request(grid, course)
		assert_eq(predicted.ready, request.ready, "prediction for %s" % cup)
		assert_eq(request.tee, predicted.tee)
		grid.set_tile(cup, TerrainTypes.Type.GRASS)  # Undo the cup for the next pair.

func test_pairs_with_the_nearest_of_several_waiting_tees() -> void:
	# Legacy saves and deleted holes can leave more than one tee box waiting.
	_paint_tee(Vector2i(2, 2))
	_paint_tee(Vector2i(2, 28))
	var near_bottom := _potential(Vector2i(14, 26))
	assert_eq(near_bottom.tee, Vector2i(2, 28))
	assert_false(near_bottom.ready, "Open Hole refuses while two tees wait")
	assert_string_contains(near_bottom.reason, "2 tee boxes")
	assert_eq(_potential(Vector2i(14, 4)).tee, Vector2i(2, 2))

# --- Where a cup can be cut ---

func test_cannot_cut_a_cup_into_existing_green() -> void:
	_paint_tee(Vector2i(2, 2))
	grid.set_tile(Vector2i(14, 2), TerrainTypes.Type.GREEN)  # Plain green, no cup.
	var hole := _potential(Vector2i(14, 2))
	assert_false(hole.is_empty())
	assert_false(hole.can_cut_cup, "Painting green over green changes nothing")
	assert_false(hole.ready)
	assert_string_contains(hole.reason, "green")

func test_cannot_cut_a_cup_on_land_the_player_does_not_own() -> void:
	var land := LandManager.new()
	add_child_autofree(land)  # _ready() grants the central starting parcels.
	GameManager.land_manager = land
	var big := TerrainGrid.new()
	big.grid_width = 96
	big.grid_height = 96
	add_child_autofree(big)
	var owned := Vector2i(50, 50)
	var unowned := Vector2i(10, 10)
	assert_true(land.is_tile_owned(owned))
	assert_false(land.is_tile_owned(unowned))
	assert_eq(HoleLayout.cup_site_blocker(big, owned), "")
	assert_string_contains(HoleLayout.cup_site_blocker(big, unowned), "own")

	big.set_tile(Vector2i(50, 60), TerrainTypes.Type.TEE_BOX)
	var blocked := HoleLayout.potential_hole(TerrainTypes.Type.GREEN, big, course, unowned)
	assert_false(blocked.is_empty(), "The path still follows the cursor onto unowned land")
	assert_false(blocked.can_cut_cup)
	assert_false(blocked.ready)
	var open := HoleLayout.potential_hole(TerrainTypes.Type.GREEN, big, course, owned)
	assert_true(open.ready, open.reason)

func test_cup_site_blocker_on_open_ground() -> void:
	assert_eq(HoleLayout.cup_site_blocker(grid, Vector2i(8, 8)), "")
	assert_string_contains(HoleLayout.cup_site_blocker(grid, Vector2i(-3, 8)), "Off")
	assert_string_contains(HoleLayout.cup_site_blocker(null, Vector2i(8, 8)), "Off")

# --- Multi-tee: the forward/middle tees Open Hole will paint ---

func test_no_extra_tees_while_multi_tee_is_off() -> void:
	_paint_tee(Vector2i(2, 2))
	assert_eq(_potential(Vector2i(22, 2)).extra_tees, {})

func test_extra_tees_match_what_open_hole_paints() -> void:
	GameManager.multi_tee_enabled = true
	_paint_tee(Vector2i(2, 2))
	var hole := _potential(Vector2i(22, 2))
	assert_eq(hole.extra_tees.get("forward"), Vector2i(10, 2), "40% of the way to the cup")
	assert_eq(hole.extra_tees.get("middle"), Vector2i(7, 2), "25% of the way to the cup")

	var built := GameManager.HoleData.new()
	built.tee_position = Vector2i(2, 2)
	built.green_position = Vector2i(22, 2)
	built.auto_generate_tee_positions(grid)
	assert_eq(hole.extra_tees.get("forward"), built.tee_positions.forward)
	assert_eq(hole.extra_tees.get("middle"), built.tee_positions.middle)
