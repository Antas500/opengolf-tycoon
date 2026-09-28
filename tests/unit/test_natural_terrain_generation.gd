extends GutTest
## Natural terrain generation only paints zero-upkeep tiles offered on Course Terrain.

const T := TerrainTypes.Type

func test_generation_inventory_is_course_tab_only_and_has_no_upkeep() -> void:
	var generated_types := TerrainTypes.get_natural_generation_types()
	assert_true(T.FLOWER_BED in generated_types, "Wild Flowers is a landscape tile on Course Terrain")
	assert_true(T.TREES in generated_types, "Theme trees are landscape tiles on Course Terrain")
	assert_true(T.ROUGH in generated_types)
	assert_true(T.DEEP_ROUGH in generated_types)
	assert_true(T.WATER in generated_types)
	assert_true(T.STREAM in generated_types)
	assert_true(T.WASTE_BUNKER in generated_types)
	assert_true(T.BRUSH in generated_types)
	assert_true(T.ROCKS in generated_types)

	for type in generated_types:
		assert_eq(TerrainTypes.get_maintenance_cost(type), 0,
			"Generated terrain %s must not add maintenance" % TerrainTypes.get_type_name(type))
		assert_true(type in TerrainTypes.COURSE_PAINT_TYPES or type in [T.FLOWER_BED, T.TREES],
			"Generated terrain %s must be offered on Course Terrain" % TerrainTypes.get_type_name(type))

func test_maintenance_terrain_and_non_course_tiles_are_excluded() -> void:
	var generated_types := TerrainTypes.get_natural_generation_types()
	for type in [T.FAIRWAY, T.FIRM_FAIRWAY, T.GREEN, T.TEE_BOX, T.BUNKER, T.POT_BUNKER]:
		assert_false(type in generated_types,
			"%s has an upkeep cost and must not be generated" % TerrainTypes.get_type_name(type))
	assert_false(T.HEAVY_ROUGH in generated_types, "Heavy Rough is not a Course Terrain tab tile")
	assert_false(T.GRASS in generated_types, "Natural Grass is the base surface, not a Course Terrain tool")

func test_generator_rejects_tiles_outside_the_eligible_inventory() -> void:
	var grid := TerrainGrid.new()
	var pos := Vector2i(2, 3)
	grid._grid[pos] = T.GRASS

	NaturalTerrainGenerator._set_generated_tile(grid, pos, T.HEAVY_ROUGH)
	assert_eq(grid.get_tile(pos), T.GRASS, "Heavy Rough cannot be painted by generation")
	NaturalTerrainGenerator._set_generated_tile(grid, pos, T.FAIRWAY)
	assert_eq(grid.get_tile(pos), T.GRASS, "A maintained tile cannot be painted by generation")

	NaturalTerrainGenerator._set_generated_tile(grid, pos, T.DEEP_ROUGH)
	assert_eq(grid.get_tile(pos), T.DEEP_ROUGH, "Deep Rough is a zero-upkeep Course Terrain tile")
