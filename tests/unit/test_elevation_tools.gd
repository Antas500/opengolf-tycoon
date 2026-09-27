extends GutTest
## Unit tests for the three elevation selector tools: Vertex, Flat Square and
## Gradual Square. Right click raises, left click lowers, and no vertex
## outside the selection is ever touched.

var grid: TerrainGrid
var tool: ElevationTool
var previous_land
var previous_pause: bool
var previous_speed: GameManager.GameSpeed

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
	tool = ElevationTool.new()
	add_child_autofree(tool)

func after_each() -> void:
	GameManager.land_manager = previous_land
	GameManager.is_paused = previous_pause
	GameManager.current_speed = previous_speed

func _set_elevations(values: Dictionary) -> void:
	for vertex in values.keys():
		grid.set_vertex_elevation(vertex, values[vertex])

# =============================================================================
# Tool selection state
# =============================================================================

func test_selecting_a_tool_arms_the_selector_until_cancelled() -> void:
	assert_false(tool.is_active())
	tool.select_tool(ElevationTool.Tool.VERTEX)
	assert_true(tool.is_active())
	assert_eq(tool.tool, ElevationTool.Tool.VERTEX)
	tool.cancel()
	assert_false(tool.is_active())
	assert_eq(tool.tool, ElevationTool.Tool.NONE)

func test_modes_are_driven_by_the_mouse_button() -> void:
	tool.select_tool(ElevationTool.Tool.VERTEX)
	assert_eq(tool.elevation_mode, ElevationTool.ElevationMode.NONE)
	tool.set_mode(true)
	assert_true(tool.is_raising())
	tool.stop_stroke()
	assert_false(tool.is_raising())
	assert_true(tool.is_active())  # The tool stays selected after a stroke
	tool.set_mode(false)
	assert_true(tool.is_lowering())
	tool.stop_stroke()
	assert_eq(tool.elevation_mode, ElevationTool.ElevationMode.NONE)

func test_brush_sizes_are_separate_per_tool() -> void:
	tool.select_tool(ElevationTool.Tool.FLAT)
	assert_eq(tool.brush_sizes(), ElevationTool.FLAT_BRUSH_SIZES)
	tool.set_brush_size(1)
	assert_eq(tool.brush_size, 1)
	tool.set_brush_size(9)
	assert_eq(tool.brush_size, 9)
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	assert_eq(tool.brush_sizes(), ElevationTool.GRADUAL_BRUSH_SIZES)
	tool.set_brush(5, true)
	assert_eq(tool.brush_size, 5)
	# Gradual cannot be 1x1; the vertex tool has no sizes at all.
	tool.set_brush_size(1)
	assert_eq(tool.brush_size, 5)
	tool.select_tool(ElevationTool.Tool.VERTEX)
	assert_eq(tool.brush_sizes(), [])

# =============================================================================
# Square area geometry
# =============================================================================

func test_square_offsets_fill_the_sized_square() -> void:
	assert_eq(ElevationTool.square_offsets(1, true).size(), 1)
	assert_eq(ElevationTool.square_offsets(3, false).size(), 9)
	assert_eq(ElevationTool.square_offsets(9, false).size(), 81)
	# Even sizes centre on the middle 2x2 block of vertices.
	var even := ElevationTool.square_offsets(4, false)
	assert_eq(even.size(), 16)
	assert_true(even.has(Vector2i(-1, -1)))
	assert_true(even.has(Vector2i(2, 2)))
	assert_false(even.has(Vector2i(3, 0)))

func test_round_shape_clips_the_corners() -> void:
	var square := ElevationTool.square_offsets(9, false)
	var round := ElevationTool.square_offsets(9, true)
	assert_gt(square.size(), round.size())
	assert_false(round.has(Vector2i(4, 4)))   # Corner is clipped
	assert_false(round.has(Vector2i(4, 3)))   # Near-corner is clipped
	assert_true(round.has(Vector2i(4, 2)))    # Edge-mid stays
	assert_true(round.has(Vector2i(0, 0)))
	# A 1x1 round brush is still one vertex.
	assert_eq(ElevationTool.square_offsets(1, true).size(), 1)
	assert_eq(ElevationTool.square_offsets(2, true).size(), 4)

