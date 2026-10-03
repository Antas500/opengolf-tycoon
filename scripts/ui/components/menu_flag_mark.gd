extends Control
class_name MenuFlagMark
## The title screen's mark: a ball resting on a green with a flagstick over it.
##
## It is drawn, not typed, for the same reason as the Rotate buttons' arrows
## and the compass needle — the game's font carries no golf glyph, and a
## Unicode flag would render as a blank box on some builds. Drawn shapes look
## the same everywhere and scale to whatever `mark_size` the layout asks for.

const DEFAULT_SIZE := 64.0
## Share of the mark taken by the flagstick, measured from the green up.
const FLAG_HEIGHT_SHARE := 0.52

const GREEN_COLOR := Color("2c6739")
const FRINGE_COLOR := Color("22502d")
const GREEN_RIM := Color("7fb08a")
const POLE_COLOR := Color("e8e2cf")
const FLAG_COLOR := Color("e5c57c")
const CUP_COLOR := Color("0d2119")
const BALL_COLOR := Color("f4edd9")
const BALL_SHADE := Color("c9c2ad")

## Side length of the mark in layout pixels. Setting it resizes the control.
@export var mark_size := DEFAULT_SIZE:
	set(value):
		mark_size = maxf(12.0, value)
		custom_minimum_size = Vector2(mark_size, mark_size)
		queue_redraw()

func _init() -> void:
	custom_minimum_size = Vector2(DEFAULT_SIZE, DEFAULT_SIZE)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var side := minf(size.x, size.y)
	if side <= 1.0:
		return
	var origin := (size - Vector2(side, side)) * 0.5
	var center := origin + Vector2(side * 0.5, side * 0.5)

	# A soft halo so the mark reads on both the light and the dark parts of the
	# backdrop, then the green's fringe and putting surface.
	draw_circle(center, side * 0.5, Color(GREEN_RIM.r, GREEN_RIM.g, GREEN_RIM.b, 0.10))
	var green := origin + Vector2(side * 0.5, side * 0.70)
	_ellipse(green, Vector2(side * 0.44, side * 0.24), FRINGE_COLOR)
	_ellipse(green, Vector2(side * 0.37, side * 0.19), GREEN_COLOR)

	# Flagstick and cloth.
	var pole_base := green + Vector2(-side * 0.06, side * 0.02)
	var pole_top := pole_base - Vector2(0.0, side * FLAG_HEIGHT_SHARE)
	var pole_width := maxf(1.6, side * 0.045)
	draw_line(pole_base, pole_top, POLE_COLOR, pole_width, true)
	draw_colored_polygon(PackedVector2Array([
		pole_top,
		pole_top + Vector2(side * 0.30, side * 0.10),
		pole_top + Vector2(0.0, side * 0.21),
	]), FLAG_COLOR)

	# Cup under the stick, ball beside it.
	_ellipse(pole_base, Vector2(pole_width * 1.5, pole_width * 1.05), CUP_COLOR)
	var ball_center := green + Vector2(side * 0.24, side * 0.02)
	draw_circle(ball_center, side * 0.10, BALL_COLOR)
	draw_circle(ball_center + Vector2(side * 0.03, side * 0.03), side * 0.04, BALL_SHADE)

## Fill an axis-aligned ellipse with a polygon (CanvasItem has no draw_ellipse).
func _ellipse(center: Vector2, radii: Vector2, color: Color, segments: int = 36) -> void:
	var points := PackedVector2Array()
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)
