extends Control
class_name GlobeMap
## GlobeMap - A draggable orthographic globe with a marker per course location.
##
## The globe is drawn in two layers so spinning, hovering and selecting never
## pay for the continents:
##
##  * **the planet** (`_planet`, a ColorRect running
##    `shaders/globe_planet.gdshader`): the hand-simplified lon/lat polygons
##    below are rasterised once into an equirectangular land mask
##    (`build_land_mask()`, cached for the whole run) and the shader turns that
##    mask back into a shaded sphere — sea depth and coastal shelf, fbm relief,
##    an arid band around the tropics, polar ice, a warm sun with a soft
##    day/night terminator, a specular glint on open water and a soft
##    atmosphere halo. One quad, one draw call, no texture assets.
##  * **the markers** (`_marker_layer`, a Control over the planet): the
##    destination pins and their labels, repainted only when the marker set
##    changes — a hover or a new selection leaves the planet untouched.
##
## `LandStyle.DOTS` keeps the earlier land-dot drawing (every land point as a
## little disc) for callers that want the mask off; the planet is the default.
##
## Drag to spin (with a little inertia), scroll or pinch to zoom, click a
## marker (or the list beside it) to select. Public API: `set_locations`,
## `set_selected`, `look_at_location`, `set_view_state` / `get_view_state`,
## `set_land_style`, `location_clicked(id)`, static `project_point`,
## `is_land`, `build_land_points`, `build_land_mask`, `mask_uv`.

signal location_clicked(location_id: String)

## How the continents are drawn: PLANET (baked mask + shader) or DOTS (the
## old rasterised land points, no shader needed).
enum LandStyle { PLANET, DOTS }

const DEFAULT_LAND_STYLE := LandStyle.PLANET
const PLANET_SHADER := preload("res://shaders/globe_planet.gdshader")

## Size of the baked equirectangular land mask. 2048x1024 is about 3.5 km per
## texel at the equator — sharper than the globe is ever drawn — and bakes in
## ~12 ms.
const MASK_WIDTH := 2048
const MASK_HEIGHT := 1024
## Land mask resolution for the DOTS style: one point every LAND_STEP_DEG degrees.
const LAND_STEP_DEG := 3.0
const MIN_RADIUS_SCALE := 0.7
const MAX_RADIUS_SCALE := 1.6
const MAX_CENTER_LAT := 80.0
## One wheel notch / zoom button step.
const ZOOM_STEP := 1.12
## Spin inertia: how much of the drag's velocity the globe keeps, the cap on
## it, and how fast it bleeds off (per second).
const MAX_SPIN_DEG_PER_SEC := 320.0
const SPIN_DECAY := 0.02
## Seconds a "centre on this destination" move takes, and the settling rate
## used for zoom.
const CENTER_DURATION := 0.5
const ZOOM_SETTLE_RATE := 14.0

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
## Where a zoom is settling to (the buttons and the wheel move this, _process
## eases _radius_scale towards it).
var _zoom_target: float = 1.0
var _locations: Array = []
var _selected_id: String = ""
var _hover_id: String = ""
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_last: Vector2 = Vector2.ZERO
var _drag_distance: float = 0.0
## Active finger, if a touch began on the globe. The global TouchInput adapter
## is for camera gestures; a touch on this control belongs to the atlas instead.
var _touch_index: int = -1
var _marker_positions: Dictionary = {}
## Planet surface (shader) and the marker layer drawn over it.
var _planet: ColorRect = null
var _planet_material: ShaderMaterial = null
var _marker_layer: Control = null
var _land_style: int = DEFAULT_LAND_STYLE
## Degrees per second the globe keeps spinning after a flick, and the
## centring animation's endpoints.
var _spin_lon: float = 0.0
var _spin_lat: float = 0.0
var _anim_from_lon: float = 0.0
var _anim_from_lat: float = 0.0
var _anim_to_lon: float = 0.0
var _anim_to_lat: float = 0.0
var _anim_time: float = 0.0
var _animating: bool = false
static var _land_points: Array = []
static var _land_polygon_cache: Array = []
## How often the planet surface has been re-shaded. Hovering and selecting a
## destination must not touch it — they are the marker layer's business.
var _view_syncs: int = 0
static var _mask_texture: ImageTexture = null
static var _mask_edges: Dictionary = {}
static var _mask_bake_count: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	# Screens that embed the globe may provide a tighter minimum for a phone;
	# keep a comfortable default for standalone previews and other callers.
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(280, 240)
	_build_layers()
	_sync_planet()
	resized.connect(_on_resized)
	set_process(false)

