extends Node2D
class_name CourseArchitecture
## Shared, footprint-relative architecture for built structures and placement ghosts.
##
## Every facility is a miniature isometric building standing on its own grid
## square. Geometry is authored in grid space — x across the footprint (u), y
## down it (v), z in pixels above the ground — and projected through the same
## 2:1 axes the terrain uses, so a building's walls, roofs and doorways follow
## the diamonds of the tiles it occupies instead of sitting on top of them as a
## flat elevation. The same routine draws the placed building, the placement
## ghost and the catalogue tile, so all three show the identical volume; see
## docs/algorithms/isometric-buildings.md.
##
## `facing` is the view rotation the footprint is projected for. The geometry is
## authored in grid space, so rotating the course turns the building with it
## rather than leaving it side-on to its own square.
##
## Upgrades add storeys, wings and landmarks. They never change the base square.
var kind := "clubhouse"
var footprint := Vector2(256, 128)
var level := 1
var clock := 0.0
var facing := 0
var redraw_elapsed := 0.0
## Opacity of every building's footprint shadow, kept in step with the global
## ShadowSystem by whichever architecture node draws next.
static var contact_shadow_strength := 0.25

func _process(delta: float) -> void:
	if not GameManager.is_paused:
		clock += delta
		redraw_elapsed += delta
	if redraw_elapsed >= 0.1:
		redraw_elapsed = 0.0
		queue_redraw()

func _draw() -> void:
	# Window lights and warm glows track gloomy weather now that the course
	# never closes: windows light up under clouds and rain.
	var gloomy: bool = GameManager.weather_system != null \
		and GameManager.weather_system.weather_type >= WeatherSystem.WeatherType.CLOUDY
	var shadow_system := get_node_or_null("/root/ShadowSystem")
	if shadow_system:
		contact_shadow_strength = shadow_system.shadow_intensity
	draw_building(self, kind, footprint, level, clock, gloomy, facing)


# ===========================================================================
# PROJECTION
# ===========================================================================

## One grid tile's diamond in world pixels: a footprint of `n` tiles arrives
## here as `n * TILE_W` wide and `n * TILE_H` deep.
const TILE_W := 64.0
const TILE_H := 32.0

## Quarter-turn a grid-space offset the way GridProjection rotates the course.
static func rotate_uv(offset: Vector2, facing: int) -> Vector2:
	match wrapi(facing, 0, 4):
		1:
			return Vector2(-offset.y, offset.x)
		2:
			return -offset
		3:
			return Vector2(offset.y, -offset.x)
		_:
			return offset

## A grid-space offset projected onto the screen's 2:1 isometric axes.
static func screen_delta(offset: Vector2) -> Vector2:
	return Vector2((offset.x - offset.y) * TILE_W * 0.5,
			(offset.x + offset.y) * TILE_H * 0.5)

## Where grid (0, 0) — the tile corner the footprint's north corner sits on —
## falls in the local space of the building node, for a given view rotation.
##
## Building.set_position_in_grid() places the node at
## `footprint centre - (size.x * 0.5, size.y)` and that anchor is fixed, while
## the footprint's projected centre swings around it as the view turns. This is
## the offset that reconciles the two, and it is what keeps the art on the tiles
## at every rotation.
static func grid_origin_offset(size: Vector2, facing: int) -> Vector2:
	var tiles := Vector2(size.x / TILE_W, size.y / TILE_H)
	var anchor := Vector2(size.x * 0.5, size.y)
	return anchor - screen_delta(rotate_uv(tiles * 0.5, facing))

## Grid point (u across, v down, z up) to local draw space.
static func project_point(origin: Vector2, p: Vector3, facing: int) -> Vector2:
	var r := rotate_uv(Vector2(p.x, p.y), facing)
	return origin + Vector2((r.x - r.y) * TILE_W * 0.5, (r.x + r.y) * TILE_H * 0.5 - p.z)

## Painter's-algorithm key: how near the viewer a plan position sits. Bigger
## draws later, on top.
static func depth_of(u: float, v: float, facing: int) -> float:
	var r := rotate_uv(Vector2(u, v), facing)
	return r.x + r.y

## Brightness of a wall or roof plane from the grid direction it faces. The sun
## hangs over the course's +u side: those faces catch the light, the +v faces
## (the classic isometric shadow side) fall away, and the two back faces only
## matter once the view is rotated around to them.
static func face_shade(normal: Vector2) -> float:
	if normal.x > 0.5:
		return 1.0
	if normal.x < -0.5:
		return 0.74
	if normal.y > 0.5:
		return 0.84
	return 0.93

static func tint(base: Color, factor: float) -> Color:
	return base.lightened(factor - 1.0) if factor > 1.0 else base.darkened(1.0 - factor)

## The wall colour of a facility, shared by its placed building and its ghost.
static func wall_colour(kind_name: String) -> Color:
	match kind_name:
		"clubhouse":
			return Color("e7dbb7")
		"pro_shop":
			return Color("e3dcc0")
		"restaurant":
			return Color("efdcbb")
		"snack_bar":
			return Color("f0e2c0")
		"driving_range", "cart_shed":
			return Color("dccfa8")
		"restroom":
			return Color("e6e0cc")
		"conservatory":
			return Color("d8e2cf")
		"tea_pavilion":
			return Color("f1e7c6")
		"garden_spa":
			return Color("efe3c6")
		"golf_academy":
			return Color("e4d9b8")
		"ice_cream_kiosk":
			return Color("f4e6c8")
		"coffee_house", "halfway_house":
			return Color("e9d8b4")
		_:
			return Color("e3d7b4")

static func roof_colour(kind_name: String, tier: int) -> Color:
	match kind_name:
		"clubhouse":
			return [Color("a8543f"), Color("8a5a3c"), Color("6b6f74")][clampi(tier, 1, 3) - 1]
		"restaurant":
			return Color("7d5a4b")
		"pro_shop":
			return Color("4e6b53")
		"snack_bar":
			return Color("8c5b48")
		"cart_shed", "driving_range":
			return Color("526a49")
		"restroom":
			return Color("4d6273")
		"conservatory":
			return Color("7fa596")
		"tea_pavilion":
			return Color("587966")
		"garden_spa":
			return Color("7d6a86")
		"golf_academy":
			return Color("5c6f57")
		"coffee_house":
			return Color("6d5a48")
		"halfway_house":
			return Color("77604a")
		"locker_room":
			return Color("5a6b80")
		"ice_cream_kiosk":
			return Color("b8707a")
		_:
			return Color("7a5f4b")


# ===========================================================================
# SKETCH — the small drawing surface the facility routines share
# ===========================================================================

