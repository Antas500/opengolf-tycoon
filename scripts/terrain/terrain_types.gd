extends RefCounted
class_name TerrainTypes
## TerrainTypes - Definitions for all terrain types

enum Type {
	EMPTY = 0, GRASS = 1, FAIRWAY = 2, ROUGH = 3, HEAVY_ROUGH = 4,
	GREEN = 5, TEE_BOX = 6, BUNKER = 7, WATER = 8, PATH = 9,
	OUT_OF_BOUNDS = 10, TREES = 11, FLOWER_BED = 12, ROCKS = 13,
	# Later additions are appended: saves store these ids as raw ints.
	FIRM_FAIRWAY = 14, POT_BUNKER = 15, STREAM = 16, DEEP_ROUGH = 17,
	WASTE_BUNKER = 18, BRUSH = 19,
	# Boulder fields: the Rocks tile's stony ground scattered with small or
	# large stones. They play exactly like Rocks (see is_rocks).
	SMALL_BOULDERS = 20, LARGE_BOULDERS = 21,
	# The tree catalogue: one tile per species, painted like any other Course
	# Terrain tile. They play exactly like Trees (see is_tree) and differ only
	# in the canopy the course draws on the tile.
	OAK = 22, PINE = 23, MAPLE = 24, BIRCH = 25, CACTUS = 26, FESCUE = 27,
	CATTAILS = 28, SHRUB = 29, PALM = 30, DEAD_TREE = 31, HEATHER = 32,
}

