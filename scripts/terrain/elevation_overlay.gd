extends Node2D
class_name ElevationOverlay
## ElevationOverlay - Active-mode elevation tool feedback
##
## Heights live on the grid vertices, so this overlay shows the lattice the player is actually editing:

var terrain_grid: TerrainGrid
var _elevation_active: bool = false  # More prominent when elevation tool is selected
var _needs_redraw: bool = true       # Kept for callers that flag "data changed"

## Alpha levels
const CONTOUR_ALPHA_MINOR: float = 0.2  # Thin contour lines (every level)
const CONTOUR_ALPHA_MAJOR: float = 0.45 # Thick contour lines (every 2 levels)
const VERTEX_ALPHA: float = 0.8
const LATTICE_ALPHA: float = 0.16

## Vertex markers are drawn as a fraction of a tile so they follow the projection.
const MARKER_SCALE: float = 0.13
const LATTICE_ZOOM: float = 1.1   # Show sea-level corners past this zoom
const LABEL_ZOOM: float = 0.55    # Show height numbers past this zoom

func initialize(grid: TerrainGrid) -> void:
	terrain_grid = grid
	z_index = 4  # Above terrain overlays when elevation tool active

	# Vertex edits are the authoritative "the ground moved" signal.
	if terrain_grid.has_signal("vertex_elevation_changed"):
		terrain_grid.vertex_elevation_changed.connect(_on_vertex_elevation_changed)
	if terrain_grid.has_signal("elevation_changed"):
		terrain_grid.elevation_changed.connect(_on_elevation_changed)

	_needs_redraw = true

func set_elevation_mode_active(active: bool) -> void:
	_elevation_active = active
	invalidate()

## Flag the overlay as stale and ask for a redraw (bulk edits, save load, tools).
func invalidate() -> void:
	_needs_redraw = true
	queue_redraw()

func _on_vertex_elevation_changed(_vertex: Vector2i, _old: int, _new: int) -> void:
	invalidate()

func _on_elevation_changed(_pos: Vector2i, _old: int, _new: int) -> void:
	invalidate()

func _camera_zoom() -> float:
	var viewport := get_viewport()
	if viewport == null:
		return 1.0
	var camera := viewport.get_camera_2d()
	return camera.zoom.x if camera else 1.0

func _draw() -> void:
	if not terrain_grid or not _elevation_active:
		return
	_needs_redraw = false

	var visible_rect: Rect2 = terrain_grid.get_visible_world_rect()
	var tile_range: Array[Vector2i] = terrain_grid.get_visible_tile_range()
	var zoom: float = _camera_zoom()
	var show_labels: bool = zoom >= LABEL_ZOOM
	var show_lattice: bool = zoom >= 0.35

	if show_lattice:
		_draw_3d_lattice(tile_range, visible_rect)
	_draw_vertex_markers(visible_rect, zoom, show_labels, zoom >= LATTICE_ZOOM)
	_draw_contours(visible_rect)
	_draw_slope_arrows(tile_range, visible_rect, zoom)

## 3D wireframe lattice connecting adjacent vertices across slopes
func _draw_3d_lattice(tile_range: Array[Vector2i], visible_rect: Rect2) -> void:
	var x_start: int = maxi(tile_range[0].x, 0)
	var x_end: int = mini(tile_range[1].x + 1, terrain_grid.grid_width)
	var y_start: int = maxi(tile_range[0].y, 0)
	var y_end: int = mini(tile_range[1].y + 1, terrain_grid.grid_height)

	for x in range(x_start, x_end + 1):
		for y in range(y_start, y_end + 1):
			var v0 := Vector2i(x, y)
			var s0 := terrain_grid.grid_point_to_screen(Vector2(v0))
			var p0 := to_local(s0)
			var h0 := terrain_grid.get_vertex_elevation(v0)

			# Segment to (x + 1, y)
			if x < x_end:
				var v1 := Vector2i(x + 1, y)
				var s1 := terrain_grid.grid_point_to_screen(Vector2(v1))
				if visible_rect.has_point(s0) or visible_rect.has_point(s1):
					var p1 := to_local(s1)
					var h1 := terrain_grid.get_vertex_elevation(v1)
					_draw_lattice_line(p0, p1, h0, h1)

			# Segment to (x, y + 1)
			if y < y_end:
				var v2 := Vector2i(x, y + 1)
				var s2 := terrain_grid.grid_point_to_screen(Vector2(v2))
				if visible_rect.has_point(s0) or visible_rect.has_point(s2):
					var p2 := to_local(s2)
					var h2 := terrain_grid.get_vertex_elevation(v2)
					_draw_lattice_line(p0, p2, h0, h2)