func test_middle_vertices_are_center_or_center_2x2() -> void:
	assert_eq(ElevationTool.middle_vertices(3, Vector2i(5, 6)), [Vector2i(5, 6)])
	var even := ElevationTool.middle_vertices(4, Vector2i(5, 6))
	assert_eq(even.size(), 4)
	for offset in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
		assert_true(even.has(Vector2i(5, 6) + offset))

func test_distance_to_middle_counts_vertices_away() -> void:
	assert_eq(ElevationTool.distance_to_middle(Vector2i(0, 0), 5, Vector2i(0, 0)), 0)
	assert_eq(ElevationTool.distance_to_middle(Vector2i(1, 0), 5, Vector2i(0, 0)), 1)
	assert_eq(ElevationTool.distance_to_middle(Vector2i(2, 3), 5, Vector2i(0, 0)), 3)
	# Even size: distance to the middle 2x2 block.
	assert_eq(ElevationTool.distance_to_middle(Vector2i(0, 0), 4, Vector2i(0, 0)), 0)
	assert_eq(ElevationTool.distance_to_middle(Vector2i(1, 1), 4, Vector2i(0, 0)), 0)
	assert_eq(ElevationTool.distance_to_middle(Vector2i(2, 0), 4, Vector2i(0, 0)), 1)
	assert_eq(ElevationTool.distance_to_middle(Vector2i(-1, -1), 4, Vector2i(0, 0)), 1)

# =============================================================================
# Vertex Selector
# =============================================================================

func test_vertex_selector_raises_and_lowers_one_step() -> void:
	tool.select_tool(ElevationTool.Tool.VERTEX)
	tool.set_mode(true)   # Right click
	var changes := tool.paint_vertices(Vector2i(8, 8), grid, null)
	assert_eq(changes.size(), 1)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), 1)

	tool.stop_stroke()
	tool.set_mode(false)  # Left click
	tool.paint_vertices(Vector2i(8, 8), grid, null)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), 0)

func test_vertex_selector_clamps_at_the_limits() -> void:
	tool.select_tool(ElevationTool.Tool.VERTEX)
	tool.set_mode(true)
	for i in range(grid.MAX_ELEVATION):
		tool.paint_vertices(Vector2i(8, 8), grid, null)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), grid.MAX_ELEVATION)
	var changes := tool.paint_vertices(Vector2i(8, 8), grid, null)
	assert_eq(changes, [])

	tool.stop_stroke()
	tool.set_mode(false)
	for i in range(grid.MAX_ELEVATION - grid.MIN_ELEVATION + 1):
		tool.paint_vertices(Vector2i(8, 8), grid, null)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), grid.MIN_ELEVATION)
	changes = tool.paint_vertices(Vector2i(8, 8), grid, null)
	assert_eq(changes, [])

func test_vertex_selector_only_touches_the_one_vertex() -> void:
	tool.select_tool(ElevationTool.Tool.VERTEX)
	tool.set_mode(true)
	tool.paint_vertices(Vector2i(8, 8), grid, null)
	for vertex in ElevationTool.square_vertices(grid, Vector2i(8, 8), 3, false):
		if vertex != Vector2i(8, 8):
			assert_eq(grid.get_vertex_elevation(vertex), 0, "vertex %s must not move" % vertex)

# =============================================================================
# Flat Square Selector
# =============================================================================

func test_flat_raising_levels_the_low_vertices_up_then_shifts_the_square() -> void:
	# 3x3 square around (8,8): rows of 0, 2 and 4.
	_set_elevations({
		Vector2i(7, 7): 4, Vector2i(8, 7): 4, Vector2i(9, 7): 4,
		Vector2i(7, 8): 2, Vector2i(8, 8): 2, Vector2i(9, 8): 2,
		Vector2i(7, 9): 0, Vector2i(8, 9): 0, Vector2i(9, 9): 0,
	})
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(3, true)
	tool.set_mode(true)  # Right click
	var changes := tool.paint_vertices(Vector2i(8, 8), grid, null)
	assert_eq(changes.size(), 9)
	for y in range(7, 10):
		for x in range(7, 10):
			assert_eq(grid.get_vertex_elevation(Vector2i(x, y)), 5,
					"vertex (%d,%d) should be levelled to 4 then raised to 5" % [x, y])
	# The square's rim is untouched.
	assert_eq(grid.get_vertex_elevation(Vector2i(6, 8)), 0)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 6)), 0)

