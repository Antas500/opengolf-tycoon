extends Node2D
class_name EntityLayer
## EntityLayer - Manages all placed buildings, trees and decorations on the course

var buildings: Dictionary = {}     # key: Vector2i (grid_pos), value: Building node
var trees: Dictionary = {}         # key: Vector2i (grid_pos), value: TreeEntity node
var decorations: Dictionary = {}   # key: Vector2i (grid_pos), value: Decoration node
var _original_terrain: Dictionary = {}  # key: Vector2i, value: int (terrain type before entity was placed)

var terrain_grid: TerrainGrid
var building_registry: Dictionary = {}  # Can accept either Node or Dictionary
var decoration_registry: Dictionary = {}  # Loaded from data/decorations.json

## Map seed for deterministic prop variations
## Set once at game start or load for consistent visual results
var map_seed: int = 0

signal building_placed(building: Building, cost: int)
signal tree_placed(tree: TreeEntity, cost: int)
signal decoration_placed(decoration: Decoration, cost: int)
signal building_removed(grid_pos: Vector2i)
## The building changed address: its dictionary key and its node both moved.
signal building_moved(building: Building, from_pos: Vector2i, to_pos: Vector2i)
signal tree_removed(grid_pos: Vector2i)
signal decoration_removed(grid_pos: Vector2i)
signal building_selected(building: Building)

@onready var buildings_container = Node2D.new()
@onready var trees_container = Node2D.new()
@onready var decorations_container = Node2D.new()

func _ready() -> void:
	# Relative shadow layers (-2/-1) must remain above the opaque terrain.
	z_index = 2
	buildings_container.name = "Buildings"
	trees_container.name = "Trees"
	decorations_container.name = "Decorations"

	# Enable Y-sorting for proper isometric depth ordering
	# Objects lower on screen (higher Y) render in front of objects higher on screen
	buildings_container.y_sort_enabled = true
	trees_container.y_sort_enabled = true
	decorations_container.y_sort_enabled = true

	add_child(buildings_container)
	add_child(trees_container)
	add_child(decorations_container)

	# Generate a random map seed if not set (new game)
	if map_seed == 0:
		randomize()
		map_seed = randi()
	_apply_map_seed()


func _apply_map_seed() -> void:
	"""Apply the map seed to the prop variation system"""
	PropVariation.set_map_seed(map_seed)


func set_map_seed(seed_value: int) -> void:
	"""Set the map seed and apply it to prop variations"""
	map_seed = seed_value
	_apply_map_seed()

func set_terrain_grid(grid: TerrainGrid) -> void:
	terrain_grid = grid

func set_building_registry(registry) -> void:
	building_registry = registry

func set_decoration_registry(registry: Dictionary) -> void:
	decoration_registry = registry

func place_building(building_type: String, grid_pos: Vector2i, registry) -> Building:
	"""Place a building at the specified grid position"""
	if registry == null or (registry is Dictionary and registry.is_empty()):
		push_error("Building registry not set")
		return null

	var building_data
	if registry is Dictionary:
		building_data = registry.get(building_type, {})
	else:
		# Support legacy Node-based registry
		building_data = registry.get_building(building_type) if registry.has_method("get_building") else {}

	if building_data.is_empty():
		push_error("Unknown building type: %s" % building_type)
		return null

	# Check if this is a unique building that already exists
	if building_data.get("required", false):
		for existing in buildings.values():
			if existing.building_type == building_type:
				push_error("Cannot place duplicate unique building: %s" % building_type)
				return null

	# Check for overlap with existing buildings
	var new_width = building_data.get("size", [1, 1])[0]
	var new_height = building_data.get("size", [1, 1])[1]
	if _would_overlap_building(grid_pos, new_width, new_height):
		push_error("Cannot place building: overlaps with existing building")
		return null

	var building = Building.new()
	building.building_type = building_type
	building.set_terrain_grid(terrain_grid)
	building.set_position_in_grid(grid_pos)
	
	buildings_container.add_child(building)
	
	# Store by grid position
	buildings[grid_pos] = building
	
	# Connect signals
	building.building_selected.connect(_on_building_selected)
	building.building_destroyed.connect(_on_building_destroyed)
	
	building_placed.emit(building, building_data.get("cost", 0))
	return building

