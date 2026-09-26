extends Node2D
class_name WalkingPathOverlay
## WalkingPathOverlay - Renders the Path improvement (Improvements tab).
##
## A walking path is a thin dirt trail laid ON TOP of hostable ground (see
## TerrainTypes.WALKING_PATH_TERRAINS): each tile is a small dirt dot, and
## dots on edge-adjacent tiles join with a slim ribbon, so a trail reads as
## one continuous path. Old full-tile cart paths (TerrainTypes.Type.PATH)
## count as walkable too — a dirt trail touching a cart path continues along
## it. A trail whose connected network reaches the clubhouse is rendered as
## a paved stone promenade instead of dirt.

## Orthogonal sides, also used by the component search below.
const SIDES := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
## Per connector: [direction offset, shared-edge midpoint in tile units,
## perpendicular grid direction for the ribbon half-width].
const CONNECTORS := [
	[Vector2i(1, 0), Vector2(1.0, 0.5), Vector2(0.0, 1.0)],
	[Vector2i(-1, 0), Vector2(0.0, 0.5), Vector2(0.0, 1.0)],
	[Vector2i(0, 1), Vector2(0.5, 1.0), Vector2(1.0, 0.0)],
	[Vector2i(0, -1), Vector2(0.5, 0.0), Vector2(1.0, 0.0)],
]

## Dirt trail (the default walking path).
const DIRT_COLOR := Color(0.58, 0.45, 0.30, 0.95)
const DIRT_DARK := Color(0.42, 0.32, 0.21, 0.9)
const DIRT_LIGHT := Color(0.70, 0.57, 0.42, 0.55)
## Paved promenade (a trail connected to the clubhouse).
const PAVED_COLOR := Color(0.74, 0.70, 0.63, 0.95)
const PAVED_DARK := Color(0.50, 0.47, 0.42, 0.9)
const PAVED_LIGHT := Color(0.87, 0.84, 0.77, 0.6)

## Ribbon half-widths in grid units (0.1 ≈ 3px on screen at zoom 1: thin).
const DIRT_HALF_W := 0.10
const PAVED_HALF_W := 0.13
const PAVED_OUTER_W := 0.17
## Center dot / pad scales (fraction of a tile diagonal).
const DIRT_DOT := 0.10
const PAVED_DOT := 0.13
const PAVED_OUTER_DOT := 0.16

var terrain_grid: TerrainGrid
## Tiles with the walking-path flag, and the subset rendered as paved stone.
var _path_tiles: Dictionary = {}
var _upgraded_tiles: Dictionary = {}
var _is_web: bool = false

func initialize(grid: TerrainGrid) -> void:
	terrain_grid = grid
	z_index = 1  # Above the terrain surface, below entities (z 2).
	_is_web = OS.get_name() == "Web"
	if grid:
		grid.walking_paths_changed.connect(rebuild)
		grid.elevation_changed.connect(_on_elevation_changed)
	EventBus.terrain_tile_changed.connect(_on_terrain_tile_changed)
	EventBus.load_completed.connect(_on_load_completed)
	rebuild()

func _exit_tree() -> void:
	if terrain_grid:
		if terrain_grid.walking_paths_changed.is_connected(rebuild):
			terrain_grid.walking_paths_changed.disconnect(rebuild)
		if terrain_grid.elevation_changed.is_connected(_on_elevation_changed):
			terrain_grid.elevation_changed.disconnect(_on_elevation_changed)
	if GameManager and GameManager.entity_layer:
		var el: Node = GameManager.entity_layer
		if el.has_signal("building_removed") and el.building_removed.is_connected(_on_entity_building_changed):
			el.building_removed.disconnect(_on_entity_building_changed)
		if el.has_signal("building_placed") and el.building_placed.is_connected(_on_entity_building_placed):
			el.building_placed.disconnect(_on_entity_building_placed)
	if EventBus.terrain_tile_changed.is_connected(_on_terrain_tile_changed):
		EventBus.terrain_tile_changed.disconnect(_on_terrain_tile_changed)
	if EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.disconnect(_on_load_completed)

func _on_load_completed(_success: bool) -> void:
	rebuild()

## Cart-path terrain is a walkable node in the network, so painting or
## removing it changes which trails connect (and which reach the clubhouse).
func _on_terrain_tile_changed(_pos: Vector2i, old_type: int, new_type: int) -> void:
	if old_type == TerrainTypes.Type.PATH or new_type == TerrainTypes.Type.PATH:
		rebuild()

## Trails follow the ground, so sculpted elevation must reproject them.
func _on_elevation_changed(_pos: Vector2i, _old: int, _new: int) -> void:
	queue_redraw()

## The entity layer is created after the grid, so hook its building signals
## lazily: a placed or removed clubhouse changes which trails are paved.
func _ensure_entity_connections() -> void:
	if not GameManager or not GameManager.entity_layer:
		return
	var el: Node = GameManager.entity_layer
	if el.has_signal("building_removed") and not el.building_removed.is_connected(_on_entity_building_changed):
		el.building_removed.connect(_on_entity_building_changed)
	if el.has_signal("building_placed") and not el.building_placed.is_connected(_on_entity_building_placed):
		el.building_placed.connect(_on_entity_building_placed)

