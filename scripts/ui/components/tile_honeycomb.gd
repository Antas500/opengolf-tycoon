extends Container
class_name TileHoneycomb
## Lays out isometric tile buttons in interlocking rows.
##
## Every second row is shifted half a tile to the right and half a tile down, so
## its diamonds drop into the notches left between the diamonds of the row above
## — the same way course cells meet on the isometric grid. The tiles themselves
## are diamond-shaped hit targets (TerrainTileButton._has_point), so the rows
## can share bounding boxes without stealing each other's clicks.

@export var columns: int = 4:
	set(value):
		columns = maxi(1, value)
		queue_sort()

## Size of one tile button (2:1 isometric footprint).
@export var tile_size := TerrainTileButton.BUTTON_SIZE:
	set(value):
		tile_size = value
		queue_sort()

## Gap between neighbouring diamonds in the same row.
@export var h_separation: int = 4:
	set(value):
		h_separation = maxi(0, value)
		queue_sort()

## Extra room between a row and the row tucked into it (0 = diamonds touching).
@export var v_separation: int = 20:
	set(value):
		v_separation = maxi(0, value)
		queue_sort()

## Breathing room kept above the first row and below the last, so the
## interlocking rows never touch the edges of the space they sit in.
@export var v_padding: int = 0:
	set(value):
		v_padding = maxi(0, value)
		queue_sort()

func _ready() -> void:
	sort_children.connect(_layout_tiles)

func _get_minimum_size() -> Vector2:
	return _grid_size()

func _layout_tiles() -> void:
	var slot := 0
	for child in get_children():
		if child is Control and child.visible:
			fit_child_in_rect(child, Rect2(_position_for(slot), tile_size))
			slot += 1

## Top-left corner of slot `slot`, counting only visible Control children.
func _position_for(slot: int) -> Vector2:
	var row := slot // columns
	var column := slot % columns
	return Vector2(column * _column_pitch() + row * _row_shift().x,
		v_padding + row * _row_shift().y)

func _column_pitch() -> float:
	return tile_size.x + h_separation

## Half a tile to the right and half a tile down: the stagger between rows.
func _row_shift() -> Vector2:
	return Vector2(_column_pitch() * 0.5, tile_size.y * 0.5 + v_separation)

## Extent actually covered by the tiles, including the staggered overhang and
## the breathing room above and below the rows.
func _grid_size() -> Vector2:
	var slot := 0
	var grid_size := Vector2.ZERO
	var has_tiles := false
	for child in get_children():
		if child is Control and child.visible:
			has_tiles = true
			var bottom_right := _position_for(slot) + tile_size
			grid_size.x = maxf(grid_size.x, bottom_right.x)
			grid_size.y = maxf(grid_size.y, bottom_right.y)
			slot += 1
	if has_tiles:
		grid_size.y += v_padding  # The padding above row 1 is already in the positions.
	return grid_size
