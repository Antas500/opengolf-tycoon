extends Button
class_name ElevationBrushNotchButton
## One Elevation Brush control drawn as a half-size selector diamond nestled
## into the Elevation tab's selector honeycomb (see TileHoneycomb.set_notch_child)
## — the same treatment the Open Hole action gets on the Course Terrain tab. The
## brush belongs to the two Square Selectors alone, so instead of standing in a
## group of its own beside the row it sits exactly where those two tiles meet:
## this cell takes the V below the point where Flat Square and Gradual Square
## meet, and the size stepper takes the V above it (see
## ElevationBrushSizeNotch).
##
## The diamond is half a selector cell, 2:1 like the grid it drops into, so its
## points line up with the tiles around it. Only the diamond answers to the
## mouse (see _has_point), so the empty corners of its bounding box fall through
## to the tiles behind it. The face carries the control's state as a glyph — the
## shape the brush paints with — over the word naming it, which is as much of the
## name as a cell this small has room for; the hover tooltip and assistive tech
## supply the rest.

## Half a selector diamond. The selectors are twice the catalogue tile size (see
## ElevationSelectorButton.SELECTOR_TILE_SIZE), so half of one is a notch diamond
## that lines up with the grid the same way Open Hole's half cell does.
const NOTCH_SIZE := ElevationSelectorButton.SELECTOR_TILE_SIZE * 0.5
## The glyph drawn on the diamond (the shape the brush paints with), and the
## word beneath it naming the control that glyph stands for.
const CAPTION_FONT_SIZE := UIConstants.FONT_SIZE_XL
const LABEL_FONT_SIZE := UIConstants.FONT_SIZE_XS
const LABEL_TEXT := "SHAPE"
## The glyph rides a little above the middle so the word has room beneath it.
const CAPTION_LIFT := 9.0
const LABEL_DROP := 14.0
## How far the diamond's shadow falls, matching the course tiles.
const SHADOW_OFFSET := Vector2(0, 2)

const COLOR_FACE_DISABLED := Color("1b2b24")
const COLOR_SHADOW := Color(0, 0, 0, 0.35)
const COLOR_RING_HOVER := Color("f7e0a6")     # Brighter gold under the cursor
const COLOR_RING_DISABLED := Color(0.35, 0.35, 0.35, 0.6)
const COLOR_TEXT_DISABLED := Color(0.55, 0.55, 0.55, 0.75)
const COLOR_DISABLED_MODULATE := Color(0.5, 0.5, 0.5, 0.65)

var _hovered := false

## The glyph drawn on the diamond, e.g. "□" for a square brush or "○" for a
## round one. The toolbar sets it as the shape changes (see set_caption).
var caption: String = ""

func _ready() -> void:
	_create_styles()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_update_visual_state)
	focus_exited.connect(_update_visual_state)
	_update_button()

## The diamond and its glyph replace Button's flat label. The honeycomb does the
## sizing: the diamond is centred in its notch at this minimum size.
func _update_button() -> void:
	text = ""
	icon = null
	custom_minimum_size = NOTCH_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_update_visual_state()

func _create_styles() -> void:
	# No rectangular chrome: the diamond is the whole button.
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, empty)

## Set the glyph drawn on the diamond and repaint it.
func set_caption(value: String) -> void:
	caption = value
	queue_redraw()

## Switch the control on or off and repaint it. The toolbar keeps the Elevation
## Brush enabled even when neither Square tool is selected, so the player can
## set the shape before picking Flat or Gradual.
func set_brush_enabled(enabled: bool) -> void:
	disabled = not enabled
	_update_visual_state()

## Repaint the diamond for the state it is in. Everything is drawn in _draw(),
## so this only has to ask for the repaint — the colours follow from `disabled`,
## the hover and the focus, and can never go stale.
func _update_visual_state() -> void:
	modulate = COLOR_DISABLED_MODULATE if disabled else Color(1, 1, 1, 1)
	queue_redraw()

## True when `point` (local to the button) falls on the diamond rather than in
## the empty corners of its bounding box, so a click beside it reaches the
## selector tile underneath.
func _has_point(point: Vector2) -> bool:
	return TerrainTileButton.point_on_tile(point, size)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return  # Not laid out into its notch yet.
	var corners := TerrainTileButton.tile_corners(size)
	var shadow := PackedVector2Array()
	for corner in corners:
		shadow.append(corner + SHADOW_OFFSET)
	draw_colored_polygon(shadow, COLOR_SHADOW)
	draw_colored_polygon(corners, _face_color())
	draw_polyline(PackedVector2Array([corners[0], corners[1], corners[2], corners[3], corners[0]]),
		_ring_color(), _ring_width(), true)
	_draw_text(caption, CAPTION_FONT_SIZE, -CAPTION_LIFT, _caption_color())
	_draw_text(LABEL_TEXT, LABEL_FONT_SIZE, LABEL_DROP, _label_color())

## Draw `text` centred on the diamond, `y_offset` above (negative) or below
## (positive) its middle.
func _draw_text(text: String, font_size: int, y_offset: float, color: Color) -> void:
	var font := get_theme_font("font")
	if font == null or text.is_empty():
		return
	var center := size * 0.5 + Vector2(0.0, y_offset)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	# draw_string() places the text's baseline, so centre the line on the diamond.
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2(center.x - text_size.x * 0.5, baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _face_color() -> Color:
	if disabled:
		return COLOR_FACE_DISABLED
	if _hovered or has_focus():
		return UIConstants.COLOR_BG_HOVER
	return UIConstants.COLOR_BG_BUTTON

## Gold while the brush can be reshaped, grey while it cannot.
func _ring_color() -> Color:
	if disabled:
		return COLOR_RING_DISABLED
	return COLOR_RING_HOVER if _hovered or has_focus() else UIConstants.COLOR_GOLD

func _caption_color() -> Color:
	if disabled:
		return COLOR_TEXT_DISABLED
	return UIConstants.COLOR_TEXT if _hovered or has_focus() else UIConstants.COLOR_GOLD

func _label_color() -> Color:
	if disabled:
		return COLOR_TEXT_DISABLED
	return UIConstants.COLOR_TEXT_DIM

func _ring_width() -> float:
	return 2.0 if not disabled and (_hovered or has_focus()) else 1.5

func _on_mouse_entered() -> void:
	_hovered = true
	_update_visual_state()

func _on_mouse_exited() -> void:
	_hovered = false
	_update_visual_state()
