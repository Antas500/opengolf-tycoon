extends SceneTree
## Integration regression for the new hole workflow:
## single-tile tee boxes, greens with a hole, and Open Hole pairing them.
##
## Written without static references to scripts that depend on autoloads: a `-s`
## script compiles before the autoload singletons exist, so HoleLayout is loaded
## dynamically instead of being named in a type annotation.

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
	print("HOLE_CREATION_FLOW_FAIL: ", message)

func run() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	layout = load("res://scripts/tools/hole_layout.gd")
	main._on_main_menu_new_game("Hole Layout Check", 0)
	for i in range(8): await process_frame

	gm = root.get_node("GameManager")
	grid = main.terrain_grid
	check(gm.current_course != null, "A new game has a course")
	check(gm.current_course.holes.is_empty(), "A new game starts with no holes")

	# --- Tee box: 1x1 brush cap, and only one may wait on the course ---
	main._on_tool_selected(TerrainTypes.Type.TEE_BOX)
	main.terrain_toolbar.set_brush_size(5)
	check(main.brush_size == 5, "Toolbar brush size change must reach main")
	check(main.terrain_toolbar.effective_brush_size() == 1, "Tee box brush is capped at 1x1")

	var tee := Vector2i(60, 60)
	main.undo_manager.begin_stroke()
	main._paint_terrain_stamp(tee)
	main.undo_manager.end_stroke()
	check(grid.get_tile(tee) == TerrainTypes.Type.TEE_BOX, "Tee box tile painted")
	check(grid.get_tee_box_tiles().size() == 1, "Tee box must paint exactly one tile")
	check(grid.get_tile(tee + Vector2i(1, 0)) != TerrainTypes.Type.TEE_BOX, "Tee brush is not 5x5")
	check(layout.can_place_tee_box(grid, gm.current_course) == false, "The waiting tee blocks another")

	var cash_before_second_tee: int = gm.money
	var second_tee := Vector2i(70, 70)
	main.undo_manager.begin_stroke()
	main._paint_terrain_stamp(second_tee)
	main.undo_manager.end_stroke()
	check(grid.get_tile(second_tee) != TerrainTypes.Type.TEE_BOX, "A second tee box must wait")
	check(gm.money == cash_before_second_tee, "A blocked tee box costs nothing")

	# --- Green: the first green is a 1x1 Green With Hole ---
	main._on_tool_selected(TerrainTypes.Type.GREEN)
	main.terrain_toolbar.set_brush_size(5)
	check(main.terrain_toolbar.effective_brush_size() == 1, "Green With Hole is capped at 1x1")
	check(main.terrain_toolbar._green_preset_group.visible == false, "No preset shape for a cup")

	var cup := Vector2i(68, 60)
	main.undo_manager.begin_stroke()
	main._paint_terrain_stamp(cup)
	main.undo_manager.end_stroke()
	check(grid.get_tile(cup) == TerrainTypes.Type.GREEN, "Green tile painted")
	check(grid.get_cup_tiles() == [cup], "The first green carries the hole")
	check(grid.get_tile(cup + Vector2i(1, 0)) != TerrainTypes.Type.GREEN, "Cup green is one tile")
	check(layout.green_places_cup(grid, gm.current_course) == false, "A cup is waiting now")
	check(main.terrain_toolbar._open_hole_buttons[0].disabled == false, "Open Hole is ready")
	for i in range(2): await process_frame  # let the cup overlay draw its waiting pin

	# --- Undo/redo keeps the cup marker with its tile ---
	main._perform_undo()
	check(grid.get_tile(cup) != TerrainTypes.Type.GREEN, "Undo removes the painted green")
	check(grid.get_cup_tiles().is_empty(), "Undo removes the cup with it")
	main._perform_redo()
	check(grid.get_tile(cup) == TerrainTypes.Type.GREEN, "Redo repaints the green")
	check(grid.get_cup_tiles() == [cup], "Redo restores the cup")

	# --- While a cup waits, the same green brush widens the putting surface ---
	var patch := Vector2i(cup.x, cup.y + 2)
	main.undo_manager.begin_stroke()
	main._paint_terrain_stamp(patch)
	main.undo_manager.end_stroke()
	var painted := 0
	for pos in grid.get_brush_tiles(patch, 5, main.round_brush):
		if grid.get_tile(pos) == TerrainTypes.Type.GREEN: painted += 1
	check(painted > 1, "Green Without Hole paints with the standard brush")
	check(grid.get_cup_tiles() == [cup], "Widening the green adds no second cup")
	check(main.terrain_toolbar.effective_brush_size() == 5, "The brush is uncapped once a cup waits")
	check(main.terrain_toolbar._green_preset_group.visible == true, "Presets return for plain green")

	# --- Open Hole (H) pairs the waiting tee with the waiting cup ---
	main._on_open_hole_pressed()
	check(gm.current_course.holes.size() == 1, "Open Hole created the hole")
	check(grid.get_cup_tiles().is_empty(), "Opening a hole consumes the cup")

	var hole = gm.current_course.holes[0]
	check(hole.tee_position == tee, "Hole tee is the painted tee box")
	check(hole.green_position == cup, "Hole green is the painted cup")
	check(hole.hole_position == cup, "Cup position is the painted cup")
	check(layout.can_place_tee_box(grid, gm.current_course), "The tee is claimed, so a new one may be painted")
	check(layout.green_places_cup(grid, gm.current_course), "The next green carries the next cup")
	check(main.terrain_toolbar._open_hole_buttons[0].disabled == true, "Nothing waiting to open")

	# --- The loop restarts: the next green is a capped Green With Hole again ---
	main._on_tool_selected(TerrainTypes.Type.GREEN)
	main.terrain_toolbar.set_brush_size(5)
	check(main.terrain_toolbar.effective_brush_size() == 1, "A fresh green is capped at 1x1 again")
	check(main.terrain_toolbar._green_preset_group.visible == false, "No preset shape for a cup")

	var next_cup := Vector2i(50, 50)
	main.undo_manager.begin_stroke()
	main._paint_terrain_stamp(next_cup)
	main.undo_manager.end_stroke()
	check(grid.get_cup_tiles() == [next_cup], "The next green carries a cup")
	for i in range(2): await process_frame  # draw the cup overlay for the new cup

	# --- Waiting cups and open holes both survive a save/load round trip ---
	var sm = root.get_node("SaveManager")
	var data: Dictionary = sm._build_save_data()
	sm._apply_save_data(data)
	check(gm.current_course.holes.size() == 1, "The hole survives save/load")
	check(gm.current_course.holes[0].hole_position == cup, "The opened cup survives save/load")
	check(grid.get_cup_tiles() == [next_cup], "The waiting cup survives save/load")

	if failures == 0:
		print("HOLE_CREATION_FLOW_PASS: 1x1 tee cap, blocked second tee, green with hole, undo/redo of the cup, open hole pairing, standard green brush, save round trip")
	quit(1 if failures > 0 else 0)
