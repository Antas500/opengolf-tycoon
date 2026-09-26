extends SceneTree
## The Course Holes tab holds one button per hole, three to a column, and a
## button opens that hole's context menu — the same menu the course's tee, green
## and flag open — instead of the statistics screen. Nothing else sits beside a
## hole button: its Open/Close toggle and its Delete button are gone, and the
## menu still reaches both the open/closed state and the statistics. Deleting a
## hole lives in that menu too, behind a confirm dialog.
##
## Uses dynamic loads because a `-s` script compiles before autoloads exist.
##
## Run: godot --headless --path . -s res://tests/integration/hole_tab_context_menu.gd

var main: Node
var gm
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	print("HOLE_TAB_FAIL: ", message)

func frames(count: int) -> void:
	for i in range(count):
		await process_frame

func menu_button(menu: Node, label: String) -> Button:
	if not menu:
		return null
	for child in menu.find_children("*", "Button", true, false):
		var button := child as Button
		if button and button.text == label:
			return button
	return null

func run() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._on_main_menu_quick_start("Hole Tab Check", 0)
	await frames(8)

	gm = root.get_node("GameManager")
	var grid = main.hole_grid
	var hole_count: int = gm.current_course.holes.size()
	check(hole_count == 9, "Quick Start builds nine holes, got %d" % hole_count)

	# --- One button per hole, and nothing else on the tab ---
	check(grid.get_child_count() == hole_count,
			"One button per hole, got %d children" % grid.get_child_count())
	check(grid.find_children("*", "Button", true, false).size() == hole_count,
			"No Open/Close or Delete button sits beside a hole button")
	check(grid.columns == 3, "Nine holes fill three columns of three, got %d" % grid.columns)

	# Reading down the columns: 1,2,3 then 4,5,6 then 7,8,9.
	var reading_order := [1, 4, 7, 2, 5, 8, 3, 6, 9]
	for slot in reading_order.size():
		check(int(grid.get_child(slot).get_meta("hole_number")) == reading_order[slot],
				"Slot %d holds hole %d" % [slot, reading_order[slot]])

	# --- A hole button opens the context menu, not the statistics screen ---
	main._on_hole_button_pressed(2)
	await frames(3)
	var menu = main.get_node("UI").get_node_or_null("HoleContextMenu")
	check(menu != null, "A hole button opens the hole's context menu")
	check(main._hole_context_menu != null \
			and main._hole_context_menu.hole_data.hole_number == 2,
			"The menu is for the hole that was clicked")
	check(not main.hole_stats_panel.visible, "The statistics screen stays closed")

	# --- The menu still owns the open/closed state the button reflects ---
	main._on_context_toggle_hole(2)
	await frames(3)
	check(gm.current_course.holes[1].is_open == false, "The menu closed hole 2")
	var hole_two: Button = grid.get_node("HoleBtn2")
	check(hole_two.modulate.r < 1.0, "The closed hole's button dims")
	check("Closed" in hole_two.tooltip_text, "The closed hole says so in its tooltip")

	# --- And the par, which the button's label reads back ---
	main._on_context_par_override(2, 5)
	await frames(3)
	check("P5" in hole_two.text, "The button reads back the new par, got '%s'" % hole_two.text)
	main._on_context_view_stats(2)
	await frames(3)
	check(main.hole_stats_panel.visible, "The menu still reaches the statistics screen")
	main._on_hole_stats_panel_closed()
	main._close_hole_context_menu()
	# Let the closed menu leave the tree, the way a click would.
	await frames(3)

	# --- Delete Hole asks first, and only deletes on a yes ---
	var first_tee = gm.current_course.holes[0].tee_position
	var first_green = gm.current_course.holes[0].green_position
	main._on_hole_button_pressed(1)
	await frames(3)
	var delete_menu = main.get_node("UI").get_node_or_null("HoleContextMenu")
	check(delete_menu != null, "The hole button reopened its menu")
	if delete_menu:
		var delete_btn := menu_button(delete_menu, "Delete Hole")
		check(delete_btn != null, "The menu offers Delete Hole")
		if delete_btn:
			delete_btn.pressed.emit()
			await frames(3)

	var hud = main.get_node("UI/HUD")
	var question = hud.get_node_or_null("DeleteHoleConfirmDialog")
	check(question != null, "Delete Hole asks before it deletes")
	check(main._hole_context_menu == null, "The menu closes behind the question")
	if question:
		question._on_cancel()
		await frames(3)
	check(gm.current_course.holes.size() == hole_count, "Cancelling keeps every hole")
	check(hud.get_node_or_null("DeleteHoleConfirmDialog") == null, "The question goes away")
	check(grid.get_child_count() == hole_count, "And every hole keeps its button")

	main._on_context_delete_hole(1)
	await frames(3)
	question = hud.get_node_or_null("DeleteHoleConfirmDialog")
	check(question != null, "Delete Hole asks again on the second try")
	if question:
		question._on_confirm()
		await frames(3)
	check(gm.current_course.holes.size() == 8,
			"Confirming deletes the hole, got %d" % gm.current_course.holes.size())

	# What the question promised: the tiles stay painted for the next hole.
	check(main.terrain_grid.get_tile(first_tee) == TerrainTypes.Type.TEE_BOX,
			"The deleted hole's tee box stays painted")
	check(main.terrain_grid.get_tile(first_green) == TerrainTypes.Type.GREEN,
			"The deleted hole's green stays painted")

	# --- A hole that goes leaves no gap in the columns ---
	check(grid.get_child_count() == 8, "Eight holes left, got %d" % grid.get_child_count())
	check(grid.columns == 3, "Eight holes fill two columns of three and start a third")
	var renumbered := [1, 4, 7, 2, 5, 8, 3, 6]
	for slot in renumbered.size():
		check(int(grid.get_child(slot).get_meta("hole_number")) == renumbered[slot],
				"Slot %d holds hole %d after the deletion" % [slot, renumbered[slot]])

	if failures == 0:
		print("HOLE_TAB_PASS: one button per hole, three to a column, each opening its hole's context menu — and Delete Hole asks before it deletes")
	quit(1 if failures > 0 else 0)