## Wraps a CanvasItem with the grid-space drawing primitives every facility is
## built from: faces, walls, roofs, windows, doors and ground clutter.
class Sketch:
	var canvas: CanvasItem
	var origin: Vector2
	var facing: int
	## Everything drawn so far, as a grid-space box (u across, v down, z up).
	## The picture is authored in grid coordinates, so this is how the renderer
	## — and the tests over it — can see that a building stays on its tiles.
	var extent := AABB()
	var _marked := false

	func _init(c: CanvasItem, o: Vector2, f: int) -> void:
		canvas = c
		origin = o
		facing = f

	func _mark(p: Vector3) -> void:
		if _marked:
			extent = extent.expand(p)
		else:
			extent = AABB(p, Vector3.ZERO)
			_marked = true

	## A grid point (tiles across, tiles down, pixels up) in draw space.
	func at(u: float, v: float, z := 0.0) -> Vector2:
		_mark(Vector3(u, v, z))
		return CourseArchitecture.project_point(origin, Vector3(u, v, z), facing)

	## A planar face through grid-space Vector3 corners.
	func face(points: Array, col: Color) -> void:
		var packed := PackedVector2Array()
		for p in points:
			packed.append(at(p.x, p.y, p.z))
		canvas.draw_colored_polygon(packed, col)

	func edge(a: Vector3, b: Vector3, col: Color, width := 1.0) -> void:
		canvas.draw_line(at(a.x, a.y, a.z), at(b.x, b.y, b.z), col, width)

	## Screen-space disc, for smoke, lamps and flowers. The radius is in pixels,
	## while the extent is kept in grid units: a pixel is at most half a tile
	## across the diagonal, so that conversion bounds the disc's reach. `mark`
	## is off for weather — a plume is not part of the building's mass.
	func disc(centre: Vector3, radius: float, col: Color, mark := true) -> void:
		var point := at(centre.x, centre.y, centre.z)
		if mark:
			_mark(centre + Vector3(radius / tiley_units(), radius / tiley_units(), radius))
		canvas.draw_circle(point, radius, col)

	## How many pixels one grid unit spans at pixel scale (the tile's width).
	func tiley_units() -> float:
		return CourseArchitecture.TILE_W

	## The four ground corners of a plan rectangle, in draw order.
	func plan(rect: Rect2, z := 0.0) -> Array:
		var u0 := rect.position.x
		var v0 := rect.position.y
		var u1 := u0 + rect.size.x
		var v1 := v0 + rect.size.y
		return [Vector3(u0, v0, z), Vector3(u1, v0, z), Vector3(u1, v1, z), Vector3(u0, v1, z)]

	## Flat top face of a plan rectangle at height z (terraces, bay floors).
	func slab(rect: Rect2, z: float, col: Color) -> void:
		face(plan(rect, z), col)

	## The vertical faces of a plan rectangle from z0 to z1, back to front, lit
	## by the grid direction each side faces. `bands` draws storey lines.
	func walls(rect: Rect2, z0: float, z1: float, base: Color, bands := 0) -> void:
		var u0 := rect.position.x
		var v0 := rect.position.y
		var u1 := u0 + rect.size.x
		var v1 := v0 + rect.size.y
		var um := (u0 + u1) * 0.5
		var vm := (v0 + v1) * 0.5
		var sides := [
			# [outward normal, face corners, plan midpoint]
			[Vector2(0, -1), [Vector3(u0, v0, z0), Vector3(u1, v0, z0), Vector3(u1, v0, z1), Vector3(u0, v0, z1)], Vector2(um, v0)],
			[Vector2(-1, 0), [Vector3(u0, v0, z0), Vector3(u0, v1, z0), Vector3(u0, v1, z1), Vector3(u0, v0, z1)], Vector2(u0, vm)],
			[Vector2(0, 1), [Vector3(u0, v1, z0), Vector3(u1, v1, z0), Vector3(u1, v1, z1), Vector3(u0, v1, z1)], Vector2(um, v1)],
			[Vector2(1, 0), [Vector3(u1, v0, z0), Vector3(u1, v1, z0), Vector3(u1, v1, z1), Vector3(u1, v0, z1)], Vector2(u1, vm)],
		]
		sides.sort_custom(func(a, b):
			return CourseArchitecture.depth_of(a[2].x, a[2].y, facing) \
				< CourseArchitecture.depth_of(b[2].x, b[2].y, facing))
		for side in sides:
			var normal: Vector2 = side[0]
			var corners: Array = side[1]
			var col := CourseArchitecture.tint(base, CourseArchitecture.face_shade(normal))
			face(corners, col)
			# Grounding skirt and a light band under the eaves.
			edge(corners[0], corners[1], col.darkened(0.35), 1.0)
			if bands > 0:
				for band in range(1, bands + 1):
					var t := float(band) / float(bands + 1)
					var zar: float = lerpf(z0, z1, t)
					var along := Vector2(corners[1].x - corners[0].x, corners[1].y - corners[0].y)
					edge(Vector3(corners[0].x, corners[0].y, zar),
						Vector3(corners[0].x + along.x, corners[0].y + along.y, zar),
						col.darkened(0.14), 1.0)

	## A small cuboid: walls plus its flat top (chimneys, towers, benches).
	func box(rect: Rect2, z0: float, z1: float, base: Color) -> void:
		walls(rect, z0, z1, base)
		slab(rect, z1, CourseArchitecture.tint(base, 1.08))

	## A hip roof over `rect` whose ridge runs along the u axis. `rise` is the
	## height of the ridge above the eaves; `hip` how far the roof slopes in at
	## each end (0 gives a plain gable).
	func hip_roof(rect: Rect2, eave: float, rise: float, base: Color, hip := -1.0) -> void:
		var u0 := rect.position.x
		var v0 := rect.position.y
		var u1 := u0 + rect.size.x
		var v1 := v0 + rect.size.y
		var vm := (v0 + v1) * 0.5
		var h := hip if hip >= 0.0 else ((v1 - v0) * 0.5)
		h = minf(h, (u1 - u0) * 0.45)
		# A plan tile is only half as deep on screen as it is wide, so an
		# uncapped rise throws a steeple over a one-tile hut. Keep the pitch
		# near the classic shallow isometric roof.
		rise = minf(rise, maxf((v1 - v0) * TILE_H * 0.5 * 0.8, 6.0))
		var ridge := eave + rise
		var planes := [
			# [outward normal, corners, plan midpoint of the eave edge]
			[Vector2(0, -1), [Vector3(u0, v0, eave), Vector3(u1, v0, eave),
				Vector3(u1 - h, vm, ridge), Vector3(u0 + h, vm, ridge)], Vector2((u0 + u1) * 0.5, v0)],
			[Vector2(-1, 0), [Vector3(u0, v0, eave), Vector3(u0, v1, eave),
				Vector3(u0 + h, vm, ridge)], Vector2(u0, vm)],
			[Vector2(0, 1), [Vector3(u0, v1, eave), Vector3(u1, v1, eave),
				Vector3(u1 - h, vm, ridge), Vector3(u0 + h, vm, ridge)], Vector2((u0 + u1) * 0.5, v1)],
			[Vector2(1, 0), [Vector3(u1, v0, eave), Vector3(u1, v1, eave),
				Vector3(u1 - h, vm, ridge)], Vector2(u1, vm)],
		]
		planes.sort_custom(func(a, b):
			return CourseArchitecture.depth_of(a[2].x, a[2].y, facing) \
				< CourseArchitecture.depth_of(b[2].x, b[2].y, facing))
		for plane in planes:
			var normal: Vector2 = plane[0]
			var col := CourseArchitecture.tint(base, CourseArchitecture.face_shade(normal) * 1.04)
			face(plane[1], col)
			var corners: Array = plane[1]
			# Courses of tiles running up the slope, so a broad roof is not a
			# flat colour field. Only the two long planes carry them: the hip
			# ends are too narrow to read them.
			if corners.size() == 4:
				var rows: int = int(rect.size.y * 0.5)
				for row in range(1, rows + 1):
					var t := float(row) / float(rows + 1)
					var a: Vector3 = corners[0].lerp(corners[3], t)
					var b: Vector3 = corners[1].lerp(corners[2], t)
					edge(Vector3(a.x, a.y, a.z), Vector3(b.x, b.y, b.z), col.darkened(0.09))
			# Shadow the eave line so the roof sits down on the wall.
			edge(corners[0], corners[1], col.darkened(0.34), 2.0)
		# Ridge cap and hips catch the light.
		if h < (u1 - u0) * 0.45 - 0.001:
			edge(Vector3(u0 + h, vm, ridge), Vector3(u1 - h, vm, ridge),
				CourseArchitecture.tint(base, 1.26), 2.0)
		edge(Vector3(u0, v0, eave), Vector3(u0 + h, vm, ridge), CourseArchitecture.tint(base, 1.12))
		edge(Vector3(u1, v0, eave), Vector3(u1 - h, vm, ridge), CourseArchitecture.tint(base, 1.12))

	## A shed roof: one plane sloping from the ridge line at `v_high` down to the
	## eave at `v_low` (used for porches, verandas and lean-to ranges).
	func shed_roof(rect: Rect2, z_high: float, z_low: float, base: Color) -> void:
		var corners := [
			Vector3(rect.position.x, rect.position.y, z_high),
			Vector3(rect.end.x, rect.position.y, z_high),
			Vector3(rect.end.x, rect.end.y, z_low),
			Vector3(rect.position.x, rect.end.y, z_low),
		]
		face(corners, CourseArchitecture.tint(base, 1.08))
		edge(corners[2], corners[3], base.darkened(0.34), 2.0)
		edge(corners[0], corners[1], CourseArchitecture.tint(base, 1.2), 1.0)

	## Roof surface height at a plan position on a hip roof — where a chimney,
	## dormer or tower has to meet the tiles.
	func roof_z(rect: Rect2, u: float, v: float, eave: float, rise: float, hip := -1.0) -> float:
		var v0 := rect.position.y
		var v1 := rect.end.y
		var vm := (v0 + v1) * 0.5
		var h := hip if hip >= 0.0 else ((v1 - v0) * 0.5)
		h = minf(h, rect.size.x * 0.45)
		var along := 1.0
		if v > vm:
			along = clampf((v1 - v) / maxf(v1 - vm, 0.001), 0.0, 1.0)
		else:
			along = clampf((v - v0) / maxf(vm - v0, 0.001), 0.0, 1.0)
		var end := 1.0
		if u < rect.position.x + h:
			end = clampf((u - rect.position.x) / maxf(h, 0.001), 0.0, 1.0)
		elif u > rect.end.x - h:
			end = clampf((rect.end.x - u) / maxf(h, 0.001), 0.0, 1.0)
		return eave + rise * minf(along, end)

	## A frame, glass and sill on a wall plane. `axis` is "u" for a wall running
	## along the u axis (a +v / -v wall, positioned by `fixed` = its v) and "v"
	## for a +u / -u wall. `along` is the centre of the window measured on the
	## other axis; `out` pushes the trim off the wall, so a window can be drawn
	## on any of the four sides.
	func window_at(axis: String, fixed: float, along: float, z0: float, wide: float,
			tall: float, night: bool, out := 0.0) -> void:
		var glass := Color("eecf85") if night else Color("577b7a")
		var high := Color("ffe7a9") if night else Color("8faeaa")
		var frame := Color("f3e7c7")
		var half := wide * 0.5
		var z1 := z0 + tall
		var a := Vector3(0, 0, 0)
		var b := Vector3(0, 0, 0)
		var o := 0.05 + out
		if axis == "u":
			a = Vector3(along - half, fixed + o, 0)
			b = Vector3(along + half, fixed + o, 0)
		else:
			a = Vector3(fixed + o, along - half, 0)
			b = Vector3(fixed + o, along + half, 0)
		# Sill and lintel stand proud of the wall.
		face([Vector3(a.x, a.y, z0 - 0.5), Vector3(b.x, b.y, z0 - 0.5),
			Vector3(b.x, b.y, z0 + 1.5), Vector3(a.x, a.y, z0 + 1.5)], frame)
		face([Vector3(a.x, a.y, z1), Vector3(b.x, b.y, z1),
			Vector3(b.x, b.y, z1 + 2.0), Vector3(a.x, a.y, z1 + 2.0)], frame.darkened(0.08))
		# Glass, its top highlight and the mullions.
		face([Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0),
			Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1)], frame.darkened(0.18))
		var glass_a := Vector3(lerpf(a.x, b.x, 0.10), lerpf(a.y, b.y, 0.10), 0)
		var glass_b := Vector3(lerpf(a.x, b.x, 0.90), lerpf(a.y, b.y, 0.90), 0)
		face([Vector3(glass_a.x, glass_a.y, z0 + 1), Vector3(glass_b.x, glass_b.y, z0 + 1),
			Vector3(glass_b.x, glass_b.y, z1 - 1), Vector3(glass_a.x, glass_a.y, z1 - 1)], glass)
		face([Vector3(glass_a.x, glass_a.y, z1 - 4.5), Vector3(glass_b.x, glass_b.y, z1 - 4.5),
			Vector3(glass_b.x, glass_b.y, z1 - 1), Vector3(glass_a.x, glass_a.y, z1 - 1)], high)
		var mid := Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, 0)
		face([Vector3(mid.x - (b.x - a.x) * 0.02, mid.y - (b.y - a.y) * 0.02, z0 + 1),
			Vector3(mid.x + (b.x - a.x) * 0.02, mid.y + (b.y - a.y) * 0.02, z0 + 1),
			Vector3(mid.x + (b.x - a.x) * 0.02, mid.y + (b.y - a.y) * 0.02, z1 - 1),
			Vector3(mid.x - (b.x - a.x) * 0.02, mid.y - (b.y - a.y) * 0.02, z1 - 1)], frame.darkened(0.3))
		# Shutters either side, so a lit window still reads as a window.
		for side in [-1.0, 1.0]:
			var sa := Vector3(along + side * (half + 0.045), fixed + o, 0)
			var sb := Vector3(along + side * (half + 0.115), fixed + o, 0)
			if axis == "v":
				sa = Vector3(fixed + o, along + side * (half + 0.045), 0)
				sb = Vector3(fixed + o, along + side * (half + 0.115), 0)
			var shade := Color("385c46") if side < 0 else Color("2f5340")
			face([Vector3(sa.x, sa.y, z0), Vector3(sb.x, sb.y, z0),
				Vector3(sb.x, sb.y, z1), Vector3(sa.x, sa.y, z1)], shade)

	## A doorway with a frame, a step and a doormat-sized threshold.
	func door_at(axis: String, fixed: float, along: float, wide: float, tall: float,
			night: bool, out := 0.0, colour := "345843") -> void:
		var half := wide * 0.5
		var frame := Color("f3e7c7")
		var o := 0.05 + out
		var a := Vector3(along - half, fixed + o, 0)
		var b := Vector3(along + half, fixed + o, 0)
		if axis == "v":
			a = Vector3(fixed + o, along - half, 0)
			b = Vector3(fixed + o, along + half, 0)
		face([Vector3(a.x, a.y, 0), Vector3(b.x, b.y, 0),
			Vector3(b.x, b.y, tall), Vector3(a.x, a.y, tall)], frame)
		var in_a := Vector3(lerpf(a.x, b.x, 0.12), lerpf(a.y, b.y, 0.12), 0)
		var in_b := Vector3(lerpf(a.x, b.x, 0.88), lerpf(a.y, b.y, 0.88), 0)
		face([Vector3(in_a.x, in_a.y, 0.4), Vector3(in_b.x, in_b.y, 0.4),
			Vector3(in_b.x, in_b.y, tall - 1.6), Vector3(in_a.x, in_a.y, tall - 1.6)], Color(colour))
		face([Vector3(in_a.x, in_a.y, 4.4), Vector3(in_b.x, in_b.y, 4.4),
			Vector3(in_b.x, in_b.y, tall - 1.6), Vector3(in_a.x, in_a.y, tall - 1.6)],
			Color("e7c77f") if night else Color("8caaa0"))
		face([Vector3(in_a.x, in_a.y, 4.0), Vector3(in_b.x, in_b.y, 4.0),
			Vector3(in_b.x, in_b.y, 4.8), Vector3(in_a.x, in_a.y, 4.8)], Color("456a50"))
		var knob := Vector3(lerpf(a.x, b.x, 0.78), lerpf(a.y, b.y, 0.78), 6.0)
		if axis == "v":
			knob = Vector3(lerpf(a.x, b.x, 0.78), lerpf(a.y, b.y, 0.78), 6.0)
		disc(knob, 1.0, Color("d5b369"))

	## A stone threshold in front of a doorway on the +v wall.
	func doorstep(u: float, v: float) -> void:
		box(Rect2(u - 0.34, v, 0.68, 0.26), 0.0, 2.2, Color("c3b795"))

	## A sheltered veranda: posts, a canopy and a rail along a +v wall.
	func veranda(u0: float, u1: float, v_wall: float, z_roof: float, col := "f0e3bf") -> void:
		var depth := 0.42
		for u in [u0, (u0 + u1) * 0.5, u1]:
			edge(Vector3(u, v_wall + depth, 2.0), Vector3(u, v_wall + depth, z_roof), Color("918b6b"), 3.0)
			edge(Vector3(u, v_wall + depth, 2.0), Vector3(u, v_wall + depth, z_roof), Color(col), 1.0)
		shed_roof(Rect2(u0 - 0.08, v_wall, (u1 - u0) + 0.16, depth + 0.1),
			z_roof + 5.0, z_roof + 1.0, Color("496a4b"))
		edge(Vector3(u0 - 0.08, v_wall + depth + 0.1, z_roof + 1.0),
			Vector3(u1 + 0.08, v_wall + depth + 0.1, z_roof + 1.0), Color("e8dbb7"), 2.0)

	## A window box of flowers pinned to a wall plane.
	func flower_box(axis: String, fixed: float, along: float, z: float, wide := 0.3) -> void:
		var a := Vector3(along - wide * 0.5, fixed + 0.12, 0)
		var b := Vector3(along + wide * 0.5, fixed + 0.12, 0)
		if axis == "v":
			a = Vector3(fixed + 0.12, along - wide * 0.5, 0)
			b = Vector3(fixed + 0.12, along + wide * 0.5, 0)
		face([Vector3(a.x, a.y, z), Vector3(b.x, b.y, z),
			Vector3(b.x, b.y, z + 4.0), Vector3(a.x, a.y, z + 4.0)], Color("a56c4c"))
		for i in range(4):
			var p := Vector3(lerpf(a.x, b.x, (i + 0.5) / 4.0), lerpf(a.y, b.y, (i + 0.5) / 4.0), z)
			disc(p, 3.0, Color("527442"))
			disc(Vector3(p.x, p.y, z + 3.0), 1.8, Color("e9ae88" if i % 2 else "efe2a6"))

	## Something growing up a wall, kept clear of the doorway.
	func climbing_roses(axis: String, fixed: float, along: float, z_top: float) -> void:
		var steps := int(z_top / 6.0)
		for i in range(steps):
			var z := 2.0 + i * 6.0
			var p := Vector3(along, fixed + 0.08, z)
			if axis == "v":
				p = Vector3(fixed + 0.08, along, z)
			edge(Vector3(p.x, p.y, z - 5.0), p, Color("536642"), 1.0)
			disc(Vector3(p.x + (0.03 if i % 2 else -0.03), p.y, z), 2.0, Color("73854f"))
			if i % 2 == 1:
				disc(Vector3(p.x + 0.05, p.y, z), 2.0, Color("d69b82"))

	## A covered bay opening: used by the driving range and the cart shed.
	func bay(u0: float, u1: float, v_open: float, z_top: float, dark := "304638") -> void:
		face([Vector3(u0, v_open, 2.0), Vector3(u1, v_open, 2.0),
			Vector3(u1, v_open, z_top), Vector3(u0, v_open, z_top)], Color(dark))
		for u in [u0, u1]:
			edge(Vector3(u, v_open, 0.0), Vector3(u, v_open, z_top), Color("b9aa84"), 2.0)

	## A rusticated stone base course around a plan rectangle.
	func plinth(rect: Rect2, z0: float, z1: float, base: Color) -> void:
		walls(rect, z0, z1, base)
		slab(rect, z1, base.lightened(0.06))

	## Paving on the footprint: a slab with its kerb showing.
	func terrace(rect: Rect2, z: float, top: Color, kerb: Color) -> void:
		var low := -0.5
		walls(rect, low, z, kerb)
		slab(rect, z, top)
		# A few paving joints across the slab.
		var u0 := rect.position.x
		var u1 := rect.end.x
		var v0 := rect.position.y
		var v1 := rect.end.y
		for i in range(1, 4):
			var t := float(i) / 4.0
			var u := lerpf(u0, u1, t)
			edge(Vector3(u, v0, z), Vector3(u, v1, z), top.darkened(0.09), 1.0)
			var v := lerpf(v0, v1, t)
			edge(Vector3(u0, v, z), Vector3(u1, v, z), top.darkened(0.09), 1.0)

	## The building's contact shadow, cast onto the tiles it stands on. It is
	## the footprint diamond itself, nudged in the sun's shadow direction, so a
	## building grounds itself on its square instead of floating over it.
	func contact_shadow(rect: Rect2) -> void:
		var shade := Color(0.10, 0.16, 0.10, CourseArchitecture.contact_shadow_strength)
		var drift := Vector2(0.16, 0.30)
		var corners := [
			Vector3(rect.position.x + drift.x, rect.position.y + drift.y, 0.0),
			Vector3(rect.end.x + drift.x, rect.position.y + drift.y, 0.0),
			Vector3(rect.end.x + drift.x, rect.end.y + drift.y, 0.0),
			Vector3(rect.position.x + drift.x, rect.end.y + drift.y, 0.0),
		]
		face(corners, shade)

	## Chimney smoke, drifting whenever the course is open — which is always.
	## Drawn straight to the canvas: a plume is not part of the building's mass,
	## and the extent is what the renderer swears to about its own square.
	func smoke(at_u: float, at_v: float, z: float, time: float) -> void:
		for i in range(3):
			var t := fmod(time * 0.22 + i / 3.0, 1.0)
			var p := Vector3(at_u + sin(t * 3.0) * 0.10, at_v + t * 0.06, z + 6.0 + t * 22.0)
			canvas.draw_circle(CourseArchitecture.project_point(origin, p, facing),
				2.0 + t * 3.0, Color(0.91, 0.9, 0.81, (1.0 - t) * 0.28))

	## A lamp on a wall plane, glowing after dark.
	func lantern(axis: String, fixed: float, along: float, z: float, night: bool,
			out := 0.0) -> void:
		var p := Vector3(along, fixed + 0.08 + out, z)
		if axis == "v":
			p = Vector3(fixed + 0.08 + out, along, z)
		if night:
			disc(Vector3(p.x, p.y, z - 3.0), 7.0, Color(1, 0.78, 0.35, 0.10))
			disc(Vector3(p.x, p.y, z - 3.0), 4.0, Color(1, 0.82, 0.43, 0.16))
		face([Vector3(p.x, p.y, z), Vector3(p.x + 0.05, p.y, z),
			Vector3(p.x + 0.05, p.y, z - 6.0), Vector3(p.x, p.y, z - 6.0)],
			Color("eacb79") if night else Color("b9c2a2"))

	## A free-standing post, for veranda rails and range dividers.
	func post(u: float, v: float, z0: float, z1: float, col := "f0e3bf") -> void:
		edge(Vector3(u, v, z0), Vector3(u, v, z1), Color("918b6b"), 3.0)
		edge(Vector3(u, v, z0), Vector3(u, v, z1), Color(col), 1.0)

	## A striped awning over a doorway or serving hatch on the +v wall. The
	## shadow it throws on the wall is drawn first, so the canopy reads as
	## attached to the building rather than laid in front of it.
	func awning(u0: float, u1: float, v_wall: float, z_top: float, stripe: Color, plain: Color,
			depth := 0.34, drop := 4.0, step := 0.16, posts := true) -> void:
		var outer := z_top - drop
		face([Vector3(u0, v_wall + 0.03, outer - 7.0), Vector3(u1, v_wall + 0.03, outer - 7.0),
			Vector3(u1, v_wall + 0.03, z_top), Vector3(u0, v_wall + 0.03, z_top)],
			Color(0.06, 0.08, 0.06, 0.13))
		var u := u0
		var i := 0
		while u < u1 - 0.001:
			var a := minf(u + step, u1)
			face([Vector3(u, v_wall + 0.04, z_top), Vector3(a, v_wall + 0.04, z_top),
				Vector3(a, v_wall + depth, outer), Vector3(u, v_wall + depth, outer)],
				stripe if i % 2 == 0 else plain)
			i += 1
			u = a
		edge(Vector3(u0, v_wall + depth, outer), Vector3(u1, v_wall + depth, outer),
			plain.darkened(0.3), 2.0)
		if posts:
			for pu in [u0 + 0.07, u1 - 0.07]:
				post(pu, v_wall + depth - 0.05, 2.0, outer, "f0e3bf")


