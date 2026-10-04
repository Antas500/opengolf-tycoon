extends Control
class_name CoursePlanPreview
## A top-down site plan of the first course the Start New Game screen is about
## to generate: the parcel block the holes sit on, each hole's fairway from tee
## to green, its water and bunkers, and the starter clubhouse cluster.
##
## The plan is drawn from GeneratedCourse.layout_for(), the same table the
## game paints the course from, so "9 holes" shows the routing the player will
## actually get. With 0 holes it shows the empty plot and a dashed outline of a
## first hole to build. Changing the hole count replays a short draw-in, one
## hole after another.
##
## Drawing goes through `_paint(canvas)` so tests can record it; in the game the
## canvas is the control itself.

const PLOT_BG := Color("143a2b")
const PLOT_EDGE := Color("2f6a4c")
const PARCEL_LINE := Color(1.0, 1.0, 1.0, 0.07)
const FAIRWAY := Color("3c8a56")
const FRINGE := Color("4d9f63")
const GREEN := Color("72c482")
const WATER := Color("3f7fa3")
const SAND := Color("d8c690")
const BUILDING := Color("e9dfc4")
const BUILDING_EDGE := Color("8f876f")
const POLE := Color("ece6d3")
const FLAG := Color("e5c57c")
const MARKER_BG := Color(0.035, 0.09, 0.07, 0.86)
const MARKER_TEXT := Color("f4edd9")
const GHOST := Color(0.91, 0.89, 0.81, 0.42)

## Footprints (tiles) of the starter amenities GeneratedCourse places beside
## the first holes. Mirrors data/buildings.json; only used for drawing.
const AMENITY_SIZES := {
	"clubhouse": Vector2i(4, 4),
	"coffee_house": Vector2i(2, 2),
	"snack_bar": Vector2i(1, 1),
	"restroom": Vector2i(1, 1),
}

## Seconds the draw-in takes, plus a little per hole so 18 do not rush.
const REVEAL_SECONDS := 0.45
const REVEAL_PER_HOLE := 0.03

var hole_count := 0
## 0..1 progress of the draw-in animation (1 = fully drawn).
var _reveal := 1.0
var _tween: Tween

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

## Show the plan for `count` holes. Animates when the preview is on screen and
## `animate` is set; otherwise jumps straight to the finished plan.
func set_hole_count(count: int, animate: bool = true) -> void:
	if count == hole_count and _reveal >= 1.0:
		return
	hole_count = count
	if _tween and _tween.is_valid():
		_tween.kill()
	if animate and is_inside_tree() and is_visible_in_tree():
		_reveal = 0.0
		_tween = create_tween()
		_tween.tween_method(_set_reveal, 0.0, 1.0,
			REVEAL_SECONDS + REVEAL_PER_HOLE * float(GeneratedCourse.layout_for(count).size()))
	else:
		_reveal = 1.0
	queue_redraw()

func _set_reveal(value: float) -> void:
	_reveal = value
	queue_redraw()

func is_revealing() -> bool:
	return _reveal < 1.0

# =============================================================================
# PLAN GEOMETRY (pure; tile offsets from the layout anchor's centre)
# =============================================================================

