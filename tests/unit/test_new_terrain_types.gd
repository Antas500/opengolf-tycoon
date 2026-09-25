extends GutTest
## Firm Fairway, Pot Bunker, Stream, Deep Rough, Waste Bunker, Rocks and Brush:
## save-compatible ids, terrain families, golf rules, roll-out, shot AI,
## rendering data, the Course Terrain toolbar and boulder footprints.

const T := TerrainTypes.Type
const NEW_TYPES := [T.FIRM_FAIRWAY, T.POT_BUNKER, T.STREAM, T.DEEP_ROUGH,
	T.WASTE_BUNKER, T.ROCKS, T.BRUSH]

var _saved_terrain_grid
var _saved_course_data
var _saved_mode

func before_each() -> void:
	_saved_terrain_grid = GameManager.terrain_grid
	_saved_course_data = GameManager.course_data
	_saved_mode = GameManager.current_mode

func after_each() -> void:
	GameManager.terrain_grid = _saved_terrain_grid
	GameManager.course_data = _saved_course_data
	GameManager.current_mode = _saved_mode

func _grid(size: int = 16, fill: int = T.GRASS) -> TerrainGrid:
	var grid: TerrainGrid = autofree(TerrainGrid.new())
	grid.grid_width = size
	grid.grid_height = size
	for x in size:
		for y in size:
			grid._grid[Vector2i(x, y)] = fill
	return grid

# --- Ids, properties and save compatibility ----------------------------------

func test_new_ids_are_appended_so_saved_terrain_keeps_its_meaning() -> void:
	assert_eq(T.ROCKS, 13, "Existing ids are unchanged")
	assert_eq(T.FIRM_FAIRWAY, 14)
	assert_eq(T.POT_BUNKER, 15)
	assert_eq(T.STREAM, 16)
	assert_eq(T.DEEP_ROUGH, 17)
	assert_eq(T.WASTE_BUNKER, 18)
	assert_eq(T.BRUSH, 19)
	assert_eq(T.values().size(), 20)

func test_every_type_has_properties_names_and_costs() -> void:
	var names := {}
	for type in T.values():
		assert_true(TerrainTypes.PROPERTIES.has(type), "Type %d has properties" % type)
		var name: String = TerrainTypes.get_type_name(type)
		assert_false(names.has(name), "Terrain names are unique: %s" % name)
		names[name] = true
	for type in NEW_TYPES:
		assert_gt(TerrainTypes.get_placement_cost(type), 0, "%s costs money to paint" % TerrainTypes.get_type_name(type))
	assert_eq(TerrainTypes.get_type_name(T.FIRM_FAIRWAY), "Firm Fairway")
	assert_eq(TerrainTypes.get_type_name(T.POT_BUNKER), "Pot Bunker")
	assert_eq(TerrainTypes.get_type_name(T.STREAM), "Stream")
	assert_eq(TerrainTypes.get_type_name(T.DEEP_ROUGH), "Deep Rough")
	assert_eq(TerrainTypes.get_type_name(T.WASTE_BUNKER), "Waste Bunker")
	assert_eq(TerrainTypes.get_type_name(T.ROCKS), "Rocks")
	assert_eq(TerrainTypes.get_type_name(T.BRUSH), "Brush")

func test_upkeep_and_hazard_flags() -> void:
	assert_gt(TerrainTypes.get_maintenance_cost(T.POT_BUNKER), TerrainTypes.get_maintenance_cost(T.BUNKER),
		"Revetted faces need rebuilding more often than a bunker is raked")
	assert_eq(TerrainTypes.get_maintenance_cost(T.WASTE_BUNKER), 0, "Waste areas are never raked")
	assert_eq(TerrainTypes.get_maintenance_cost(T.DEEP_ROUGH), 0, "Deep rough is left unmown")
	assert_true(TerrainTypes.is_hazard(T.POT_BUNKER))
	assert_true(TerrainTypes.is_hazard(T.STREAM))
	assert_false(TerrainTypes.is_hazard(T.WASTE_BUNKER), "A waste bunker is not a hazard")
	assert_false(TerrainTypes.is_playable(T.STREAM))
	assert_lt(TerrainTypes.get_speed_modifier(T.BRUSH), 1.0, "Golfers wade slowly through brush")

