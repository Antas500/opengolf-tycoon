extends SceneTree
## Generated courses (Quick Start and the prebuilt packages) must keep delivering
## every hole, and must not leave tee boxes or cups waiting — otherwise the
## player's next tee box would be blocked by a generated one.
##
## Uses dynamic loads because a `-s` script compiles before autoloads exist.

var main: Node
var grid
var gm
var layout
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	print("GENERATED_HOLE_LAYOUT_FAIL: ", message)

func run() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	layout = load("res://scripts/tools/hole_layout.gd")
	main._on_main_menu_quick_start("Generated Layout Check", 0)
	for i in range(8): await process_frame

	gm = root.get_node("GameManager")
	grid = main.terrain_grid

	check(gm.current_course.holes.size() == 9, "Quick Start builds nine holes, got %d" % gm.current_course.holes.size())
	check(grid.get_cup_tiles().is_empty(), "Quick Start leaves no waiting cup")
	check(layout.unused_tee_boxes(grid, gm.current_course).is_empty(),
			"Quick Start leaves no unused tee box, so the player can place one")
	check(layout.can_place_tee_box(grid, gm.current_course), "The player can add a tee box after Quick Start")
	check(layout.green_places_cup(grid, gm.current_course), "The player's next green carries a cup")

	for hole in gm.current_course.holes:
		check(grid.get_tile(hole.hole_position) == TerrainTypes.Type.GREEN,
				"Hole %d cup sits on its green" % hole.hole_number)

	# Prebuilt packages replace the course; each must deliver its full hole count.
	var generator = load("res://scripts/systems/prebuilt_course_generator.gd")
	var expected := {"starter": 3, "executive": 9, "standard9": 9, "championship18": 18}
	for package_id in expected:
		# A prebuilt package is only ever built on a fresh course: reset the grid so
		# tee boxes from the previous package do not leak into this one.
		grid.begin_batch()
		grid.deserialize({})
		grid.clear_cup_tiles()
		grid.end_batch_quiet()
		grid.begin_batch()
		generator.build(package_id, grid, main.entity_layer, main.hole_tool)
		grid.end_batch_quiet()
		grid.refresh_all_overlays()
		for i in range(4): await process_frame
		var holes: int = gm.current_course.holes.size()
		check(holes == expected[package_id],
				"%s builds %d holes, got %d" % [package_id, expected[package_id], holes])
		check(grid.get_cup_tiles().is_empty(), "%s leaves no waiting cup" % package_id)
		check(layout.unused_tee_boxes(grid, gm.current_course).is_empty(),
				"%s leaves no unused tee box" % package_id)

	if failures == 0:
		print("GENERATED_HOLE_LAYOUT_PASS: quick start and all four prebuilt packages deliver every hole with nothing left waiting")
	quit(1 if failures > 0 else 0)
