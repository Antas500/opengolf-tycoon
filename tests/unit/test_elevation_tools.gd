extends GutTest
## Unit tests for the three elevation selector tools: Vertex, Flat Square and
## Gradual Square. Right click raises, left click lowers, and no vertex
## outside the selection is ever touched.
##
## The Square Selectors' Elevation Brush is measured in **tiles**: it reshapes
## the tiles it covers by moving their corner vertices, so an S x S brush
## holds (S+1)^2 vertices. The round (circle) shape keeps the tiles whose
## centre lies inside a circle of radius S/2 around the middle of the block,
## which clips the corners away.

## Elevation levels run 0..10 with flat, untouched ground mid-range at
## BASE_ELEVATION, so a fresh grid starts at BASE and strokes move off it.
const BASE := TerrainGrid.BASE_ELEVATION

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

## Every vertex of an S x S tile brush anchored on `anchor` (0..S per axis).
func _brush_vertices(anchor: Vector2i, size: int, square: bool = true) -> Array[Vector2i]:
	return ElevationTool.brush_vertices(grid, anchor, size, square)

## The current elevation of each vertex, in order - for asserting strokes.
func _elevations(vertices: Array) -> Array:
	var result: Array = []
	for vertex in vertices:
		result.append(grid.get_vertex_elevation(vertex))
	return result

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

func test_brush_sizes_are_shared_by_the_square_tools() -> void:
	tool.select_tool(ElevationTool.Tool.FLAT)
	assert_eq(tool.brush_sizes(), ElevationTool.BRUSH_SIZES)
	tool.set_brush_size(1)
	assert_eq(tool.brush_size, 1)
	tool.set_brush_size(9)
	assert_eq(tool.brush_size, 9)
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	assert_eq(tool.brush_sizes(), ElevationTool.BRUSH_SIZES)
	tool.set_brush(5, true)
	assert_eq(tool.brush_size, 5)
	# Gradual can be 1x1, the same sizes Flat offers; the vertex tool has none.
	tool.set_brush_size(1)
	assert_eq(tool.brush_size, 1)
	tool.select_tool(ElevationTool.Tool.VERTEX)
	assert_eq(tool.brush_sizes(), [])
	# Size can still be set while Vertex is selected so the Square tools
	# pick up the shared brush when they come back.
	tool.set_brush_size(4)
	assert_eq(tool.brush_size, 4)

# =============================================================================
# Brush area geometry (sizes are in tiles)
# =============================================================================

func test_square_brush_is_one_tile_wider_in_vertices() -> void:
	# 1x1 = 1 tile = 4 vertices, 2x2 = 4 tiles = 9 vertices,
	# 3x3 = 9 tiles = 16 vertices, ...
	for size in [1, 2, 3, 4, 5]:
		assert_eq(ElevationTool.tile_offsets(size, true).size(), size * size,
				"%dx%d square brush covers %d tiles" % [size, size, size * size])
		assert_eq(ElevationTool.vertex_offsets(size, true).size(), (size + 1) * (size + 1),
				"%dx%d square brush covers %d vertices" % [size, size, (size + 1) * (size + 1)])

func test_round_brush_clips_the_corners_to_the_documented_counts() -> void:
	# 1x1 = 1 tile = 4 vertices, 2x2 = 4 tiles = 9 vertices,
	# 3x3 = 5 tiles = 12 vertices, 4x4 = 12 tiles = 21 vertices,
	# 5x5 = 13 tiles = 24 vertices.
	var round_tiles := [1, 4, 5, 12, 13]
	var round_vertices := [4, 9, 12, 21, 24]
	for i in round_tiles.size():
		var size: int = i + 1
		assert_eq(ElevationTool.tile_offsets(size, false).size(), round_tiles[i],
				"%dx%d round brush tile count" % [size, size])
		assert_eq(ElevationTool.vertex_offsets(size, false).size(), round_vertices[i],
				"%dx%d round brush vertex count" % [size, size])
	# The two shapes only start to differ once there are corners to clip.
	for size in [1, 2]:
		assert_eq(ElevationTool.tile_offsets(size, false), ElevationTool.tile_offsets(size, true))

