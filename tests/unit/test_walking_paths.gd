extends GutTest
## The Path improvement: a thin walking trail laid ON TOP of hostable ground
## (rough, deep rough, waste bunker, brush, rocks/boulders, stream, flower
## bed, trees) that connects dot-to-dot and is paved once it reaches the
## clubhouse.

var grid: TerrainGrid

func before_each() -> void:
	grid = TerrainGrid.new()
	grid.grid_width = 8
	grid.grid_height = 8
	add_child_autofree(grid)
	for x in range(8):
		for y in range(8):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.GRASS)

# ---------------------------------------------------------------------------
# Placement rules
# ---------------------------------------------------------------------------

func test_walking_paths_only_lay_on_hostable_ground() -> void:
	var hostable: Array = TerrainTypes.WALKING_PATH_TERRAINS
	for t in hostable:
		grid.set_tile(Vector2i(1, 1), t)
		assert_true(grid.can_place_walking_path(Vector2i(1, 1)),
				"%s should host a walking path" % TerrainTypes.get_type_name(t))
		assert_true(grid.set_walking_path(Vector2i(1, 1), true))
		grid.set_walking_path(Vector2i(1, 1), false)

	var unhostable: Array = [
		TerrainTypes.Type.EMPTY, TerrainTypes.Type.GRASS, TerrainTypes.Type.FAIRWAY,
		TerrainTypes.Type.FIRM_FAIRWAY, TerrainTypes.Type.HEAVY_ROUGH,
		TerrainTypes.Type.GREEN, TerrainTypes.Type.TEE_BOX, TerrainTypes.Type.BUNKER,
		TerrainTypes.Type.POT_BUNKER, TerrainTypes.Type.WATER,
		TerrainTypes.Type.PATH, TerrainTypes.Type.OUT_OF_BOUNDS,
	]
	for t in unhostable:
		grid.set_tile(Vector2i(2, 2), t)
		assert_false(grid.can_place_walking_path(Vector2i(2, 2)),
				"%s must not host a walking path" % TerrainTypes.get_type_name(t))
		assert_false(grid.set_walking_path(Vector2i(2, 2), true))

func test_placement_refuses_out_of_bounds_tiles() -> void:
	assert_false(grid.set_walking_path(Vector2i(99, 99), true))
	assert_false(grid.set_walking_path(Vector2i(-1, 0), true))
	assert_false(grid.can_place_walking_path(Vector2i(8, 0)))
	assert_ne(grid.walking_path_placement_error(Vector2i(99, 99)), "")

func test_set_walking_path_is_idempotent() -> void:
	grid.set_tile(Vector2i(3, 3), TerrainTypes.Type.ROUGH)
	watch_signals(grid)
	assert_true(grid.set_walking_path(Vector2i(3, 3), true))
	assert_false(grid.set_walking_path(Vector2i(3, 3), true), "A dot stays a dot")
	assert_signal_emit_count(grid, "walking_paths_changed", 1)
	assert_true(grid.set_walking_path(Vector2i(3, 3), false))
	assert_false(grid.set_walking_path(Vector2i(3, 3), false), "Nothing left to remove")
	assert_signal_emit_count(grid, "walking_paths_changed", 2)

func test_paths_do_not_change_the_tile_terrain() -> void:
	grid.set_tile(Vector2i(4, 4), TerrainTypes.Type.DEEP_ROUGH)
	grid.set_walking_path(Vector2i(4, 4), true)
	assert_eq(grid.get_tile(Vector2i(4, 4)), TerrainTypes.Type.DEEP_ROUGH)
	assert_true(grid.has_walking_path(Vector2i(4, 4)))

func test_painting_non_hostable_ground_removes_the_path() -> void:
	grid.set_tile(Vector2i(5, 5), TerrainTypes.Type.BRUSH)
	grid.set_walking_path(Vector2i(5, 5), true)
	watch_signals(grid)
	grid.set_tile(Vector2i(5, 5), TerrainTypes.Type.FAIRWAY)
	assert_false(grid.has_walking_path(Vector2i(5, 5)))
	assert_signal_emitted(grid, "walking_paths_changed")

