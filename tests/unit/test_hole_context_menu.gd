extends GutTest
## The hole's context menu: the actions it offers and what each one asks for.
## Deleting is the destructive one, so it sits apart and only ever asks — the
## question itself is main.gd's to put to the player.

var grid: TerrainGrid
var hole: GameManager.HoleData
var menu: HoleContextMenu

func before_each() -> void:
	grid = TerrainGrid.new()
	grid.grid_width = 16
	grid.grid_height = 16
	add_child_autofree(grid)

	hole = GameManager.HoleData.new()
	hole.hole_number = 3
	hole.par = 4
	hole.distance_yards = 350
	hole.tee_position = Vector2i(2, 2)
	hole.green_position = Vector2i(10, 10)
	hole.hole_position = Vector2i(10, 10)
	hole.pin_positions = [Vector2i(10, 10)]
	grid.set_tile(hole.tee_position, TerrainTypes.Type.TEE_BOX)
	grid.set_tile(hole.green_position, TerrainTypes.Type.GREEN)

	menu = HoleContextMenu.new(hole, grid)
	add_child_autofree(menu)

func _menu_button(label: String) -> Button:
	for child in menu.find_children("*", "Button", true, false):
		var button := child as Button
		if button and button.text == label:
			return button
	return null

func test_delete_hole_is_offered_apart_from_the_other_actions() -> void:
	var delete_btn := _menu_button("Delete Hole")
	assert_not_null(delete_btn, "The menu offers Delete Hole")
	assert_eq(delete_btn.get_theme_color("font_color"), UIConstants.COLOR_DANGER,
			"Delete Hole reads as destructive")

	# It sits at the bottom, below a separator, away from the actions that only
	# move things about.
	var actions: Array[Node] = delete_btn.get_parent().get_children()
	assert_same(actions[actions.size() - 1], delete_btn, "Delete Hole is the last action")
	assert_true(actions[actions.size() - 2] is HSeparator, "A separator sets it apart")

func test_delete_hole_only_asks() -> void:
	var delete_btn := _menu_button("Delete Hole")
	watch_signals(menu)
	delete_btn.pressed.emit()

	assert_signal_emitted_with_parameters(menu, "delete_hole_requested", [3])
	assert_true(menu.is_queued_for_deletion(), "The menu closes behind the question")
	# The menu carries no reference to the course, so asking changes nothing.
	assert_eq(grid.get_tile(hole.tee_position), TerrainTypes.Type.TEE_BOX,
			"Asking leaves the tee box painted")
	assert_eq(grid.get_tile(hole.green_position), TerrainTypes.Type.GREEN,
			"Asking leaves the green painted")

func test_the_menu_still_offers_the_open_close_toggle_and_statistics() -> void:
	assert_not_null(_menu_button("Close Hole"), "An open hole can be closed from its menu")
	assert_not_null(_menu_button("View Statistics"), "Statistics stay one click away")