## The two drawing layers: the shader planet underneath, the markers on top.
func _build_layers() -> void:
	if _land_style == LandStyle.PLANET:
		_planet_material = ShaderMaterial.new()
		_planet_material.shader = PLANET_SHADER
		_planet_material.set_shader_parameter("land_mask", get_land_mask_texture())
		_planet_material.set_shader_parameter("mask_size", Vector2(MASK_WIDTH, MASK_HEIGHT))
		_planet = ColorRect.new()
		_planet.name = "PlanetSurface"
		_planet.color = Color.WHITE
		_planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_planet.set_anchors_preset(Control.PRESET_FULL_RECT)
		_planet.material = _planet_material
		add_child(_planet)
	_marker_layer = Control.new()
	_marker_layer.name = "MarkerLayer"
	_marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker_layer.draw.connect(_draw_marker_layer)
	add_child(_marker_layer)

## Switch between the shader planet and the land-dot fallback. Set it before
## the globe enters the tree to decide the layers' first build; changing it on
## a live globe rebuilds them in place.
func set_land_style(style: int) -> void:
	if style == _land_style:
		return
	_land_style = style
	if is_inside_tree():
		if is_instance_valid(_planet):
			_planet.queue_free()
			_planet = null
			_planet_material = null
		if is_instance_valid(_marker_layer):
			_marker_layer.queue_free()
			_marker_layer = null
		_build_layers()
		_redraw_view()

func get_land_style() -> int:
	return _land_style

func _on_resized() -> void:
	_sync_planet()
	_redraw_view()

## Push the view into the planet shader. Changing a shader parameter is what
## makes the planet repaint, so this is the only cost of spinning the globe.
func _sync_planet() -> void:
	if _planet_material == null:
		return
	_view_syncs += 1
	_planet_material.set_shader_parameter("view_size", size)
	_planet_material.set_shader_parameter("center_lon_deg", _center_lon)
	_planet_material.set_shader_parameter("center_lat_deg", _center_lat)
	_planet_material.set_shader_parameter("radius_scale", _radius_scale)

## The view moved: the planet needs new shading and the markers new positions.
func _redraw_view() -> void:
	_sync_planet()
	if _land_style == LandStyle.DOTS:
		queue_redraw()
	_redraw_markers()

## Only the pins changed (hover, selection, list): the planet is left alone.
func _redraw_markers() -> void:
	if is_instance_valid(_marker_layer):
		_marker_layer.queue_redraw()

## How many times the planet has been re-shaded (see _view_syncs).
func view_sync_count() -> int:
	return _view_syncs

## Current orientation and zoom, used to preserve the player's globe view when
## the responsive screen is rebuilt after a resize or device rotation.
func get_view_state() -> Dictionary:
	return {
		"center_lon": _center_lon,
		"center_lat": _center_lat,
		"radius_scale": _radius_scale,
	}

func set_view_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	_center_lon = float(state.get("center_lon", _center_lon))
	_center_lat = clampf(float(state.get("center_lat", _center_lat)), -MAX_CENTER_LAT, MAX_CENTER_LAT)
	_radius_scale = clampf(float(state.get("radius_scale", _radius_scale)), MIN_RADIUS_SCALE, MAX_RADIUS_SCALE)
	_zoom_target = _radius_scale
	_animating = false
	_spin_lon = 0.0
	_spin_lat = 0.0
	set_process(false)
	_redraw_view()

## Zoom steps ease to their target instead of jumping, which reads as the
## globe being pulled towards the player.
func zoom_in() -> void:
	_zoom_target = clampf(_zoom_target * ZOOM_STEP, MIN_RADIUS_SCALE, MAX_RADIUS_SCALE)
	set_process(true)

