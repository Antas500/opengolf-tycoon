extends Control
class_name GlobeMap
## GlobeMap - A draggable orthographic globe with a marker per course location.
##
## Draws an ocean sphere, a latitude/longitude graticule and the continents,
## then pins every WorldLocations entry at its latitude/longitude. Drag to spin
## the globe, scroll to zoom, click a marker (or the list beside it) to select.
##
## The continents come from hand-simplified lon/lat polygons rasterised once
## into ~2000 land points, so the globe needs no texture assets and rotates
## smoothly.

signal location_clicked(location_id: String)

## Land mask resolution: one point every LAND_STEP_DEG degrees.
const LAND_STEP_DEG := 3.0
const MIN_RADIUS_SCALE := 0.7
const MAX_RADIUS_SCALE := 1.6
const MAX_CENTER_LAT := 80.0

const OCEAN_COLOR := Color("16314a")
const OCEAN_RIM := Color("0c1c2c")
const SHORE_COLOR := Color("8fb3c9")
const LAND_COLOR := Color("5f7d4a")
const LAND_SHADE_COLOR := Color("3f5530")
const GRATICULE_COLOR := Color(1.0, 1.0, 1.0, 0.10)
const MARKER_RADIUS := 6.0
const MARKER_HIT_RADIUS := 11.0

## Simplified continent outlines as [lon, lat] pairs (longitude first).
## They are deliberately coarse — the globe is a navigation aid, not an atlas.
const LAND_POLYGONS: Array = [
	# North America
	[
		[-168, 66], [-158, 71], [-140, 70], [-125, 72], [-108, 73], [-95, 73],
		[-82, 74], [-70, 68], [-58, 60], [-52, 48], [-66, 45], [-72, 41],
		[-76, 35], [-81, 25], [-83, 25], [-90, 29], [-97, 26], [-105, 21],
		[-110, 23], [-114, 28], [-117, 32], [-121, 35], [-124, 40], [-127, 49],
		[-131, 54], [-139, 60], [-150, 60], [-160, 56],
	],
	# Central America
	[
		[-92, 16], [-87, 21], [-83, 15], [-78, 8], [-77, 7], [-83, 8], [-88, 14],
	],
	# South America
	[
		[-78, 8], [-72, 11], [-62, 10], [-52, 4], [-44, -2], [-35, -6], [-38, -16],
		[-48, -25], [-58, -35], [-62, -40], [-65, -48], [-68, -55], [-75, -52],
		[-73, -40], [-71, -30], [-70, -18], [-76, -14], [-81, -5], [-80, 2],
	],
	# Greenland
	[
		[-56, 60], [-42, 60], [-22, 70], [-20, 78], [-35, 84], [-58, 82], [-66, 72],
	],
	# Africa
	[
		[-17, 15], [-16, 22], [-10, 30], [0, 36], [10, 37], [20, 33], [33, 31],
		[35, 25], [43, 12], [51, 12], [42, -2], [40, -10], [40, -25], [35, -25],
		[26, -34], [18, -34], [13, -23], [9, -1], [9, 5], [3, 6], [-8, 5], [-13, 9],
	],
	# Madagascar
	[
		[43, -13], [50, -15], [50, -25], [44, -22],
	],
	# Eurasia
	[
		[-10, 36], [-9, 44], [0, 44], [3, 51], [-5, 58], [8, 63], [20, 70],
		[35, 70], [60, 72], [90, 76], [120, 74], [150, 70], [180, 66], [180, 60],
		[150, 52], [140, 42], [130, 34], [122, 30], [115, 22], [108, 15],
		[100, 6], [98, 10], [92, 20], [85, 20], [80, 12], [75, 8], [70, 20],
		[62, 25], [56, 20], [50, 27], [43, 37], [35, 42], [30, 45], [28, 41],
		[20, 40], [13, 45], [18, 42], [10, 38], [3, 43], [-2, 40],
	],
	# British Isles
	[
		[-6, 50], [-2, 52], [0, 54], [-3, 58], [-6, 58], [-8, 53],
	],
	# Ireland
	[
		[-10.5, 51.5], [-6, 52], [-6, 55], [-10, 55],
	],
	# Japan
	[
		[130, 31], [136, 34], [141, 40], [146, 44], [143, 43], [138, 36],
		[133, 33],
	],
	# Indonesia / New Guinea
	[
		[95, 5], [105, 0], [115, -5], [125, -3], [135, -3], [150, -6], [150, -10],
		[140, -9], [130, -8], [120, -9], [110, -8], [100, -2],
	],
	# Philippines
	[
		[120, 6], [126, 8], [126, 18], [120, 16],
	],
	# Australia
	[
		[114, -22], [122, -18], [130, -12], [142, -11], [147, -20], [153, -28],
		[150, -38], [140, -38], [129, -32], [115, -35], [113, -26],
	],
	# Tasmania
	[
		[145, -41], [148, -41], [148, -43], [145, -43],
	],
	# New Zealand
	[
		[173, -35], [178, -38], [174, -47], [166, -46], [170, -41],
	],
	# Antarctica (drawn as a polar band)
	[
		[-180, -63], [-140, -70], [-100, -73], [-60, -63], [-20, -70], [20, -68],
		[60, -66], [100, -64], [140, -66], [180, -63], [180, -90], [-180, -90],
	],
]

