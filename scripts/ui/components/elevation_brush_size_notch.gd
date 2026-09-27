extends Control
class_name ElevationBrushSizeNotch
## The Elevation Brush size stepper drawn as a half-size selector diamond
## nestled into the V above the point where the Elevation tab's Flat Square and
## Gradual Square tiles meet (see TileHoneycomb.set_notch_child) — the same
## notch treatment the Open Hole action gets on the Course Terrain tab. The
## shape toggle takes the V below those two tiles (see
## ElevationBrushNotchButton).
##
## Three flush cells — smaller, the size the tool paints with, bigger — sit
## centred in the diamond, so the whole stepper reads as one control in the
## notch. The plate itself ignores the cursor (MOUSE_FILTER_IGNORE) so the empty
## corners of its bounding box fall through to the tiles behind it, and only the
## cells answer to the mouse.

## Half a selector diamond, like the shape toggle's cell beside it: the two
## notch cells split the gap between the Square tiles into a V above and a V
## below the point where they meet.
const NOTCH_SIZE := ElevationSelectorButton.SELECTOR_TILE_SIZE * 0.5
## The stepper's cells: smaller / the size it paints with / bigger. They are held
## narrow enough to sit inside the diamond at their own height.
const STEP_CELL := Vector2(20, 18)
const SIZE_CELL := Vector2(28, 18)
const CELL_GAP := 4.0
const STEP_FONT_SIZE := UIConstants.FONT_SIZE_SM
## How far the diamond's shadow falls, matching the course tiles.
const SHADOW_OFFSET := Vector2(0, 2)

const COLOR_FACE_DISABLED := Color("1b2b24")
const COLOR_SHADOW := Color(0, 0, 0, 0.35)
const COLOR_RING_HOVER := Color("f7e0a6")     # Brighter gold under the cursor
const COLOR_RING_DISABLED := Color(0.35, 0.35, 0.35, 0.6)

## The stepper's cells, wired by the toolbar to the Elevation Brush state (see
## TerrainToolbar._make_elevation_brush_size_notch). They exist as soon as the
## notch is created, so they can be wired before it is laid out.
var decrease_button: Button
var size_label: Label
var increase_button: Button

## A Control has no `disabled` of its own (that is BaseButton's), so the notch
## carries one in case the toolbar greys it out. Size and shape stay enabled
## even when neither Square tool is selected.
var disabled := false

func _init() -> void:
	# The plate is only a frame for the cells: it must not swallow clicks meant
	# for the selector tiles in the corners of its bounding box.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = NOTCH_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	decrease_button = _make_step("-", "BrushSmallerStep")
	size_label = _make_size_readout()
	increase_button = _make_step("+", "BrushBiggerStep")
	add_child(decrease_button)
	add_child(size_label)
	add_child(increase_button)
	resized.connect(_layout_cells)
	_layout_cells()

func _ready() -> void:
	# A Control takes its minimum size when it joins the tree, which is measured
	# before its own theme overrides land, so the cells are re-seated once they
	# are really laid out (and again whenever the notch itself is re-sized).
	_layout_cells()

func _make_step(caption: String, node_name: String) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = caption
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", STEP_FONT_SIZE)
	_style_cell(btn, STEP_CELL)
	return btn

## The size the selected Square tool paints with, read out between the two
## steps. It is not a button: it only reports what a click on either side of it
## will paint with.
func _make_size_readout() -> Label:
	var label := Label.new()
	label.name = "BrushSizeReadout"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", STEP_FONT_SIZE)
	label.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
	label.custom_minimum_size = SIZE_CELL
	return label

## Give a stepper cell its own flush footprint. The theme's button styleboxes
## carry content margins of their own, which would push the caption off-centre in
## a cell this small, so the notch draws its own instead — the same treatment the
## pinned brush dock gives its cells (see TerrainToolbar._style_dock_cell).
func _style_cell(control: Control, cell_size: Vector2) -> void:
	control.custom_minimum_size = cell_size
	var faces := {
		"normal": UIConstants.COLOR_BG_BUTTON,
		"hover": UIConstants.COLOR_BG_HOVER,
		"pressed": UIConstants.COLOR_PRIMARY_PRESSED,
		"hover_pressed": UIConstants.COLOR_PRIMARY_PRESSED,
		"focus": UIConstants.COLOR_BG_BUTTON,
		"disabled": UIConstants.COLOR_BG_DARK,
	}
	for state in faces:
		var box := StyleBoxFlat.new()
		box.bg_color = faces[state]
		box.corner_radius_top_left = 3
		box.corner_radius_top_right = 3
		box.corner_radius_bottom_right = 3
		box.corner_radius_bottom_left = 3
		for margin in ["content_margin_left", "content_margin_top",
				"content_margin_right", "content_margin_bottom"]:
			box.set(margin, 0.0)
		control.add_theme_stylebox_override(state, box)
	if control is Button:
		control.add_theme_color_override("font_disabled_color", UIConstants.COLOR_TEXT_MUTED)

## Centre the three cells in the diamond: one row, the size readout between the
## two steps. Laid out from the notch's own size so it survives a re-layout.
func _layout_cells() -> void:
	var box := size if size.x > 0.0 and size.y > 0.0 else NOTCH_SIZE
	var row_width := STEP_CELL.x + CELL_GAP + SIZE_CELL.x + CELL_GAP + STEP_CELL.x
	var left := (box.x - row_width) * 0.5
	var top := (box.y - STEP_CELL.y) * 0.5
	_place(decrease_button, Rect2(left, top, STEP_CELL.x, STEP_CELL.y))
	_place(size_label, Rect2(left + STEP_CELL.x + CELL_GAP, top, SIZE_CELL.x, SIZE_CELL.y))
	_place(increase_button, Rect2(
		left + STEP_CELL.x + CELL_GAP + SIZE_CELL.x + CELL_GAP, top, STEP_CELL.x, STEP_CELL.y))

func _place(cell: Control, rect: Rect2) -> void:
	cell.position = rect.position
	cell.size = rect.size

## Switch the stepper on or off and repaint the diamond around it. The toolbar
## keeps the Elevation Brush enabled even when neither Square tool is selected,
## so the player can set the size before picking Flat or Gradual.
func set_brush_enabled(enabled: bool) -> void:
	disabled = not enabled
	queue_redraw()

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

## The plate lights up with whichever of its cells the cursor is over, so the
## whole stepper reads as one control even though only the cells are clickable.
func _any_cell_active() -> bool:
	for cell in [decrease_button, increase_button]:
		if is_instance_valid(cell) and (cell.is_hovered() or cell.has_focus()):
			return true
	return false

func _face_color() -> Color:
	if disabled:
		return COLOR_FACE_DISABLED
	if _any_cell_active():
		return UIConstants.COLOR_BG_HOVER
	return UIConstants.COLOR_BG_BUTTON

## Gold while the brush can be resized, grey while it cannot.
func _ring_color() -> Color:
	if disabled:
		return COLOR_RING_DISABLED
	return COLOR_RING_HOVER if _any_cell_active() else UIConstants.COLOR_GOLD

func _ring_width() -> float:
	return 2.0 if not disabled and _any_cell_active() else 1.5