func test_tile_offsets_centre_on_the_anchor() -> void:
	# Odd sizes centre on the anchor tile...
	var odd := ElevationTool.tile_offsets(3, true)
	assert_true(odd.has(Vector2i(-1, -1)))
	assert_true(odd.has(Vector2i(0, 0)))
	assert_true(odd.has(Vector2i(1, 1)))
	assert_false(odd.has(Vector2i(2, 0)))
	# ...even sizes centre on the vertex at the anchor tile's near corner.
	var even := ElevationTool.tile_offsets(4, true)
	assert_true(even.has(Vector2i(-2, -2)))
	assert_true(even.has(Vector2i(0, 0)))
	assert_true(even.has(Vector2i(1, 1)))
	assert_false(even.has(Vector2i(2, 0)))

func test_round_shape_clips_the_tiles_furthest_from_the_middle() -> void:
	var round3 := ElevationTool.tile_offsets(3, false)
	assert_true(round3.has(Vector2i(0, 0)))     # Middle tile stays
	assert_true(round3.has(Vector2i(1, 0)))     # Edge-middle tile stays
	assert_false(round3.has(Vector2i(1, 1)))    # Corner tile is clipped
	var round5 := ElevationTool.tile_offsets(5, false)
	assert_true(round5.has(Vector2i(2, 0)))     # Edge tile stays
	assert_true(round5.has(Vector2i(1, 1)))     # Near-edge tile stays
	assert_false(round5.has(Vector2i(2, 1)))    # Corner-ward tile is clipped
	assert_false(round5.has(Vector2i(2, 2)))    # Corner tile is clipped

func test_vertices_are_the_corners_of_the_brush_tiles() -> void:
	for size in [1, 2, 3, 4, 5]:
		for square in [true, false]:
			var tiles := ElevationTool.brush_tiles(grid, Vector2i(8, 8), size, square)
			var vertices := ElevationTool.brush_vertices(grid, Vector2i(8, 8), size, square)
			var expected := {}
			for tile in tiles:
				for vertex in grid.vertices_of_tile(tile):
					expected[vertex] = true
			assert_eq(vertices.size(), expected.size(),
					"size %d square %s: every tile corner is selected once" % [size, square])
			for vertex in vertices:
				assert_true(expected.has(vertex), "vertex %s bounds a selected tile" % vertex)

func test_brush_tiles_and_vertices_clip_at_the_grid_edge() -> void:
	var tiles := ElevationTool.brush_tiles(grid, Vector2i.ZERO, 3, true)
	var vertices := ElevationTool.brush_vertices(grid, Vector2i.ZERO, 3, true)
	assert_eq(tiles.size(), 4, "a 3x3 brush at the corner keeps the on-grid tiles")
	assert_eq(vertices.size(), 9, "and their corners")
	for tile in tiles:
		assert_true(grid.is_valid_position(tile), "preview tile stays on the terrain grid")
	for vertex in vertices:
		assert_true(grid.is_valid_vertex(vertex), "selected vertex stays on the vertex grid")

func test_middle_vertices_are_the_anchor_or_the_anchor_tile_corners() -> void:
	# Even sizes centre the brush on a vertex...
	assert_eq(ElevationTool.middle_vertices(4, Vector2i(5, 6)), [Vector2i(5, 6)])
	# ...odd sizes centre it on the anchor tile, whose corners are the middle.
	var odd := ElevationTool.middle_vertices(3, Vector2i(5, 6))
	assert_eq(odd.size(), 4)
	for offset in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
		assert_true(odd.has(Vector2i(5, 6) + offset))

func test_distance_to_middle_counts_vertices_away() -> void:
	# Even size: distance to the single middle vertex at the anchor.
	assert_eq(ElevationTool.distance_to_middle(Vector2i(0, 0), 4, Vector2i(0, 0)), 0)
	assert_eq(ElevationTool.distance_to_middle(Vector2i(1, 0), 4, Vector2i(0, 0)), 1)
	assert_eq(ElevationTool.distance_to_middle(Vector2i(2, 3), 4, Vector2i(0, 0)), 3)
	# Odd size: distance to the middle 2x2 block of the anchor tile.
	assert_eq(ElevationTool.distance_to_middle(Vector2i(0, 0), 5, Vector2i(0, 0)), 0)
	assert_eq(ElevationTool.distance_to_middle(Vector2i(1, 1), 5, Vector2i(0, 0)), 0)
	assert_eq(ElevationTool.distance_to_middle(Vector2i(2, 0), 5, Vector2i(0, 0)), 1)
	assert_eq(ElevationTool.distance_to_middle(Vector2i(-1, -1), 5, Vector2i(0, 0)), 1)

