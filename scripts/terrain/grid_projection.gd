extends RefCounted
class_name GridProjection
## GridProjection - Maps simulation grid coordinates onto world/screen space.

const ORIENTATION_COUNT: int = 4

var grid_size: Vector2i = Vector2i(128, 128)
var tile_size: Vector2 = Vector2(64, 32)
var isometric: bool = true
var orientation: int = 0

# Cached projection state, rebuilt whenever an input above changes.
var _center := Vector2.ZERO
var _origin := Vector2.ZERO
var _axis_x := Vector2.ZERO
var _axis_y := Vector2.ZERO
var _bounds := Rect2()
var _dirty := true

func _init(size: Vector2i = Vector2i(128, 128), tile: Vector2 = Vector2(64, 32),
		iso: bool = true, facing: int = 0) -> void:
	grid_size = size
	tile_size = tile
	isometric = iso
	orientation = wrapi(facing, 0, ORIENTATION_COUNT)

func configure(size: Vector2i, tile: Vector2) -> void:
	grid_size = size
	tile_size = tile
	_dirty = true

func _ensure_fresh() -> void:
	if _dirty:
		_refresh()

## Rotate a point-space offset by `steps` quarter turns.
func _rotate(offset: Vector2, steps: int) -> Vector2:
	match steps % ORIENTATION_COUNT:
		1:
			return Vector2(-offset.y, offset.x)
		2:
			return Vector2(-offset.x, -offset.y)
		3:
			return Vector2(offset.y, -offset.x)
		_:
			return offset

func _refresh() -> void:
	_center = Vector2(grid_size.x * 0.5, grid_size.y * 0.5)

	var rx := _rotate(Vector2(1, 0), orientation)
	var ry := _rotate(Vector2(0, 1), orientation)
	if isometric:
		var half_w := tile_size.x * 0.5
		var half_h := tile_size.y * 0.5
		_axis_x = Vector2((rx.x - rx.y) * half_w, (rx.x + rx.y) * half_h)
		_axis_y = Vector2((ry.x - ry.y) * half_w, (ry.x + ry.y) * half_h)
	else:
		_axis_x = Vector2(rx.x * tile_size.x, rx.y * tile_size.y)
		_axis_y = Vector2(ry.x * tile_size.x, ry.y * tile_size.y)

	var half := _rotate(_center, orientation)
	half = Vector2(absf(half.x), absf(half.y))
	if isometric:
		var span := half.x + half.y
		_bounds = Rect2(Vector2.ZERO, Vector2(span * tile_size.x, span * tile_size.y))
	else:
		_bounds = Rect2(Vector2.ZERO,
				Vector2(half.x * 2.0 * tile_size.x, half.y * 2.0 * tile_size.y))
	_origin = _bounds.get_center()
	_dirty = false

func project(grid_pos: Vector2) -> Vector2:
	_ensure_fresh()
	var r := _rotate(grid_pos - _center, orientation)
	if isometric:
		return _origin + Vector2(
				(r.x - r.y) * tile_size.x * 0.5,
				(r.x + r.y) * tile_size.y * 0.5)
	return _origin + Vector2(r.x * tile_size.x, r.y * tile_size.y)


## Fractional grid-space point for a world position. Exact inverse of project().
func unproject(world_pos: Vector2) -> Vector2:
	_ensure_fresh()
	var d := world_pos - _origin
	var r: Vector2
	if isometric:
		var a := d.x / (tile_size.x * 0.5)
		var b := d.y / (tile_size.y * 0.5)
		r = Vector2((a + b) * 0.5, (b - a) * 0.5)
	else:
		r = Vector2(d.x / tile_size.x, d.y / tile_size.y)
	return _rotate(r, ORIENTATION_COUNT - orientation) + _center

func cell_corner(cell: Vector2i) -> Vector2:
	return project(Vector2(cell))

func cell_center(cell: Vector2i) -> Vector2:
	return project(Vector2(cell) + Vector2(0.5, 0.5))

func cell_polygon(cell: Vector2i) -> PackedVector2Array:
	var p := Vector2(cell)
	return PackedVector2Array([
		project(p),
		project(p + Vector2(1, 0)),
		project(p + Vector2(1, 1)),
		project(p + Vector2(0, 1)),
	])

func cell_world_rect(cell: Vector2i) -> Rect2:
	var poly := cell_polygon(cell)
	var rect := Rect2(poly[0], Vector2.ZERO)
	for i in range(1, poly.size()):
		rect = rect.expand(poly[i])
	return rect

func world_to_cell(world_pos: Vector2) -> Vector2i:
	var g := unproject(world_pos)
	return Vector2i(floori(g.x), floori(g.y))

func grid_origin() -> Vector2:
	_ensure_fresh()
	return project(Vector2.ZERO)

func axis_x() -> Vector2:
	_ensure_fresh()
	return _axis_x

func axis_y() -> Vector2:
	_ensure_fresh()
	return _axis_y

func world_bounds() -> Rect2:
	_ensure_fresh()
	return _bounds

func rotate_cw() -> void:
	set_orientation(orientation + 1)

func rotate_ccw() -> void:
	set_orientation(orientation - 1)

func set_orientation(facing: int) -> void:
	orientation = wrapi(facing, 0, ORIENTATION_COUNT)
	_dirty = true

func set_isometric(enabled: bool) -> void:
	isometric = enabled
	_dirty = true