func test_json_mirror_lists_every_type() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/terrain_types.json"))
	var by_id := {}
	for key in data.terrain_types:
		by_id[int(data.terrain_types[key].id)] = data.terrain_types[key]
	for type in T.values():
		assert_true(by_id.has(type), "terrain_types.json lists id %d" % type)
	for type in NEW_TYPES:
		assert_eq(by_id[type].name, TerrainTypes.get_type_name(type))
		assert_eq(int(by_id[type].placement_cost), TerrainTypes.get_placement_cost(type))

func test_new_tiles_round_trip_through_a_save() -> void:
	var grid := _grid(8)
	for i in NEW_TYPES.size():
		grid.set_tile(Vector2i(i, 0), NEW_TYPES[i])
	var saved := grid.serialize()
	var loaded := _grid(8)
	loaded.deserialize(saved)
	for i in NEW_TYPES.size():
		assert_eq(loaded.get_tile(Vector2i(i, 0)), NEW_TYPES[i])

# --- Families ------------------------------------------------------------------

func test_families_group_each_variant_with_its_parent() -> void:
	assert_true(TerrainTypes.is_fairway(T.FIRM_FAIRWAY))
	assert_true(TerrainTypes.is_fairway(T.FAIRWAY))
	assert_true(TerrainTypes.is_rough(T.DEEP_ROUGH))
	assert_true(TerrainTypes.is_rough(T.HEAVY_ROUGH))
	assert_true(TerrainTypes.is_bunker(T.POT_BUNKER))
	assert_false(TerrainTypes.is_bunker(T.WASTE_BUNKER), "Waste areas don't plug the ball like a bunker")
	assert_true(TerrainTypes.is_sand(T.WASTE_BUNKER))
	assert_true(TerrainTypes.is_water(T.STREAM))
	assert_true(TerrainTypes.is_out_of_play(T.STREAM))
	assert_false(TerrainTypes.is_out_of_play(T.ROCKS))
	for type in NEW_TYPES:
		assert_true(type in TerrainTypes.COURSE_PAINT_TYPES, "%s is a paintable course tile" % TerrainTypes.get_type_name(type))

# --- Golf rules ------------------------------------------------------------------

func test_stream_is_a_penalty_area_like_water() -> void:
	assert_eq(GolfRules.get_penalty_strokes(T.STREAM), 1)
	assert_eq(GolfRules.get_relief_type(T.STREAM), GolfRules.ReliefType.DROP_AT_ENTRY)

func test_new_playable_ground_needs_no_relief() -> void:
	for type in [T.FIRM_FAIRWAY, T.POT_BUNKER, T.DEEP_ROUGH, T.WASTE_BUNKER, T.ROCKS, T.BRUSH]:
		assert_eq(GolfRules.get_penalty_strokes(type), 0)
		assert_eq(GolfRules.get_relief_type(type), GolfRules.ReliefType.NONE)

func test_pot_bunker_is_harsher_than_a_deep_bunker() -> void:
	for club in [Golfer.Club.WEDGE, Golfer.Club.IRON]:
		assert_lt(GolfRules.get_lie_modifier(T.POT_BUNKER, club),
			GolfRules.get_lie_modifier(T.BUNKER, club, 1))
	assert_lt(GolfRules.get_terrain_distance_modifier(T.POT_BUNKER),
		GolfRules.get_terrain_distance_modifier(T.BUNKER, 1))

