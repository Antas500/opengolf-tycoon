extends RefCounted
class_name HoleLayout
## HoleLayout - Single source of truth for how a golf hole is laid out.
##
## A hole is no longer drawn in one pass. The player paints the two ends with the
## ordinary terrain brushes and then opens the hole:
##
##   * Tee Box  - always a single tile (max brush 1x1). A second tee box cannot be
##     placed while an earlier tee box is still unused, so exactly one tee waits
##     on the course at a time.
##   * Green    - the first green placed while no cup is waiting is a
##     "Green With Hole": a single tile (max brush 1x1) with a cup cut into it.
##     Any later green is a "Green Without Hole" and paints with the normal brush.
##   * Open Hole (H / toolbar button) - pairs the single unused tee box with the
##     single unused green with a hole and creates the hole.
##
## "Unused" means the tile is not already claimed by a hole in the course.

## Returned by max_brush_size() when a tool has no special restriction.
const UNLIMITED_BRUSH: int = 0
## Tee and cup must be at least this many tiles apart (5 tiles = 110 yards).
const MIN_HOLE_TILES: float = 5.0

## Tiles claimed by existing holes as tees (back tee plus forward/middle tees).
static func used_tee_tiles(course: GameManager.CourseData) -> Dictionary:
	var used: Dictionary = {}
	if not course:
		return used
	for hole in course.holes:
		used[hole.tee_position] = true
		for tee_key in hole.tee_positions:
			used[hole.tee_positions[tee_key]] = true
	return used

## Tiles claimed by existing holes as the cup (current pin plus the pin rotation set).
static func used_cup_tiles(course: GameManager.CourseData) -> Dictionary:
	var used: Dictionary = {}
	if not course:
		return used
	for hole in course.holes:
		used[hole.hole_position] = true
		for pin in hole.pin_positions:
			used[pin] = true
	return used

## Tee box tiles that no hole has claimed yet.
static func unused_tee_boxes(grid: TerrainGrid, course: GameManager.CourseData = null) -> Array[Vector2i]:
	var waiting: Array[Vector2i] = []
	if not grid:
		return waiting
	var used := used_tee_tiles(course)
	for pos in grid.get_tee_box_tiles():
		if not used.has(pos):
			waiting.append(pos)
	waiting.sort()
	return waiting

## "Green With Hole" tiles that no hole has claimed yet.
static func unused_cups(grid: TerrainGrid, course: GameManager.CourseData = null) -> Array[Vector2i]:
	var waiting: Array[Vector2i] = []
	if not grid:
		return waiting
	var used := used_cup_tiles(course)
	for pos in grid.get_cup_tiles():
		if not used.has(pos):
			waiting.append(pos)
	waiting.sort()
	return waiting

## True when the course has no waiting green with a hole, so the next green the
## player paints becomes one.
static func green_places_cup(grid: TerrainGrid, course: GameManager.CourseData = null) -> bool:
	return unused_cups(grid, course).is_empty()

## A tee box may only be placed while no other tee box is waiting.
static func can_place_tee_box(grid: TerrainGrid, course: GameManager.CourseData = null) -> bool:
	return unused_tee_boxes(grid, course).is_empty()

## Why a tee box cannot be placed right now ("" when it can).
static func tee_placement_blocker(grid: TerrainGrid, course: GameManager.CourseData = null) -> String:
	if can_place_tee_box(grid, course):
		return ""
	return "A tee box is already waiting to be paired with a green. Open the hole first (H)."

## Largest brush the tool may use: 1x1 for a tee box and for a green that is
## about to become a green with a hole; no restriction otherwise.
static func max_brush_size(tool_type: int, grid: TerrainGrid,
		course: GameManager.CourseData = null) -> int:
	match tool_type:
		TerrainTypes.Type.TEE_BOX:
			return 1
		TerrainTypes.Type.GREEN:
			return 1 if green_places_cup(grid, course) else UNLIMITED_BRUSH
	return UNLIMITED_BRUSH

## Is a hole ready to be opened, and from which tiles?
## Returns {"ready": bool, "reason": String, "tee": Vector2i, "cup": Vector2i}.
static func open_hole_request(grid: TerrainGrid, course: GameManager.CourseData = null) -> Dictionary:
	var request := {
		"ready": false,
		"reason": "",
		"tee": Vector2i(-1, -1),
		"cup": Vector2i(-1, -1),
	}
	var tees := unused_tee_boxes(grid, course)
	var cups := unused_cups(grid, course)

	if tees.is_empty() and cups.is_empty():
		request.reason = "Paint a tee box (T) and a green (3) to lay out a hole."
		return request
	if tees.is_empty():
		request.reason = "Paint a tee box to go with the waiting green."
		return request
	if cups.is_empty():
		request.reason = "Paint a green to cut a cup for the waiting tee box."
		return request
	if tees.size() > 1:
		request.reason = "Holes open one at a time: %d tee boxes are waiting. Repaint the extra tees." % tees.size()
		return request
	if cups.size() > 1:
		request.reason = "Holes open one at a time: %d greens with a hole are waiting. Repaint the extra cups." % cups.size()
		return request

	request.tee = tees[0]
	request.cup = cups[0]
	var distance: float = Vector2(request.cup - request.tee).length()
	if distance < MIN_HOLE_TILES:
		request.reason = "Tee and cup are only %d yards apart — a hole needs at least %d yards." % [
			int(distance * 22.0), int(MIN_HOLE_TILES * 22.0)]
		return request

	request.ready = true
	return request
