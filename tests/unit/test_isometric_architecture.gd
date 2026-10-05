extends GutTest
## Buildings stand on the grid's own isometric diamonds.
##
## Every wall, roof, window and planter is authored in grid space — tiles
## across, tiles down, pixels up — and projected through the same 2:1 axes the
## terrain uses. These tests hold the renderer to that promise: the artwork
## covers exactly the tiles the building occupies at every view rotation, every
## facility draws inside its own square, and the upgrades grow upward rather
## than outward. See CourseArchitecture.

const POS := Vector2i(6, 6)

## Draws facilities the way the game does — from inside a real `_draw()` — and
## reports the grid-space box each one covered.
class Painter extends Node2D:
	var jobs: Array = []
	var extents: Array = []

	func _draw() -> void:
		extents.clear()
		for job in jobs:
			extents.append(CourseArchitecture.draw_building(self, job.kind, job.size,
				job.tier, 0.0, false, job.facing))


var grid: TerrainGrid
var entities: EntityLayer
var registry: Dictionary
var painter: Painter
var _saved_terrain_grid
var _saved_entity_layer


func before_all() -> void:
	registry = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]


func before_each() -> void:
	_saved_terrain_grid = GameManager.terrain_grid
	_saved_entity_layer = GameManager.entity_layer
	grid = TerrainGrid.new()
	grid.grid_width = 40
	grid.grid_height = 32
	add_child_autofree(grid)
	for x in range(grid.grid_width):
		for y in range(grid.grid_height):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.GRASS)
	entities = EntityLayer.new()
	add_child_autofree(entities)
	entities.set_terrain_grid(grid)
	GameManager.terrain_grid = grid
	GameManager.entity_layer = entities
	painter = Painter.new()
	add_child_autofree(painter)


func after_each() -> void:
	GameManager.terrain_grid = _saved_terrain_grid if is_instance_valid(_saved_terrain_grid) else null
	GameManager.entity_layer = _saved_entity_layer if is_instance_valid(_saved_entity_layer) else null


func _size_of(building_type: String) -> Vector2:
	var dimensions: Array = registry[building_type].get("size", [1, 1])
	return Vector2(float(dimensions[0]) * 64.0, float(dimensions[1]) * 32.0)


func _tiles_of(size: Vector2) -> Vector2:
	return size / Vector2(64.0, 32.0)


func _corners(tiles: Vector2) -> Array:
	return [Vector2(0, 0), Vector2(tiles.x, 0), Vector2(tiles.x, tiles.y), Vector2(0, tiles.y)]


## The node position Building.set_position_in_grid() gives a footprint here.
func _node_position(size: Vector2, tiles: Vector2) -> Vector2:
	return grid.grid_point_to_screen(Vector2(POS) + tiles * 0.5) - Vector2(size.x * 0.5, size.y)


## Draw one facility and hand back the box it covered.
func _draw_extent(building_type: String, tier := 1, facing := 0) -> AABB:
	var size := _size_of(building_type)
	painter.jobs = [{"kind": building_type, "size": size, "tier": tier, "facing": facing}]
	painter.extents = []
	painter.queue_redraw()
	for _attempt in range(3):
		await get_tree().process_frame
		if not painter.extents.is_empty():
			return painter.extents[0]
	fail_test("%s at rotation %d never drew" % [building_type, facing])
	return AABB()


# ---------------------------------------------------------------------------
# The footprint sits on the tiles
# ---------------------------------------------------------------------------

func test_the_art_covers_exactly_the_tiles_a_building_stands_on() -> void:
	# The whole point of the renderer: a placed building's projected corners are
	# the terrain's own tile corners, so its square is the square it was placed
	# on — not a flat elevation laid across them.
	for building_type in registry:
		var size := _size_of(building_type)
		var tiles := _tiles_of(size)
		for facing in range(4):
			grid.set_view_orientation(facing)
			var node_pos := _node_position(size, tiles)
			var origin := CourseArchitecture.grid_origin_offset(size, facing)
			for corner in _corners(tiles):
				var drawn := origin + CourseArchitecture.project_point(
						Vector2.ZERO, Vector3(corner.x, corner.y, 0), facing)
				var expected := grid.grid_point_to_screen(Vector2(POS) + corner) - node_pos
				assert_almost_eq(drawn.x, expected.x, 0.001,
					"%s at rotation %d: corner %s across" % [building_type, facing, corner])
				assert_almost_eq(drawn.y, expected.y, 0.001,
					"%s at rotation %d: corner %s down" % [building_type, facing, corner])


func test_every_placed_building_lands_on_its_tile_corners() -> void:
	# Exercise the real placement path: EntityLayer positions a building before
	# it enters the tree, while Building loads its data-driven footprint in
	# _ready(). Every building type must be re-anchored to that final footprint,
	# not just the 4x4 clubhouse whose size matches Building's default.
	for building_type in registry:
		var kind := str(building_type)
		var building := entities.place_building(kind, POS, registry)
		assert_not_null(building, "%s is placed" % kind)
		if building == null:
			continue

		var size := _size_of(kind)
		var tiles := _tiles_of(size)
		assert_eq(Vector2i(building.width, building.height), Vector2i(tiles),
			"%s loads its registered footprint" % kind)
		for facing in range(4):
			grid.set_view_orientation(facing)
			building.set_position_in_grid(POS)
			var origin := CourseArchitecture.grid_origin_offset(size, facing)
			for corner in _corners(tiles):
				var drawn := building.global_position + origin + CourseArchitecture.project_point(
						Vector2.ZERO, Vector3(corner.x, corner.y, 0), facing)
				var expected := grid.to_global(grid.grid_point_to_screen(Vector2(POS) + corner))
				assert_almost_eq(drawn.x, expected.x, 0.001,
					"%s rotation %d: corner %s across" % [kind, facing, corner])
				assert_almost_eq(drawn.y, expected.y, 0.001,
					"%s rotation %d: corner %s down" % [kind, facing, corner])

		entities.clear_all()
		await get_tree().process_frame