# =============================================================================
# Vertex Selector
# =============================================================================

func test_vertex_selector_raises_and_lowers_one_step() -> void:
	tool.select_tool(ElevationTool.Tool.VERTEX)
	tool.set_mode(true)   # Right click
	var changes := tool.paint_at_vertex(Vector2i(8, 8), grid, null)
	assert_eq(changes.size(), 1)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), BASE + 1)

	tool.stop_stroke()
	tool.set_mode(false)  # Left click
	tool.paint_at_vertex(Vector2i(8, 8), grid, null)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), BASE)

func test_vertex_selector_clamps_at_the_limits() -> void:
	tool.select_tool(ElevationTool.Tool.VERTEX)
	tool.set_mode(true)
	for i in range(grid.MAX_ELEVATION - grid.BASE_ELEVATION):
		tool.paint_at_vertex(Vector2i(8, 8), grid, null)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), grid.MAX_ELEVATION)
	var changes := tool.paint_at_vertex(Vector2i(8, 8), grid, null)
	assert_eq(changes, [])

	tool.stop_stroke()
	tool.set_mode(false)
	for i in range(grid.MAX_ELEVATION - grid.MIN_ELEVATION + 1):
		tool.paint_at_vertex(Vector2i(8, 8), grid, null)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), grid.MIN_ELEVATION)
	changes = tool.paint_at_vertex(Vector2i(8, 8), grid, null)
	assert_eq(changes, [])

func test_vertex_selector_only_touches_the_one_vertex() -> void:
	tool.select_tool(ElevationTool.Tool.VERTEX)
	tool.set_mode(true)
	tool.paint_at_vertex(Vector2i(8, 8), grid, null)
	for vertex in _brush_vertices(Vector2i(8, 8), 3):
		if vertex != Vector2i(8, 8):
			assert_eq(grid.get_vertex_elevation(vertex), BASE, "vertex %s must not move" % vertex)

# =============================================================================
# Flat Square Selector
# =============================================================================

func test_flat_raising_lifts_only_the_lowest_vertices_one_level() -> void:
	# 3x3 tile brush on (8,8): 16 corner vertices, stepped 0..3 above the base
	# by column.
	for x in range(7, 11):
		for y in range(7, 11):
			grid.set_vertex_elevation(Vector2i(x, y), BASE + x - 7)
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(3, true)
	tool.set_mode(true)  # Right click
	var changes := tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_eq(changes.size(), 4, "only the vertices at the lowest level move")
	for y in range(7, 11):
		for x in range(7, 11):
			var expected: int = BASE + 1 if x == 7 else BASE + x - 7
			assert_eq(grid.get_vertex_elevation(Vector2i(x, y)), expected,
					"vertex (%d,%d): the lowest rise one level, the rest stay put" % [x, y])
	# The brush's rim is untouched.
	assert_eq(grid.get_vertex_elevation(Vector2i(6, 8)), BASE)
	assert_eq(grid.get_vertex_elevation(Vector2i(11, 8)), BASE)

func test_flat_lowering_trims_only_the_highest_vertices_one_level() -> void:
	for x in range(7, 11):
		for y in range(7, 11):
			grid.set_vertex_elevation(Vector2i(x, y), BASE + x - 7)
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(3, true)
	tool.set_mode(false)  # Left click
	var changes := tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_eq(changes.size(), 4, "only the vertices at the highest level move")
	for y in range(7, 11):
		for x in range(7, 11):
			var expected: int = BASE + 2 if x == 10 else BASE + x - 7
			assert_eq(grid.get_vertex_elevation(Vector2i(x, y)), expected,
					"vertex (%d,%d): the highest drop one level, the rest stay put" % [x, y])

