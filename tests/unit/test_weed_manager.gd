extends GutTest
## Tests for WeedManager: growth on owned turf, removal and serialization.

var grid: TerrainGrid
var weed_manager: WeedManager
var _saved_entity_layer
var _saved_land_manager

func before_each() -> void:
	grid = TerrainGrid.new()
	grid.grid_width = 16
	grid.grid_height = 16
	add_child_autofree(grid)
	for x in range(16):
		for y in range(16):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.GRASS)
	weed_manager = WeedManager.new()
	add_child_autofree(weed_manager)
	weed_manager.setup(grid, null)
	_saved_entity_layer = GameManager.entity_layer
	_saved_land_manager = GameManager.land_manager
	GameManager.entity_layer = null
	GameManager.land_manager = null

func after_each() -> void:
	GameManager.entity_layer = _saved_entity_layer
	GameManager.land_manager = _saved_land_manager

## Daily sprout rates are scaled by DAILY_RATE_SCALE (~1/480), so one game day
## rarely produces a whole clump. Advance enough days to cover one legacy day.
func _grow_legacy_day(open_holes: int) -> int:
	var sprouted := 0
	var days := int(ceil(1.0 / GameManager.DAILY_RATE_SCALE))
	for _i in days:
		sprouted += weed_manager.grow_daily(open_holes)
	return sprouted

func test_grow_daily_sprouts_weeds_on_turf() -> void:
	seed(1)
	var sprouted := _grow_legacy_day(6)
	assert_gt(sprouted, 0, "A legacy day's growth should sprout at least one clump")
	assert_eq(weed_manager.get_weed_count(), sprouted)
	for pos in weed_manager.get_weed_positions():
		assert_true(WeedManager.HOST_TURF.has(grid.get_tile(pos)),
			"Weeds only sprout on hostable turf")

func test_grow_daily_grows_existing_weeds() -> void:
	weed_manager.spawn_weed(Vector2i(2, 2), 0.2)
	var before := weed_manager.get_growth(Vector2i(2, 2))
	weed_manager.grow_daily(2)
	assert_gt(weed_manager.get_growth(Vector2i(2, 2)), before)

func test_weeds_never_sprout_on_greens_or_tees() -> void:
	seed(1)
	for x in range(16):
		grid.set_tile(Vector2i(x, 0), TerrainTypes.Type.GREEN)
		grid.set_tile(Vector2i(x, 1), TerrainTypes.Type.TEE_BOX)
		grid.set_tile(Vector2i(x, 2), TerrainTypes.Type.WATER)
	var sprouted := _grow_legacy_day(40)
	assert_gt(sprouted, 0, "Should still sprout on remaining grass")
	for pos in weed_manager.get_weed_positions():
		var tile := int(grid.get_tile(pos))
		assert_false(tile == TerrainTypes.Type.GREEN or tile == TerrainTypes.Type.TEE_BOX
			or tile == TerrainTypes.Type.WATER, "Weed sprouted on %s" % score_label(tile, pos))

func score_label(tile: int, pos: Vector2i) -> String:
	return "%s at %s" % [TerrainTypes.get_type_name(tile), str(pos)]

func test_remove_weed_clears_it() -> void:
	weed_manager.spawn_weed(Vector2i(5, 5), 0.5)
	assert_true(weed_manager.has_weed(Vector2i(5, 5)))
	assert_true(weed_manager.remove_weed(Vector2i(5, 5)))
	assert_false(weed_manager.has_weed(Vector2i(5, 5)))
	assert_false(weed_manager.remove_weed(Vector2i(5, 5)), "Removing twice is a no-op")

func test_find_closest_weed_within_radius() -> void:
	weed_manager.spawn_weed(Vector2i(2, 2), 0.5)
	weed_manager.spawn_weed(Vector2i(9, 9), 0.5)
	var near: Vector2i = weed_manager.find_closest_weed(Vector2(3, 3), 3.0)
	assert_eq(near, Vector2i(2, 2))
	assert_eq(weed_manager.find_closest_weed(Vector2(14, 14), 2.0), Vector2i(-1, -1),
		"Nothing in range returns the sentinel")

func test_pressure_scales_with_open_holes() -> void:
	assert_eq(weed_manager.get_pressure(9), 0.0)
	for i in 8:
		weed_manager.spawn_weed(Vector2i(i, 0), 0.5)
	# 8 weeds / (9 holes * 4 per hole) = 0.222
	assert_almost_eq(weed_manager.get_pressure(9), 8.0 / 36.0, 0.001)
	assert_gt(weed_manager.get_pressure(1), weed_manager.get_pressure(18))

func test_serialize_round_trip() -> void:
	weed_manager.spawn_weed(Vector2i(4, 6), 0.35)
	var data := weed_manager.serialize()

	var restored := WeedManager.new()
	add_child_autofree(restored)
	restored.setup(grid, null)
	restored.deserialize(data)
	assert_eq(restored.get_weed_count(), 1)
	assert_true(restored.has_weed(Vector2i(4, 6)))
	assert_almost_eq(restored.get_growth(Vector2i(4, 6)), 0.35, 0.001)

func test_clear_all_removes_every_weed() -> void:
	weed_manager.spawn_weed(Vector2i(1, 1), 0.5)
	weed_manager.spawn_weed(Vector2i(2, 2), 0.5)
	weed_manager.clear_all()
	assert_eq(weed_manager.get_weed_count(), 0)
