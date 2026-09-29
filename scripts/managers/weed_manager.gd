extends Node
class_name WeedManager
## WeedManager - Grows and tracks the weeds sprouting on the course.
##
## Weeds are the groundskeepers' job: at the end of each day a few clumps sprout
## on owned turf, and hired groundskeepers pull them out during play. Left alone
## they accumulate and drag the course condition (and so the star rating) down.

signal weeds_changed()

## Turf the player would not want weeds in. Greens/tees are kept clear so a clump
## never hides a cup or blocks a tee shot.
const HOST_TURF: Array = [
	TerrainTypes.Type.GRASS,
	TerrainTypes.Type.FAIRWAY,
	TerrainTypes.Type.FIRM_FAIRWAY,
	TerrainTypes.Type.ROUGH,
	TerrainTypes.Type.HEAVY_ROUGH,
	TerrainTypes.Type.DEEP_ROUGH,
]

## Weeds per open hole that count as "the course is overrun" (condition floor).
const WEEDS_PER_HOLE_FULL_PRESSURE: float = 4.0
## Absolute ceiling so an abandoned course does not litter every tile.
const MAX_WEEDS: int = 80
## Growth gained per legacy day by weeds already on the course. Scaled down to
## the 3.5-second day via GameManager.DAILY_RATE_SCALE for real-time parity.
const DAILY_GROWTH: float = 0.22
## New clumps sprouting per open hole per legacy day (fractional carry kept).
const DAILY_SPROUTS_PER_HOLE: float = 0.5
## Attempts to find an open turf tile when sprouting. Fails gracefully.
const SPAWN_ATTEMPTS: int = 80

## Vector2i grid tile -> Weed node (null when headless, e.g. in unit tests).
var weeds: Dictionary = {}
## Vector2i grid tile -> growth 0.0-1.0, kept independently of the visuals.
var growth: Dictionary = {}
## Fractional sprout debt so sub-one daily rates are not rounded away.
var _sprout_carry: float = 0.0
var terrain_grid: TerrainGrid = null
var container: Node2D = null

func setup(grid: TerrainGrid, weed_container: Node2D) -> void:
	terrain_grid = grid
	container = weed_container

func has_weed(pos: Vector2i) -> bool:
	return growth.has(pos)

func get_weed_count() -> int:
	return growth.size()

func get_weed_positions() -> Array:
	return growth.keys()

func get_growth(pos: Vector2i) -> float:
	return float(growth.get(pos, 0.0))

## Sprout new clumps for the day and let existing ones grow a little taller.
## Rates are scaled by GameManager.DAILY_RATE_SCALE so weeds accumulate at the
## tune the legacy 6 AM–8 PM clock had. Returns how many new clumps appeared.
func grow_daily(open_holes: int) -> int:
	if terrain_grid == null:
		return 0
	var scaled_growth := DAILY_GROWTH * GameManager.DAILY_RATE_SCALE
	for pos in growth.keys():
		var next: float = minf(1.0, float(growth[pos]) + scaled_growth)
		growth[pos] = next
		_apply_growth(pos, next)

	_sprout_carry += open_holes * DAILY_SPROUTS_PER_HOLE * GameManager.DAILY_RATE_SCALE
	var wanted := int(floor(_sprout_carry))
	_sprout_carry -= wanted
	var sprouted := 0
	for i in wanted:
		if growth.size() >= MAX_WEEDS:
			break
		var pos := _find_open_turf_tile()
		if pos == Vector2i(-1, -1):
			break
		spawn_weed(pos, randf_range(0.15, 0.35))
		sprouted += 1
	if sprouted > 0:
		weeds_changed.emit()
	return sprouted

func spawn_weed(pos: Vector2i, weed_growth: float = 0.3) -> bool:
	if terrain_grid == null or growth.has(pos):
		return false
	var value := clampf(weed_growth, 0.0, 1.0)
	growth[pos] = value
	var weed: Weed = null
	if container:
		weed = Weed.new()
		weed.set_terrain_grid(terrain_grid)
		weed.set_position_in_grid(pos)
		weed.set_growth(value)
		container.add_child(weed)
	weeds[pos] = weed
	return true