func _draw_lattice_line(p0: Vector2, p1: Vector2, h0: int, h1: int) -> void:
	var has_slope: bool = h0 != h1
	var has_elev: bool = h0 != 0 or h1 != 0

	var color: Color
	var width: float
	if has_slope:
		if h0 > 0 or h1 > 0:
			color = Color(1.0, 0.82, 0.4, 0.5)
		else:
			color = Color(0.45, 0.75, 1.0, 0.5)
		width = 1.6
	elif has_elev:
		color = Color(1.0, 0.85, 0.5, 0.25) if h0 > 0 else Color(0.5, 0.75, 1.0, 0.25)
		width = 1.1
	else:
		color = Color(1.0, 1.0, 1.0, 0.10)
		width = 1.0

	draw_line(p0, p1, color, width, true)

## Downhill slope arrows on sloped tiles
func _draw_slope_arrows(tile_range: Array[Vector2i], visible_rect: Rect2, zoom: float) -> void:
	if zoom < 0.6:
		return
	var x_start: int = maxi(tile_range[0].x, 0)
	var x_end: int = mini(tile_range[1].x, terrain_grid.grid_width - 1)
	var y_start: int = maxi(tile_range[0].y, 0)
	var y_end: int = mini(tile_range[1].y, terrain_grid.grid_height - 1)

	for x in range(x_start, x_end + 1):
		for y in range(y_start, y_end + 1):
			var pos := Vector2i(x, y)
			var slope: Vector2 = terrain_grid.get_slope_at(Vector2(pos) + Vector2(0.5, 0.5))
			var mag: float = slope.length()
			if mag < 0.15:
				continue
			var world_c: Vector2 = terrain_grid.grid_to_screen_center(pos)
			if not visible_rect.has_point(world_c):
				continue
			var center: Vector2 = to_local(world_c)

			# Project downhill slope direction into screen space
			var s_norm := slope.normalized()
			var screen_dir := (terrain_grid.projection.axis_x() * s_norm.x + terrain_grid.projection.axis_y() * s_norm.y).normalized()

			var arrow_len: float = clampf(mag * 9.0, 6.0, 15.0)
			var arrow_end := center + screen_dir * (arrow_len * 0.5)
			var arrow_start := center - screen_dir * (arrow_len * 0.5)

			var arrow_color := Color(1.0, 0.88, 0.35, clampf(mag * 0.7, 0.35, 0.8))
			draw_line(arrow_start, arrow_end, arrow_color, 1.5, true)

			var perp := Vector2(-screen_dir.y, screen_dir.x) * (arrow_len * 0.28)
			var head_base := arrow_end - screen_dir * (arrow_len * 0.35)
			draw_colored_polygon(PackedVector2Array([
				arrow_end, head_base + perp, head_base - perp
			]), arrow_color)

## Markers + height numbers on the vertices inside the viewport.
func _draw_vertex_markers(visible_rect: Rect2, _zoom: float, show_labels: bool,
		show_lattice: bool) -> void:
	var vertices: Array[Vector2i] = _visible_vertices(visible_rect)
	for vertex in vertices:
		var height: int = terrain_grid.get_vertex_elevation(vertex)
		if height == 0:
			if show_lattice:
				_draw_vertex_marker(vertex, Color(1, 1, 1, LATTICE_ALPHA), MARKER_SCALE * 0.7)
			continue

		var color: Color
		if height > 0:
			color = Color(1.0, 0.85, 0.55, VERTEX_ALPHA)  # Warm = raised
		else:
			color = Color(0.55, 0.78, 1.0, VERTEX_ALPHA)  # Cool = depressed
		var center: Vector2 = _draw_vertex_marker(vertex, color, MARKER_SCALE)

		if show_labels:
			var sign_str: String = "+" if height > 0 else ""
			draw_string(
				ThemeDB.fallback_font,
				center + Vector2(4, -4),
				"%s%d" % [sign_str, height],
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				9,
				Color(1, 1, 1, 0.75)
			)

