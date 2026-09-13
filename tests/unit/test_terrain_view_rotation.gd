extends GutTest
## TerrainGrid view rotation - the SimGolf-style rotate controls end to end.
##
## These cover the contract the rest of the game depends on: rotating the view
## changes only how the course is drawn, never the course data, and mouse
## picking keeps landing on the tile under the cursor at every orientation.

var grid: TerrainGrid

func before_each() -> void:
	grid = TerrainGrid.new()
	grid.grid_width = 16
	grid.grid_height = 16
	grid.tile_width = 64
	grid.tile_height = 32
	grid.view_isometric = true
	grid.view_orientation = 0
	add_child_autofree(grid)
	watch_signals(grid)

# =============================================================================
# PICKING STAYS CORRECT AT EVERY ORIENTATION
# =============================================================================

func test_tile_centre_picks_back_to_the_same_tile_at_every_orientation() -> void:
	for orientation in range(4):
		grid.set_view_orientation(orientation)
		for cell in [Vector2i(0, 0), Vector2i(3, 11), Vector2i(15, 15), Vector2i(7, 2)]:
			var center := grid.grid_to_screen_center(cell)
			assert_eq(grid.screen_to_grid(center), cell,
					"%s at orientation %d" % [cell, orientation])

func test_picking_works_in_top_down_mode_too() -> void:
	grid.set_view_isometric(false)
	for orientation in range(4):
		grid.set_view_orientation(orientation)
		var cell := Vector2i(9, 4)
		assert_eq(grid.screen_to_grid(grid.grid_to_screen_center(cell)), cell)

func test_paint_brush_tiles_are_where_the_player_clicked() -> void:
	# Regression guard: a rotate that broke unproject() would silently paint the
	# wrong tiles while the preview showed the right ones.
	grid.set_view_orientation(2)
	var target := Vector2i(5, 12)
	var clicked := grid.grid_to_screen_center(target)
	var brush := grid.get_brush_tiles(grid.screen_to_grid(clicked), 3)
	assert_has(brush, target)
	assert_eq(brush.size(), 9)

# =============================================================================
# ROTATION IS A VIEW CHANGE, NOT A DATA CHANGE
# =============================================================================

func test_rotating_does_not_alter_terrain_data() -> void:
	grid.set_tile(Vector2i(2, 3), TerrainTypes.Type.BUNKER)
	grid.set_tile(Vector2i(9, 9), TerrainTypes.Type.WATER)
	grid.set_elevation(Vector2i(4, 4), 3)
	var terrain_before := grid.serialize()
	var elevation_before := grid.serialize_elevation()

	grid.rotate_view_cw()
	grid.rotate_view_cw()

	assert_eq(grid.serialize(), terrain_before)
	assert_eq(grid.serialize_elevation(), elevation_before)
	assert_eq(grid.get_tile(Vector2i(2, 3)), TerrainTypes.Type.BUNKER)
	assert_eq(grid.get_elevation(Vector2i(4, 4)), 3)

func test_rotate_emits_view_rotated_with_the_new_orientation() -> void:
	grid.rotate_view_cw()
	assert_signal_emitted(grid, "view_rotated")
	assert_eq(grid.get_view_orientation(), 1)
	grid.rotate_view_ccw()
	assert_eq(grid.get_view_orientation(), 0)

func test_orientation_wraps_in_both_directions() -> void:
	grid.rotate_view_ccw()
	assert_eq(grid.get_view_orientation(), 3)
	grid.rotate_view_cw()
	assert_eq(grid.get_view_orientation(), 0)

func test_isometric_toggle_flips_layout_and_back() -> void:
	assert_true(grid.is_view_isometric())
	grid.set_view_isometric(false)
	assert_false(grid.is_view_isometric())
	grid.set_view_isometric(true)
	assert_true(grid.is_view_isometric())

# =============================================================================
# WORLD BOUNDS / CAMERA
# =============================================================================

func test_world_bounds_stay_put_across_rotations() -> void:
	var first := grid.world_bounds()
	for orientation in range(4):
		grid.set_view_orientation(orientation)
		var bounds := grid.world_bounds()
		assert_eq(bounds.position, first.position)
		assert_eq(bounds.size, first.size)

func test_visible_tile_range_stays_inside_the_grid_when_rotated() -> void:
	grid.set_view_orientation(1)
	var tile_range := grid.get_visible_tile_range()
	var min_tile: Vector2i = tile_range[0]
	var max_tile: Vector2i = tile_range[1]
	assert_gte(min_tile.x, 0)
	assert_gte(min_tile.y, 0)
	assert_lte(max_tile.x, grid.grid_width - 1)
	assert_lte(max_tile.y, grid.grid_height - 1)
	assert_lte(min_tile.x, max_tile.x)
	assert_lte(min_tile.y, max_tile.y)

# =============================================================================
# SURFACE / SHADER PLUMBING
# =============================================================================

func test_course_surface_receives_the_projection_terms() -> void:
	# The terrain shader inverts these to find grid coordinates; if they are
	# missing or stale the course renders blank or sheared.
	var surface := grid._course_surface
	assert_not_null(surface)
	var mat := surface.material as ShaderMaterial
	assert_not_null(mat)
	grid.set_view_orientation(3)
	var axis_x: Vector2 = mat.get_shader_parameter("grid_axis_x")
	assert_eq(axis_x, grid.projection.axis_x())
	var axis_y: Vector2 = mat.get_shader_parameter("grid_axis_y")
	assert_eq(axis_y, grid.projection.axis_y())
	var origin: Vector2 = mat.get_shader_parameter("grid_origin")
	assert_eq(origin, grid.projection.grid_origin())

func test_elevation_rect_is_resized_to_the_projected_bounds() -> void:
	grid.set_view_orientation(2)
	var rect := grid._elevation_shader_rect
	assert_not_null(rect)
	var bounds := grid.world_bounds()
	assert_eq(rect.position, bounds.position)
	assert_eq(rect.size, bounds.size)