func test_flat_lowering_levels_the_high_vertices_down_then_shifts_the_square() -> void:
	_set_elevations({
		Vector2i(7, 7): 4, Vector2i(8, 7): 4, Vector2i(9, 7): 4,
		Vector2i(7, 8): 2, Vector2i(8, 8): 2, Vector2i(9, 8): 2,
		Vector2i(7, 9): 0, Vector2i(8, 9): 0, Vector2i(9, 9): 0,
	})
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(3, true)
	tool.set_mode(false)  # Left click
	tool.paint_vertices(Vector2i(8, 8), grid, null)
	for y in range(7, 10):
		for x in range(7, 10):
			assert_eq(grid.get_vertex_elevation(Vector2i(x, y)), -1,
					"vertex (%d,%d) should be levelled to 0 then lowered to -1" % [x, y])

func test_flat_on_flat_ground_is_a_plain_step() -> void:
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(5, true)
	tool.set_mode(true)
	tool.paint_vertices(Vector2i(8, 8), grid, null)
	var area := ElevationTool.square_vertices(grid, Vector2i(8, 8), 5, true)
	for vertex in area:
		assert_eq(grid.get_vertex_elevation(vertex), 1)
	tool.stop_stroke()
	tool.set_mode(false)
	tool.paint_vertices(Vector2i(8, 8), grid, null)
	for vertex in area:
		assert_eq(grid.get_vertex_elevation(vertex), 0)

func test_flat_clamps_at_the_limits() -> void:
	for y in range(7, 10):
		for x in range(7, 10):
			grid.set_vertex_elevation(Vector2i(x, y), grid.MAX_ELEVATION)
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(3, true)
	tool.set_mode(true)
	var changes := tool.paint_vertices(Vector2i(8, 8), grid, null)
	assert_eq(changes, [])  # Already at the top: nothing changes

	tool.stop_stroke()
	for y in range(7, 10):
		for x in range(7, 10):
			grid.set_vertex_elevation(Vector2i(x, y), grid.MIN_ELEVATION)
	tool.set_mode(false)
	changes = tool.paint_vertices(Vector2i(8, 8), grid, null)
	assert_eq(changes, [])

func test_flat_1x1_is_a_single_vertex_step() -> void:
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(1, true)
	tool.set_mode(true)
	tool.paint_vertices(Vector2i(8, 8), grid, null)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), 1)
	assert_eq(grid.get_vertex_elevation(Vector2i(9, 8)), 0)

func test_flat_even_sizes_cover_the_2x2_centre() -> void:
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(2, true)
	tool.set_mode(true)
	tool.paint_vertices(Vector2i(8, 8), grid, null)
	for vertex in ElevationTool.square_vertices(grid, Vector2i(8, 8), 2, true):
		assert_eq(grid.get_vertex_elevation(vertex), 1, "vertex %s is in the 2x2" % vertex)
	assert_eq(grid.get_vertex_elevation(Vector2i(7, 7)), 0)

func test_flat_round_shape_skips_clipped_corners() -> void:
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(9, false)  # Round
	tool.set_mode(true)
	tool.paint_vertices(Vector2i(8, 8), grid, null)
	var round_area := ElevationTool.square_vertices(grid, Vector2i(8, 8), 9, false)
	var square_area := ElevationTool.square_vertices(grid, Vector2i(8, 8), 9, true)
	for vertex in round_area:
		assert_eq(grid.get_vertex_elevation(vertex), 1)
	for vertex in square_area:
		if not round_area.has(vertex):
			assert_eq(grid.get_vertex_elevation(vertex), 0, "clipped corner %s must not move" % vertex)

func test_flat_ignores_unselected_and_uneditable_vertices() -> void:
	# A ring of 3s around a 0 centre: raising must level to 3 then shift to 4,
	# and nothing outside the 3x3 square may move.
	_set_elevations({
		Vector2i(7, 7): 3, Vector2i(8, 7): 3, Vector2i(9, 7): 3,
		Vector2i(7, 8): 3, Vector2i(9, 8): 3,
		Vector2i(7, 9): 3, Vector2i(8, 9): 3, Vector2i(9, 9): 3,
	})
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(3, true)
	tool.set_mode(true)
	var changes := tool.paint_vertices(Vector2i(8, 8), grid, null)
	for change in changes:
		assert_eq(change.new_elevation, 4)
		assert_eq(grid.get_vertex_elevation(change.position), 4)
	assert_eq(grid.get_vertex_elevation(Vector2i(6, 6)), 0)
	assert_eq(grid.get_vertex_elevation(Vector2i(10, 10)), 0)