func test_painting_more_hostable_ground_keeps_the_path() -> void:
	grid.set_tile(Vector2i(6, 6), TerrainTypes.Type.ROUGH)
	grid.set_walking_path(Vector2i(6, 6), true)
	grid.set_tile(Vector2i(6, 6), TerrainTypes.Type.DEEP_ROUGH)
	assert_true(grid.has_walking_path(Vector2i(6, 6)))

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func test_walking_paths_round_trip_through_save_data() -> void:
	grid.set_tile(Vector2i(1, 2), TerrainTypes.Type.ROUGH)
	grid.set_tile(Vector2i(2, 2), TerrainTypes.Type.ROUGH)
	grid.set_walking_path(Vector2i(1, 2), true)
	grid.set_walking_path(Vector2i(2, 2), true)
	var saved_paths := grid.serialize_walking_paths()
	assert_eq(saved_paths.size(), 2)

	grid.deserialize({})  # Everything back to grass: the trails' ground is gone.
	grid.deserialize_walking_paths(saved_paths)
	assert_eq(grid.get_walking_paths(), [], "Paths need hostable ground to survive")

	grid.set_tile(Vector2i(1, 2), TerrainTypes.Type.ROUGH)
	grid.set_tile(Vector2i(2, 2), TerrainTypes.Type.ROUGH)
	grid.deserialize_walking_paths(saved_paths)
	assert_eq(grid.get_walking_paths().size(), 2)
	assert_true(grid.has_walking_path(Vector2i(1, 2)))
	assert_true(grid.has_walking_path(Vector2i(2, 2)))

func test_paths_on_cleared_trees_are_dropped_on_load() -> void:
	grid.set_tile(Vector2i(3, 3), TerrainTypes.Type.TREES)
	grid.set_walking_path(Vector2i(3, 3), true)
	var saved_paths := grid.serialize_walking_paths()
	grid.set_tile(Vector2i(3, 3), TerrainTypes.Type.GRASS)  # Tree bulldozed.
	assert_false(grid.has_walking_path(Vector2i(3, 3)))
	grid.deserialize_walking_paths(saved_paths)
	assert_eq(grid.get_walking_paths(), [])

func test_reset_for_new_course_clears_walking_paths() -> void:
	grid.set_tile(Vector2i(2, 2), TerrainTypes.Type.ROUGH)
	grid.set_walking_path(Vector2i(2, 2), true)
	grid.reset_for_new_course()
	assert_eq(grid.get_walking_paths(), [])
	assert_eq(grid.serialize_walking_paths(), [])

# ---------------------------------------------------------------------------
# Clubhouse connection (the paved look)
# ---------------------------------------------------------------------------

## is_walkable over a plain dictionary of walkable tiles.
static func _walkable_of(walkable: Dictionary) -> Callable:
	return func(p: Vector2i) -> bool: return walkable.has(p)

func test_component_touching_clubhouse_is_upgraded() -> void:
	var paths := {Vector2i(0, 0): true, Vector2i(1, 0): true, Vector2i(2, 0): true}
	var walkable := _walkable_of(paths)
	var edges := {Vector2i(2, 0): true}  # Clubhouse footprint at (3, 0).
	var upgraded := WalkingPathOverlay.upgraded_component_tiles(paths, walkable, edges)
	assert_eq(upgraded.size(), 3, "The whole trail reaches the clubhouse")
	for pos in paths:
		assert_true(upgraded.has(pos), "Trail tile %s should be paved" % pos)

func test_disconnected_trail_stays_dirt() -> void:
	var paths := {Vector2i(0, 0): true, Vector2i(5, 5): true}
	var walkable := _walkable_of(paths)
	var edges := {Vector2i(5, 5): true}  # Clubhouse footprint at (6, 5).
	var upgraded := WalkingPathOverlay.upgraded_component_tiles(paths, walkable, edges)
	assert_false(upgraded.has(Vector2i(0, 0)))
	assert_true(upgraded.has(Vector2i(5, 5)))

func test_diagonal_contact_does_not_reach_the_clubhouse() -> void:
	var paths := {Vector2i(0, 0): true}
	var walkable := _walkable_of(paths)
	# Clubhouse footprint at (1, 1): its edge ring never includes (0, 0).
	var edges := {Vector2i(0, 1): true, Vector2i(1, 0): true}
	var upgraded := WalkingPathOverlay.upgraded_component_tiles(paths, walkable, edges)
	assert_eq(upgraded, {})

func test_cart_path_terrain_extends_the_connection() -> void:
	# Trail (0,0)-(0,1), then a full-tile cart path (0,2) touching the
	# clubhouse at (0,3): the dirt trail must be paved all the way back.
	var walkable := {
		Vector2i(0, 0): true, Vector2i(0, 1): true, Vector2i(0, 2): true,
	}
	var paths := {Vector2i(0, 0): true, Vector2i(0, 1): true}
	var edges := {Vector2i(0, 2): true}
	var upgraded := WalkingPathOverlay.upgraded_component_tiles(paths, _walkable_of(walkable), edges)
	assert_true(upgraded.has(Vector2i(0, 0)))
	assert_true(upgraded.has(Vector2i(0, 1)))

