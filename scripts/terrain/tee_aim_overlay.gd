extends Node2D
class_name TeeAimOverlay
## TeeAimOverlay - Paints the aiming arrow in the turf of every tee tile.
##
## Each tee tile carries a painted arrow that points the way the hole plays, with
## a red ball on either side of it — the tee markers a golfer stands between. A
## hole that plays straight gets a straight arrow aimed at the cup; a dogleg gets
## a curved one: the shaft leaves the tee along the drive line, curves through the
## turn and arrives at the tip pointing down the approach (TeeAimRoute supplies the
## legs). While a tee box is still waiting for its green the arrow points at the
## waiting cup, so the tee the player just painted already says which green it will
## play to.
##
## The marker is a sign, not a map: a fixed-size arrow rather than a miniature of
## the hole, so every tee on the course reads the same. Direction comes off the
## flat map — elevation lifts the tile the arrow is painted on, it must not bend
## the arrow — and the whole marker is then centred on the tile and scaled to fit
## inside the shape its grass covers, which is the tile's projected outline: a 2:1
## diamond in the isometric view, leaning with the terrain's elevation. A tile whose
## grass folds to a sliver cannot hold a readable arrow at all, so the marker stops
## shrinking at MIN_FIT_SCALE and laps a pixel or two over the edge instead.
##
## Like CupOverlay this is a terrain overlay: it redraws when the view rotates or
## the camera moves, and rebuilds when the terrain or the holes change.

## Nothing to aim at (grid coordinates are never negative).
const NO_TARGET := Vector2i(-1, -1)
const EMPTY_ROUTE: Array[Vector2i] = []

## Above the terrain surface, below the golfers and the ball.
const Z_INDEX: int = 6

## Length of the shaft, tail to tip, before the tile fit. Sized for the 64x32
## tile, whose diamond reaches 32 px sideways and 16 px up from its centre.
const ARROW_LENGTH: float = 32.0
const SHAFT_STEPS: int = 12
## A hole that turns less than this (about 3°) is a straight hole: its arc would
## be so wide it could only be drawn as a straight line anyway.
const TURN_MIN_RADIANS: float = 0.05

# Painted arrow. A dark rim under light paint keeps the marker readable on both
# sun-bleached links turf and dark woodland tee boxes.
const PAINT_COLOR := Color(0.97, 0.98, 0.93, 0.92)
const PAINT_EDGE_COLOR := Color(0.05, 0.13, 0.07, 0.45)
const SHAFT_WIDTH: float = 3.6
const EDGE_WIDTH: float = 5.2
const HEAD_LENGTH: float = 8.6
const HEAD_HALF: float = 5.0
## The shaft stops this far back from the tip so the head covers its end cleanly.
const HEAD_OVERLAP: float = 0.7

# The two red tee markers on either side of the shaft.
const BALL_COLOR := Color(0.86, 0.15, 0.14)
const BALL_EDGE_COLOR := Color(0.30, 0.04, 0.04, 0.85)
const BALL_HIGHLIGHT := Color(1.0, 1.0, 1.0, 0.8)
const BALL_RADIUS: float = 2.5
const BALL_OFFSET: float = 6.8
## Where along the shaft (0 = tail, 1 = tip) the red markers straddle it.
const BALL_ANCHOR_FRACTION: float = 0.5

## Pixels kept between the paint and the edge of the tile.
const SAFE_INSET: float = 2.6
## Smallest the marker is ever drawn. A tile whose grass folds to a sliver — a tee
## perched on a cliff edge — has no room for a readable arrow, so the marker is
## drawn at this size and laps a pixel or two over the tile edge rather than
## shrinking into an unreadable speck.
const MIN_FIT_SCALE: float = 0.45
const MIN_SEGMENT: float = 0.25

var terrain_grid: TerrainGrid = null
## Vector2i tee tile -> Array[Vector2i] route to aim along (see TeeAimRoute).
var _markers: Dictionary = {}
var _rebuild_pending: bool = false