func zoom_out() -> void:
	_zoom_target = clampf(_zoom_target / ZOOM_STEP, MIN_RADIUS_SCALE, MAX_RADIUS_SCALE)
	set_process(true)

## Give the globe the locations to pin: array of dictionaries with
## id/name/lat/lon (plus any extra state the marker colour needs).
func set_locations(locations: Array) -> void:
	_locations = locations
	_redraw_markers()

func set_selected(location_id: String) -> void:
	_selected_id = location_id
	_redraw_markers()

## Fly the globe round to a location (used when the list selects it). The
## move takes CENTER_DURATION seconds and always goes the shortest way.
func look_at_location(location_id: String) -> void:
	for loc in _locations:
		if str(loc.get("id", "")) == location_id:
			_center_on(float(loc.get("lon", 0.0)), float(loc.get("lat", 0.0)))
			return

## Animate the centre to a lon/lat, picking the nearest copy of the longitude
## so the globe never unwinds the long way round.
func _center_on(lon: float, lat: float) -> void:
	while lon - _center_lon > 180.0:
		lon -= 360.0
	while lon - _center_lon < -180.0:
		lon += 360.0
	_anim_from_lon = _center_lon
	_anim_from_lat = _center_lat
	_anim_to_lon = lon
	_anim_to_lat = clampf(lat, -MAX_CENTER_LAT, MAX_CENTER_LAT)
	_anim_time = 0.0
	_animating = true
	_spin_lon = 0.0
	_spin_lat = 0.0
	set_process(true)

## Smoothly unwrap a longitude so animations can cross the antimeridian
## without a jump.
static func _unwrap_lon(lon: float, reference: float) -> float:
	while lon - reference > 180.0:
		lon -= 360.0
	while lon - reference < -180.0:
		lon += 360.0
	return lon

## Flies the centring animation, settles the zoom and keeps a flicked globe
## spinning until it slows down.
func _process(delta: float) -> void:
	var changed := false

	if _animating:
		_anim_time = minf(_anim_time + delta / CENTER_DURATION, 1.0)
		# Ease out cubic: quick off the mark, gentle on arrival.
		var t := 1.0 - pow(1.0 - _anim_time, 3.0)
		_center_lon = lerpf(_anim_from_lon, _anim_to_lon, t)
		_center_lat = lerpf(_anim_from_lat, _anim_to_lat, t)
		if _anim_time >= 1.0:
			_animating = false
			# Keep the centre in a sane range after a move that wrapped.
			_center_lon = _unwrap_lon(_center_lon, 0.0)
		changed = true

	if absf(_radius_scale - _zoom_target) > 0.0005:
		_radius_scale = lerpf(_radius_scale, _zoom_target, minf(1.0, ZOOM_SETTLE_RATE * delta))
		if absf(_radius_scale - _zoom_target) <= 0.0005:
			_radius_scale = _zoom_target
		changed = true

	# Inertia, but never while the player is still holding the globe.
	if not _dragging and (absf(_spin_lon) > 0.05 or absf(_spin_lat) > 0.05):
		_center_lon = fposmod(_center_lon + _spin_lon * delta, 360.0)
		_center_lat = clampf(_center_lat + _spin_lat * delta, -MAX_CENTER_LAT, MAX_CENTER_LAT)
		var decay := pow(SPIN_DECAY, delta)
		_spin_lon *= decay
		_spin_lat *= decay
		changed = true

	if not changed:
		_spin_lon = 0.0
		_spin_lat = 0.0
		set_process(false)
		return
	_redraw_view()

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

## ── Baked land mask (what the planet shader samples) ─────────────────────