func place_tree(grid_pos: Vector2i, tree_type: String = "oak") -> TreeEntity:
	"""Place a tree at the specified grid position"""
	var tree = TreeEntity.new()
	tree.set_terrain_grid(terrain_grid)
	tree.set_position_in_grid(grid_pos)

	# Pre-set tree data BEFORE add_child so _ready() skips the default build.
	# Without this, _ready() builds default oak visuals, then set_tree_type()
	# rebuilds with the correct type — doubling the work for every tree.
	tree.tree_type = tree_type
	if tree_type in TreeEntity.TREE_PROPERTIES:
		tree.tree_data = TreeEntity.TREE_PROPERTIES[tree_type].duplicate(true)
	else:
		tree.tree_type = "oak"
		tree.tree_data = TreeEntity.TREE_PROPERTIES["oak"].duplicate(true)

	trees_container.add_child(tree)

	# Now that the node is in tree, build visuals exactly once.
	# _ready() skipped because tree_data was pre-populated above.
	tree.set_tree_type(tree_type)

	# Store by grid position
	trees[grid_pos] = tree

	# Stamp terrain at the tree's grid position (the visual base is shifted
	# to align with this tile, so no offset needed for any tree type)
	if terrain_grid and not _original_terrain.has(grid_pos):
		_original_terrain[grid_pos] = terrain_grid.get_tile(grid_pos)
	if terrain_grid:
		terrain_grid.set_tile(grid_pos, TerrainTypes.Type.TREES)

	# Connect signals
	tree.tree_selected.connect(_on_tree_selected)
	tree.tree_destroyed.connect(_on_tree_destroyed)

	# Get actual tree cost from tree data
	var tree_cost = tree.tree_data.get("cost", 20)
	tree_placed.emit(tree, tree_cost)
	return tree

func get_building_at(grid_pos: Vector2i) -> Building:
	return buildings.get(grid_pos, null)

func get_tree_at(grid_pos: Vector2i) -> TreeEntity:
	return trees.get(grid_pos, null)

func get_buildings_in_area(top_left: Vector2i, bottom_right: Vector2i) -> Array:
	"""Get all buildings within the specified area"""
	var result: Array = []
	for pos in buildings.keys():
		if pos.x >= top_left.x and pos.x <= bottom_right.x and \
		   pos.y >= top_left.y and pos.y <= bottom_right.y:
			result.append(buildings[pos])
	return result

func get_trees_in_area(top_left: Vector2i, bottom_right: Vector2i) -> Array:
	"""Get all trees within the specified area"""
	var result: Array = []
	for pos in trees.keys():
		if pos.x >= top_left.x and pos.x <= bottom_right.x and \
		   pos.y >= top_left.y and pos.y <= bottom_right.y:
			result.append(trees[pos])
	return result

func remove_building(grid_pos: Vector2i, force: bool = false) -> void:
	var building = buildings.get(grid_pos, null)
	if building == null:
		# Buildings are keyed by their top-left tile; a demolition click can
		# land anywhere on a multi-tile facility.
		building = get_building_containing(grid_pos)
		if building == null:
			return
		grid_pos = building.grid_position
	# A required building (the clubhouse) is part of the course: it can be
	# moved, never demolished. `force` is for teardown paths that must clear
	# the layer regardless (see clear_all).
	if not force and building.is_required():
		return
	building.destroy()
	buildings.erase(grid_pos)
	building_removed.emit(grid_pos)

## Move a building to a new top-left tile, keeping its node — upgrade level,
## architecture and lifetime revenue all carry over. The dictionary key follows
## the building so lookups by the old tile find nothing. Returns false when
## there is no such building or it is already there.
func move_building(building: Building, new_pos: Vector2i) -> bool:
	if not is_instance_valid(building):
		return false
	var old_pos: Vector2i = building.grid_position
	if old_pos == new_pos:
		return false
	buildings.erase(old_pos)
	building.set_position_in_grid(new_pos)
	buildings[new_pos] = building
	building_moved.emit(building, old_pos, new_pos)
	return true

func remove_tree(grid_pos: Vector2i) -> void:
	var tree = trees.get(grid_pos, null)
	if tree:
		tree.destroy()
		trees.erase(grid_pos)
		_restore_terrain(grid_pos)
		tree_removed.emit(grid_pos)

