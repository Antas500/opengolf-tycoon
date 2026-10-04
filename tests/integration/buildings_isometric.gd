extends SceneTree
## Integration regression: buildings are drawn on the grid they stand on.
##
## A new course's clubhouse is an isometric solid on its own four tiles: the
## drawing follows the course when the view rotates, each upgrade tier rebuilds
## it without changing the footprint, and the placement ghost and the catalogue
## tiles go through the same routine. Everything here runs through the real
## scene, so a facility that stops reaching the drawing fails.
##
## Uses dynamic loads because a `-s` script compiles before autoloads exist.

var main: Node
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	print("BUILDINGS_ISOMETRIC_FAIL: ", message)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func run() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._on_main_menu_new_game("Isometric buildings", 0)
	await _frames(8)

	var grid = main.terrain_grid
	var entities = main.entity_layer
	check(grid != null, "the course has a grid")
	check(entities != null, "the course has an entity layer")
	if grid == null or entities == null:
		_finish()
		return

	var clubhouse = null
	for building in entities.get_all_buildings():
		if building.is_clubhouse():
			clubhouse = building
	check(clubhouse != null, "the course starts with a clubhouse")
	if clubhouse == null:
		_finish()
		return

	var architecture = clubhouse.get_node_or_null("Visual/Architecture")
	check(architecture != null, "the clubhouse draws through CourseArchitecture")
	if architecture != null:
		check(architecture.footprint == Vector2(clubhouse.width * 64, clubhouse.height * 32),
			"the drawing knows the footprint it has to fill")
		print("clubhouse at %s, %dx%d tiles, facing %d" % [clubhouse.grid_position,
			clubhouse.width, clubhouse.height, architecture.facing])

	# Every tier draws, and none of them outgrows the tiles.
	for level in range(1, 4):
		clubhouse.upgrade_level = level
		clubhouse._update_visuals()
		await _frames(2)
		var arch = clubhouse.get_node_or_null("Visual/Architecture")
		check(arch != null, "tier %d has a drawing" % level)
		if arch == null:
			continue
		check(arch.level == level, "tier %d reached the drawing" % level)
		check(arch.footprint == Vector2(clubhouse.width * 64, clubhouse.height * 32),
			"tier %d keeps the footprint" % level)

	# Rotating the course turns the building with it.
	for rotation in range(4):
		grid.rotate_view_cw()
		await _frames(2)
		var arch = clubhouse.get_node_or_null("Visual/Architecture")
		check(arch != null and arch.facing == grid.get_view_orientation(),
			"rotation %d moved the drawing" % rotation)

	# The placement ghost: the same routine, on the course's current view.
	main.placement_preview._draw_building_ghost_shape(Vector2i(10, 10), "restaurant",
		Vector2i(3, 3), Color(0.3, 0.9, 0.3, 0.6))
	check(main.placement_preview._building_ghost.visible, "the ghost is visible")
	check(main.placement_preview._building_ghost.facing == grid.get_view_orientation(),
		"the ghost follows the view")
	await _frames(2)

	# Every catalogue tile, drawn the way the Buildings tab draws it.
	var tile_art = load("res://scripts/ui/components/building_tile_art.gd")
	var drawn: int = 0
	for kind in main.building_registry.keys():
		var tile = tile_art.new()
		main.add_child(tile)
		tile.configure(kind, main.building_registry[kind])
		await _frames(1)
		drawn += 1
	check(drawn >= 16, "every building has a catalogue tile (drew %d)" % drawn)

	_finish()


func _finish() -> void:
	if failures == 0:
		print("BUILDINGS_ISOMETRIC_OK")
	else:
		print("BUILDINGS_ISOMETRIC_FAILED: %d failures" % failures)
	quit(failures)
