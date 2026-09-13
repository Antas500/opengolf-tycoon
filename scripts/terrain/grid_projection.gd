extends RefCounted
class_name GridProjection
## GridProjection - Maps simulation grid coordinates onto world/screen space.
##
## Two layouts are supported:
##   * top-down    - the legacy square-tile look
##   * isometric   - 2:1 diamond tiles, the Sid Meier's SimGolf look
##
## Each layout supports four 90-degree view orientations, so the player can spin
## the course and look down a fairway from any corner.
##
## The projection is a pure affine map, which buys two things:
##   * `unproject()` is exact, so mouse picking lands on the tile under the
##     cursor no matter how the view is rotated.
##   * Shaders can invert it per fragment, so the terrain and elevation passes
##     keep sampling their textures along *grid* axes rather than screen axes.
##
## The projected grid always fills the same world rectangle it did in top-down
## mode (top-left at the origin), so camera bounds, the minimap and the land
## boundary keep working without special-casing the rotation.

const ORIENTATION_COUNT: int = 4

## Grid dimensions in tiles.
var grid_size: Vector2i = Vector2i(128, 128)
## Size of one tile in world units. Isometric tiles are 2:1 (64 x 32).
var tile_size: Vector2 = Vector2(64, 32)
## False restores the legacy top-down square-tile layout.
var isometric: bool = true
## View rotation in 90-degree steps, 0..3. Increasing spins the course clockwise.
var orientation: int = 0

# Cached projection state, rebuilt whenever an input above changes.
var _center := Vector2.ZERO  # Point-space centre of the grid.
var _origin := Vector2.ZERO  # World position the projected centre lands on.
var _axis_x := Vector2.ZERO  # World delta for +1 along grid x.
var _axis_y := Vector2.ZERO  # World delta for +1 along grid y.
var _bounds := Rect2()       # World AABB of the whole grid.
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

	# A rotation only permutes which grid axis lands on which world axis, so the
	# extents of the rotated point-space box are the component magnitudes.
	var half := _rotate(_center, orientation)
	half = Vector2(absf(half.x), absf(half.y))
	if isometric:
		# Projected span along each world axis is the sum of both grid extents.
		var span := half.x + half.y
		_bounds = Rect2(Vector2.ZERO, Vector2(span * tile_size.x, span * tile_size.y))
	else:
		_bounds = Rect2(Vector2.ZERO,
				Vector2(half.x * 2.0 * tile_size.x, half.y * 2.0 * tile_size.y))
	_origin = _bounds.get_center()
	_dirty = false


# =============================================================================
# FORWARD / INVERSE
# =============================================================================

## World position of a point in grid space. Whole numbers are tile corners,
## so cell (x, y) spans grid points (x, y) .. (x + 1, y + 1).
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


# =============================================================================
# TILE GEOMETRY
# =============================================================================

func cell_corner(cell: Vector2i) -> Vector2:
	return project(Vector2(cell))


func cell_center(cell: Vector2i) -> Vector2:
	return project(Vector2(cell) + Vector2(0.5, 0.5))


## Cell outline in world space, ordered from the tile's topmost vertex when
## facing 0. A diamond when isometric, a square when top-down.
func cell_polygon(cell: Vector2i) -> PackedVector2Array:
	var p := Vector2(cell)
	return PackedVector2Array([
		project(p),
		project(p + Vector2(1, 0)),
		project(p + Vector2(1, 1)),
		project(p + Vector2(0, 1)),
	])


## World-space AABB of one tile, for cheap viewport culling.
func cell_world_rect(cell: Vector2i) -> Rect2:
	var poly := cell_polygon(cell)
	var rect := Rect2(poly[0], Vector2.ZERO)
	for i in range(1, poly.size()):
		rect = rect.expand(poly[i])
	return rect


## Tile containing a world position. May fall outside the grid; callers clamp.
func world_to_cell(world_pos: Vector2) -> Vector2i:
	var g := unproject(world_pos)
	return Vector2i(floori(g.x), floori(g.y))


# =============================================================================
# SHADER / CAMERA PLUMBING
# =============================================================================

## World position of grid point (0, 0) - the projection's translation term.
func grid_origin() -> Vector2:
	_ensure_fresh()
	return project(Vector2.ZERO)


func axis_x() -> Vector2:
	_ensure_fresh()
	return _axis_x


func axis_y() -> Vector2:
	_ensure_fresh()
	return _axis_y


## World rectangle that contains the entire projected grid.
func world_bounds() -> Rect2:
	_ensure_fresh()
	return _bounds


# =============================================================================
# ROTATION
# =============================================================================

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
