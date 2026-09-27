extends GutTest
## Elevation hover-preview geometry: the Vertex tool is vertex-only, while the
## square tools tint the tiles their brush covers and mark the corner vertices
## they will move. Brush sizes are counted in tiles - a 3x3 brush is nine
## tiles holding sixteen vertices.

var grid: TerrainGrid
var preview: PlacementPreview

func before_each() -> void:
	grid = TerrainGrid.new()
	grid.grid_width = 8
	grid.grid_height = 8
	preview = PlacementPreview.new()
	preview.terrain_grid = grid

func test_vertex_selector_does_not_create_tile_highlights() -> void:
	preview.elevation_tool_type = ElevationTool.Tool.VERTEX
	var selected := preview._elevation_preview_vertices(Vector2i(4, 4))
	var tiles := preview._elevation_preview_tiles(Vector2i(4, 4))

	assert_eq(selected, [])
	assert_eq(tiles, [], "Vertex Selector shows its point marker only")

func test_flat_square_highlights_its_tiles_and_their_corners() -> void:
	preview.elevation_tool_type = ElevationTool.Tool.FLAT
	preview.elevation_brush_size = 3
	preview.elevation_brush_square = true
	var selected := preview._elevation_preview_vertices(Vector2i(4, 4))
	var tiles := preview._elevation_preview_tiles(Vector2i(4, 4))

	assert_eq(tiles.size(), 9, "3x3 tile brush highlights nine tiles")
	assert_eq(selected.size(), 16, "those tiles have sixteen corners")
	for tile in tiles:
		assert_true(grid.is_valid_position(tile), "preview tile stays on the terrain grid")
		for vertex in grid.vertices_of_tile(tile):
			assert_true(selected.has(vertex), "corner %s of tile %s is marked" % [vertex, tile])

func test_square_brush_growth_matches_one_vertex_per_tile_and_side() -> void:
	preview.elevation_tool_type = ElevationTool.Tool.FLAT
	preview.elevation_brush_square = true
	var expected_tiles := {1: 1, 2: 4, 3: 9, 4: 16}
	var expected_vertices := {1: 4, 2: 9, 3: 16, 4: 25}
	for size in expected_tiles:
		preview.elevation_brush_size = size
		var anchor := Vector2i(4, 4)
		assert_eq(preview._elevation_preview_tiles(anchor).size(), expected_tiles[size],
				"%dx%d brush tiles" % [size, size])
		assert_eq(preview._elevation_preview_vertices(anchor).size(), expected_vertices[size],
				"%dx%d brush vertices" % [size, size])

func test_round_brush_clips_the_preview_corners() -> void:
	preview.elevation_tool_type = ElevationTool.Tool.GRADUAL
	preview.elevation_brush_size = 5
	var expected_tiles := {3: 5, 4: 12, 5: 13}
	var expected_vertices := {3: 12, 4: 21, 5: 24}
	for size in expected_tiles:
		preview.elevation_brush_size = size
		var anchor := Vector2i(4, 4)
		preview.elevation_brush_square = false
		var round_tiles := preview._elevation_preview_tiles(anchor)
		var round_vertices := preview._elevation_preview_vertices(anchor)
		preview.elevation_brush_square = true
		var square_tiles := preview._elevation_preview_tiles(anchor)

		assert_eq(round_tiles.size(), expected_tiles[size], "%dx%d round brush tiles" % [size, size])
		assert_eq(round_vertices.size(), expected_vertices[size], "%dx%d round brush vertices" % [size, size])
		assert_lt(round_tiles.size(), square_tiles.size(),
				"the round shape clips corners the square keeps")
		for tile in round_tiles:
			assert_true(grid.is_valid_position(tile), "preview tile stays on the terrain grid")
		for vertex in round_vertices:
			assert_true(grid.is_valid_vertex(vertex), "preview vertex stays on the vertex grid")

func test_round_brush_preview_keeps_the_hovered_tile() -> void:
	preview.elevation_tool_type = ElevationTool.Tool.GRADUAL
	preview.elevation_brush_size = 5
	preview.elevation_brush_square = false
	var anchor := Vector2i(4, 4)
	var tiles := preview._elevation_preview_tiles(anchor)

	assert_true(tiles.has(anchor), "the tile under the cursor is always in the brush")
	for vertex in grid.vertices_of_tile(anchor):
		assert_true(preview._elevation_preview_vertices(anchor).has(vertex),
				"corner %s of the hovered tile is marked" % vertex)

func test_square_selector_preview_clips_at_the_grid_edge() -> void:
	preview.elevation_tool_type = ElevationTool.Tool.FLAT
	preview.elevation_brush_size = 3
	preview.elevation_brush_square = true
	var selected := preview._elevation_preview_vertices(Vector2i.ZERO)
	var tiles := preview._elevation_preview_tiles(Vector2i.ZERO)

	assert_eq(tiles.size(), 4, "only on-grid tiles are highlighted")
	assert_eq(selected.size(), 9, "and their corners are selected")
	for tile in tiles:
		assert_true(grid.is_valid_position(tile), "preview does not draw outside the grid")