# ===========================================================================
# FACILITIES
# ===========================================================================

static func body_width(kind_name: String, size: Vector2, tier: int) -> float:
	## Width of the building's mass across its square, in pixels. The clubhouse
	## grows with its tier but never leaves the tiles that were bought for it.
	if kind_name == "clubhouse":
		return 118.0 + 26.0 * (clampi(tier, 1, 3) - 1)
	return size.x - 36.0 if size.x > 64 else 36.0

## How many tiles across and down the footprint is.
static func tiles_of(size: Vector2) -> Vector2:
	return Vector2(maxf(size.x / TILE_W, 1.0), maxf(size.y / TILE_H, 1.0))

## Draws one facility on its own square and returns the grid-space box the
## artwork covers (u across, v down, z up). Callers that only want the picture
## can ignore the return value; the placement ghost and the catalogue tile use
## the same routine, so all three show the identical volume.
static func draw_building(c: CanvasItem, kind_name: String, size: Vector2, tier := 1,
		time := 0.0, gloomy := false, facing := 0) -> AABB:
	if kind_name == "bench":
		c.draw_set_transform(Vector2(size.x * 0.5, size.y * 0.7))
		PathFurniture.draw_item(c, "park_bench", Vector2i.DOWN)
		c.draw_set_transform(Vector2.ZERO)
		return AABB(Vector3.ZERO, Vector3(size.x / TILE_W, size.y / TILE_H, 0.0))
	var sk := Sketch.new(c, grid_origin_offset(size, facing), facing)
	match kind_name:
		"clubhouse":
			draw_clubhouse(sk, size, clampi(tier, 1, 3), time, gloomy)
		"pro_shop":
			draw_pro_shop(sk, size, gloomy)
		"restaurant":
			draw_restaurant(sk, size, time, gloomy)
		"snack_bar":
			draw_snack_bar(sk, size, gloomy)
		"driving_range":
			draw_driving_range(sk, size, gloomy)
		"cart_shed":
			draw_cart_shed(sk, size, gloomy)
		"restroom":
			draw_restroom(sk, size, gloomy)
		"conservatory":
			draw_conservatory(sk, size, gloomy)
		"tea_pavilion":
			draw_tea_pavilion(sk, size, gloomy)
		"garden_spa":
			draw_garden_spa(sk, size, gloomy)
		"golf_academy":
			draw_golf_academy(sk, size, gloomy)
		"locker_room":
			draw_locker_room(sk, size, gloomy)
		_:
			draw_kiosk(sk, kind_name, size, time, gloomy)
	return sk.extent


