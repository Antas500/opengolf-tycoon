extends GutTest
## Aim guide coverage: the owner's normalized, shot-type-specific flight arc and
## rollout must connect and end at the selected terrain anchor.

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
	assert_almost_eq(float(geometry.apex_height), chord_mid.y - arc[middle].y, 0.01,
		"Apex height matches the stable guide arc profile")

func test_roll_trail_runs_from_carry_to_rest() -> void:
	var preview := _preview()
	var geometry := AimGuide.build_geometry(grid, preview)
	var arc: PackedVector2Array = geometry.arc
	var roll: PackedVector2Array = geometry.roll
	assert_gte(roll.size(), 2, "Roll trail has at least a start and end")
	assert_almost_eq(roll[0].distance_to(arc[arc.size() - 1]), 0.0, 0.5, "Roll starts where the arc lands")
	assert_almost_eq(roll[roll.size() - 1].distance_to(geometry.rest), 0.0, 0.01, "Roll ends at the resting point")
	assert_gt(roll[0].distance_to(roll[roll.size() - 1]), 0.0, "Roll has visible length")

func test_combined_trajectory_connects_arc_roll_and_tile_anchor() -> void:
	var preview := _preview({"target": Vector2(8, 22), "anchor_type": "center"})
	var geometry := AimGuide.build_geometry(grid, preview)
	var trajectory: PackedVector2Array = geometry.trajectory
	assert_eq(trajectory.size(), geometry.arc.size() + geometry.roll.size() - 1,
		"The unified guide joins flight and ground roll without a duplicate carry point")
	assert_almost_eq(trajectory[0].distance_to(geometry.origin), 0.0, 0.01)
	assert_almost_eq(trajectory[trajectory.size() - 1].distance_to(geometry.rest), 0.0, 0.01)
	assert_eq(geometry.anchor_type, "center")

func test_mouse_snaps_to_tile_centres_and_vertices() -> void:
	var centre_point := Vector2(8, 8)
	var centre_snap := grid.snap_world_to_tile_anchor(grid.grid_to_screen_precise(centre_point))
	assert_false(centre_snap.is_empty())
	assert_eq(centre_snap.anchor_type, "center")
	assert_eq(centre_snap.point, centre_point)

	var vertex_grid_point := Vector2(9, 8)
	var vertex_precise_point := vertex_grid_point - Vector2(0.5, 0.5)
	var vertex_snap := grid.snap_world_to_tile_anchor(grid.grid_point_to_screen(vertex_grid_point))
	assert_false(vertex_snap.is_empty())
	assert_eq(vertex_snap.anchor_type, "vertex")
	assert_eq(vertex_snap.point, vertex_precise_point)

func test_mouse_snap_chooses_the_nearest_centre_or_vertex() -> void:
	var centre := grid.grid_to_screen_precise(Vector2(8, 8))
	var vertex := grid.grid_point_to_screen(Vector2(9, 8))
	var pointer := centre.lerp(vertex, 0.8)
	var snapped_anchor := grid.snap_world_to_tile_anchor(pointer)
	assert_eq(snapped_anchor.anchor_type, "vertex")
	assert_eq(snapped_anchor.point, Vector2(8.5, 7.5))

func test_mouse_snap_tracks_rotated_sculpted_tile_geometry() -> void:
	grid.set_vertex_elevation(Vector2i(11, 10), grid.BASE_ELEVATION + 3)
	grid.set_view_orientation(1)
	var vertex_grid_point := Vector2(11, 10)
	var snapped_anchor := grid.snap_world_to_tile_anchor(grid.grid_point_to_screen(vertex_grid_point))
	assert_false(snapped_anchor.is_empty())
	assert_eq(snapped_anchor.anchor_type, "vertex")
	assert_eq(snapped_anchor.point, vertex_grid_point - Vector2(0.5, 0.5))

