extends TerrainTileButton
class_name ElevationSelectorButton
## An Elevation tab selector drawn as a small diamond of terrain tiles that
## demonstrates what the selector does to the ground. Every demo is a 5x5 tile
## grid with the central 3x3 tiles selected — the Square Selectors' default
## Elevation Brush — outlined in gold. When the shared brush is round, the
## clipped 3x3 footprint is shown as a cross:
##  - **vertex**: one grid vertex lifted a single step, its four tiles tilting
##    up to meet it.
##  - **flat**: the selected 3x3 tiles raised together into a level plateau.
##  - **gradual**: the selected 3x3 tiles raised into a smooth hill, every
##    vertex keeping at most one step of slope.
##
## The button keeps TerrainTileButton's diamond hit area, outline and
## selection treatment; only the artwork inside the diamond differs.

## The selectors are drawn at twice the catalogue tile size so their relief
## demos read clearly and they make large, easy click targets.
const SELECTOR_SCALE := 2.0
const SELECTOR_TILE_SIZE := TILE_SIZE * SELECTOR_SCALE

## Tiles along each side of the preview grid.
const GRID_TILES := 5
## Tiles along each side of the selected block the demos highlight: the
## Square Selectors' default 3x3 Elevation Brush, outlined in gold.
const SELECTED_TILES := 3
## Screen height of one elevation step in the preview.
const STEP_PX := 6.0 * SELECTOR_SCALE
## The preview diamond is inset a little so raised ground stays inside the
## button, and dropped slightly so peaks have headroom.
const PREVIEW_SCALE := 0.86
const PREVIEW_DROP := 4.0 * SELECTOR_SCALE

const GRASS_COLOR := Color("5f9e45")
const HIGHLIGHT_COLOR := Color(1.0, 0.85, 0.35)

var _art: Node2D
var _brush_square := true

## The two Square Selector examples share the toolbar's Square/Circle setting.
## Changing it redraws the selected footprint without changing the Vertex demo.
func set_brush_square(square_shape: bool) -> void:
	if _brush_square == square_shape:
		return
	_brush_square = square_shape
	if is_instance_valid(_art):
		_art.queue_free()
		_art = null
		_build_elevation_art()

func button_size() -> Vector2:
	return SELECTOR_TILE_SIZE

func _ready() -> void:
	super._ready()
	_build_elevation_art()
	_update_visual_state()

## Vertex heights (in steps) on a (GRID_TILES+1)^2 vertex grid showing the
## selector's effect.
static func example_heights(kind: String, square_shape: bool = true) -> Array:
	var n := GRID_TILES + 1
	var heights: Array = []
	var mid := int(GRID_TILES / 2.0)
	for y in n:
		var row: Array = []
		for x in n:
			var h := 0
			match kind:
				"vertex":
					h = 1 if x == mid and y == mid else 0
				"flat":
					h = 1 if _vertex_is_in_selected_tiles(x, y, square_shape) else 0
				"gradual":
					if square_shape:
						h = maxi(0, int((GRID_TILES - _centre_distance_doubled(x, y)) / 2.0))
					elif _vertex_is_in_selected_tiles(x, y, false):
						# The round 3x3 footprint has a 2x2 middle and one-step
						# shoulders on each arm of its cross.
						h = 2 if x >= mid and x <= mid + 1 and y >= mid and y <= mid + 1 else 1
			row.append(h)
		heights.append(row)
	return heights


## True when a preview vertex is a corner of at least one selected tile.
static func _vertex_is_in_selected_tiles(x: int, y: int, square_shape: bool) -> bool:
	var mid := int(GRID_TILES / 2.0)
	for offset in ElevationTool.tile_offsets(SELECTED_TILES, square_shape):
		var tx: int = mid + offset.x
		var ty: int = mid + offset.y
		if x >= tx and x <= tx + 1 and y >= ty and y <= ty + 1:
			return true
	return false


## First and last vertex (per axis) of the selected tile block: the selected
## 3x3 tiles span a 4x4 block of corner vertices.
static func _selected_vertex_range() -> Vector2i:
	var first := int((GRID_TILES - SELECTED_TILES) / 2.0)
	return Vector2i(first, first + SELECTED_TILES)


## Doubled Chebyshev distance from vertex (x, y) to the centre of the preview
## grid. The centre of a 5x5 tile grid falls between vertices, so doubling
## keeps every distance a whole number: 1 = the centre vertices, 3 = the
## selection's rim, 5 = the grid's rim.
static func _centre_distance_doubled(x: int, y: int) -> int:
	return maxi(abs(x * 2 - GRID_TILES), abs(y * 2 - GRID_TILES))

## Screen position (local to the button) of grid vertex (x, y) at height h.
## x and y are floats so spots between vertices (the middle of a tile) can be
## addressed too.
static func vertex_point(x: float, y: float, h: float) -> Vector2:
	var tile := SELECTOR_TILE_SIZE * PREVIEW_SCALE / float(GRID_TILES)
	var top := Vector2(SELECTOR_TILE_SIZE.x * 0.5,
		(SELECTOR_TILE_SIZE.y - SELECTOR_TILE_SIZE.y * PREVIEW_SCALE) * 0.5 + PREVIEW_DROP)
	return top + Vector2((x - y) * tile.x * 0.5, (x + y) * tile.y * 0.5 - h * STEP_PX)