const PROPERTIES: Dictionary = {
	# Prettier, more vibrant colors for better visual appeal
	# Maintenance costs tuned so a 9-hole course costs ~$800-1200/day raw (before seasonal/theme modifiers)
	Type.EMPTY: {"name": "Empty", "color": Color(0.18, 0.22, 0.18), "playable": false, "placement_cost": 0, "maintenance_cost": 0},
	Type.GRASS: {"name": "Natural Grass", "color": Color(0.45, 0.62, 0.35), "playable": true, "placement_cost": 0, "maintenance_cost": 0, "shot_difficulty": 0.3},
	Type.FAIRWAY: {"name": "Fairway", "color": Color(0.4, 0.78, 0.4), "playable": true, "placement_cost": 5, "maintenance_cost": 1, "shot_difficulty": 0.0},
	Type.ROUGH: {"name": "Rough", "color": Color(0.38, 0.55, 0.32), "playable": true, "placement_cost": 2, "maintenance_cost": 0, "shot_difficulty": 0.2},
	Type.HEAVY_ROUGH: {"name": "Heavy Rough", "color": Color(0.32, 0.48, 0.28), "playable": true, "placement_cost": 0, "maintenance_cost": 0, "shot_difficulty": 0.5},
	Type.GREEN: {"name": "Green", "color": Color(0.35, 0.88, 0.45), "playable": true, "placement_cost": 20, "maintenance_cost": 2, "shot_difficulty": 0.0},
	Type.TEE_BOX: {"name": "Tee Box", "color": Color(0.45, 0.75, 0.42), "playable": true, "placement_cost": 12, "maintenance_cost": 1, "shot_difficulty": 0.0},
	Type.BUNKER: {"name": "Bunker", "color": Color(0.95, 0.88, 0.65), "playable": true, "placement_cost": 10, "maintenance_cost": 1, "shot_difficulty": 0.6, "is_hazard": true},
	Type.WATER: {"name": "Water", "color": Color(0.25, 0.55, 0.85), "playable": false, "placement_cost": 20, "maintenance_cost": 0, "is_hazard": true, "penalty_strokes": 1},
	Type.PATH: {"name": "Cart Path", "color": Color(0.78, 0.75, 0.68), "playable": true, "placement_cost": 8, "maintenance_cost": 0, "shot_difficulty": 0.1, "speed_modifier": 1.5},
	Type.OUT_OF_BOUNDS: {"name": "Out of Bounds", "color": Color(0.42, 0.35, 0.32), "playable": false, "placement_cost": 0, "maintenance_cost": 0, "penalty_strokes": 1},
	Type.TREES: {"name": "Trees", "color": Color(0.22, 0.45, 0.22), "playable": true, "placement_cost": 10, "maintenance_cost": 0, "shot_difficulty": 0.7, "blocks_shots": true},
	# One tile per species. Like the boulder fields beside Rocks, each copies
	# the Trees tile's numbers exactly (see is_tree) and only changes the
	# canopy the course paints on the tile.
	Type.OAK: {"name": "Oak Tree", "color": Color(0.20, 0.50, 0.20), "playable": true, "placement_cost": 10, "maintenance_cost": 0, "shot_difficulty": 0.7, "blocks_shots": true},
	Type.PINE: {"name": "Pine Tree", "color": Color(0.15, 0.40, 0.15), "playable": true, "placement_cost": 10, "maintenance_cost": 0, "shot_difficulty": 0.7, "blocks_shots": true},
	Type.MAPLE: {"name": "Maple Tree", "color": Color(0.30, 0.50, 0.25), "playable": true, "placement_cost": 10, "maintenance_cost": 0, "shot_difficulty": 0.7, "blocks_shots": true},
	Type.BIRCH: {"name": "Birch Tree", "color": Color(0.25, 0.45, 0.20), "playable": true, "placement_cost": 10, "maintenance_cost": 0, "shot_difficulty": 0.7, "blocks_shots": true},
	Type.CACTUS: {"name": "Cactus", "color": Color(0.28, 0.55, 0.30), "playable": true, "placement_cost": 10, "maintenance_cost": 0, "shot_difficulty": 0.7, "blocks_shots": true},
	Type.FESCUE: {"name": "Fescue Grass", "color": Color(0.58, 0.55, 0.32), "playable": true, "placement_cost": 10, "maintenance_cost": 0, "shot_difficulty": 0.7, "blocks_shots": true},
	Type.CATTAILS: {"name": "Cattails", "color": Color(0.30, 0.48, 0.22), "playable": true, "placement_cost": 10, "maintenance_cost": 0, "shot_difficulty": 0.7, "blocks_shots": true},
	Type.SHRUB: {"name": "Shrub", "color": Color(0.22, 0.48, 0.22), "playable": true, "placement_cost": 10, "maintenance_cost": 0, "shot_difficulty": 0.7, "blocks_shots": true},
	Type.PALM: {"name": "Palm Tree", "color": Color(0.20, 0.58, 0.28), "playable": true, "placement_cost": 10, "maintenance_cost": 0, "shot_difficulty": 0.7, "blocks_shots": true},
	Type.DEAD_TREE: {"name": "Dead Tree", "color": Color(0.45, 0.38, 0.28), "playable": true, "placement_cost": 10, "maintenance_cost": 0, "shot_difficulty": 0.7, "blocks_shots": true},
	Type.HEATHER: {"name": "Heather", "color": Color(0.55, 0.28, 0.55), "playable": true, "placement_cost": 10, "maintenance_cost": 0, "shot_difficulty": 0.7, "blocks_shots": true},
	Type.FLOWER_BED: {"name": "Wild Flowers", "color": Color(0.85, 0.5, 0.6), "playable": false, "placement_cost": 15, "maintenance_cost": 0, "beauty_bonus": 5},
	# Stony ground. The three Rocks tiles share one look and one set of rules;
	# only the stones the course surface draws on them change (see the shader).
	Type.ROCKS: {"name": "Rocks", "color": Color(0.55, 0.52, 0.48), "playable": true, "placement_cost": 8, "maintenance_cost": 0, "shot_difficulty": 0.8},
	Type.SMALL_BOULDERS: {"name": "Small Boulders", "color": Color(0.60, 0.57, 0.53), "playable": true, "placement_cost": 8, "maintenance_cost": 0, "shot_difficulty": 0.8},
	Type.LARGE_BOULDERS: {"name": "Large Boulders", "color": Color(0.50, 0.47, 0.44), "playable": true, "placement_cost": 8, "maintenance_cost": 0, "shot_difficulty": 0.8},
	# Links-style fast running turf: plays like fairway but the ball releases.
	Type.FIRM_FAIRWAY: {"name": "Firm Fairway", "color": Color(0.62, 0.70, 0.38), "playable": true, "placement_cost": 6, "maintenance_cost": 1, "shot_difficulty": 0.05},
	# Small, deep bunker with a steep revetted face — wedge out, often sideways.
	Type.POT_BUNKER: {"name": "Pot Bunker", "color": Color(0.84, 0.76, 0.54), "playable": true, "placement_cost": 18, "maintenance_cost": 2, "shot_difficulty": 0.85, "is_hazard": true},
	# Narrow running water (a burn/creek). Same penalty as Water, but golfers
	# can still walk across it, so it can cut through the middle of a hole.
	Type.STREAM: {"name": "Stream", "color": Color(0.33, 0.62, 0.76), "playable": false, "placement_cost": 15, "maintenance_cost": 0, "is_hazard": true, "penalty_strokes": 1, "beauty_bonus": 2},
	# Knee-high unmown grass: the ball sits down and is hard to advance.
	Type.DEEP_ROUGH: {"name": "Deep Rough", "color": Color(0.36, 0.46, 0.26), "playable": true, "placement_cost": 1, "maintenance_cost": 0, "shot_difficulty": 0.6, "speed_modifier": 0.85},
	# Natural sandy scrubland. Not a hazard (no raking, club may be grounded).
	Type.WASTE_BUNKER: {"name": "Waste Bunker", "color": Color(0.80, 0.72, 0.55), "playable": true, "placement_cost": 6, "maintenance_cost": 0, "shot_difficulty": 0.35},
	# Dense scrub (gorse, heather, sagebrush) that swallows the ball.
	Type.BRUSH: {"name": "Brush", "color": Color(0.33, 0.40, 0.22), "playable": true, "placement_cost": 3, "maintenance_cost": 0, "shot_difficulty": 0.75, "speed_modifier": 0.75, "beauty_bonus": 1},
}