func _on_entity_building_changed(_grid_pos: Vector2i) -> void:
	rebuild()

func _on_entity_building_placed(_building, _cost: int) -> void:
	rebuild()

## Rescan the walking-path layer and the network it forms. Cheap: the walk
## only visits path tiles, and the course carries few of them.
func rebuild() -> void:
	_ensure_entity_connections()
	_path_tiles.clear()
	_upgraded_tiles.clear()
	if not terrain_grid:
		queue_redraw()
		return
	for pos in terrain_grid.get_walking_paths():
		_path_tiles[pos] = true
	if not _path_tiles.is_empty():
		var is_walkable := func(p: Vector2i) -> bool: return _is_walkable(p)
		_upgraded_tiles = upgraded_component_tiles(
				_path_tiles, is_walkable, _clubhouse_edge_tiles())
	queue_redraw()

## True when a tile is a node of the walking network: it carries the
## walking-path flag, or it is an old full-tile cart path.
func _is_walkable(pos: Vector2i) -> bool:
	if not terrain_grid or not terrain_grid.is_valid_position(pos):
		return false
	return _path_tiles.has(pos) or terrain_grid.get_tile(pos) == TerrainTypes.Type.PATH

## Every tile orthogonally adjacent to a clubhouse footprint — a trail node
## here means the network reaches the clubhouse.
func _clubhouse_edge_tiles() -> Dictionary:
	var edges: Dictionary = {}
	if not GameManager or not GameManager.entity_layer or not terrain_grid:
		return edges
	for building in GameManager.entity_layer.buildings.values():
		if building.building_type != "clubhouse":
			continue
		var origin: Vector2i = building.grid_position
		for x in range(building.width):
			for y in range(building.height):
				var footprint: Vector2i = origin + Vector2i(x, y)
				for side in SIDES:
					var neighbor: Vector2i = footprint + side
					if terrain_grid.is_valid_position(neighbor):
						edges[neighbor] = true
	return edges

## Flood-fill the walking network (4-way) and return the path tiles that
## belong to components touching any tile in `clubhouse_edges`. Kept static
## so the connection rule is unit-testable without a scene.
static func upgraded_component_tiles(path_tiles: Dictionary,
		is_walkable: Callable, clubhouse_edges: Dictionary) -> Dictionary:
	var upgraded: Dictionary = {}
	var visited: Dictionary = {}
	for start in path_tiles.keys():
		if visited.has(start):
			continue
		var component: Array = []
		var frontier: Array = [start]
		visited[start] = true
		while frontier.size() > 0:
			var node: Vector2i = frontier.pop_back()
			component.append(node)
			for side in SIDES:
				var neighbor: Vector2i = node + side
				if not is_walkable.call(neighbor) or visited.has(neighbor):
					continue
				visited[neighbor] = true
				frontier.append(neighbor)
		for node in component:
			if clubhouse_edges.has(node):
				for member in component:
					upgraded[member] = true
				break
	return upgraded

func _draw() -> void:
	if not terrain_grid or _path_tiles.is_empty():
		return
	# Viewport culling: skip tiles whose center is off-screen (with margin).
	var visible_rect = terrain_grid.get_visible_world_rect()
	visible_rect = visible_rect.grow_individual(
			terrain_grid.tile_width, terrain_grid.tile_height,
			terrain_grid.tile_width, terrain_grid.tile_height)
	for pos in _path_tiles.keys():
		var center := to_local(terrain_grid.grid_to_screen_center(pos))
		if not visible_rect.has_point(center):
			continue
		for cmd in tile_draw_commands(pos, _upgraded_tiles.has(pos), not _is_web):
			match cmd.kind:
				"polygon":
					draw_colored_polygon(cmd.points, cmd.color)
				"line":
					draw_line(cmd.a, cmd.b, cmd.color, cmd.width)
				"polyline":
					draw_polyline(cmd.points, cmd.color, cmd.width)
				"circle":
					draw_circle(cmd.center, cmd.radius, cmd.color)

# =============================================================================
# Geometry — computed outside the draw cycle so it can be unit-tested.
# =============================================================================

## One draw command: kind plus its typed payload (see _draw()).
class DrawCommand:
	var kind := "polygon"
	var points: PackedVector2Array
	var a: Vector2
	var b: Vector2
	var center: Vector2
	var radius: float
	var color: Color
	var width: float

static func _cmd(kind: String) -> DrawCommand:
	var c := DrawCommand.new()
	c.kind = kind
	return c

