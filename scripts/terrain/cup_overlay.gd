extends Node2D
class_name CupOverlay
## CupOverlay - Marks every "Green With Hole" tile that is not part of a hole yet.
##
## A green painted while the course has no waiting cup gets a cup cut into it.
## Until a tee box is paired with it (Open Hole / H) the cup is unused, so it is
## drawn here with a gold pin to distinguish it from the red pins of open holes.

const CUP_COLOR := Color(0.07, 0.10, 0.07, 0.9)
const CUP_RING := Color(0.96, 0.96, 0.90, 0.8)
const WAITING_PIN_COLOR := Color(0.98, 0.83, 0.25)
const WAITING_POLE_HEIGHT := 30.0
const WAITING_FLAG_LENGTH := 14.0
const CUP_RADIUS_SCALE := 0.34

var _terrain_grid: TerrainGrid = null
var _pins: Array[WindFlag] = []

func initialize(grid: TerrainGrid) -> void:
	_terrain_grid = grid
	z_index = 6  # Above terrain, below golfers and ball
	if _terrain_grid and not _terrain_grid.cup_tiles_changed.is_connected(_on_cup_tiles_changed):
		_terrain_grid.cup_tiles_changed.connect(_on_cup_tiles_changed)
	EventBus.load_completed.connect(_on_load_completed)
	_rebuild()

func _exit_tree() -> void:
	if _terrain_grid and _terrain_grid.cup_tiles_changed.is_connected(_on_cup_tiles_changed):
		_terrain_grid.cup_tiles_changed.disconnect(_on_cup_tiles_changed)
	if EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.disconnect(_on_load_completed)

func _on_cup_tiles_changed() -> void:
	_rebuild()

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
	for cup_pos in _terrain_grid.get_cup_tiles():
		if not _terrain_grid.is_valid_position(cup_pos):
			continue
		draw_colored_polygon(_cup_polygon(cup_pos, CUP_RADIUS_SCALE + 0.16), CUP_RING)
		draw_colored_polygon(_cup_polygon(cup_pos, CUP_RADIUS_SCALE), CUP_COLOR)

## Ellipse fitted to the projected tile so the cup reads as a circle in top-down
## view and as a squashed ellipse on the isometric diamond.
func _cup_polygon(pos: Vector2i, radius_scale: float) -> PackedVector2Array:
	var center := OverlayGeometry.tile_center(_terrain_grid, self, pos)
	var right := OverlayGeometry.point_in_tile(_terrain_grid, self, pos, Vector2(1.0, 0.5))
	var bottom := OverlayGeometry.point_in_tile(_terrain_grid, self, pos, Vector2(0.5, 1.0))
	var rx: float = (right - center).length() * radius_scale
	var ry: float = (bottom - center).length() * radius_scale
	var points := PackedVector2Array()
	const SEGMENTS := 16
	for i in range(SEGMENTS):
		var angle := TAU * float(i) / float(SEGMENTS)
		points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	return points
