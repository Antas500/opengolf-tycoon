extends GutTest
## GridProjection - isometric layout and the four view orientations.
##
## The projection is the single conversion path for terrain, overlays, entities
## and mouse picking, so these tests pin down the invariants the rest of the
## game relies on: exact round-tripping, the diamond tile shape, a world bounds
## that does not move when the course is rotated, and a top-down mode that
## reproduces the legacy square-tile mapping exactly.

const TILE := Vector2(64, 32)
const GRID := Vector2i(128, 128)

var proj: GridProjection

func before_each() -> void:
	proj = GridProjection.new(GRID, TILE, true, 0)

# =============================================================================
# ROUND TRIP
# =============================================================================

func test_unproject_inverts_project_for_every_orientation() -> void:
	for orientation in range(GridProjection.ORIENTATION_COUNT):
		proj.set_orientation(orientation)
		for x in range(0, GRID.x, 17):
			for y in range(0, GRID.y, 13):
				for offset in [Vector2.ZERO, Vector2(0.5, 0.5), Vector2(0.25, 0.75)]:
					var point := Vector2(x, y) + offset
					var back := proj.unproject(proj.project(point))
					assert_almost_eq(back.x, point.x, 0.0001,
							"orientation %d x at %s" % [orientation, point])
					assert_almost_eq(back.y, point.y, 0.0001,
							"orientation %d y at %s" % [orientation, point])

func test_round_trip_also_holds_in_top_down_mode() -> void:
	proj.set_isometric(false)
	for orientation in range(GridProjection.ORIENTATION_COUNT):
		proj.set_orientation(orientation)
		var point := Vector2(31.5, 77.25)
		var back := proj.unproject(proj.project(point))
		assert_almost_eq(back.x, point.x, 0.0001)
		assert_almost_eq(back.y, point.y, 0.0001)

# =============================================================================
# TILE SHAPE
# =============================================================================

func test_isometric_cell_is_a_two_to_one_diamond() -> void:
	var poly := proj.cell_polygon(Vector2i(40, 40))
	assert_eq(poly.size(), 4)
	var rect := proj.cell_world_rect(Vector2i(40, 40))
	assert_almost_eq(rect.size.x, TILE.x, 0.0001, "diamond spans one tile width")
	assert_almost_eq(rect.size.y, TILE.y, 0.0001, "diamond spans one tile height (2:1)")
	# The centre is equidistant from all four vertices - the definition of the
	# regular diamond the isometric look depends on.
	var center := proj.cell_center(Vector2i(40, 40))
	var first := center.distance_to(poly[0])
	for vertex in poly:
		assert_almost_eq(center.distance_to(vertex), first, 0.0001)

func test_top_down_cell_is_a_square() -> void:
	proj.set_isometric(false)
	var rect := proj.cell_world_rect(Vector2i(40, 40))
	assert_almost_eq(rect.size.x, TILE.x, 0.0001)
	assert_almost_eq(rect.size.y, TILE.y, 0.0001)
	var poly := proj.cell_polygon(Vector2i(40, 40))
	# Axis-aligned: two distinct x values and two distinct y values.
	var xs := {}
	var ys := {}
	for vertex in poly:
		xs[roundi(vertex.x)] = true
		ys[roundi(vertex.y)] = true
	assert_eq(xs.size(), 2)
	assert_eq(ys.size(), 2)

# =============================================================================
# ROTATION
# =============================================================================

func test_rotation_cycles_through_four_orientations() -> void:
	assert_eq(proj.orientation, 0)
	proj.rotate_cw()
	assert_eq(proj.orientation, 1)
	proj.rotate_cw()
	assert_eq(proj.orientation, 2)
	proj.rotate_cw()
	assert_eq(proj.orientation, 3)
	proj.rotate_cw()
	assert_eq(proj.orientation, 0, "wraps back to the start")

func test_rotate_ccw_wraps_backwards() -> void:
	proj.rotate_ccw()
	assert_eq(proj.orientation, 3)
	proj.rotate_cw()
	assert_eq(proj.orientation, 0)

func test_four_cw_rotations_restore_the_original_projection() -> void:
	var samples: Array[Vector2] = [
		Vector2.ZERO, Vector2(128, 0), Vector2(64, 64), Vector2(12.5, 90.25),
	]
	var before: Array[Vector2] = []
	for sample in samples:
		before.append(proj.project(sample))
	for i in range(4):
		proj.rotate_cw()
	for i in range(samples.size()):
		var after := proj.project(samples[i])
		assert_almost_eq(after.x, before[i].x, 0.0001)
		assert_almost_eq(after.y, before[i].y, 0.0001)

func test_each_orientation_places_the_grid_corners_differently() -> void:
	# Rotating must actually move the course around, not leave it identical.
	var seen := {}
	for orientation in range(GridProjection.ORIENTATION_COUNT):
		proj.set_orientation(orientation)
		var corner := proj.cell_corner(Vector2i.ZERO)
		seen["%d,%d" % [roundi(corner.x), roundi(corner.y)]] = true
	assert_eq(seen.size(), 4, "grid origin lands on a different diamond vertex each quarter turn")