static func get_properties(type: Type) -> Dictionary:
	return PROPERTIES.get(type, PROPERTIES[Type.EMPTY])

static func get_type_name(type: Type) -> String:
	return get_properties(type).get("name", "Unknown")

static func get_color(type: Type) -> Color:
	return get_properties(type).get("color", Color.MAGENTA)

static func is_playable(type: Type) -> bool:
	return get_properties(type).get("playable", false)

static func is_hazard(type: Type) -> bool:
	return get_properties(type).get("is_hazard", false)

static func get_placement_cost(type: Type) -> int:
	return get_properties(type).get("placement_cost", 0)

static func get_maintenance_cost(type: Type) -> int:
	return get_properties(type).get("maintenance_cost", 0)

static func get_speed_modifier(type: Type) -> float:
	return get_properties(type).get("speed_modifier", 1.0)

# =============================================================================
# Terrain families — use these rather than comparing against single types, so
# every variant (e.g. Firm Fairway, Pot Bunker, Stream) behaves like its family.
# =============================================================================

## Pond water or a stream: a penalty area (1 stroke, drop at point of entry).
static func is_water(type: int) -> bool:
	return type == Type.WATER or type == Type.STREAM

## The ball can never be played from here: water, stream, out of bounds, or
## outside the property line.
static func is_out_of_play(type: int) -> bool:
	return is_water(type) or type == Type.OUT_OF_BOUNDS or type == Type.EMPTY

## Sand hazards where the ball plugs: bunkers and pot bunkers. Waste bunkers
## are sandy but are not hazards (see is_sand).
static func is_bunker(type: int) -> bool:
	return type == Type.BUNKER or type == Type.POT_BUNKER

