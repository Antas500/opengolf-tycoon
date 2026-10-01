extends Node
## Headless smoke test for the three elevation selector tools (Vertex, Flat
## Square, Gradual Square) through the real main.gd input path: the toolbar
## selects the tool, right click raises, left click lowers, right click never
## cancels the tool, and Esc still does.
##
## The Square Selectors' brush is measured in tiles: it reshapes the tiles it
## covers, so a 3x3 brush holds 16 vertices (4 per side).
##
## Run:  godot --headless --path . res://tests/harness/elevation_tools_harness.tscn

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

func _mouse_button(pressed: bool, button_index: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	return event

## An owned, unoccupied tile in the middle of the quick-start course: every
## corner of it (and of the brushes centred on it) can be reshaped.
func _pick_tile() -> Vector2i:
	for radius in range(0, 20):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tile := Vector2i(64, 64) + Vector2i(dx, dy)
				if not grid.is_valid_position(tile):
					continue
				if _tile_is_editable(tile):
					return tile
	return Vector2i(64, 64)

func _tile_is_editable(tile: Vector2i) -> bool:
	for vertex in grid.vertices_of_tile(tile):
		if not grid.is_vertex_editable(vertex, main.entity_layer, false):
			return false
	return true

## Flatten every vertex of the brush centred on `anchor` so assertions are exact.
func _flatten(anchor: Vector2i, size: int) -> void:
	for vertex in ElevationTool.brush_vertices(grid, anchor, size, true):
		grid.set_vertex_elevation(vertex, grid.BASE_ELEVATION)

func _run() -> void:
	await _frames(10)
	print("HARNESS: quick-starting new game")
	main._on_main_menu_quick_start("Elevation Harness", 0)
	await _frames(60)
	grid = main.terrain_grid
	await _frames(5)

	var anchor := _pick_tile()
	_check(_tile_is_editable(anchor), "test tile %s is editable owned land" % anchor)
	# Flatten the brushes used below so assertions are exact.
	_flatten(anchor, 9)

	# ------------------------------------------------------------------
	# 1. Toolbar selects the Flat Square tool; the tool arms for painting.
	# ------------------------------------------------------------------
	main.terrain_toolbar._on_tool_button_pressed("flat")
	await _frames(2)
	_check(main.elevation_tool.tool == ElevationTool.Tool.FLAT, "Flat Square tool selected from the toolbar")
	_check(main.elevation_tool.is_active(), "elevation tool is active")
	_check(main.placement_preview.elevation_mode_active, "placement preview shows the elevation brush")
	_check(main.placement_preview.elevation_tool_type == ElevationTool.Tool.FLAT,
			"placement preview mirrors the selected tool")

	# ------------------------------------------------------------------
	# 2. Right click raises and never cancels; left click lowers.
	#    (Headless, the pointer sits at the course corner, so the terrain
	#    effect of the stroke is verified in section 3 on a chosen tile;
	#    here we verify the input wiring and mode state.)
	# ------------------------------------------------------------------
	main._unhandled_input(_mouse_button(true, MOUSE_BUTTON_RIGHT))
	await _frames(1)
	_check(main.elevation_tool.is_raising(), "right click started a raising stroke")
	main._unhandled_input(_mouse_button(false, MOUSE_BUTTON_RIGHT))
	await _frames(1)
	_check(main.elevation_tool.is_active(), "right click release did not cancel the tool")
	_check(main.elevation_tool.elevation_mode == ElevationTool.ElevationMode.NONE,
			"right click release ended the stroke")

	main._unhandled_input(_mouse_button(true, MOUSE_BUTTON_LEFT))
	await _frames(1)
	_check(main.elevation_tool.is_lowering(), "left click started a lowering stroke")
	main._unhandled_input(_mouse_button(false, MOUSE_BUTTON_LEFT))
	await _frames(1)
	_check(main.elevation_tool.is_active(), "left click release did not cancel the tool")

	# ------------------------------------------------------------------
	# 3. Flat Square: right click raises only the lowest vertices one
	#    level; left click lowers only the highest ones. Even ground
	#    steps as one slab. A 3x3 brush is nine tiles / sixteen vertices.
	# ------------------------------------------------------------------
	main._start_elevation_painting(true)
	var flat_area := ElevationTool.brush_vertices(grid, anchor, 3, true)
	_check(flat_area.size() == 16, "3x3 Flat brush selects 16 vertices (%d)" % flat_area.size())
	for i in flat_area.size():
		grid.set_vertex_elevation(flat_area[i], grid.BASE_ELEVATION + i % 3)  # +0/+1/+2 mixture
	var flat_changes: Array = main.elevation_tool.paint_at_tile(anchor, grid, main.entity_layer)
	main.undo_manager.record_elevation_stroke(flat_changes)
	main._stop_elevation_painting()
	await _frames(2)
	for i in flat_area.size():
		var vertex: Vector2i = flat_area[i]
		var expected: int = grid.BASE_ELEVATION + 1 if i % 3 == 0 else grid.BASE_ELEVATION + i % 3
		_check(grid.get_vertex_elevation(vertex) == expected,
				"flat raise: vertex %s %s" % [vertex,
				"is at the lowest level: raised one level" if i % 3 == 0 else "is higher: stays put"])
	_check(grid.get_vertex_elevation(anchor + Vector2i(-2, 0)) == grid.BASE_ELEVATION,
			"flat raise: outside the brush is untouched")

	main._start_elevation_painting(false)
	for vertex in flat_area:
		grid.set_vertex_elevation(vertex, grid.BASE_ELEVATION + 3)
	var flat_lower: Array = main.elevation_tool.paint_at_tile(anchor, grid, main.entity_layer)
	main.undo_manager.record_elevation_stroke(flat_lower)
	main._stop_elevation_painting()
	await _frames(2)
	for vertex in flat_area:
		_check(grid.get_vertex_elevation(vertex) == grid.BASE_ELEVATION + 2,
				"flat lower: vertex %s stays even and steps down one level" % vertex)

	# ------------------------------------------------------------------
	# 4. Gradual Square: right click lifts the middle; repeated clicks build
	#    a one-step pyramid.
	# ------------------------------------------------------------------
	_flatten(anchor, 9)
	main._on_elevation_tool_pressed(ElevationTool.TOOL_GRADUAL)
	await _frames(2)
	_check(main.elevation_tool.tool == ElevationTool.Tool.GRADUAL, "Gradual Square tool selected")
	_check(main.elevation_tool.brush_size >= 2, "gradual brush is at least 2x2")
	# Widen the Elevation Brush to 7x7 the way the tab's stepper does.
	main._on_elevation_brush_size_changed(7)
	await _frames(1)
	_check(main.elevation_tool.brush_size == 7, "elevation brush widened to 7x7")
	main._start_elevation_painting(true)
	for i in range(3):
		var gradual_changes: Array = main.elevation_tool.paint_at_tile(anchor, grid, main.entity_layer)
		main.undo_manager.record_elevation_stroke(gradual_changes)
		main._stop_elevation_painting()
		main._start_elevation_painting(true)
	await _frames(2)
	var middle := ElevationTool.middle_vertices(7, anchor)
	_check(grid.get_vertex_elevation(anchor) == grid.BASE_ELEVATION + 3,
			"gradual raise: middle lifted three levels")
	for vertex in ElevationTool.brush_vertices(grid, anchor, 7, true):
		var expected: int = grid.BASE_ELEVATION + 3 - ElevationTool.distance_to_middle(vertex, 7, anchor)
		_check(grid.get_vertex_elevation(vertex) == expected,
				"gradual raise: vertex %s holds the one-step pyramid (%d)" % [vertex, expected])
	_check(middle.size() == 4, "7x7 gradual brush lifts the anchor tile's four corners")

	# ------------------------------------------------------------------
	# 5. Vertex tool: one vertex moves, nothing else does.
	# ------------------------------------------------------------------
	main._on_elevation_tool_pressed(ElevationTool.TOOL_VERTEX)
	await _frames(2)
	_check(main.elevation_tool.tool == ElevationTool.Tool.VERTEX, "Vertex tool selected")
	_flatten(anchor, 5)
	main._start_elevation_painting(true)
	var vertex_changes: Array = main.elevation_tool.paint_at_vertex(anchor, grid, main.entity_layer)
	main.undo_manager.record_elevation_stroke(vertex_changes)
	main._stop_elevation_painting()
	await _frames(2)
	_check(grid.get_vertex_elevation(anchor) == grid.BASE_ELEVATION + 1,
			"vertex raise: the single vertex lifted one level")
	var neighbours_moved := 0
	for vertex in ElevationTool.brush_vertices(grid, anchor, 5, true):
		if vertex != anchor and grid.get_vertex_elevation(vertex) != grid.BASE_ELEVATION:
			neighbours_moved += 1
	_check(neighbours_moved == 0, "vertex raise: no other vertex moved")

	# ------------------------------------------------------------------
	# 6. Undo restores the elevation changes recorded through main.gd.
	# ------------------------------------------------------------------
	main._perform_undo()
	await _frames(2)
	_check(grid.get_vertex_elevation(anchor) == grid.BASE_ELEVATION,
			"undo restored the vertex tool stroke")

	# ------------------------------------------------------------------
	# 7. Esc cancels the tool.
	# ------------------------------------------------------------------
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	main._unhandled_input(esc)
	await _frames(2)
	_check(not main.elevation_tool.is_active(), "Esc cancelled the elevation tool")
	_check(not main.placement_preview.elevation_mode_active, "preview hidden after cancel")

	print("HARNESS: done, %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
