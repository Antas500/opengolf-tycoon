extends ToolButton
class_name OpenHoleNotchButton
## The Open Hole action drawn as a half-size course cell.
##
## Open Hole pairs the waiting tee box with the waiting green with a hole, so on
## the Course Terrain tab it is nestled into the notch between those two tiles
## (see TileHoneycomb.set_notch_child) instead of standing in the tools column at
## the far left of the tab: the action that joins the tee and the green sits
## exactly where they meet, and the tiles either side of it keep their places in
## the rows. The diamond is half a course cell, so its points line up with the
## grid it drops into — its top point level with the top of the tiles' row and
## its bottom point on the point where the tee box and the green meet — and it
## carries the hotkey chip: a cell this small has no room for the name, which the
## rich hover tooltip and assistive tech supply instead.
##
## Only the diamond answers to the mouse (see _has_point), so the empty corners
## of its bounding box fall through to the tiles behind it. The ring is gold
## while the action is available and grey while no pair is waiting, so the chip
## itself reports whether a hole can be opened.

## The button's diamond: half a course cell (120x60), 2:1 like the grid.
const DIAMOND_SIZE: Vector2 = TerrainTileButton.BUTTON_SIZE * 0.5
## Hotkey chip size. The name doesn't fit on a cell this small.
const CAPTION_FONT_SIZE := UIConstants.FONT_SIZE_SM
## How far the diamond's shadow falls, matching the course tiles.
const SHADOW_OFFSET := Vector2(0, 2)

const COLOR_FACE_DISABLED := Color("1b2b24")
const COLOR_SHADOW := Color(0, 0, 0, 0.35)
const COLOR_RING_HOVER := Color("f7e0a6")     # Brighter gold under the cursor
const COLOR_RING_DISABLED := Color(0.35, 0.35, 0.35, 0.6)
const COLOR_CAPTION_DISABLED := Color(0.55, 0.55, 0.55, 0.75)
const COLOR_DISABLED_MODULATE := Color(0.5, 0.5, 0.5, 0.65)

var _hovered := false

func _ready() -> void:
	super._ready()
	focus_entered.connect(_update_visual_state)
	focus_exited.connect(_update_visual_state)

## The tile and its hotkey chip replace ToolButton's flat label. The honeycomb
## does the sizing: the diamond is centred in its notch at this minimum size.
func _update_button() -> void:
	text = ""
	icon = null
	custom_minimum_size = DIAMOND_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	accessibility_name = tool_name
	accessibility_description = "%s Shortcut %s." % [tool_description, hotkey]
	_update_visual_state()

func _create_styles() -> void:
	# No rectangular chrome: the diamond is the whole button.
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, empty)

func _apply_styles() -> void:
	_update_visual_state()

## Repaint the diamond for the state it is in. Everything is drawn in _draw(),
## so this only has to ask for the repaint — the colours follow from `disabled`,
## the hover and the focus, and can never go stale.
func _update_visual_state() -> void:
	modulate = COLOR_DISABLED_MODULATE if disabled else Color(1, 1, 1, 1)
	queue_redraw()

## The chip drawn on the diamond: the tool's hotkey marker, e.g. "[H]".
func caption() -> String:
	return tool_icon if not tool_icon.is_empty() else hotkey

## The four corners of the diamond filling `box`, top vertex first, clockwise.
static func diamond_corners(box: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(box.x * 0.5, 0.0),
		Vector2(box.x, box.y * 0.5),
		Vector2(box.x * 0.5, box.y),
		Vector2(0.0, box.y * 0.5),
	])

## True when `point` (local to the button) falls on the diamond rather than in
## the empty corners of its bounding box.
static func point_on_diamond(point: Vector2, box: Vector2) -> bool:
	if box.x <= 0.0 or box.y <= 0.0:
		return false
	var offset := (point - box * 0.5).abs()
	return offset.x / (box.x * 0.5) + offset.y / (box.y * 0.5) <= 1.0

func _has_point(point: Vector2) -> bool:
	return OpenHoleNotchButton.point_on_diamond(point, size)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return  # Not laid out into its notch yet.
	var corners := diamond_corners(size)
	var shadow := PackedVector2Array()
	for corner in corners:
		shadow.append(corner + SHADOW_OFFSET)
	draw_colored_polygon(shadow, COLOR_SHADOW)
	draw_colored_polygon(corners, _face_color())
	draw_polyline(PackedVector2Array([corners[0], corners[1], corners[2], corners[3], corners[0]]),
		_ring_color(), _ring_width(), true)
	_draw_caption()

func _draw_caption() -> void:
	var font := get_theme_font("font")
	var chip := caption()
	if font == null or chip.is_empty():
		return
	var center := size * 0.5
	var chip_size := font.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_FONT_SIZE)
	# draw_string() places the text's baseline, so centre the line on the diamond.
	var baseline := center.y + (font.get_ascent(CAPTION_FONT_SIZE) - font.get_descent(CAPTION_FONT_SIZE)) * 0.5
	draw_string(font, Vector2(center.x - chip_size.x * 0.5, baseline), chip,
		HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_FONT_SIZE, _caption_color())

func _face_color() -> Color:
	if disabled:
		return COLOR_FACE_DISABLED
	if is_pressed():
		return UIConstants.COLOR_PRIMARY_PRESSED
	if _hovered or has_focus():
		return UIConstants.COLOR_BG_HOVER
	return UIConstants.COLOR_BG_BUTTON

## Gold while the action can be taken, grey while it cannot.
func _ring_color() -> Color:
	if disabled:
		return COLOR_RING_DISABLED
	return COLOR_RING_HOVER if _hovered or has_focus() or is_pressed() else UIConstants.COLOR_GOLD

func _caption_color() -> Color:
	if disabled:
		return COLOR_CAPTION_DISABLED
	return UIConstants.COLOR_TEXT if _hovered or has_focus() or is_pressed() else UIConstants.COLOR_GOLD

func _ring_width() -> float:
	return 2.0 if not disabled and (_hovered or has_focus() or is_pressed()) else 1.5

func _on_mouse_entered() -> void:
	_hovered = true
	_update_visual_state()
	super._on_mouse_entered()

func _on_mouse_exited() -> void:
	_hovered = false
	_update_visual_state()
	super._on_mouse_exited()