func test_the_projection_matches_the_grids_own_away_from_the_corners() -> void:
	# Interior tiles and lifted points — the wall tops and roof ridges the
	# renderer builds from — project through the same transform.
	var tiles := Vector2(3, 2)
	var size := Vector2(tiles.x * 64.0, tiles.y * 32.0)
	for facing in range(4):
		grid.set_view_orientation(facing)
		var node_pos := _node_position(size, tiles)
		var origin := CourseArchitecture.grid_origin_offset(size, facing)
		for point in [Vector3(0, 0, 0), Vector3(1.5, 0.5, 0), Vector3(3, 2, 0),
				Vector3(0.5, 1.5, 40), Vector3(2.5, 2.0, 17)]:
			var drawn := node_pos + origin + CourseArchitecture.project_point(
					Vector2.ZERO, point, facing)
			var expected := grid.grid_point_to_screen(
					Vector2(POS) + Vector2(point.x, point.y)) - Vector2(0, point.z)
			assert_almost_eq(drawn.x, expected.x, 0.001,
				"rotation %d: %s across" % [facing, point])
			assert_almost_eq(drawn.y, expected.y, 0.001,
				"rotation %d: %s down" % [facing, point])


func test_rotating_the_view_turns_the_building_with_the_course() -> void:
	var building := entities.place_building("restaurant", POS, registry)
	var architecture: CourseArchitecture = building.get_node("Visual/Architecture")
	for facing in range(4):
		grid.set_view_orientation(facing)
		building.set_position_in_grid(POS)
		assert_eq(architecture.facing, facing,
			"the drawing follows the course round to rotation %d" % facing)


# ---------------------------------------------------------------------------
# Every facility draws, and stays on its square
# ---------------------------------------------------------------------------

func test_every_facility_draws_inside_its_own_square() -> void:
	for building_type in registry:
		var tiles := _tiles_of(_size_of(building_type))
		for facing in range(4):
			var box := await _draw_extent(building_type, 1, facing)
			# A building may overhang its tiles a little — eaves, a bench on the
			# terrace, a bay window — but it may not wander off its square.
			assert_between(box.position.x, -0.5, 0.5,
				"%s at rotation %d overhangs its west tiles" % [building_type, facing])
			assert_between(box.position.y, -0.5, 0.5,
				"%s at rotation %d overhangs its north tiles" % [building_type, facing])
			assert_between(box.end.x, tiles.x - 0.5, tiles.x + 0.5,
				"%s at rotation %d overhangs its east tiles" % [building_type, facing])
			assert_between(box.end.y, tiles.y - 0.5, tiles.y + 0.5,
				"%s at rotation %d overhangs its south tiles" % [building_type, facing])
			assert_between(box.position.z, -4.0, 8.0,
				"%s at rotation %d digs into the ground" % [building_type, facing])
			assert_lt(box.end.z, 100.0,
				"%s at rotation %d is a skyscraper" % [building_type, facing])


func test_the_art_leaves_room_for_the_walls_it_draws() -> void:
	# The two sides facing the viewer carry the frontage — door, windows,
	# awning. A roof that swallows the wall would hide all of it, so the drawn
	# volume has to stand a storey high on every rotation.
	var box := await _draw_extent("clubhouse", 1, 0)
	assert_gt(box.end.z, 34.0, "the clubhouse walls stand a storey high")


func test_the_clubhouse_grows_without_leaving_its_square() -> void:
	var tiles := _tiles_of(_size_of("clubhouse"))
	var heights: Array = []
	for tier in range(1, 4):
		for facing in range(4):
			var box := await _draw_extent("clubhouse", tier, facing)
			assert_between(box.position.x, -0.5, 0.5, "tier %d covers its square" % tier)
			assert_between(box.end.x, tiles.x - 0.5, tiles.x + 0.5,
				"tier %d covers its square" % tier)
			assert_between(box.end.y, tiles.y - 0.5, tiles.y + 0.5,
				"tier %d covers its square" % tier)
			heights.append(box.end.z)
	# Each upgrade is visibly a bigger building, never a wider one.
	assert_gt(heights[4], heights[0], "The second tier is taller than the first")
	assert_gt(heights[8], heights[4], "The third tier is taller than the second")


func test_every_building_type_has_its_own_architecture() -> void:
	# A kind with no branch falls through to the kiosk routine, which would
	# silently give a clubhouse the wrong building.
	var named := ["clubhouse", "pro_shop", "restaurant", "snack_bar", "driving_range",
		"cart_shed", "restroom", "conservatory", "tea_pavilion", "garden_spa",
		"golf_academy", "locker_room"]
	var kiosks := ["coffee_house", "halfway_house", "ice_cream_kiosk"]
	for building_type in registry:
		assert_true(building_type in named or building_type in kiosks
				or building_type == "bench",
			"%s has an architecture routine" % building_type)
