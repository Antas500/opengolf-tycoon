extends RefCounted
class_name PlacementManager
## PlacementManager - Handles placement of buildings and trees on the course

signal placement_mode_changed(mode: PlacementMode)

enum PlacementMode {
	NONE = 0,
	BUILDING = 1,
	TREE = 2,
	DECORATION = 3
}

var placement_mode: PlacementMode = PlacementMode.NONE
var selected_building_type: String = ""
var selected_tree_type: String = "oak"
var selected_decoration_type: String = ""
var selected_decoration_data: Dictionary = {}
var current_placement_data: Dictionary = {}

func start_building_placement(building_type: String, building_data: Dictionary) -> void:
	placement_mode = PlacementMode.BUILDING
	selected_building_type = building_type
	current_placement_data = building_data.duplicate(true)
	placement_mode_changed.emit(placement_mode)
	print("Started building placement: %s" % building_type)

func start_tree_placement(tree_type: String = "oak") -> void:
	placement_mode = PlacementMode.TREE
	selected_building_type = ""
	selected_tree_type = tree_type
	current_placement_data = {}
	placement_mode_changed.emit(placement_mode)
	print("Started tree placement: %s" % tree_type)

func start_decoration_placement(dec_type: String, dec_data: Dictionary) -> void:
	placement_mode = PlacementMode.DECORATION
	selected_building_type = ""
	selected_decoration_type = dec_type
	selected_decoration_data = dec_data.duplicate(true)
	current_placement_data = dec_data.duplicate(true)
	placement_mode_changed.emit(placement_mode)
	print("Started decoration placement: %s" % dec_type)

func cancel_placement() -> void:
	placement_mode = PlacementMode.NONE
	selected_building_type = ""
	selected_decoration_type = ""
	selected_decoration_data = {}
	current_placement_data = {}
	placement_mode_changed.emit(placement_mode)

func can_place_at(grid_pos: Vector2i, terrain_grid: TerrainGrid) -> bool:
	return get_placement_error(grid_pos, terrain_grid).is_empty()

## The terrain a building may stand on. One list for the player's Buildings tab
## and for a clubhouse being carried to a new spot (see CourseClubhouse).
static func building_terrain_ok(tile_type: int) -> bool:
	return tile_type in [
		TerrainTypes.Type.GRASS,
		TerrainTypes.Type.ROUGH,
		TerrainTypes.Type.HEAVY_ROUGH,
		TerrainTypes.Type.DEEP_ROUGH,
		TerrainTypes.Type.FAIRWAY,
		TerrainTypes.Type.FIRM_FAIRWAY,
		TerrainTypes.Type.PATH,
	]

func get_placement_error(grid_pos: Vector2i, terrain_grid: TerrainGrid) -> String:
	if placement_mode == PlacementMode.NONE:
		return "Select an item first."
	var footprint := get_placement_footprint()
	if footprint.is_empty():
		footprint = [Vector2i.ZERO]
	for offset in footprint:
		var tile: Vector2i = grid_pos + offset
		if not terrain_grid.is_valid_position(tile):
			return "The entire footprint must fit inside the course."
		if GameManager.land_manager and not GameManager.land_manager.is_tile_owned(tile):
			return "Buy this land first (L). The entire footprint must be owned."
		if GameManager.entity_layer and placement_mode in [PlacementMode.BUILDING, PlacementMode.DECORATION]:
			var entities = GameManager.entity_layer
			if entities.is_tile_occupied_by_building(tile):
				return "Move the footprint clear of the existing building."
			if entities.is_tile_occupied_by_decoration(tile):
				return "Remove the decoration in this footprint first."
			if entities.get_tree_at(tile):
				return "Clear the tree first: paint another Course Terrain tile over it."
		elif placement_mode == PlacementMode.TREE and _improvement_blocks(tile):
			return _improvement_blocker(tile)
	if not _terrain_allows_at(grid_pos, terrain_grid):
		if placement_mode == PlacementMode.BUILDING:
			return "Use grass, rough, fairway or path; keep greens, tees, sand and water clear."
		if placement_mode == PlacementMode.TREE:
			if is_same_course_tile(grid_pos, terrain_grid):
				return "This tile is already that one."
			return "Outside the course."
		return "This item needs compatible ground across its entire footprint."
	return ""

## True when this click would lay the Course Terrain tile that is already here.
## The click is a no-op; the preview shows it as invalid so it doesn't look free.
func is_same_course_tile(grid_pos: Vector2i, _terrain_grid: TerrainGrid) -> bool:
	var entities = GameManager.entity_layer
	if entities == null:
		return false
	if placement_mode == PlacementMode.TREE:
		var tree = entities.get_tree_at(grid_pos)
		return tree != null and tree.tree_type == selected_tree_type
	return false

func _improvement_blocks(grid_pos: Vector2i) -> bool:
	var entities = GameManager.entity_layer
	if entities == null:
		return false
	return entities.is_tile_occupied_by_building(grid_pos) \
			or entities.is_tile_occupied_by_decoration(grid_pos)