var _center_lon: float = -40.0
var _center_lat: float = 30.0
var _radius_scale: float = 1.0
var _locations: Array = []
var _selected_id: String = ""
var _hover_id: String = ""
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_last: Vector2 = Vector2.ZERO
var _drag_distance: float = 0.0
var _marker_positions: Dictionary = {}
static var _land_points: Array = []
static var _land_polygon_cache: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(280, 240)
	if _land_points.is_empty():
		_land_points = build_land_points()
	resized.connect(queue_redraw)

## Give the globe the locations to pin: array of dictionaries with
## id/name/lat/lon (plus any extra state the marker colour needs).
func set_locations(locations: Array) -> void:
	_locations = locations
	queue_redraw()

func set_selected(location_id: String) -> void:
	_selected_id = location_id
	queue_redraw()

## Slowly recentre the globe on a location (used when the list selects it).
func look_at_location(location_id: String) -> void:
	for loc in _locations:
		if str(loc.get("id", "")) == location_id:
			var target_lon: float = float(loc.get("lon", 0.0))
			# Skip the shortest way round the globe.
			while target_lon - _center_lon > 180.0:
				target_lon -= 360.0
			while target_lon - _center_lon < -180.0:
				target_lon += 360.0
			_center_lon = lerpf(_center_lon, target_lon, 0.6)
			_center_lat = lerpf(_center_lat, clampf(float(loc.get("lat", 0.0)), -MAX_CENTER_LAT, MAX_CENTER_LAT), 0.5)
			queue_redraw()
			return

## ── Projection ───────────────────────────────────────────────────────────

## Orthographic projection of a lon/lat point for a globe centred on
## (center_lon, center_lat). Returns a Vector3 where x/y are unit-sphere screen
## offsets (y grows up) and z is visibility (> 0 = facing the viewer).
static func project_point(lon_deg: float, lat_deg: float, center_lon: float, center_lat: float) -> Vector3:
	var phi := deg_to_rad(lat_deg)
	var lam := deg_to_rad(lon_deg - center_lon)
	var phi0 := deg_to_rad(center_lat)
	var z := sin(phi0) * sin(phi) + cos(phi0) * cos(phi) * cos(lam)
	var x := cos(phi) * sin(lam)
	var y := cos(phi0) * sin(phi) - sin(phi0) * cos(phi) * cos(lam)
	return Vector3(x, y, z)

## Rasterise every land polygon into lon/lat points (computed once per run).
static func build_land_points() -> Array:
	var points: Array = []
	var lat := -88.0
	while lat <= 88.0:
		var lon := -180.0
		while lon < 180.0:
			if is_land(lon, lat):
				points.append(Vector2(lon, lat))
			lon += LAND_STEP_DEG
		lat += LAND_STEP_DEG
	return points