func test_flat_repeated_strokes_level_the_brush_then_move_it_as_one_slab() -> void:
	var corners := [Vector2i(8, 8), Vector2i(9, 8), Vector2i(8, 9), Vector2i(9, 9)]
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(1, true)
	# Raising only lifts the selection's lowest vertices, one level per
	# stroke, until the brush is even and steps up as one slab.
	_set_elevations({Vector2i(8, 8): BASE, Vector2i(9, 8): BASE,
			Vector2i(8, 9): BASE + 2, Vector2i(9, 9): BASE + 2})
	tool.set_mode(true)  # Right click
	tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_eq(_elevations(corners), [BASE + 1, BASE + 1, BASE + 2, BASE + 2],
			"raising lifts only the two lowest")
	tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_eq(_elevations(corners), [BASE + 2, BASE + 2, BASE + 2, BASE + 2],
			"the second stroke levels the brush")
	tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_eq(_elevations(corners), [BASE + 3, BASE + 3, BASE + 3, BASE + 3],
			"an even brush steps up as one slab")
	# Lowering only trims the selection's highest vertices the same way.
	tool.stop_stroke()
	_set_elevations({Vector2i(8, 8): BASE + 3, Vector2i(9, 8): BASE + 3,
			Vector2i(8, 9): BASE + 1, Vector2i(9, 9): BASE + 1})
	tool.set_mode(false)  # Left click
	tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_eq(_elevations(corners), [BASE + 2, BASE + 2, BASE + 1, BASE + 1],
			"lowering trims only the two highest")
	tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_eq(_elevations(corners), [BASE + 1, BASE + 1, BASE + 1, BASE + 1],
			"the second stroke levels the brush")
	tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_eq(_elevations(corners), [BASE, BASE, BASE, BASE],
			"an even brush steps down as one slab")

func test_flat_on_flat_ground_is_a_plain_step() -> void:
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(5, true)
	tool.set_mode(true)
	tool.paint_at_tile(Vector2i(8, 8), grid, null)
	var area := _brush_vertices(Vector2i(8, 8), 5)
	assert_eq(area.size(), 36, "a 5x5 tile brush moves 6x6 vertices")
	for vertex in area:
		assert_eq(grid.get_vertex_elevation(vertex), BASE + 1)
	tool.stop_stroke()
	tool.set_mode(false)
	tool.paint_at_tile(Vector2i(8, 8), grid, null)
	for vertex in area:
		assert_eq(grid.get_vertex_elevation(vertex), BASE)

func test_flat_clamps_at_the_limits() -> void:
	for y in range(7, 11):
		for x in range(7, 11):
			grid.set_vertex_elevation(Vector2i(x, y), grid.MAX_ELEVATION)
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(3, true)
	tool.set_mode(true)
	var changes := tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_eq(changes, [])  # Already at the top: nothing changes

	tool.stop_stroke()
	for y in range(7, 11):
		for x in range(7, 11):
			grid.set_vertex_elevation(Vector2i(x, y), grid.MIN_ELEVATION)
	tool.set_mode(false)
	changes = tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_eq(changes, [])

func test_flat_1x1_reshapes_the_single_tile_under_the_cursor() -> void:
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(1, true)
	tool.set_mode(true)
	var changes := tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_eq(changes.size(), 4, "1 tile = 4 vertices")
	for vertex in [Vector2i(8, 8), Vector2i(9, 8), Vector2i(8, 9), Vector2i(9, 9)]:
		assert_eq(grid.get_vertex_elevation(vertex), BASE + 1, "corner %s of the tile" % vertex)
	assert_eq(grid.get_vertex_elevation(Vector2i(7, 8)), BASE)
	assert_eq(grid.get_vertex_elevation(Vector2i(10, 9)), BASE)

func test_flat_even_sizes_cover_the_2x2_tiles_around_the_anchor() -> void:
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(2, true)
	tool.set_mode(true)
	tool.paint_at_tile(Vector2i(8, 8), grid, null)
	var area := _brush_vertices(Vector2i(8, 8), 2)
	assert_eq(area.size(), 9, "2x2 tiles = 9 vertices")
	for vertex in area:
		assert_eq(grid.get_vertex_elevation(vertex), BASE + 1, "vertex %s is in the brush" % vertex)
	assert_eq(grid.get_vertex_elevation(Vector2i(6, 6)), BASE)

