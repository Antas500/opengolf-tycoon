extends GutTest
## Tests for vertex-based terrain graphics displacement and slope visualization.

var grid: TerrainGrid

func before_each() -> void:
	grid = TerrainGrid.new()
	grid.grid_width = 16
	grid.grid_height = 16
	add_child_autofree(grid)

func test_vertex_elevation_displacement_in_isometric_view() -> void:
	assert_true(grid.view_isometric)
	assert_gt(grid.ELEVATION_STEP_Y, 0.0)

	var v_flat := Vector2i(5, 5)
	grid.set_vertex_elevation(v_flat, 0)
	var disp_flat := grid.get_vertex_elevation_displacement(v_flat)
	assert_eq(disp_flat, Vector2.ZERO)

	var v_high := Vector2i(6, 6)
	grid.set_vertex_elevation(v_high, 3)
	var disp_high := grid.get_vertex_elevation_displacement(v_high)
	assert_eq(disp_high.x, 0.0)
	assert_eq(disp_high.y, -3.0 * grid.ELEVATION_STEP_Y)

	var v_low := Vector2i(7, 7)
	grid.set_vertex_elevation(v_low, -2)
	var disp_low := grid.get_vertex_elevation_displacement(v_low)
	assert_eq(disp_low.x, 0.0)
	assert_eq(disp_low.y, 2.0 * grid.ELEVATION_STEP_Y)

func test_grid_point_to_screen_moves_with_elevation() -> void:
	var v := Vector2i(4, 4)
	grid.set_vertex_elevation(v, 0)
	var flat_screen: Vector2 = grid.grid_point_to_screen(Vector2(v))

	grid.set_vertex_elevation(v, 2)
	var raised_screen: Vector2 = grid.grid_point_to_screen(Vector2(v))
	assert_eq(raised_screen.x, flat_screen.x)
	assert_almost_eq(raised_screen.y, flat_screen.y - 2.0 * grid.ELEVATION_STEP_Y, 0.01)

	grid.set_vertex_elevation(v, -3)
	var lowered_screen: Vector2 = grid.grid_point_to_screen(Vector2(v))
	assert_eq(lowered_screen.x, flat_screen.x)
	assert_almost_eq(lowered_screen.y, flat_screen.y + 3.0 * grid.ELEVATION_STEP_Y, 0.01)

func test_tile_polygon_corners_reflect_varying_vertex_heights() -> void:
	# Tile at (3, 3) has corners at (3,3), (4,3), (4,4), (3,4)
	grid.set_vertex_elevation(Vector2i(3, 3), 0)
	grid.set_vertex_elevation(Vector2i(4, 3), 2)
	grid.set_vertex_elevation(Vector2i(4, 4), 4)
	grid.set_vertex_elevation(Vector2i(3, 4), 1)

	var poly := grid.tile_polygon(Vector2i(3, 3))
	assert_eq(poly.size(), 4)

	var c0 := grid.grid_point_to_screen(Vector2(3, 3))
	var c1 := grid.grid_point_to_screen(Vector2(4, 3))
	var c2 := grid.grid_point_to_screen(Vector2(4, 4))
	var c3 := grid.grid_point_to_screen(Vector2(3, 4))

	assert_almost_eq(poly[0].y, c0.y, 0.01)
	assert_almost_eq(poly[1].y, c1.y, 0.01)
	assert_almost_eq(poly[2].y, c2.y, 0.01)
	assert_almost_eq(poly[3].y, c3.y, 0.01)

	# Verify slopes are evident between corners
	assert_lt(poly[2].y, poly[0].y, "Higher elevation corner should be higher on screen (smaller Y)")

func test_screen_to_grid_point_inverts_elevation_displacement() -> void:
	# For an elevated point on a slope, screen_to_grid_point should retrieve the grid coordinate
	var target_grid := Vector2(5.0, 5.0)
	grid.set_vertex_elevation(Vector2i(5, 5), 3)

	var screen_pos := grid.grid_point_to_screen(target_grid)
	var unprojected := grid.screen_to_grid_point(screen_pos)

	assert_almost_eq(unprojected.x, target_grid.x, 0.05)
	assert_almost_eq(unprojected.y, target_grid.y, 0.05)

func test_top_down_view_has_no_elevation_displacement() -> void:
	grid.set_view_isometric(false)
	assert_false(grid.view_isometric)

	var v := Vector2i(4, 4)
	grid.set_vertex_elevation(v, 4)
	var disp := grid.get_vertex_elevation_displacement(v)
	assert_eq(disp, Vector2.ZERO)

	var screen_pos := grid.grid_point_to_screen(Vector2(v))
	var flat_proj := grid.projection.project(Vector2(v))
	assert_eq(screen_pos, flat_proj)

func test_course_surface_shader_uniforms_configured() -> void:
	assert_not_null(grid._course_surface)
	var mat := grid._course_surface.material as ShaderMaterial
	assert_not_null(mat)

	var step_y = mat.get_shader_parameter("elevation_step_y")
	assert_eq(step_y, grid.ELEVATION_STEP_Y)

	var is_iso = mat.get_shader_parameter("is_isometric")
	assert_eq(is_iso, true)
