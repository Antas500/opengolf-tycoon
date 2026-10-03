extends GutTest
## The company world map: the location catalog, prices that follow the amount
## of land that comes pre-cleared, buying and switching locations, the
## unlimited-money option and the enabled game features.

var _saved_world: Dictionary
var _saved_money: int
var _saved_unlimited: bool
var _saved_difficulty: int
var _saved_features: Dictionary
var _saved_land: LandManager
var _saved_grid: TerrainGrid
var _saved_course: GameManager.CourseData

func before_each() -> void:
	_saved_world = WorldMap.serialize()
	_saved_money = GameManager.money
	_saved_unlimited = GameManager.unlimited_money
	_saved_difficulty = GameManager.current_difficulty
	_saved_features = {
		"weather": GameManager.weather_enabled,
		"wind": GameManager.wind_enabled,
		"seasons": GameManager.seasons_enabled,
	}
	_saved_land = GameManager.land_manager
	_saved_grid = GameManager.terrain_grid
	_saved_course = GameManager.current_course

func after_each() -> void:
	WorldMap.deserialize(_saved_world)
	GameManager.money = _saved_money
	GameManager.set_unlimited_money(_saved_unlimited)
	GameManager.current_difficulty = _saved_difficulty
	GameManager.set_weather_enabled(_saved_features["weather"])
	GameManager.set_wind_enabled(_saved_features["wind"])
	GameManager.set_seasons_enabled(_saved_features["seasons"])
	GameManager.land_manager = _saved_land
	GameManager.terrain_grid = _saved_grid if is_instance_valid(_saved_grid) else null
	GameManager.current_course = _saved_course

## ── Catalog ──────────────────────────────────────────────────────────────

func test_catalog_has_every_named_location() -> void:
	var ids: Array = []
	for def in WorldLocations.get_all():
		ids.append(def["id"])
	for expected in ["monterey", "san_diego", "rocky_mountains", "las_vegas", "phoenix",
			"hawaii", "oahu", "nova_scotia", "northeast", "carolina", "ireland",
			"scotland", "wales", "spain", "florida", "jamaica"]:
		assert_true(expected in ids, "catalog includes %s" % expected)
	assert_gt(ids.size(), 16, "the catalog has locations beyond the named ones")

func test_catalog_entries_are_well_formed() -> void:
	var seen: Dictionary = {}
	for def in WorldLocations.get_all():
		var id: String = def["id"]
		assert_false(seen.has(id), "location id %s is unique" % id)
		seen[id] = true
		assert_true(WorldLocations.SIZE_DATA.has(int(def["size"])), "%s has a known size" % id)
		assert_ne(CourseTheme.get_theme_name(int(def["theme"])), "Unknown", "%s has a real theme" % id)
		assert_between(float(def["lat"]), -90.0, 90.0, "%s latitude is on the globe" % id)
		assert_between(float(def["lon"]), -180.0, 180.0, "%s longitude is on the globe" % id)
		assert_gt(WorldLocations.get_price_for_land(id, 4), 0, "%s costs something" % id)

func test_unlocked_land_always_covers_a_full_generated_course() -> void:
	# Whatever a location's size, its land block must include the 3x3 parcel
	# block the 18-hole layout is built on — otherwise a player could ask for
	# 18 generated holes on a site that can never hold them.
	for def in WorldLocations.get_all():
		var id: String = def["id"]
		var order: Array = WorldLocations.layout_order(
			int(def["size"]), _rng(), WorldLocations.get_required_parcels(18))
		for parcel in WorldLocations.get_required_parcels(18):
			assert_true(order.has(parcel), "%s can hold an 18-hole layout (%s missing)" % [id, parcel])
		assert_between(order.size(), WorldLocations.get_parcel_count(int(def["size"])), 36,
			"%s keeps its size while covering the layout" % id)