func test_only_the_trail_that_reaches_the_clubhouse_is_paved() -> void:
	# Two parallel trails; only one touches the clubhouse footprint at (2, 0).
	var paths := {
		Vector2i(0, 0): true, Vector2i(1, 0): true,   # Trail A (reaches the clubhouse)
		Vector2i(0, 3): true, Vector2i(1, 3): true,   # Trail B (no contact)
	}
	var walkable := _walkable_of(paths)
	var edges := {Vector2i(1, 0): true}
	var upgraded := WalkingPathOverlay.upgraded_component_tiles(paths, walkable, edges)
	assert_true(upgraded.has(Vector2i(0, 0)))
	assert_true(upgraded.has(Vector2i(1, 0)))
	assert_false(upgraded.has(Vector2i(0, 3)))
	assert_false(upgraded.has(Vector2i(1, 3)))

# ---------------------------------------------------------------------------
# Clubhouse edge discovery through a real entity layer
# ---------------------------------------------------------------------------

func test_clubhouse_edge_tiles_follow_the_footprint() -> void:
	var overlay: WalkingPathOverlay = grid.get_node_or_null("WalkingPathOverlay") as WalkingPathOverlay
	assert_not_null(overlay, "TerrainGrid must host the walking path overlay")

	var saved_entity_layer = GameManager.entity_layer
	var saved_grid = GameManager.terrain_grid
	GameManager.terrain_grid = grid
	var entities := EntityLayer.new()
	entities.set_terrain_grid(grid)
	add_child_autofree(entities)
	GameManager.entity_layer = entities

	var building := Building.new()
	building.building_type = "clubhouse"
	building.grid_position = Vector2i(4, 4)
	building.width = 2
	building.height = 2
	entities.buildings[Vector2i(4, 4)] = building

	var edges := overlay._clubhouse_edge_tiles()
	# The ring of tiles orthogonally around the 2x2 footprint.
	assert_true(edges.has(Vector2i(3, 4)), "West edge")
	assert_true(edges.has(Vector2i(4, 3)), "North edge")
	assert_true(edges.has(Vector2i(6, 5)), "Southeast corner ring")
	assert_false(edges.has(Vector2i(3, 3)), "Diagonal corners are not edges")
	assert_false(edges.has(Vector2i(2, 2)), "Unrelated tiles are not edges")

	GameManager.entity_layer = saved_entity_layer
	GameManager.terrain_grid = saved_grid

func test_building_signals_update_the_paved_state() -> void:
	var overlay: WalkingPathOverlay = grid.get_node_or_null("WalkingPathOverlay") as WalkingPathOverlay
	assert_not_null(overlay)

	var saved_entity_layer = GameManager.entity_layer
	var saved_grid = GameManager.terrain_grid
	GameManager.terrain_grid = grid
	var entities := EntityLayer.new()
	entities.set_terrain_grid(grid)
	add_child_autofree(entities)
	GameManager.entity_layer = entities

	# A trail with no clubhouse anywhere: dirt.
	grid.set_tile(Vector2i(0, 0), TerrainTypes.Type.ROUGH)
	grid.set_tile(Vector2i(1, 0), TerrainTypes.Type.ROUGH)
	grid.set_walking_path(Vector2i(0, 0), true)
	grid.set_walking_path(Vector2i(1, 0), true)
	assert_false(overlay._upgraded_tiles.has(Vector2i(0, 0)), "No clubhouse, no paving")

	# Placing a clubhouse at the trail's end paves the whole trail.
	var building := Building.new()
	building.building_type = "clubhouse"
	building.grid_position = Vector2i(2, 0)
	building.width = 1
	building.height = 1
	entities.buildings[Vector2i(2, 0)] = building
	entities.building_placed.emit(building, 0)
	assert_true(overlay._upgraded_tiles.has(Vector2i(0, 0)), "Placing the clubhouse paves the trail")
	assert_true(overlay._upgraded_tiles.has(Vector2i(1, 0)))

	# Removing it reverts the trail to dirt.
	entities.buildings.erase(Vector2i(2, 0))
	entities.building_removed.emit(Vector2i(2, 0))
	assert_false(overlay._upgraded_tiles.has(Vector2i(0, 0)), "Removing the clubhouse reverts to dirt")

	GameManager.entity_layer = saved_entity_layer
	GameManager.terrain_grid = saved_grid
