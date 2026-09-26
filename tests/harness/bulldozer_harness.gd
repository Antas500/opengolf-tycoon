extends Node
## Headless smoke test for the Bulldozer's remit: it demolishes Improvements
## and Buildings (walking paths, decorations, buildings — from any footprint
## tile of a multi-tile facility) and never touches Course Terrain tiles,
## which replace each other when painted instead.
##
## Run:  godot --headless --path . res://tests/harness/bulldozer_harness.tscn

var main: Node2D
var grid: TerrainGrid
var failures: int = 0

func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _check(condition: bool, label: String) -> void:
	if condition:
		print("HARNESS: PASS: %s" % label)
	else:
		failures += 1
		printerr("HARNESS: FAIL: %s" % label)

## The quick-start course scatters trees; drop whatever stands on a tile and
## repaint it so each scenario runs on known ground (harness choreography,
## not player strokes — undo stays suppressed).
func _prep(pos: Vector2i, terrain: int) -> void:
	main._suppress_tile_undo = true
	if main.entity_layer.get_tree_at(pos):
		main.entity_layer.remove_tree(pos)
	if main.entity_layer.get_rock_at(pos):
		main.entity_layer.remove_rock(pos)
	grid.set_tile(pos, terrain)
	main._suppress_tile_undo = false