static func is_land(lon: float, lat: float) -> bool:
	for polygon in _get_polygons():
		if Geometry2D.is_point_in_polygon(Vector2(lon, lat), polygon):
			return true
	return false

## LAND_POLYGONS as PackedVector2Array, built once (the const form is a plain
## array of [lon, lat] pairs, which PackedVector2Array() would not convert).
static func _get_polygons() -> Array:
	if _land_polygon_cache.is_empty():
		for polygon in LAND_POLYGONS:
			var points := PackedVector2Array()
			for point in polygon:
				points.append(Vector2(float(point[0]), float(point[1])))
			_land_polygon_cache.append(points)
	return _land_polygon_cache

func _project(lon: float, lat: float) -> Vector3:
	return project_point(lon, lat, _center_lon, _center_lat)

func _sphere_radius() -> float:
	return minf(size.x, size.y) * 0.5 * 0.92 * _radius_scale

func _sphere_center() -> Vector2:
	return size * 0.5

func _screen_for(v: Vector3, center: Vector2, radius: float) -> Vector2:
	return center + Vector2(v.x, -v.y) * radius

## ── Drawing ──────────────────────────────────────────────────────────────

func _draw() -> void:
	var center := _sphere_center()
	var radius := _sphere_radius()
	if radius <= 4.0:
		return

	# Ocean sphere with a darker rim so it reads as a ball, not a disc.
	draw_circle(center, radius + 3.0, OCEAN_RIM)
	draw_circle(center, radius, OCEAN_COLOR)
	draw_circle(center - Vector2(0.0, radius * 0.12), radius * 0.92, Color(OCEAN_COLOR.lightened(0.04)))

	_draw_graticule(center, radius)
	_draw_land(center, radius)
	draw_arc(center, radius, 0.0, TAU, 128, SHORE_COLOR, 1.5, true)
	_draw_markers(center, radius)

func _draw_graticule(center: Vector2, radius: float) -> void:
	# Meridians every 30 degrees.
	for lon in range(-180, 180, 30):
		var segment: PackedVector2Array = []
		for lat_step in range(-90, 91, 5):
			var v := _project(float(lon), float(lat_step))
			if v.z > 0.0:
				segment.append(_screen_for(v, center, radius))
			elif segment.size() > 1:
				draw_polyline(segment, GRATICULE_COLOR, 1.0, true)
				segment = []
			else:
				segment = []
		if segment.size() > 1:
			draw_polyline(segment, GRATICULE_COLOR, 1.0, true)

	# Parallels every 30 degrees.
	for lat in range(-60, 90, 30):
		var segment: PackedVector2Array = []
		for lon_step in range(-180, 181, 5):
			var v := _project(float(lon_step), float(lat))
			if v.z > 0.0:
				segment.append(_screen_for(v, center, radius))
			elif segment.size() > 1:
				draw_polyline(segment, GRATICULE_COLOR, 1.0, true)
				segment = []
			else:
				segment = []
		if segment.size() > 1:
			draw_polyline(segment, GRATICULE_COLOR, 1.0, true)

func _draw_land(center: Vector2, radius: float) -> void:
	var dot_radius := maxf(radius * deg_to_rad(LAND_STEP_DEG) * 0.68, 1.5)
	for point in _land_points:
		var v := _project(point.x, point.y)
		if v.z <= 0.0:
			continue
		var pos := _screen_for(v, center, radius)
		var lit := clampf(v.z * 1.6, 0.0, 1.0)
		var color := LAND_SHADE_COLOR.lerp(LAND_COLOR, lit)
		draw_circle(pos, dot_radius * (0.75 + 0.25 * lit), color)