## Any sandy ground, including waste bunkers.
static func is_sand(type: int) -> bool:
	return is_bunker(type) or type == Type.WASTE_BUNKER

## Mown fairway turf, soft or firm.
static func is_fairway(type: int) -> bool:
	return type == Type.FAIRWAY or type == Type.FIRM_FAIRWAY

## Any rough: rough, heavy rough, and deep rough.
static func is_rough(type: int) -> bool:
	return type == Type.ROUGH or type == Type.HEAVY_ROUGH or type == Type.DEEP_ROUGH

## Stony ground: painted Rocks and the two boulder fields. All three play the
## same — the worst lie on the course — and differ only in the stones the
## course surface draws on them.
static func is_rocks(type: int) -> bool:
	return type == Type.ROCKS or type == Type.SMALL_BOULDERS or type == Type.LARGE_BOULDERS

## Woodland: the Trees tile and every species tile beside it. They play the
## same — a ball buried in the roots, a shot that has to be punched out — and
## differ only in the canopy painted on the tile.
static func is_tree(type: int) -> bool:
	return type == Type.TREES or type in TREE_SPECIES_TILES

## The species tiles in toolbar order. Every one of them is a Course Terrain
## tile: paint it, replace it, and it costs its `placement_cost` per tile.
const TREE_SPECIES_TILES: Array[int] = [
	Type.OAK, Type.PINE, Type.MAPLE, Type.BIRCH, Type.CACTUS, Type.FESCUE,
	Type.CATTAILS, Type.SHRUB, Type.PALM, Type.DEAD_TREE, Type.HEATHER,
]

## Every tree tile: the generic Trees ground plus each species. The
## TreeOverlay draws a canopy on each of them.
const TREE_TERRAIN_TYPES: Array[int] = [Type.TREES,
	Type.OAK, Type.PINE, Type.MAPLE, Type.BIRCH, Type.PALM, Type.CACTUS,
	Type.DEAD_TREE, Type.SHRUB, Type.FESCUE, Type.CATTAILS, Type.HEATHER]

## The ground each species is planted in, which the course surface paints under
## the canopy (tree_look() in shaders/course_surface.gdshader mirrors this).
## Species sharing a ground share its edge too, so an oak wood running into a
## maple wood is one unbroken floor while a pine stand beside it still fades
## needles into leaves.
const TREE_GROUND_LOOKS: Dictionary = {
	Type.TREES: "leaf litter", Type.OAK: "leaf litter", Type.MAPLE: "leaf litter",
	Type.BIRCH: "leaf litter", Type.SHRUB: "leaf litter",
	Type.PINE: "pine needles", Type.CACTUS: "bare sand", Type.PALM: "bare sand",
	Type.DEAD_TREE: "bare sand", Type.CATTAILS: "waterlogged silt",
	Type.HEATHER: "acid peat", Type.FESCUE: "dry straw",
}

## The ground a tree tile is painted on, or "" for any tile that is not
## woodland. Every one of them is ordinary ground: nothing is planted in a
## second layer, so a species tile costs its `placement_cost` and nothing more.
static func get_tree_ground(type: int) -> String:
	return str(TREE_GROUND_LOOKS.get(type, ""))

## Each species tile's art key, which doubles as the name old saves gave a
## planted tree of that species (see EntityLayer.deserialize).
const TREE_SPECIES_KEYS: Dictionary = {
	Type.OAK: "oak", Type.PINE: "pine", Type.MAPLE: "maple", Type.BIRCH: "birch",
	Type.CACTUS: "cactus", Type.FESCUE: "fescue", Type.CATTAILS: "cattails",
	Type.SHRUB: "bush", Type.PALM: "palm", Type.DEAD_TREE: "dead_tree",
	Type.HEATHER: "heather",
}

## The art key a tree tile draws, or "" for the generic Trees tile, whose
## canopy the course picks from the theme.
static func get_tree_species(type: int) -> String:
	return TREE_SPECIES_KEYS.get(type, "")