func test_larger_locations_cost_more() -> void:
	# Same theme and prestige, different sizes: the bigger site costs more.
	var medium := WorldLocations.compute_price("phoenix", 6)     # Medium, desert
	var large := WorldLocations.compute_price("las_vegas", 6)    # Large, desert
	assert_gt(large, medium, "a bigger site costs more than a medium one")
	assert_gt(WorldLocations.get_parcel_count(WorldLocations.Size.LARGE),
		WorldLocations.get_parcel_count(WorldLocations.Size.SMALL),
		"a large site has more land than a small one")

func test_more_ready_land_means_a_higher_price() -> void:
	var few := WorldLocations.compute_price("scotland", 4)
	var many := WorldLocations.compute_price("scotland", 12)
	assert_gt(many, few, "more pre-cleared land costs more")

func test_growth_order_keeps_the_centre_cluster() -> void:
	var order: Array = WorldLocations.growth_order(WorldLocations.Size.CHAMPIONSHIP, _rng())
	assert_eq(order.size(), WorldLocations.get_parcel_count(WorldLocations.Size.CHAMPIONSHIP))
	for parcel in [Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 2), Vector2i(3, 3)]:
		assert_true(order.has(parcel), "centre parcel %s is part of the land" % parcel)

## ── World rolls ──────────────────────────────────────────────────────────

func test_new_world_rolls_every_location_and_prices_it() -> void:
	WorldMap.new_world(WorldMap.default_options(), 12345)
	assert_eq(WorldMap.locations.size(), WorldLocations.get_all().size())
	for def in WorldLocations.get_all():
		var id: String = def["id"]
		assert_false(WorldMap.is_owned(id), "%s starts unowned" % id)
		assert_gt(WorldMap.get_price(id), 0, "%s has a price" % id)
		var unlocked: Array = WorldMap.get_unlocked_parcels(id)
		assert_between(unlocked.size(), 4, WorldMap.get_total_parcels(id),
			"%s starts with a sensible amount of ready land" % id)

func test_new_world_applies_company_settings() -> void:
	WorldMap.new_world({
		"company_name": "Fairway Holdings",
		"difficulty": DifficultyPresets.Preset.HARD,
		"starting_money": 200000,
		"generated_holes": 9,
		"features": {"weather": true, "wind": false, "seasons": false},
	})
	assert_eq(WorldMap.company_name, "Fairway Holdings")
	assert_eq(GameManager.company_name, "Fairway Holdings", "the company name reaches the game")
	assert_eq(GameManager.current_difficulty, DifficultyPresets.Preset.HARD)
	assert_eq(GameManager.money, 200000, "the chosen budget is the opening balance")
	assert_false(GameManager.wind_enabled, "wind can be turned off")
	assert_true(GameManager.weather_enabled, "weather stays on")
	assert_false(GameManager.seasons_enabled, "seasons can be turned off")
	assert_eq(WorldMap.generated_holes, 9)

func test_quick_start_defaults_match_the_agreed_options() -> void:
	var options := WorldMap.default_options()
	assert_eq(options["difficulty"], DifficultyPresets.Preset.NORMAL)
	assert_eq(options["starting_money"], 100000)
	assert_eq(options["generated_holes"], 0)
	for key in WorldMap.FEATURE_KEYS:
		assert_true(bool(options["features"][key]), "%s is enabled by default" % key)
	assert_ne(options["company_name"], "", "Quick Start picks a random company name")

func test_reset_world_never_takes_owned_land_away() -> void:
	WorldMap.new_world(WorldMap.default_options(), 999)
	GameManager.money = 10000000
	assert_true(WorldMap.buy_location("monterey"), "the location can be bought")
	var owned_land: Array = WorldMap.get_unlocked_parcels("monterey").duplicate()
	WorldMap.reset_world()
	assert_true(WorldMap.is_owned("monterey"), "an owned location stays owned after a reset")
	assert_eq(WorldMap.get_unlocked_parcels("monterey"), owned_land,
		"an owned location keeps its land after a reset")
	assert_gt(WorldMap.get_price("florida"), 0, "unowned locations are re-priced")

