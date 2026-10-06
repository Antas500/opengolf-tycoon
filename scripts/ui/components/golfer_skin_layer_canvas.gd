extends Control
class_name GolferSkinLayerCanvas
## The painting surface of the Edit Golfer Skins screen: one animation sprite
## blown up to whole pixels, with its Re-color Layer drawn over it.
##
## Left-click or drag gives the pixel under the pointer to the active Re-color
## Group, right-click (or shift-click) frees it, and alt-click takes the group
## the pixel already belongs to. The canvas does not edit anything itself - it
## reports the pixel and the screen decides - so the same control can be driven
## by a test without a mouse.
##
## Two views: "Re-color" shows the sprite the way the golfer is drawn with the
## skin's colours, and "Groups" shows the plain artwork under a wash of every
## group, which is how a layer is read at a glance.

## A pixel was painted (left button), freed (right button) or picked (alt-click).
signal cell_painted(cell: Vector2i)
signal cell_erased(cell: Vector2i)
signal cell_picked(cell: Vector2i)

const BACKGROUND := Color(0.020, 0.051, 0.039, 0.92)
const CHECKER_LIGHT := Color(0.075, 0.125, 0.105)
const CHECKER_DARK := Color(0.055, 0.098, 0.082)
const BORDER := Color(0.388, 0.443, 0.353, 0.9)
const GRID_LINE := Color(1, 1, 1, 0.07)
const HOVER_LINE := Color(1, 1, 1, 0.85)
## Cells smaller than this are not worth a grid.
const GRID_MIN_CELL := 5.0
const CHECKER_CELL := 6.0

## The artwork: the raw sprite and, when the skin has been re-coloured, the
## same sprite with the skin's colours on it.
var image: Image = null
var preview_image: Image = null
var layer: GolferSkinLayer = null
## Group id -> Color, for the wash that shows which pixels belong where.
var group_colors: Dictionary = {}
## The group a left-click paints with (0 frees the pixel).
var active_group: int = 0
## Draw the re-coloured sprite (true) or the artwork under group washes.
var show_recolor: bool = true
var show_grid: bool = true
var hover_cell: Vector2i = Vector2i(-1, -1)

var _texture: ImageTexture = null
var _preview_texture: ImageTexture = null
var _painting: bool = false
var _last_painted: Vector2i = Vector2i(-2, -2)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(220, 220)


## Show a sprite and its re-coloured twin.
func set_artwork(raw: Image, preview: Image) -> void:
	image = raw
	preview_image = preview
	_texture = _texture_from(raw)
	_preview_texture = _texture_from(preview)
	queue_redraw()


## Swap in the re-coloured sprite only (a colour or a layer changed).
func set_preview(preview: Image) -> void:
	preview_image = preview
	_preview_texture = _texture_from(preview)
	queue_redraw()


func set_layer(new_layer: GolferSkinLayer) -> void:
	layer = new_layer
	queue_redraw()


static func _texture_from(source: Image) -> ImageTexture:
	if source == null or source.is_empty():
		return null
	return ImageTexture.create_from_image(source)


# =============================================================================
# GEOMETRY (pure, so the mapping can be tested without a mouse)
# =============================================================================

## The square the sprite is drawn in: centred, with a margin, never stretched.
func sprite_rect() -> Rect2:
	var sprite_size := _sprite_size()
	if sprite_size == Vector2.ZERO:
		return Rect2()
	var side := minf(size.x, size.y) - 12.0
	if side <= 0.0:
		return Rect2()
	# Whole pixels per sprite pixel keeps the art crisp at every window size.
	var cell := floorf(side / sprite_size.x)
	if cell < 1.0:
		cell = side / sprite_size.x
	var drawn := Vector2(cell * sprite_size.x, cell * sprite_size.y)
	return Rect2(((size - drawn) * 0.5).floor(), drawn)


func _sprite_size() -> Vector2:
	if image != null and not image.is_empty():
		return Vector2(image.get_width(), image.get_height())
	if layer != null and layer.width > 0 and layer.height > 0:
		return Vector2(layer.width, layer.height)
	return Vector2.ZERO


## How many screen pixels one sprite pixel covers.
func cell_size() -> float:
	var sprite_size := _sprite_size()
	if sprite_size.x <= 0.0:
		return 0.0
	return sprite_rect().size.x / sprite_size.x


## The sprite pixel under a point in this control, or (-1, -1) outside it.
func cell_at(local_position: Vector2) -> Vector2i:
	var rect := sprite_rect()
	var cell := cell_size()
	if rect.size == Vector2.ZERO or cell <= 0.0:
		return Vector2i(-1, -1)
	var local := local_position - rect.position
	if local.x < 0.0 or local.y < 0.0 or local.x >= rect.size.x or local.y >= rect.size.y:
		return Vector2i(-1, -1)
	return Vector2i(int(local.x / cell), int(local.y / cell))