func initialize(grid: TerrainGrid) -> void:
	terrain_grid = grid
	z_index = Z_INDEX
	if terrain_grid:
		if not terrain_grid.tile_changed.is_connected(_on_tile_changed):
			terrain_grid.tile_changed.connect(_on_tile_changed)
		if not terrain_grid.cup_tiles_changed.is_connected(_on_cup_tiles_changed):
			terrain_grid.cup_tiles_changed.connect(_on_cup_tiles_changed)
		if not terrain_grid.vertex_elevation_changed.is_connected(_on_ground_changed):
			terrain_grid.vertex_elevation_changed.connect(_on_ground_changed)
		if not terrain_grid.elevation_changed.is_connected(_on_ground_changed):
			terrain_grid.elevation_changed.connect(_on_ground_changed)
	EventBus.hole_created.connect(_on_holes_changed)
	EventBus.hole_deleted.connect(_on_holes_changed)
	EventBus.hole_updated.connect(_on_hole_updated)
	EventBus.pins_rotated.connect(_on_holes_changed)
	EventBus.load_completed.connect(_on_load_completed)
	rebuild()

func _exit_tree() -> void:
	if terrain_grid:
		if terrain_grid.tile_changed.is_connected(_on_tile_changed):
			terrain_grid.tile_changed.disconnect(_on_tile_changed)
		if terrain_grid.cup_tiles_changed.is_connected(_on_cup_tiles_changed):
			terrain_grid.cup_tiles_changed.disconnect(_on_cup_tiles_changed)
		if terrain_grid.vertex_elevation_changed.is_connected(_on_ground_changed):
			terrain_grid.vertex_elevation_changed.disconnect(_on_ground_changed)
		if terrain_grid.elevation_changed.is_connected(_on_ground_changed):
			terrain_grid.elevation_changed.disconnect(_on_ground_changed)
	if EventBus.hole_created.is_connected(_on_holes_changed):
		EventBus.hole_created.disconnect(_on_holes_changed)
	if EventBus.hole_deleted.is_connected(_on_holes_changed):
		EventBus.hole_deleted.disconnect(_on_holes_changed)
	if EventBus.hole_updated.is_connected(_on_hole_updated):
		EventBus.hole_updated.disconnect(_on_hole_updated)
	if EventBus.pins_rotated.is_connected(_on_holes_changed):
		EventBus.pins_rotated.disconnect(_on_holes_changed)
	if EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.disconnect(_on_load_completed)

func _on_tile_changed(_position: Vector2i, _old_type: int, _new_type: int) -> void:
	_schedule_rebuild()

func _on_cup_tiles_changed() -> void:
	_schedule_rebuild()

## Raising or lowering the ground reshapes the tile and so the marker that fits in
## it — but not the route, so a redraw is enough.
func _on_ground_changed(_a = null, _b = null, _c = null) -> void:
	queue_redraw()

func _on_holes_changed(_a = null, _b = null, _c = null) -> void:
	_schedule_rebuild()

func _on_hole_updated(_hole_number: int) -> void:
	_schedule_rebuild()

func _on_load_completed(_success: bool) -> void:
	_schedule_rebuild()

## Coalesce the rebuilds a paint stroke or a bulk edit would otherwise trigger.
func _schedule_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	call_deferred("rebuild")

## Work out which tile each tee tile aims at, then repaint.
func rebuild() -> void:
	_rebuild_pending = false
	_markers.clear()
	if not terrain_grid:
		queue_redraw()
		return

	var course: GameManager.CourseData = GameManager.current_course
	var targets := _hole_cups_by_tee(course)
	var waiting := _waiting_cup()
	var waiting_tees: Dictionary = {}
	if waiting != NO_TARGET:
		for pos in HoleLayout.unused_tee_boxes(terrain_grid, course):
			waiting_tees[pos] = true

	for tee in terrain_grid.get_tee_box_tiles():
		var cup: Vector2i = targets.get(tee, NO_TARGET)
		if cup == NO_TARGET and waiting_tees.has(tee):
			cup = waiting
		if cup == NO_TARGET:
			continue
		var route := TeeAimRoute.aim_route(terrain_grid, tee, cup)
		if route.size() >= 2:
			_markers[tee] = route
	queue_redraw()

## Tee tile -> the cup of the hole that owns it (back, forward and middle tees).
func _hole_cups_by_tee(course: GameManager.CourseData) -> Dictionary:
	var cups: Dictionary = {}
	if not course:
		return cups
	for hole in course.holes:
		cups[hole.tee_position] = hole.hole_position
		for tee_key in hole.tee_positions:
			cups[hole.tee_positions[tee_key]] = hole.hole_position
	return cups