# --------------------------- the clubhouse -------------------------------

## The clubhouse is the one building every course has, so it gets the full
## treatment: a paved terrace filling the footprint, a stone plinth, a hall
## whose two visible walls carry the windows and the front door that the
## golfers actually use, and a hipped roof with a chimney. Each upgrade level
## adds a storey or a wing — and a landmark so the tier reads at a glance.
static func draw_clubhouse(sk: Sketch, size: Vector2, tier: int, time: float, gloomy: bool) -> void:
	var tiles := tiles_of(size)
	var night := gloomy
	var wall := wall_colour("clubhouse").lerp(Color("d9c9a2"), (tier - 1) * 0.55)
	var roof := roof_colour("clubhouse", tier)
	var stone := Color("b6ad87")

	# The footprint itself: paving inside the tiles, with its kerb showing.
	sk.contact_shadow(Rect2(0.22, 0.22, tiles.x - 0.44, tiles.y - 0.44))
	var paving := Rect2(0.14, 0.14, tiles.x - 0.28, tiles.y - 0.28)
	sk.terrace(paving, 2.0, Color("d4c8a4"), Color("b7ab87"))

	# --- massing. Blocks are drawn back to front so an L-shaped or two-storey
	# clubhouse keeps its depth at every view rotation.
	var hall := Rect2(0.42, 0.42, tiles.x - 0.84, tiles.y - 0.84)
	var hall_wall := 30.0
	var hall_rise := 13.0
	if tier >= 2:
		hall = Rect2(0.40, 0.40, tiles.x - 0.80, tiles.y * 0.62)
		hall_wall = 34.0
		hall_rise = 13.0
	if tier >= 3:
		hall = Rect2(0.38, 0.38, tiles.x - 0.76, tiles.y * 0.60)
		hall_wall = 48.0
		hall_rise = 14.0

	# The front range under the entrance, for the tiers that have one.
	var front_range := Rect2(0.62, hall.end.y - 0.06, tiles.x - 1.24,
		tiles.y - 0.62 - hall.end.y + 0.06)
	var blocks: Array = [[hall, hall_wall, hall_rise]]
	if tier >= 2:
		blocks.append([front_range, 21.0, 9.0])
	blocks.sort_custom(func(a, b):
		return CourseArchitecture.depth_of(a[0].position.x + a[0].size.x * 0.5,
				a[0].position.y + a[0].size.y * 0.5, sk.facing) \
			< CourseArchitecture.depth_of(b[0].position.x + b[0].size.x * 0.5,
				b[0].position.y + b[0].size.y * 0.5, sk.facing))

	for i in range(blocks.size()):
		var block: Array = blocks[i]
		var rect: Rect2 = block[0]
		var wall_h: float = block[1]
		var rise: float = block[2]
		var front: bool = i == blocks.size() - 1
		# Stone plinth, so the walls stand on something on every side.
		sk.plinth(Rect2(rect.position - Vector2(0.06, 0.06), rect.size + Vector2(0.12, 0.12)),
			0.0, 3.0, stone)
		sk.walls(rect, 3.0, wall_h, wall, 1 if tier >= 3 and rect == hall else 0)
		var eave := wall_h
		sk.hip_roof(Rect2(rect.position - Vector2(0.16, 0.16), rect.size + Vector2(0.32, 0.32)),
			eave, rise, roof, 1.0)
		# Only the block in front carries the door: it is the one the golfers
		# walk up to. The block behind it gets plain windows.
		if front:
			_draw_clubhouse_front(sk, rect, wall_h, tier, night)
		else:
			_draw_clubhouse_windows(sk, rect, wall_h, night, tier)
		_draw_chimney(sk, rect, eave, rise, tier, time, i == 0)

	if tier >= 3:
		# Ridge height of the block behind, so the tower still reads as a tower.
		_draw_clock_tower(sk, front_range, 21.0 + 9.0, time, night, roof, hall_wall + hall_rise)

	# Ground clutter in front of the entrance, drawn last so it sits proud of
	# the walls: benches, planters and a lamp on the terrace.
	var front_y: float = tiles.y - 0.30
	sk.post(0.72, front_y, 2.0, 13.0, "f0e3bf")
	sk.post(1.02, front_y, 2.0, 13.0, "f0e3bf")
	_bench(sk, 0.86, tiles.y - 0.06)
	_planter(sk, 1.30, front_y + 0.02)
	_planter(sk, tiles.x - 1.30, front_y + 0.02)
	_bench(sk, tiles.x - 0.86, tiles.y - 0.06)