func test_deep_rough_is_harsher_than_heavy_rough() -> void:
	assert_lt(GolfRules.get_lie_modifier(T.DEEP_ROUGH, Golfer.Club.IRON),
		GolfRules.get_lie_modifier(T.HEAVY_ROUGH, Golfer.Club.IRON))
	assert_lt(GolfRules.get_terrain_distance_modifier(T.DEEP_ROUGH),
		GolfRules.get_terrain_distance_modifier(T.HEAVY_ROUGH))

func test_waste_bunker_plays_easier_than_a_bunker() -> void:
	for club in [Golfer.Club.WEDGE, Golfer.Club.IRON]:
		assert_gt(GolfRules.get_lie_modifier(T.WASTE_BUNKER, club), GolfRules.get_lie_modifier(T.BUNKER, club))
	assert_gt(GolfRules.get_terrain_distance_modifier(T.WASTE_BUNKER), GolfRules.get_terrain_distance_modifier(T.BUNKER))

func test_firm_fairway_is_a_tight_full_distance_lie() -> void:
	assert_eq(GolfRules.get_lie_modifier(T.FIRM_FAIRWAY, Golfer.Club.DRIVER), 1.0)
	assert_lt(GolfRules.get_lie_modifier(T.FIRM_FAIRWAY, Golfer.Club.WEDGE), 1.0, "Little cushion for wedges")
	assert_eq(GolfRules.get_terrain_distance_modifier(T.FIRM_FAIRWAY), 1.0)

func test_brush_and_rocks_are_hack_outs() -> void:
	assert_lte(GolfRules.get_lie_modifier(T.BRUSH, Golfer.Club.WEDGE), GolfRules.get_lie_modifier(T.TREES, Golfer.Club.WEDGE))
	assert_eq(GolfRules.get_lie_modifier(T.ROCKS, Golfer.Club.WEDGE), 0.25, "Rocks keep their existing lie")
	assert_eq(GolfRules.get_terrain_distance_modifier(T.ROCKS), 0.5)
	assert_eq(GolfRules.get_terrain_distance_modifier(T.BRUSH), 0.5)

func test_roll_multipliers_keep_existing_values_and_rank_the_new_ground() -> void:
	# Existing surfaces are unchanged by moving the table into GolfRules.
	assert_eq(GolfRules.get_roll_multiplier(T.GREEN), 1.3)
	assert_eq(GolfRules.get_roll_multiplier(T.FAIRWAY), 1.0)
	assert_eq(GolfRules.get_roll_multiplier(T.ROUGH), 0.3)
	assert_eq(GolfRules.get_roll_multiplier(T.HEAVY_ROUGH), 0.12)
	assert_eq(GolfRules.get_roll_multiplier(T.PATH), 1.4)
	assert_eq(GolfRules.get_roll_multiplier(T.ROCKS), 0.15)
	assert_gt(GolfRules.get_roll_multiplier(T.FIRM_FAIRWAY), GolfRules.get_roll_multiplier(T.GREEN),
		"Firm fairway is the fastest-running turf")
	assert_lt(GolfRules.get_roll_multiplier(T.DEEP_ROUGH), GolfRules.get_roll_multiplier(T.HEAVY_ROUGH))
	assert_lt(GolfRules.get_roll_multiplier(T.BRUSH), GolfRules.get_roll_multiplier(T.DEEP_ROUGH))

func test_which_ground_stops_or_catches_the_ball() -> void:
	for type in [T.WATER, T.STREAM, T.BUNKER, T.POT_BUNKER, T.OUT_OF_BOUNDS, T.FLOWER_BED]:
		assert_true(GolfRules.stops_ball_on_landing(type), "%s stops a landing ball" % TerrainTypes.get_type_name(type))
	for type in [T.WASTE_BUNKER, T.FIRM_FAIRWAY, T.DEEP_ROUGH, T.ROCKS, T.BRUSH]:
		assert_false(GolfRules.stops_ball_on_landing(type))
	for type in [T.STREAM, T.POT_BUNKER, T.DEEP_ROUGH, T.BRUSH]:
		assert_true(GolfRules.catches_rolling_ball(type), "%s catches a rolling ball" % TerrainTypes.get_type_name(type))
	for type in [T.FAIRWAY, T.FIRM_FAIRWAY, T.ROUGH, T.WASTE_BUNKER, T.GREEN]:
		assert_false(GolfRules.catches_rolling_ball(type))