## The tile a species grows on; anything unknown is the generic Trees tile.
static func tree_tile_for_species(species: String) -> int:
	for type in TREE_SPECIES_KEYS:
		if TREE_SPECIES_KEYS[type] == species:
			return type
	return Type.TREES

## Tooltip sentence shared by every Course Terrain tile. Each one overwrites
## every other tile on that tab — ground, wild flowers and trees.
const REPLACES_ANY_COURSE_TILE := "Replaces any other Course Terrain tile."

## Every terrain type the player can paint from the Course Terrain tab, in
## toolbar order: row 1 (tee box, green, bunker, rough, pot bunker, stream,
## water, out of bounds) then row 2 (fairway, firm fairway, deep rough, waste
## bunker, brush, rocks, small boulders, large boulders). Wild flowers and
## theme trees share the tab and the same replacement rule; they are appended
## beside this list.
const COURSE_PAINT_TYPES: Array[int] = [
	Type.TEE_BOX, Type.GREEN, Type.BUNKER, Type.ROUGH, Type.POT_BUNKER,
	Type.STREAM, Type.WATER, Type.OUT_OF_BOUNDS,
	Type.FAIRWAY, Type.FIRM_FAIRWAY, Type.DEEP_ROUGH, Type.WASTE_BUNKER,
	Type.BRUSH, Type.ROCKS, Type.SMALL_BOULDERS, Type.LARGE_BOULDERS,
]

## Landscape terrain tiles beside COURSE_PAINT_TYPES on the Course Terrain
## tab: wild flowers and the woodlands — the generic Trees ground plus every
## species tile the themes offer.
const COURSE_LANDSCAPE_TERRAIN_TYPES: Array[int] = [Type.FLOWER_BED,
	Type.TREES, Type.OAK, Type.PINE, Type.MAPLE, Type.BIRCH, Type.PALM, Type.CACTUS,
	Type.DEAD_TREE, Type.SHRUB, Type.FESCUE, Type.CATTAILS, Type.HEATHER]

## Terrain tiles available on the Course Terrain tab that natural generation may
## use. Keep this derived from the tab inventory and upkeep data so generated
## terrain cannot introduce a hidden daily maintenance bill.
static func get_natural_generation_types() -> Array[int]:
	var eligible: Array[int] = []
	for type in COURSE_PAINT_TYPES:
		if get_maintenance_cost(type) == 0:
			eligible.append(type)
	for type in COURSE_LANDSCAPE_TERRAIN_TYPES:
		if get_maintenance_cost(type) == 0:
			eligible.append(type)
	return eligible

## Is this a zero-upkeep terrain tile the Course Terrain tab actually offers?
static func is_natural_generation_type(type: int) -> bool:
	var is_course_tab_tile := type in COURSE_PAINT_TYPES or type in COURSE_LANDSCAPE_TERRAIN_TYPES
	return is_course_tab_tile and get_maintenance_cost(type) == 0

## Ground the walking-path improvement can be laid over (the Path tool in the
## Improvements tab): the rough and scrubby Course Terrain tiles, painted
## Rocks and the boulder fields, streams and wild flowers, plus tree tiles.
## The path sits on top of these tiles without replacing the terrain.
const WALKING_PATH_TERRAINS: Array[int] = [
	Type.ROUGH, Type.DEEP_ROUGH, Type.WASTE_BUNKER, Type.BRUSH,
	Type.ROCKS, Type.SMALL_BOULDERS, Type.LARGE_BOULDERS, Type.STREAM,
	Type.FLOWER_BED,
	Type.TREES, Type.OAK, Type.PINE, Type.MAPLE, Type.BIRCH, Type.PALM,
	Type.CACTUS, Type.DEAD_TREE, Type.SHRUB, Type.FESCUE, Type.CATTAILS, Type.HEATHER
]

## Can a walking path be laid on this terrain?
static func can_host_walking_path(type: int) -> bool:
	return type in WALKING_PATH_TERRAINS
