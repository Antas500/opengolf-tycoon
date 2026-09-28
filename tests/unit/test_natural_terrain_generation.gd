extends GutTest
## Natural terrain generation only paints zero-upkeep tiles offered on Course
## Terrain, and it never leaves Natural Grass on the map: the generated base
## turf is Rough.

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
	assert_false(T.GRASS in generated_types, "Natural Grass is the blank canvas, not a Course Terrain tool")

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

func test_generation_never_leaves_natural_grass_the_base_turf_is_rough() -> void:
	var grid := TerrainGrid.new()
	add_child_autofree(grid)
	var entities := EntityLayer.new()
	entities.map_seed = 7
	add_child_autofree(entities)
	entities.set_terrain_grid(grid)

	grid.begin_batch()
	NaturalTerrainGenerator.generate(grid, entities, 4242)
	grid.end_batch_quiet()

	var grass_count := 0
	var rough_count := 0
	for y in range(grid.grid_height):
		for x in range(grid.grid_width):
			var tile := grid.get_tile(Vector2i(x, y))
			if tile == T.GRASS:
				grass_count += 1
			elif tile == T.ROUGH:
				rough_count += 1
	assert_eq(grass_count, 0, "Terrain generation removes the Natural Grass tile from the map")
	assert_gt(rough_count, 0, "The generated base turf is Rough")
	assert_true(entities.trees.size() > 0, "Trees still grow on the Rough base")

func test_premium_rough_features_paint_onto_the_rough_base() -> void:
	var grid := TerrainGrid.new()
	add_child_autofree(grid)
	grid.begin_batch()
	for x in range(20):
		for y in range(20):
			grid.set_tile(Vector2i(x, y), T.ROUGH)
	grid.end_batch_quiet()

	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	PremiumFeatureGenerator._generate_scoped_rough(Rect2i(0, 0, 20, 20), grid, rng, 6, 8)

	var heavy_count := 0
	for x in range(20):
		for y in range(20):
			var tile := grid.get_tile(Vector2i(x, y))
			assert_true(tile in [T.ROUGH, T.HEAVY_ROUGH],
				"The scoped pass only raises rough on the Rough base")
			if tile == T.HEAVY_ROUGH:
				heavy_count += 1
	assert_gt(heavy_count, 0, "Heavy Rough clumps still land on the Rough base")

func test_premium_rough_features_convert_a_legacy_grass_parcel() -> void:
	var grid := TerrainGrid.new()
	add_child_autofree(grid)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	PremiumFeatureGenerator._generate_scoped_rough(Rect2i(0, 0, 20, 20), grid, rng, 6, 8)

	var rough_count := 0
	for x in range(20):
		for y in range(20):
			if grid.get_tile(Vector2i(x, y)) == T.ROUGH:
				rough_count += 1
	assert_gt(rough_count, 0, "A pre-rough-base grass parcel still grows Rough patches")