func test_flat_round_shape_skips_clipped_corners() -> void:
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(9, false)  # Round
	tool.set_mode(true)
	tool.paint_at_tile(Vector2i(8, 8), grid, null)
	var round_area := _brush_vertices(Vector2i(8, 8), 9, false)
	var square_area := _brush_vertices(Vector2i(8, 8), 9, true)
	assert_eq(round_area.size(), 68, "9x9 round brush: 49 tiles, 68 vertices")
	for vertex in round_area:
		assert_eq(grid.get_vertex_elevation(vertex), BASE + 1)
	for vertex in square_area:
		if not round_area.has(vertex):
			assert_eq(grid.get_vertex_elevation(vertex), BASE,
					"clipped corner %s must not move" % vertex)

func test_flat_ignores_unselected_and_uneditable_vertices() -> void:
	# A ring three levels above a flat-level centre: raising moves only the
	# centre (the selection's lowest vertex) one level, and nothing outside
	# the brush.
	for x in range(7, 11):
		for y in range(7, 11):
			grid.set_vertex_elevation(Vector2i(x, y), BASE if x == 9 and y == 9 else BASE + 3)
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(3, true)
	tool.set_mode(true)
	var changes := tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_eq(changes.size(), 1, "only the lowest vertex of the selection moves")
	assert_eq(changes[0].position, Vector2i(9, 9))
	assert_eq(changes[0].old_elevation, BASE)
	assert_eq(changes[0].new_elevation, BASE + 1)
	assert_eq(grid.get_vertex_elevation(Vector2i(9, 9)), BASE + 1)
	for x in range(7, 11):
		for y in range(7, 11):
			if x == 9 and y == 9:
				continue
			assert_eq(grid.get_vertex_elevation(Vector2i(x, y)), BASE + 3,
					"vertex (%d,%d) is not at the lowest level: it must not move" % [x, y])
	assert_eq(grid.get_vertex_elevation(Vector2i(6, 6)), BASE)
	assert_eq(grid.get_vertex_elevation(Vector2i(12, 12)), BASE)

func test_flat_skips_vertices_under_buildings() -> void:
	var entities := EntityLayer.new()
	entities.map_seed = 1234
	add_child_autofree(entities)
	entities.set_terrain_grid(grid)
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]
	entities.place_building("clubhouse", Vector2i(7, 7), registry)
	# Raise a 3x3 tile brush over the building corner: its pinned vertices stay put.
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(3, true)
	tool.set_mode(true)
	var changes := tool.paint_at_tile(Vector2i(8, 8), grid, entities)
	for change in changes:
		assert_true(grid.is_vertex_editable(change.position, entities, false),
				"changed vertex %s must be editable" % change.position)
	for vertex in _brush_vertices(Vector2i(8, 8), 3):
		if not grid.is_vertex_editable(vertex, entities, false):
			assert_eq(grid.get_vertex_elevation(vertex), BASE,
					"pinned vertex %s must not move" % vertex)

# =============================================================================
# Gradual Square Selector
# =============================================================================

func test_gradual_1x1_reshapes_the_single_tile_under_the_cursor() -> void:
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	tool.set_brush(1, true)
	tool.set_mode(true)
	var changes := tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_eq(changes.size(), 4, "1 tile = 4 vertices")
	for vertex in [Vector2i(8, 8), Vector2i(9, 8), Vector2i(8, 9), Vector2i(9, 9)]:
		assert_eq(grid.get_vertex_elevation(vertex), BASE + 1, "corner %s of the tile" % vertex)
	assert_eq(grid.get_vertex_elevation(Vector2i(7, 8)), BASE)
	assert_eq(grid.get_vertex_elevation(Vector2i(10, 9)), BASE)

func test_gradual_raising_lifts_the_middle_of_flat_ground() -> void:
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	tool.set_brush(6, true)  # Even size: the middle is the anchor vertex.
	tool.set_mode(true)
	tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), BASE + 1)
	for vertex in _brush_vertices(Vector2i(8, 8), 6):
		if vertex != Vector2i(8, 8):
			assert_eq(grid.get_vertex_elevation(vertex), BASE)
	# Outside the brush: untouched.
	assert_eq(grid.get_vertex_elevation(Vector2i(4, 8)), BASE)

