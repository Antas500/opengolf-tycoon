extends TerrainTileButton
class_name ElevationSelectorButton
## An Elevation tab selector drawn as a small diamond of terrain tiles that
## demonstrates what the selector does to the ground:
##  - **vertex**: one grid vertex lifted a single step, its four tiles tilting
##    up to meet it.
##  - **flat**: a square of tiles raised together into a level plateau.
##  - **gradual**: the middle of the square raised into a smooth hill, every
##    neighbouring vertex keeping at most one step of slope.
##
## The button keeps TerrainTileButton's diamond hit area, outline and
## selection treatment; only the artwork inside the diamond differs.

## The selectors are drawn at twice the catalogue tile size so their relief
## demos read clearly and they make large, easy click targets.
const SELECTOR_SCALE := 2.0
const SELECTOR_TILE_SIZE := TILE_SIZE * SELECTOR_SCALE

## Tiles along each side of the preview diamond.
const GRID_TILES := 4
## Screen height of one elevation step in the preview.
const STEP_PX := 6.0 * SELECTOR_SCALE
## The preview diamond is inset a little so raised ground stays inside the
## button, and dropped slightly so peaks have headroom.
const PREVIEW_SCALE := 0.86
const PREVIEW_DROP := 4.0 * SELECTOR_SCALE

const GRASS_COLOR := Color("5f9e45")
const HIGHLIGHT_COLOR := Color(1.0, 0.85, 0.35)

var _art: Node2D

func button_size() -> Vector2:
	return SELECTOR_TILE_SIZE

func _ready() -> void:
	super._ready()
	_build_elevation_art()
	_update_visual_state()

## Vertex heights (in steps) on a (GRID_TILES+1)^2 vertex grid showing the
## selector's effect.
static func example_heights(kind: String) -> Array:
	var n := GRID_TILES + 1
	var heights: Array = []
	var mid := GRID_TILES / 2
	for y in n:
		var row: Array = []
		for x in n:
			var h := 0
			match kind:
				"vertex":
					h = 1 if x == mid and y == mid else 0
				"flat":
					h = 1 if abs(x - mid) <= 1 and abs(y - mid) <= 1 else 0
				"gradual":
					h = maxi(0, 2 - maxi(abs(x - mid), abs(y - mid)))
			row.append(h)
		heights.append(row)
	return heights

## Screen position (local to the button) of grid vertex (x, y) at height h.
static func vertex_point(x: int, y: int, h: float) -> Vector2:
	var tile := SELECTOR_TILE_SIZE * PREVIEW_SCALE / float(GRID_TILES)
	var top := Vector2(SELECTOR_TILE_SIZE.x * 0.5,
		(SELECTOR_TILE_SIZE.y - SELECTOR_TILE_SIZE.y * PREVIEW_SCALE) * 0.5 + PREVIEW_DROP)
	return top + Vector2((x - y) * tile.x * 0.5, (x + y) * tile.y * 0.5 - h * STEP_PX)

func _build_elevation_art() -> void:
	if not tool_type is String:
		return
	_art = Node2D.new()
	_art.name = "ElevationPreviewArt"
	var heights := example_heights(tool_type)
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

## Mark the vertices each selector actually moves.
func _add_markers(heights: Array) -> void:
	var mid := GRID_TILES / 2
	match tool_type:
		"vertex":
			_add_dot(vertex_point(mid, mid, heights[mid][mid]))
		"flat":
			var outline := Line2D.new()
			outline.points = PackedVector2Array([
				vertex_point(mid - 1, mid - 1, 1), vertex_point(mid + 1, mid - 1, 1),
				vertex_point(mid + 1, mid + 1, 1), vertex_point(mid - 1, mid + 1, 1),
				vertex_point(mid - 1, mid - 1, 1)])
			outline.width = 2.5
			outline.default_color = HIGHLIGHT_COLOR
			outline.antialiased = true
			_art.add_child(outline)
		"gradual":
			_add_dot(vertex_point(mid, mid, heights[mid][mid]))

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