## Windows on the two walls the viewer can see, sized so they stay inside the
## wall they belong to.
static func _draw_clubhouse_windows(sk: Sketch, rect: Rect2, wall_h: float, night: bool,
		tier: int) -> void:
	var floors := [wall_h * 0.5 - 5.0]
	if tier >= 3:
		floors = [11.0, wall_h - 17.0]
	for z in floors:
		for t in [0.32, 0.68]:
			sk.window_at("u", rect.end.y, lerpf(rect.position.x, rect.end.x, t), z, 0.34, 11.0, night)
			sk.window_at("v", rect.end.x, lerpf(rect.position.y, rect.end.y, t), z, 0.34, 11.0, night)
			sk.window_at("u", rect.position.y, lerpf(rect.position.x, rect.end.x, t), z, 0.34, 11.0, night)


## The entrance face: door, porch canopy, window boxes, a lamp and a sign —
## the side `CourseClubhouse.front_tile()` sends the golfers to.
static func _draw_clubhouse_front(sk: Sketch, rect: Rect2, wall_h: float, tier: int,
		night: bool) -> void:
	var v := rect.end.y
	var entry := (rect.position.x + rect.end.x) * 0.5
	_draw_clubhouse_windows(sk, rect, wall_h, night, tier)
	# The doorway sits on the +v wall in grid space, which is the edge the
	# golfers walk up to from whichever tile the course calls the doorstep.
	sk.door_at("u", v, entry, 0.46, 17.0, night)
	sk.doorstep(entry, v)
	sk.flower_box("u", v, entry - 0.46, 5.0)
	sk.flower_box("u", v, entry + 0.46, 5.0)
	sk.lantern("u", v, entry - 0.30, 14.0, night)
	sk.lantern("u", v, entry + 0.30, 14.0, night)
	# A gabled entrance canopy over the door.
	sk.shed_roof(Rect2(entry - 0.46, v - 0.02, 0.92, 0.34), wall_h - 8.0, wall_h - 12.0,
		Color("496a4b"))
	sk.post(entry - 0.44, v + 0.30, 2.0, wall_h - 12.0)
	sk.post(entry + 0.44, v + 0.30, 2.0, wall_h - 12.0)
	# A hanging board beside the door, and roses up the far corner.
	sk.face([Vector3(rect.position.x + 0.35, v + 0.06, 13.0), Vector3(rect.position.x + 0.75, v + 0.06, 13.0),
		Vector3(rect.position.x + 0.75, v + 0.06, 18.0), Vector3(rect.position.x + 0.35, v + 0.06, 18.0)],
		Color("8d6e4b"))
	sk.face([Vector3(rect.position.x + 0.40, v + 0.07, 14.0), Vector3(rect.position.x + 0.70, v + 0.07, 14.0),
		Vector3(rect.position.x + 0.70, v + 0.07, 17.0), Vector3(rect.position.x + 0.40, v + 0.07, 17.0)],
		Color("395b48"))
	sk.climbing_roses("v", rect.end.x, rect.position.y + 0.4, wall_h - 2.0)


static func _draw_chimney(sk: Sketch, rect: Rect2, eave: float, rise: float, tier: int,
		time: float, smoking: bool) -> void:
	if not smoking:
		return
	# Set on the back plane of the roof, off to one side: it must read as part
	# of the roof rather than as a box dropped on the ridge.
	var u := rect.position.x + rect.size.x * 0.30
	var v := rect.position.y + rect.size.y * 0.30
	var base := sk.roof_z(rect, u, v, eave, rise, 1.0) - 5.0
	var top := eave + rise + 9.0
	sk.box(Rect2(u - 0.11, v - 0.11, 0.22, 0.22), base, top, Color("956c52"))
	sk.face([Vector3(u - 0.13, v - 0.13, top), Vector3(u + 0.13, v - 0.13, top),
		Vector3(u + 0.13, v + 0.13, top), Vector3(u - 0.13, v + 0.13, top)],
		Color("d0b68d"))
	sk.disc(Vector3(u, v, top + 0.5), 1.6, Color("4a3a33"))
	sk.smoke(u, v, top, time)


static func _draw_clock_tower(sk: Sketch, rect: Rect2, eave: float, time: float, night: bool,
		roof: Color, clear_of: float) -> void:
	var u := (rect.position.x + rect.end.x) * 0.5
	var v := (rect.position.y + rect.end.y) * 0.5
	var base := eave - 6.0
	# The tower has to clear the roof behind it, or it disappears into it.
	var top := maxf(base + 32.0, clear_of + 5.0)
	sk.box(Rect2(u - 0.34, v - 0.34, 0.68, 0.68), base, top, Color("e8dab6"))
	# Clock faces on the two walls that face the viewer.
	for axis in ["u", "v"]:
		var fixed := v + 0.34 if axis == "u" else u + 0.34
		var along := u if axis == "u" else v
		var centre := Vector3(along, fixed + 0.03, top - 12.0)
		if axis == "v":
			centre = Vector3(fixed + 0.03, along, top - 12.0)
		sk.disc(centre, 5.0, Color("fcf0ce"))
		sk.disc(centre, 4.0, Color("eecf85") if night else Color("a8c0b6"))
		# The hands are pixels on the clock face, not tiles on the ground.
		var face := sk.at(centre.x, centre.y, centre.z)
		sk.canvas.draw_line(face, face - Vector2(0, 3.0), Color("5e6249"), 1.0)
		sk.canvas.draw_line(face, face + Vector2(2.5, -1.5), Color("5e6249"), 1.0)
	# Pyramid roof, finial and pennant.
	sk.face([Vector3(u - 0.44, v - 0.44, top), Vector3(u + 0.44, v - 0.44, top),
		Vector3(u, v, top + 13.0)], CourseArchitecture.tint(roof, 0.94))
	sk.face([Vector3(u + 0.44, v - 0.44, top), Vector3(u + 0.44, v + 0.44, top),
		Vector3(u, v, top + 13.0)], CourseArchitecture.tint(roof, 0.78))
	sk.face([Vector3(u + 0.44, v + 0.44, top), Vector3(u - 0.44, v + 0.44, top),
		Vector3(u, v, top + 13.0)], CourseArchitecture.tint(roof, 1.12))
	sk.face([Vector3(u - 0.44, v + 0.44, top), Vector3(u - 0.44, v - 0.44, top),
		Vector3(u, v, top + 13.0)], CourseArchitecture.tint(roof, 0.68))
	sk.edge(Vector3(u, v, top + 13.0), Vector3(u, v, top + 20.0), Color("c9b98f"), 1.0)
	var flutter := sin(time * 2.8) * 1.4
	var mast := sk.at(u, v, top + 20.0)
	var mast_tip := sk.at(u, v, top + 15.0)
	sk.canvas.draw_colored_polygon(PackedVector2Array([
		mast, mast + Vector2(11.0, 2.0 + flutter), mast_tip]), Color("d6b967"))
	sk.disc(Vector3(u, v, top + 21.0), 1.2, Color("efdb9f"))


