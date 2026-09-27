extends Node
## Headless smoke test for the three elevation selector tools (Vertex, Flat
## Square, Gradual Square) through the real main.gd input path: the toolbar
## selects the tool, right click raises, left click lowers, right click never
## cancels the tool, and Esc still does.
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

func _mouse_button(pressed: bool, button_index: int) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	return event

## An owned, unoccupied vertex in the middle of the quick-start course.
func _pick_vertex() -> Vector2i:
	for radius in range(0, 20):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var vertex := Vector2i(64, 64) + Vector2i(dx, dy)
				if grid.is_vertex_editable(vertex, main.entity_layer, false):
					return vertex
	return Vector2i(64, 64)

func _run() -> void:
	await _frames(10)
	print("HARNESS: quick-starting new game")
	main._on_main_menu_quick_start("Elevation Harness", 0)
	await _frames(60)
	grid = main.terrain_grid
	await _frames(5)

	var vertex := _pick_vertex()
	_check(grid.is_vertex_editable(vertex, main.entity_layer, false),
			"test vertex %s is editable owned land" % vertex)
	# Flatten the 9x9 area around the test vertex so assertions are exact.
	for offset in ElevationTool.square_offsets(9, false):
		var candidate: Vector2i = vertex + offset
		if grid.is_valid_vertex(candidate):
			grid.set_vertex_elevation(candidate, 0)

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
	#    effect of the stroke is verified in section 3 on a chosen vertex;
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
	# 3. Flat Square: right click evens the square up, then raises it;
	#    left click evens it down, then lowers it.
	# ------------------------------------------------------------------
	main._start_elevation_painting(true)
	for offset in ElevationTool.square_offsets(3, false):
		var candidate: Vector2i = vertex + offset
		if grid.is_valid_vertex(candidate):
			grid.set_vertex_elevation(candidate, (offset.x + 2) % 3)  # 0,1,2 rings
	var flat_changes: Array = main.elevation_tool.paint_vertices(vertex, grid, main.entity_layer)
	main.undo_manager.record_elevation_stroke(flat_changes)
	main._stop_elevation_painting()
	await _frames(2)
	for offset in ElevationTool.square_offsets(3, false):
		var candidate: Vector2i = vertex + offset
		if grid.is_valid_vertex(candidate):
			_check(grid.get_vertex_elevation(candidate) == 3,
					"flat raise: vertex %s levelled to 2 then raised to 3" % candidate)
	_check(grid.get_vertex_elevation(vertex + Vector2i(3, 0)) == 0,
			"flat raise: outside the square is untouched")

	main._start_elevation_painting(false)
	for offset in ElevationTool.square_offsets(3, false):
		var candidate: Vector2i = vertex + offset
		if grid.is_valid_vertex(candidate):
			grid.set_vertex_elevation(candidate, 3)
	var flat_lower: Array = main.elevation_tool.paint_vertices(vertex, grid, main.entity_layer)
	main.undo_manager.record_elevation_stroke(flat_lower)
	main._stop_elevation_painting()
	await _frames(2)
	for offset in ElevationTool.square_offsets(3, false):
		var candidate: Vector2i = vertex + offset
		if grid.is_valid_vertex(candidate):
			_check(grid.get_vertex_elevation(candidate) == 2,
					"flat lower: vertex %s stays even and steps down to 2" % candidate)

	# ------------------------------------------------------------------
	# 4. Gradual Square: right click lifts the middle; repeated clicks build
	#    a one-step pyramid.
	# ------------------------------------------------------------------
	for offset in ElevationTool.square_offsets(9, false):
		var candidate: Vector2i = vertex + offset
		if grid.is_valid_vertex(candidate):
			grid.set_vertex_elevation(candidate, 0)
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
		var gradual_changes: Array = main.elevation_tool.paint_vertices(vertex, grid, main.entity_layer)
		main.undo_manager.record_elevation_stroke(gradual_changes)
		main._stop_elevation_painting()
		main._start_elevation_painting(true)
	await _frames(2)
	_check(grid.get_vertex_elevation(vertex) == 3, "gradual raise: middle lifted to 3")
	for offset in ElevationTool.square_offsets(7, false):
		var candidate: Vector2i = vertex + offset
		if grid.is_valid_vertex(candidate):
			var expected: int = 3 - ElevationTool.distance_to_middle(candidate, 7, vertex)
			_check(grid.get_vertex_elevation(candidate) == expected,
					"gradual raise: vertex %s holds the one-step pyramid (%d)" % [candidate, expected])

	# ------------------------------------------------------------------
	# 5. Vertex tool: one vertex moves, nothing else does.
	# ------------------------------------------------------------------
	main._on_elevation_tool_pressed(ElevationTool.TOOL_VERTEX)
	await _frames(2)
	_check(main.elevation_tool.tool == ElevationTool.Tool.VERTEX, "Vertex tool selected")
	for offset in ElevationTool.square_offsets(5, false):
		var candidate: Vector2i = vertex + offset
		if grid.is_valid_vertex(candidate):
			grid.set_vertex_elevation(candidate, 0)
	main._start_elevation_painting(true)
	var vertex_changes: Array = main.elevation_tool.paint_vertices(vertex, grid, main.entity_layer)
	main.undo_manager.record_elevation_stroke(vertex_changes)
	main._stop_elevation_painting()
	await _frames(2)
	_check(grid.get_vertex_elevation(vertex) == 1, "vertex raise: the single vertex lifted to 1")
	var neighbours_moved := 0
	for offset in ElevationTool.square_offsets(5, false):
		var candidate: Vector2i = vertex + offset
		if grid.is_valid_vertex(candidate) and candidate != vertex:
			if grid.get_vertex_elevation(candidate) != 0:
				neighbours_moved += 1
	_check(neighbours_moved == 0, "vertex raise: no other vertex moved")

	# ------------------------------------------------------------------
	# 6. Undo restores the elevation changes recorded through main.gd.
	# ------------------------------------------------------------------
	main._perform_undo()
	await _frames(2)
	_check(grid.get_vertex_elevation(vertex) == 0, "undo restored the vertex tool stroke")

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
