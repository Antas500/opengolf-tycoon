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
## A layer may also carry the sprite's own pixels (`art`). A layer that has never
## been painted with them leaves the artwork exactly as it ships and only says
## which group each pixel belongs to; as soon as the player paints a pixel in the
## studio's Pixels side, the layer's pixels become that sprite's artwork and the
## shipped file is no longer read.
##
## The grid is stored as an editable text file, one file per animation sprite
## (see GolferSkin for the naming and GolferSkinLibrary for where the files
## live):
##
##     # OpenGolf Tycoon golfer skin re-color layer
##     # legend: . = no group, A = Shirt, B = Pants, C = Cap
##     golfer-skin-layer 2
##     size 48 48
##     cells
##     ....CCCC....
##     ...CCCCCC...
##     (48 lines of 48 characters - one character per pixel)
##     # The sprite's own pixels: ------ = transparent, else RRGGBB.
##     art
##     f03366------
##     (48 lines of 48 six-character pixels, only once something is painted)
##
## The legend line is written for the reader only; loading takes the
## character -> group id mapping from its skin's group table, so renaming a
## group never rewrites the grid.
##
## A layer whose sprite has been painted carries a second section after the
## grid - an `art` line and one row of pixels per sprite row, `-` for a
## transparent pixel and its six hex digits otherwise.

## A cell that belongs to no group: the pixel keeps the colour of the artwork.
const NO_GROUP: int = 0
## The character an ungrouped cell is written as.
const EMPTY_SYMBOL: String = "."
## First line of a layer file, and the schema version that follows it.
const FORMAT_TAG: String = "golfer-skin-layer"
const FORMAT_VERSION: int = 2
const SIZE_TAG: String = "size"
const CELLS_TAG: String = "cells"
## Section tag for the sprite's own painted pixels (see golfer-skin-layer 2).
const ART_TAG: String = "art"
## Characters one pixel of the art section takes.
const ART_TOKEN_WIDTH: int = 6
## The token a transparent painted pixel is written as. Every token in the art
## section is this many characters wide, so a row reads in fixed-size chunks.
const ART_EMPTY: String = "------"

## Sprite size in pixels and the row-major grid of group ids (0 = no group).
var width: int = 0
var height: int = 0
var cells: PackedByteArray = PackedByteArray()
## The sprite's own pixels (RGBA8, four bytes per cell), empty while the layer
## leaves the artwork that ships with the game alone. See has_art().
var pixels: PackedByteArray = PackedByteArray()
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
	var resized_art := PackedByteArray()
	if has_art():
		resized_art.resize(new_width * new_height * 4)
	for y in mini(new_height, height):
		for x in mini(new_width, width):
			resized[y * new_width + x] = cells[y * width + x]
			if resized_art.is_empty():
				continue
			for channel in 4:
				resized_art[(y * new_width + x) * 4 + channel] = \
					pixels[(y * width + x) * 4 + channel]
	cells = resized
	pixels = resized_art
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


# =============================================================================
# THE SPRITE'S OWN PIXELS
# =============================================================================

## Whether this layer carries the sprite's artwork itself, i.e. the player has
## painted (or erased) a pixel of it. Until then the sprite is the file that
## ships with the game.
func has_art() -> bool:
	return pixels.size() == width * height * 4 and width > 0 and height > 0


## Take the sprite's pixels into the layer, so they can be painted. Called the
## first time the player paints one: from then on this layer is the sprite.
func begin_art(image: Image) -> void:
	if has_art():
		return
	pixels.resize(width * height * 4)
	if image == null or image.is_empty():
		return
	var sprite := _rgba(image)
	var data := sprite.get_data()
	var sprite_width := sprite.get_width()
	var sprite_height := sprite.get_height()
	for y in mini(sprite_height, height):
		for x in mini(sprite_width, width):
			for channel in 4:
				pixels[(y * width + x) * 4 + channel] = data[(y * sprite_width + x) * 4 + channel]


## The sprite as this layer holds it, or null while it holds none.
func art_image() -> Image:
	if not has_art():
		return null
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, pixels)


## The colour of one painted pixel (transparent when the layer holds no art).
func art_pixel(x: int, y: int) -> Color:
	if not contains(x, y) or not has_art():
		return Color(0, 0, 0, 0)
	var index := (y * width + x) * 4
	return Color8(pixels[index], pixels[index + 1], pixels[index + 2], pixels[index + 3])


## Paint one pixel. A fully transparent colour erases it, which is what the
## studio's right-click does. Returns false when there is nothing to change.
func set_art_pixel(x: int, y: int, color: Color) -> bool:
	if not contains(x, y) or not has_art():
		return false
	var index := (y * width + x) * 4
	var wanted := [
		clampi(int(round(color.r * 255.0)), 0, 255),
		clampi(int(round(color.g * 255.0)), 0, 255),
		clampi(int(round(color.b * 255.0)), 0, 255),
		clampi(int(round(color.a * 255.0)), 0, 255),
	]
	var changed := false
	for channel in 4:
		if pixels[index + channel] != wanted[channel]:
			pixels[index + channel] = wanted[channel]
			changed = true
	return changed