static func _bench(sk: Sketch, u: float, v: float) -> void:
	sk.box(Rect2(u - 0.20, v - 0.07, 0.40, 0.14), 2.0, 5.0, Color("b98956"))
	sk.face([Vector3(u - 0.20, v + 0.07, 5.0), Vector3(u + 0.20, v + 0.07, 5.0),
		Vector3(u + 0.20, v + 0.07, 11.0), Vector3(u - 0.20, v + 0.07, 11.0)], Color("d0a16d"))
	for side in [-0.17, 0.17]:
		sk.edge(Vector3(u + side, v - 0.06, 0.0), Vector3(u + side, v - 0.06, 2.0),
			Color("5d6549"), 2.0)


static func _planter(sk: Sketch, u: float, v: float) -> void:
	sk.box(Rect2(u - 0.16, v - 0.14, 0.32, 0.28), 2.0, 7.0, Color("a56c4c"))
	for i in range(4):
		var p := Vector3(u - 0.10 + i * 0.06, v - 0.04 + (i % 2) * 0.06, 7.0)
		sk.disc(p, 3.0, Color("527442"))
		sk.disc(Vector3(p.x, p.y, p.z + 2.5), 1.6, Color("e9ae88" if i % 2 else "efe2a6"))


# --------------------------- the other facilities -------------------------

## A generic single-hall facility: plinth, walls, hipped roof, and whatever
## frontage the kind asks for. Keeps every building on the same square and the
## same scale as the clubhouse.
## Plinth, walls and a hipped roof on an inset rectangle: the common body of
## the single-storey facilities. Returns the rectangle the caller can hang
## frontage off.
static func _hall(sk: Sketch, size: Vector2, wall_h: float, rise: float,
		wall: Color, roof: Color, inset := 0.42) -> Rect2:
	var tiles := tiles_of(size)
	var rect := Rect2(inset, inset, tiles.x - inset * 2.0, tiles.y - inset * 2.0)
	sk.plinth(Rect2(rect.position - Vector2(0.05, 0.05), rect.size + Vector2(0.1, 0.1)),
		0.0, 2.5, Color("b6ad87"))
	sk.walls(rect, 2.5, wall_h, wall)
	sk.hip_roof(Rect2(rect.position - Vector2(0.14, 0.14), rect.size + Vector2(0.28, 0.28)),
		wall_h, rise, roof, minf(0.7, rect.size.x * 0.3))
	return rect


static func draw_pro_shop(sk: Sketch, size: Vector2, gloomy: bool) -> void:
	var wall := wall_colour("pro_shop")
	var roof := roof_colour("pro_shop", 1)
	var rect := _hall(sk, size, 26.0, 12.0, wall, roof)
	var v := rect.end.y
	var u := rect.end.x
	# Display window onto the shop floor, tools in the glass.
	sk.window_at("u", v, rect.position.x + rect.size.x * 0.33, 6.0, 0.62, 12.0, gloomy)
	sk.face([Vector3(u - 0.10, v + 0.06, 9.0), Vector3(u - 0.02, v + 0.06, 9.0),
		Vector3(u - 0.02, v + 0.06, 13.0), Vector3(u - 0.10, v + 0.06, 13.0)], Color("d2ba76"))
	sk.face([Vector3(u - 0.10, v + 0.065, 14.5), Vector3(u - 0.02, v + 0.065, 14.5),
		Vector3(u - 0.02, v + 0.065, 17.0), Vector3(u - 0.10, v + 0.065, 17.0)], Color("b7cebd"))
	sk.window_at("v", u, rect.position.y + rect.size.y * 0.4, 6.0, 0.42, 11.0, gloomy)
	sk.door_at("u", v, u - 0.55, 0.42, 16.0, gloomy)
	sk.doorstep(u - 0.55, v)
	sk.awning(rect.position.x + 0.06, u - 0.86, v, 21.5, Color("54734d"), Color("eadbbb"),
		0.36, 4.5, 0.16, false)
	# Bag stand and a sign board beside the door.
	_golf_bag(sk, u - 1.02, v + 0.16)
	_golf_bag(sk, u - 1.20, v + 0.20)
	sk.face([Vector3(rect.position.x + 0.18, v + 0.05, 11.0), Vector3(rect.position.x + 0.72, v + 0.05, 11.0),
		Vector3(rect.position.x + 0.72, v + 0.05, 18.0), Vector3(rect.position.x + 0.18, v + 0.05, 18.0)],
		Color("355840"))
	sk.disc(Vector3(rect.position.x + 0.45, v + 0.06, 15.5), 2.4, Color("ddc58d"))
	sk.lantern("u", v, u - 0.75, 15.0, gloomy)
	sk.climbing_roses("v", rect.end.x, rect.position.y + 0.35, 20.0)


static func draw_restaurant(sk: Sketch, size: Vector2, time: float, gloomy: bool) -> void:
	var wall := wall_colour("restaurant")
	var roof := roof_colour("restaurant", 1)
	var rect := _hall(sk, size, 28.0, 14.0, wall, roof, 0.36)
	var v := rect.end.y
	var u := rect.end.x
	sk.window_at("u", v, rect.position.x + rect.size.x * 0.26, 7.0, 0.5, 12.0, gloomy)
	sk.window_at("u", v, rect.position.x + rect.size.x * 0.74, 7.0, 0.5, 12.0, gloomy)
	sk.window_at("v", u, rect.position.y + rect.size.y * 0.5, 7.0, 0.5, 12.0, gloomy)
	sk.flower_box("u", v, rect.position.x + rect.size.x * 0.26, 5.0, 0.36)
	sk.flower_box("u", v, rect.position.x + rect.size.x * 0.74, 5.0, 0.36)
	sk.door_at("u", v, u - 0.5, 0.46, 17.0, gloomy)
	sk.doorstep(u - 0.5, v)
	# Awning over the dining windows, chimney with a plume of smoke.
	sk.awning(rect.position.x + 0.06, u - 0.86, v, 22.5, Color("38583e"), Color("e1c98f"),
		0.34, 4.0, 0.14, false)
	sk.face([Vector3(u - 0.32, v + 0.05, 23.0), Vector3(u + 0.32, v + 0.05, 23.0),
		Vector3(u + 0.32, v + 0.05, 27.0), Vector3(u - 0.32, v + 0.05, 27.0)], Color("38583e"))
	sk.edge(Vector3(u - 0.20, v + 0.06, 25.0), Vector3(u - 0.06, v + 0.06, 25.0), Color("e1c98f"), 1.0)
	sk.edge(Vector3(u + 0.06, v + 0.06, 25.0), Vector3(u + 0.20, v + 0.06, 25.0), Color("e1c98f"), 1.0)
	sk.lantern("u", v, u - 0.72, 17.0, gloomy)
	_planter(sk, rect.position.x + 0.30, v + 0.16)
	_planter(sk, u - 0.20, v + 0.20)
	# Table and chairs on the terrace corner.
	sk.box(Rect2(rect.position.x + 0.02, v + 0.30, 0.26, 0.26), 2.0, 9.0, Color("e8dabc"))
	for side in [-1.0, 1.0]:
		sk.edge(Vector3(rect.position.x + 0.15 + side * 0.24, v + 0.43, 2.0),
			Vector3(rect.position.x + 0.15 + side * 0.24, v + 0.43, 7.0), Color("8c6847"), 2.0)


static func draw_snack_bar(sk: Sketch, size: Vector2, gloomy: bool) -> void:
	var wall := wall_colour("snack_bar")
	var roof := roof_colour("snack_bar", 1)
	# A one-tile hut: the diamond is tiny, so the hatch does the talking and the
	# walls fill the tile they were bought for.
	var tiles := tiles_of(size)
	var rect := Rect2(0.17, 0.17, tiles.x - 0.34, tiles.y - 0.34)
	sk.plinth(rect, 0.0, 2.0, Color("b6ad87"))
	sk.walls(rect, 2.0, 21.0, wall)
	sk.hip_roof(Rect2(rect.position - Vector2(0.12, 0.12), rect.size + Vector2(0.24, 0.24)),
		21.0, 12.0, roof, 0.2)
	var v := rect.end.y
	var u := rect.end.x
	# Serving hatch with a striped awning, and a menu board on the side wall.
	sk.face([Vector3(rect.position.x + 0.2, v + 0.04, 8.0), Vector3(u - 0.2, v + 0.04, 8.0),
		Vector3(u - 0.2, v + 0.04, 14.0), Vector3(rect.position.x + 0.2, v + 0.04, 14.0)],
		Color("3e5645"))
	sk.face([Vector3(rect.position.x + 0.22, v + 0.05, 8.6), Vector3(u - 0.22, v + 0.05, 8.6),
		Vector3(u - 0.22, v + 0.05, 13.4), Vector3(rect.position.x + 0.22, v + 0.05, 13.4)],
		Color("b07050"))
	sk.awning(rect.position.x + 0.12, u - 0.12, v, 18.0, Color("b86469"), Color("f3e3bd"),
		0.26, 3.5, 0.16, false)
	sk.face([Vector3(u + 0.02, v - 0.1, 10.0), Vector3(u + 0.02, v - 0.42, 10.0),
		Vector3(u + 0.02, v - 0.42, 16.0), Vector3(u + 0.02, v - 0.1, 16.0)], Color("b99160"))
	sk.face([Vector3(u + 0.03, v - 0.14, 11.0), Vector3(u + 0.03, v - 0.38, 11.0),
		Vector3(u + 0.03, v - 0.38, 15.0), Vector3(u + 0.03, v - 0.14, 15.0)], Color("395b48"))
	sk.disc(Vector3(u + 0.03, v - 0.26, 8.4), 2.0, Color("f2e0b7"))