# --- Roll-out on the course ----------------------------------------------------

func _rollout_on(landing: int, beyond: int = -1) -> Dictionary:
	var grid := _grid(32, landing)
	if beyond >= 0:
		for x in range(19, 32):
			for y in 32:
				grid._grid[Vector2i(x, y)] = beyond
	GameManager.terrain_grid = grid
	var golfer: Golfer = autofree(Golfer.new())
	# An 8-tile iron carry landing at (18, 10), rolling on toward +x.
	return golfer._calculate_rollout(Golfer.Club.IRON, Vector2i(18, 10), Vector2(18, 10),
		Vector2(10, 10), 8.0, 0.9, true)

func test_firm_fairway_releases_the_ball_farther_than_fairway() -> void:
	var soft := _rollout_on(T.FAIRWAY)
	var firm := _rollout_on(T.FIRM_FAIRWAY)
	assert_gt(soft.rollout_distance, 0.0)
	assert_almost_eq(firm.rollout_distance / soft.rollout_distance, 1.6, 0.05)

func test_deep_rough_and_brush_snag_a_rolling_ball() -> void:
	var open := _rollout_on(T.FIRM_FAIRWAY)
	assert_gt(open.final_position.x, 19.0, "On open ground the ball runs on into tile 19")
	for snag in [T.DEEP_ROUGH, T.BRUSH]:
		var caught := _rollout_on(T.FIRM_FAIRWAY, snag)
		assert_eq(Vector2i(caught.final_position.round()).x, 19, "The ball stops where it enters the long stuff")
		assert_lt(caught.final_position.x, open.final_position.x - 0.3)

func test_ball_landing_in_a_stream_or_pot_bunker_does_not_roll() -> void:
	for type in [T.STREAM, T.POT_BUNKER]:
		var result := _rollout_on(type)
		assert_eq(result.rollout_distance, 0.0)

func test_stream_penalty_drops_at_the_point_of_entry_on_dry_ground() -> void:
	var grid := _grid(20)
	for x in 20:
		grid._grid[Vector2i(x, 10)] = T.STREAM
		grid._grid[Vector2i(x, 11)] = T.STREAM
	GameManager.terrain_grid = grid
	var course_data = GameManager.CourseData.new()
	var hole = GameManager.HoleData.new()
	hole.hole_position = Vector2i(10, 18)
	course_data.add_hole(hole)
	GameManager.course_data = course_data
	var golfer: Golfer = autofree(Golfer.new())
	golfer.current_hole = 0
	var entry := golfer._find_water_entry_point(Vector2i(10, 4), Vector2i(10, 11))
	assert_eq(entry, Vector2i(10, 10), "Entry is where the flight first crosses the stream")
	var drop := golfer._find_water_drop_position(entry)
	assert_false(TerrainTypes.is_water(grid.get_tile(drop)), "Dropped out of the stream")
	assert_gte(Vector2(drop).distance_to(Vector2(hole.hole_position)),
		Vector2(entry).distance_to(Vector2(hole.hole_position)), "No nearer the hole than the entry")

# --- Shot AI -----------------------------------------------------------------------