func _improvement_blocker(grid_pos: Vector2i) -> String:
	var entities = GameManager.entity_layer
	if entities == null:
		return ""
	if entities.is_tile_occupied_by_building(grid_pos):
		return "Bulldoze the building first. Course Terrain tiles replace each other, not buildings."
	if entities.is_tile_occupied_by_decoration(grid_pos):
		return "Bulldoze the decoration first. Course Terrain tiles replace each other, not decorations."
	return ""

func _terrain_allows_at(grid_pos: Vector2i, terrain_grid: TerrainGrid) -> bool:
	if placement_mode == PlacementMode.NONE:
		return false

	if placement_mode == PlacementMode.TREE:
		return _can_place_tree(grid_pos, terrain_grid)
	elif placement_mode == PlacementMode.BUILDING:
		return _can_place_building(grid_pos, terrain_grid)
	elif placement_mode == PlacementMode.DECORATION:
		return _can_place_decoration(grid_pos, terrain_grid)

	return false

func _can_place_tree(grid_pos: Vector2i, terrain_grid: TerrainGrid) -> bool:
	# A tree is a Course Terrain tile: it replaces any other tile on that tab
	# (water, sand, greens, other trees). Buildings and decorations are
	# improvements, so they stay until the Bulldozer takes them.
	return _can_replace_course_tile(grid_pos, terrain_grid)

func _can_replace_course_tile(grid_pos: Vector2i, terrain_grid: TerrainGrid) -> bool:
	if not terrain_grid.is_valid_position(grid_pos):
		return false
	if _improvement_blocks(grid_pos):
		return false
	if is_same_course_tile(grid_pos, terrain_grid):
		return false
	return true

func _can_place_building(grid_pos: Vector2i, terrain_grid: TerrainGrid) -> bool:
	if not terrain_grid.is_valid_position(grid_pos):
		return false
	
	var size = current_placement_data.get("size", [1, 1])
	var width = size[0] as int
	var height = size[1] as int
	
	# Check all tiles that the building would occupy
	for x in range(width):
		for y in range(height):
			var check_pos = grid_pos + Vector2i(x, y)
			if not terrain_grid.is_valid_position(check_pos):
				return false
			
			# Buildings stand on grass-type terrain or a cart path; greens,
			# tees, sand and water stay clear (shared with the clubhouse move).
			if not building_terrain_ok(terrain_grid.get_tile(check_pos)):
				return false
	
	return true

func _can_place_decoration(grid_pos: Vector2i, terrain_grid: TerrainGrid) -> bool:
	if not terrain_grid.is_valid_position(grid_pos):
		return false

	var sz = selected_decoration_data.get("size", [1, 1])
	var width = int(sz[0])
	var height = int(sz[1])
	var placeable = selected_decoration_data.get("placeable_terrain", ["grass"])

	# Map terrain name strings to TerrainTypes
	var valid_types: Array = []
	for terrain_name in placeable:
		match terrain_name:
			# "grass" ground includes Rough: terrain generation opens every
			# course on Rough as its base turf, so lawn decorations that used
			# to sit anywhere on Natural Grass must accept it too.
			"grass": valid_types.append_array([TerrainTypes.Type.GRASS, TerrainTypes.Type.ROUGH])
			"fairway": valid_types.append_array([TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.FIRM_FAIRWAY])
			"rough": valid_types.append_array([TerrainTypes.Type.ROUGH, TerrainTypes.Type.DEEP_ROUGH])
			"heavy_rough": valid_types.append(TerrainTypes.Type.HEAVY_ROUGH)
			"path": valid_types.append(TerrainTypes.Type.PATH)

	for x in range(width):
		for y in range(height):
			var check_pos = grid_pos + Vector2i(x, y)
			if not terrain_grid.is_valid_position(check_pos):
				return false
			var tile_type = terrain_grid.get_tile(check_pos)
			if not (tile_type in valid_types):
				return false

	return true

func get_placement_cost() -> int:
	if placement_mode == PlacementMode.TREE:
		var tree_data = TreeEntity.TREE_PROPERTIES.get(selected_tree_type, {})
		return tree_data.get("cost", 20)
	elif placement_mode == PlacementMode.BUILDING:
		return current_placement_data.get("cost", 0)
	elif placement_mode == PlacementMode.DECORATION:
		return selected_decoration_data.get("cost", 0)

	return 0

func get_placement_footprint() -> Array:
	"""Returns array of Vector2i positions for building or decoration footprint"""
	if placement_mode != PlacementMode.BUILDING and placement_mode != PlacementMode.DECORATION:
		return []

	var size = current_placement_data.get("size", [1, 1])
	var width = size[0] as int
	var height = size[1] as int
	var footprint: Array = []

	for x in range(width):
		for y in range(height):
			footprint.append(Vector2i(x, y))

	return footprint

func get_building_footprint() -> Array:
	"""Returns array of Vector2i positions for building footprint (legacy, calls get_placement_footprint)"""
	return get_placement_footprint()