func test_flat_skips_vertices_under_buildings() -> void:
	var entities := EntityLayer.new()
	entities.map_seed = 1234
	add_child_autofree(entities)
	entities.set_terrain_grid(grid)
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]
	entities.place_building("clubhouse", Vector2i(7, 7), registry)
	# Raise a 3x3 over the building corner: its pinned vertices stay put.
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(3, true)
	tool.set_mode(true)
	var changes := tool.paint_vertices(Vector2i(8, 8), grid, entities)
	for change in changes:
		assert_true(grid.is_vertex_editable(change.position, entities, false),
				"changed vertex %s must be editable" % change.position)
	for vertex in ElevationTool.square_vertices(grid, Vector2i(8, 8), 3, true):
		if not grid.is_vertex_editable(vertex, entities, false):
			assert_eq(grid.get_vertex_elevation(vertex), 0, "pinned vertex %s must not move" % vertex)

# =============================================================================
# Gradual Square Selector
# =============================================================================

func test_gradual_raising_lifts_the_middle_of_flat_ground() -> void:
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	tool.set_brush(5, true)
	tool.set_mode(true)
	tool.paint_vertices(Vector2i(8, 8), grid, null)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), 1)
	for vertex in ElevationTool.square_vertices(grid, Vector2i(8, 8), 5, true):
		if vertex != Vector2i(8, 8):
			assert_eq(grid.get_vertex_elevation(vertex), 0)
	# Outside the square: untouched.
	assert_eq(grid.get_vertex_elevation(Vector2i(5, 8)), 0)

func test_gradual_repeated_clicks_build_a_one_step_pyramid() -> void:
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	tool.set_brush(7, true)
	tool.set_mode(true)
	for i in range(3):
		tool.stop_stroke()
		tool.set_mode(true)
		tool.paint_vertices(Vector2i(8, 8), grid, null)
	# A 3-step square pyramid: each ring is one step lower than the last.
	for vertex in ElevationTool.square_vertices(grid, Vector2i(8, 8), 7, true):
		var expected: int = 3 - ElevationTool.distance_to_middle(vertex, 7, Vector2i(8, 8))
		assert_eq(grid.get_vertex_elevation(vertex), expected, "vertex %s" % vertex)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), 3)

func test_gradual_lowering_digs_a_one_step_basin() -> void:
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	tool.set_brush(5, true)
	tool.set_mode(false)
	tool.stop_stroke()
	tool.set_mode(false)
	tool.paint_vertices(Vector2i(8, 8), grid, null)
	tool.stop_stroke()
	tool.set_mode(false)
	tool.paint_vertices(Vector2i(8, 8), grid, null)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), -2)
	assert_eq(grid.get_vertex_elevation(Vector2i(9, 8)), -1)
	assert_eq(grid.get_vertex_elevation(Vector2i(10, 8)), 0)
	assert_eq(grid.get_vertex_elevation(Vector2i(9, 9)), -1)
	assert_eq(grid.get_vertex_elevation(Vector2i(11, 8)), 0)

func test_gradual_even_sizes_move_the_middle_2x2_as_one_unit() -> void:
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	tool.set_brush(4, true)
	tool.set_mode(true)
	tool.paint_vertices(Vector2i(8, 8), grid, null)
	var middle := ElevationTool.middle_vertices(4, Vector2i(8, 8))
	for vertex in middle:
		assert_eq(grid.get_vertex_elevation(vertex), 1, "middle vertex %s" % vertex)
	for vertex in ElevationTool.square_vertices(grid, Vector2i(8, 8), 4, true):
		if not middle.has(vertex):
			assert_eq(grid.get_vertex_elevation(vertex), 0)

