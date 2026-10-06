extends RefCounted
class_name GolferSkinLayer
## Golfer Skins Re-color Layer - the grid behind one golfer skin animation sprite.
##
## One cell per pixel of one sprite. A cell either belongs to no Re-color Group
## (NO_GROUP) or names the group id of the skin it belongs to. When a golfer is
## drawn, every pixel whose cell names a group is painted in that group's colour
## while keeping the light and shade of the original artwork, so a whole skin can
## be re-coloured - or re-coloured differently by the player - without touching
## the sprites themselves.
##
## The grid is stored as an editable text file, one file per animation sprite
## (see GolferSkin for the naming and GolferSkinLibrary for where the files
## live):
##
##     # OpenGolf Tycoon golfer skin re-color layer
##     # legend: . = no group, A = Shirt, B = Pants, C = Cap
##     golfer-skin-layer 1
##     size 48 48
##     cells
##     ....CCCC....
##     ...CCCCCC...
##     (48 lines of 48 characters - one character per pixel)
##
## The legend line is written for the reader only; loading takes the
## character -> group id mapping from its skin's group table, so renaming a
## group never rewrites the grid.

## A cell that belongs to no group: the pixel keeps the colour of the artwork.
const NO_GROUP: int = 0
## The character an ungrouped cell is written as.
const EMPTY_SYMBOL: String = "."
## First line of a layer file, and the schema version that follows it.
const FORMAT_TAG: String = "golfer-skin-layer"
const FORMAT_VERSION: int = 1
const SIZE_TAG: String = "size"
const CELLS_TAG: String = "cells"

## Sprite size in pixels and the row-major grid of group ids (0 = no group).
var width: int = 0
var height: int = 0
var cells: PackedByteArray = PackedByteArray()
## Anything odd met while parsing (unknown characters, short rows...). The
## layer still loads; the skin reports these in the editor.
var warnings: PackedStringArray = PackedStringArray()


## An empty layer for a width x height sprite.
static func create(sprite_width: int, sprite_height: int) -> GolferSkinLayer:
	var layer := GolferSkinLayer.new()
	layer.resize(sprite_width, sprite_height)
	return layer


func _init(sprite_width: int = 0, sprite_height: int = 0) -> void:
	resize(sprite_width, sprite_height)


## Size the grid, keeping the cells that still fit.
func resize(sprite_width: int, sprite_height: int) -> void:
	var new_width := maxi(sprite_width, 0)
	var new_height := maxi(sprite_height, 0)
	if new_width == width and new_height == height:
		return
	var resized := PackedByteArray()
	resized.resize(new_width * new_height)
	for y in mini(new_height, height):
		for x in mini(new_width, width):
			resized[y * new_width + x] = cells[y * width + x]
	cells = resized
	width = new_width
	height = new_height


