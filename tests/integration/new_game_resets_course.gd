extends SceneTree
## Integration regression: starting a new game must leave no trace of the course
## that was played before it.
##
## `_on_new_game_started()` regenerated natural terrain over the existing grid
## without clearing it, so anything from the previous session survived: tee boxes,
## greens, fairways, bunker depths, waiting cups, sculpted elevation, placed
## entities, golfers, hole flags and the undo stack. Under the tee box rule a leftover tee box is
## worse than cosmetic — it blocks the player's very first tee.

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
	print("NEW_GAME_RESET_FAIL: ", message)

func _count_tiles_of_types(types: Array) -> int:
	var total := 0
	for y in range(grid.grid_height):
		for x in range(grid.grid_width):
			if grid.get_tile(Vector2i(x, y)) in types:
				total += 1
	return total

func run() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	layout = load("res://scripts/tools/hole_layout.gd")
	gm = root.get_node("GameManager")
	grid = main.terrain_grid

	# ---------------------------------------------------------------- first course
	main._on_main_menu_new_game("First Course", 0)
	for i in range(8): await process_frame

	var tee := Vector2i(60, 60)
	var cup := Vector2i(60, 50)
	main._on_tool_selected(TerrainTypes.Type.TEE_BOX)
	main.undo_manager.begin_stroke()
	main._paint_terrain_stamp(tee)
	main.undo_manager.end_stroke()
	main._on_tool_selected(TerrainTypes.Type.GREEN)
	main.undo_manager.begin_stroke()
	main._paint_terrain_stamp(cup)
	main.undo_manager.end_stroke()
	main._on_open_hole_pressed()
	for i in range(4): await process_frame

	check(gm.current_course.holes.size() == 1, "First course opens one hole")
	check(grid.get_tee_box_tiles().size() == 1, "First course leaves a tee box behind")
	main.entity_layer.place_rock(Vector2i(58, 58), "medium")
	check(main.entity_layer.rocks.has(Vector2i(58, 58)), "First course has a placed rock")
	var sculpted := Vector2i(61, 61)
	grid.set_vertex_elevation(sculpted, 5)
	check(grid.get_vertex_elevation(sculpted) == 5, "First course has sculpted elevation")
	check(main.undo_manager.can_undo(), "First course has undo history")
	check(main.hole_manager.get_all_hole_visualizers().size() == 1, "First course has a hole flag")
	main.golfer_manager.spawn_initial_group()
	for i in range(4): await process_frame
	check(main.golfer_manager.get_active_golfers().size() > 0, "First course has golfers on it")

	var built_tiles_before: int = _count_tiles_of_types([
		TerrainTypes.Type.TEE_BOX, TerrainTypes.Type.GREEN,
		TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.BUNKER,
	])
	check(built_tiles_before > 0, "First course has built tiles on the grid")

	# --------------------------------------------------------------- second course
	main._on_main_menu_new_game("Second Course", 0)
	for i in range(10): await process_frame

	check(gm.course_name == "Second Course", "The second game is running")
	check(gm.current_course.holes.is_empty(), "The second course starts with no holes")
	check(grid.get_tee_box_tiles().is_empty(), "No tee box survives into the second course")
	check(grid.get_cup_tiles().is_empty(), "No waiting cup survives into the second course")
	check(_count_tiles_of_types([
		TerrainTypes.Type.TEE_BOX, TerrainTypes.Type.GREEN,
		TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.BUNKER,
	]) == 0, "No built tile survives into the second course")
	# Player-placed marks are not asserted here: natural tree and rock placement
	# goes through set_tile() with player_placed=true, so every new game marks its
	# own vegetation. reset_for_new_course() clearing them is covered in
	# tests/unit/test_cup_tiles.gd, where the grid is not re-vegetated.
	check(grid.serialize_bunker_depth().is_empty(), "No bunker depth survives")
	check(not main.entity_layer.rocks.has(Vector2i(58, 58)), "The placed rock is gone")
	check(main.hole_manager.get_all_hole_visualizers().is_empty(), "The old hole flag is gone")
	check(not main.undo_manager.can_undo(), "Undo history does not cross into the second course")
	check(main.golfer_manager.get_active_golfers().is_empty(), "No golfer survives into the second course")
	check(layout.can_place_tee_box(grid, gm.current_course), "The player can paint a first tee box")
	# Natural generation clamps vertices to the theme's elevation range (max 3), so
	# the +5 the player sculpted can only come back if the vertex was never reset.
	check(grid.get_vertex_elevation(sculpted) != 5, "Sculpted elevation is regenerated, not inherited")

	# The second course must still be playable: a tee and a green open a hole.
	main._on_tool_selected(TerrainTypes.Type.TEE_BOX)
	main.undo_manager.begin_stroke()
	main._paint_terrain_stamp(tee)
	main.undo_manager.end_stroke()
	check(grid.get_tile(tee) == TerrainTypes.Type.TEE_BOX,
			"A tee box paints on the second course")
	main._on_tool_selected(TerrainTypes.Type.GREEN)
	main.undo_manager.begin_stroke()
	main._paint_terrain_stamp(cup)
	main.undo_manager.end_stroke()
	main._on_open_hole_pressed()
	check(gm.current_course.holes.size() == 1, "The second course opens its own hole")

	if failures == 0:
		print("NEW_GAME_RESET_PASS: tiles, cups, entities, golfers, flags, elevation and undo all reset on New Game")
	quit(1 if failures > 0 else 0)