func test_gradual_moves_nearby_vertices_beyond_one_step_of_slope() -> void:
	# A steep rise next to the middle: raising the middle must drag the high
	# neighbour down (and pull a deep neighbour up) so the slope stays 1:1.
	_set_elevations({
		Vector2i(9, 8): 3,   # Steep neighbour, 1 away from the middle
		Vector2i(7, 8): -2,  # Deep neighbour, 1 away
		Vector2i(10, 8): 3,  # Two away: may differ by 2
	})
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	tool.set_brush(5, true)
	tool.set_mode(true)
	tool.paint_vertices(Vector2i(8, 8), grid, null)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), 1)
	assert_eq(grid.get_vertex_elevation(Vector2i(9, 8)), 2, "steep neighbour clamped to one above the middle")
	assert_eq(grid.get_vertex_elevation(Vector2i(7, 8)), 0, "deep neighbour raised to one below the middle")
	assert_eq(grid.get_vertex_elevation(Vector2i(10, 8)), 3, "two away: allowed to differ by two, not moved")
	assert_eq(grid.get_vertex_elevation(Vector2i(11, 8)), 0)

func test_gradual_moves_only_vertices_that_break_the_gradient() -> void:
	# Slopes that already fit the 1:1 rule around the raised middle stay put;
	# the downhill side, now two below the raised middle, gets pulled along.
	_set_elevations({
		Vector2i(9, 8): 1, Vector2i(10, 8): 2,   # Fit: 0 and 1 below the new middle
		Vector2i(7, 8): -1, Vector2i(6, 8): -2,  # Break: 2 and 3 below
	})
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	tool.set_brush(7, true)
	tool.set_mode(true)
	var changes := tool.paint_vertices(Vector2i(8, 8), grid, null)
	assert_eq(changes.size(), 3)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), 1)
	assert_eq(grid.get_vertex_elevation(Vector2i(7, 8)), 0)
	assert_eq(grid.get_vertex_elevation(Vector2i(6, 8)), -1)
	assert_eq(grid.get_vertex_elevation(Vector2i(9, 8)), 1)
	assert_eq(grid.get_vertex_elevation(Vector2i(10, 8)), 2)
	assert_eq(grid.get_vertex_elevation(Vector2i(11, 8)), 0)

func test_gradual_stops_at_the_height_limits() -> void:
	for vertex in ElevationTool.middle_vertices(3, Vector2i(8, 8)):
		grid.set_vertex_elevation(vertex, grid.MAX_ELEVATION)
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	tool.set_brush(3, true)
	tool.set_mode(true)
	var changes := tool.paint_vertices(Vector2i(8, 8), grid, null)
	assert_eq(changes, [])  # Middle already at the top: no change propagates

func test_gradual_round_shape_clips_the_area() -> void:
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	tool.set_brush(5, false)  # Round
	tool.set_mode(true)
	tool.paint_vertices(Vector2i(8, 8), grid, null)
	var round_area := ElevationTool.square_vertices(grid, Vector2i(8, 8), 5, false)
	var square_area := ElevationTool.square_vertices(grid, Vector2i(8, 8), 5, true)
	for vertex in square_area:
		if not round_area.has(vertex):
			assert_eq(grid.get_vertex_elevation(vertex), 0, "clipped vertex %s must not move" % vertex)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), 1)

# =============================================================================
# Painting entry points
# =============================================================================

func test_paint_at_point_snaps_to_the_nearest_vertex() -> void:
	tool.select_tool(ElevationTool.Tool.VERTEX)
	tool.set_mode(true)
	tool.paint_at_point(Vector2(8.2, 8.2), grid, null)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), 1)

func test_paint_requires_a_selected_tool_and_a_mode() -> void:
	tool.select_tool(ElevationTool.Tool.VERTEX)
	assert_eq(tool.paint_vertices(Vector2i(8, 8), grid, null), [])  # No button held
	tool.cancel()
	tool.elevation_mode = ElevationTool.ElevationMode.RAISING
	assert_eq(tool.paint_vertices(Vector2i(8, 8), grid, null), [])  # No tool selected

func test_changes_support_undo_restore() -> void:
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(3, true)
	tool.set_mode(true)
	var changes := tool.paint_vertices(Vector2i(8, 8), grid, null)
	assert_gt(changes.size(), 0)
	for i in range(changes.size() - 1, -1, -1):
		var change = changes[i]
		grid.set_vertex_elevation(change.position, change.old_elevation)
	for vertex in ElevationTool.square_vertices(grid, Vector2i(8, 8), 3, true):
		assert_eq(grid.get_vertex_elevation(vertex), 0)
