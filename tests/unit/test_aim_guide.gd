extends GutTest
## Aim guide coverage: the owner's aim must show the intended flight arc and the
## roll that follows it, in the same screen space the ball animation uses.

var grid: TerrainGrid

func before_each() -> void:
	grid = TerrainGrid.new()
	grid.grid_width = 32
	grid.grid_height = 32
	add_child_autofree(grid)
	await get_tree().process_frame
	for x in range(32):
		for y in range(32):
			grid._grid[Vector2i(x, y)] = TerrainTypes.Type.FAIRWAY

func _preview(overrides: Dictionary = {}) -> Dictionary:
	var preview := {
		"origin": Vector2(8, 8),
		"aim": Vector2(8, 20),
		"carry": Vector2(8, 20),
		"rest": Vector2(8, 22),
		"roll_path": PackedVector2Array([Vector2(8, 20), Vector2(8, 21), Vector2(8, 22)]),
		"shape_bend_deg": 0.0,
		"arc_scale": 1.0,
	}
	preview.merge(overrides, true)
	return preview

func test_arc_rises_over_the_ground_and_lands_on_carry() -> void:
	var preview := _preview()
	var geometry := AimGuide.build_geometry(grid, preview)
	assert_false(geometry.is_empty(), "Geometry builds for a valid preview")

	var arc: PackedVector2Array = geometry.arc
	var ground: PackedVector2Array = geometry.ground_track
	var origin_screen: Vector2 = geometry.origin
	var carry_screen: Vector2 = geometry.carry
	assert_almost_eq(arc[0].distance_to(origin_screen), 0.0, 0.01, "Arc starts at the ball")
	assert_almost_eq(arc[arc.size() - 1].distance_to(carry_screen), 0.0, 0.01, "Arc ends on the carry point")
	assert_almost_eq(ground[0].distance_to(origin_screen), 0.0, 0.01)
	assert_almost_eq(ground[ground.size() - 1].distance_to(carry_screen), 0.0, 0.01)

	# The apex sits above the straight line between the endpoints (screen y is down),
	# and the arc rides above its own ground track.
	var middle := int(arc.size() / 2.0)
	var chord_mid := origin_screen.lerp(carry_screen, 0.5)
	assert_lt(arc[middle].y, chord_mid.y, "Arc rises above the aim line")
	assert_lt(arc[middle].y, ground[middle].y, "Arc floats above the ground track")
	assert_almost_eq(float(geometry.apex_height), chord_mid.y - arc[middle].y, 0.01, "Apex height matches Ball's arc")

func test_roll_trail_runs_from_carry_to_rest() -> void:
	var preview := _preview()
	var geometry := AimGuide.build_geometry(grid, preview)
	var arc: PackedVector2Array = geometry.arc
	var roll: PackedVector2Array = geometry.roll
	assert_gte(roll.size(), 2, "Roll trail has at least a start and end")
	assert_almost_eq(roll[0].distance_to(arc[arc.size() - 1]), 0.0, 0.5, "Roll starts where the arc lands")
	assert_almost_eq(roll[roll.size() - 1].distance_to(geometry.rest), 0.0, 0.01, "Roll ends at the resting point")
	assert_gt(roll[0].distance_to(roll[roll.size() - 1]), 0.0, "Roll has visible length")

func test_roll_trail_without_walk_uses_carry_to_rest() -> void:
	var preview := _preview({"roll_path": PackedVector2Array([Vector2(8, 20), Vector2(8, 22)])})
	var geometry := AimGuide.build_geometry(grid, preview)
	var roll: PackedVector2Array = geometry.roll
	assert_eq(roll.size(), 2)
	assert_almost_eq(roll[0].distance_to(geometry.carry), 0.0, 0.01)
	assert_almost_eq(roll[1].distance_to(geometry.rest), 0.0, 0.01)

func test_fade_and_draw_bend_to_opposite_sides() -> void:
	var fade := AimGuide.build_geometry(grid, _preview({"shape_bend_deg": 8.0}))
	var draw := AimGuide.build_geometry(grid, _preview({"shape_bend_deg": -8.0}))
	var straight := AimGuide.build_geometry(grid, _preview())
	var index: int = straight.arc.size() / 2
	var chord_mid: Vector2 = straight.arc[index]
	assert_gt(absf(fade.arc[index].x - chord_mid.x), 0.5, "Fade bends off the straight line")
	assert_gt(absf(draw.arc[index].x - chord_mid.x), 0.5, "Draw bends off the straight line")
	assert_lt((fade.arc[index].x - chord_mid.x) * (draw.arc[index].x - chord_mid.x), 0.0,
		"Fade and draw bend in opposite directions")

func test_backspin_and_punch_scale_the_arc() -> void:
	var flat := AimGuide.build_geometry(grid, _preview())
	var punch := AimGuide.build_geometry(grid, _preview({"arc_scale": 0.3}))
	var backspin := AimGuide.build_geometry(grid, _preview({"arc_scale": 1.4}))
	var index: int = flat.arc.size() / 2
	assert_gt(punch.arc[index].y, flat.arc[index].y, "Punch keeps a flat, low arc")
	assert_lt(backspin.arc[index].y, flat.arc[index].y, "Backspin launches the arc higher")

func test_ground_track_follows_elevation() -> void:
	var flat := AimGuide.build_geometry(grid, _preview())
	for x in range(6, 11):
		grid.set_elevation(Vector2i(x, 14), 3)
	var hilly := AimGuide.build_geometry(grid, _preview())
	var index: int = hilly.ground_track.size() / 2
	assert_lt(hilly.ground_track[index].y, flat.ground_track[index].y,
		"Ground track rides over raised terrain")

func test_invalid_preview_or_grid_returns_no_geometry() -> void:
	assert_true(AimGuide.build_geometry(grid, {}).is_empty(), "Empty preview draws nothing")
	assert_true(AimGuide.build_geometry(null, _preview()).is_empty(), "Missing grid draws nothing")
	assert_true(AimGuide.build_geometry(grid, _preview({"origin": Vector2(400, 400)})).is_empty(),
		"Off-map origin draws nothing")

func test_show_and_clear_hold_the_preview() -> void:
	var guide: AimGuide = add_child_autofree(AimGuide.new())
	assert_true(guide.preview.is_empty(), "Guide starts hidden")
	guide.show_preview(_preview())
	assert_false(guide.preview.is_empty(), "Guide holds the preview it was given")
	guide.show_preview({})
	assert_true(guide.preview.is_empty(), "Empty payload clears the guide")
	guide.show_preview(_preview())
	guide.clear()
	assert_true(guide.preview.is_empty(), "clear() removes the guide")