## Everything needed to draw the plan for `count` holes, in tile units
## measured from the centre of the layout's anchor tile:
##   plot          Rect2  - the parcel block the layout is guaranteed
##   parcel_lines  Array  - offsets of the parcel boundaries inside the block
##   holes         Array  - {tee, green, width, water, bunker} per hole
##   amenities     Array  - {kind, rect} for the starter buildings
static func plan(count: int) -> Dictionary:
	var anchor := GeneratedCourse.get_anchor(count)
	# Up to 9 holes use the central 2x2 parcels (2..3), 18 the 3x3 block
	# (1..3) - see GeneratedCourse.
	var first_parcel := 1 if count >= 18 else 2
	var end_parcel := 4
	var parcel := LandManager.PARCEL_SIZE
	var origin := float(LandManager.GRID_OFFSET + first_parcel * parcel) - (float(anchor.x) + 0.5)
	var extent := float((end_parcel - first_parcel) * parcel)
	var parcel_lines: Array = []
	for p in range(first_parcel + 1, end_parcel):
		parcel_lines.append(float(LandManager.GRID_OFFSET + p * parcel) - (float(anchor.x) + 0.5))
	var holes: Array = []
	for entry in GeneratedCourse.layout_for(count):
		# Optional hazards: a hole has water/bunker only when the generator
		# placed one, so the entry is null rather than a point. Assigned with
		# statements because Vector2 and null are not mutually compatible
		# branches for the ternary operator.
		var water: Variant = null
		if entry.size() > 3 and entry[3] != null:
			water = Vector2(entry[3])
		var bunker: Variant = null
		if entry.size() > 4 and entry[4] != null:
			bunker = Vector2(entry[4])
		holes.append({
			"tee": Vector2(entry[0]),
			"green": Vector2(entry[1]),
			"width": float(entry[2]),
			"water": water,
			"bunker": bunker,
		})
	var amenities: Array = []
	if count > 0:
		for spot in GeneratedCourse.AMENITY_SPOTS:
			var footprint: Vector2i = AMENITY_SIZES.get(spot[0], Vector2i.ONE)
			var offset: Vector2i = spot[1]
			amenities.append({"kind": spot[0], "rect": Rect2(Vector2(offset) - Vector2(0.5, 0.5), Vector2(footprint))})
	return {
		"plot": Rect2(origin, origin, extent, extent),
		"parcel_lines": parcel_lines,
		"holes": holes,
		"amenities": amenities,
	}

# =============================================================================
# DRAWING
# =============================================================================

func _draw() -> void:
	_paint(self)

func _paint(canvas) -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	var data := plan(hole_count)
	var plot: Rect2 = data["plot"]
	var side := minf(size.x, size.y)
	var inset := side * 0.04
	var px := (side - inset * 2.0) / plot.size.x
	var screen_plot := Rect2((size - Vector2(side, side)) * 0.5 + Vector2(inset, inset),
		Vector2(side - inset * 2.0, side - inset * 2.0))
	var to_screen := func(p: Vector2) -> Vector2:
		return screen_plot.position + (p - plot.position) * px

	canvas.draw_colored_polygon(SetupGlyph._rounded_rect(screen_plot, side * 0.05), PLOT_BG)
	canvas.draw_polyline(SetupGlyph._closed(SetupGlyph._rounded_rect(screen_plot, side * 0.05)),
		Color(PLOT_EDGE.r, PLOT_EDGE.g, PLOT_EDGE.b, 0.9), maxf(1.0, side * 0.006), true)
	for line in data["parcel_lines"]:
		var at: float = line
		_dashed(canvas, to_screen.call(Vector2(at, plot.position.y)), to_screen.call(Vector2(at, plot.end.y)),
			PARCEL_LINE, maxf(1.0, side * 0.004), side * 0.025)
		_dashed(canvas, to_screen.call(Vector2(plot.position.x, at)), to_screen.call(Vector2(plot.end.x, at)),
			PARCEL_LINE, maxf(1.0, side * 0.004), side * 0.025)

	var holes: Array = data["holes"]
	if holes.is_empty():
		_paint_ghost_hole(canvas, to_screen, px, side)
		return

	for amenity in data["amenities"]:
		var r: Rect2 = amenity["rect"]
		var top_left: Vector2 = to_screen.call(r.position)
		var screen_rect := Rect2(top_left, r.size * px).grow(-px * 0.12)
		canvas.draw_rect(screen_rect, BUILDING)
		canvas.draw_rect(screen_rect, BUILDING_EDGE, false, maxf(1.0, px * 0.15))

	var count := holes.size()
	var show_numbers := px >= 3.4
	var show_flags := px >= 4.0
	# Fairways, hazards and greens first, markers last so numbers stay on top.
	for i in count:
		var hole: Dictionary = holes[i]
		var progress := _hole_progress(i, count)
		if progress <= 0.0:
			continue
		var tee: Vector2 = to_screen.call(hole["tee"])
		var green: Vector2 = to_screen.call(hole["green"])
		var eased := 1.0 - pow(1.0 - progress, 3.0)
		var end := tee.lerp(green, eased)
		var width: float = maxf(2.0, float(hole["width"]) * px * 0.82)
		canvas.draw_line(tee, end, FAIRWAY, width, true)
		canvas.draw_circle(tee, width * 0.5, FAIRWAY)
		canvas.draw_circle(end, width * 0.5, FAIRWAY)
		if progress >= 0.5:
			var grow := clampf((progress - 0.5) * 2.0, 0.0, 1.0)
			if hole["water"] != null:
				_blob(canvas, to_screen.call(hole["water"]), Vector2(2.3, 1.7) * px * grow, WATER)
			if hole["bunker"] != null:
				_blob(canvas, to_screen.call(hole["bunker"]), Vector2(1.4, 1.0) * px * grow, SAND)
		if progress >= 0.85:
			var pop := clampf((progress - 0.85) / 0.15, 0.0, 1.0)
			canvas.draw_circle(green, px * 2.1 * pop, FRINGE)
			canvas.draw_circle(green, px * 1.65 * pop, GREEN)
			if show_flags and pop >= 1.0:
				var pole_top := green + Vector2(0.0, -px * 3.4)
				canvas.draw_line(green, pole_top, POLE, maxf(1.0, px * 0.22), true)
				canvas.draw_colored_polygon(PackedVector2Array([
					pole_top, pole_top + Vector2(px * 1.7, px * 0.55), pole_top + Vector2(0.0, px * 1.1),
				]), FLAG)
	if show_numbers:
		var font := get_theme_default_font()
		var font_size := int(clampf(px * 1.55, 9.0, 15.0))
		for i in count:
			if _hole_progress(i, count) <= 0.0:
				continue
			var hole: Dictionary = holes[i]
			var tee: Vector2 = to_screen.call(hole["tee"])
			var label := str(i + 1)
			var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var radius := maxf(text_size.x, font.get_height(font_size) * 0.78) * 0.5 + 2.0
			canvas.draw_circle(tee, radius, MARKER_BG)
			canvas.draw_string(font, tee + Vector2(-text_size.x * 0.5, font.get_ascent(font_size) * 0.5 - 1.0),
				label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, MARKER_TEXT)