func test_gradual_repeated_clicks_build_a_one_step_pyramid() -> void:
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	tool.set_brush(6, true)  # 7x7 vertices: three steps down to the rim.
	tool.set_mode(true)
	for i in range(3):
		tool.stop_stroke()
		tool.set_mode(true)
		tool.paint_at_tile(Vector2i(8, 8), grid, null)
	# A 3-step square pyramid: each ring is one step lower than the last.
	for vertex in _brush_vertices(Vector2i(8, 8), 6):
		var expected: int = BASE + 3 - ElevationTool.distance_to_middle(vertex, 6, Vector2i(8, 8))
		assert_eq(grid.get_vertex_elevation(vertex), expected, "vertex %s" % vertex)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), BASE + 3)

func test_gradual_lowering_digs_a_one_step_basin() -> void:
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	tool.set_brush(5, true)  # Odd size: the middle is the anchor tile's 2x2 corners.
	tool.set_mode(false)
	tool.stop_stroke()
	tool.set_mode(false)
	tool.paint_at_tile(Vector2i(8, 8), grid, null)
	tool.stop_stroke()
	tool.set_mode(false)
	tool.paint_at_tile(Vector2i(8, 8), grid, null)
	for vertex in ElevationTool.middle_vertices(5, Vector2i(8, 8)):
		assert_eq(grid.get_vertex_elevation(vertex), BASE - 2, "middle vertex %s" % vertex)
	assert_eq(grid.get_vertex_elevation(Vector2i(10, 8)), BASE - 1)  # One away
	assert_eq(grid.get_vertex_elevation(Vector2i(7, 8)), BASE - 1)
	assert_eq(grid.get_vertex_elevation(Vector2i(11, 8)), BASE)  # Two away: may differ by two
	assert_eq(grid.get_vertex_elevation(Vector2i(6, 8)), BASE)

func test_gradual_odd_sizes_move_the_anchor_tile_corners_as_one_unit() -> void:
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	tool.set_brush(3, true)
	tool.set_mode(true)
	tool.paint_at_tile(Vector2i(8, 8), grid, null)
	var middle := ElevationTool.middle_vertices(3, Vector2i(8, 8))
	assert_eq(middle.size(), 4)
	for vertex in middle:
		assert_eq(grid.get_vertex_elevation(vertex), BASE + 1, "middle vertex %s" % vertex)
	for vertex in _brush_vertices(Vector2i(8, 8), 3):
		if not middle.has(vertex):
			assert_eq(grid.get_vertex_elevation(vertex), BASE)

func test_gradual_moves_nearby_vertices_beyond_one_step_of_slope() -> void:
	# A steep rise next to the middle: raising the middle must drag the high
	# neighbour down (and pull a deep neighbour up) so the slope stays 1:1.
	_set_elevations({
		Vector2i(10, 8): BASE + 3,   # Steep neighbour, 1 away from the middle block
		Vector2i(7, 8): BASE - 2,    # Deep neighbour, 1 away
		Vector2i(11, 8): BASE + 3,   # Two away: may differ by 2
	})
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	tool.set_brush(5, true)
	tool.set_mode(true)
	tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), BASE + 1)
	assert_eq(grid.get_vertex_elevation(Vector2i(9, 8)), BASE + 1, "the whole middle block steps up")
	assert_eq(grid.get_vertex_elevation(Vector2i(10, 8)), BASE + 2, "steep neighbour clamped to one above the middle")
	assert_eq(grid.get_vertex_elevation(Vector2i(7, 8)), BASE, "deep neighbour raised to one below the middle")
	assert_eq(grid.get_vertex_elevation(Vector2i(11, 8)), BASE + 3, "two away: allowed to differ by two, not moved")
	assert_eq(grid.get_vertex_elevation(Vector2i(12, 8)), BASE)