## All draw commands for one trail tile, in local coordinates. `detail`
## trims the decorative passes (outlines, speckles, seams) on the web build.
func tile_draw_commands(pos: Vector2i, upgraded: bool, detail: bool) -> Array:
	var c := _pt(pos, Vector2(0.5, 0.5))
	var xd := _pt(pos, Vector2(1.5, 0.5)) - c
	var yd := _pt(pos, Vector2(0.5, 1.5)) - c
	var cmds: Array = []
	if upgraded:
		cmds.append_array(_paved_commands(pos, c, xd, yd, detail))
	else:
		cmds.append_array(_dirt_commands(pos, c, xd, yd, detail))
	return cmds

## Slim dirt ribbons to each walkable neighbor plus the center dot.
func _dirt_commands(pos: Vector2i, c: Vector2, xd: Vector2, yd: Vector2,
		detail: bool) -> Array:
	var cmds: Array = []
	for conn in CONNECTORS:
		var neighbor: Vector2i = pos + conn[0]
		if not _is_walkable(neighbor):
			continue
		var e := _pt(pos, conn[1])
		var pvec := _pt(pos, Vector2(0.5, 0.5) + conn[2] * DIRT_HALF_W) - c
		var ribbon := _cmd("polygon")
		ribbon.points = _ribbon(c, e, pvec)
		ribbon.color = DIRT_COLOR
		cmds.append(ribbon)
		if detail:
			for side_sign in [1.0, -1.0]:
				var line := _cmd("line")
				line.a = c + pvec * side_sign
				line.b = e + pvec * side_sign
				line.color = DIRT_DARK
				line.width = 1.0
				cmds.append(line)
	var dot := _cmd("polygon")
	dot.points = _diamond(c, xd, yd, DIRT_DOT)
	dot.color = DIRT_COLOR
	cmds.append(dot)
	if detail:
		var outline := _cmd("polyline")
		var pts := _diamond(c, xd, yd, DIRT_DOT)
		pts.append(pts[0])
		outline.points = pts
		outline.color = DIRT_DARK
		outline.width = 1.0
		cmds.append(outline)
		var rng := _deterministic_rng(pos)
		for i in range(3):
			var off := Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
			var speckle := _cmd("circle")
			speckle.center = _pt(pos, Vector2(0.5, 0.5) + off * DIRT_DOT)
			speckle.radius = 1.0
			speckle.color = DIRT_LIGHT
			cmds.append(speckle)
	return cmds

## Stone curb + paver ribbons to each walkable neighbor plus a paved center
## pad with stone seams.
func _paved_commands(pos: Vector2i, c: Vector2, xd: Vector2, yd: Vector2,
		detail: bool) -> Array:
	var cmds: Array = []
	for conn in CONNECTORS:
		var neighbor: Vector2i = pos + conn[0]
		if not _is_walkable(neighbor):
			continue
		var e := _pt(pos, conn[1])
		var pvec := _pt(pos, Vector2(0.5, 0.5) + conn[2] * PAVED_HALF_W) - c
		var outer := _pt(pos, Vector2(0.5, 0.5) + conn[2] * PAVED_OUTER_W) - c
		var curb := _cmd("polygon")
		curb.points = _ribbon(c, e, outer)
		curb.color = PAVED_DARK
		cmds.append(curb)
		var paver := _cmd("polygon")
		paver.points = _ribbon(c, e, pvec)
		paver.color = PAVED_COLOR
		cmds.append(paver)
		if detail:
			for t in [0.35, 0.7]:
				var mid := c.lerp(e, t)
				var seam := _cmd("line")
				seam.a = mid - pvec
				seam.b = mid + pvec
				seam.color = PAVED_LIGHT
				seam.width = 1.0
				cmds.append(seam)
	var ring := _cmd("polygon")
	ring.points = _diamond(c, xd, yd, PAVED_OUTER_DOT)
	ring.color = PAVED_DARK
	cmds.append(ring)
	var pad := _cmd("polygon")
	pad.points = _diamond(c, xd, yd, PAVED_DOT)
	pad.color = PAVED_COLOR
	cmds.append(pad)
	if detail:
		var seam := PAVED_DOT * 0.8
		for along in [xd, yd]:
			var line := _cmd("line")
			line.a = c - along * seam
			line.b = c + along * seam
			line.color = PAVED_LIGHT
			line.width = 1.0
			cmds.append(line)
	return cmds

# =============================================================================
# Projection helpers
# =============================================================================

## Projected point of grid-space point `pos + t` (t in tile units), local.
func _pt(pos: Vector2i, t: Vector2) -> Vector2:
	return to_local(terrain_grid.grid_point_to_screen(Vector2(pos) + t))

## Tile diamond scaled by `scale` around the tile center.
func _diamond(center: Vector2, xd: Vector2, yd: Vector2, scale: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + (xd + yd) * scale,
		center + (-xd + yd) * scale,
		center + (-xd - yd) * scale,
		center + (xd - yd) * scale,
	])

func _ribbon(c: Vector2, e: Vector2, pvec: Vector2) -> PackedVector2Array:
	return PackedVector2Array([c + pvec, e + pvec, e - pvec, c - pvec])

func _deterministic_rng(pos: Vector2i) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = pos.x * 12289 ^ pos.y * 24593
	return rng
