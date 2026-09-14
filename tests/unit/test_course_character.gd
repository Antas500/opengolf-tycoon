extends GutTest
var grid: TerrainGrid
var previous_land
var previous_pause: bool
var previous_speed: int

func before_each() -> void:
	previous_land = GameManager.land_manager
	GameManager.land_manager = null
	previous_pause = GameManager.is_paused
	previous_speed = GameManager.current_speed
	GameManager.is_paused = false
	GameManager.current_speed = GameManager.GameSpeed.NORMAL
	grid = TerrainGrid.new()
	grid.grid_width = 16
	grid.grid_height = 16
	add_child_autofree(grid)
	for x in range(16):
		for y in range(16):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.GRASS)

func after_each() -> void:
	GameManager.land_manager = previous_land
	GameManager.is_paused = previous_pause
	GameManager.current_speed = previous_speed

func test_vertex_selector_moves_single_vertex_and_nothing_else() -> void:
	var tool := ElevationTool.new()
	add_child_autofree(tool)
	tool.start_vertex_selector()
	assert_true(tool.is_active())
	# Right-click raises exactly one vertex.
	var changes := tool.paint_vertex(Vector2i(8, 8), grid, true)
	assert_eq(changes.size(), 1)
	assert_eq(changes[0]["position"], Vector2i(8, 8))
	assert_eq(changes[0]["old_elevation"], 0)
	assert_eq(changes[0]["new_elevation"], 1)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), 1)
	for neighbour in [Vector2i(7, 8), Vector2i(9, 8), Vector2i(8, 7), Vector2i(8, 9),
			Vector2i(7, 7), Vector2i(9, 9)]:
		assert_eq(grid.get_vertex_elevation(neighbour), 0)
	# Left-click lowers it back.
	changes = tool.paint_vertex(Vector2i(8, 8), grid, false)
	assert_eq(changes.size(), 1)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), 0)
	# paint_at_point routes through the active selector.
	changes = tool.paint_at_point(Vector2(8.2, 7.8), grid, true)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), 1)
	# Height limits clamp without recording no-op changes.
	grid.set_vertex_elevation(Vector2i(8, 8), TerrainGrid.MAX_ELEVATION)
	assert_true(tool.paint_vertex(Vector2i(8, 8), grid, true).is_empty())
	grid.set_vertex_elevation(Vector2i(8, 8), TerrainGrid.MIN_ELEVATION)
	assert_true(tool.paint_vertex(Vector2i(8, 8), grid, false).is_empty())
	# Undo round-trips through serialization.
	var heights := grid.serialize_elevation()
	grid.deserialize_elevation(heights)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), TerrainGrid.MIN_ELEVATION)
	grid.deserialize_elevation({})
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), 0)
	# An inactive tool paints nothing.
	tool.cancel()
	assert_false(tool.is_active())
	assert_true(tool.paint_vertex(Vector2i(8, 8), grid, true).is_empty())
	assert_true(tool.paint_at_point(Vector2(8.0, 8.0), grid, true).is_empty())