## Pull the clump out. Returns true when one was actually removed.
func remove_weed(pos: Vector2i) -> bool:
	if not growth.has(pos):
		return false
	growth.erase(pos)
	var weed: Weed = weeds.get(pos, null)
	weeds.erase(pos)
	if weed and is_instance_valid(weed):
		if weed.get_parent():
			weed.get_parent().remove_child(weed)
		weed.queue_free()
	weeds_changed.emit()
	return true

## Nearest weed to a point expressed in grid coordinates (fractional) within a
## radius in tiles. Returns Vector2i(-1, -1) when nothing is in range.
func find_closest_weed(from_grid: Vector2, max_distance: float) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := max_distance
	for pos in growth.keys():
		var d := Vector2(pos).distance_to(from_grid)
		if d <= best_dist:
			best_dist = d
			best = pos
	return best

func clear_all() -> void:
	for pos in weeds.keys():
		var weed: Weed = weeds[pos]
		if weed and is_instance_valid(weed):
			if weed.get_parent():
				weed.get_parent().remove_child(weed)
			weed.queue_free()
	weeds.clear()
	growth.clear()
	weeds_changed.emit()

## Weeds relative to open holes — 1.0 means fully overrun.
func get_pressure(open_holes: int) -> float:
	var capacity := maxf(1.0, float(open_holes) * WEEDS_PER_HOLE_FULL_PRESSURE)
	return clampf(float(growth.size()) / capacity, 0.0, 1.0)

func serialize() -> Dictionary:
	var out: Dictionary = {}
	for pos in growth:
		out["%d,%d" % [pos.x, pos.y]] = float(growth[pos])
	return {"weeds": out}

func deserialize(data: Dictionary) -> void:
	clear_all()
	if terrain_grid == null:
		return
	for key in data.get("weeds", {}):
		var parts: PackedStringArray = String(key).split(",")
		if parts.size() != 2:
			continue
		var pos := Vector2i(int(parts[0]), int(parts[1]))
		spawn_weed(pos, float(data["weeds"][key]))
	weeds_changed.emit()

# --- Internals ---------------------------------------------------------------

func _apply_growth(pos: Vector2i, value: float) -> void:
	var weed: Weed = weeds.get(pos, null)
	if weed and is_instance_valid(weed):
		weed.set_growth(value)

func _find_open_turf_tile() -> Vector2i:
	var tee_tiles: Dictionary = {}
	for tee in terrain_grid.get_tee_box_tiles():
		tee_tiles[tee] = true

	var w := terrain_grid.grid_width
	var h := terrain_grid.grid_height
	for attempt in SPAWN_ATTEMPTS:
		var pos := Vector2i(randi_range(0, w - 1), randi_range(0, h - 1))
		if growth.has(pos):
			continue
		if not HOST_TURF.has(terrain_grid.get_tile(pos)):
			continue
		if terrain_grid.has_cup_tile(pos) or tee_tiles.has(pos):
			continue
		if _tile_occupied(pos):
			continue
		if not _tile_owned(pos):
			continue
		return pos
	return Vector2i(-1, -1)

func _tile_occupied(pos: Vector2i) -> bool:
	var layer = GameManager.entity_layer
	if layer == null:
		return false
	if layer.is_tile_occupied_by_building(pos):
		return true
	if layer.has_method("is_tile_occupied_by_decoration") and layer.is_tile_occupied_by_decoration(pos):
		return true
	if layer.trees.has(pos) or layer.rocks.has(pos):
		return true
	return false

func _tile_owned(pos: Vector2i) -> bool:
	var land = GameManager.land_manager
	if land == null:
		return true
	return land.is_tile_owned(pos)
