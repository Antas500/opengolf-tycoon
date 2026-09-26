extends Button
class_name BulldozerButton
## The round Bulldozer action button pinned to a toolbar page.
##
## Demolition belongs beside the things it removes, so the Improvements and
## Buildings tabs each pin one of these to their bottom-left corner (see
## TerrainToolbar._build_page) instead of the Bulldozer living among the
## Course Terrain paint tiles. Pressing it toggles bulldozer mode exactly like
## the old tools-column button did (same `bulldozer_pressed` signal, hotkey X
## still works); it only ever demolishes Improvements and Buildings — course
## terrain tiles repaint with other tiles and ignore the bulldozer.
##
## The circle carries a compact side-view bulldozer drawn in UI colors, so the
## tool reads at a glance without sprite assets.

## Fixed diameter: a comfortable click target inside the 190px bottom bar.
const BUTTON_DIAMETER := 46.0
## Distance kept from the page's bottom-left corner.
const CORNER_MARGIN := 10.0

const COLOR_FACE := Color("3d4a42")        # Circle face (deep course green)
const COLOR_FACE_HOVER := Color("4a5a50")
const COLOR_FACE_PRESSED := Color("2e3a33")
const COLOR_RING := Color("6b7a70")        # Resting ring
const COLOR_RING_ACTIVE := Color("f0c419") # Gold ring while bulldozer mode is on
const COLOR_TRACKS := Color("2b2f33")
const COLOR_WHEELS := Color("59616b")
const COLOR_BODY := Color("e8a33d")        # Construction-plant yellow
const COLOR_BODY_DARK := Color("b57f27")
const COLOR_BLADE := Color("c8ced6")       # Steel dozer blade
const COLOR_WINDOW := Color("bfe3f0")

# The button's name/summary for tooltips and assistive tech ride on Button's
# native accessibility_name / accessibility_description properties; the
# toolbar sets them when it pins the button (see TerrainToolbar).

var _is_active := false
var _icon: Control = null

func _init() -> void:
	custom_minimum_size = Vector2(BUTTON_DIAMETER, BUTTON_DIAMETER)
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _ready() -> void:
	_apply_styles()
	_build_icon()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

## True when `point` (local) falls on the circle rather than the bounding box's
## square corners, so clicks just outside the round face fall through to the
## tiles underneath.
func _has_point(point: Vector2) -> bool:
	return point.distance_to(size * 0.5) <= size.x * 0.5

func _create_styles() -> void:
	pass

## Circle face + ring. The ring turns gold while bulldozer mode is active so
## the pinned buttons report the mode the toolbar cannot otherwise show.
func _apply_styles() -> void:
	pass

func _style_for(state: String, face: Color, ring: Color, border: float) -> void:
	pass

func set_active(active: bool) -> void:
	if _is_active == active:
		return
	_is_active = active
	_apply_styles()

func is_active() -> bool:
	return _is_active

## The bulldozer silhouette: tracks, body, cab, exhaust, and the dozer blade
## on its push arm, drawn facing left. Scaled from the fixed 46px design so it
## stays crisp if the button is ever resized.
func _build_icon() -> void:
	if is_instance_valid(_icon):
		return
	_icon = Control.new()
	_icon.name = "BulldozerIcon"
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.custom_minimum_size = Vector2(BUTTON_DIAMETER, BUTTON_DIAMETER)
	_icon.draw.connect(_draw_icon.bind(_icon))
	add_child(_icon)

func _draw_icon(icon: Control) -> void:
	var design := Vector2(BUTTON_DIAMETER, BUTTON_DIAMETER)
	var scale := minf(icon.size.x, icon.size.y) / design.x
	if scale <= 0.0:
		return
	icon.draw_set_transform(
		(icon.size - design * scale) * 0.5, 0.0, Vector2(scale, scale))
	# Everything below is laid out in the fixed 46px design space, baseline at
	# the tracks' bottom edge.
	var base := 32.0

	# Tracks: one dark rounded band with three lighter wheels.
	_box(icon, Rect2(12, base - 7, 22, 7), COLOR_TRACKS, 3.5)
	for wheel_x in [17.5, 23.0, 28.5]:
		icon.draw_circle(Vector2(wheel_x, base - 3.5), 2.1, COLOR_WHEELS)

	# Body sits on the tracks; the cab and exhaust stack above it.
	_box(icon, Rect2(14, 17, 18, 9), COLOR_BODY, 2.0)
	_box(icon, Rect2(22, 10, 10, 8), COLOR_BODY, 2.0)
	_box(icon, Rect2(23.8, 11.8, 6.4, 4.4), COLOR_WINDOW, 1.2)
	_box(icon, Rect2(29.5, 7, 2.2, 3.5), COLOR_TRACKS, 0.8)

	# Blade (left) joined to the body by its push arm.
	_box(icon, Rect2(8.5, 15, 3.6, 17), COLOR_BLADE, 1.6)
	_box(icon, Rect2(12, 19, 3.5, 2.6), COLOR_BODY_DARK, 0.8)

func _box(icon: Control, rect: Rect2, color: Color, corner_radius: float) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = corner_radius
	box.corner_radius_top_right = corner_radius
	box.corner_radius_bottom_right = corner_radius
	box.corner_radius_bottom_left = corner_radius
	icon.draw_style_box(box, rect)

func _on_mouse_entered() -> void:
	_apply_styles()
	if not has_node("/root/TooltipManager"):
		return
	var tm = get_node("/root/TooltipManager")
	tm.show_tooltip({
		"title": "Bulldozer",
		"description": accessibility_description,
		"cost": 0,
		"maintenance": 0,
		"shortcut": "X",
	}, self)

func _on_mouse_exited() -> void:
	_apply_styles()
	if not has_node("/root/TooltipManager"):
		return
	var tm = get_node("/root/TooltipManager")
	tm.hide_tooltip()
