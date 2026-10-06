extends Control
class_name SkinPixelEditor
## SkinPixelEditor - the painting canvas of the Golfer Skin Designer.
##
## Shows one 48x48 frame of a golfer skin blown up, with a grid, and lets the
## player paint it one pixel at a time. What gets painted is not a colour but a
## *part and shade* (shirt / dark, cap / base, ...): the canvas stores part+shade
## indices, and the colours come from the skin's palette. That is the same
## format the art's own part layers use, so a painted pixel and a pixel the
## artist drew are told apart by exactly the same rule.
##
## Left mouse paints, right mouse picks the part under the cursor (an eyedropper,
## so a player can carry on from a pixel they already have - within the parts
## the skin's layer offers).

signal pixels_changed()
signal part_picked(part: String, shade: int)

const CANVAS := GolferSkinLibrary.CANVAS
const ZOOM_STEPS: Array[int] = [4, 6, 8, 10, 12, 16]

var zoom: int = 8
## The part and shade the brush lays down. An empty part erases.
var brush_part: String = "shirt"
var brush_shade: int = 0
var erasing: bool = false
var show_grid: bool = true

var _image: Image = null
var _texture: ImageTexture = null
## part -> PackedColorArray, the colours this frame should be painted with.
var _palette: Dictionary = {}
var _painting := false
var _stroke_touched := false
## The pixel a drag last landed on, so a fast drag still draws a line.
var _last_painted := Vector2i(-1, -1)
## The pixels the current stroke has written: pixel -> stored index.
var _written: Dictionary = {}
var _hover := Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	focus_mode = Control.FOCUS_NONE
	_update_minimum_size()


## Show an image to paint on. The editor keeps the reference and writes to it.
func set_image(source: Image) -> void:
	_image = source
	if _image != null:
		_texture = ImageTexture.create_from_image(_image)
	queue_redraw()


func set_palette(colours: Dictionary) -> void:
	_palette = colours
	queue_redraw()


func palette() -> Dictionary:
	return _palette


func image() -> Image:
	return _image


func set_zoom(value: int) -> void:
	zoom = clampi(value, ZOOM_STEPS[0], ZOOM_STEPS[ZOOM_STEPS.size() - 1])
	_update_minimum_size()
	queue_redraw()


func zoom_in() -> void:
	for step in ZOOM_STEPS:
		if step > zoom:
			set_zoom(step)
			return
	set_zoom(ZOOM_STEPS[ZOOM_STEPS.size() - 1])


func zoom_out() -> void:
	for index in range(ZOOM_STEPS.size() - 1, -1, -1):
		if ZOOM_STEPS[index] < zoom:
			set_zoom(ZOOM_STEPS[index])
			return
	set_zoom(ZOOM_STEPS[0])


func _update_minimum_size() -> void:
	custom_minimum_size = Vector2(CANVAS * zoom, CANVAS * zoom)


## Where the canvas is drawn inside the control.
func _canvas_origin() -> Vector2:
	var art_size := Vector2(CANVAS * zoom, CANVAS * zoom)
	return ((Vector2(self.size) - art_size) * 0.5).floor()


func _pixel_at(local: Vector2) -> Vector2i:
	var offset := local - _canvas_origin()
	return Vector2i(floori(offset.x / zoom), floori(offset.y / zoom))


func _inside(pixel: Vector2i) -> bool:
	return pixel.x >= 0 and pixel.y >= 0 and pixel.x < CANVAS and pixel.y < CANVAS


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hovered := _pixel_at(event.position)
		if hovered != _hover:
			_hover = hovered
			queue_redraw()
		if _painting and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_paint(hovered)
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_painting = true
				_stroke_touched = false
				# A new stroke starts where it is put down, not where the last
				# one ended.
				_last_painted = Vector2i(-1, -1)
				_written.clear()
				_paint(_pixel_at(event.position))
			else:
				_painting = false
				if _stroke_touched:
					pixels_changed.emit()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_pick(_pixel_at(event.position))
			return