func test_square_selector_levels_then_lifts_and_lowers() -> void:
	var tool := ElevationTool.new()
	add_child_autofree(tool)
	tool.start_square_selector()
	var tile := Vector2i(4, 4)
	var corners: Array[Vector2i] = grid.vertices_of_tile(tile)
	grid.set_vertex_elevation(corners[0], 0)
	grid.set_vertex_elevation(corners[1], 0)
	grid.set_vertex_elevation(corners[2], 1)
	grid.set_vertex_elevation(corners[3], 2)
	# Raising lifts only the lowest corners until the square is even.
	var changes := tool.paint_square(tile, grid, true)
	assert_eq(changes.size(), 2)
	assert_eq(_corner_heights(tile), [1, 1, 1, 2])
	changes = tool.paint_square(tile, grid, true)
	assert_eq(changes.size(), 3)
	assert_eq(_corner_heights(tile), [2, 2, 2, 2])
	# Once even, the whole square rises together.
	changes = tool.paint_square(tile, grid, true)
	assert_eq(changes.size(), 4)
	assert_eq(_corner_heights(tile), [3, 3, 3, 3])
	# Lowering an even square drops it together.
	changes = tool.paint_square(tile, grid, false)
	assert_eq(changes.size(), 4)
	assert_eq(_corner_heights(tile), [2, 2, 2, 2])
	# Lowering an uneven square drops only the highest corner(s).
	grid.set_vertex_elevation(corners[3], 4)
	changes = tool.paint_square(tile, grid, false)
	assert_eq(changes.size(), 1)
	assert_eq(_corner_heights(tile), [2, 2, 2, 3])
	# Neighbouring vertices outside the square are never touched.
	assert_eq(grid.get_vertex_elevation(Vector2i(3, 4)), 0)
	assert_eq(grid.get_vertex_elevation(Vector2i(6, 5)), 0)
	# paint_at_point routes tile centres to the square selector.
	changes = tool.paint_at_point(Vector2(4.5, 4.5), grid, true)
	assert_eq(_corner_heights(tile), [3, 3, 3, 3])
	# square_targets previews exactly the corners paint would move.
	assert_eq(ElevationTool.square_targets(tile, grid, true).size(), 4)
	assert_eq(ElevationTool.square_targets(tile, grid, false).size(), 4)
	# A square parked at the height limit does not move.
	for corner in corners:
		grid.set_vertex_elevation(corner, TerrainGrid.MAX_ELEVATION)
	assert_true(tool.paint_square(tile, grid, true).is_empty())
	for corner in corners:
		grid.set_vertex_elevation(corner, TerrainGrid.MIN_ELEVATION)
	assert_true(tool.paint_square(tile, grid, false).is_empty())

func test_square_selector_respects_buildings() -> void:
	var entities := EntityLayer.new()
	entities.map_seed = 1234
	add_child_autofree(entities)
	entities.set_terrain_grid(grid)
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]
	entities.place_building("clubhouse", Vector2i(6, 6), registry)
	var tool := ElevationTool.new()
	add_child_autofree(tool)
	tool.start_square_selector()
	var pinned := tool.paint_square(Vector2i(7, 7), grid, true, entities)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), 0)
	assert_lt(pinned.size(), 4)
	# Just outside the footprint the same tool still lifts the ground.
	var free := tool.paint_square(Vector2i(3, 7), grid, true, entities)
	assert_eq(free.size(), 4)
	assert_eq(grid.get_vertex_elevation(Vector2i(3, 7)), 1)
	tool.start_vertex_selector()
	assert_true(tool.paint_vertex(Vector2i(8, 8), grid, true, entities).is_empty())
	assert_eq(tool.paint_vertex(Vector2i(5, 8), grid, true, entities).size(), 1)

func test_cliff_helpers_measure_steps_and_edges() -> void:
	grid.set_vertex_elevation(Vector2i(5, 5), 4)
	assert_eq(grid.get_tile_corner_step(Vector2i(5, 5)), 4)
	assert_true(grid.is_cliff_tile(Vector2i(5, 5)))
	grid.set_vertex_elevation(Vector2i(5, 5), 1)
	assert_eq(grid.get_tile_corner_step(Vector2i(5, 5)), 1)
	assert_false(grid.is_cliff_tile(Vector2i(5, 5)))
	assert_true(grid.get_cliff_edges(Vector2i(5, 5)).is_empty())
	# A raised plateau tile drops away on all four sides.
	for corner in grid.vertices_of_tile(Vector2i(10, 10)):
		grid.set_vertex_elevation(corner, 4)
	assert_eq(grid.get_cliff_edges(Vector2i(10, 10)), [0, 1, 2, 3])
	assert_true(grid.is_cliff_tile(Vector2i(10, 10)))
	assert_false(grid.is_cliff_tile(Vector2i(0, 0)))

