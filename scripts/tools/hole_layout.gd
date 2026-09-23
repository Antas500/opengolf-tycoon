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
## While a tee box waits and the Green tool is about to cut the cup,
## potential_hole() describes the hole the hovered tile would make, so the
## placement preview can draw its path before the cup is placed.
##
## "Unused" means the tile is not already claimed by a hole in the course.

## Returned by max_brush_size() when a tool has no special restriction.
const UNLIMITED_BRUSH: int = 0
## Tee and cup must be at least this many tiles apart (5 tiles = 110 yards).
const MIN_HOLE_TILES: float = 5.0
## Yardage scale used for hole lengths (matches TerrainGrid.calculate_distance_yards()).
const YARDS_PER_TILE: float = 22.0

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
			int(distance * YARDS_PER_TILE), min_hole_yards()]
		return request

	request.ready = true
	return request

## Shortest playable hole, in yards (MIN_HOLE_TILES at YARDS_PER_TILE).
static func min_hole_yards() -> int:
	return int(MIN_HOLE_TILES * YARDS_PER_TILE)

## Why the Green tool cannot cut a cup into `pos` right now ("" when it can).
## Mirrors main._paint_terrain_stamp(): a stamp skips land the player does not
## own and tiles under a building or decoration, and painting green over a tile
## that is already green changes nothing, so no cup gets cut there.
static func cup_site_blocker(grid: TerrainGrid, pos: Vector2i) -> String:
	if not grid or not grid.is_valid_position(pos):
		return "Off the course"
	if grid.get_tile(pos) == TerrainTypes.Type.GREEN:
		return "Already green — cut the cup on a new tile"
	if GameManager.land_manager and not GameManager.land_manager.is_tile_owned(pos):
		return "You don't own this land (L to buy)"
	var entities = GameManager.entity_layer
	if entities and (entities.is_tile_occupied_by_building(pos) \
			or entities.is_tile_occupied_by_decoration(pos)):
		return "Clear the building or decoration first"
	return ""

## Forward and middle tee tiles Open Hole paints for a tee/cup pair when multi-tee
## is on (HoleCreationTool._build_hole() via HoleData.auto_generate_tee_positions());
## {} otherwise. Keys are "forward" / "middle"; tiles on the back tee are left out.
static func extra_tee_tiles(grid: TerrainGrid, tee: Vector2i, cup: Vector2i) -> Dictionary:
	var tiles: Dictionary = {}
	if not grid or not GameManager.multi_tee_enabled:
		return tiles
	var probe := GameManager.HoleData.new()
	probe.tee_position = tee
	probe.green_position = cup
	probe.hole_position = cup
	probe.auto_generate_tee_positions(grid)
	for tee_key in ["forward", "middle"]:
		var pos: Vector2i = probe.tee_positions.get(tee_key, tee)
		if pos != tee and grid.is_valid_position(pos):
			tiles[tee_key] = pos
	return tiles

## The hole the player would lay out by cutting a cup at `cup_pos` — the
## potential hole the placement preview draws while the Green tool hovers.
##
## Only exists while the Green tool is about to paint a Green With Hole (no cup is
## waiting) and a tee box is waiting to be paired with it; otherwise returns {}.
## When several tee boxes wait (possible after deleting a hole) the nearest one is
## used, and the pair is reported as not ready because Open Hole would refuse it.
##
## Returns {
##   "tee": Vector2i, "cup": Vector2i, "hole_number": int,
##   "distance_yards": int, "par": int  — the numbers open_hole() will use,
##   "extra_tees": Dictionary — forward/middle tees Open Hole will paint (multi-tee),
##   "can_cut_cup": bool  — the Green tool would cut a cup on this tile,
##   "ready": bool        — Open Hole would accept the pair once the cup is cut,
##   "reason": String     — short label text for why not ("" when ready),
## }
static func potential_hole(tool_type: int, grid: TerrainGrid, course: GameManager.CourseData,
		cup_pos: Vector2i) -> Dictionary:
	if tool_type != TerrainTypes.Type.GREEN or not grid or not grid.is_valid_position(cup_pos):
		return {}
	if not green_places_cup(grid, course):
		return {}
	var tees := unused_tee_boxes(grid, course)
	if tees.is_empty():
		return {}

	# unused_tee_boxes() is sorted, so ties go to the first tee deterministically.
	var tee: Vector2i = tees[0]
	for candidate in tees:
		if Vector2(candidate - cup_pos).length_squared() < Vector2(tee - cup_pos).length_squared():
			tee = candidate

	var distance_yards: int = grid.calculate_distance_yards(tee, cup_pos)
	var site_blocker := cup_site_blocker(grid, cup_pos)
	var reason := site_blocker
	if reason.is_empty() and tees.size() > 1:
		reason = "%d tee boxes waiting — repaint the extras" % tees.size()
	if reason.is_empty() and Vector2(cup_pos - tee).length() < MIN_HOLE_TILES:
		reason = "Too short — a hole needs %d yds" % min_hole_yards()

	return {
		"tee": tee,
		"cup": cup_pos,
		"hole_number": (course.holes.size() if course else 0) + 1,
		"distance_yards": distance_yards,
		"par": GolfRules.calculate_par(distance_yards),
		"extra_tees": extra_tee_tiles(grid, tee, cup_pos),
		"can_cut_cup": site_blocker.is_empty(),
		"ready": reason.is_empty(),
		"reason": reason,
	}