func test_buying_deducts_the_price_and_marks_the_location_owned() -> void:
	WorldMap.new_world(WorldMap.default_options(), 4242)
	GameManager.money = 500000
	var price := WorldMap.get_price("ireland")
	assert_true(WorldMap.buy_location("ireland"), "Ireland can be bought")
	assert_true(WorldMap.is_owned("ireland"))
	assert_eq(GameManager.money, 500000 - price, "the price is deducted")
	assert_true(WorldMap.buy_location("ireland"), "buying twice is a no-op")
	assert_eq(GameManager.money, 500000 - price, "buying twice does not charge twice")

func test_cannot_buy_what_the_company_cannot_afford() -> void:
	WorldMap.new_world(WorldMap.default_options(), 777)
	GameManager.money = 100
	GameManager.bankruptcy_threshold = -1000
	var price := WorldMap.get_price("scotland")
	assert_gt(price, 100)
	assert_false(WorldMap.can_afford("scotland"))
	assert_false(WorldMap.buy_location("scotland"), "an unaffordable location cannot be bought")
	assert_false(WorldMap.is_owned("scotland"))

func test_unlimited_money_never_runs_out() -> void:
	WorldMap.new_world({
		"company_name": "Endless Links",
		"starting_money": WorldMap.UNLIMITED_MONEY,
		"features": {},
	}, 5150)
	assert_true(GameManager.unlimited_money)
	assert_true(GameManager.can_afford(99999999), "anything is affordable")
	GameManager.modify_money(-500000)
	assert_eq(GameManager.money, GameManager.UNLIMITED_STARTING_BALANCE,
		"spending does not reduce an unlimited balance")
	assert_false(GameManager.is_bankrupt())
	assert_true(WorldMap.buy_location("rocky_mountains"), "locations can still be bought")

func test_world_state_survives_a_save_round_trip() -> void:
	WorldMap.new_world(WorldMap.default_options(), 31337)
	GameManager.money = 500000
	WorldMap.buy_location("wales")
	WorldMap.set_active_location("wales")
	WorldMap.take_snapshot("wales", {"marker": true})
	var data := WorldMap.serialize()

	WorldMap.new_world(WorldMap.default_options(), 1)
	assert_false(WorldMap.is_owned("wales"), "the fresh world forgets the purchase")
	WorldMap.deserialize(data)

	assert_true(WorldMap.is_owned("wales"), "the purchase is restored")
	assert_eq(WorldMap.active_location_id, "wales", "the active location is restored")
	assert_true(WorldMap.get_snapshot("wales").get("marker", false), "the snapshot is restored")
	assert_eq(WorldMap.get_price("wales"), int(data["locations"]["wales"]["price"]),
		"prices are restored exactly")

## ── Land ─────────────────────────────────────────────────────────────────

func test_location_land_limits_what_can_be_bought() -> void:
	WorldMap.new_world(WorldMap.default_options(), 2024)
	var land := LandManager.new()
	add_child_autofree(land)
	GameManager.land_manager = land
	WorldMap.apply_location_land("nova_scotia")

	var block: Array = WorldMap.get_location_parcels("nova_scotia")
	assert_gt(block.size(), 0)
	for parcel in WorldMap.get_unlocked_parcels("nova_scotia"):
		assert_true(land.owned_parcels.has(parcel), "unlocked parcel %s is owned" % parcel)
	for parcel in block:
		assert_true(land.is_parcel_in_location(parcel), "parcel %s belongs to the location" % parcel)
	# A parcel outside the location's block is never purchasable.
	var outside := Vector2i(5, 5)
	if not block.has(outside):
		assert_false(land.is_parcel_purchasable(outside), "land outside the site is not for sale")

## ── Features ─────────────────────────────────────────────────────────────

