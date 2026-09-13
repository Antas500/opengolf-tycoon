extends Node2D
class_name LandBoundaryOverlay
## LandBoundaryOverlay - Draws property lines around owned land
##
## Shows a visible border between owned and unowned parcels, and
## applies a subtle tint to unowned areas so players know where
## they can and cannot build.

var terrain_grid: TerrainGrid

## Visual settings
const BOUNDARY_COLOR = Color(0.9, 0.6, 0.2, 0.8)  # Orange/gold property line
const BOUNDARY_WIDTH: float = 2.5
const UNOWNED_TINT = Color(0.4, 0.3, 0.3, 0.15)  # Subtle dark tint on unowned land

## Cache the boundary edges to avoid recalculating every frame
var _boundary_edges: Array = []  # Array of {start: Vector2, end: Vector2}
var _needs_recalculate: bool = true

func initialize(grid: TerrainGrid) -> void:
	terrain_grid = grid
	z_index = 5  # Above terrain but below UI elements

	# Defer signal connection - land_manager may not exist yet
	call_deferred("_connect_land_signals")

	_needs_recalculate = true
	queue_redraw()

func _connect_land_signals() -> void:
	# Connect to land manager signals (deferred to ensure manager exists)
	if GameManager.land_manager:
		if not GameManager.land_manager.land_purchased.is_connected(_on_land_changed):
			GameManager.land_manager.land_purchased.connect(_on_land_changed)
		if not GameManager.land_manager.land_boundary_changed.is_connected(_on_land_boundary_changed):
			GameManager.land_manager.land_boundary_changed.connect(_on_land_boundary_changed)

func _on_land_boundary_changed() -> void:
	_needs_recalculate = true
	queue_redraw()

func _on_land_changed(_parcel = null) -> void:
	_needs_recalculate = true
	queue_redraw()

func _draw() -> void:
	if not terrain_grid:
		return
	if not GameManager.land_manager:
		return

	# Recalculate boundary edges if needed
	if _needs_recalculate:
		_calculate_boundary_edges()
		_needs_recalculate = false

	var lm = GameManager.land_manager
	var visible_rect = terrain_grid.get_visible_world_rect()

	# Draw tint on unowned tiles
	for x in range(terrain_grid.grid_width):
		for y in range(terrain_grid.grid_height):
			var pos = Vector2i(x, y)
			if not lm.is_tile_owned(pos):
				if not visible_rect.has_point(terrain_grid.grid_to_screen_center(pos)):
					continue
				# Projected tile outline, so the tint is a diamond when isometric.
				draw_colored_polygon(
						OverlayGeometry.tile_polygon(terrain_grid, self, pos), UNOWNED_TINT)

	# Draw property line borders.
	for edge in _boundary_edges:
		var start_world = terrain_grid.grid_point_to_screen(
				Vector2(edge.start_tile) + edge.start_offset)
		var end_world = terrain_grid.grid_point_to_screen(
				Vector2(edge.end_tile) + edge.end_offset)
		draw_line(to_local(start_world), to_local(end_world), BOUNDARY_COLOR,
				BOUNDARY_WIDTH, true)

func _calculate_boundary_edges() -> void:
	"""Calculate all boundary edges between owned and unowned tiles."""
	_boundary_edges.clear()

	if not GameManager.land_manager:
		return

	var lm = GameManager.land_manager

	# Check every tile for boundary edges
	for x in range(terrain_grid.grid_width):
		for y in range(terrain_grid.grid_height):
			var pos = Vector2i(x, y)
			var is_owned = lm.is_tile_owned(pos)

			if not is_owned:
				continue  # Only draw borders from owned side

			# Check each neighbor
			# Right neighbor
			var right = Vector2i(x + 1, y)
			if not lm.is_tile_owned(right):
				_boundary_edges.append({
					"start_tile": pos,
					"start_offset": Vector2(1, 0),
					"end_tile": pos,
					"end_offset": Vector2(1, 1)
				})

			# Bottom neighbor
			var bottom = Vector2i(x, y + 1)
			if not lm.is_tile_owned(bottom):
				_boundary_edges.append({
					"start_tile": pos,
					"start_offset": Vector2(0, 1),
					"end_tile": pos,
					"end_offset": Vector2(1, 1)
				})

			# Left neighbor
			var left = Vector2i(x - 1, y)
			if not lm.is_tile_owned(left):
				_boundary_edges.append({
					"start_tile": pos,
					"start_offset": Vector2(0, 0),
					"end_tile": pos,
					"end_offset": Vector2(0, 1)
				})

			# Top neighbor
			var top = Vector2i(x, y - 1)
			if not lm.is_tile_owned(top):
				_boundary_edges.append({
					"start_tile": pos,
					"start_offset": Vector2(0, 0),
					"end_tile": pos,
					"end_offset": Vector2(1, 0)
				})