# =============================================================================
# DRAWING
# =============================================================================

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND, true)
	var rect := sprite_rect()
	if rect.size == Vector2.ZERO:
		return
	_draw_checkerboard(rect)
	var cell := cell_size()
	var texture: ImageTexture = _preview_texture if show_recolor else _texture
	if texture != null:
		# `false` keeps the texture filtered by the node's own setting
		# (nearest, set by the screen) so the sprite stays pixel-crisp.
		draw_texture_rect(texture, rect, false)
	if layer != null:
		_draw_groups(rect, cell)
	if show_grid and cell >= GRID_MIN_CELL and layer != null:
		_draw_grid(rect, cell)
	draw_rect(rect, BORDER, false, 1.0)
	if layer != null and hover_cell.x >= 0:
		draw_rect(Rect2(rect.position + Vector2(hover_cell) * cell, Vector2(cell, cell)),
			HOVER_LINE, false, 2.0)


func _draw_checkerboard(rect: Rect2) -> void:
	var columns := ceili(rect.size.x / CHECKER_CELL)
	var rows := ceili(rect.size.y / CHECKER_CELL)
	for row in rows:
		for column in columns:
			var corner := rect.position + Vector2(column, row) * CHECKER_CELL
			var patch := Rect2(corner, Vector2(CHECKER_CELL, CHECKER_CELL))
			patch = patch.intersection(rect)
			if patch.size.x <= 0.0 or patch.size.y <= 0.0:
				continue
			var light := (row + column) % 2 == 0
			draw_rect(patch, CHECKER_LIGHT if light else CHECKER_DARK, true)


## The wash that says which pixels belong to which group. In "Groups" view
## every group shows; in "Re-color" view only the active one does, so the
## player can still see what their next stroke reaches.
func _draw_groups(rect: Rect2, cell: float) -> void:
	for y in layer.height:
		for x in layer.width:
			var group_id := layer.get_cell(x, y)
			if group_id == GolferSkinLayer.NO_GROUP:
				continue
			if show_recolor and group_id != active_group:
				continue
			var color: Color = group_colors.get(group_id, Color.WHITE)
			# Under a group wash every group shows at half strength and the
			# active one at full; over the re-coloured sprite only the active
			# group is marked, and faintly, so the colours stay readable.
			var alpha := 0.30
			if not show_recolor:
				alpha = 0.85 if group_id == active_group else 0.45
			draw_rect(Rect2(rect.position + Vector2(x, y) * cell, Vector2(cell, cell)),
				Color(color.r, color.g, color.b, alpha), true)


func _draw_grid(rect: Rect2, cell: float) -> void:
	for x in range(1, layer.width):
		var line_x := rect.position.x + float(x) * cell
		draw_line(Vector2(line_x, rect.position.y), Vector2(line_x, rect.end.y), GRID_LINE, 1.0)
	for y in range(1, layer.height):
		var line_y := rect.position.y + float(y) * cell
		draw_line(Vector2(rect.position.x, line_y), Vector2(rect.end.x, line_y), GRID_LINE, 1.0)


# =============================================================================
# INPUT
# =============================================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_update_hover(motion.position)
		# A held button paints: mouse drags and the synthetic strokes TouchInput
		# makes while a finger paints.
		if _painting or (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_report(cell_at(motion.position), false)
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					_painting = true
					_report(cell_at(button.position), button.alt_pressed)
				else:
					_painting = false
					_last_painted = Vector2i(-2, -2)
			MOUSE_BUTTON_RIGHT:
				if button.pressed:
					_report(cell_at(button.position), false, true)
				else:
					_last_painted = Vector2i(-2, -2)
			_:
				return
		get_viewport().set_input_as_handled()


func _update_hover(local_position: Vector2) -> void:
	var cell := cell_at(local_position)
	if cell != hover_cell:
		hover_cell = cell
		queue_redraw()


## Report one cell to the screen: a pick (alt), an erase (right) or a paint.
## A stroke visits each pixel once, so a slow drag does not repaint cells.
func _report(cell: Vector2i, pick: bool, erase: bool = false) -> void:
	if cell.x < 0 or cell == _last_painted:
		return
	_last_painted = cell
	if pick:
		cell_picked.emit(cell)
	elif erase:
		cell_erased.emit(cell)
	else:
		cell_painted.emit(cell)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover_cell = Vector2i(-1, -1)
		_painting = false
		queue_redraw()