## Lift a tree off a tile without putting its ground back. Course Terrain
## replacement uses this so the new tile stays, instead of the stamp the entity
## left behind. Returns {} when nothing stood here, otherwise
## {type, position, subtype, original_terrain}. original_terrain is -1 when the
## entity never recorded the ground it stood on.
func take_course_terrain_entity(grid_pos: Vector2i) -> Dictionary:
	var original := int(_original_terrain.get(grid_pos, -1))
	if trees.has(grid_pos):
		var tree: TreeEntity = trees[grid_pos]
		var subtype := tree.tree_type
		tree.destroy()
		trees.erase(grid_pos)
		_original_terrain.erase(grid_pos)
		tree_removed.emit(grid_pos)
		return {
			"type": "tree",
			"position": grid_pos,
			"subtype": subtype,
			"original_terrain": original,
		}
	return {}

## Remember the ground under a tile that is about to receive a new tree,
## without changing the tile. place_tree only snapshots the current tile when
## nothing is remembered, so this keeps the real ground (and any walking path
## the new tile can still host).
func remember_original_terrain(grid_pos: Vector2i, terrain_type: int) -> void:
	if terrain_type >= 0:
		_original_terrain[grid_pos] = terrain_type

## Put back a tree lifted by take_course_terrain_entity, including the ground
## it stood on so a later removal restores that ground.
func restore_course_terrain_entity(grid_pos: Vector2i, kind: String, subtype: String, original_terrain: int = -1) -> void:
	if trees.has(grid_pos):
		take_course_terrain_entity(grid_pos)
	if original_terrain >= 0:
		_original_terrain[grid_pos] = original_terrain
	if kind == "tree":
		place_tree(grid_pos, subtype)

func place_decoration(dec_type: String, grid_pos: Vector2i, dec_registry: Dictionary) -> Decoration:
	"""Place a decoration at the specified grid position"""
	var dec_data = dec_registry.get(dec_type, {})
	if dec_data.is_empty():
		push_error("Unknown decoration type: %s" % dec_type)
		return null

	var sz = dec_data.get("size", [1, 1])
	var dec_width = int(sz[0])
	var dec_height = int(sz[1])

	# Check for overlap with existing entities (buildings, decorations)
	if _would_overlap_building(grid_pos, dec_width, dec_height):
		push_error("Cannot place decoration: overlaps with existing building")
		return null
	if _would_overlap_decoration(grid_pos, dec_width, dec_height):
		push_error("Cannot place decoration: overlaps with existing decoration")
		return null

	# Check individual tiles for tree occupancy
	for x in range(dec_width):
		for y in range(dec_height):
			var check_pos = grid_pos + Vector2i(x, y)
			if trees.has(check_pos):
				push_error("Cannot place decoration: tile occupied by a tree")
				return null

	var decoration = Decoration.new()
	decoration.set_terrain_grid(terrain_grid)
	decoration.set_decoration_type(dec_type, dec_data)
	decoration.set_position_in_grid(grid_pos)

	decorations_container.add_child(decoration)

	# Store by grid position (anchor tile)
	decorations[grid_pos] = decoration

	decoration.decoration_selected.connect(_on_decoration_selected)
	decoration.decoration_destroyed.connect(_on_decoration_destroyed)

	decoration_placed.emit(decoration, dec_data.get("cost", 0))
	EventBus.decoration_placed.emit(dec_type, grid_pos)
	return decoration

func remove_decoration(grid_pos: Vector2i) -> void:
	var decoration = decorations.get(grid_pos, null)
	if decoration:
		decoration.destroy()
		decorations.erase(grid_pos)
		decoration_removed.emit(grid_pos)
		EventBus.decoration_removed.emit(grid_pos)

func get_decoration_at(grid_pos: Vector2i) -> Decoration:
	"""Get decoration at position, checking both anchor tiles and footprints"""
	# Direct lookup first
	if decorations.has(grid_pos):
		return decorations[grid_pos]
	# Check if grid_pos falls within any multi-tile decoration's footprint
	for dec in decorations.values():
		if dec.size.x > 1 or dec.size.y > 1:
			var footprint = dec.get_footprint()
			if grid_pos in footprint:
				return dec
	return null

