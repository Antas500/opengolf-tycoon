extends GutTest
## Terrain grid state behind the new hole workflow: which tiles carry a cup
## ("Green With Hole") and which tee boxes are waiting.

var grid: TerrainGrid

func before_each() -> void:
	grid = TerrainGrid.new()
	grid.grid_width = 8
	grid.grid_height = 8
	add_child_autofree(grid)

func test_a_cup_can_only_be_cut_into_a_green() -> void:
	assert_false(grid.add_cup_tile(Vector2i(1, 1)), "Grass cannot carry a cup")
	grid.set_tile(Vector2i(1, 1), TerrainTypes.Type.GREEN)
	assert_true(grid.add_cup_tile(Vector2i(1, 1)))
	assert_true(grid.has_cup_tile(Vector2i(1, 1)))
	assert_false(grid.add_cup_tile(Vector2i(1, 1)), "A tile carries at most one cup")
	assert_false(grid.add_cup_tile(Vector2i(99, 99)), "Off-grid tiles are rejected")

func test_painting_over_a_cup_removes_it() -> void:
	grid.set_tile(Vector2i(2, 2), TerrainTypes.Type.GREEN)
	grid.add_cup_tile(Vector2i(2, 2))
	watch_signals(grid)

	grid.set_tile(Vector2i(2, 2), TerrainTypes.Type.BUNKER)
	assert_false(grid.has_cup_tile(Vector2i(2, 2)))
	assert_signal_emitted(grid, "cup_tiles_changed")

func test_painting_more_green_keeps_the_cup() -> void:
	grid.set_tile(Vector2i(3, 3), TerrainTypes.Type.GREEN)
	grid.add_cup_tile(Vector2i(3, 3))
	grid.set_tile(Vector2i(3, 4), TerrainTypes.Type.GREEN)
	assert_true(grid.has_cup_tile(Vector2i(3, 3)))
	assert_eq(grid.get_cup_tiles(), [Vector2i(3, 3)])

func test_cup_tiles_round_trip_through_save_data() -> void:
	grid.set_tile(Vector2i(4, 4), TerrainTypes.Type.GREEN)
	grid.add_cup_tile(Vector2i(4, 4))
	var saved_terrain := grid.serialize()
	var saved_cups := grid.serialize_cup_tiles()
	assert_eq(saved_cups, ["4,4"])

	grid.set_tile(Vector2i(4, 4), TerrainTypes.Type.WATER)
	assert_false(grid.has_cup_tile(Vector2i(4, 4)))

	grid.deserialize(saved_terrain)
	grid.deserialize_cup_tiles(saved_cups)
	assert_true(grid.has_cup_tile(Vector2i(4, 4)))

func test_a_cup_on_a_tile_that_is_no_longer_green_is_dropped_on_load() -> void:
	grid.set_tile(Vector2i(5, 5), TerrainTypes.Type.GREEN)
	grid.add_cup_tile(Vector2i(5, 5))
	var saved_cups := grid.serialize_cup_tiles()
	grid.deserialize({})  # Everything back to grass
	grid.deserialize_cup_tiles(saved_cups)
	assert_eq(grid.get_cup_tiles(), [])

func test_tee_box_index_tracks_painting() -> void:
	assert_eq(grid.get_tee_box_tiles(), [])
	grid.set_tile(Vector2i(1, 2), TerrainTypes.Type.TEE_BOX)
	grid.set_tile(Vector2i(3, 4), TerrainTypes.Type.TEE_BOX)
	assert_eq(grid.get_tee_box_tiles().size(), 2)

	grid.set_tile(Vector2i(1, 2), TerrainTypes.Type.FAIRWAY)
	assert_eq(grid.get_tee_box_tiles(), [Vector2i(3, 4)])

func test_tee_box_index_survives_a_load() -> void:
	grid.set_tile(Vector2i(6, 6), TerrainTypes.Type.TEE_BOX)
	var saved := grid.serialize()
	grid.deserialize({})
	assert_eq(grid.get_tee_box_tiles(), [])
	grid.deserialize(saved)
	assert_eq(grid.get_tee_box_tiles(), [Vector2i(6, 6)])
func test_reset_for_new_course_clears_every_per_tile_state() -> void:
	grid.set_tile(Vector2i(2, 2), TerrainTypes.Type.TEE_BOX)
	grid.set_tile(Vector2i(3, 3), TerrainTypes.Type.GREEN)
	grid.add_cup_tile(Vector2i(3, 3))
	grid.set_tile(Vector2i(4, 4), TerrainTypes.Type.BUNKER)
	grid.set_bunker_depth(Vector2i(4, 4), 1)
	grid.set_vertex_elevation(Vector2i(5, 5), 4)

	grid.reset_for_new_course()

	assert_eq(grid.get_tee_box_tiles(), [], "Waiting tee boxes must not survive")
	assert_eq(grid.get_cup_tiles(), [], "Waiting cups must not survive")
	assert_eq(grid.serialize_player_placed(), [], "Player-placed marks must not survive")
	assert_eq(grid.serialize_bunker_depth(), {}, "Bunker depths must not survive")
	assert_eq(grid.get_vertex_elevation(Vector2i(5, 5)), 0, "Sculpted elevation must not survive")
	assert_eq(grid.get_tile(Vector2i(2, 2)), TerrainTypes.Type.GRASS)
	assert_eq(grid.get_tile(Vector2i(3, 3)), TerrainTypes.Type.GRASS)