func test_disabling_weather_keeps_the_course_sunny() -> void:
	var weather := WeatherSystem.new()
	add_child_autofree(weather)
	await wait_frames(1)
	GameManager.set_weather_enabled(false)
	weather.update_weather_daily()
	assert_eq(weather.weather_type, WeatherSystem.WeatherType.SUNNY)
	assert_eq(weather.intensity, 0.0)
	assert_almost_eq(weather.get_spawn_rate_modifier(), 1.0, 0.001)
	assert_false(weather.is_raining())

func test_disabling_wind_makes_every_shot_calm() -> void:
	var wind := WindSystem.new()
	add_child_autofree(wind)
	await wait_frames(1)
	GameManager.set_wind_enabled(false)
	wind.update_wind_daily()
	assert_eq(wind.wind_speed, 0.0)
	assert_eq(wind.get_wind_displacement(Vector2.RIGHT, 30.0, 1), Vector2.ZERO)
	assert_almost_eq(wind.get_distance_modifier(Vector2.RIGHT, 1), 1.0, 0.001)

func test_disabling_seasons_flattens_the_calendar() -> void:
	GameManager.set_seasons_enabled(false)
	assert_true(SeasonSystem.disabled)
	assert_almost_eq(SeasonSystem.get_blended_spawn_modifier(200, CourseTheme.Type.PARKLAND), 1.0, 0.001)
	assert_almost_eq(SeasonSystem.get_blended_maintenance_modifier(200), 1.0, 0.001)
	assert_almost_eq(SeasonSystem.get_fee_tolerance(200), 1.0, 0.001)
	GameManager.set_seasons_enabled(true)
	assert_false(SeasonSystem.disabled)

## ── Generated first course ───────────────────────────────────────────────

func test_generated_course_layouts_deliver_every_hole() -> void:
	var grid := TerrainGrid.new()
	grid.grid_width = 128
	grid.grid_height = 128
	add_child_autofree(grid)
	GameManager.terrain_grid = grid
	GameManager.current_course = GameManager.CourseData.new()
	var tool := HoleCreationTool.new()
	add_child_autofree(tool)
	var land := LandManager.new()
	add_child_autofree(land)
	GameManager.land_manager = land

	for count in [3, 6, 9, 18]:
		GameManager.current_course = GameManager.CourseData.new()
		tool.current_hole_number = 1
		land.grant_parcels(WorldLocations.get_required_parcels(count))
		var built := GeneratedCourse.generate(count, grid, null, tool)
		assert_eq(built, count, "%d generated holes were opened" % count)
		assert_eq(GameManager.current_course.holes.size(), count)
		assert_eq(GameManager.current_course.total_par, GeneratedCourse.get_par_for_count(count),
			"the %d-hole layout has the advertised par" % count)

func test_generated_course_refuses_to_leave_the_owned_land() -> void:
	var grid := TerrainGrid.new()
	grid.grid_width = 128
	grid.grid_height = 128
	add_child_autofree(grid)
	GameManager.terrain_grid = grid
	GameManager.current_course = GameManager.CourseData.new()
	var tool := HoleCreationTool.new()
	add_child_autofree(tool)
	var land := LandManager.new()
	add_child_autofree(land)
	GameManager.land_manager = land
	land.grant_parcels([Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 2), Vector2i(3, 3)])

	assert_false(GeneratedCourse.can_generate(18), "18 holes do not fit the central 2x2")
	assert_eq(GeneratedCourse.generate(18, grid, null, tool), 0, "nothing is built without land")
	assert_true(GeneratedCourse.can_generate(9), "9 holes do fit the central 2x2")
	assert_eq(GeneratedCourse.generate(9, grid, null, tool), 9)

func test_generated_course_anchors() -> void:
	assert_eq(GeneratedCourse.get_anchor(9), GeneratedCourse.SMALL_ANCHOR)
	assert_eq(GeneratedCourse.get_anchor(18), GeneratedCourse.CHAMPIONSHIP_ANCHOR)
	assert_eq(GeneratedCourse.get_par_for_count(0), 0)
	assert_eq(GeneratedCourse.get_par_for_count(18), 72)

## Deterministic RNG for the layout helpers under test.
func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20241003
	return rng