func test_shot_ai_scores_every_terrain_type() -> void:
	for type in T.values():
		assert_true(ShotAI.TERRAIN_SCORES.has(type), "ShotAI scores %s" % TerrainTypes.get_type_name(type))
	assert_eq(ShotAI.TERRAIN_SCORES[T.STREAM], ShotAI.TERRAIN_SCORES[T.WATER])
	assert_lt(ShotAI.TERRAIN_SCORES[T.POT_BUNKER], ShotAI.TERRAIN_SCORES[T.BUNKER])
	assert_lt(ShotAI.TERRAIN_SCORES[T.DEEP_ROUGH], ShotAI.TERRAIN_SCORES[T.HEAVY_ROUGH])
	assert_gt(ShotAI.TERRAIN_SCORES[T.WASTE_BUNKER], ShotAI.TERRAIN_SCORES[T.BUNKER])
	assert_gt(ShotAI.TERRAIN_SCORES[T.FIRM_FAIRWAY], ShotAI.TERRAIN_SCORES[T.ROUGH])

func test_shot_ai_plays_recovery_from_the_trouble_lies() -> void:
	for type in [T.POT_BUNKER, T.DEEP_ROUGH, T.ROCKS, T.BRUSH]:
		assert_lt(ShotAI._assess_lie_quality(type), 0.4, "%s is a recovery lie" % TerrainTypes.get_type_name(type))
	for type in [T.FIRM_FAIRWAY, T.WASTE_BUNKER]:
		assert_gte(ShotAI._assess_lie_quality(type), 0.4, "%s plays a normal shot" % TerrainTypes.get_type_name(type))
	assert_eq(ShotAI._get_recovery_clubs(T.POT_BUNKER), [Golfer.Club.WEDGE])
	assert_eq(ShotAI._get_recovery_clubs(T.BRUSH), [Golfer.Club.WEDGE])
	assert_false(Golfer.Club.FAIRWAY_WOOD in ShotAI._get_recovery_clubs(T.DEEP_ROUGH))

func test_hole_difficulty_counts_the_new_hazards() -> void:
	var grid := _grid(10)
	var bunkers: Array = [Vector2i(1, 1), Vector2i(2, 1)]
	grid._grid[bunkers[0]] = T.BUNKER
	grid._grid[bunkers[1]] = T.BUNKER
	var plain := DifficultyCalculator._calculate_hazard_difficulty(bunkers, grid)
	grid._grid[bunkers[0]] = T.POT_BUNKER
	grid._grid[bunkers[1]] = T.POT_BUNKER
	assert_gt(DifficultyCalculator._calculate_hazard_difficulty(bunkers, grid), plain)
	grid._grid[bunkers[0]] = T.STREAM
	grid._grid[bunkers[1]] = T.WATER
	assert_almost_eq(DifficultyCalculator._calculate_hazard_difficulty(bunkers, grid), 0.6, 0.001,
		"A stream tile weighs like a water tile")

func test_hole_difficulty_ignores_lone_boulders_but_counts_painted_rocks() -> void:
	var grid := _grid(10)
	var tiles: Array = [Vector2i(3, 3)]
	grid._grid[tiles[0]] = T.ROCKS
	assert_gt(DifficultyCalculator._calculate_hazard_difficulty(tiles, grid), 0.0)
	grid.set_object_footprint(tiles[0], true)
	assert_eq(DifficultyCalculator._calculate_hazard_difficulty(tiles, grid), 0.0)

# --- Boulder footprints and the course surface ----------------------------------

func test_footprint_marks_clear_whenever_the_terrain_changes() -> void:
	var grid := _grid(8)
	grid.set_tile(Vector2i(2, 2), T.ROCKS)
	grid.set_object_footprint(Vector2i(2, 2), true)
	assert_true(grid.is_object_footprint(Vector2i(2, 2)))
	grid.set_tile(Vector2i(2, 2), T.ROUGH)
	assert_false(grid.is_object_footprint(Vector2i(2, 2)), "Repainting drops the mark")
	grid.set_tile(Vector2i(3, 3), T.ROCKS)
	grid.set_object_footprint(Vector2i(3, 3), true)
	var copy := grid.create_analysis_copy()
	assert_true(copy.is_object_footprint(Vector2i(3, 3)), "Shot planning copies see the marks")
	copy.free()
	grid.deserialize(grid.serialize())
	assert_false(grid.is_object_footprint(Vector2i(3, 3)), "Loading rebuilds marks from the entities")