static func draw_driving_range(sk: Sketch, size: Vector2, gloomy: bool) -> void:
	var wall := wall_colour("driving_range")
	var roof := roof_colour("driving_range", 1)
	var tiles := tiles_of(size)
	var rect := Rect2(0.3, 0.45, tiles.x - 0.6, tiles.y - 0.9)
	sk.plinth(rect, 0.0, 2.5, Color("b6ad87"))
	sk.walls(rect, 2.5, 17.0, wall)
	sk.hip_roof(Rect2(rect.position - Vector2(0.18, 0.14), rect.size + Vector2(0.36, 0.28)),
		17.0, 9.0, roof, 0.45)
	# An open front of covered bays, each with a padded divider and a basket.
	var v := rect.end.y
	var count := maxi(2, int(ceilf((tiles.x - 0.6) / 0.5)))
	for i in range(count):
		var u0 := rect.position.x + 0.16 + i * ((rect.size.x - 0.32) / count)
		var u1 := u0 + (rect.size.x - 0.32) / count - 0.08
		sk.bay(u0, u1, v, 15.5)
		sk.post(u0, v, 2.0, 15.5, "f0e3bf")
		sk.post(u1, v, 2.0, 15.5, "f0e3bf")
		sk.face([Vector3(u1 - 0.12, v + 0.04, 2.5), Vector3(u1, v + 0.04, 2.5),
			Vector3(u1, v + 0.04, 12.0), Vector3(u1 - 0.12, v + 0.04, 12.0)], Color("395f45"))
		sk.box(Rect2(u1 - 0.34, v + 0.10, 0.2, 0.18), 2.0, 6.0, Color("ad9061"))
		if i % 2 == 0:
			sk.lantern("u", v, u0 + 0.1, 13.0, gloomy)
	# Clubhouse signage over the middle of the range.
	var mid := (rect.position.x + rect.end.x) * 0.5
	sk.face([Vector3(mid - 0.42, v + 0.06, 18.0), Vector3(mid + 0.42, v + 0.06, 18.0),
		Vector3(mid + 0.42, v + 0.06, 22.0), Vector3(mid - 0.42, v + 0.06, 22.0)], Color("31563e"))
	sk.disc(Vector3(mid, v + 0.07, 20.0), 1.8, Color("eee4bf"))


static func draw_cart_shed(sk: Sketch, size: Vector2, gloomy: bool) -> void:
	var wall := wall_colour("cart_shed")
	var roof := roof_colour("cart_shed", 1)
	var tiles := tiles_of(size)
	var rect := Rect2(0.34, 0.4, tiles.x - 0.68, tiles.y - 0.8)
	sk.plinth(rect, 0.0, 2.0, Color("b6ad87"))
	sk.walls(rect, 2.0, 17.0, wall)
	sk.hip_roof(Rect2(rect.position - Vector2(0.18, 0.16), rect.size + Vector2(0.36, 0.32)),
		17.0, 9.0, roof, 0.4)
	# Two open bays with golf carts parked inside.
	var v := rect.end.y
	var count := 2
	for i in range(count):
		var u0 := rect.position.x + 0.14 + i * ((rect.size.x - 0.28) / count)
		var u1 := u0 + (rect.size.x - 0.28) / count - 0.08
		sk.bay(u0, u1, v, 14.0)
		sk.post(u0, v, 2.0, 14.0, "f0e3bf")
		sk.post(u1, v, 2.0, 14.0, "f0e3bf")
		var cu := (u0 + u1) * 0.5
		sk.box(Rect2(cu - 0.3, v - 0.34, 0.6, 0.34), 2.0, 8.0, Color("d8d4ae"))
		sk.face([Vector3(cu - 0.3, v - 0.02, 8.0), Vector3(cu + 0.3, v - 0.02, 8.0),
			Vector3(cu + 0.3, v - 0.02, 12.0), Vector3(cu - 0.3, v - 0.02, 12.0)], Color("b8c4a1"))
		for side in [-0.5, 0.5]:
			sk.disc(Vector3(cu + side * 0.26, v + 0.02, 3.0), 2.4, Color("39483b"))
		sk.disc(Vector3(cu + 0.18, v - 0.06, 12.6), 2.0, Color("425743"))
	sk.lantern("u", v, rect.end.x - 0.16, 13.0, gloomy)
	_golf_bag(sk, rect.position.x + 0.02, v + 0.14)


static func draw_restroom(sk: Sketch, size: Vector2, gloomy: bool) -> void:
	var wall := wall_colour("restroom")
	var roof := roof_colour("restroom", 1)
	var tiles := tiles_of(size)
	var rect := Rect2(0.17, 0.17, tiles.x - 0.34, tiles.y - 0.34)
	sk.plinth(rect, 0.0, 2.0, Color("b6ad87"))
	sk.walls(rect, 2.0, 21.0, wall)
	sk.hip_roof(Rect2(rect.position - Vector2(0.12, 0.12), rect.size + Vector2(0.24, 0.24)),
		21.0, 12.0, roof, 0.2)
	var v := rect.end.y
	var u := rect.end.x
	# Two doors, apiece with a small sign, and a trellis on the side wall.
	for side in [-0.22, 0.22]:
		sk.door_at("u", v, (rect.position.x + u) * 0.5 + side, 0.26, 14.0, gloomy, 0.0, "4e6b58")
		sk.disc(Vector3((rect.position.x + u) * 0.5 + side, v + 0.06, 17.0), 1.6, Color("eee1bf"))
	sk.window_at("v", u, rect.position.y + rect.size.y * 0.5, 8.0, 0.3, 6.0, gloomy)
	for i in range(4):
		sk.edge(Vector3(u, v - 0.1 - i * 0.1, 3.0), Vector3(u, v - 0.1 - i * 0.1, 15.0),
			Color("a3946e"), 1.0)
	sk.climbing_roses("u", rect.position.y, rect.position.x + 0.2, 16.0)


static func draw_conservatory(sk: Sketch, size: Vector2, gloomy: bool) -> void:
	var tiles := tiles_of(size)
	var rect := Rect2(0.34, 0.34, tiles.x - 0.68, tiles.y - 0.68)
	sk.plinth(rect, 0.0, 2.5, Color("b6ad87"))
	# A glasshouse: mullioned walls, a light frame and a glazed lantern roof.
	sk.walls(rect, 2.5, 22.0, Color("9dc0b2"))
	var v := rect.end.y
	var u := rect.end.x
	for i in range(1, 6):
		var z := 2.5 + i * 3.4
		sk.edge(Vector3(rect.position.x, v + 0.02, z), Vector3(u, v + 0.02, z), Color("e7dfbb"), 1.0)
	for i in range(1, 5):
		var along := rect.position.x + rect.size.x * i / 5.0
		sk.edge(Vector3(along, v + 0.02, 2.5), Vector3(along, v + 0.02, 22.0), Color("e7dfbb"), 2.0)
	for i in range(1, 4):
		var along_v := rect.position.y + rect.size.y * i / 4.0
		sk.edge(Vector3(u + 0.02, along_v, 2.5), Vector3(u + 0.02, along_v, 22.0), Color("e7dfbb"), 2.0)
	sk.face([Vector3(rect.position.x, v + 0.03, 6.0), Vector3(rect.position.x + 0.3, v + 0.03, 6.0),
		Vector3(rect.position.x + 0.3, v + 0.03, 18.0), Vector3(rect.position.x, v + 0.03, 18.0)],
		Color("3e6957"))
	sk.window_at("u", v, rect.position.x + rect.size.x * 0.7, 7.0, 0.36, 10.0, gloomy)
	sk.hip_roof(Rect2(rect.position - Vector2(0.16, 0.16), rect.size + Vector2(0.32, 0.32)),
		22.0, 13.0, roof_colour("conservatory", 1), 0.55)
	for i in range(3):
		sk.edge(Vector3(rect.position.x, v - 0.16, 22.0 + i * 2.0),
			Vector3(u, v - 0.16, 22.0 + i * 2.0), Color("cfe0d2"), 1.0)
	sk.lantern("u", v, rect.position.x + 0.18, 19.0, gloomy)


static func draw_tea_pavilion(sk: Sketch, size: Vector2, gloomy: bool) -> void:
	var wall := wall_colour("tea_pavilion")
	var roof := roof_colour("tea_pavilion", 1)
	var tiles := tiles_of(size)
	var rect := Rect2(0.36, 0.36, tiles.x - 0.72, tiles.y - 0.72)
	sk.plinth(rect, 0.0, 2.5, Color("b6ad87"))
	sk.walls(rect, 2.5, 22.0, wall)
	sk.hip_roof(Rect2(rect.position - Vector2(0.2, 0.2), rect.size + Vector2(0.4, 0.4)),
		22.0, 12.0, roof, 0.45)
	# A wide shade roof carried on corner posts, tea tables underneath.
	var v := rect.end.y
	var u := rect.end.x
	for corner in [[rect.position.x - 0.2, v + 0.2], [u + 0.2, v + 0.2],
			[rect.position.x - 0.2, rect.position.y - 0.2], [u + 0.2, rect.position.y - 0.2]]:
		sk.post(corner[0], corner[1], 2.5, 22.0, "ece0bd")
	sk.door_at("u", v, (rect.position.x + u) * 0.5, 0.42, 15.0, gloomy)
	for side in [-0.5, 0.5]:
		sk.box(Rect2((rect.position.x + u) * 0.5 + side - 0.16, v + 0.22, 0.32, 0.22),
			2.5, 8.0, Color("b0855c"))
	sk.climbing_roses("v", u, rect.position.y + 0.3, 19.0)
	sk.lantern("u", v, rect.position.x + 0.22, 19.0, gloomy)