## The cells a brush of this size covers, centred on (x, y): a disc, so a round
## brush stays round on the sprite. Size 1 is the one pixel itself.
func brush_cells(x: int, y: int, size: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	if not contains(x, y):
		return found
	var span := maxi(size, 1)
	if span <= 1:
		found.append(Vector2i(x, y))
		return found
	# The brush is centred on the pixel clicked; an even brush sits half a pixel
	# between pixels instead, so a 2-wide brush covers a 2x2 block, a 3-wide one a
	# plus, and a 5-wide one the classic 21-pixel disc.
	var centre := Vector2(0.5, 0.5) if span % 2 == 0 else Vector2.ZERO
	var radius := (span - 1) * 0.5 + 0.35
	var reach := int(ceil(radius + centre.x))
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if Vector2(dx, dy).distance_to(centre) > radius:
				continue
			if contains(x + dx, y + dy):
				found.append(Vector2i(x + dx, y + dy))
	return found


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
	copy.pixels = pixels.duplicate()
	return copy


func equals(other: GolferSkinLayer) -> bool:
	if other == null or other.width != width or other.height != height:
		return false
	return other.cells == cells and other.pixels == pixels


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
	if has_art():
		lines.append("# The sprite's own pixels: %s = transparent, else RRGGBB." % ART_EMPTY)
		lines.append(ART_TAG)
		for y in height:
			var art_row := PackedStringArray()
			for x in width:
				art_row.append(_art_token((y * width + x) * 4))
			lines.append("".join(art_row))
	return "\n".join(lines) + "\n"


## One painted pixel as text: the transparent token, or its six hex digits.
func _art_token(index: int) -> String:
	if pixels[index + 3] == 0:
		return ART_EMPTY
	return "%02x%02x%02x" % [pixels[index], pixels[index + 1], pixels[index + 2]]


## Parse a layer file. `symbol_to_id` is the skin's group table; characters
## outside it (and out of range) leave the pixel ungrouped and are reported in
## `warnings` instead of failing the load.
static func parse(text: String, symbol_to_id: Dictionary) -> GolferSkinLayer:
	var layer := GolferSkinLayer.new()
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var rows := PackedStringArray()
	var art_rows := PackedStringArray()
	var saw_cells := false
	var saw_art := false
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
		if not saw_art and line == ART_TAG:
			saw_art = true
			continue
		if saw_art:
			art_rows.append(line)
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
	if saw_art:
		layer._read_art(art_rows, grid_width, grid_height)
	return layer


## Read the painted-pixel rows: one token per pixel, six characters wide -
## `------` for a transparent pixel, six hex digits otherwise.
func _read_art(art_rows: PackedStringArray, grid_width: int, grid_height: int) -> void:
	if art_rows.size() != grid_height:
		warnings.append("Expected %d pixel rows, found %d" % [grid_height, art_rows.size()])
	pixels.resize(grid_width * grid_height * 4)
	for y in mini(art_rows.size(), grid_height):
		var row: String = art_rows[y]
		if row.length() < grid_width * ART_TOKEN_WIDTH:
			warnings.append("Row %d has %d pixel characters, expected %d" % [
				y, row.length(), grid_width * ART_TOKEN_WIDTH])
		var tokens := floori(float(row.length()) / ART_TOKEN_WIDTH)
		for x in mini(tokens, grid_width):
			var token := row.substr(x * ART_TOKEN_WIDTH, ART_TOKEN_WIDTH)
			if token.begins_with("-"):
				continue
			if not token.is_valid_hex_number(false):
				warnings.append("Row %d has a pixel that is not hex: %s" % [y, token])
				continue
			var index := (y * grid_width + x) * 4
			var value := token.hex_to_int()
			pixels[index] = (value >> 16) & 0xff
			pixels[index + 1] = (value >> 8) & 0xff
			pixels[index + 2] = value & 0xff
			pixels[index + 3] = 255


# =============================================================================
# RE-COLORING
# =============================================================================

## The brightest channel value each group reaches in this sprite, used as the
## group's reference: its brightest pixel ends up exactly on the group's colour
## and the rest of the group shades down from there. Groups with no pixels in
## this sprite are left out.
func source_maxima(image: Image) -> Dictionary:
	var maxima := {}
	var owned := has_art()
	if not owned and (image == null or image.is_empty()):
		return maxima
	var sprite: Image = null
	if not owned:
		sprite = _rgba(image)
	var data := pixels if owned else sprite.get_data()
	var sprite_width := width if owned else sprite.get_width()
	var sprite_height := height if owned else sprite.get_height()
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


## A re-coloured copy of the sprite: every pixel in a group takes that group's
## colour with the artwork's own shading, every other pixel is left as the sprite
## draws it. The sprite is the layer's own painted art when it has any, else the
## file that ships with the game. `colors` maps group id -> Color, `shades` group
## id -> reference brightness (see source_maxima).
func recolor(image: Image, colors: Dictionary, shades: Dictionary = {}) -> Image:
	var owned := has_art()
	if not owned and (image == null or image.is_empty()):
		return image
	if is_empty():
		# No group re-colours anything: the sprite is the painted art, if any.
		return art_image() if owned else image
	var sprite: Image = null
	if not owned:
		sprite = _rgba(image)
	var sprite_width := width if owned else sprite.get_width()
	var sprite_height := height if owned else sprite.get_height()
	var data := pixels if owned else sprite.get_data()
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
	if not changed and not owned:
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