func test_boulders_keep_native_turf_but_painted_rocks_render_as_stone() -> void:
	var grid: TerrainGrid = TerrainGrid.new()
	grid.grid_width = 8
	grid.grid_height = 8
	add_child_autofree(grid)
	var entities := EntityLayer.new()
	entities.map_seed = 99
	add_child_autofree(entities)
	entities.set_terrain_grid(grid)

	entities.place_rock(Vector2i(2, 2), "small")
	assert_eq(grid.get_tile(Vector2i(2, 2)), T.ROCKS, "A boulder still plays as Rocks")
	assert_true(grid.is_object_footprint(Vector2i(2, 2)))
	assert_eq(grid._course_surface._data.get_pixel(2, 2).a, 0.0, "The surface draws native turf under it")

	grid.set_tile(Vector2i(5, 5), T.ROCKS)
	assert_eq(grid._course_surface._data.get_pixel(5, 5).a, 1.0, "Painted Rocks render as stony ground")
	entities.place_rock(Vector2i(5, 5), "medium")
	assert_false(grid.is_object_footprint(Vector2i(5, 5)), "A boulder on painted Rocks sits on the stones")

	entities.remove_rock(Vector2i(2, 2))
	assert_eq(grid.get_tile(Vector2i(2, 2)), T.GRASS)
	assert_false(grid.is_object_footprint(Vector2i(2, 2)))
	entities.remove_rock(Vector2i(5, 5))
	assert_eq(grid.get_tile(Vector2i(5, 5)), T.ROCKS, "Removing it leaves the painted Rocks")

func test_painting_rocks_around_a_boulder_merges_it_into_the_ground() -> void:
	var grid: TerrainGrid = TerrainGrid.new()
	grid.grid_width = 8
	grid.grid_height = 8
	add_child_autofree(grid)
	var entities := EntityLayer.new()
	add_child_autofree(entities)
	entities.set_terrain_grid(grid)
	entities.place_rock(Vector2i(4, 4), "large")
	assert_true(entities.merge_rock_into_painted_rocks(Vector2i(4, 4)))
	assert_false(grid.is_object_footprint(Vector2i(4, 4)))
	assert_false(entities.merge_rock_into_painted_rocks(Vector2i(4, 4)), "Only once")
	entities.remove_rock(Vector2i(4, 4))
	assert_eq(grid.get_tile(Vector2i(4, 4)), T.ROCKS)

func test_saved_boulders_reload_with_their_footprints() -> void:
	var grid: TerrainGrid = TerrainGrid.new()
	grid.grid_width = 8
	grid.grid_height = 8
	add_child_autofree(grid)
	var entities := EntityLayer.new()
	add_child_autofree(entities)
	entities.set_terrain_grid(grid)
	entities.place_rock(Vector2i(1, 1), "small")
	grid.set_tile(Vector2i(3, 3), T.ROCKS)
	entities.place_rock(Vector2i(3, 3), "small")
	var terrain := grid.serialize()
	var saved := entities.serialize()
	grid.deserialize(terrain)
	entities.deserialize(saved)
	assert_true(grid.is_object_footprint(Vector2i(1, 1)), "The boulder on grass keeps its grass look")
	assert_false(grid.is_object_footprint(Vector2i(3, 3)), "The boulder on painted Rocks stays on stone")

	# An older save without original terrain: the boulder stood on native grass.
	saved.erase("original_terrain")
	grid.deserialize(terrain)
	entities.deserialize(saved)
	assert_true(grid.is_object_footprint(Vector2i(1, 1)))
	entities.remove_rock(Vector2i(1, 1))
	assert_eq(grid.get_tile(Vector2i(1, 1)), T.GRASS, "Removing it leaves grass, not a bare Rocks lie")

