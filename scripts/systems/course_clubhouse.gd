extends RefCounted
class_name CourseClubhouse
## CourseClubhouse - the one building every course has.
##
## A clubhouse is different from the optional facilities the Buildings tab
## sells: the course itself is not considered open without one, golfers walk
## out of it to the first tee and back to it when their round ends, and it can
## never be demolished — only moved. This class is the single place that
## decides where it stands, which tile is its front door, and whether a move
## is legal, so placing, moving and reading the clubhouse never disagree.


const BUILDING_TYPE := "clubhouse"

## Terrain the search for a home for the clubhouse will not build over, even
## though a player may drop an optional building on the fairway: greens, tees,
## sand and water are the course, and a fairway is somebody's hole.
const FORBIDDEN_TERRAINS: Array = [
	TerrainTypes.Type.EMPTY,
	TerrainTypes.Type.FAIRWAY,
	TerrainTypes.Type.FIRM_FAIRWAY,
	TerrainTypes.Type.GREEN,
	TerrainTypes.Type.TEE_BOX,
	TerrainTypes.Type.BUNKER,
	TerrainTypes.Type.POT_BUNKER,
	TerrainTypes.Type.WASTE_BUNKER,
	TerrainTypes.Type.WATER,
	TerrainTypes.Type.STREAM,
	TerrainTypes.Type.OUT_OF_BOUNDS,
]

## How far the search for a spot may walk away from the suggested anchor.
const SEARCH_RADIUS := 40

## Where the Quick Start arrival garden stands, measured from the middle of the
## owned land (its clubhouse at (54,61), the layouts' anchor at (63,63)). Every
## shipped layout is centred on that middle and keeps this corner clear, so it
## is also the obvious home for a clubhouse on a course that has no layout of
## its own yet: an empty lot or a prebuilt package.
const ARRIVAL_CORNER_OFFSET := Vector2i(-9, -2)

static var _building_data: Dictionary = {}


# =============================================================================
# READING
# =============================================================================

## The course's clubhouse, or null when the course has none.
static func find(entity_layer) -> Building:
	if entity_layer == null:
		return null
	var buildings: Array = entity_layer.get_all_buildings()
	for building in buildings:
		if is_clubhouse(building):
			return building
	return null

static func exists(entity_layer) -> bool:
	return find(entity_layer) != null

static func is_clubhouse(building) -> bool:
	return building is Building and building.building_type == BUILDING_TYPE

## The tile at the clubhouse door: where arriving golfers appear, where a round
## ends, and the tile the walking-path overlay paves up to. It is the first
## walkable tile just outside the footprint, starting from the front (the
## screen-facing long side) and fanning out to the sides. (-1,-1) when every
## neighbouring tile is un-walkable (all water, say).
static func front_tile(building: Building, terrain_grid, entity_layer) -> Vector2i:
	if not is_clubhouse(building) or terrain_grid == null:
		return Vector2i(-1, -1)
	# Any walkable tile beside the building will do: a tree is ground now, so
	# the door no longer has to dodge anything standing in front of the house.
	for tile in _front_tiles(building):
		if _is_walkable(tile, terrain_grid, entity_layer):
			return tile
	return Vector2i(-1, -1)

## Screen position of the door, or Vector2.INF when the clubhouse has none.
static func door_position(building: Building, terrain_grid, entity_layer) -> Vector2:
	var tile := front_tile(building, terrain_grid, entity_layer)
	if tile.x < 0 or terrain_grid == null:
		return Vector2.INF
	return terrain_grid.grid_to_screen_center(tile)

## The loaded clubhouse entry from data/buildings.json (empty if unreadable).
static func building_data() -> Dictionary:
	if _building_data.is_empty():
		var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))
		if raw is Dictionary and raw.has("buildings"):
			_building_data = raw["buildings"].get(BUILDING_TYPE, {})
	return _building_data


# =============================================================================
# GUARANTEEING ONE
# =============================================================================

