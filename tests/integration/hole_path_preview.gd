extends SceneTree
## Integration check for the potential hole path: while a tee box waits and the
## Green tool is about to cut the cup, hovering a tile previews the hole it would
## make — and the route drawn is the one the opened hole shows.
##
## The cursor is simulated through the camera's pointer, so the preview runs its
## real per-frame path: screen -> grid picking, HoleLayout.potential_hole() and
## the background route planner.
##
## Uses dynamic loads because a `-s` script compiles before autoloads exist.

var main: Node
var grid
var gm
var preview
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	print("HOLE_PATH_PREVIEW_FAIL: ", message)

## Put the simulated cursor over a tile's centre.
func hover(tile: Vector2i) -> void:
	var camera = main.camera
	camera._has_pointer = true
	camera._pointer_position = camera.get_canvas_transform() * grid.grid_to_screen_center(tile)

func paint(tile: Vector2i) -> void:
	main.undo_manager.begin_stroke()
	main._paint_terrain_stamp(tile)
	main.undo_manager.end_stroke()

## Wait for the background planner to deliver the hovered route.
func await_route(max_frames: int = 600) -> void:
	for i in range(max_frames):
		if not preview.potential_hole_route.is_empty():
			return
		await process_frame

func run() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._on_main_menu_new_game("Hole Path Preview Check", 0)
	for i in range(8): await process_frame

	gm = root.get_node("GameManager")
	grid = main.terrain_grid
	preview = main.placement_preview
	gm.wind_system = null  # Routes ignore wind anyway; keep the check deterministic.

	# Clear a quiet stretch of owned land so trees don't bend the route.
	var tee := Vector2i(52, 60)
	for x in range(48, 82):
		for y in range(54, 68):
			var pos := Vector2i(x, y)
			if main.entity_layer.get_tree_at(pos): main.entity_layer.remove_tree(pos)
			if main.entity_layer.get_rock_at(pos): main.entity_layer.remove_rock(pos)
			grid.set_tile(pos, TerrainTypes.Type.GRASS)

	# --- Green tool with no tee box waiting: no path ---
	main._on_tool_selected(TerrainTypes.Type.GREEN)
	hover(Vector2i(64, 60))
	for i in range(3): await process_frame
	check(preview.potential_hole.is_empty(), "No path while no tee box waits")

	# --- Paint the tee; other tools never show the path ---
	main._on_tool_selected(TerrainTypes.Type.TEE_BOX)
	paint(tee)
	check(grid.get_tile(tee) == TerrainTypes.Type.TEE_BOX, "Tee box painted")
	hover(Vector2i(64, 60))
	for i in range(3): await process_frame
	check(preview.potential_hole.is_empty(), "The Tee Box tool shows no hole path")
	main._on_tool_selected(TerrainTypes.Type.FAIRWAY)
	for i in range(3): await process_frame
	check(preview.potential_hole.is_empty(), "The Fairway tool shows no hole path")

	# --- Green tool + waiting tee: a par 3 path follows the cursor ---
	main._on_tool_selected(TerrainTypes.Type.GREEN)
	var par3_cup := Vector2i(62, 60)
	hover(par3_cup)
	for i in range(3): await process_frame
	var hole: Dictionary = preview.potential_hole
	check(not hole.is_empty(), "Hovering with the Green tool shows the potential hole")
	if not hole.is_empty():
		check(hole.tee == tee, "The path starts at the waiting tee")
		check(hole.cup == par3_cup, "The path ends at the hovered tile")
		check(hole.par == 3 and hole.distance_yards == 220, "Par 3, 220 yds (got par %d, %d yds)" % [hole.par, hole.distance_yards])
		check(hole.hole_number == 1, "It would be hole 1")
		check(hole.ready, "A 220-yard pair on open, owned grass is ready: %s" % hole.reason)
	check(preview.potential_hole_route == [tee, par3_cup], "A par 3 route is drawn tee to cup at once")

	# --- Too short: still drawn, flagged ---
	hover(tee + Vector2i(2, 0))
	for i in range(3): await process_frame
	check(not preview.potential_hole.is_empty(), "The path follows the cursor even when too short")
	check(not preview.potential_hole.get("ready", true), "A 44-yard pair is flagged as too short")

	# --- Par 4: the route is planned in the background, then drawn ---
	var par4_cup := Vector2i(70, 62)
	hover(par4_cup)
	await process_frame
	check(preview.potential_hole.get("par", 0) == 4, "18-tile pair is a par 4 (got %s)" % preview.potential_hole.get("par"))
	await await_route()
	var route: Array = preview.potential_hole_route
	check(route.size() == 3, "Par 4 preview route has a landing zone (got %s)" % str(route))
	check(not route.is_empty() and route[0] == tee and route[route.size() - 1] == par4_cup,
			"Par 4 route runs tee -> cup")
	var previewed: Array = route.duplicate()

	# --- Other modes hide the path ---
	main._on_bulldozer_pressed()
	for i in range(3): await process_frame
	check(preview.potential_hole.is_empty(), "Bulldozer mode hides the path")
	main._on_tool_selected(TerrainTypes.Type.GREEN)
	hover(par4_cup)
	for i in range(3): await process_frame
	check(not preview.potential_hole.is_empty(), "Back on the Green tool, the path returns")
	check(preview.potential_hole_route == previewed, "The planned route was cached")
	main._cancel_action()  # ESC deselects the tool
	for i in range(3): await process_frame
	check(preview.potential_hole.is_empty(), "Deselecting the tool hides the path")

	# --- Cut the cup: the Green tool now paints a Green Without Hole ---
	main._on_tool_selected(TerrainTypes.Type.GREEN)
	hover(par4_cup)
	for i in range(3): await process_frame
	paint(par4_cup)
	check(grid.get_cup_tiles() == [par4_cup], "The cup was cut where the path ended")
	hover(par4_cup + Vector2i(0, 3))
	for i in range(3): await process_frame
	check(preview.potential_hole.is_empty(), "With a cup waiting the path is hidden")

	# --- Open the hole: its route is the one that was previewed ---
	main._on_open_hole_pressed()
	check(gm.current_course.holes.size() == 1, "Open Hole created the hole")
	if gm.current_course.holes.size() == 1:
		var opened = gm.current_course.holes[0]
		check(opened.par == 4, "The opened hole is the previewed par 4")
		var calc = load("res://scripts/course/shot_path_calculator.gd")
		var opened_route: Array = calc.calculate_waypoints(opened, grid)
		check(opened_route == previewed,
				"Opened hole route %s matches the preview %s" % [str(opened_route), str(previewed)])
	hover(Vector2i(64, 64))
	for i in range(3): await process_frame
	check(preview.potential_hole.is_empty(), "Every tee is claimed again: no path")

	# --- Hole 2, multi-tee on: a par 5 whose forward/middle tees Open Hole paints ---
	gm.multi_tee_enabled = true
	var tee2 := Vector2i(52, 66)
	main._on_tool_selected(TerrainTypes.Type.TEE_BOX)
	paint(tee2)
	main._on_tool_selected(TerrainTypes.Type.GREEN)
	var par5_cup := Vector2i(78, 64)
	hover(par5_cup)
	await process_frame
	var hole2: Dictionary = preview.potential_hole
	check(hole2.get("hole_number", 0) == 2, "The next hole is hole 2")
	check(hole2.get("par", 0) == 5, "26-tile pair is a par 5 (got %s)" % hole2.get("par"))
	check(hole2.get("extra_tees", {}).size() == 2, "Multi-tee previews forward and middle tees")
	await await_route()
	var previewed_par5: Array = preview.potential_hole_route.duplicate()
	# Two landings usually; one when a lay-up already reaches a green (hole 1's is close).
	check(previewed_par5.size() >= 3 and previewed_par5[0] == tee2 and previewed_par5[-1] == par5_cup,
			"Par 5 preview route runs tee -> landing(s) -> cup (got %s)" % str(previewed_par5))
	paint(par5_cup)
	main._on_open_hole_pressed()
	check(gm.current_course.holes.size() == 2, "Open Hole created hole 2")
	if gm.current_course.holes.size() == 2:
		var opened2 = gm.current_course.holes[1]
		check(opened2.tee_positions.forward == hole2.extra_tees.forward, "Forward tee as previewed")
		check(opened2.tee_positions.middle == hole2.extra_tees.middle, "Middle tee as previewed")
		var calc2 = load("res://scripts/course/shot_path_calculator.gd")
		var opened2_route: Array = calc2.calculate_waypoints(opened2, grid)
		check(opened2_route == previewed_par5,
				"Opened par 5 route %s matches the preview %s" % [str(opened2_route), str(previewed_par5)])
	gm.multi_tee_enabled = false

	if failures == 0:
		print("HOLE_PATH_PREVIEW_PASS: hidden without a tee / on other tools / with a cup waiting, par 3 immediate, too-short flagged, par 4 planned in the background and cached, preview route == opened hole route (par 4, and par 5 with multi-tee)")
	quit(1 if failures > 0 else 0)