## Rasterise LAND_POLYGONS into an equirectangular coverage mask, white on
## land, which is what `shaders/globe_planet.gdshader` samples. The bake uses
## a scanline fill: a row's land spans are written in bulk with `fill_rect()`
## and only the two ends of each span are written pixel by pixel (with their
## analytic coverage, so coastlines get a soft texel instead of a staircase).
## That keeps a 2048x1024 bake near 12 ms, where testing every texel with
## Geometry2D.is_point_in_polygon would take seconds.
static func build_land_mask(width: int = MASK_WIDTH, height: int = MASK_HEIGHT) -> Image:
	var mask := Image.create(width, height, false, Image.FORMAT_R8)
	mask.fill(Color(0, 0, 0, 1))
	var edges := _get_mask_edges()
	var coords: PackedFloat32Array = edges["coords"]
	var edge_end: PackedInt32Array = edges["end"]
	var lat_min: PackedFloat32Array = edges["lat_min"]
	var lat_max: PackedFloat32Array = edges["lat_max"]
	var polygon_count := edge_end.size()
	var deg_per_row := 180.0 / float(height)
	var to_x := float(width) / 360.0

	_mask_bake_count += 1
	for y in range(height):
		var lat := 90.0 - (float(y) + 0.5) * deg_per_row
		# Longitude where this scanline enters (odd crossing) or leaves (even
		# crossing) the land, kept in ascending order by an insertion sort —
		# a row only ever has a handful of crossings.
		var crossings := PackedFloat32Array()
		var first_edge := 0
		for polygon in range(polygon_count):
			var last_edge: int = edge_end[polygon]
			if lat >= lat_min[polygon] and lat <= lat_max[polygon]:
				for e in range(first_edge, last_edge):
					var ax := coords[e * 4]
					var ay := coords[e * 4 + 1]
					var bx := coords[e * 4 + 2]
					var by := coords[e * 4 + 3]
					if (ay <= lat and by > lat) or (by <= lat and ay > lat):
						var t := (lat - ay) / (by - ay)
						var lon := ax + t * (bx - ax)
						var slot := crossings.size()
						crossings.resize(slot + 1)
						while slot > 0 and crossings[slot - 1] > lon:
							crossings[slot] = crossings[slot - 1]
							slot -= 1
						crossings[slot] = lon
			first_edge = last_edge

		var i := 0
		while i + 1 < crossings.size():
			# Span from crossing i to i+1, in pixel edges. Pixel centres sit at
			# half integers, hence the -0.5.
			var x_start := (crossings[i] + 180.0) * to_x - 0.5
			var x_end := (crossings[i + 1] + 180.0) * to_x - 0.5
			i += 2
			if x_end <= 0.0 or x_start >= float(width - 1):
				continue
			x_start = maxf(x_start, 0.0)
			x_end = minf(x_end, float(width - 1))
			var first := int(x_start)
			var last := int(x_end)
			if first == last:
				_write_mask_coverage(mask, first, y, x_end - x_start)
				continue
			_write_mask_coverage(mask, first, y, 1.0 - (x_start - float(first)))
			_write_mask_coverage(mask, last, y, x_end - float(last))
			if last - first > 1:
				mask.fill_rect(Rect2i(first + 1, y, last - first - 1, 1), Color(1, 1, 1, 1))
	return mask

static func _write_mask_coverage(mask: Image, x: int, y: int, coverage: float) -> void:
	if x < 0 or x >= mask.get_width():
		return
	var value := int(roundf(clampf(coverage, 0.0, 1.0) * 255.0))
	if value > 0:
		mask.set_pixel(x, y, Color8(value, value, value, 255))

## The mask as a texture, baked once per run and shared by every GlobeMap.
## The mipmaps keep the coastline from shimmering when the globe is small.
static func get_land_mask_texture() -> ImageTexture:
	if _mask_texture == null:
		var mask := build_land_mask()
		mask.generate_mipmaps()
		_mask_texture = ImageTexture.create_from_image(mask)
	return _mask_texture

## UV of a lon/lat point in the mask: (0, 0) is the north-west corner. The
## longitude wraps, so any value works; the latitude is kept half a texel
## inside the polar rows so the top/bottom edge is never sampled.
static func mask_uv(lon_deg: float, lat_deg: float, width: int = MASK_WIDTH, height: int = MASK_HEIGHT) -> Vector2:
	var half_row := 0.5 / float(height)
	return Vector2(
		fposmod((lon_deg + 180.0) / 360.0, 1.0),
		clampf(0.5 - lat_deg / 180.0, half_row, 1.0 - half_row))

## Land coverage (0..1) of the mask at a lon/lat, read back for tests and the
## preview harness.
static func mask_coverage(mask: Image, lon_deg: float, lat_deg: float) -> float:
	var uv := mask_uv(lon_deg, lat_deg, mask.get_width(), mask.get_height())
	var x := clampi(int(uv.x * float(mask.get_width())), 0, mask.get_width() - 1)
	var y := clampi(int(uv.y * float(mask.get_height())), 0, mask.get_height() - 1)
	return mask.get_pixel(x, y).r

