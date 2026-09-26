extends Container
class_name TileHoneycomb
## Lays out isometric tile buttons in interlocking rows.
##
## Every second row is shifted half a tile to the right and half a tile down, so
## its diamonds drop into the notches left between the diamonds of the row above
## — the same way course cells meet on the isometric grid. The tiles themselves
## are diamond-shaped hit targets (TerrainTileButton._has_point), so the rows
## can share bounding boxes without stealing each other's clicks.
##
## A control can also be nestled into a notch of the grid instead of taking a
## tile slot (see set_notch_child): it keeps its own size, sits in the V-shaped
## gap between two neighbouring tiles and shifts nothing along the rows. The
## Open Hole action uses it to sit between the Course Terrain tab's tee and
## green, the pair it opens.

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

## Controls nestled into a notch of the grid instead of taking a slot:
## Control -> the flow slot to the left of the notch it fills.
var _notch_children: Dictionary = {}

func _ready() -> void:
	sort_children.connect(_layout_tiles)

func _get_minimum_size() -> Vector2:
	return _grid_size()

func _layout_tiles() -> void:
	var slot := 0
	for child in get_children():
		if child is Control and child.visible and not _notch_children.has(child):
			fit_child_in_rect(child, Rect2(_position_for(slot), tile_size))
			slot += 1
	_layout_notch_children()

## The children laid out as tiles, in reading order — the order they take their
## slots in. A child nestled into a notch is not a tile (see set_notch_child),
## and a hidden child takes no slot, so neither is listed here.
func flow_children() -> Array[Control]:
	var tiles: Array[Control] = []
	for child in get_children():
		if child is Control and child.visible and not _notch_children.has(child):
			tiles.append(child)
	return tiles

## Nestle `child` into the notch to the right of flow slot `left_slot`: the
## V-shaped gap above the point where that tile and the next one in its row
## meet. The child is added to the honeycomb if it is not already a child, keeps
## its own minimum size (it is centred in the notch cell, see notch_cell_size)
## and takes no slot, so every tile keeps its place along the rows.
func set_notch_child(child: Control, left_slot: int) -> void:
	_notch_children[child] = maxi(0, left_slot)
	if child.get_parent() != self:
		add_child(child)
	queue_sort()

## True when `child` is nestled into a notch rather than laid out as a tile.
func is_notch_child(child: Control) -> bool:
	return _notch_children.has(child)

## Size of one notch — half a column pitch wide by half a tile tall, the child
## cell of the interlocking grid. A nestled child smaller than this keeps the
## honeycomb's own daylight from the two tiles it sits between.
func notch_cell_size() -> Vector2:
	return Vector2(_column_pitch() * 0.5, tile_size.y * 0.5)

## Centre of the notch to the right of flow slot `left_slot`: halfway between
## the right vertex of that tile and the left vertex of the next one, a quarter
## tile below the top of their row.
func notch_centre(left_slot: int) -> Vector2:
	var left := _position_for(left_slot)
	return Vector2(left.x + tile_size.x * 0.5 + _column_pitch() * 0.5,
		left.y + tile_size.y * 0.25)

## Centre every nestled child in its notch at its own size.
func _layout_notch_children() -> void:
	for child in _notch_children:
		if not is_instance_valid(child) or not child.visible or child.get_parent() != self:
			continue
		var notch_size: Vector2 = child.get_combined_minimum_size()
		fit_child_in_rect(child, Rect2(notch_centre(_notch_children[child]) - notch_size * 0.5,
			notch_size))

## Top-left corner of slot `slot`, counting only visible Control children.
func _position_for(slot: int) -> Vector2:
	var row := int(slot / float(columns))
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
	var grid_extent := Vector2.ZERO
	var has_tiles := false
	for child in get_children():
		if child is Control and child.visible and not _notch_children.has(child):
			has_tiles = true
			var bottom_right := _position_for(slot) + tile_size
			grid_extent.x = maxf(grid_extent.x, bottom_right.x)
			grid_extent.y = maxf(grid_extent.y, bottom_right.y)
			slot += 1
	if has_tiles:
		grid_extent.y += v_padding  # The padding above row 1 is already in the positions.
	return grid_extent
