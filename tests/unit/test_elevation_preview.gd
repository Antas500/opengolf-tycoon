extends GutTest
## Elevation hover-preview geometry: the Vertex tool is vertex-only, while
## square tools tint the tiles touched by their selected vertices.

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
	var tiles := preview._elevation_preview_tiles(selected)

	assert_eq(selected, [])
	assert_eq(tiles, [], "Vertex Selector shows its point marker only")

func test_flat_square_highlights_tiles_and_their_connected_vertices() -> void:
	preview.elevation_tool_type = ElevationTool.Tool.FLAT
	preview.elevation_brush_size = 3
	preview.elevation_brush_square = true
	var selected := preview._elevation_preview_vertices(Vector2i(4, 4))
	var tiles := preview._elevation_preview_tiles(selected)
	var connected := preview._elevation_preview_connected_vertices(tiles)

	assert_eq(selected.size(), 9, "3x3 vertex brush selection")
	assert_eq(tiles.size(), 16, "all tiles touching the selected vertices")
	assert_eq(connected.size(), 25, "all unique corners of the highlighted tiles")
	for vertex in selected:
		assert_true(connected.has(vertex), "selected vertex %s is shown" % vertex)

func test_gradual_round_brush_highlights_only_unique_in_bounds_tiles() -> void:
	preview.elevation_tool_type = ElevationTool.Tool.GRADUAL
	preview.elevation_brush_size = 5
	preview.elevation_brush_square = false
	var selected := preview._elevation_preview_vertices(Vector2i(4, 4))
	var tiles := preview._elevation_preview_tiles(selected)
	var connected := preview._elevation_preview_connected_vertices(tiles)
	var unique_tiles := {}

	assert_gt(selected.size(), 0)
	assert_lt(selected.size(), 25, "round clipping excludes brush corners")
	for tile in tiles:
		assert_true(grid.is_valid_position(tile), "preview tile stays on the terrain grid")
		assert_false(unique_tiles.has(tile), "overlapping vertex tiles are deduplicated")
		unique_tiles[tile] = true
	for vertex in selected:
		assert_true(connected.has(vertex), "selected vertex %s is connected to a highlighted tile" % vertex)

func test_square_selector_preview_clips_at_the_grid_edge() -> void:
	preview.elevation_tool_type = ElevationTool.Tool.FLAT
	preview.elevation_brush_size = 3
	preview.elevation_brush_square = true
	var selected := preview._elevation_preview_vertices(Vector2i.ZERO)
	var tiles := preview._elevation_preview_tiles(selected)

	assert_eq(selected.size(), 4, "only on-grid vertices are selected")
	for tile in tiles:
		assert_true(grid.is_valid_position(tile), "preview does not draw outside the grid")