func _draw_markers(center: Vector2, radius: float) -> void:
	_marker_positions.clear()
	var placed: Array = []
	for loc in _locations:
		var v := _project(float(loc.get("lon", 0.0)), float(loc.get("lat", 0.0)))
		if v.z <= 0.02:
			continue
		var pos := _screen_for(v, center, radius)
		# Nudge markers apart so neighbours (Hawaii/Oahu, Scotland/Ireland)
		# stay individually clickable and readable.
		for other in placed:
			if pos.distance_to(other) < MARKER_HIT_RADIUS * 1.6:
				var push: Vector2 = pos - other
				if push.length() < 0.01:
					push = Vector2.RIGHT
				pos = other + push.normalized() * MARKER_HIT_RADIUS * 1.6
		placed.append(pos)

		var id := str(loc.get("id", ""))
		_marker_positions[id] = pos
		var selected: bool = id == _selected_id
		var hovered := id == _hover_id
		var marker_radius := MARKER_RADIUS + (2.0 if selected else 0.0)

		draw_circle(pos + Vector2(1.5, 2.0), marker_radius + 1.0, Color(0.0, 0.0, 0.0, 0.35))
		draw_circle(pos, marker_radius, marker_color(loc))
		draw_arc(pos, marker_radius, 0.0, TAU, 24, Color(0.05, 0.08, 0.05, 0.9), 1.5, true)
		if selected:
			draw_arc(pos, marker_radius + 5.0, 0.0, TAU, 32, UIConstants.COLOR_GOLD, 2.0, true)
		if selected or hovered:
			_draw_marker_label(pos, str(loc.get("name", id)), selected)

func _draw_marker_label(pos: Vector2, text: String, selected: bool) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var font_size := 13
	var text_pos := pos + Vector2(11.0, 4.0)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := Vector2(5.0, 3.0)
	var rect_pos := text_pos - pad
	var rect_size := text_size + pad * 2.0
	draw_rect(Rect2(rect_pos, rect_size), Color(0.04, 0.07, 0.05, 0.82), true)
	var border := UIConstants.COLOR_GOLD if selected else Color(0.6, 0.7, 0.6, 0.8)
	draw_rect(Rect2(rect_pos, rect_size), border, false, 1.0)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UIConstants.COLOR_TEXT)

## Marker colour: active location gold, owned green, affordable white,
## out-of-reach grey.
static func marker_color(loc: Dictionary) -> Color:
	if bool(loc.get("active", false)):
		return UIConstants.COLOR_GOLD
	if bool(loc.get("owned", false)):
		return Color("7fd07f")
	if bool(loc.get("affordable", true)):
		return Color("f0f4ea")
	return Color("7d8a80")

## ── Interaction ──────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_start = event.position
			_drag_last = event.position
			_drag_distance = 0.0
		else:
			_dragging = false
			if _drag_distance < 6.0:
				var hit := _marker_at(event.position)
				if not hit.is_empty():
					location_clicked.emit(hit)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_radius_scale = clampf(_radius_scale * 1.1, MIN_RADIUS_SCALE, MAX_RADIUS_SCALE)
		queue_redraw()
		accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_radius_scale = clampf(_radius_scale / 1.1, MIN_RADIUS_SCALE, MAX_RADIUS_SCALE)
		queue_redraw()
		accept_event()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _dragging:
		var delta := event.position - _drag_last
		_drag_last = event.position
		_drag_distance += delta.length()
		var radius := maxf(_sphere_radius(), 1.0)
		_center_lon = fposmod(_center_lon - delta.x * (190.0 / radius), 360.0)
		_center_lat = clampf(_center_lat + delta.y * (170.0 / radius), -MAX_CENTER_LAT, MAX_CENTER_LAT)
		queue_redraw()
		return
	var hit := _marker_at(event.position)
	if hit != _hover_id:
		_hover_id = hit
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not hit.is_empty() else Control.CURSOR_ARROW
		queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and not _hover_id.is_empty():
		_hover_id = ""
		queue_redraw()

## The marker under a screen position (uses the positions from the last draw).
func _marker_at(screen_pos: Vector2) -> String:
	for id in _marker_positions:
		if screen_pos.distance_to(_marker_positions[id]) <= MARKER_HIT_RADIUS:
			return id
	return ""

## Screen position of a marker from the last draw (empty Vector2 when hidden).
func get_marker_position(location_id: String) -> Vector2:
	return _marker_positions.get(location_id, Vector2.ZERO)

func has_marker_on_screen(location_id: String) -> bool:
	return _marker_positions.has(location_id)