# =============================================================================
# WORLD BOUNDS
# =============================================================================

func test_world_bounds_do_not_move_when_rotating() -> void:
	# Camera limits, the minimap and the land boundary are all sized from this
	# rectangle, so a rotation must not shift or resize it.
	var first := proj.world_bounds()
	for orientation in range(GridProjection.ORIENTATION_COUNT):
		proj.set_orientation(orientation)
		var bounds := proj.world_bounds()
		assert_almost_eq(bounds.position.x, first.position.x, 0.0001)
		assert_almost_eq(bounds.position.y, first.position.y, 0.0001)
		assert_almost_eq(bounds.size.x, first.size.x, 0.0001)
		assert_almost_eq(bounds.size.y, first.size.y, 0.0001)

func test_isometric_bounds_match_the_top_down_footprint() -> void:
	var iso_size := proj.world_bounds().size
	proj.set_isometric(false)
	var flat_size := proj.world_bounds().size
	assert_almost_eq(iso_size.x, flat_size.x, 0.0001)
	assert_almost_eq(iso_size.y, flat_size.y, 0.0001)

# =============================================================================
# TOP-DOWN BACK COMPATIBILITY
# =============================================================================

func test_top_down_orientation_zero_reproduces_the_legacy_square_mapping() -> void:
	# The pre-isometric code mapped grid point (x, y) to (x * tile_width,
	# y * tile_height). Top-down mode must still do exactly that so existing
	# saves, screenshots and expectations keep lining up.
	proj.set_isometric(false)
	proj.set_orientation(0)
	for point in [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Vector2(127, 127), Vector2(64, 32)]:
		var expected := Vector2(point.x * TILE.x, point.y * TILE.y)
		var got := proj.project(point)
		assert_almost_eq(got.x, expected.x, 0.0001, "x at %s" % point)
		assert_almost_eq(got.y, expected.y, 0.0001, "y at %s" % point)

# =============================================================================
# PICKING
# =============================================================================

func test_world_to_cell_finds_the_tile_under_a_point() -> void:
	for orientation in range(GridProjection.ORIENTATION_COUNT):
		proj.set_orientation(orientation)
		for cell in [Vector2i(0, 0), Vector2i(5, 9), Vector2i(127, 127)]:
			var center := proj.cell_center(cell)
			assert_eq(proj.world_to_cell(center), cell,
					"centre of %s at orientation %d" % [cell, orientation])

func test_cell_centre_is_inside_its_own_tile_polygon() -> void:
	for orientation in range(GridProjection.ORIENTATION_COUNT):
		proj.set_orientation(orientation)
		var cell := Vector2i(33, 71)
		var center := proj.cell_center(cell)
		assert_true(Geometry2D.is_point_in_polygon(center, proj.cell_polygon(cell)),
				"orientation %d" % orientation)

func test_a_neighbouring_cell_centre_is_not_inside_this_tile() -> void:
	# Guards against a picking regression where every click resolves to one tile.
	var cell := Vector2i(33, 71)
	var poly := proj.cell_polygon(cell)
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbour := proj.cell_center(cell + offset)
		assert_false(Geometry2D.is_point_in_polygon(neighbour, poly),
				"neighbour %s leaked into %s" % [cell + offset, cell])

# =============================================================================
# SHADER PLUMBING
# =============================================================================

func test_affine_terms_reconstruct_the_projection() -> void:
	# course_surface.gdshader and elevation_lighting.gdshader invert the view
	# from these three vectors, so they have to reproduce project() exactly.
	for orientation in range(GridProjection.ORIENTATION_COUNT):
		proj.set_orientation(orientation)
		var origin := proj.grid_origin()
		var axis_x := proj.axis_x()
		var axis_y := proj.axis_y()
		for point in [Vector2.ZERO, Vector2(3, 7), Vector2(128, 128), Vector2(64.5, 20.25)]:
			var rebuilt := origin + axis_x * point.x + axis_y * point.y
			var expected := proj.project(point)
			assert_almost_eq(rebuilt.x, expected.x, 0.0001, "orientation %d at %s" % [orientation, point])
			assert_almost_eq(rebuilt.y, expected.y, 0.0001, "orientation %d at %s" % [orientation, point])

func test_axes_are_linearly_independent() -> void:
	# A degenerate (parallel) pair would make the shader's determinant zero and
	# blank the terrain.
	for orientation in range(GridProjection.ORIENTATION_COUNT):
		proj.set_orientation(orientation)
		var det: float = proj.axis_x().x * proj.axis_y().y - proj.axis_y().x * proj.axis_x().y
		assert_gt(absf(det), 1.0, "orientation %d" % orientation)