func test_every_rim_vertex_and_centre_can_be_picked() -> void:
	# The far-edge vertices sit exactly on the map's edge, where the hovered point
	# is "outside" the grid; they must snap just like the near-edge ones.
	var width := grid.grid_width
	var height := grid.grid_height
	for vertex_point in [Vector2(0, 0), Vector2(0, 10), Vector2(10, 0), Vector2(width, 10), Vector2(10, height),
			Vector2(width, height), Vector2(width, 0), Vector2(0, height)]:
		var snapped_anchor := grid.snap_world_to_tile_anchor(grid.grid_point_to_screen(vertex_point))
		assert_false(snapped_anchor.is_empty(), "Rim vertex %s can be picked" % vertex_point)
		assert_eq(snapped_anchor.anchor_type, "vertex")
		assert_eq(snapped_anchor.point, vertex_point - Vector2(0.5, 0.5), "Rim vertex %s snaps to itself" % vertex_point)
	for centre_point in [Vector2(0, 0), Vector2(width - 1, height - 1), Vector2(0, height - 1), Vector2(width - 1, 0)]:
		var snapped_anchor := grid.snap_world_to_tile_anchor(grid.grid_to_screen_precise(centre_point))
		assert_eq(snapped_anchor.anchor_type, "center")
		assert_eq(snapped_anchor.point, centre_point, "Corner tile centre %s snaps to itself" % centre_point)

func test_every_centre_and_vertex_snaps_to_itself_on_every_view() -> void:
	# Hovering exactly on an anchor must always pick that anchor, flat or sculpted,
	# in all four camera orientations.
	for x in range(grid.grid_width + 1):
		for y in range(grid.grid_height + 1):
			if (x + y) % 3 == 0:
				grid.set_vertex_elevation(Vector2i(x, y), grid.BASE_ELEVATION + 1)
			elif (x * 7 + y) % 5 == 0:
				grid.set_vertex_elevation(Vector2i(x, y), grid.BASE_ELEVATION - 1)
	for orientation in range(4):
		grid.set_view_orientation(orientation)
		var misses: Array[String] = []
		for x in range(1, grid.grid_width - 1):
			for y in range(1, grid.grid_height - 1):
				var centre := grid.snap_world_to_tile_anchor(grid.grid_to_screen_precise(Vector2(x, y)))
				if centre.is_empty() or centre.anchor_type != "center" or centre.point != Vector2(x, y):
					misses.append("centre (%d, %d)" % [x, y])
				var vertex := grid.snap_world_to_tile_anchor(grid.grid_point_to_screen(Vector2(x, y)))
				if vertex.is_empty() or vertex.anchor_type != "vertex" or vertex.point != Vector2(x, y) - Vector2(0.5, 0.5):
					misses.append("vertex (%d, %d)" % [x, y])
		assert_eq(misses.size(), 0, "Orientation %d snaps every anchor to itself: %s" % [orientation, str(misses.slice(0, 5))])

func test_pointer_just_past_the_rim_snaps_to_the_rim_anchor_and_further_out_picks_nothing() -> void:
	var width := float(grid.grid_width)
	var near := grid.snap_world_to_tile_anchor(grid.grid_point_to_screen(Vector2(width + 0.3, 10.0)))
	assert_false(near.is_empty(), "The outer half of a rim vertex's cell still belongs to it")
	assert_eq(near.point, Vector2(width - 0.5, 9.5))
	var origin_side := grid.snap_world_to_tile_anchor(grid.grid_point_to_screen(Vector2(-0.3, 10.0)))
	assert_eq(origin_side.point, Vector2(-0.5, 9.5))
	assert_true(grid.snap_world_to_tile_anchor(grid.grid_point_to_screen(Vector2(width + 0.8, 10.0))).is_empty(),
		"Well off the map there is nothing to aim at")
	assert_true(grid.snap_world_to_tile_anchor(grid.grid_point_to_screen(Vector2(-0.8, 10.0))).is_empty())

func test_guide_draws_for_a_rim_anchor_whose_carry_lands_off_the_map() -> void:
	var rim := Vector2(grid.grid_width - 0.5, 20.5)
	var preview := _preview({"origin": Vector2(26, 20), "aim": rim, "carry": Vector2(grid.grid_width + 0.5, 20.5),
		"rest": rim, "target": rim, "anchor_type": "vertex", "roll_path": PackedVector2Array([rim])})
	var geometry := AimGuide.build_geometry(grid, preview)
	assert_false(geometry.is_empty(), "A rim vertex still gets its guide")
	assert_eq(geometry.anchor_type, "vertex")
	assert_almost_eq(geometry.rest.distance_to(grid.grid_to_screen_precise(rim)), 0.0, 0.01, "It ends on the rim vertex")

