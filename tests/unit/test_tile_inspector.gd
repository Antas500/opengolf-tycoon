extends GutTest

var grid: TerrainGrid
var entities: EntityLayer
const TILE := Vector2i(2, 2)

func before_each() -> void:
	# The panel test below clamps against the real viewport, which is a
	# desktop-sized window (the game renders at native window size).
	get_window().size = Vector2i(1600, 1000)
	await get_tree().process_frame
	await get_tree().process_frame
	grid = TerrainGrid.new()
	grid.grid_width = 8
	grid.grid_height = 8
	add_child_autofree(grid)
	grid.set_tile(TILE, TerrainTypes.Type.ROUGH)
	# Data-only entities avoid generating artwork in these lookup tests.
	entities = autofree(EntityLayer.new())

func test_empty_tile_reports_all_three_categories() -> void:
	assert_eq(TileInspector.describe_tile(grid, entities, TILE), {
		"terrain": TerrainTypes.get_type_name(TerrainTypes.Type.ROUGH),
		"improvements": "None", "buildings": "None"})

func test_path_is_an_improvement_and_preserves_underlying_terrain() -> void:
	grid.set_walking_path(TILE, true)
	var details := TileInspector.describe_tile(grid, entities, TILE)
	assert_eq(details.terrain, TerrainTypes.get_type_name(TerrainTypes.Type.ROUGH))
	assert_eq(details.improvements, "Walking Path")
	assert_eq(grid.get_tile(TILE), TerrainTypes.Type.ROUGH)
	assert_true(grid.has_walking_path(TILE))

func test_decoration_lookup_includes_entire_footprint() -> void:
	var decoration: Decoration = autofree(Decoration.new())
	decoration.grid_position = TILE
	decoration.size = Vector2i(2, 2)
	decoration.decoration_data = {"name": "Garden Fountain"}
	entities.decorations[TILE] = decoration
	for offset in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		assert_eq(TileInspector.describe_tile(grid, entities, TILE + offset).improvements, "Garden Fountain")
	assert_eq(TileInspector.describe_tile(grid, entities, TILE + Vector2i(2, 0)).improvements, "None")

func test_building_lookup_includes_entire_footprint_and_display_name() -> void:
	var building: Building = autofree(Building.new())
	building.grid_position = TILE
	building.width = 3
	building.height = 2
	building.building_data = {"name": "Clubhouse"}
	entities.buildings[TILE] = building
	for x in 3:
		for y in 2:
			assert_eq(TileInspector.describe_tile(grid, entities, TILE + Vector2i(x, y)).buildings, "Clubhouse")
	assert_eq(TileInspector.describe_tile(grid, entities, TILE + Vector2i(3, 0)).buildings, "None")

func test_trees_and_rocks_are_terrain_not_improvements() -> void:
	var tree: TreeEntity = autofree(TreeEntity.new())
	tree.tree_data = {"name": "Oak Tree"}
	entities.trees[TILE] = tree
	assert_string_contains(TileInspector.describe_tile(grid, entities, TILE).terrain, "Oak Tree")
	assert_eq(TileInspector.describe_tile(grid, entities, TILE).improvements, "None")
	entities.trees.clear()
	var rock: Rock = autofree(Rock.new())
	rock.rock_data = {"name": "Large Rock"}
	entities.rocks[TILE] = rock
	assert_string_contains(TileInspector.describe_tile(grid, entities, TILE).terrain, "Large Rock")

func test_invalid_tiles_have_no_details() -> void:
	assert_eq(TileInspector.describe_tile(grid, entities, Vector2i(-1, 0)), {})
	assert_eq(TileInspector.describe_tile(grid, entities, Vector2i(8, 0)), {})

func test_panel_updates_hides_and_stays_in_viewport() -> void:
	var panel: TileInspector = add_child_autofree(TileInspector.new())
	var mouse := get_viewport().get_visible_rect().size - Vector2.ONE
	panel.show_tile(grid, entities, TILE, mouse)
	await get_tree().process_frame
	panel.show_tile(grid, entities, TILE, mouse)
	assert_true(panel.visible)
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_true(get_viewport().get_visible_rect().encloses(panel.get_rect()))
	grid.set_walking_path(TILE, true)
	panel.show_tile(grid, entities, TILE, mouse)
	assert_string_contains(panel._details.text, "Walking Path")
	panel.show_tile(grid, entities, Vector2i(-1, 0), mouse)
	assert_false(panel.visible)
