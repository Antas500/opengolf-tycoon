extends Node2D
class_name CupOverlay
## CupOverlay - Cuts a black hole in the ground under every flag on the course.
##
## Two kinds of flag stand on a cup: the gold pin of a "Green With Hole" tile
## that no tee box has been paired with yet, and the red pin of an open hole.
## Both get the same hole drawn under them, so the pin always has something to
## stand in.
##
## The hole is cut to the golf ball's own size — Ball.BALL_RADIUS across — so
## the black disc is exactly as wide as the ball that drops into it. Laid flat
## on the green it reads as an ellipse squashed the same way the tile under it
## is, never as a circle pasted on the screen.

const HOLE_COLOR := Color(0.0, 0.0, 0.0, 1.0)
## A hair of light around the rim: the black disc is the ball's exact size, and
## the lip of the cut is what keeps it from vanishing into a dark green.
const HOLE_RIM_COLOR := Color(0.96, 0.96, 0.90, 0.8)
const HOLE_RIM_WIDTH := 1.0
const WAITING_PIN_COLOR := Color(0.98, 0.83, 0.25)
const WAITING_POLE_HEIGHT := 30.0
const WAITING_FLAG_LENGTH := 14.0
const SEGMENTS := 16

var _terrain_grid: TerrainGrid = null
var _pins: Array[WindFlag] = []

## The radius the hole is drawn at: the golf ball's, so hole and ball match.
static func hole_radius() -> float:
	return Ball.BALL_RADIUS

func initialize(grid: TerrainGrid) -> void:
	_terrain_grid = grid
	z_index = 6  # Above terrain, below golfers and ball
	if _terrain_grid and not _terrain_grid.cup_tiles_changed.is_connected(_on_cup_tiles_changed):
		_terrain_grid.cup_tiles_changed.connect(_on_cup_tiles_changed)
	EventBus.load_completed.connect(_on_load_completed)
	# An open hole's cup moves with its green, so the holes redrawn here follow
	# the same signals WindFlagOverlay rebuilds its pins on.
	EventBus.hole_created.connect(_on_hole_created)
	EventBus.hole_deleted.connect(_on_hole_changed)
	EventBus.hole_updated.connect(_on_hole_changed)
	_rebuild()

func _exit_tree() -> void:
	if _terrain_grid and _terrain_grid.cup_tiles_changed.is_connected(_on_cup_tiles_changed):
		_terrain_grid.cup_tiles_changed.disconnect(_on_cup_tiles_changed)
	if EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.disconnect(_on_load_completed)
	if EventBus.hole_created.is_connected(_on_hole_created):
		EventBus.hole_created.disconnect(_on_hole_created)
	if EventBus.hole_deleted.is_connected(_on_hole_changed):
		EventBus.hole_deleted.disconnect(_on_hole_changed)
	if EventBus.hole_updated.is_connected(_on_hole_changed):
		EventBus.hole_updated.disconnect(_on_hole_changed)

func _on_cup_tiles_changed() -> void:
	_rebuild()

func _on_hole_created(_hole_number: int, _par: int, _distance_yards: int) -> void:
	queue_redraw()

func _on_hole_changed(_hole_number: int) -> void:
	queue_redraw()

func _on_load_completed(_success: bool) -> void:
	call_deferred("_rebuild")

## Reposition the waiting pins after a view projection change.
func refresh_pin_positions() -> void:
	if not _terrain_grid:
		return
	var cups := _terrain_grid.get_cup_tiles()
	for i in range(_pins.size()):
		var pin := _pins[i]
		if is_instance_valid(pin) and i < cups.size():
			pin.position = _terrain_grid.grid_to_screen_center(cups[i])

## Every tile that carries a hole in the ground: the cups still waiting for a
## tee box, then the cup of each open hole.
func hole_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if not _terrain_grid:
		return tiles
	tiles = _terrain_grid.get_cup_tiles()
	if GameManager.course_data:
		for hole_data in GameManager.course_data.holes:
			var pos: Vector2i = hole_data.hole_position
			if _terrain_grid.is_valid_position(pos) and not tiles.has(pos):
				tiles.append(pos)
	return tiles

func _rebuild() -> void:
	for pin in _pins:
		if is_instance_valid(pin):
			remove_child(pin)
			pin.free()
	_pins.clear()

	if not _terrain_grid:
		queue_redraw()
		return

	for cup_pos in _terrain_grid.get_cup_tiles():
		var pin := WindFlag.new()
		pin.name = "WaitingPin_%d_%d" % [cup_pos.x, cup_pos.y]
		pin._flag_color = WAITING_PIN_COLOR
		pin._pole_height = WAITING_POLE_HEIGHT
		pin._flag_length = WAITING_FLAG_LENGTH
		pin.position = _terrain_grid.grid_to_screen_center(cup_pos)
		add_child(pin)
		_pins.append(pin)
	queue_redraw()

func _draw() -> void:
	if not _terrain_grid:
		return
	for hole_pos in hole_tiles():
		if not _terrain_grid.is_valid_position(hole_pos):
			continue
		draw_hole(self, _terrain_grid, hole_pos)

## The hole as an ellipse on the projected tile: Ball.BALL_RADIUS across — the
## golf ball's own width — squashed the way the ground under it is, so it lies
## flat on the green instead of facing the camera. `rim` gives the slightly
## larger lip the black disc sits in.
static func hole_polygon(grid: TerrainGrid, node: CanvasItem, pos: Vector2i,
		rim: bool = false) -> PackedVector2Array:
	var center := OverlayGeometry.tile_center(grid, node, pos)
	var rx := hole_radius() + (HOLE_RIM_WIDTH if rim else 0.0)
	var ry := rx * ground_squash(grid)
	var points := PackedVector2Array()
	for i in range(SEGMENTS):
		var angle := TAU * float(i) / float(SEGMENTS)
		points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	return points

## How much a shape lying flat on the ground is squashed in this view: the
## projected tile's own height-to-width ratio (0.5 in the 2:1 isometric view,
## 1.0 if the tiles are square). The hole is a flat circle cut in the turf, so
## this — not the tile's corners, which the view rotates — sets its shape.
static func ground_squash(grid: TerrainGrid) -> float:
	if grid == null or grid.tile_width <= 0:
		return 0.5
	return float(grid.tile_height) / float(grid.tile_width)

## Cut a hole in the ground at `pos`: a light lip with the black, ball-sized
## disc inside it. Shared with the placement preview so the cup a player is
## about to paint is drawn exactly like the one that gets cut.
static func draw_hole(item: CanvasItem, grid: TerrainGrid, pos: Vector2i,
		alpha: float = 1.0) -> void:
	var rim_color := Color(HOLE_RIM_COLOR, HOLE_RIM_COLOR.a * alpha)
	var hole_color := Color(HOLE_COLOR, HOLE_COLOR.a * alpha)
	item.draw_colored_polygon(hole_polygon(grid, item, pos, true), rim_color)
	item.draw_colored_polygon(hole_polygon(grid, item, pos, false), hole_color)