## The single green with a hole that is still waiting for its tee box, or
## NO_TARGET when there is none — or when the pairing is ambiguous.
func _waiting_cup() -> Vector2i:
	var cups := HoleLayout.unused_cups(terrain_grid, GameManager.current_course)
	if cups.size() != 1:
		return NO_TARGET
	return cups[0]

## Every tee tile carrying an aim arrow, sorted for stable callers.
func aimed_tees() -> Array[Vector2i]:
	var tees: Array[Vector2i] = []
	for tee in _markers:
		tees.append(tee)
	tees.sort()
	return tees

## The route a tee tile aims along, or [] when the tile has no arrow.
func route_for(tee: Vector2i) -> Array[Vector2i]:
	return _markers.get(tee, EMPTY_ROUTE)

## Everything needed to paint one tee tile's marker, in this overlay's local
## space: {"shaft": PackedVector2Array, "head": PackedVector2Array,
## "balls": PackedVector2Array, "scale": float, "fit": float, "floored": bool} —
## the scale being how much the tile fit shrank the marker, so the painter can
## shrink its pen widths to match; `fit` the honest room the tile had, and
## `floored` true when that was under MIN_FIT_SCALE. Empty when the tile has no
## arrow to paint.
func marker_layout(tee: Vector2i) -> Dictionary:
	if not _markers.has(tee) or terrain_grid == null:
		return {}
	if not terrain_grid.is_valid_position(tee):
		return {}
	var route: Array[Vector2i] = _markers[tee]
	if route.size() < 2:
		return {}

	# 1. The two legs of the route, on the flat map: the arrow leaves the tee
	#    along the first and arrives at the tip pointing down the last.
	var flat_centre := _flat_point(tee)
	var legs := PackedVector2Array()
	for pos in route:
		legs.append(_flat_point(pos) - flat_centre)
	var in_dir := direction(legs[0], legs[1])
	var out_dir := direction(legs[legs.size() - 2], legs[legs.size() - 1])
	if in_dir == Vector2.ZERO:
		in_dir = out_dir
	if out_dir == Vector2.ZERO:
		out_dir = in_dir
	if in_dir == Vector2.ZERO:
		return {}

	# 2. The shaft: a fixed-length arrow aimed down the hole, straight when the
	#    legs line up and bowed toward the turn of a dogleg when they don't.
	var shaft := aim_shaft(in_dir, out_dir, ARROW_LENGTH)
	var head_dir := direction(shaft[shaft.size() - 2], shaft[shaft.size() - 1])
	if head_dir == Vector2.ZERO:
		return {}
	var head := head_points(shaft[shaft.size() - 1], head_dir, HEAD_LENGTH, HEAD_HALF)

	# 3. Centre the arrow on the tile by what is actually painted.
	var shift := _bounds_centre(shaft, head)
	for i in range(shaft.size()):
		shaft[i] -= shift
	for i in range(head.size()):
		head[i] -= shift

	# 4. Fit the whole marker — shaft, arrow head and both red balls — inside the
	#    shape the tile's grass covers.
	var centre := OverlayGeometry.tile_center(terrain_grid, self, tee)
	var balls := ball_points(shaft, BALL_OFFSET, BALL_ANCHOR_FRACTION)
	var edges := _tile_edges(tee, centre)
	# No edges means the tile's outline folds over itself: it has no dependable
	# interior to fit into, so the marker drops to its minimum size.
	var fit := 0.0
	if not edges.is_empty():
		fit = fit_scale(edges, [
			{"points": shaft, "pen": EDGE_WIDTH * 0.5},
			{"points": head, "pen": 1.0},
			{"points": balls, "pen": BALL_RADIUS},
		], centre, SAFE_INSET)
	var scale := clampf(fit, MIN_FIT_SCALE, 1.0)
	if scale < 1.0:
		for i in range(shaft.size()):
			shaft[i] *= scale
		for i in range(head.size()):
			head[i] *= scale
		for i in range(balls.size()):
			balls[i] *= scale

	# 5. Local space, with the shaft stopped where the head takes over.
	for i in range(shaft.size()):
		shaft[i] += centre
	for i in range(head.size()):
		head[i] += centre
	for i in range(balls.size()):
		balls[i] += centre
	return {
		"shaft": trim_to_head(shaft, HEAD_LENGTH * HEAD_OVERLAP * scale),
		"head": head,
		"balls": balls,
		"scale": scale,
		"fit": fit,
		"floored": fit < MIN_FIT_SCALE,
	}