## Make sure the course has its clubhouse and return it. An existing clubhouse
## is never moved or duplicated. A missing one is placed as close to
## `preferred` as the rules allow — the pocket the layout left for it — and
## failing that at the first legal spot outward from the centre of the owned
## land. Returns null only when there is genuinely nowhere to put it.
static func ensure(terrain_grid, entity_layer, preferred: Vector2i = Vector2i(-1, -1)) -> Building:
	var existing := find(entity_layer)
	if existing != null:
		return existing
	if terrain_grid == null or entity_layer == null:
		return null
	var data := building_data()
	if data.is_empty():
		push_warning("CourseClubhouse: data/buildings.json has no clubhouse entry")
		return null
	var size := _data_size(data)

	for anchor in _search_seeds(terrain_grid, preferred):
		var spot := _find_spot(terrain_grid, entity_layer, anchor, size)
		if spot.x >= 0:
			_prepare_ground(terrain_grid, spot, size)
			var building = entity_layer.place_building(BUILDING_TYPE, spot, {BUILDING_TYPE: data})
			if building != null:
				return building
	return null


# =============================================================================
# MOVING ONE
# =============================================================================

## Why this clubhouse cannot be moved so its top-left tile sits at `target`.
## Empty string means the move is legal. `CourseClubhouse` is the authority the
## preview, the click handler and any future UI all read, so they agree.
static func move_error(terrain_grid, entity_layer, building: Building, target: Vector2i) -> String:
	if not is_clubhouse(building):
		return "Only the clubhouse can be moved."
	if terrain_grid == null or entity_layer == null:
		return "There is no course to move the clubhouse on."
	if target == building.grid_position:
		return "The clubhouse is already there."
	var size := Vector2i(building.width, building.height)
	for x in range(size.x):
		for y in range(size.y):
			var error := tile_error(target + Vector2i(x, y), terrain_grid, entity_layer, building)
			if not error.is_empty():
				return error
	return ""

## Why one footprint tile of a clubhouse move is refused ("" when it is fine).
## Shared with the move preview so its per-tile colouring cannot disagree with
## the click. `moving` is the building on its way in: its own tiles are not in
## its way, the way the Buildings tab also ignores a ghost's own tile.
static func tile_error(tile: Vector2i, terrain_grid, entity_layer, moving: Building = null) -> String:
	if not terrain_grid.is_valid_position(tile):
		return "The whole clubhouse must fit on the course."
	if not _is_owned(tile):
		return "Buy this land first — the whole footprint must be owned."
	if entity_layer != null:
		var occupant = entity_layer.get_building_containing(tile)
		if occupant != null and occupant != moving:
			return "Move the footprint clear of the other building."
		if entity_layer.is_tile_occupied_by_decoration(tile):
			return "Remove the decoration in this footprint first."
	if not _terrain_ok(terrain_grid.get_tile(tile)):
		return "Move it off the greens, tees, sand and water."
	return ""

static func can_move_to(terrain_grid, entity_layer, building: Building, target: Vector2i) -> bool:
	return move_error(terrain_grid, entity_layer, building, target).is_empty()

## Move the clubhouse (its node, upgrades and revenue all come along). Returns
## true when it actually moved; refuses the same way move_error explains, so a
## click handler cannot drop it somewhere the preview said no.
static func move_to(entity_layer, building: Building, target: Vector2i) -> bool:
	if entity_layer == null or not is_clubhouse(building):
		return false
	var terrain_grid = entity_layer.terrain_grid
	var error := move_error(terrain_grid, entity_layer, building, target)
	if not error.is_empty():
		return false
	if not entity_layer.move_building(building, target):
		return false
	return true


# =============================================================================
# INTERNALS
# =============================================================================

