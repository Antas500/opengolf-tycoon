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
	var zoom: float = _camera_zoom()
	var show_labels: bool = zoom >= LABEL_ZOOM
	var show_lattice: bool = zoom >= LATTICE_ZOOM

	_draw_vertex_markers(visible_rect, zoom, show_labels, show_lattice)
	_draw_contours(visible_rect)
	_draw_cliff_faces(visible_rect)

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

## Cliff faces: rock outlines on tiles whose corners step steeply, plus thick
## edge lines where a neighbour tile's average height drops away sharply.
func _draw_cliff_faces(visible_rect: Rect2) -> void:
	var tile_range: Array[Vector2i] = terrain_grid.get_visible_tile_range()
	var outline_color := Color(0.35, 0.28, 0.24, 0.85)
	var edge_color := Color(0.25, 0.18, 0.15, 0.9)
	var line_starts: Array[Vector2] = [Vector2(1, 0), Vector2(0, 1), Vector2.ZERO, Vector2.ZERO]
	var line_ends: Array[Vector2] = [Vector2(1, 1), Vector2(1, 1), Vector2(0, 1), Vector2(1, 0)]
	for x in range(tile_range[0].x, tile_range[1].x + 1):
		for y in range(tile_range[0].y, tile_range[1].y + 1):
			var pos := Vector2i(x, y)
			if not terrain_grid.is_cliff_tile(pos):
				continue
			if not visible_rect.has_point(terrain_grid.grid_to_screen_center(pos)):
				continue
			draw_polyline(OverlayGeometry.tile_polyline(terrain_grid, self, pos),
					outline_color, 2.0)
			for edge in terrain_grid.get_cliff_edges(pos):
				draw_line(
						OverlayGeometry.point_in_tile(terrain_grid, self, pos, line_starts[edge]),
						OverlayGeometry.point_in_tile(terrain_grid, self, pos, line_ends[edge]),
						edge_color, 3.0, true)

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
func _draw_vertex_marker(vertex: Vector2i, color: Color, scale: float) -> Vector2:
	var axis_x: Vector2 = terrain_grid.projection.axis_x() * scale
	var axis_y: Vector2 = terrain_grid.projection.axis_y() * scale
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