static func draw_garden_spa(sk: Sketch, size: Vector2, gloomy: bool) -> void:
	var wall := wall_colour("garden_spa")
	var roof := roof_colour("garden_spa", 1)
	var tiles := tiles_of(size)
	var rect := Rect2(0.34, 0.34, tiles.x - 0.68, tiles.y * 0.52)
	sk.plinth(rect, 0.0, 2.5, Color("b6ad87"))
	sk.walls(rect, 2.5, 22.0, wall)
	sk.hip_roof(Rect2(rect.position - Vector2(0.16, 0.16), rect.size + Vector2(0.32, 0.32)),
		22.0, 12.0, roof, 0.5)
	sk.door_at("u", rect.end.y, (rect.position.x + rect.end.x) * 0.5, 0.42, 15.0, gloomy)
	sk.window_at("v", rect.end.x, rect.position.y + rect.size.y * 0.5, 8.0, 0.34, 10.0, gloomy)
	# The bathing pool outside the door, ringed by loungers.
	var pool := Rect2(rect.position.x + 0.5, rect.end.y + 0.28, rect.size.x - 1.0, tiles.y * 0.32)
	sk.terrace(pool, 2.6, Color("f4dfb2"), Color("c9bb98"))
	sk.slab(pool.grow(-0.14), 2.8, Color("469c99"))
	sk.slab(pool.grow(-0.24), 2.9, Color("78ccc1"))
	for side in [-0.1, 1.1]:
		sk.box(Rect2(rect.position.x + 0.2 + side, pool.end.y + 0.02, 0.5, 0.18), 2.6, 5.0,
			Color("e6d6b2"))
	sk.lantern("v", rect.end.x, rect.end.y - 0.3, 18.0, gloomy)


static func draw_golf_academy(sk: Sketch, size: Vector2, gloomy: bool) -> void:
	var wall := wall_colour("golf_academy")
	var roof := roof_colour("golf_academy", 1)
	var tiles := tiles_of(size)
	var rect := Rect2(0.3, 0.4, tiles.x - 0.6, tiles.y - 0.8)
	sk.plinth(rect, 0.0, 2.5, Color("b6ad87"))
	sk.walls(rect, 2.5, 21.0, wall)
	sk.hip_roof(Rect2(rect.position - Vector2(0.22, 0.18), rect.size + Vector2(0.44, 0.36)),
		21.0, 11.0, roof, 0.6)
	# Teaching bays with netting, a sign and a bag stand.
	var v := rect.end.y
	var count := 3
	for i in range(count):
		var u0 := rect.position.x + 0.14 + i * ((rect.size.x - 0.28) / count)
		var u1 := u0 + (rect.size.x - 0.28) / count - 0.08
		sk.bay(u0, u1, v, 16.0, "527b49")
		sk.post(u0, v, 2.5, 16.0, "f0e3bf")
		sk.post(u1, v, 2.5, 16.0, "f0e3bf")
		sk.edge(Vector3((u0 + u1) * 0.5, v + 0.06, 3.0), Vector3((u0 + u1) * 0.5, v + 0.06, 15.0),
			Color("a0b39a"), 1.0)
		sk.disc(Vector3((u0 + u1) * 0.5, v + 0.07, 4.0), 1.6, Color("faf0d0"))
	sk.face([Vector3(rect.position.x + 0.06, v + 0.05, 18.0), Vector3(rect.position.x + 0.62, v + 0.05, 18.0),
		Vector3(rect.position.x + 0.62, v + 0.05, 24.0), Vector3(rect.position.x + 0.06, v + 0.05, 24.0)],
		Color("31563e"))
	sk.face([Vector3(rect.position.x + 0.1, v + 0.06, 19.0), Vector3(rect.position.x + 0.58, v + 0.06, 19.0),
		Vector3(rect.position.x + 0.58, v + 0.06, 23.0), Vector3(rect.position.x + 0.1, v + 0.06, 23.0)],
		Color("e6d9b5"))
	_golf_bag(sk, rect.end.x - 0.06, v + 0.16)


static func draw_locker_room(sk: Sketch, size: Vector2, gloomy: bool) -> void:
	var wall := wall_colour("locker_room")
	var roof := roof_colour("locker_room", 1)
	var rect := _hall(sk, size, 23.0, 10.0, wall, roof, 0.36)
	var v := rect.end.y
	var u := rect.end.x
	sk.door_at("u", v, (rect.position.x + u) * 0.5 - 0.2, 0.4, 14.0, gloomy)
	sk.door_at("u", v, (rect.position.x + u) * 0.5 + 0.4, 0.4, 14.0, gloomy)
	sk.window_at("v", u, rect.position.y + rect.size.y * 0.5, 7.0, 0.32, 8.0, gloomy)
	# A pair of benches under the veranda, and a club rack outside.
	for side in [-0.6, 0.35]:
		sk.box(Rect2((rect.position.x + u) * 0.5 + side, v + 0.2, 0.44, 0.16), 2.5, 5.0,
			Color("b98956"))
	for i in range(3):
		sk.edge(Vector3(rect.position.x + 0.16 + i * 0.07, v + 0.24, 2.5),
			Vector3(rect.position.x + 0.16 + i * 0.07, v + 0.24, 14.0), Color("a6b4ab"), 1.0)
	sk.lantern("u", v, u - 0.3, 13.0, gloomy)


static func draw_kiosk(sk: Sketch, kind_name: String, size: Vector2, time: float, gloomy: bool) -> void:
	## Coffee house, halfway house and ice-cream kiosk: one small hut with a
	## counter, an awning and whatever landmark the kind is known for.
	var wall := wall_colour(kind_name)
	var roof := roof_colour(kind_name, 1)
	var tiles := tiles_of(size)
	var rect := Rect2(0.22, 0.22, tiles.x - 0.44, tiles.y - 0.44)
	sk.plinth(rect, 0.0, 2.0, Color("b6ad87"))
	sk.walls(rect, 2.0, 21.0, wall)
	var v := rect.end.y
	var u := rect.end.x
	# Counter and striped awning on the frontage.
	sk.face([Vector3(rect.position.x + 0.16, v + 0.04, 8.0), Vector3(u - 0.16, v + 0.04, 8.0),
		Vector3(u - 0.16, v + 0.04, 13.0), Vector3(rect.position.x + 0.16, v + 0.04, 13.0)],
		Color("3e5645"))
	sk.awning(rect.position.x + 0.1, u - 0.1, v, 18.5, Color("3e7866"), Color("f3e3bd"),
		0.28, 3.5, 0.17, false)
	if kind_name == "halfway_house":
		# Its chimney and the tray of drinks by the hatch mark the half-way hut.
		sk.box(Rect2(u - 0.5, rect.position.y + 0.1, 0.22, 0.22), 21.0, 32.0, Color("a87959"))
		sk.smoke(u - 0.39, rect.position.y + 0.21, 32.0, time)
		sk.box(Rect2(u - 0.9, v + 0.3, 0.3, 0.2), 2.0, 6.0, Color("e8dabc"))
	elif kind_name == "ice_cream_kiosk":
		# A scoop sign on a post, and the cone board above the hatch.
		sk.edge(Vector3(u - 0.6, v + 0.22, 2.0), Vector3(u - 0.6, v + 0.22, 24.0), Color("c9b98f"), 2.0)
		sk.disc(Vector3(u - 0.6, v + 0.22, 26.0), 5.0, Color("eab3bd"))
		sk.face([Vector3(u - 0.42, v + 0.04, 18.0), Vector3(u - 0.12, v + 0.04, 18.0),
			Vector3(u - 0.12, v + 0.04, 23.0), Vector3(u - 0.42, v + 0.04, 23.0)], Color("d8a660"))
	else:
		sk.window_at("v", u, rect.position.y + rect.size.y * 0.5, 8.0, 0.3, 8.0, gloomy)
		sk.lantern("u", v, rect.position.x + 0.2, 16.0, gloomy)
	sk.hip_roof(Rect2(rect.position - Vector2(0.18, 0.18), rect.size + Vector2(0.36, 0.36)),
		21.0, 12.0, roof, 0.4)


static func _golf_bag(sk: Sketch, u: float, v: float) -> void:
	sk.box(Rect2(u - 0.09, v - 0.07, 0.18, 0.14), 2.0, 9.0, Color("915d47"))
	for i in range(3):
		sk.edge(Vector3(u - 0.04 + i * 0.04, v, 9.0), Vector3(u - 0.06 + i * 0.04, v, 15.0),
			Color("a6b4ab"), 1.0)
		sk.edge(Vector3(u - 0.06 + i * 0.04, v, 15.0), Vector3(u - 0.02 + i * 0.04, v, 15.0),
			Color("d5d9c4"), 2.0)

