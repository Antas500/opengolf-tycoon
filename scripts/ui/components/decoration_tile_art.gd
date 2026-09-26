extends Node2D
class_name DecorationTileArt
## Compact preview of one decoration, drawn inside a DecorationTileButton.
##
## Decoration catalogue tiles use the same isometric diamond as the Course
## Terrain and Buildings tiles, so the preview reuses the drawings the course
## itself uses — `GardenArt` pieces, path furniture and the pixel-art sprites —
## scaled into the middle of the tile so the caption on the diamond stays
## readable on top of them.

const PREVIEW_SIZE := TerrainTileButton.TILE_SIZE
## Garden pieces are drawn around their own origin, roughly 55px wide and 55px
## tall. The base sits in the lower half of the diamond so the piece rises
## through the middle of the tile.
const GARDEN_ANCHOR := Vector2(PREVIEW_SIZE.x * 0.5, PREVIEW_SIZE.y * 0.78)
const GARDEN_SCALE := 0.78
## Path furniture (benches, signage) is low and wide, drawn from its base down
## to the tile.
const FURNITURE_ANCHOR := Vector2(PREVIEW_SIZE.x * 0.5, PREVIEW_SIZE.y * 0.73)
const FURNITURE_SCALE := 1.15
## Pixel-art sprites are square canvases with transparent padding, so they are
## fitted, rather than scaled by a fixed factor, to keep every ornament a
## similar size on its tile.
const SPRITE_BOX := Vector2(58, 44)
const SPRITE_CENTER := Vector2(PREVIEW_SIZE.x * 0.5, PREVIEW_SIZE.y * 0.55)

var decoration_type := ""
var _texture: Texture2D = null

func configure(type: String) -> void:
	decoration_type = type
	_texture = null
	var sprite_path: String = Decoration.SPRITE_PATHS.get(type, "")
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		_texture = load(sprite_path)
	queue_redraw()

## True when the tile has something to show: a hand-drawn garden piece, the
## shared path furniture, or the decoration's pixel-art sprite.
static func has_art(type: String) -> bool:
	if GardenArt.has_art(type) or PathFurniture.has_art(type):
		return true
	var sprite_path: String = Decoration.SPRITE_PATHS.get(type, "")
	return not sprite_path.is_empty() and ResourceLoader.exists(sprite_path)

func _draw() -> void:
	if not has_art(decoration_type):
		return
	# Same order as the catalogue artwork: hand-drawn garden pieces first, then
	# shared path furniture, then the pixel-art sprite as the fallback.
	if GardenArt.has_art(decoration_type):
		draw_set_transform(GARDEN_ANCHOR, 0.0, Vector2.ONE * GARDEN_SCALE)
		GardenArt.draw_piece(self, decoration_type)
	elif PathFurniture.has_art(decoration_type):
		draw_set_transform(FURNITURE_ANCHOR, 0.0, Vector2.ONE * FURNITURE_SCALE)
		PathFurniture.draw_item(self, decoration_type, Vector2i.DOWN)
	elif _texture != null:
		var ratio := minf(SPRITE_BOX.x / _texture.get_width(), SPRITE_BOX.y / _texture.get_height())
		var drawn := _texture.get_size() * ratio
		draw_texture_rect(_texture, Rect2(SPRITE_CENTER - drawn * 0.5, drawn), false)
	draw_set_transform(Vector2.ZERO)