func test_plateau_stamp_creates_flat_top_with_cliff_rim() -> void:
	NaturalTerrainGenerator.stamp_plateau(grid, Vector2i(8, 8), 4.0, 3)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), 3)
	assert_eq(grid.get_vertex_elevation(Vector2i(7, 7)), 3)
	assert_eq(grid.get_vertex_elevation(Vector2i(9, 8)), 3)
	assert_eq(_corner_heights(Vector2i(7, 7)), [3, 3, 3, 3])
	assert_eq(grid.get_vertex_elevation(Vector2i(2, 2)), 0)
	assert_eq(grid.get_vertex_elevation(Vector2i(14, 14)), 0)
	var found_cliff := false
	for x in range(16):
		for y in range(16):
			if grid.is_cliff_tile(Vector2i(x, y)):
				found_cliff = true
	assert_true(found_cliff)
	assert_false(grid.is_cliff_tile(Vector2i(7, 7)))
	NaturalTerrainGenerator.stamp_plateau(grid, Vector2i(3, 3), 2.0, -3)
	assert_eq(grid.get_vertex_elevation(Vector2i(3, 3)), -3)

func _corner_heights(tile: Vector2i) -> Array:
	var heights: Array = []
	for corner in grid.vertices_of_tile(tile):
		heights.append(grid.get_vertex_elevation(corner))
	return heights

func test_clubhouse_upgrades_grow_without_changing_footprint_or_duplicate_clicks() -> void:
	var building := Building.new()
	add_child_autofree(building)
	var previous_width := 0.0
	for level in range(1, 4):
		building.upgrade_level = level
		building._update_visuals()
		assert_eq(building.get_node("Visual/Architecture").level, level)
		var architecture = building.get_node("Visual/Architecture")
		var body_width := CourseArchitecture.body_width("clubhouse", architecture.footprint, level)
		assert_gt(body_width, previous_width)
		assert_lt(body_width, architecture.footprint.x)
		assert_eq(architecture.footprint, Vector2(256, 128))
		previous_width = body_width
		var clicks := 0
		var visuals := 0
		for child in building.get_children():
			if child is Area2D: clicks += 1
			if child.name == "Visual": visuals += 1
		assert_eq(clicks, 1)
		assert_eq(visuals, 1)
		await get_tree().process_frame

func test_golfer_expression_does_not_move_actor_or_delay_next_shot() -> void:
	var golfer = load("res://scenes/entities/golfer.tscn").instantiate()
	add_child_autofree(golfer)
	golfer.set_process(false)
	var expression: GolferExpression = golfer._expression
	expression.set_process(false)
	var position_before: Vector2 = golfer.position
	var score_before: int = golfer.current_strokes
	expression.react_to_score(-1)
	expression._process(0.1)
	assert_lt(expression.position.y, 0.0)
	assert_eq(golfer.position, position_before)
	assert_eq(golfer.current_strokes, score_before)
	GameManager.is_paused = true
	var remaining := expression._reaction_remaining
	expression._process(1.0)
	assert_eq(expression._reaction_remaining, remaining)
	GameManager.is_paused = false
	golfer.current_state = Golfer.State.PREPARING_SHOT
	expression._process(0.1)
	assert_eq(expression._reaction_remaining, 0.0)
	assert_eq(golfer.preparation_time, 0.0)
	assert_eq(GolferExpression.reaction_for_score(2), -1)
	assert_eq(GolferExpression.reaction_for_score(0), 0)

func test_building_ghost_matches_facility_and_clears_when_preview_ends() -> void:
	var manager := PlacementManager.new()
	add_child_autofree(manager)
	manager.selected_building_type = "restaurant"
	manager.current_placement_data = {"size": {"width": 3, "height": 3}}
	var preview := PlacementPreview.new()
	add_child_autofree(preview)
	preview.set_process(false)
	preview.placement_manager = manager
	preview._draw_building_ghost(Vector2(120, 80), Color(0.3, 0.9, 0.3, 0.4))
	assert_eq(preview._building_ghost.kind, "restaurant")
	assert_eq(preview._building_ghost.position, Vector2(120, 80))
	assert_almost_eq(preview._building_ghost.modulate.a, 0.4, 0.001)
	assert_true(preview._building_ghost.visible)
	# With no terrain/active preview, drawing must hide the previous building.
	preview._draw()
	assert_false(preview._building_ghost.visible)