func get_all_decorations() -> Array:
	return decorations.values()

func get_decorations_in_area(top_left: Vector2i, bottom_right: Vector2i) -> Array:
	"""Get all decorations within the specified area (checks footprint for multi-tile)"""
	var result: Array = []
	for dec in decorations.values():
		# Check if any tile in footprint is within the area
		var in_area = false
		for tile_pos in dec.get_footprint():
			if tile_pos.x >= top_left.x and tile_pos.x <= bottom_right.x and \
			   tile_pos.y >= top_left.y and tile_pos.y <= bottom_right.y:
				in_area = true
				break
		if in_area:
			result.append(dec)
	return result

func _would_overlap_decoration(new_pos: Vector2i, new_width: int, new_height: int) -> bool:
	"""Check if a new entity would overlap with any existing decoration"""
	for existing in decorations.values():
		var ex_pos = existing.grid_position
		var ex_width = existing.size.x
		var ex_height = existing.size.y

		var new_right = new_pos.x + new_width
		var new_bottom = new_pos.y + new_height
		var ex_right = ex_pos.x + ex_width
		var ex_bottom = ex_pos.y + ex_height

		if new_pos.x < ex_right and new_right > ex_pos.x and new_pos.y < ex_bottom and new_bottom > ex_pos.y:
			return true
	return false

func is_tile_occupied_by_decoration(grid_pos: Vector2i) -> bool:
	"""Check if a tile is occupied by any decoration (including multi-tile)"""
	return get_decoration_at(grid_pos) != null

func _restore_terrain(grid_pos: Vector2i) -> void:
	"""Restore the original terrain type after removing an entity"""
	if not terrain_grid:
		return
	var original = _original_terrain.get(grid_pos, TerrainTypes.Type.GRASS)
	terrain_grid.set_tile(grid_pos, original)
	_original_terrain.erase(grid_pos)

func get_all_buildings() -> Array:
	return buildings.values()

func _would_overlap_building(new_pos: Vector2i, new_width: int, new_height: int) -> bool:
	"""Check if a new building would overlap with any existing building"""
	for existing in buildings.values():
		var ex_pos = existing.grid_position
		var ex_width = existing.width
		var ex_height = existing.height

		# Check if rectangles overlap
		var new_right = new_pos.x + new_width
		var new_bottom = new_pos.y + new_height
		var ex_right = ex_pos.x + ex_width
		var ex_bottom = ex_pos.y + ex_height

		if new_pos.x < ex_right and new_right > ex_pos.x and new_pos.y < ex_bottom and new_bottom > ex_pos.y:
			return true

	return false

func has_building_of_type(building_type: String) -> bool:
	## Check if a building of the specified type already exists
	for existing in buildings.values():
		if existing.building_type == building_type:
			return true
	return false

func is_tile_occupied_by_building(grid_pos: Vector2i) -> bool:
	## Check if a tile is occupied by any building (including multi-tile buildings)
	return get_building_containing(grid_pos) != null

func get_building_containing(grid_pos: Vector2i) -> Building:
	## Get the building whose footprint covers this tile (multi-tile aware).
	## Buildings are keyed by their top-left placement tile, so demolition from
	## any tile of the facility looks the footprint up like this.
	for building in buildings.values():
		var b_pos = building.grid_position
		if grid_pos.x >= b_pos.x and grid_pos.x < b_pos.x + building.width and \
		   grid_pos.y >= b_pos.y and grid_pos.y < b_pos.y + building.height:
			return building
	return null

func get_all_trees() -> Array:
	return trees.values()

func serialize() -> Dictionary:
	var data: Dictionary = {
		"map_seed": map_seed,
		"buildings": {},
		"trees": {},
		"decorations": {},
		"original_terrain": {}
	}

	for pos in buildings:
		data["buildings"]["%d,%d" % [pos.x, pos.y]] = buildings[pos].get_building_info()

	for pos in trees:
		data["trees"]["%d,%d" % [pos.x, pos.y]] = trees[pos].get_tree_info()

	for pos in decorations:
		data["decorations"]["%d,%d" % [pos.x, pos.y]] = decorations[pos].get_decoration_info()

	for pos in _original_terrain:
		data["original_terrain"]["%d,%d" % [pos.x, pos.y]] = _original_terrain[pos]

	return data