## Walkable tiles outside the clubhouse, front first. The screen-facing side of
## an isometric building is its south edge, so that row leads.
static func _front_tiles(building: Building) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var pos := building.grid_position
	var w: int = maxi(1, building.width)
	var h: int = maxi(1, building.height)
	var south_y: int = pos.y + h
	# Doors face the middle of the front (screen-facing) edge first; the rest of
	# that row follows, then the corners, the flanks and finally the back.
	for x in _middle_out(w):
		tiles.append(Vector2i(pos.x + x, south_y))
	for y in _middle_out(h):
		tiles.append(Vector2i(pos.x - 1, pos.y + y))
		tiles.append(Vector2i(pos.x + w, pos.y + y))
	for x in _middle_out(w):
		tiles.append(Vector2i(pos.x + x, pos.y - 1))
	return tiles

## Indices 0..count-1 ordered from the middle outwards, so doors and other
## "edge" choices land at the centre of a side first.
static func _middle_out(count: int) -> Array[int]:
	var order: Array[int] = []
	# Whole-tile indices on purpose: the lower middle of an odd/even count.
	@warning_ignore("integer_division")
	var left: int = (count - 1) / 2
	var right: int = left + 1
	while order.size() < count:
		if left >= 0:
			order.append(left)
			left -= 1
		if right < count:
			order.append(right)
			right += 1
	return order

static func _is_walkable(tile: Vector2i, terrain_grid, entity_layer) -> bool:
	if not terrain_grid.is_valid_position(tile):
		return false
	if entity_layer != null and entity_layer.is_tile_occupied_by_building(tile):
		return false
	return not TerrainTypes.is_water(terrain_grid.get_tile(tile))


## The anchors the search tries, in priority order: the layout's pocket, then
## the middle of the land the player owns, then the middle of the course.
static func _search_seeds(terrain_grid, preferred: Vector2i) -> Array[Vector2i]:
	var seeds: Array[Vector2i] = []
	_try_add_seed(seeds, preferred, terrain_grid)
	_try_add_seed(seeds, arrival_corner(), terrain_grid)
	_try_add_seed(seeds, owned_land_centre(), terrain_grid)
	_try_add_seed(seeds, Vector2i(terrain_grid.grid_width / 2, terrain_grid.grid_height / 2), terrain_grid)
	return seeds

static func _try_add_seed(seeds: Array[Vector2i], candidate: Vector2i, terrain_grid) -> void:
	if candidate.x < 0 or candidate.y < 0:
		return
	if not terrain_grid.is_valid_position(candidate) or seeds.has(candidate):
		return
	seeds.append(candidate)

## Searches outward from the anchor in square rings and returns the first legal
## top-left corner, or (-1,-1) when nothing within SEARCH_RADIUS works. Ground
## that needs no clearing wins ties: the clubhouse will mow its own plot of
## woodland and level stony ground (see _prepare_ground) but should not have to
## when there is an open patch just as close.
static func _find_spot(terrain_grid, entity_layer, anchor: Vector2i, size: Vector2i) -> Vector2i:
	for distance in range(SEARCH_RADIUS + 1):
		for require_clear in [true, false]:
			for offset in _ring_offsets(distance):
				var candidate := anchor + offset
				if _footprint_ok(terrain_grid, entity_layer, candidate, size, require_clear):
					return candidate
	return Vector2i(-1, -1)