func test_boulder_placement_rules() -> void:
	var grid := _grid(8)
	var placement := PlacementManager.new()
	grid._grid[Vector2i(1, 1)] = T.ROCKS
	assert_true(placement._can_place_rock(Vector2i(1, 1), grid), "Boulders can sit on painted Rocks")
	grid.set_object_footprint(Vector2i(1, 1), true)
	assert_false(placement._can_place_rock(Vector2i(1, 1), grid), "One boulder per tile")
	grid._grid[Vector2i(2, 2)] = T.DEEP_ROUGH
	assert_true(placement._can_place_rock(Vector2i(2, 2), grid))
	assert_true(placement._can_place_tree(Vector2i(2, 2), grid))
	for type in [T.WASTE_BUNKER, T.BRUSH, T.STREAM, T.POT_BUNKER]:
		grid._grid[Vector2i(3, 3)] = type
		assert_false(placement._can_place_rock(Vector2i(3, 3), grid))
		assert_false(placement._can_place_tree(Vector2i(3, 3), grid))

func test_every_theme_colors_every_palette_key() -> void:
	assert_eq(CourseSurface.PALETTE_KEYS.size(), T.values().size(), "One palette entry per terrain id")
	for key in CourseSurface.PALETTE_KEYS:
		assert_true(TilesetGenerator.TERRAIN_COLORS.has(key), "Default palette has %s" % key)
		for theme in CourseTheme.Type.values():
			assert_true(CourseTheme.get_terrain_colors(theme).has(key),
				"%s theme colors %s" % [CourseTheme.to_string_name(theme), key])
	var palette := CourseSurface.make_palette_texture().get_image()
	assert_eq(palette.get_width(), T.values().size(), "The shader reads the palette width as the id count")

func test_legacy_tileset_maps_variants_to_their_family_rows() -> void:
	assert_eq(TilesetGenerator.get_autotile_coords(T.FIRM_FAIRWAY, 0).y, TilesetGenerator.TerrainRow.FAIRWAY)
	assert_eq(TilesetGenerator.get_autotile_coords(T.POT_BUNKER, 0).y, TilesetGenerator.TerrainRow.BUNKER)
	assert_eq(TilesetGenerator.get_autotile_coords(T.STREAM, 0).y, TilesetGenerator.TerrainRow.WATER)
	assert_eq(TilesetGenerator.get_autotile_coords(T.DEEP_ROUGH, 0).y, TilesetGenerator.TerrainRow.HEAVY_ROUGH)

# --- Painting ---------------------------------------------------------------------

func test_stream_strokes_are_edge_connected() -> void:
	var points := TerrainBrush.centers_4_connected(Vector2i(2, 2), Vector2i(7, 5))
	assert_eq(points[0], Vector2i(2, 2))
	assert_eq(points[points.size() - 1], Vector2i(7, 5))
	for i in range(1, points.size()):
		var step: Vector2i = (points[i] - points[i - 1]).abs()
		assert_eq(step.x + step.y, 1, "Every step shares an edge with the last")

# --- Toolbar ------------------------------------------------------------------------