func test_gradual_moves_only_vertices_that_break_the_gradient() -> void:
	# Slopes that already fit the 1:1 rule around the raised middle stay put;
	# the downhill side, now two below the raised middle, gets pulled along.
	_set_elevations({
		Vector2i(10, 8): BASE + 1, Vector2i(11, 8): BASE + 2,   # Fit: 0 and 1 above the new middle
		Vector2i(7, 8): BASE - 1, Vector2i(6, 8): BASE - 2,     # Break: 2 and 3 below
	})
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	tool.set_brush(7, true)
	tool.set_mode(true)
	var changes := tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_eq(changes.size(), 6, "the 2x2 middle plus the two broken vertices")
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), BASE + 1)
	assert_eq(grid.get_vertex_elevation(Vector2i(9, 8)), BASE + 1)
	assert_eq(grid.get_vertex_elevation(Vector2i(7, 8)), BASE)
	assert_eq(grid.get_vertex_elevation(Vector2i(6, 8)), BASE - 1)
	assert_eq(grid.get_vertex_elevation(Vector2i(10, 8)), BASE + 1)
	assert_eq(grid.get_vertex_elevation(Vector2i(11, 8)), BASE + 2)
	assert_eq(grid.get_vertex_elevation(Vector2i(12, 8)), BASE)

func test_gradual_stops_at_the_height_limits() -> void:
	for vertex in ElevationTool.middle_vertices(3, Vector2i(8, 8)):
		grid.set_vertex_elevation(vertex, grid.MAX_ELEVATION)
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	tool.set_brush(3, true)
	tool.set_mode(true)
	var changes := tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_eq(changes, [])  # Middle already at the top: no change propagates

func test_gradual_round_shape_clips_the_area() -> void:
	tool.select_tool(ElevationTool.Tool.GRADUAL)
	tool.set_brush(5, false)  # Round
	tool.set_mode(true)
	tool.paint_at_tile(Vector2i(8, 8), grid, null)
	var round_area := _brush_vertices(Vector2i(8, 8), 5, false)
	var square_area := _brush_vertices(Vector2i(8, 8), 5, true)
	assert_eq(round_area.size(), 24, "5x5 round brush: 13 tiles, 24 vertices")
	for vertex in square_area:
		if not round_area.has(vertex):
			assert_eq(grid.get_vertex_elevation(vertex), BASE,
					"clipped vertex %s must not move" % vertex)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), BASE + 1)

# =============================================================================
# Painting entry points
# =============================================================================

func test_vertex_paint_at_point_snaps_to_the_nearest_vertex() -> void:
	tool.select_tool(ElevationTool.Tool.VERTEX)
	tool.set_mode(true)
	tool.paint_at_point(Vector2(8.2, 8.2), grid, null)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), BASE + 1)

func test_square_paint_at_point_anchors_on_the_tile_under_the_cursor() -> void:
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(1, true)
	tool.set_mode(true)
	# 8.2 and 8.7 sit in the same tile, so both reshape that tile's corners.
	tool.paint_at_point(Vector2(8.2, 8.2), grid, null)
	for vertex in [Vector2i(8, 8), Vector2i(9, 8), Vector2i(8, 9), Vector2i(9, 9)]:
		assert_eq(grid.get_vertex_elevation(vertex), BASE + 1, "corner %s of tile (8,8)" % vertex)
	assert_eq(grid.get_vertex_elevation(Vector2i(7, 7)), BASE)

func test_paint_requires_a_selected_tool_and_a_mode() -> void:
	tool.select_tool(ElevationTool.Tool.VERTEX)
	assert_eq(tool.paint_at_vertex(Vector2i(8, 8), grid, null), [])  # No button held
	tool.cancel()
	tool.elevation_mode = ElevationTool.ElevationMode.RAISING
	assert_eq(tool.paint_at_vertex(Vector2i(8, 8), grid, null), [])  # No tool selected
	tool.select_tool(ElevationTool.Tool.FLAT)
	assert_eq(tool.paint_at_tile(Vector2i(-1, 8), grid, null), [])  # Off the grid

func test_changes_support_undo_restore() -> void:
	tool.select_tool(ElevationTool.Tool.FLAT)
	tool.set_brush(3, true)
	tool.set_mode(true)
	var changes := tool.paint_at_tile(Vector2i(8, 8), grid, null)
	assert_gt(changes.size(), 0)
	for i in range(changes.size() - 1, -1, -1):
		var change = changes[i]
		grid.set_vertex_elevation(change.position, change.old_elevation)
	for vertex in _brush_vertices(Vector2i(8, 8), 3):
		assert_eq(grid.get_vertex_elevation(vertex), BASE)