## Candidates at exactly `distance` tiles from the centre, without duplicates.
static func _ring_offsets(distance: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	if distance == 0:
		offsets.append(Vector2i.ZERO)
		return offsets
	for x in range(-distance, distance + 1):
		offsets.append(Vector2i(x, -distance))
		offsets.append(Vector2i(x, distance))
	for y in range(-distance + 1, distance):
		offsets.append(Vector2i(-distance, y))
		offsets.append(Vector2i(distance, y))
	return offsets

static func _footprint_ok(terrain_grid, entity_layer, origin: Vector2i, size: Vector2i,
		require_clear: bool = false) -> bool:
	for x in range(size.x):
		for y in range(size.y):
			var tile: Vector2i = origin + Vector2i(x, y)
			if not terrain_grid.is_valid_position(tile):
				return false
			if not _is_owned(tile):
				return false
			var kind: int = terrain_grid.get_tile(tile)
			if not _plain_ground_ok(kind) \
					and (require_clear or not _clearable_ground_ok(kind)):
				return false
			if entity_layer.is_tile_occupied_by_building(tile):
				return false
			if entity_layer.is_tile_occupied_by_decoration(tile):
				return false
	return true

## Clears the footprint's scenery and lays the grounds the building stands on.
static func _prepare_ground(terrain_grid, origin: Vector2i, size: Vector2i) -> void:
	for x in range(size.x):
		for y in range(size.y):
			var tile: Vector2i = origin + Vector2i(x, y)
			var ground: int = terrain_grid.get_tile(tile)
			# Woodland and scrub are tiles, not things to clear away, so the
			# plot is made by painting the lawn straight over them.
			if TerrainTypes.is_tree(ground) or ground == TerrainTypes.Type.BRUSH \
					or TerrainTypes.is_rocks(ground):
				terrain_grid.set_tile_natural(tile, TerrainTypes.Type.GRASS)

## Ground a dropped clubhouse needs: the same list the Buildings tab allows,
## so a move never feels stricter than placing any other building.
static func _terrain_ok(tile_type: int) -> bool:
	return PlacementManager.building_terrain_ok(tile_type)

## Ground the search for a *home* for the clubhouse prefers: that same list
## minus the fairways, because a course without a clubhouse is a course to be
## built, and the middle of somebody's hole is not where its front door goes.
static func _plain_ground_ok(tile_type: int) -> bool:
	return _terrain_ok(tile_type) and tile_type not in [TerrainTypes.Type.FAIRWAY,
			TerrainTypes.Type.FIRM_FAIRWAY]

## Wild ground a clubhouse will clear for its own plot (see _prepare_ground).
## The first pass of the search walks past these; the second takes them when
## nothing open is as close.
static func _clearable_ground_ok(tile_type: int) -> bool:
	return TerrainTypes.is_tree(tile_type) or TerrainTypes.is_rocks(tile_type) \
			or tile_type == TerrainTypes.Type.BRUSH

static func _is_owned(tile: Vector2i) -> bool:
	var land_manager = GameManager.land_manager
	return land_manager == null or land_manager.is_tile_owned(tile)

## The arrival corner of the owned land (see ARRIVAL_CORNER_OFFSET), or
## (-1,-1) when nothing is owned.
static func arrival_corner() -> Vector2i:
	var centre := owned_land_centre()
	if centre.x < 0:
		return Vector2i(-1, -1)
	return centre + ARRIVAL_CORNER_OFFSET

## Centre of the owned parcels, in tiles; (-1,-1) when nothing is owned.
static func owned_land_centre() -> Vector2i:
	var land_manager = GameManager.land_manager
	if land_manager == null or land_manager.owned_parcels.is_empty():
		return Vector2i(-1, -1)
	var min_tile := Vector2i(1 << 30, 1 << 30)
	var max_tile := Vector2i(-(1 << 30), -(1 << 30))
	for parcel in land_manager.owned_parcels.keys():
		var rect: Rect2i = land_manager.parcel_to_tile_rect(parcel)
		min_tile.x = mini(min_tile.x, rect.position.x)
		min_tile.y = mini(min_tile.y, rect.position.y)
		max_tile.x = maxi(max_tile.x, rect.position.x + rect.size.x - 1)
		max_tile.y = maxi(max_tile.y, rect.position.y + rect.size.y - 1)
	# The middle tile of the bounding box: tile indices are integers.
	@warning_ignore("integer_division")
	return Vector2i((min_tile.x + max_tile.x) / 2, (min_tile.y + max_tile.y) / 2)

static func _data_size(data: Dictionary) -> Vector2i:
	var size: Array = data.get("size", [1, 1])
	return Vector2i(int(size[0]), int(size[1]))
