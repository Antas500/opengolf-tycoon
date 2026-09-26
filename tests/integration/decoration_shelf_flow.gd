extends SceneTree
## Integration regression for the garden shed moving into the toolbar: the
## Improvements tab lists every decoration as a tile, picking one starts
## placement straight away, locked ornaments stay unselectable, and no separate
## picker window is opened any more.
##
## Written without static references to scripts that depend on autoloads: a `-s`
## script compiles before the autoload singletons exist, so the toolbar and the
## placement manager are reached through the live scene instead.
##
## Run:  godot --headless --path . -s res://tests/integration/decoration_shelf_flow.gd

var main: Node
var toolbar
var placements
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	print("DECORATION_SHELF_FLOW_FAIL: ", message)

func run() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._on_main_menu_quick_start("Decoration shelf flow", 0)
	for i in range(8): await process_frame
	toolbar = main.terrain_toolbar
	placements = main.placement_manager
	var gm = root.get_node("GameManager")
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/decorations.json"))["decorations"]

	# O still opens the decorations — as the toolbar tab, not a popup window.
	main._on_decoration_placement_pressed()
	check(toolbar._tab_bar.current_tab == toolbar.Tab.IMPROVEMENTS, "Decorations open the Improvements tab")
	check(placements.placement_mode == placements.PlacementMode.NONE,
		"Opening the tab does not start a placement")
	for child in main.get_children():
		check(not (child is Window), "Decorations no longer open a separate window")

	# The shelf carries the whole catalogue, locked ornaments included.
	check(toolbar._decoration_shelf.get_child_count() == registry.size(),
		"Every decoration is a tile on the shelf")
	check(toolbar._decoration_shelf.columns == ceili(float(registry.size()) / 2.0),
		"The shelf is laid out in two interlocking rows")

	# A locked ornament cannot start a placement: drop the rating below the
	# statue's 4-star requirement, then check the tile greys out and says what it
	# still needs.
	gm.course_rating["stars"] = 1
	toolbar.refresh_decoration_unlocks()
	var locked = toolbar._decoration_tiles["golfer_statue"]
	check(locked.disabled, "The 4-star statue locks while the course holds one star")
	check(locked.tool_description.contains("4★ rating"), "The tile says what it still needs")
	locked.pressed.emit()
	check(placements.placement_mode == placements.PlacementMode.NONE,
		"A locked ornament never starts placement")
	gm.course_rating["stars"] = 5
	toolbar.refresh_decoration_unlocks()
	check(not locked.disabled, "Meeting the requirement unlocks the tile")
	var tile = toolbar._decoration_tiles["rose_border"]

	# An unlocked tile starts placement on the catalogue's terms.
	tile.pressed.emit()
	check(placements.placement_mode == placements.PlacementMode.DECORATION,
		"Pressing a decoration tile starts decoration placement")
	check(placements.selected_decoration_type == "rose_border",
		"Placement uses the tile's decoration type")
	check(toolbar._tab_bar.current_tab == toolbar.Tab.IMPROVEMENTS,
		"Picking a tile keeps the Improvements tab open")

	# And it places with the normal click path, for the catalogue price.
	var pos := _find_placement_tile()
	check(pos != Vector2i(-1, -1), "A legal decoration tile should exist near the clubhouse")
	if pos != Vector2i(-1, -1):
		var cash_before: int = gm.money
		main._handle_placement_click(pos)
		check(main.entity_layer.get_decoration_at(pos) != null, "The clicked tile carries the decoration")
		check(gm.money == cash_before - int(registry["rose_border"]["cost"]),
			"Rose Border is charged at the catalogue price")

	if failures == 0:
		print("DECORATION_SHELF_FLOW_PASS: shelf tiles, locks and placement from the Improvements tab")
		quit(0)
	else:
		quit(1)

func _find_placement_tile() -> Vector2i:
	for hole in root.get_node("GameManager").current_course.holes:
		for radius in range(1, 6):
			for dx in range(-radius, radius + 1):
				for dy in range(-radius, radius + 1):
					var pos: Vector2i = hole.tee_position + Vector2i(dx, dy)
					if placements.can_place_at(pos, main.terrain_grid):
						return pos
	return Vector2i(-1, -1)
