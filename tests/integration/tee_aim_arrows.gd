extends SceneTree
## The aiming arrows painted on tee tiles, in the real game: a generated course's
## tees all aim at their hole's cup — straight holes with a straight arrow, doglegs
## with a curved one — and every marker (shaft, head and the two red tee markers)
## stays inside the grass of its own tile, including tee tiles on sculpted ground
## whose projected outline leans and stretches.
##
## Uses dynamic loads because a `-s` script compiles before autoloads exist.

var main: Node
var grid
var overlay
var gm
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	print("TEE_AIM_ARROWS_FAIL: ", message)

func run() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._on_main_menu_quick_start("Tee Aim Check", 0)
	for i in range(8): await process_frame

	gm = root.get_node("GameManager")
	grid = main.terrain_grid
	overlay = grid.get_node_or_null("TeeAimOverlay")
	check(overlay != null, "TerrainGrid builds a TeeAimOverlay")
	if overlay == null:
		_finish()
		return

	overlay.rebuild()
	var curved := 0
	var tees: Array = grid.get_tee_box_tiles()
	check(not tees.is_empty(), "The generated course has tee boxes")
	check(overlay.aimed_tees().size() == tees.size(),
			"Every tee box on an open hole carries an arrow: %d arrows for %d tees"
			% [overlay.aimed_tees().size(), tees.size()])

	for tee in overlay.aimed_tees():
		var hole = _hole_of_tee(tee)
		check(hole != null, "The arrow on tee %s belongs to a hole" % tee)
		if hole == null:
			continue
		var route: Array = overlay.route_for(tee)
		check(route[0] == tee, "The arrow on %s starts on its own tile" % tee)
		check(route[route.size() - 1] == hole.hole_position,
				"The arrow on %s aims at hole %d's cup" % [tee, hole.hole_number])
		if route.size() == 3:
			curved += 1
		_assert_marker_inside_tile(tee)

	check(curved > 0, "At least one dogleg hole on the generated course gets a curved arrow")
	check(curved < tees.size(), "Straight holes keep the straight arrow")

	# The same tile with its corner raised: the marker has to follow the ground.
	var test_tee: Vector2i = tees[0]
	grid.set_vertex_elevation(Vector2i(test_tee), 4)
	grid.set_vertex_elevation(Vector2i(test_tee.x + 1, test_tee.y), -3)
	overlay.rebuild()
	_assert_marker_inside_tile(test_tee)

	_finish()

func _finish() -> void:
	if failures == 0:
		print("TEE_AIM_ARROWS_PASS: every tee tile aims at its cup and keeps its marker on its own tile")
	else:
		print("TEE_AIM_ARROWS_FAILED: ", failures, " problems")
	quit()

func _hole_of_tee(tee: Vector2i):
	for hole in gm.current_course.holes:
		if hole.tee_position == tee or hole.tee_positions.values().has(tee):
			return hole
	return null

func _assert_marker_inside_tile(tee: Vector2i) -> void:
	var layout: Dictionary = overlay.marker_layout(tee)
	check(not layout.is_empty(), "Tee %s has marker geometry" % tee)
	if layout.is_empty():
		return
	var polygon := PackedVector2Array()
	for corner in grid.tile_polygon(tee):
		polygon.append(overlay.to_local(corner))
	if layout.floored:
		# Steep ground: the marker keeps a readable size instead of shrinking to
		# nothing, so all that is promised is that it stays on the tile.
		_assert_marker_on_tile(layout, polygon, tee)
		return
	for point in layout.shaft:
		check(Geometry2D.is_point_in_polygon(point, polygon),
				"Shaft point %s of tee %s stays in its tile" % [point, tee])
	for point in layout.head:
		check(Geometry2D.is_point_in_polygon(point, polygon),
				"Arrow head point %s of tee %s stays in its tile" % [point, tee])
	for ball in layout.balls:
		check(Geometry2D.is_point_in_polygon(ball, polygon),
				"Red marker of tee %s stays in its tile" % tee)

func _assert_marker_on_tile(layout: Dictionary, polygon: PackedVector2Array, tee: Vector2i) -> void:
	var box := Rect2(polygon[0], Vector2.ZERO)
	for corner in polygon:
		box = box.expand(corner)
	for point in layout.shaft:
		check(box.has_point(point), "Shaft point %s of tee %s stays on its tile" % [point, tee])
	for point in layout.head:
		check(box.has_point(point), "Head point %s of tee %s stays on its tile" % [point, tee])
	for ball in layout.balls:
		check(box.has_point(ball), "Red marker of tee %s stays on its tile" % tee)
