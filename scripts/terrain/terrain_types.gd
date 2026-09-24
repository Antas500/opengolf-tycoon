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
	Type.WATER: {"name": "Water", "color": Color(0.25, 0.55, 0.85), "playable": false, "placement_cost": 20, "maintenance_cost": 1, "is_hazard": true, "penalty_strokes": 1},
	Type.PATH: {"name": "Cart Path", "color": Color(0.78, 0.75, 0.68), "playable": true, "placement_cost": 8, "maintenance_cost": 0, "shot_difficulty": 0.1, "speed_modifier": 1.5},
	Type.OUT_OF_BOUNDS: {"name": "Out of Bounds", "color": Color(0.42, 0.35, 0.32), "playable": false, "placement_cost": 0, "maintenance_cost": 0, "penalty_strokes": 1},
	Type.TREES: {"name": "Trees", "color": Color(0.22, 0.45, 0.22), "playable": true, "placement_cost": 10, "maintenance_cost": 0, "shot_difficulty": 0.7, "blocks_shots": true},
	Type.FLOWER_BED: {"name": "Flower Bed", "color": Color(0.85, 0.5, 0.6), "playable": false, "placement_cost": 15, "maintenance_cost": 1, "beauty_bonus": 5},
	# Rocky ground. Painted Rocks tiles render as stony ground; a boulder
	# placed on other terrain stamps this type too, but keeps its native turf
	# look (see TerrainGrid.set_object_footprint).
	Type.ROCKS: {"name": "Rocks", "color": Color(0.55, 0.52, 0.48), "playable": true, "placement_cost": 8, "maintenance_cost": 0, "shot_difficulty": 0.8},
	# Links-style fast running turf: plays like fairway but the ball releases.
	Type.FIRM_FAIRWAY: {"name": "Firm Fairway", "color": Color(0.62, 0.70, 0.38), "playable": true, "placement_cost": 6, "maintenance_cost": 1, "shot_difficulty": 0.05},
	# Small, deep bunker with a steep revetted face — wedge out, often sideways.
	Type.POT_BUNKER: {"name": "Pot Bunker", "color": Color(0.84, 0.76, 0.54), "playable": true, "placement_cost": 18, "maintenance_cost": 2, "shot_difficulty": 0.85, "is_hazard": true},
	# Narrow running water (a burn/creek). Same penalty as Water, but golfers
	# can still walk across it, so it can cut through the middle of a hole.
	Type.STREAM: {"name": "Stream", "color": Color(0.33, 0.62, 0.76), "playable": false, "placement_cost": 15, "maintenance_cost": 1, "is_hazard": true, "penalty_strokes": 1, "beauty_bonus": 2},
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

## Every terrain type the player can paint from the Course Terrain tab, in
## toolbar order.
const COURSE_PAINT_TYPES: Array[int] = [
	Type.FAIRWAY, Type.FIRM_FAIRWAY, Type.ROUGH, Type.DEEP_ROUGH, Type.GREEN,
	Type.TEE_BOX, Type.WASTE_BUNKER, Type.BRUSH,
	Type.BUNKER, Type.POT_BUNKER, Type.WATER, Type.STREAM, Type.ROCKS,
	Type.OUT_OF_BOUNDS,
]