func _draw() -> void:
	if terrain_grid == null or _markers.is_empty():
		return
	var visible_rect := terrain_grid.get_visible_world_rect()
	visible_rect = visible_rect.grow(maxf(terrain_grid.tile_width, terrain_grid.tile_height))
	for tee in _markers:
		if not visible_rect.has_point(terrain_grid.grid_to_screen_center(tee)):
			continue
		var layout := marker_layout(tee)
		if layout.is_empty():
			continue
		var scale: float = layout.scale
		var shaft: PackedVector2Array = layout.shaft
		var head: PackedVector2Array = layout.head
		draw_polyline(shaft, PAINT_EDGE_COLOR, EDGE_WIDTH * scale, true)
		draw_polyline(shaft, PAINT_COLOR, SHAFT_WIDTH * scale, true)
		draw_colored_polygon(head, PAINT_COLOR)
		draw_polyline(_closed(head), PAINT_EDGE_COLOR, 2.0 * scale, true)
		for ball in layout.balls:
			_draw_tee_marker(ball, BALL_RADIUS * scale)

## A red tee marker ball: shadow on the grass, dark rim, red body, highlight.
func _draw_tee_marker(centre: Vector2, radius: float) -> void:
	var shadow := PackedVector2Array()
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		shadow.append(centre + Vector2(cos(angle) * radius * 0.95,
				sin(angle) * radius * 0.55 + radius * 0.4))
	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.22))
	draw_circle(centre, radius + 0.35 * radius, BALL_EDGE_COLOR)
	draw_circle(centre, radius, BALL_COLOR)
	draw_circle(centre - Vector2(radius * 0.32, radius * 0.38), radius * 0.34, BALL_HIGHLIGHT)

## The painted shaft, centred on the tile: a straight arrow when the hole plays
## straight, and otherwise the arc that leaves the tee pointing down the drive
## line and arrives at the tip pointing down the approach line. The arc always
## spans the same distance along the hole, so a dogleg reads as the same arrow
## with a bend in it.
static func aim_shaft(in_dir: Vector2, out_dir: Vector2, length: float) -> PackedVector2Array:
	var turn := in_dir.angle_to(out_dir)
	if absf(turn) < TURN_MIN_RADIANS:
		return straight_polyline(-in_dir * (length * 0.5), in_dir * (length * 0.5))
	# A circular arc: the chord between tail and tip runs along the bisector of
	# the two directions, the radius follows from the turn, and the centre sits
	# on the inside of the turn.
	var chord_dir := (in_dir + out_dir).normalized()
	var radius := length / (2.0 * sin(absf(turn) * 0.5))
	var tail := -chord_dir * (length * 0.5)
	var centre := tail + Vector2(-in_dir.y, in_dir.x) * signf(turn) * radius
	var points := PackedVector2Array()
	for step in range(SHAFT_STEPS + 1):
		var t := float(step) / float(SHAFT_STEPS)
		points.append(centre + (tail - centre).rotated(turn * t))
	return points

static func head_points(tip: Vector2, head_dir: Vector2, length: float, half: float) -> PackedVector2Array:
	var side := Vector2(-head_dir.y, head_dir.x)
	return PackedVector2Array([
		tip,
		tip - head_dir * length + side * half,
		tip - head_dir * length - side * half,
	])

## The two red markers, one either side of the shaft at `fraction` along it.
static func ball_points(shaft: PackedVector2Array, offset: float, fraction: float) -> PackedVector2Array:
	var index := index_at_fraction(shaft, fraction)
	var here := shaft[index]
	var along := direction(shaft[maxi(index - 1, 0)], shaft[mini(index + 1, shaft.size() - 1)])
	if along == Vector2.ZERO:
		along = direction(shaft[0], shaft[shaft.size() - 1])
	if along == Vector2.ZERO:
		return PackedVector2Array()
	var side := Vector2(-along.y, along.x)
	return PackedVector2Array([here + side * offset, here - side * offset])

static func straight_polyline(start: Vector2, end: Vector2,
		steps: int = SHAFT_STEPS) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in range(steps + 1):
		points.append(start.lerp(end, float(step) / float(steps)))
	return points

static func direction(from: Vector2, to: Vector2) -> Vector2:
	var delta := to - from
	if delta.length() < 0.001:
		return Vector2.ZERO
	return delta.normalized()

