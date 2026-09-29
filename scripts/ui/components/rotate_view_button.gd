extends Button
class_name RotateViewButton
## One of the two Rotate buttons in the left control stack: a curved arrow that
## sweeps the way the course turns, sitting either side of the compass letter
## (N / E / S / W).
##
## The arrow is *drawn*, not typed. The buttons used to carry the Unicode glyphs
## ⟲ / ⟳ (U+27F2 / U+27F3), but the game's font has no such characters —
## `Font.has_char()` returns false for both — so the pair showed blank faces
## and only the tooltips named them. Everything here is drawn from arcs and a
## triangle instead, so it reads the same in every build: an almost-complete
## ring with a gap at the bottom and an arrow head at the end of the sweep, so
## the head itself says which way the course spins.
##
## `clockwise` picks the sweep: the counter-clockwise button (hotkey Q) draws
## its head on the lower left of the ring, the clockwise one (hotkey Shift+Q)
## mirrors it onto the lower right.

## Snap size: a 28x24 slot, the same footprint the buttons had as text.
const BUTTON_SIZE := Vector2(28, 24)

## Radius of the ring the arrow sweeps round.
const ARROW_RADIUS := 7.5
## Thickness of the ring.
const ARC_WIDTH := 1.8
## The gap left in the ring, centred on the bottom of the circle, in degrees.
## The head of each arrow finishes next to it, pointing into it.
const GAP_DEGREES := 64.0
## Length of the arrow head, and half its width across the shaft.
const HEAD_LENGTH := 4.6
const HEAD_HALF := 2.9
## How much of the head sits outside the ring (the rest overlaps the arc, so
## head and stroke join without a seam).
const HEAD_OVERHANG := 0.55

const COLOR_ARROW := UIConstants.COLOR_TEXT          # Resting: the HUD's parchment
const COLOR_ARROW_HOVER := Color.WHITE               # Lit under the cursor
const COLOR_ARROW_DISABLED := UIConstants.COLOR_TEXT_MUTED

## True for the clockwise button (Shift+Q), false for counter-clockwise (Q).
@export var clockwise := false:
	set(value):
		if clockwise == value:
			return
		clockwise = value
		queue_redraw()

var _hovered := false

func _init() -> void:
	custom_minimum_size = BUTTON_SIZE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# The sweep is the label: no room left for a text caption.
	text = ""

func _ready() -> void:
	# A scene that still carries the old ⟲ / ⟳ text drops it here.
	text = ""
	custom_minimum_size = BUTTON_SIZE
	# With no caption left on the face, the tooltip is the button's only name.
	if accessibility_name.is_empty():
		accessibility_name = tooltip_text
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

## The arrow's sweep, as (start, end) angles in radians. Screen angles grow
## clockwise (y points down), so the counter-clockwise arrow is the same pair
## of angles read backwards.
static func arc_angles(is_clockwise: bool) -> Vector2:
	var start := deg_to_rad(90.0 + GAP_DEGREES * 0.5)
	var end := start + deg_to_rad(360.0 - GAP_DEGREES)
	return Vector2(start, end) if is_clockwise else Vector2(end, start)

## Unit vector the arrow is travelling in where it passes `angle`.
static func travel_direction(angle: float, is_clockwise: bool) -> Vector2:
	return Vector2(-sin(angle), cos(angle)) if is_clockwise else Vector2(sin(angle), -cos(angle))

## Where the arrow head's tip lands, relative to the centre of the ring: the
## first corner of the head.
static func head_tip(radius: float, is_clockwise: bool) -> Vector2:
	return head_corners(radius, is_clockwise)[0]

## The three corners of the arrow head, relative to the centre of the ring:
## the tip first, then the two corners of its base.
static func head_corners(radius: float, is_clockwise: bool) -> PackedVector2Array:
	var angle := arc_angles(is_clockwise).y
	var direction := travel_direction(angle, is_clockwise)
	var on_ring := Vector2(cos(angle), sin(angle)) * radius
	var tip := on_ring + direction * (HEAD_LENGTH * HEAD_OVERHANG)
	var base := on_ring - direction * (HEAD_LENGTH * (1.0 - HEAD_OVERHANG))
	var across := Vector2(-direction.y, direction.x) * HEAD_HALF
	return PackedVector2Array([tip, base + across, base - across])

func _draw() -> void:
	var center := size * 0.5
	# The design radius, shrunk if the button is ever squeezed below its slot,
	# so the ring and its head stay inside the face.
	var radius := minf(ARROW_RADIUS,
		maxf(minf(size.x, size.y) * 0.5 - HEAD_LENGTH * HEAD_OVERHANG - 1.0, 1.0))
	var angles := arc_angles(clockwise)
	var color := _arrow_color()
	draw_arc(center, radius, angles.x, angles.y, 32, color, ARC_WIDTH, true)
	var corners := head_corners(radius, clockwise)
	for i in corners.size():
		corners[i] += center
	draw_colored_polygon(corners, color)

func _arrow_color() -> Color:
	if disabled:
		return COLOR_ARROW_DISABLED
	return COLOR_ARROW_HOVER if _hovered or has_focus() else COLOR_ARROW

func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()

func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()