func clear_all() -> void:
	"""Remove all entities from the layer."""
	for pos in buildings.keys():
		# force: teardown clears the layer regardless of what is standing on
		# it. clear_all means "empty", not "demolish what the rules allow".
		buildings[pos].destroy(true)
	buildings.clear()
	for pos in trees.keys():
		trees[pos].destroy()
	trees.clear()
	for pos in decorations.keys():
		decorations[pos].destroy()
	decorations.clear()
	_original_terrain.clear()

func deserialize(data: Dictionary) -> void:
	"""Reconstruct entities from saved data."""
	clear_all()

	# Restore map seed for consistent prop variations
	if data.has("map_seed"):
		set_map_seed(data["map_seed"])

	# Restore original terrain map before placing entities so place_tree
	# doesn't overwrite the tile with the TREES stamp value.
	if data.has("original_terrain"):
		for key in data["original_terrain"]:
			var parts = key.split(",")
			if parts.size() == 2:
				var pos = Vector2i(int(parts[0]), int(parts[1]))
				_original_terrain[pos] = int(data["original_terrain"][key])

	if data.has("trees"):
		for key in data["trees"]:
			var parts = key.split(",")
			if parts.size() == 2:
				var pos = Vector2i(int(parts[0]), int(parts[1]))
				var tree_data_saved = data["trees"][key]
				# Support both "type" (current) and "tree_type" (legacy) keys
				var tree_type_val = "oak"
				if tree_data_saved is Dictionary:
					tree_type_val = tree_data_saved.get("type", tree_data_saved.get("tree_type", "oak"))
				place_tree(pos, tree_type_val)

	if data.has("buildings"):
		for key in data["buildings"]:
			var parts = key.split(",")
			if parts.size() == 2:
				var pos = Vector2i(int(parts[0]), int(parts[1]))
				var building_info = data["buildings"][key]
				var building_type = building_info.get("building_type", "") if building_info is Dictionary else ""
				if building_type.is_empty():
					building_type = building_info.get("type", "") if building_info is Dictionary else ""
				if not building_type.is_empty():
					var building = place_building(building_type, pos, building_registry)
					if building and building_info is Dictionary:
						building.restore_from_info(building_info)

	# Boulders were once sprite entities placed on the course; they are Course
	# Terrain paint now (Small Boulders / Large Boulders). A save from before
	# that change still carries a "rocks" block, and dropping the boulder must
	# not leave its stamp behind: the tile goes back to the ground the boulder
	# stood on. Painted Rocks ground stays Rocks, because that is what it was.
	if data.has("rocks"):
		for key in data["rocks"]:
			var parts = key.split(",")
			if parts.size() != 2:
				continue
			var pos = Vector2i(int(parts[0]), int(parts[1]))
			var original := int(_original_terrain.get(pos, -1))
			if terrain_grid and original >= 0 and not TerrainTypes.is_rocks(original):
				terrain_grid.set_tile(pos, original)
			_original_terrain.erase(pos)

	if data.has("decorations"):
		for key in data["decorations"]:
			var parts = key.split(",")
			if parts.size() == 2:
				var pos = Vector2i(int(parts[0]), int(parts[1]))
				var dec_data_saved = data["decorations"][key]
				var dec_type = ""
				if dec_data_saved is Dictionary:
					dec_type = dec_data_saved.get("type", "")
				if not dec_type.is_empty() and not decoration_registry.is_empty():
					place_decoration(dec_type, pos, decoration_registry)

func _on_building_selected(building: Building) -> void:
	building_selected.emit(building)

func _on_building_destroyed(_building: Building) -> void:
	pass  # Clean up if needed

func _on_tree_selected(_tree: TreeEntity) -> void:
	pass  # Handle tree selection if needed

func _on_tree_destroyed(_tree: TreeEntity) -> void:
	pass  # Clean up if needed

func _on_decoration_selected(_decoration: Decoration) -> void:
	pass  # Handle decoration selection if needed

func _on_decoration_destroyed(_decoration: Decoration) -> void:
	pass  # Clean up if needed