## How far hole `index` of `count` has drawn in (0..1). Holes start one after
## another and each takes about two holes' worth of the animation.
func _hole_progress(index: int, count: int) -> float:
	if _reveal >= 1.0:
		return 1.0
	return clampf((_reveal * float(count + 2) - float(index)) / 2.0, 0.0, 1.0)

## The empty plot's invitation: a dashed tee-to-green outline of a first hole.
func _paint_ghost_hole(canvas, to_screen: Callable, px: float, side: float) -> void:
	var tee: Vector2 = to_screen.call(Vector2(-11.0, 7.0))
	var green: Vector2 = to_screen.call(Vector2(9.0, -6.0))
	var width := maxf(1.0, side * 0.007)
	_dashed(canvas, tee, green, GHOST, width, side * 0.03)
	var ring := PackedVector2Array()
	for i in 33:
		var angle := TAU * float(i) / 32.0
		ring.append(green + Vector2(cos(angle), sin(angle)) * px * 2.4)
	for i in range(0, 32, 2):
		canvas.draw_line(ring[i], ring[i + 1], GHOST, width, true)
	canvas.draw_rect(Rect2(tee - Vector2(px, px), Vector2(px, px) * 2.0), GHOST, false, width)
	var pole_top := green + Vector2(0.0, -px * 4.2)
	canvas.draw_line(green, pole_top, GHOST, width, true)
	canvas.draw_colored_polygon(PackedVector2Array([
		pole_top, pole_top + Vector2(px * 2.0, px * 0.65), pole_top + Vector2(0.0, px * 1.3),
	]), GHOST)

func _dashed(canvas, from: Vector2, to: Vector2, color: Color, width: float, dash: float) -> void:
	var length := from.distance_to(to)
	if length <= 0.0 or dash <= 0.0:
		return
	var dir := (to - from) / length
	var at := 0.0
	while at < length:
		canvas.draw_line(from + dir * at, from + dir * minf(at + dash, length), color, width, true)
		at += dash * 2.0

func _blob(canvas, center: Vector2, radii: Vector2, color: Color) -> void:
	if radii.x <= 0.5 or radii.y <= 0.5:
		return
	var points := PackedVector2Array()
	for i in 20:
		var angle := TAU * float(i) / 20.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	canvas.draw_colored_polygon(points, color)