## Contour lines on the edges of visible tiles whose derived height steps.
func _draw_contours(visible_rect: Rect2) -> void:
	var tile_range: Array[Vector2i] = terrain_grid.get_visible_tile_range()
	for x in range(tile_range[0].x, tile_range[1].x + 1):
		for y in range(tile_range[0].y, tile_range[1].y + 1):
			var pos := Vector2i(x, y)
			if terrain_grid.get_elevation(pos) == 0 and not _has_elevated_neighbor(pos):
				continue
			if not visible_rect.has_point(terrain_grid.grid_to_screen_center(pos)):
				continue
			_draw_contour_lines(pos)

## Vertices inside the visible world rect (bounded by the viewport, not the course).
func _visible_vertices(visible_rect: Rect2) -> Array[Vector2i]:
	var tile_range: Array[Vector2i] = terrain_grid.get_visible_tile_range()
	var vertices: Array[Vector2i] = []
	for x in range(tile_range[0].x, tile_range[1].x + 2):
		for y in range(tile_range[0].y, tile_range[1].y + 2):
			var vertex := Vector2i(x, y)
			if not terrain_grid.is_valid_vertex(vertex):
				continue
			if visible_rect.has_point(terrain_grid.grid_point_to_screen(Vector2(vertex))):
				vertices.append(vertex)
	return vertices

## Draw a small projection-aware diamond on a vertex; returns its local centre.
func _draw_vertex_marker(vertex: Vector2i, color: Color, marker_scale: float) -> Vector2:
	var axis_x: Vector2 = terrain_grid.projection.axis_x() * marker_scale
	var axis_y: Vector2 = terrain_grid.projection.axis_y() * marker_scale
	var center: Vector2 = to_local(terrain_grid.grid_point_to_screen(Vector2(vertex)))
	draw_colored_polygon(PackedVector2Array([
		center - axis_x, center - axis_y, center + axis_x, center + axis_y,
	]), color)
	return center

## Check if any of the 4 neighbors has non-zero elevation
func _has_elevated_neighbor(pos: Vector2i) -> bool:
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbor: Vector2i = pos + offset
		if terrain_grid.is_valid_position(neighbor) and terrain_grid.get_elevation(neighbor) != 0:
			return true
	return false

## Draw contour lines with variable weight at elevation boundaries
func _draw_contour_lines(pos: Vector2i) -> void:
	var elevation: int = terrain_grid.get_elevation(pos)

	# Check each edge for elevation change (right, bottom, left, top)
	var offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var line_starts: Array[Vector2] = [Vector2(1, 0), Vector2(0, 1), Vector2.ZERO, Vector2.ZERO]
	var line_ends: Array[Vector2] = [Vector2(1, 1), Vector2(1, 1), Vector2(0, 1), Vector2(1, 0)]

	for i in offsets.size():
		var n_pos: Vector2i = pos + offsets[i]
		if not terrain_grid.is_valid_position(n_pos):
			continue
		var n_elev: int = terrain_grid.get_elevation(n_pos)
		if n_elev == elevation:
			continue

		# Determine line weight: thick for major intervals (crossing even levels)
		var elev_diff: int = abs(elevation - n_elev)
		var is_major: bool = elev_diff >= 2 or (elevation % 2 == 0 and n_elev % 2 != 0) or (elevation != 0 and n_elev == 0)
		var line_width: float = 2.0 if is_major else 1.0
		var alpha: float = CONTOUR_ALPHA_MAJOR if is_major else CONTOUR_ALPHA_MINOR

		# Color: brown for boundaries, darker for deeper
		var avg_elev: float = (elevation + n_elev) / 2.0
		var contour_color: Color
		if avg_elev >= 0:
			contour_color = Color(0.55, 0.4, 0.25, alpha)  # Warm brown
		else:
			contour_color = Color(0.2, 0.25, 0.4, alpha)    # Cool blue-gray

		# Draw the edge line
		draw_line(
				OverlayGeometry.point_in_tile(terrain_grid, self, pos, line_starts[i]),
				OverlayGeometry.point_in_tile(terrain_grid, self, pos, line_ends[i]),
				contour_color, line_width, true)