func _run() -> void:
	await _frames(10)
	print("HARNESS: quick-starting new game")
	main._on_main_menu_quick_start("Dozer Harness", 0)
	await _frames(60)
	grid = main.terrain_grid
	await _frames(5)

	# Test tiles on owned land near the clubhouse (see walking_path_harness).
	var brush_tile := Vector2i(50, 62)
	var rocks_tile := Vector2i(51, 62)
	var flowers_tile := Vector2i(49, 62)
	var water_tile := Vector2i(60, 50)
	var tree_tile := Vector2i(59, 50)
	var boulder_tile := Vector2i(58, 50)
	_prep(brush_tile, TerrainTypes.Type.BRUSH)
	_prep(rocks_tile, TerrainTypes.Type.ROCKS)
	_prep(flowers_tile, TerrainTypes.Type.FLOWER_BED)
	_prep(water_tile, TerrainTypes.Type.WATER)
	_prep(tree_tile, TerrainTypes.Type.GRASS)
	_prep(boulder_tile, TerrainTypes.Type.GRASS)
	main.entity_layer.place_tree(tree_tile, "oak")
	main.entity_layer.place_rock(boulder_tile, "small")
	await _frames(2)

	# ------------------------------------------------------------------
	# 1. Course Terrain tiles replace each other when painted.
	# ------------------------------------------------------------------
	main.terrain_toolbar._on_tool_button_pressed(TerrainTypes.Type.ROUGH)
	main._paint_terrain_stamp(brush_tile)
	_check(grid.get_tile(brush_tile) == TerrainTypes.Type.ROUGH,
			"painting Rough over Brush replaces it")
	main.terrain_toolbar._on_tool_button_pressed(TerrainTypes.Type.FAIRWAY)
	main._paint_terrain_stamp(rocks_tile)
	_check(grid.get_tile(rocks_tile) == TerrainTypes.Type.FAIRWAY,
			"painting Fairway over Rocks replaces it")
	main.terrain_toolbar._on_tool_button_pressed(TerrainTypes.Type.BUNKER)
	main._paint_terrain_stamp(flowers_tile)
	_check(grid.get_tile(flowers_tile) == TerrainTypes.Type.BUNKER,
			"painting Bunker over Flower Bed replaces it")
	main.terrain_toolbar._on_tool_button_pressed(TerrainTypes.Type.STREAM)
	main._paint_terrain_stamp(water_tile)
	_check(grid.get_tile(water_tile) == TerrainTypes.Type.STREAM,
			"painting Stream over Water replaces it")

	# ------------------------------------------------------------------
	# 2. The Bulldozer never touches Course Terrain tiles.
	# ------------------------------------------------------------------
	main._on_bulldozer_pressed()
	await _frames(2)
	_check(main.bulldozer_mode, "bulldozer mode is active")
	_check(main.terrain_toolbar._bulldozer_buttons.all(
			func(btn): return btn.is_active()),
			"the pinned buttons show bulldozer mode is on")

	var money := GameManager.money
	main._handle_bulldozer_click(brush_tile)
	_check(grid.get_tile(brush_tile) == TerrainTypes.Type.ROUGH,
			"bulldozer left the painted Rough in place")
	main._handle_bulldozer_click(rocks_tile)
	_check(grid.get_tile(rocks_tile) == TerrainTypes.Type.FAIRWAY,
			"bulldozer left the painted Fairway in place")
	main._handle_bulldozer_click(flowers_tile)
	_check(grid.get_tile(flowers_tile) == TerrainTypes.Type.BUNKER,
			"bulldozer left the painted Bunker in place")
	main._handle_bulldozer_click(water_tile)
	_check(grid.get_tile(water_tile) == TerrainTypes.Type.STREAM,
			"bulldozer left the painted Stream in place")
	_check(GameManager.money == money, "bulldozing course terrain charges nothing")

	# Placed landscape tiles are course terrain too: trees and boulders stay.
	main._handle_bulldozer_click(tree_tile)
	_check(main.entity_layer.get_tree_at(tree_tile) != null,
			"bulldozer left the tree standing")
	main._handle_bulldozer_click(boulder_tile)
	_check(main.entity_layer.get_rock_at(boulder_tile) != null,
			"bulldozer left the boulder standing")
	_check(GameManager.money == money, "bulldozing trees and boulders charges nothing")

	# ------------------------------------------------------------------
	# 3. The Bulldozer demolishes Improvements: a decoration for $20.
	# ------------------------------------------------------------------
	var deco_pos := Vector2i(48, 62)
	_prep(deco_pos, TerrainTypes.Type.GRASS)
	main.entity_layer.place_decoration("topiary", deco_pos, main.decoration_registry)
	await _frames(2)
	_check(main.entity_layer.get_decoration_at(deco_pos) != null, "topiary placed")
	money = GameManager.money  # re-snapshot: the day simulation keeps earning
	main._handle_bulldozer_click(deco_pos)
	await _frames(2)
	_check(main.entity_layer.get_decoration_at(deco_pos) == null,
			"bulldozer removed the decoration")
	_check(GameManager.money == money - 20, "bulldozer charged $20 for the decoration")

	# ------------------------------------------------------------------
	# 4. The Bulldozer demolishes Buildings from any footprint tile: a
	#    2x3 cart shed falls to a click on its far corner, flat $20 fee.
	# ------------------------------------------------------------------
	var shed_pos := Vector2i(48, 56)
	_prep(shed_pos, TerrainTypes.Type.GRASS)
	for offset in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1),
			Vector2i(0, 2), Vector2i(1, 2)]:
		_prep(shed_pos + offset, TerrainTypes.Type.GRASS)
	main.entity_layer.place_building("cart_shed", shed_pos, main.building_registry)
	await _frames(2)
	_check(main.entity_layer.is_tile_occupied_by_building(shed_pos + Vector2i(1, 2)),
			"cart shed covers its 2x3 footprint")
	money = GameManager.money  # re-snapshot: the day simulation keeps earning
	main._handle_bulldozer_click(shed_pos + Vector2i(1, 2))
	await _frames(2)
	_check(not main.entity_layer.is_tile_occupied_by_building(shed_pos),
			"clicking a footprint tile demolished the whole building")
	_check(not main.entity_layer.is_tile_occupied_by_building(shed_pos + Vector2i(1, 2)),
			"the building is gone from every tile")
	_check(GameManager.money == money - 20, "demolition charged a flat $20, whatever the facility")

	# ------------------------------------------------------------------
	# 5. Leaving bulldozer mode quiets the pinned buttons again.
	# ------------------------------------------------------------------
	main._cancel_bulldozer_mode()
	await _frames(2)
	_check(main.terrain_toolbar._bulldozer_buttons.all(
			func(btn): return not btn.is_active()),
			"the pinned buttons show bulldozer mode is off")

	# The toolbar still routes the pinned buttons and the X hotkey through the
	# same signal, without switching tabs.
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.IMPROVEMENTS)
	main.terrain_toolbar._bulldozer_buttons[0].pressed.emit()
	_check(main.bulldozer_mode, "pinned button activates bulldozer mode")
	_check(main.terrain_toolbar._tab_bar.current_tab == TerrainToolbar.Tab.IMPROVEMENTS,
			"pressing the pinned Bulldozer keeps its tab open")
	main._cancel_bulldozer_mode()

	print("HARNESS: done, %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
