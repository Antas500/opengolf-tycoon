extends GutTest
## The designated-area overlay projects each staff member's grid-space circle
## into world space so rings render correctly in both course views.

var _previous_staff_manager
var grid: TerrainGrid
var overlay: StaffAreaOverlay

func before_each() -> void:
	_previous_staff_manager = GameManager.staff_manager
	grid = TerrainGrid.new()
	grid.grid_width = 32
	grid.grid_height = 32
	add_child_autofree(grid)
	overlay = StaffAreaOverlay.new()
	overlay.name = "StaffAreaOverlay"
	overlay.set_terrain_grid(grid)
	add_child_autofree(overlay)

func after_each() -> void:
	GameManager.staff_manager = _previous_staff_manager

func test_projected_circle_is_a_closed_ring() -> void:
	var points: PackedVector2Array = overlay._projected_circle(Vector2(10, 10), 4.0)
	assert_eq(points.size(), 32)
	# Every sampled point should be a finite world position.
	for point in points:
		assert_true(is_finite(point.x) and is_finite(point.y))
	# A grid-space circle is not degenerate when projected.
	assert_gt(points[0].distance_to(points[16]), 1.0)

func test_highlight_index_defaults_to_none() -> void:
	assert_eq(overlay.highlight_index, -1)

func test_overlay_survives_a_staff_change_with_no_manager() -> void:
	GameManager.staff_manager = null
	overlay.refresh()
	# No crash and no drawn geometry required: the guard returns early.
	assert_eq(overlay.highlight_index, -1)