## How many times the mask has been rasterised this run (tests assert the
## bake is shared, so this only ever grows by one per process).
static func mask_bake_count() -> int:
	return _mask_bake_count

## Reset the shared mask cache (tests only).
static func clear_mask_cache() -> void:
	_mask_texture = null
	_mask_bake_count = 0

## LAND_POLYGONS as one flat array of non-horizontal edges — four floats
## [ax, ay, bx, by] per edge — plus each polygon's latitude range and where
## its edges end in that array. Horizontal edges can never cross a scanline,
## so they are dropped, and a polygon is only tested on rows inside its
## latitude range.
static func _get_mask_edges() -> Dictionary:
	if _mask_edges.is_empty():
		var coords := PackedFloat32Array()
		var end := PackedInt32Array()
		var lat_min := PackedFloat32Array()
		var lat_max := PackedFloat32Array()
		for polygon in _get_polygons():
			var low := 90.0
			var high := -90.0
			var count: int = polygon.size()
			for i in range(count):
				var from: Vector2 = polygon[i]
				var to: Vector2 = polygon[(i + 1) % count]
				low = minf(low, minf(from.y, to.y))
				high = maxf(high, maxf(from.y, to.y))
				if absf(from.y - to.y) < 0.000001:
					continue
				coords.append_array(PackedFloat32Array([from.x, from.y, to.x, to.y]))
			end.append(coords.size() / 4)
			lat_min.append(low)
			lat_max.append(high)
		_mask_edges = {
			"coords": coords,
			"end": end,
			"lat_min": lat_min,
			"lat_max": lat_max,
		}
	return _mask_edges

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

## The land-dot fallback (LandStyle.DOTS). The planet style is drawn by the
## shader on its own layer, so there is nothing to do here.
func _draw() -> void:
	if _land_style == LandStyle.PLANET:
		return
	var center := _sphere_center()
	var radius := _sphere_radius()
	if radius <= 4.0:
		return
	if _land_points.is_empty():
		_land_points = build_land_points()

	# Ocean sphere with a darker rim so it reads as a ball, not a disc.
	draw_circle(center, radius + 3.0, OCEAN_RIM)
	draw_circle(center, radius, OCEAN_COLOR)
	draw_circle(center - Vector2(0.0, radius * 0.12), radius * 0.92, Color(OCEAN_COLOR.lightened(0.04)))

	_draw_graticule(center, radius)
	_draw_land(center, radius)
	draw_arc(center, radius, 0.0, TAU, 128, SHORE_COLOR, 1.5, true)

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

## The marker layer's repaint. Positions are recorded here, in the globe's own
## coordinates (the layer covers the globe exactly), which is what the hover
## test, the click test and the layout harness read back.
func _draw_marker_layer() -> void:
	var canvas: CanvasItem = _marker_layer
	_marker_positions.clear()
	var center := _sphere_center()
	var radius := _sphere_radius()
	if radius <= 4.0:
		return
	_draw_markers(canvas, center, radius)

func _draw_markers(canvas: CanvasItem, center: Vector2, radius: float) -> void:
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

		canvas.draw_circle(pos + Vector2(1.5, 2.0), marker_radius + 1.0, Color(0.0, 0.0, 0.0, 0.35))
		canvas.draw_circle(pos, marker_radius, marker_color(loc))
		canvas.draw_arc(pos, marker_radius, 0.0, TAU, 24, Color(0.05, 0.08, 0.05, 0.9), 1.5, true)
		if selected:
			canvas.draw_arc(pos, marker_radius + 5.0, 0.0, TAU, 32, UIConstants.COLOR_GOLD, 2.0, true)
		if selected or hovered:
			_draw_marker_label(canvas, pos, str(loc.get("name", id)), selected)