func contains(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


## The group id at a cell, or NO_GROUP when the cell is off the grid.
func get_cell(x: int, y: int) -> int:
	if not contains(x, y):
		return NO_GROUP
	return cells[y * width + x]


## Put a cell in a group (NO_GROUP frees it). Returns false when off the grid.
func set_cell(x: int, y: int, group_id: int) -> bool:
	if not contains(x, y):
		return false
	cells[y * width + x] = clampi(group_id, 0, 255)
	return true


## Free every cell that belongs to `group_id`; returns how many were freed.
func clear_group(group_id: int) -> int:
	if group_id == NO_GROUP:
		return 0
	var cleared := 0
	for index in cells.size():
		if cells[index] == group_id:
			cells[index] = NO_GROUP
			cleared += 1
	return cleared


## Give every cell of the sprite to `group_id`.
func fill(group_id: int) -> void:
	var value := clampi(group_id, 0, 255)
	for index in cells.size():
		cells[index] = value


## Every cell of one connected run that shares `x`, `y`'s group. Transparency
## is a wall, so a fill started on the background cannot swallow the sprite's
## outline; `image` may be null, in which case only the grid bounds the run.
func flood_cells(x: int, y: int, image: Image = null) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	if not contains(x, y):
		return found
	var target := get_cell(x, y)
	var seen := {}
	var queue: Array[Vector2i] = [Vector2i(x, y)]
	seen[Vector2i(x, y)] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		if get_cell(cell.x, cell.y) != target:
			continue
		if _is_transparent(cell, image):
			continue
		found.append(cell)
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := cell + step
			if not contains(next.x, next.y) or seen.has(next):
				continue
			seen[next] = true
			if get_cell(next.x, next.y) != target:
				continue
			if _is_transparent(next, image):
				continue
			queue.append(next)
	return found


func _is_transparent(cell: Vector2i, image: Image) -> bool:
	if image == null or image.is_empty():
		return false
	return image.get_pixel(cell.x, cell.y).a <= 0.01


## How many cells belong to a group (or are free, for NO_GROUP).
func count(group_id: int) -> int:
	var total := 0
	for value in cells:
		if value == group_id:
			total += 1
	return total


## How many cells are in any group.
func marked_count() -> int:
	var total := 0
	for value in cells:
		if value != NO_GROUP:
			total += 1
	return total


func is_empty() -> bool:
	return marked_count() == 0


## The group ids this grid uses, in ascending order.
func used_group_ids() -> Array[int]:
	var used: Array[int] = []
	var seen := {}
	for value in cells:
		if value != NO_GROUP and not seen.has(value):
			seen[value] = true
			used.append(value)
	used.sort()
	return used


## Move every cell of one group into another (used when groups are merged).
func remap_group(from_id: int, to_id: int) -> int:
	var moved := 0
	for index in cells.size():
		if cells[index] == from_id:
			cells[index] = clampi(to_id, 0, 255)
			moved += 1
	return moved


func duplicate_layer() -> GolferSkinLayer:
	var copy := GolferSkinLayer.new(width, height)
	copy.cells = cells.duplicate()
	return copy


func equals(other: GolferSkinLayer) -> bool:
	if other == null or other.width != width or other.height != height:
		return false
	return other.cells == cells


# =============================================================================
# TEXT FILES
# =============================================================================

## The layer as an editable text file. `id_to_symbol` is the skin's group
## table, `legend` (group id -> group name) is written into the header comment
## so the file can be read - and painted - without opening the game.
func serialize(id_to_symbol: Dictionary, legend: Dictionary = {}) -> String:
	var lines := PackedStringArray()
	lines.append("# OpenGolf Tycoon golfer skin re-color layer")
	lines.append("# One character per pixel; %s means the pixel keeps the artwork's own colour."
		% EMPTY_SYMBOL)
	var entries := PackedStringArray()
	for group_id in id_to_symbol:
		if group_id == NO_GROUP:
			continue
		var name := str(legend.get(group_id, ""))
		entries.append("%s = %s" % [id_to_symbol[group_id], name if not name.is_empty() else "group %d" % group_id])
	if not entries.is_empty():
		lines.append("# legend: %s" % ", ".join(entries))
	lines.append("%s %d" % [FORMAT_TAG, FORMAT_VERSION])
	lines.append("%s %d %d" % [SIZE_TAG, width, height])
	lines.append(CELLS_TAG)
	for y in height:
		var row := PackedStringArray()
		for x in width:
			row.append(str(id_to_symbol.get(cells[y * width + x], EMPTY_SYMBOL)))
		lines.append("".join(row))
	return "\n".join(lines) + "\n"


## Parse a layer file. `symbol_to_id` is the skin's group table; characters
## outside it (and out of range) leave the pixel ungrouped and are reported in
## `warnings` instead of failing the load.
static func parse(text: String, symbol_to_id: Dictionary) -> GolferSkinLayer:
	var layer := GolferSkinLayer.new()
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var rows := PackedStringArray()
	var saw_cells := false
	var declared_width := 0
	var declared_height := 0
	for raw_line in lines:
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if not saw_cells:
			var parts := line.split(" ", false)
			if parts[0] == FORMAT_TAG:
				var version := int(parts[1]) if parts.size() > 1 else FORMAT_VERSION
				if version > FORMAT_VERSION:
					layer.warnings.append("Written by a newer version of the game (%d)" % version)
				continue
			if parts[0] == SIZE_TAG and parts.size() >= 3:
				declared_width = int(parts[1])
				declared_height = int(parts[2])
				continue
			if parts[0] == CELLS_TAG:
				saw_cells = true
				continue
			layer.warnings.append("Ignored unknown line: %s" % line.left(32))
			continue
		rows.append(line)
	if not saw_cells:
		layer.warnings.append("No cells: is this a re-color layer file?")
		return layer

	# The grid's own size wins; a missing size line falls back to the rows.
	var grid_width := declared_width
	var grid_height := declared_height
	if grid_width <= 0 or grid_height <= 0:
		grid_height = rows.size()
		grid_width = 0
		for row in rows:
			grid_width = maxi(grid_width, row.length())
	if grid_width <= 0 or grid_height <= 0:
		return layer
	layer.resize(grid_width, grid_height)
	if rows.size() != grid_height:
		layer.warnings.append("Expected %d rows, found %d" % [grid_height, rows.size()])
	for y in mini(rows.size(), grid_height):
		var row: String = rows[y]
		if row.length() != grid_width:
			layer.warnings.append("Row %d has %d cells, expected %d" % [y, row.length(), grid_width])
		for x in mini(row.length(), grid_width):
			var symbol := row[x]
			if symbol == EMPTY_SYMBOL:
				continue
			var group_id: Variant = symbol_to_id.get(symbol, null)
			if group_id == null:
				layer.warnings.append("Unknown group character '%s'" % symbol)
				continue
			layer.set_cell(x, y, int(group_id))
	return layer


# =============================================================================
# RE-COLORING
# =============================================================================

## The brightest channel value each group reaches in this sprite, used as the
## group's reference: its brightest pixel ends up exactly on the group's colour
## and the rest of the group shades down from there. Groups with no pixels in
## this sprite are left out.
func source_maxima(image: Image) -> Dictionary:
	var maxima := {}
	if image == null or image.is_empty():
		return maxima
	var sprite := _rgba(image)
	var sprite_width := sprite.get_width()
	var sprite_height := sprite.get_height()
	var data := sprite.get_data()
	for y in mini(sprite_height, height):
		for x in mini(sprite_width, width):
			var group_id := cells[y * width + x]
			if group_id == NO_GROUP:
				continue
			var index := (y * sprite_width + x) * 4
			if data[index + 3] == 0:
				continue
			var value := maxf(maxf(data[index], data[index + 1]), data[index + 2]) / 255.0
			if value > float(maxima.get(group_id, -1.0)):
				maxima[group_id] = value
	return maxima


## A re-coloured copy of `image`: every pixel in a group takes that group's
## colour with the artwork's own shading, every other pixel is left alone.
## `colors` maps group id -> Color, `shades` group id -> reference brightness
## (see source_maxima); a missing colour leaves the pixel as it is.
func recolor(image: Image, colors: Dictionary, shades: Dictionary = {}) -> Image:
	if image == null or image.is_empty() or is_empty():
		return image
	var sprite := _rgba(image)
	var sprite_width := sprite.get_width()
	var sprite_height := sprite.get_height()
	var data := sprite.get_data()
	var changed := false
	for y in mini(sprite_height, height):
		for x in mini(sprite_width, width):
			var group_id := cells[y * width + x]
			if group_id == NO_GROUP:
				continue
			var color: Variant = colors.get(group_id, null)
			if color == null:
				continue
			var index := (y * sprite_width + x) * 4
			var alpha := data[index + 3]
			if alpha == 0:
				continue
			var brightest_of_group := maxf(float(shades.get(group_id, 1.0)), 0.01)
			var brightest := maxf(maxf(data[index], data[index + 1]), data[index + 2]) / 255.0
			var shade := brightest / brightest_of_group
			var target: Color = color
			data[index] = _channel(target.r * shade)
			data[index + 1] = _channel(target.g * shade)
			data[index + 2] = _channel(target.b * shade)
			changed = true
	if not changed:
		return image
	return Image.create_from_data(sprite_width, sprite_height, false, Image.FORMAT_RGBA8, data)


static func _channel(value: float) -> int:
	return clampi(int(round(minf(value, 1.0) * 255.0)), 0, 255)


## A private RGBA8 copy of `image` the caller may hand to set_data().
static func _rgba(image: Image) -> Image:
	var copy := image.duplicate() as Image
	if copy == null:
		copy = image
	if copy.get_format() != Image.FORMAT_RGBA8:
		copy.convert(Image.FORMAT_RGBA8)
	return copy