func test_toolbar_paints_all_course_tiles_in_two_rows() -> void:
	var toolbar := TerrainToolbar.new()
	add_child_autofree(toolbar)
	var grid: TileHoneycomb = toolbar._tool_buttons[T.FAIRWAY].get_parent()
	var landscape_count := 4 + CourseTheme.get_tree_types(GameManager.current_theme).size()
	assert_eq(grid.get_child_count(), TerrainTypes.COURSE_PAINT_TYPES.size() + landscape_count)
	for i in TerrainTypes.COURSE_PAINT_TYPES.size():
		var type: int = TerrainTypes.COURSE_PAINT_TYPES[i]
		var button: TerrainTileButton = toolbar._tool_buttons[type]
		var slot := i if i < TerrainToolbar.COURSE_TILE_COLUMNS else grid.columns + i - TerrainToolbar.COURSE_TILE_COLUMNS
		assert_eq(button.get_index(), slot, "%s sits in toolbar order" % TerrainTypes.get_type_name(type))
		assert_eq(button.tool_name, TerrainTypes.get_type_name(type))
		assert_eq(TerrainToolbar.TOOL_TAB_MAP[type], TerrainToolbar.Tab.TERRAIN)
	# Two rows include both course and landscape tiles.
	assert_eq(grid.columns, ceili(float(grid.get_child_count()) / 2.0),
		"The two rows hold every course and landscape tile")
	for type in [T.TEE_BOX, T.GREEN, T.BUNKER, T.ROUGH, T.POT_BUNKER, T.STREAM, T.WATER]:
		assert_lt(toolbar._tool_buttons[type].get_index(), grid.columns,
			"%s on the top row" % TerrainTypes.get_type_name(type))
	for type in [T.FAIRWAY, T.FIRM_FAIRWAY, T.DEEP_ROUGH, T.WASTE_BUNKER, T.BRUSH, T.ROCKS, T.OUT_OF_BOUNDS]:
		assert_gte(toolbar._tool_buttons[type].get_index(), grid.columns,
			"%s on the bottom row" % TerrainTypes.get_type_name(type))
	assert_eq(toolbar._tool_buttons["rock"].tool_name, "Boulders", "The boulder tool isn't a second 'Rocks'")

func test_toolbar_hotkeys_select_the_new_tiles() -> void:
	GameManager.current_mode = GameManager.GameMode.BUILDING
	var toolbar := TerrainToolbar.new()
	add_child_autofree(toolbar)
	var cases := [[KEY_9, false, T.FIRM_FAIRWAY], [KEY_0, false, T.WASTE_BUNKER],
		[KEY_2, true, T.DEEP_ROUGH], [KEY_5, true, T.POT_BUNKER], [KEY_6, true, T.STREAM],
		[KEY_7, true, T.ROCKS], [KEY_8, true, T.BRUSH], [KEY_5, false, T.BUNKER]]
	for case in cases:
		var event := InputEventKey.new()
		event.keycode = case[0]
		event.shift_pressed = case[1]
		event.pressed = true
		toolbar._input(event)
		assert_eq(toolbar._current_tool, case[2],
			"%s%s selects %s" % ["Shift+" if case[1] else "", OS.get_keycode_string(case[0]), TerrainTypes.get_type_name(case[2])])

func test_tile_previews_show_a_flowing_stream_and_patches_of_scatter() -> void:
	var toolbar := TerrainToolbar.new()
	add_child_autofree(toolbar)
	var stream: Image = toolbar._tool_buttons[T.STREAM]._surface_material.get_shader_parameter("terrain_data").get_image()
	assert_eq(roundi(stream.get_pixel(0, 1).r * 255.0), T.STREAM, "The channel enters from one side")
	assert_eq(roundi(stream.get_pixel(2, 1).r * 255.0), T.STREAM, "and leaves from the other")
	assert_eq(roundi(stream.get_pixel(1, 0).r * 255.0), T.GRASS, "with grass banks")
	for type in [T.ROCKS, T.BRUSH]:
		var image: Image = toolbar._tool_buttons[type]._surface_material.get_shader_parameter("terrain_data").get_image()
		assert_eq(roundi(image.get_pixel(0, 0).r * 255.0), type, "A patch, not a lone tile")
		assert_eq(image.get_pixel(1, 1).a, 1.0, "Painted Rocks, not a boulder footprint")
	for type in [T.FIRM_FAIRWAY, T.POT_BUNKER, T.DEEP_ROUGH, T.WASTE_BUNKER]:
		var image: Image = toolbar._tool_buttons[type]._surface_material.get_shader_parameter("terrain_data").get_image()
		assert_eq(roundi(image.get_pixel(1, 1).r * 255.0), type)
		assert_eq(roundi(image.get_pixel(0, 1).r * 255.0), T.GRASS)
