extends Control
class_name CompassNeedle
## The needle that stands beside the N / E / S / W letter in the left control
## stack, pointing the way the course is facing.
##
## The letter alone only names the facing; the needle shows it. It takes one
## quarter turn per view rotation — up for N, right for E, down for S, left for
## W — so pressing either Rotate arrow swings the needle a quarter turn the same
## way the course turns, and the two buttons now bracket a little compass
## instead of a bare letter.
##
## Drawn rather than typed for the same reason as the Rotate arrows' sweeps
## (see RotateViewButton): the ring is an arc, the head a triangle, and neither
## depends on the font carrying an arrow glyph.

## The needle occupies a 12x12 slot beside the letter.
const NEEDLE_SIZE := Vector2(12, 12)
## The needle's reach from the pivot: the head's tip sits this far out.
const NEEDLE_LENGTH := 4.8
## Half the head's width across the shaft.
const HEAD_HALF := 2.3
## Thickness of the shaft, and the radius of the pivot dot.
const SHAFT_WIDTH := 1.6
const PIVOT_RADIUS := 1.2
## Share of the needle's length taken by the head, measured from the tip back.
const HEAD_SHARE := 0.35

const COLOR_NEEDLE := UIConstants.COLOR_GOLD          # Matches the compass letter
const COLOR_PIVOT := UIConstants.COLOR_TEXT_DIM

const ORIENTATION_COUNT := 4

## View orientation 0..3 (N, E, S, W). Values outside the range wrap round.
var orientation := 0:
	set(value):
		var next := wrapi(value, 0, ORIENTATION_COUNT)
		if orientation == next:
			return
		orientation = next
		queue_redraw()

func _init() -> void:
	custom_minimum_size = NEEDLE_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Unit vector the needle points along for `orientation`: N up, E right, S down,
## W left. Screen angles grow clockwise, so each step is a quarter turn right.
static func needle_direction(orientation: int) -> Vector2:
	return Vector2.UP.rotated(float(wrapi(orientation, 0, ORIENTATION_COUNT)) * TAU / float(ORIENTATION_COUNT))

## Where the needle's tip lands, relative to the centre of the control.
static func needle_tip(orientation: int, length: float = NEEDLE_LENGTH) -> Vector2:
	return needle_direction(orientation) * length

func _draw() -> void:
	var center := size * 0.5
	var direction := needle_direction(orientation)

	# The needle is symmetrical about its pivot: the tail reaches as far behind
	# it as the head's tip does ahead of it, so turning it never swings it out
	# of its slot.
	var tip := center + needle_tip(orientation)
	var tail := center - direction * NEEDLE_LENGTH
	# Base of the head: the last HEAD_SHARE of the needle, back from the tip.
	var base := center + direction * NEEDLE_LENGTH * (1.0 - HEAD_SHARE * 2.0)
	var across := Vector2(-direction.y, direction.x) * HEAD_HALF

	# Shaft: from the tail, through the pivot, up to the base of the head.
	draw_line(tail, base, COLOR_NEEDLE, SHAFT_WIDTH, true)

	# Head: a triangle whose tip is the point of the whole needle.
	draw_colored_polygon(PackedVector2Array([
		tip,
		base + across,
		base - across,
	]), COLOR_NEEDLE)

	# Pivot: the dot the needle turns on.
	draw_circle(center, PIVOT_RADIUS, COLOR_PIVOT)
