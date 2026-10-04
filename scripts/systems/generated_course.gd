extends RefCounted
class_name GeneratedCourse
## GeneratedCourse - Builds the partially generated first course.
##
## Start New Game lets the player begin with 0, 3, 6, 9 or 18 holes already
## laid out. This class owns those four layouts. Each layout is a set of
## tee/green offsets measured from a fixed anchor on the parcel grid, so a
## generated course always lands on the land the world map guaranteed:
##
##  * up to 9 holes — anchored on the central 2x2 parcel cluster
##    (tiles 44..83, exactly the plot every location starts with), so every
##    location can host them;
##  * 18 holes — anchored on the 3x3 parcel block (tiles 24..83) the world map
##    pre-clears whenever 18 generated holes are requested.
##
## The layouts keep the hole count, par mix and non-overlap guarantees used by
## the Quick Start course, and are painted with the same helpers
## (QuickStartCourse._paint_hole and friends). PrebuiltCourseGenerator keeps its
## own copies for the (legacy) prebuilt packages so already-shipped layouts do
## not shift under existing saves.

## Hole counts the Start New Game screen offers.
const SUPPORTED_HOLE_COUNTS: Array[int] = [0, 3, 6, 9, 18]

## Tile anchor for the small layouts (the centre of the central 2x2 parcels).
const SMALL_ANCHOR := Vector2i(63, 63)
## Tile anchor for the 18-hole layout (the centre of the 3x3 parcel block).
const CHAMPIONSHIP_ANCHOR := Vector2i(53, 53)

## [tee_offset, green_offset, corridor_width, water_offset_or_null, extra_bunker_or_null]
const LAYOUT_3: Array = [
	[Vector2i(-14, -8), Vector2i(2, -6), 5, null, null],          # Par 4, E
	[Vector2i(5, -8), Vector2i(6, 1), 3, null, null],             # Par 3, S
	[Vector2i(8, 4), Vector2i(-14, 6), 5, Vector2i(-4, 5), null], # Par 5, W
]

## Perimeter six: two par 3s, one par 5 and three par 4s around the plot edge.
const LAYOUT_6: Array = [
	[Vector2i(-17, -17), Vector2i(-1, -15), 5, null, null],        # Par 4, E
	[Vector2i(2, -17), Vector2i(11, -17), 3, null, null],          # Par 3, E
	[Vector2i(13, -15), Vector2i(17, 9), 5, Vector2i(15, -3), null], # Par 5, S
	[Vector2i(15, 12), Vector2i(-1, 17), 5, null, Vector2i(5, 15)], # Par 4, W
	[Vector2i(-4, 17), Vector2i(-17, 7), 5, null, null],           # Par 4, NW
	[Vector2i(-17, 4), Vector2i(-15, -11), 5, null, null],         # Par 4, N
]

## Nine holes snaking around the plot then cutting through the middle.
const LAYOUT_9: Array = [
	[Vector2i(-17, -17), Vector2i(-1, -15), 5, null, null],          # H1: Par 4, E
	[Vector2i(2, -17), Vector2i(11, -17), 3, null, null],            # H2: Par 3, E
	[Vector2i(13, -15), Vector2i(17, 9), 5, Vector2i(15, -3), null], # H3: Par 5, S
	[Vector2i(15, 12), Vector2i(-1, 17), 5, null, Vector2i(5, 15)],  # H4: Par 4, W
	[Vector2i(-4, 17), Vector2i(-17, 7), 5, null, null],             # H5: Par 4, NW
	[Vector2i(-17, 4), Vector2i(-15, -11), 5, null, null],           # H6: Par 4, N
	[Vector2i(-13, -13), Vector2i(9, -7), 5, Vector2i(-1, -7), null],# H7: Par 5, E
	[Vector2i(11, -5), Vector2i(15, 3), 3, Vector2i(13, -1), null],  # H8: Par 3, SE
	[Vector2i(13, 5), Vector2i(-1, 1), 5, null, null],               # H9: Par 4, W
]

## Full 18 holes (Par 72): the nine-hole layout as the front nine, then a
## counter-clockwise outer loop for the back nine. Every corridor lives in the
## 3x3 parcel block (offsets stay within ±27 tiles of the anchor), and the yard
## par mix is 4x par 3, 10x par 4, 4x par 5.
const LAYOUT_18_FRONT: Array = LAYOUT_9

const LAYOUT_18_BACK: Array = [
	[Vector2i(-27, -24), Vector2i(-11, -24), 5, null],        # H10: Par 4, E (352y)
	[Vector2i(-8, -24), Vector2i(4, -24), 5, null],           # H11: Par 4, E (264y)
	[Vector2i(7, -24), Vector2i(15, -24), 3, null],           # H12: Par 3, E (176y)
	[Vector2i(20, -24), Vector2i(20, -2), 5, Vector2i(17, -13)], # H13: Par 5, S (484y)
	[Vector2i(22, 0), Vector2i(22, 16), 5, null],             # H14: Par 4, S (352y)
	[Vector2i(24, 20), Vector2i(2, 20), 5, Vector2i(13, 23)], # H15: Par 5, W (484y)
	[Vector2i(0, 23), Vector2i(-14, 23), 5, null],            # H16: Par 4, W (308y)
	[Vector2i(-17, 23), Vector2i(-25, 23), 3, null],          # H17: Par 3, W (176y)
	[Vector2i(-27, 20), Vector2i(-27, 4), 5, null],           # H18: Par 4, N (352y)
]