## Paint every pixel the mouse passed over, so a fast drag still draws a line.
func _paint(pixel: Vector2i) -> void:
	if _image == null or not _inside(pixel):
		return
	var previous := _last_painted
	if previous.x >= 0 and abs(previous.x - pixel.x) + abs(previous.y - pixel.y) > 1:
		for step in _steps_between(previous, pixel):
			_write(step)
	_write(pixel)
	_last_painted = pixel
	_texture.update(_image)
	queue_redraw()


func _steps_between(from: Vector2i, to: Vector2i) -> Array:
	var steps: Array = []
	var dx := absi(to.x - from.x)
	var dy := absi(to.y - from.y)
	var sx: int = 1 if from.x < to.x else -1
	var sy: int = 1 if from.y < to.y else -1
	var error: int = dx - dy
	var point := from
	while point != to:
		var e2: int = error * 2
		if e2 > -dy:
			error -= dy
			point.x += sx
		if e2 < dx:
			error += dx
			point.y += sy
		steps.append(point)
	return steps


func _write(pixel: Vector2i) -> void:
	var index := 0 if erasing else GolferSkinLibrary.pixel_index(brush_part, brush_shade)
	if erasing:
		_image.set_pixelv(pixel, Color(0, 0, 0, 0))
	else:
		var shades: PackedColorArray = _palette.get(brush_part, GolferSkinLibrary.ramp(Color.WHITE))
		_image.set_pixelv(pixel, shades[clampi(brush_shade, 0, shades.size() - 1)])
	_stroke_touched = true
	_written[pixel] = index


## The pixels this stroke has written, so the designer can store them.
func take_written() -> Dictionary:
	var written := _written.duplicate()
	_written.clear()
	return written


## The eyedropper: take the part and shade of the pixel under the cursor, so a
## player can carry on with a shade they already used.
func _pick(pixel: Vector2i) -> void:
	if _image == null or not _inside(pixel):
		return
	var colour := _image.get_pixelv(pixel)
	if colour.a <= 0.01:
		erasing = true
		queue_redraw()
		return
	var best := {}
	var best_distance := 0.010
	for part in _palette:
		if not GolferSkinLibrary.PAINTABLE_PARTS.has(part):
			continue
		var shades: PackedColorArray = _palette[part]
		for shade in shades.size():
			var d := colour.r - shades[shade].r
			var dg := colour.g - shades[shade].g
			var db := colour.b - shades[shade].b
			var distance := d * d + dg * dg + db * db
			if distance < best_distance:
				best_distance = distance
				best = {"part": part, "shade": shade}
	if best.is_empty():
		return
	brush_part = str(best["part"])
	brush_shade = int(best["shade"])
	erasing = false
	part_picked.emit(brush_part, brush_shade)
	queue_redraw()


func _draw() -> void:
	var origin := _canvas_origin()
	var canvas_size := Vector2(CANVAS * zoom, CANVAS * zoom)
	draw_rect(Rect2(Vector2.ZERO, Vector2(size)), Color(0.06, 0.07, 0.09, 1.0))
	# Checkerboard behind the art, so transparent pixels read as transparent.
	var square := maxi(zoom, 8)
	var light := Color(0.16, 0.18, 0.2, 1.0)
	var dark := Color(0.12, 0.13, 0.15, 1.0)
	for row in int(canvas_size.y / square) + 1:
		for column in int(canvas_size.x / square) + 1:
			var colour := light if (row + column) % 2 == 0 else dark
			draw_rect(Rect2(origin + Vector2(column * square, row * square),
				Vector2(square, square)), colour)
	if _texture != null:
		draw_texture_rect(_texture, Rect2(origin, canvas_size), false)
	if show_grid and zoom >= 8:
		var grid := Color(1, 1, 1, 0.06)
		for step in CANVAS + 1:
			draw_line(origin + Vector2(step * zoom, 0), origin + Vector2(step * zoom, canvas_size.y), grid, 1.0)
			draw_line(origin + Vector2(0, step * zoom), origin + Vector2(canvas_size.x, step * zoom), grid, 1.0)
	draw_rect(Rect2(origin, canvas_size), Color(0, 0, 0, 0.6), false, 1.0)
	if _inside(_hover):
		draw_rect(Rect2(origin + Vector2(_hover * zoom), Vector2(zoom, zoom)),
			Color(1, 1, 1, 0.85), false, 1.0)