func _build_elevation_art() -> void:
	if not tool_type is String:
		return
	_art = Node2D.new()
	_art.name = "ElevationPreviewArt"
	var heights := example_heights(tool_type, _brush_square)
	# Back to front, so nearer (raised) tiles overlap the ones behind them.
	for d in range(0, GRID_TILES * 2 - 1):
		for x in GRID_TILES:
			var y := d - x
			if y < 0 or y >= GRID_TILES:
				continue
			_add_tile(x, y, heights)
	_add_markers(heights)
	add_child(_art)
	if _name_label:
		move_child(_art, _name_label.get_index())
	# Push the caption below the demo so the relief stays visible.
	if _name_label:
		_name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_name_label.position.y = 4 * SELECTOR_SCALE

func _add_tile(x: int, y: int, heights: Array) -> void:
	var hn: float = heights[y][x]
	var he: float = heights[y][x + 1]
	var hs: float = heights[y + 1][x + 1]
	var hw: float = heights[y + 1][x]
	var corners := PackedVector2Array([
		vertex_point(x, y, hn), vertex_point(x + 1, y, he),
		vertex_point(x + 1, y + 1, hs), vertex_point(x, y + 1, hw),
	])
	# Light from the upper left: slopes facing it brighten, others darken.
	var facing := ((hs + he) - (hn + hw)) * 0.5 + ((hw + hs) - (hn + he)) * 0.5
	var shade := clampf(-facing * 0.14, -0.3, 0.3)
	var color := GRASS_COLOR.lightened(shade) if shade > 0.0 else GRASS_COLOR.darkened(-shade)
	# Checker the grass lightly so each tile reads as its own cell.
	if (x + y) % 2 == 0:
		color = color.lightened(0.05)
	var poly := Polygon2D.new()
	poly.polygon = corners
	poly.color = color
	poly.antialiased = true
	_art.add_child(poly)
	var edge := Line2D.new()
	edge.points = PackedVector2Array([corners[0], corners[1], corners[2], corners[3], corners[0]])
	edge.width = 1.5
	edge.default_color = Color(0.1, 0.2, 0.08, 0.45)
	edge.antialiased = true
	_art.add_child(edge)

## Mark what each selector reshapes: both Square Selectors get a gold outline
## around their selected 3x3 tiles, and the Gradual Selector adds a dot on the
## middle it moves.
func _add_markers(heights: Array) -> void:
	var mid := int(GRID_TILES / 2.0)
	match tool_type:
		"vertex":
			_add_dot(vertex_point(mid, mid, heights[mid][mid]))
		"flat", "gradual":
			_add_selected_tile_outline(heights)
			if tool_type == "gradual":
				# The dot sits on the hilltop, over the middle of the
				# selection — the vertex pair a click raises or lowers.
				_add_dot(vertex_point(GRID_TILES * 0.5, GRID_TILES * 0.5,
						heights[mid][mid]))

## Draw only the exposed edges of the selected tiles. For the round 3x3
## brush this traces a cross instead of the square selector's 3x3 perimeter.
func _add_selected_tile_outline(heights: Array) -> void:
	var mid := int(GRID_TILES / 2.0)
	var sides := [
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, -1)], # north
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 0)],  # east
		[Vector2i(1, 1), Vector2i(0, 1), Vector2i(0, 1)],  # south
		[Vector2i(0, 1), Vector2i(0, 0), Vector2i(-1, 0)], # west
	]
	for offset in ElevationTool.tile_offsets(SELECTED_TILES, _brush_square):
		var tx := mid + offset.x
		var ty := mid + offset.y
		for side in sides:
			var neighbor: Vector2i = Vector2i(tx, ty) + side[2]
			if _is_selected_tile(neighbor.x - mid, neighbor.y - mid, _brush_square):
				continue
			var start: Vector2i = Vector2i(tx, ty) + side[0]
			var finish: Vector2i = Vector2i(tx, ty) + side[1]
			var edge := Line2D.new()
			edge.points = PackedVector2Array([
				vertex_point(start.x, start.y, heights[start.y][start.x]),
				vertex_point(finish.x, finish.y, heights[finish.y][finish.x])])
			edge.width = 2.5
			edge.default_color = HIGHLIGHT_COLOR
			edge.antialiased = true
			_art.add_child(edge)

static func _is_selected_tile(offset_x: int, offset_y: int, square_shape: bool) -> bool:
	return ElevationTool.tile_offsets(SELECTED_TILES, square_shape).has(
			Vector2i(offset_x, offset_y))

func _add_dot(center: Vector2) -> void:
	var dot := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 10:
		var a := i * TAU / 10.0
		pts.append(center + Vector2(cos(a) * 3.0 * SELECTOR_SCALE, sin(a) * 2.0 * SELECTOR_SCALE))
	dot.polygon = pts
	dot.color = HIGHLIGHT_COLOR
	dot.antialiased = true
	_art.add_child(dot)