## Index of the polyline point `fraction` of the way along it.
static func index_at_fraction(points: PackedVector2Array, fraction: float) -> int:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	if total <= 0.0:
		return 0
	var wanted := total * clampf(fraction, 0.0, 1.0)
	var walked := 0.0
	for i in range(1, points.size()):
		walked += points[i].distance_to(points[i - 1])
		if walked >= wanted:
			return i
	return points.size() - 1

## True when a quad's corners all turn the same way — which a tile's outline
## stops doing once a steep slope folds it over itself.
static func _is_convex(outline: PackedVector2Array) -> bool:
	var turns_clockwise := false
	var turns_counter_clockwise := false
	for i in range(outline.size()):
		var before := outline[i]
		var corner := outline[(i + 1) % outline.size()]
		var after := outline[(i + 2) % outline.size()]
		var turn := (corner - before).cross(after - corner)
		if turn > 0.001:
			turns_counter_clockwise = true
		elif turn < -0.001:
			turns_clockwise = true
		if turns_clockwise and turns_counter_clockwise:
			return false
	return true

## Largest scale that keeps every painted part inside the tile — 1.0 when the
## marker already fits, and never more, so a marker that fits keeps its size; 0.0
## when the tile is too small to hold anything. `edges` are the tile's outward edge
## lines and `parts` the painted pieces, each with the radius of its pen. Points are
## relative to the tile centre, and a pen shrinks with the marker (the painter
## scales its own line widths), so a part reaches `normal·point + pen` toward an
## edge, where the room left is `gap`.
static func fit_scale(edges: Array, parts: Array, centre: Vector2, inset: float) -> float:
	var scale := 1.0
	for edge in edges:
		var normal: Vector2 = edge.normal
		var gap: float = -(normal.dot(centre) + edge.offset) - inset
		if gap <= 0.0:
			return 0.0
		for part in parts:
			var pen: float = part.pen
			for point in part.points:
				var reach: float = normal.dot(point) + pen
				if reach > 0.0:
					scale = minf(scale, gap / reach)
	return clampf(scale, 0.0, 1.0)

## The outline of a tile as outward edge lines: {"normal": Vector2, "offset":
## float}, with the tile's inside at `normal·p + offset < 0`. Corner elevations
## move these edges, so the fit follows the grass the tile really paints. Empty
## when the outline folds over itself and there is no inside to speak of.
func _tile_edges(tee: Vector2i, centre: Vector2) -> Array:
	var edges: Array = []
	var outline := PackedVector2Array()
	for point in terrain_grid.tile_polygon(tee):
		outline.append(to_local(point))
	if not _is_convex(outline):
		return edges
	for i in range(outline.size()):
		var from := outline[i]
		var to := outline[(i + 1) % outline.size()]
		var along := to - from
		if along.length() < 0.001:
			continue
		var normal := Vector2(along.y, -along.x).normalized()
		var offset := -normal.dot(from)
		if normal.dot(centre) + offset > 0.0:
			normal = -normal  # Face the line outward, away from the tile centre.
			offset = -offset
		edges.append({"normal": normal, "offset": offset})
	return edges

## A local copy of the shaft, cut back to where the arrow head covers it.
static func trim_to_head(shaft: PackedVector2Array, overlap: float) -> PackedVector2Array:
	if shaft.size() < 2:
		return shaft
	var trimmed := PackedVector2Array()
	for i in range(shaft.size() - 1):
		trimmed.append(shaft[i])
	var tip := shaft[shaft.size() - 1]
	var stop := tip + direction(tip, shaft[shaft.size() - 2]) * overlap
	if trimmed[trimmed.size() - 1].distance_to(stop) >= MIN_SEGMENT:
		trimmed.append(stop)
	return trimmed

## Centre of the box that holds both painted parts of the arrow.
static func _bounds_centre(shaft: PackedVector2Array, head: PackedVector2Array) -> Vector2:
	var bounds := Rect2(shaft[0], Vector2.ZERO)
	for point in shaft:
		bounds = bounds.expand(point)
	for point in head:
		bounds = bounds.expand(point)
	return bounds.get_center()

static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var closed := PackedVector2Array()
	for point in points:
		closed.append(point)
	closed.append(points[0])
	return closed

func _flat_point(pos: Vector2i) -> Vector2:
	return to_local(terrain_grid.projection.project(Vector2(pos) + Vector2(0.5, 0.5)))