func test_roll_trail_uses_type_profile_not_simulated_waypoints() -> void:
	var preview := _preview({"roll_path": PackedVector2Array([Vector2(8, 20), Vector2(12, 21), Vector2(8, 22)])})
	var geometry := AimGuide.build_geometry(grid, preview)
	var roll: PackedVector2Array = geometry.roll
	assert_gte(roll.size(), 2)
	assert_almost_eq(roll[0].distance_to(geometry.carry), 0.0, 0.01)
	assert_almost_eq(roll[roll.size() - 1].distance_to(geometry.rest), 0.0, 0.01)
	var expected_guide_carry := Vector2(8, 22 - 14.0 * AimGuide.STANDARD_ROLL_RATIO / (1.0 + AimGuide.STANDARD_ROLL_RATIO))
	assert_almost_eq(geometry.guide_carry_grid.y, expected_guide_carry.y, 0.001,
		"Roll length comes from the standard shot profile, not terrain waypoints")

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

func test_guide_profile_ignores_terrain_and_elevation_variation() -> void:
	var previews: Array[Dictionary] = []
	var flat_geometries: Array[Dictionary] = []
	for shape in range(5):
		var bend := 8.0 if shape == 1 else (-8.0 if shape == 2 else 0.0)
		var shot_preview := _preview({"shape": shape, "shape_bend_deg": bend})
		previews.append(shot_preview)
		flat_geometries.append(AimGuide.build_geometry(grid, shot_preview))

	# Change both the lies under the route and its elevation, including the final
	# anchor, while also substituting a very different deterministic carry path.
	for x in range(7, 10):
		for y in range(12, 22):
			grid._grid[Vector2i(x, y)] = TerrainTypes.Type.DEEP_ROUGH
	for x in range(6, 11):
		grid.set_elevation(Vector2i(x, 14), grid.BASE_ELEVATION + 3)
	grid.set_elevation(Vector2i(8, 22), grid.BASE_ELEVATION + 2)

	var altered_geometries: Array[Dictionary] = []
	for shape in range(5):
		var altered_preview: Dictionary = previews[shape].duplicate(true)
		altered_preview["carry"] = Vector2(12, 18)
		altered_preview["roll_path"] = PackedVector2Array([
			Vector2(12, 18), Vector2(16, 19), Vector2(8, 22)])
		altered_preview["roll_yards"] = 999
		altered_geometries.append(AimGuide.build_geometry(grid, altered_preview))

		var flat: Dictionary = flat_geometries[shape]
		var altered: Dictionary = altered_geometries[shape]
		assert_eq(altered.guide_carry_grid, flat.guide_carry_grid,
			"Shot %d keeps the same nominal carry point" % shape)
		assert_almost_eq(float(altered.apex_height), float(flat.apex_height), 0.01,
			"Shot %d keeps its arc height across lies and elevations" % shape)
		assert_almost_eq(float(altered.guide_roll_distance_tiles),
			float(flat.guide_roll_distance_tiles), 0.001,
			"Shot %d keeps its rollout distance across lies and elevations" % shape)
		assert_almost_eq(altered.roll[0].distance_to(altered.roll[altered.roll.size() - 1]),
			flat.roll[0].distance_to(flat.roll[flat.roll.size() - 1]), 0.01,
			"Shot %d keeps the same screen-space rollout length" % shape)

	var straight: Dictionary = flat_geometries[0]
	var fade: Dictionary = flat_geometries[1]
	var draw: Dictionary = flat_geometries[2]
	var backspin: Dictionary = flat_geometries[3]
	var punch: Dictionary = flat_geometries[4]
	assert_almost_eq(float(fade.guide_roll_distance_tiles), float(straight.guide_roll_distance_tiles), 0.001)
	assert_almost_eq(float(draw.guide_roll_distance_tiles), float(straight.guide_roll_distance_tiles), 0.001)
	assert_gt(float(punch.guide_roll_distance_tiles), float(straight.guide_roll_distance_tiles),
		"Punch keeps its longer-roll profile")
	assert_gt(float(backspin.apex_height), float(straight.apex_height),
		"Backspin keeps its higher arc profile")
	assert_lt(float(punch.apex_height), float(straight.apex_height),
		"Punch keeps its flatter arc profile")
	assert_true(backspin.guide_backspin, "Backspin keeps its reverse-roll profile")

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
