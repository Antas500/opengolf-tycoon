extends Node
## Headless smoke test for the Path improvement: paints the trail through the
## real main.gd paint stamp, verifies the terrain is untouched, the paved
## look when the trail reaches the quick-start clubhouse, save/load, the
## bulldozer removal, and undo/redo.
##
## Run:  godot --headless --path . res://tests/harness/walking_path_harness.tscn

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

## The quick-start course scatters trees; drop any standing on a tile so the
## trail test runs on bare ground (a reloaded tree would re-stamp its tile
## TREES and muddy the assertions).
func _clear_entity_at(pos: Vector2i) -> void:
	if main.entity_layer.get_tree_at(pos):
		main.entity_layer.remove_tree(pos)
	if main.entity_layer.get_rock_at(pos):
		main.entity_layer.remove_rock(pos)

func _run() -> void:
	await _frames(10)
	print("HARNESS: quick-starting new game")
	main._on_main_menu_quick_start("Walk Harness", 0)
	await _frames(60)
	grid = main.terrain_grid
	await _frames(5)

	# ------------------------------------------------------------------
	# 1. Select the Path tool the way the toolbar does, then paint a trail
	#    of four tiles west of the quick-start clubhouse (footprint 54..57,
	#    61..64). (53, 62) is the tile that touches the clubhouse.
	# ------------------------------------------------------------------
	main.terrain_toolbar._on_tool_button_pressed(TerrainTypes.Type.PATH)
	await _frames(2)
	_check(main.current_tool == TerrainTypes.Type.PATH, "Path tool selected (8)")

	var trail := [Vector2i(50, 62), Vector2i(51, 62), Vector2i(52, 62), Vector2i(53, 62)]
	# Prep the ground without polluting the undo stack (harness choreography,
	# not player strokes).
	main._suppress_tile_undo = true
	for pos in trail:
		_clear_entity_at(pos)
		grid.set_tile(pos, TerrainTypes.Type.ROUGH)
		_check(grid.is_valid_position(pos), "trail tile %s is on the course" % pos)
		_check(GameManager.land_manager.is_tile_owned(pos), "trail tile %s is owned land" % pos)
	main._suppress_tile_undo = false
	await _frames(2)

	var money_before := GameManager.money
	main.undo_manager.begin_stroke()
	for pos in trail:
		main._paint_walking_path_stamp(pos)
	main.undo_manager.end_stroke()
	await _frames(2)

	for pos in trail:
		_check(grid.has_walking_path(pos), "trail tile %s has a walking path" % pos)
		_check(grid.get_tile(pos) == TerrainTypes.Type.ROUGH,
				"trail tile %s terrain is untouched (still rough)" % pos)
	_check(GameManager.money == money_before - 4 * 8,
			"four trail tiles cost $32 (was %d, now %d)" % [money_before, GameManager.money])

	# Paint on unhostable ground must be refused (no path, no charge).
	var money_now := GameManager.money
	main._suppress_tile_undo = true
	_clear_entity_at(Vector2i(49, 62))
	grid.set_tile(Vector2i(49, 62), TerrainTypes.Type.FAIRWAY)
	main._suppress_tile_undo = false
	main._paint_walking_path_stamp(Vector2i(49, 62))
	_check(not grid.has_walking_path(Vector2i(49, 62)), "fairway refuses the trail")
	_check(GameManager.money == money_now, "refused trail costs nothing")

	# ------------------------------------------------------------------
	# 2. The trail reaches the clubhouse -> the whole component is paved.
	# ------------------------------------------------------------------
	var overlay: WalkingPathOverlay = grid.get_node("WalkingPathOverlay")
	await _frames(2)
	_check(overlay != null, "walking path overlay exists on the grid")
	for pos in trail:
		_check(overlay._upgraded_tiles.has(pos), "trail tile %s is paved (reaches clubhouse)" % pos)

	# A disconnected trail within the owned plot stays dirt.
	main._suppress_tile_undo = true
	_clear_entity_at(Vector2i(60, 50))
	_clear_entity_at(Vector2i(61, 50))
	grid.set_tile(Vector2i(60, 50), TerrainTypes.Type.ROUGH)
	grid.set_tile(Vector2i(61, 50), TerrainTypes.Type.ROUGH)
	main._suppress_tile_undo = false
	grid.set_walking_path(Vector2i(60, 50), true)
	grid.set_walking_path(Vector2i(61, 50), true)
	await _frames(2)
	_check(not overlay._upgraded_tiles.has(Vector2i(60, 50)), "far trail tile (60,50) stays dirt")

	# ------------------------------------------------------------------
	# 3. Run the tile geometry builder (the payload _draw executes) headless.
	# ------------------------------------------------------------------
	var dirt_cmds: Array = overlay.tile_draw_commands(trail[0], false, true)
	var paved_cmds: Array = overlay.tile_draw_commands(trail[0], true, true)
	_check(dirt_cmds.size() >= 2, "dirt tile emits dot plus connectors (%d commands)" % dirt_cmds.size())
	_check(paved_cmds.size() >= 2, "paved tile emits curb/paver detail (%d commands)" % paved_cmds.size())
	var all_typed := true
	for cmd in dirt_cmds + paved_cmds:
		if not (cmd is WalkingPathOverlay.DrawCommand):
			all_typed = false
	_check(all_typed, "every draw command is a typed DrawCommand")
	print("HARNESS: overlay geometry pass completed")

	# ------------------------------------------------------------------
	# 4. Save, break, load: the trail and its paved state survive.
	# ------------------------------------------------------------------
	SaveManager.save_game("walk_harness_slot")
	await _frames(30)
	grid.set_walking_path(Vector2i(51, 62), false)
	SaveManager.load_game("walk_harness_slot")
	await _frames(60)
	_check(grid.has_walking_path(Vector2i(51, 62)), "saved trail tile (51,62) restored on load")
	_check(grid.has_walking_path(Vector2i(50, 62)), "saved trail tile (50,62) restored on load")
	_check(grid.get_tile(Vector2i(51, 62)) == TerrainTypes.Type.ROUGH,
			"restored trail keeps its rough ground")
	overlay = grid.get_node("WalkingPathOverlay")
	await _frames(2)
	_check(overlay._upgraded_tiles.has(Vector2i(51, 62)), "restored trail is paved again")

	# ------------------------------------------------------------------
	# 5. Bulldozer removes a trail tile for its fee.
	# ------------------------------------------------------------------
	main._on_bulldozer_pressed()
	await _frames(2)
	var bulldoze_money := GameManager.money
	main._handle_bulldozer_click(Vector2i(52, 62))
	await _frames(2)
	_check(not grid.has_walking_path(Vector2i(52, 62)), "bulldozer removed the trail tile")
	_check(GameManager.money == bulldoze_money - 5, "bulldozer charged $5 for the trail")
	_check(grid.get_tile(Vector2i(52, 62)) == TerrainTypes.Type.ROUGH,
			"bulldozer left the rough ground in place")
	# (53,62) still touches the clubhouse and stays paved, while the detached
	# tail (50,62)-(51,62) reverts to dirt.
	await _frames(2)
	_check(overlay._upgraded_tiles.has(Vector2i(53, 62)),
			"tile still touching the clubhouse stays paved")
	_check(not overlay._upgraded_tiles.has(Vector2i(51, 62)),
			"detached tail reverts to dirt")

	# ------------------------------------------------------------------
	# 6. Undo/redo of the paint stroke and the bulldozer removal.
	# ------------------------------------------------------------------
	main._perform_undo()  # undo the bulldozer removal
	await _frames(2)
	_check(grid.has_walking_path(Vector2i(52, 62)), "undo restored the bulldozed trail tile")
	_check(overlay._upgraded_tiles.has(Vector2i(52, 62)), "restored trail is paved again")
	main._perform_redo()  # redo the removal
	await _frames(2)
	_check(not grid.has_walking_path(Vector2i(52, 62)), "redo removed the trail tile again")
	main._perform_undo()  # back to painted
	await _frames(2)
	main._perform_undo()  # undo the whole paint stroke
	await _frames(2)
	_check(not grid.has_walking_path(Vector2i(50, 62)), "undo of the paint stroke cleared tile (50,62)")
	_check(not grid.has_walking_path(Vector2i(53, 62)), "undo of the paint stroke cleared tile (53,62)")
	main._perform_redo()  # re-apply the paint stroke
	await _frames(2)
	_check(grid.has_walking_path(Vector2i(50, 62)), "redo re-laid the trail")

	print("HARNESS: done, %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
