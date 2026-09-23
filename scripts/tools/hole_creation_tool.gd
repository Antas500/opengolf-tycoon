extends Node
class_name HoleCreationTool
## HoleCreationTool - Opens golf holes from the tiles the player painted.
##
## Tee boxes and greens are placed with the ordinary terrain brushes (see
## HoleLayout for the rules: a tee box is a single tile and only one may wait at
## a time; the first green painted while no cup is waiting becomes a
## "Green With Hole"). This tool turns that waiting tee box + green with a hole
## pair into a hole when the player presses H or clicks Open Hole.

## Tee and cup must be at least this far apart to make a playable hole.
const MIN_HOLE_TILES: float = HoleLayout.MIN_HOLE_TILES

var current_hole_number: int = 1

signal hole_created(hole_data: GameManager.HoleData)

## The pair a hole would be opened from right now, and why it may not be ready.
func open_hole_request() -> Dictionary:
	return HoleLayout.open_hole_request(GameManager.terrain_grid, GameManager.current_course)

func can_open_hole() -> bool:
	return bool(open_hole_request().get("ready", false))

## Create a hole from an unused tee box tile and an unused green-with-hole tile.
## Returns the new hole, or null when the pair is not valid.
func open_hole(tee_position: Vector2i, cup_position: Vector2i) -> GameManager.HoleData:
	var grid: TerrainGrid = GameManager.terrain_grid
	if not grid:
		return null
	if not grid.is_valid_position(tee_position) or not grid.is_valid_position(cup_position):
		return null
	if grid.get_tile(tee_position) != TerrainTypes.Type.TEE_BOX:
		print("Open hole needs a tee box tile at ", tee_position)
		return null
	if grid.get_tile(cup_position) != TerrainTypes.Type.GREEN:
		print("Open hole needs a green with a hole at ", cup_position)
		return null
	if Vector2(cup_position - tee_position).length() < MIN_HOLE_TILES:
		print("Tee and cup are too close to open a hole")
		return null
	return _build_hole(tee_position, cup_position)

## Create a hole for a generated course (Quick Start, prebuilt packages).
## Generated layouts only paint the land the player owns, so the player-facing
## preconditions of open_hole() do not apply here.
func create_generated_hole(tee_position: Vector2i, green_position: Vector2i) -> GameManager.HoleData:
	return _build_hole(tee_position, green_position)

## Build the hole record for a tee/cup pair and add it to the course.
func _build_hole(tee_position: Vector2i, cup_position: Vector2i) -> GameManager.HoleData:
	var grid: TerrainGrid = GameManager.terrain_grid
	var hole = GameManager.HoleData.new()
	hole.hole_number = current_hole_number
	hole.tee_position = tee_position
	hole.green_position = cup_position
	hole.hole_position = cup_position  # Cup is at the green-with-hole tile

	# Calculate distance in yards
	hole.distance_yards = grid.calculate_distance_yards(tee_position, cup_position)

	# Calculate par based on distance
	hole.par = calculate_par(hole.distance_yards)

	# Auto-generate multiple tee boxes and pin positions
	hole.tee_positions = {"back": hole.tee_position, "middle": hole.tee_position, "forward": hole.tee_position}
	if GameManager.multi_tee_enabled:
		hole.auto_generate_tee_positions(grid)
		# Paint TEE_BOX terrain at forward/middle tee positions
		for tee_key in ["forward", "middle"]:
			var tee_pos: Vector2i = hole.tee_positions[tee_key]
			if tee_pos != hole.tee_position and grid.is_valid_position(tee_pos):
				grid.set_tile(tee_pos, TerrainTypes.Type.TEE_BOX)
	hole.pin_positions = [hole.hole_position]
	hole.auto_generate_pin_positions(grid)
	# auto_generate_pin_positions() replaces the cup with a quadrant extreme of the
	# green. The player cut this cup, so it stays the active pin and leads the
	# rotation set used by daily pin changes.
	var pins: Array = [cup_position]
	for pin in hole.pin_positions:
		if pin != cup_position:
			pins.append(pin)
	hole.pin_positions = pins
	hole.current_pin_index = 0
	hole.hole_position = cup_position
	hole.recalculate_par_by_tee(grid)

	# Calculate difficulty rating based on surrounding terrain
	hole.difficulty_rating = DifficultyCalculator.calculate_hole_difficulty(hole, grid)

	# The cup now belongs to this hole, so it stops being a waiting green with a hole.
	grid.remove_cup_tile(cup_position)

	# Add hole to course
	if not GameManager.current_course:
		GameManager.current_course = GameManager.CourseData.new()

	GameManager.current_course.add_hole(hole)

	print("Hole ", current_hole_number, " created! Par ", hole.par, " (", hole.distance_yards, " yards)")

	EventBus.hole_created.emit(hole.hole_number, hole.par, hole.distance_yards)
	hole_created.emit(hole)

	current_hole_number += 1
	return hole

## Calculate par based on hole distance — delegates to GolfRules
static func calculate_par(distance_yards: int) -> int:
	return GolfRules.calculate_par(distance_yards)

## Get all holes in the current course
func get_holes() -> Array:
	if GameManager.current_course:
		return GameManager.current_course.holes
	return []

## Get total par for the course
func get_total_par() -> int:
	if GameManager.current_course:
		return GameManager.current_course.total_par
	return 0

## Remove tree and rock entities at a grid position before placing tee/green
func _remove_obstacles_at(position: Vector2i) -> void:
	var el = GameManager.entity_layer
	if not el:
		return
	if el.get_tree_at(position):
		el.remove_tree(position)
	if el.get_rock_at(position):
		el.remove_rock(position)

func delete_hole(hole_number: int) -> bool:
	if not GameManager.current_course:
		return false

	for i in range(GameManager.current_course.holes.size()):
		var hole = GameManager.current_course.holes[i]
		if hole.hole_number == hole_number:
			GameManager.current_course.holes.remove_at(i)
			GameManager.current_course._recalculate_par()

			# Renumber subsequent holes
			for j in range(i, GameManager.current_course.holes.size()):
				GameManager.current_course.holes[j].hole_number = j + 1

			current_hole_number = GameManager.current_course.holes.size() + 1
			EventBus.hole_deleted.emit(hole_number)
			return true

	return false
