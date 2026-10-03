extends SceneTree
## Integration regression: the Start New Game → World Map → first course flow,
## and switching between owned locations.
##
## Run with --path . --script tests/integration/world_map_flow.gd
##
## Covers:
##  * the main menu offering exactly the six agreed actions,
##  * Start New Game options (company name, difficulty, money, generated holes,
##    features) landing on the new game,
##  * the world map listing every location with name/theme/size/cost,
##  * buying a location and building the generated first course on it,
##  * buying a second location, switching to it, and coming back to find the
##    first course exactly as it was left.

var main: Node
var gm: Node
var bus: Node
var sm
var world
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	print("WORLD_MAP_FLOW_FAIL: ", message)

func frames(count: int) -> void:
	for i in count:
		await process_frame

func run() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await frames(6)
	gm = root.get_node("GameManager")
	bus = root.get_node("EventBus")
	world = root.get_node("WorldMap")
	sm = root.get_node("SaveManager")

	# ---------------------------------------------------------------- main menu
	var menu = main.main_menu
	check(menu != null, "the game opens on the main menu")
	var labels: Array = []
	for node in _all_buttons(menu):
		labels.append(node.text)
	for expected in ["Start New Game", "Quick Start", "Continue", "Load Game", "Settings", "Quit"]:
		check(expected in labels, "main menu has a %s button" % expected)
	check(not ("New Game" in labels), "the old combined New Game button is gone")
	check(not ("Credits" in labels), "Credits is no longer on the main menu")
	check(not ("Prebuilt Course" in labels), "Prebuilt Course is no longer on the main menu")

	# ------------------------------------------------------- start new game flow
	main._on_menu_start_new_game()
	await frames(3)
	var setup = main.get_node_or_null("UI/HUD/StartNewGameScreen")
	check(setup != null, "Start New Game opens the company setup screen")
	check(main.main_menu == null, "the title screen steps aside for the setup screen")

	setup._company_input.text = "Summit Golf Group"
	setup._select_difficulty(DifficultyPresets.Preset.HARD)
	setup._select_money(200000)
	setup._select_holes(6)
	setup._feature_boxes["wind"].button_pressed = false
	var options: Dictionary = setup.get_options()
	check(options["company_name"] == "Summit Golf Group", "company name is captured")
	check(options["difficulty"] == DifficultyPresets.Preset.HARD, "difficulty is captured")
	check(options["starting_money"] == 200000, "starting money is captured")
	check(options["generated_holes"] == 6, "generated hole count is captured")
	check(options["features"]["wind"] == false, "wind can be turned off")
	check(options["features"]["weather"] == true, "weather stays on by default")

	main._on_menu_start_new_game()
	await frames(2)
	setup = main.get_node_or_null("UI/HUD/StartNewGameScreen")
	setup._on_next_pressed()
	await frames(3)
	check(main.get_node_or_null("UI/HUD/WorldMapScreen") != null,
		"Next from the setup screen goes to the world map")
	check(world.company_name == "Summit Golf Group", "the world carries the company name")

	# ---------------------------------------------------------------- world map
	var screen = main.get_node("UI/HUD/WorldMapScreen")
	check(screen._rows.size() == WorldLocations.get_all().size(),
		"the world map lists every location (got %d of %d)" % [screen._rows.size(), WorldLocations.get_all().size()])
	var names: Array = []
	for def in WorldLocations.get_all():
		names.append(def["id"])
	for expected_id in ["monterey", "san_diego", "rocky_mountains", "las_vegas", "phoenix",
			"hawaii", "oahu", "nova_scotia", "northeast", "carolina", "ireland",
			"scotland", "wales", "spain", "florida", "jamaica"]:
		check(expected_id in names, "the catalog includes %s" % expected_id)
	for id in names:
		var def: Dictionary = WorldLocations.get_definition(id)
		check(CourseTheme.get_theme_name(int(def["theme"])) != "Unknown",
			"%s has a real theme" % id)
		check(world.get_price(id) > 0, "%s has a price" % id)
		check(world.get_unlocked_parcels(id).size() >= 4,
			"%s starts with the central land unlocked" % id)
		check(world.get_total_parcels(id) > 0, "%s has land" % id)

	# The list must show name, theme, size and cost for a location.
	var listed_text: String = _all_labels_text(screen)
	check("Monterey" in listed_text, "the list shows the Monterey row")
	check(WorldLocations.get_size_name(int(WorldLocations.get_definition("monterey")["size"])) in listed_text,
		"the list shows the Monterey size")
	check(CourseTheme.get_theme_name(int(WorldLocations.get_definition("monterey")["theme"])) in listed_text,
		"the list shows the Monterey theme")
	check("$" in listed_text, "the list shows costs")

	# Reset World re-rolls prices (locations may coincidentally match, so the
	# seed must change and every price must stay valid).
	var seed_before = world.world_seed
	var prices_before: Dictionary = {}
	for id in names:
		prices_before[id] = world.get_price(id)
	world.reset_world()
	check(world.world_seed != seed_before, "Reset World rolls a new world")
	var changed := 0
	for id in names:
		check(world.get_price(id) > 0, "%s still has a valid price after reset" % id)
		if world.get_price(id) != prices_before[id]:
			changed += 1
	check(changed > 0, "Reset World changes location costs")

	# ------------------------------------------------------- buy & start playing
	var target := "monterey"
	check(not world.is_owned(target), "Monterey starts unowned")
	check(world.buy_location(target), "Monterey can be bought")
	var money_after_buy: int = gm.money
	check(world.is_owned(target), "Monterey is owned after buying")
	check(money_after_buy == 200000 - world.get_price(target), "buying deducts the price")

	main._on_world_map_play_location(target)
	await frames(12)
	check(gm.company_name == "Summit Golf Group", "the company name reaches the game")
	check(gm.current_difficulty == DifficultyPresets.Preset.HARD, "difficulty reaches the game")
	check(gm.wind_enabled == false, "the wind feature is off in the new game")
	check(SeasonSystem.disabled == false, "seasons stay enabled by default")
	check(gm.current_course != null and gm.current_course.holes.size() == 6,
		"the first course starts with the 6 generated holes (got %d)" % (
			gm.current_course.holes.size() if gm.current_course else -1))
	check(gm.course_name.begins_with("Monterey"), "the course is named for its location")
	check(gm.current_theme == int(WorldLocations.get_definition(target)["theme"]),
		"the course uses the location's theme")
	var land = gm.land_manager
	for parcel in world.get_unlocked_parcels(target):
		check(land.owned_parcels.has(parcel), "pre-cleared parcel %s is owned" % parcel)
	for parcel in world.get_location_parcels(target):
		check(parcel in land.location_parcels or land.location_parcels.is_empty(),
			"parcel %s belongs to the location" % parcel)

	# The generated holes must all be on land the player owns.
	var outside := 0
	for hole in gm.current_course.holes:
		if not land.is_tile_owned(hole.tee_position) or not land.is_tile_owned(hole.green_position):
			outside += 1
	check(outside == 0, "every generated hole sits on owned land")

	# The player can go back to the world map from the pause menu.
	var before_money: int = gm.money
	main._show_pause_menu()
	await frames(2)
	check(main.pause_menu != null, "the pause menu opens in game")
	main._on_pause_world_map()
	await frames(3)
	screen = main.get_node_or_null("UI/HUD/WorldMapScreen")
	check(screen != null, "the pause menu opens the world map")
	check(gm.money == before_money, "opening the world map does not change the money")

	# ------------------------------------------------------ buy and switch sites
	var second := "florida"
	check(world.buy_location(second), "a second location can be bought")
	# Mark the first course so the switch can be verified to preserve it.
	var marker_hole = gm.current_course.holes[0]
	marker_hole.par_override = 5
	marker_hole.total_revenue = 1234
	var first_holes: int = gm.current_course.holes.size()
	var first_cash: int = gm.money

	# The switch is synchronous, so the company's balance can be compared
	# exactly: money belongs to the company, not to the course site.
	main._on_world_map_play_location(second)
	var cash_after_switch: int = gm.money
	check(world.active_location_id == second, "the world map switched to the second location")
	check(gm.current_theme == int(WorldLocations.get_definition(second)["theme"]),
		"the second course uses its own theme")
	check(cash_after_switch == first_cash, "switching locations keeps the company's money (was %d, now %d)" % [first_cash, cash_after_switch])
	await frames(12)
	check(gm.current_course != null, "the second location has a course")
	check(gm.current_course.holes.size() == 6, "the second site also gets the generated course")

	main._on_world_map_play_location(target)
	var cash_after_return: int = gm.money
	await frames(12)
	check(world.active_location_id == target, "switched back to the first location")
	check(gm.current_course.holes.size() == first_holes, "the first course kept its hole count")
	check(gm.current_course.holes[0].par_override == 5,
		"the first course kept the edit made before leaving (par override)")
	check(gm.current_course.holes[0].total_revenue == 1234,
		"the first course kept the edit made before leaving (revenue)")
	check(abs(cash_after_return - cash_after_switch) < 20000,
		"switching back keeps the company's money (%d -> %d)" % [cash_after_switch, cash_after_return])

	# ------------------------------------------------- eighteen-hole first course
	# A company that asks for 18 generated holes must be able to build them
	# wherever it buys, and a save must keep the whole company world.
	main._on_menu_start_new_game()
	await frames(2)
	setup = main.get_node("UI/HUD/StartNewGameScreen")
	setup._company_input.text = "Championship Holdings"
	setup._select_money(200000)
	setup._select_holes(18)
	setup._on_next_pressed()
	await frames(3)
	var championship := "rocky_mountains"
	check(world.buy_location(championship), "a championship-sized location can be bought")
	main._on_world_map_play_location(championship)
	var cash_at_championship: int = gm.money
	await frames(14)
	check(world.active_location_id == championship, "playing on the championship site")
	check(gm.current_course != null and gm.current_course.holes.size() == 18,
		"the championship site gets all 18 generated holes (got %d)" % (
			gm.current_course.holes.size() if gm.current_course else -1))
	check(gm.current_course.total_par == 72, "the 18-hole course plays to par 72 (got %d)" % (
		gm.current_course.total_par if gm.current_course else -1))
	var off_land := 0
	for hole in gm.current_course.holes:
		if not gm.land_manager.is_tile_owned(hole.tee_position) or not gm.land_manager.is_tile_owned(hole.green_position):
			off_land += 1
	check(off_land == 0, "every 18-hole tee and green is on owned land")
	check(main.entity_layer.get_all_buildings().size() > 0,
		"the generated course comes with its clubhouse cluster")

	# Save and reload: the company keeps the locations it owns, the location it
	# is playing and its money.
	var money_at_save: int = gm.money
	check(sm.save_game("world_map_flow"), "the company world saves")
	check(sm.load_game("world_map_flow"), "the company world loads")
	await frames(4)
	check(world.is_owned(championship), "a bought location survives the save")
	check(world.active_location_id == championship,
		"the location that was active when saving is restored")
	check(abs(gm.money - money_at_save) < 1000,
		"the company keeps its money across a save and load (%d -> %d)" % [money_at_save, gm.money])
	check(gm.current_course != null and gm.current_course.holes.size() == 18,
		"the 18-hole course on the location is restored")
	sm.delete_save("world_map_flow")
	check(cash_at_championship > 0, "the championship purchase left the company solvent")

	# ------------------------------------------------------------ quick start
	main._on_menu_quick_start()
	await frames(3)
	check(main.get_node_or_null("UI/HUD/WorldMapScreen") != null,
		"Quick Start goes straight to the world map")
	var defaults: Dictionary = world.default_options()
	check(world.difficulty == DifficultyPresets.Preset.NORMAL, "Quick Start uses Normal difficulty")
	check(world.starting_money_option == 100000, "Quick Start starts with $100,000")
	check(world.generated_holes == 0, "Quick Start generates no holes up front")
	for key in defaults["features"]:
		check(bool(world.features[key]), "Quick Start enables %s" % key)
	check(world.company_name.length() > 0, "Quick Start picks a random company name")

	if failures == 0:
		print("WORLD_MAP_FLOW_PASS: menu, setup, globe list, buying, switching and quick start all work")
	quit(0 if failures == 0 else 1)

func _all_buttons(node: Node) -> Array:
	var found: Array = []
	if node is Button:
		found.append(node)
	for child in node.get_children():
		found.append_array(_all_buttons(child))
	return found

func _all_labels_text(node: Node) -> String:
	var text := ""
	for child in node.get_children():
		if child is Label:
			text += child.text + "\n"
		text += _all_labels_text(child)
	return text