## The anchor a layout of this size is built around.
static func get_anchor(hole_count: int) -> Vector2i:
	return CHAMPIONSHIP_ANCHOR if hole_count >= 18 else SMALL_ANCHOR

## Par mix of a generated course, for display on the Start New Game screen.
static func get_par_for_count(hole_count: int) -> int:
	match hole_count:
		3: return 12
		6: return 24
		9: return 36
		18: return 72
		_: return 0

## Build `hole_count` holes on the current terrain grid. Returns how many holes
## were actually opened (0 when the layout does not fit the owned land).
static func generate(
	hole_count: int,
	terrain_grid: TerrainGrid,
	entity_layer: EntityLayer,
	hole_tool: HoleCreationTool
) -> int:
	if hole_count <= 0 or not terrain_grid or not hole_tool:
		return 0
	if not can_generate(hole_count):
		EventBus.notify("Not enough land for a %d-hole layout — buy more plots first." % hole_count, "warning")
		return 0

	var anchor := get_anchor(hole_count)
	var created := 0
	for hole in _get_layout(hole_count):
		var tee: Vector2i = anchor + Vector2i(hole[0])
		var green: Vector2i = anchor + Vector2i(hole[1])
		QuickStartCourse._paint_hole(terrain_grid, tee, green, int(hole[2]))
		if hole[3] != null:
			QuickStartCourse._paint_water_hazard(terrain_grid, anchor + Vector2i(hole[3]), 2)
		if hole.size() > 4 and hole[4] != null:
			QuickStartCourse._paint_extra_bunker(terrain_grid, anchor + Vector2i(hole[4]))
		if hole_tool.create_generated_hole(tee, green) != null:
			created += 1
		else:
			push_warning("GeneratedCourse: could not open a hole from %s to %s" % [tee, green])

	if entity_layer:
		QuickStartCourse._clear_entities_on_course(terrain_grid, entity_layer)
	_place_starter_amenity(terrain_grid, entity_layer, anchor)
	if created > 0:
		EventBus.notify("%d generated holes are ready to play — build the rest of the course around them." % created, "success")
	return created

## Can this layout be built with the land the player owns right now?
static func can_generate(hole_count: int) -> bool:
	var land_manager = GameManager.land_manager
	if not land_manager:
		return true
	for parcel in WorldLocations.get_required_parcels(hole_count):
		if not land_manager.owned_parcels.has(parcel):
			return false
	return true

## The layout `generate` paints for `hole_count` holes (empty for 0 or an
## unsupported count), in the same [tee, green, corridor, water, bunker]
## offset form as the LAYOUT_* tables. The Start New Game screen draws its
## course plan preview from this, so the preview is always the real layout.
static func layout_for(hole_count: int) -> Array:
	return _get_layout(hole_count)

static func _get_layout(hole_count: int) -> Array:
	match hole_count:
		3:
			return LAYOUT_3
		6:
			return LAYOUT_6
		9:
			return LAYOUT_9
		18:
			return LAYOUT_18_FRONT + LAYOUT_18_BACK
	return []

## A small clubhouse cluster sits in the pocket every layout leaves clear
## (offsets (1,6)..(8,11) from the anchor) and gives a generated course a
## revenue stream from day one. A footprint that would sit on a playing surface
## or another building is skipped rather than bulldozed into the course.
const AMENITY_SPOTS: Array = [
	["clubhouse", Vector2i(1, 6)],
	["coffee_house", Vector2i(6, 6)],
	["snack_bar", Vector2i(6, 9)],
	["restroom", Vector2i(8, 9)],
]

static func _place_starter_amenity(terrain_grid: TerrainGrid, entity_layer: EntityLayer, anchor: Vector2i) -> void:
	if not entity_layer:
		return
	var buildings: Dictionary = {}
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))
	if raw is Dictionary and raw.has("buildings"):
		buildings = raw["buildings"]
	for item in AMENITY_SPOTS:
		var kind: String = item[0]
		if not buildings.has(kind):
			continue
		var pos: Vector2i = anchor + Vector2i(item[1])
		if _can_place_footprint(terrain_grid, entity_layer, buildings[kind], pos):
			entity_layer.place_building(kind, pos, buildings)

static func _can_place_footprint(terrain_grid: TerrainGrid, entity_layer: EntityLayer, data: Dictionary, origin: Vector2i) -> bool:
	var size: Array = data.get("size", [1, 1])
	for dx in range(int(size[0])):
		for dy in range(int(size[1])):
			var pos := origin + Vector2i(dx, dy)
			if not terrain_grid.is_valid_position(pos):
				return false
			if terrain_grid.get_tile(pos) in [
				TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.GREEN,
				TerrainTypes.Type.TEE_BOX, TerrainTypes.Type.BUNKER,
				TerrainTypes.Type.WATER, TerrainTypes.Type.PATH,
			]:
				return false
			if entity_layer.is_tile_occupied_by_building(pos):
				return false
	return true