func _draw_marker_label(canvas: CanvasItem, pos: Vector2, text: String, selected: bool) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var font_size := 13
	var text_pos := pos + Vector2(11.0, 4.0)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := Vector2(5.0, 3.0)
	var rect_pos := text_pos - pad
	var rect_size := text_size + pad * 2.0
	canvas.draw_rect(Rect2(rect_pos, rect_size), Color(0.04, 0.07, 0.05, 0.82), true)
	var border := UIConstants.COLOR_GOLD if selected else Color(0.6, 0.7, 0.6, 0.8)
	canvas.draw_rect(Rect2(rect_pos, rect_size), border, false, 1.0)
	canvas.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UIConstants.COLOR_TEXT)

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

## Handle raw screen touches here instead of letting the game's camera gesture
## adapter claim them. On phones, a drag on the atlas rotates this globe; a tap
## on a marker selects a destination. Other screen gestures still flow to the
## shared TouchInput adapter as usual.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag and event.index == _touch_index:
		var local_pos := _screen_to_local(event.position)
		var delta := local_pos - _drag_last
		_drag_last = local_pos
		_drag_distance += delta.length()
		var radius := maxf(_sphere_radius(), 1.0)
		_center_lon = fposmod(_center_lon - delta.x * (190.0 / radius), 360.0)
		_center_lat = clampf(_center_lat + delta.y * (170.0 / radius), -MAX_CENTER_LAT, MAX_CENTER_LAT)
		_remember_flick(_spin_from_velocity(event.velocity, radius))
		_redraw_view()
		get_viewport().set_input_as_handled()

func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	var local_pos := _screen_to_local(event.position)
	var inside := Rect2(Vector2.ZERO, size).has_point(local_pos)
	if event.pressed:
		if not inside:
			return
		if _touch_index == -1:
			_touch_index = event.index
			_dragging = true
			_drag_start = local_pos
			_drag_last = local_pos
			_drag_distance = 0.0
		get_viewport().set_input_as_handled()
		return
	if event.index == _touch_index:
		_dragging = false
		if _drag_distance < 6.0:
			_spin_lon = 0.0
			_spin_lat = 0.0
			var hit := _marker_at(local_pos)
			if not hit.is_empty():
				location_clicked.emit(hit)
		else:
			# Let go mid-flick: the globe keeps the spin and coasts.
			set_process(true)
		_touch_index = -1
		get_viewport().set_input_as_handled()
	elif inside:
		# A second finger on the map should not start panning the course behind it.
		get_viewport().set_input_as_handled()

func _screen_to_local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos

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
				_spin_lon = 0.0
				_spin_lat = 0.0
				var hit := _marker_at(event.position)
				if not hit.is_empty():
					location_clicked.emit(hit)
			else:
				set_process(true)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		zoom_in()
		accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		zoom_out()
		accept_event()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _dragging:
		var delta := event.position - _drag_last
		_drag_last = event.position
		_drag_distance += delta.length()
		var radius := maxf(_sphere_radius(), 1.0)
		_center_lon = fposmod(_center_lon - delta.x * (190.0 / radius), 360.0)
		_center_lat = clampf(_center_lat + delta.y * (170.0 / radius), -MAX_CENTER_LAT, MAX_CENTER_LAT)
		_remember_flick(_spin_from_velocity(event.velocity, radius))
		_redraw_view()
		return
	var hit := _marker_at(event.position)
	if hit != _hover_id:
		_hover_id = hit
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not hit.is_empty() else Control.CURSOR_ARROW
		_redraw_markers()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and not _hover_id.is_empty():
		_hover_id = ""
		_redraw_markers()

## The spin a drag of this speed leaves behind, in degrees per second. The
## direction matches the drag: pulling right spins the globe eastwards.
func _spin_from_velocity(velocity: Vector2, radius: float) -> Vector2:
	return Vector2(-velocity.x * (190.0 / radius), velocity.y * (170.0 / radius))

## Remember the newest flick, capped so a violent throw cannot spin the globe
## into a blur.
func _remember_flick(spin: Vector2) -> void:
	_spin_lon = clampf(spin.x, -MAX_SPIN_DEG_PER_SEC, MAX_SPIN_DEG_PER_SEC)
	_spin_lat = clampf(spin.y, -MAX_SPIN_DEG_PER_SEC, MAX_SPIN_DEG_PER_SEC)

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
