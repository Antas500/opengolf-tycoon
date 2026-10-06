extends RefCounted
class_name WorldLocations
## WorldLocations - Static catalog of the course locations on the world map.
##
## Each location is a separate course site with its own theme (CourseTheme.Type)
## and land size. A location's land is a block of parcels on the standard 6x6
## parcel grid (see LandManager); the block always contains the central 2x2
## starting parcel cluster so every location can host a golf course.
##
## Price = (size base price + value of the land that comes pre-cleared)
##         x theme land multiplier x location prestige
##
## The amount of pre-cleared ("already unlocked") land is rolled per world
## (see WorldMap) — a richer plot costs more, so the Reset World button
## re-prices the map.

enum Size { SMALL, MEDIUM, LARGE, CHAMPIONSHIP }

## Land value of one parcel that is already unlocked when the location is bought.
const LAND_VALUE_PER_PARCEL: int = 2200

## Where each location's visiting-golfer JSON file lives (50 golfers each).
## Each file is a JSON array of objects with keys: name, skin_id, tier,
## group_colors ({Shirt, Pants, Cap, Hair, Skin} → hex colour string).
const VISITING_GOLFERS_ROOT: String = "res://data/visiting_golfers"

## Every location's unlocked land includes at least the central parcel cluster.
const MIN_UNLOCKED_PARCELS: int = 4

## Parcels required to build the biggest generated layout (18 holes).
const CHAMPIONSHIP_PARCELS: int = 9

const SIZE_DATA: Dictionary = {
	Size.SMALL: {
		"name": "Small",
		"parcels": 9,
		"base_price": 15000,
		"hole_capacity": 9,
		"description": "A compact site — room for a nine-hole course and a clubhouse.",
	},
	Size.MEDIUM: {
		"name": "Medium",
		"parcels": 12,
		"base_price": 24000,
		"hole_capacity": 12,
		"description": "A comfortable site with room to grow past the first nine.",
	},
	Size.LARGE: {
		"name": "Large",
		"parcels": 16,
		"base_price": 36000,
		"hole_capacity": 16,
		"description": "A generous site that can host a full 18-hole layout.",
	},
	Size.CHAMPIONSHIP: {
		"name": "Championship",
		"parcels": 20,
		"base_price": 52000,
		"hole_capacity": 18,
		"description": "A championship-sized estate built for tournament golf.",
	},
}

## The world catalog. `lat`/`lon` place the marker on the globe.
const LOCATIONS: Array[Dictionary] = [
	{
		"id": "monterey", "name": "Monterey", "region": "California Coast",
		"theme": CourseTheme.Type.LINKS, "size": Size.MEDIUM,
		"lat": 36.60, "lon": -121.89, "prestige": 1.10,
		"description": "Cold Pacific air, cypress and clifftop fairways above the bay.",
	},
	{
		"id": "san_diego", "name": "San Diego", "region": "Southern California",
		"theme": CourseTheme.Type.RESORT, "size": Size.SMALL,
		"lat": 32.72, "lon": -117.16, "prestige": 1.05,
		"description": "Sunny resort golf with ocean views and year-round play.",
	},
	{
		"id": "rocky_mountains", "name": "Rocky Mountains", "region": "Colorado",
		"theme": CourseTheme.Type.MOUNTAIN, "size": Size.CHAMPIONSHIP,
		"lat": 39.55, "lon": -105.78, "prestige": 1.15,
		"description": "Thin air and dramatic elevation changes among the pines.",
	},
	{
		"id": "las_vegas", "name": "Las Vegas", "region": "Nevada",
		"theme": CourseTheme.Type.DESERT, "size": Size.LARGE,
		"lat": 36.17, "lon": -115.14, "prestige": 1.20,
		"description": "Neon, hardpan and island greens in the middle of the Mojave.",
	},
	{
		"id": "phoenix", "name": "Phoenix", "region": "Arizona",
		"theme": CourseTheme.Type.DESERT, "size": Size.MEDIUM,
		"lat": 33.45, "lon": -112.07, "prestige": 1.00,
		"description": "Saguaro-lined target golf where every yard is earned.",
	},
	{
		"id": "hawaii", "name": "Hawaii", "region": "Pacific Islands",
		"theme": CourseTheme.Type.TROPICAL, "size": Size.MEDIUM,
		"lat": 19.90, "lon": -155.58, "prestige": 1.25,
		"description": "Lava rock, black sand and trade winds off the Kohala coast.",
	},
	{
		"id": "oahu", "name": "Oahu", "region": "Pacific Islands",
		"theme": CourseTheme.Type.TROPICAL, "size": Size.SMALL,
		"lat": 21.35, "lon": -157.93, "prestige": 1.10,
		"description": "A tight island track with ocean carries and jungle rough.",
	},
	{
		"id": "nova_scotia", "name": "Nova Scotia", "region": "Atlantic Canada",
		"theme": CourseTheme.Type.LINKS, "size": Size.SMALL,
		"lat": 44.65, "lon": -63.58, "prestige": 0.95,
		"description": "Raw maritime links golf on windswept Atlantic dunes.",
	},
	{
		"id": "northeast", "name": "Northeast", "region": "New England",
		"theme": CourseTheme.Type.PARKLAND, "size": Size.LARGE,
		"lat": 42.35, "lon": -71.10, "prestige": 1.05,
		"description": "Classic New England parkland framed by maples and stone walls.",
	},
	{
		"id": "carolina", "name": "Carolina", "region": "Lowcountry",
		"theme": CourseTheme.Type.MARSHLAND, "size": Size.LARGE,
		"lat": 33.75, "lon": -78.85, "prestige": 1.00,
		"description": "Tidal creeks, marsh grass and live oaks draped in Spanish moss.",
	},
	{
		"id": "florida", "name": "Florida", "region": "Gulf Coast",
		"theme": CourseTheme.Type.MARSHLAND, "size": Size.LARGE,
		"lat": 27.95, "lon": -81.40, "prestige": 1.05,
		"description": "Water everywhere, palm-lined fairways and afternoon storms.",
	},
	{
		"id": "chicago", "name": "Chicago", "region": "Great Lakes",
		"theme": CourseTheme.Type.CITY, "size": Size.LARGE,
		"lat": 41.85, "lon": -87.65, "prestige": 1.05,
		"description": "A muscular municipal course on the shore of Lake Michigan.",
	},
	{
		"id": "new_york", "name": "New York", "region": "East Coast",
		"theme": CourseTheme.Type.CITY, "size": Size.MEDIUM,
		"lat": 40.75, "lon": -73.98, "prestige": 1.25,
		"description": "City golf with skyline views and premium green fees.",
	},
	{
		"id": "ireland", "name": "Ireland", "region": "West Coast",
		"theme": CourseTheme.Type.LINKS, "size": Size.LARGE,
		"lat": 53.35, "lon": -8.00, "prestige": 1.15,
		"description": "Rugged links land, pot bunkers and Atlantic squalls.",
	},
	{
		"id": "scotland", "name": "Scotland", "region": "Fife",
		"theme": CourseTheme.Type.LINKS, "size": Size.CHAMPIONSHIP,
		"lat": 56.40, "lon": -3.20, "prestige": 1.30,
		"description": "The home of golf — fescue, gorse and wind off the Firth.",
	},
	{
		"id": "wales", "name": "Wales", "region": "Celtic Coast",
		"theme": CourseTheme.Type.HEATHLAND, "size": Size.MEDIUM,
		"lat": 52.30, "lon": -3.80, "prestige": 1.00,
		"description": "Heather, gorse and sandy inland turf under slate-grey skies.",
	},
	{
		"id": "south_england", "name": "South England", "region": "Home Counties",
		"theme": CourseTheme.Type.HEATHLAND, "size": Size.MEDIUM,
		"lat": 51.20, "lon": -0.90, "prestige": 1.05,
		"description": "Rolling heathland with deep pot bunkers and firm turf.",
	},
	{
		"id": "spain", "name": "Spain", "region": "Costa del Sol",
		"theme": CourseTheme.Type.RESORT, "size": Size.MEDIUM,
		"lat": 36.72, "lon": -4.42, "prestige": 1.00,
		"description": "Olive groves, whitewashed clubhouses and Mediterranean sun.",
	},
	{
		"id": "portugal", "name": "Portugal", "region": "Algarve",
		"theme": CourseTheme.Type.RESORT, "size": Size.SMALL,
		"lat": 37.02, "lon": -7.93, "prestige": 0.95,
		"description": "Clifftop resort golf above golden Algarve beaches.",
	},
	{
		"id": "jamaica", "name": "Jamaica", "region": "Caribbean",
		"theme": CourseTheme.Type.TROPICAL, "size": Size.MEDIUM,
		"lat": 18.11, "lon": -77.30, "prestige": 1.00,
		"description": "Palm groves, turquoise water and a relaxed island pace.",
	},
	{
		"id": "bahamas", "name": "Bahamas", "region": "Caribbean",
		"theme": CourseTheme.Type.TROPICAL, "size": Size.SMALL,
		"lat": 25.05, "lon": -77.35, "prestige": 1.05,
		"description": "A short island course ringed by sand and reef.",
	},
	{
		"id": "japan", "name": "Japan", "region": "Kanto",
		"theme": CourseTheme.Type.WOODLAND, "size": Size.MEDIUM,
		"lat": 35.68, "lon": 139.75, "prestige": 1.15,
		"description": "Tight tree-lined corridors cut through cedar forest.",
	},
	{
		"id": "dubai", "name": "Dubai", "region": "Arabian Gulf",
		"theme": CourseTheme.Type.DESERT, "size": Size.LARGE,
		"lat": 25.20, "lon": 55.27, "prestige": 1.25,
		"description": "Man-made lakes and manicured green amid the dunes.",
	},
	{
		"id": "south_africa", "name": "South Africa", "region": "Western Cape",
		"theme": CourseTheme.Type.HEATHLAND, "size": Size.MEDIUM,
		"lat": -33.92, "lon": 18.42, "prestige": 1.00,
		"description": "Fynbos, mountain backdrops and a stiff Cape southeaster.",
	},
	{
		"id": "australia", "name": "Australia", "region": "Sandbelt",
		"theme": CourseTheme.Type.HEATHLAND, "size": Size.LARGE,
		"lat": -37.85, "lon": 144.95, "prestige": 1.05,
		"description": "Firm sandbelt turf and fiercely bunkered greens.",
	},
	{
		"id": "new_zealand", "name": "New Zealand", "region": "South Island",
		"theme": CourseTheme.Type.LINKS, "size": Size.MEDIUM,
		"lat": -41.30, "lon": 174.75, "prestige": 1.00,
		"description": "Wild coastal links between the mountains and the sea.",
	},
	{
		"id": "vancouver", "name": "Pacific Northwest", "region": "British Columbia",
		"theme": CourseTheme.Type.WOODLAND, "size": Size.MEDIUM,
		"lat": 49.28, "lon": -123.12, "prestige": 1.00,
		"description": "Rainforest, fjord views and soft, damp fairways.",
	},
]

## Get every location definition.
static func get_all() -> Array[Dictionary]:
	return LOCATIONS

## Look up one definition by id (empty dictionary when unknown).
static func get_definition(location_id: String) -> Dictionary:
	for def in LOCATIONS:
		if def["id"] == location_id:
			return def
	return {}

## True when `location_id` names a location in the catalog.
static func has_location(location_id: String) -> bool:
	return not get_definition(location_id).is_empty()

static func get_size_data(size: int) -> Dictionary:
	return SIZE_DATA.get(size, SIZE_DATA[Size.SMALL])

static func get_size_name(size: int) -> String:
	return str(get_size_data(size).get("name", "Small"))

## How many parcels of land belong to a location of this size.
static func get_parcel_count(size: int) -> int:
	return int(get_size_data(size).get("parcels", 9))

## The biggest generated layout this size of location is advertised to host.
static func get_hole_capacity(size: int) -> int:
	return int(get_size_data(size).get("hole_capacity", 9))

## Land is worth more in some themes (desert is cheap, city is dear).
static func get_land_multiplier(theme: int) -> float:
	var modifiers := CourseTheme.get_gameplay_modifiers(theme)
	return float(modifiers.get("land_cost_multiplier", 1.0))

## What a location costs when `unlocked_count` parcels come pre-cleared
## (an alias for compute_price, kept readable at call sites).
static func get_price_for_land(location_id: String, unlocked_count: int) -> int:
	return compute_price(location_id, unlocked_count)

## What a location costs when `unlocked_count` parcels come pre-cleared.
static func compute_price(location_id: String, unlocked_count: int) -> int:
	var def := get_definition(location_id)
	if def.is_empty():
		return 0
	var base := float(get_size_data(int(def["size"])).get("base_price", 15000))
	var prestige := float(def.get("prestige", 1.0))
	var land_value := float(maxi(unlocked_count, 0) * LAND_VALUE_PER_PARCEL)
	var price := (base + land_value) * get_land_multiplier(int(def["theme"])) * prestige
	# Round to the nearest 100 so the list reads like a price tag.
	return int(round(price / 100.0)) * 100

## The parcels every location needs so the generated first course fits:
## the central 2x2 (parcels 2..3 x 2..3) for up to 9 holes, a 3x3 block
## (parcels 1..3 x 1..3) for a full 18.
static func get_required_parcels(hole_count: int) -> Array:
	if hole_count >= 18:
		return get_block_parcels(1, 1, 4, 4)
	return get_block_parcels(2, 2, 4, 4)

## A rectangular parcel block [from_x, from_y] .. [to_x, to_y) in grid coords
## (the upper bound is exclusive, matching range()).
static func get_block_parcels(from_x: int, from_y: int, to_x: int, to_y: int) -> Array:
	var result: Array = []
	for x in range(from_x, to_x):
		for y in range(from_y, to_y):
			result.append(Vector2i(x, y))
	return result

## Parcels of a location ordered from the centre outwards, with a per-world
## random tiebreak so two worlds of the same size do not share a shape.
static func growth_order(size: int, rng: RandomNumberGenerator) -> Array:
	var center := Vector2(2.5, 2.5)
	var wanted := clampi(get_parcel_count(size), MIN_UNLOCKED_PARCELS, 36)
	var candidates: Array = []
	for x in range(6):
		for y in range(6):
			var pos := Vector2i(x, y)
			candidates.append({
				"pos": pos,
				"distance": Vector2(pos).distance_to(center),
				"jitter": rng.randf(),
			})
	candidates.sort_custom(func(a, b):
		if not is_equal_approx(a["distance"], b["distance"]):
			return a["distance"] < b["distance"]
		return a["jitter"] < b["jitter"])
	var order: Array = []
	for entry in candidates:
		if order.size() >= wanted:
			break
		order.append(entry["pos"])
	return order

## The land a location actually spans: its size decides how much land it has,
## but it always includes the parcels the generated first course needs. Without
## this a small site could come with pre-cleared land outside its own block.
static func layout_order(size: int, rng: RandomNumberGenerator, required: Array = []) -> Array:
	var order: Array = []
	for pos in required:
		if not order.has(pos):
			order.append(pos)
	for pos in growth_order(size, rng):
		if order.size() >= maxi(get_parcel_count(size), order.size()):
			break
		if not order.has(pos):
			order.append(pos)
	return order

## How many parcels a location of this size may have pre-unlocked at most.
static func max_unlocked_for_size(size: int) -> int:
	var total := get_parcel_count(size)
	return clampi(int(round(total * 0.75)), MIN_UNLOCKED_PARCELS, total)

## A random golf company name for Quick Start (and the Random button).
static func random_company_name(rng: RandomNumberGenerator = null) -> String:
	var prefixes := [
		"Eagle", "Fairway", "Sunset", "Highland", "Emerald", "Cypress",
		"Pinecrest", "Coastal", "Golden", "Summit", "Meadow", "Harbour",
		"Bogey", "Caddie", "Divot", "Links", "Sandbelt", "Birdie",
	]
	var suffixes := [
		"Golf Co.", "Golf Group", "Golf Club", "Golf Ventures", "Golf Holdings",
		"Country Club", "Golf Resorts", "Golf Partners", "Golf & Leisure",
	]
	var pick := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		pick.randomize()
	return "%s %s" % [prefixes[pick.randi_range(0, prefixes.size() - 1)],
		suffixes[pick.randi_range(0, suffixes.size() - 1)]]


# ==============================================================================
# VISITING GOLFERS
# ==============================================================================

## Every visiting golfer definition for a location. Reads from the per-location
## JSON file in `data/visiting_golfers/<id>.json` once and caches the result.
static func get_visiting_golfers(location_id: String) -> Array:
	if _visitor_cache.has(location_id):
		return _visitor_cache[location_id]
	var path := VISITING_GOLFERS_ROOT.path_join(location_id + ".json")
	var result: Array = []
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path)
		var parsed = JSON.parse_string(text)
		if parsed is Array:
			result = parsed
	_visitor_cache[location_id] = result
	return result

## Module-level cache shared across all callers (static methods need a
## dictionary that outlives the call — GDScript file-scope `var` does that).
static var _visitor_cache: Dictionary = {}

## How many visiting golfers a location has in its pool.
static func visiting_golfer_count(location_id: String) -> int:
	return get_visiting_golfers(location_id).size()

## All visiting golfer names at a location.
static func visiting_golfer_names(location_id: String) -> PackedStringArray:
	var names := PackedStringArray()
	for entry in get_visiting_golfers(location_id):
		names.append(str(entry.get("name", "")))
	return names

## Parse a visiting golfer's group_colors dictionary into Color objects.
## Keys are group names (e.g. "Shirt"), values are hex strings (e.g. "4a90d9").
static func parse_visitor_group_colors(visitor: Dictionary) -> Dictionary:
	var colors := {}
	for group_name in visitor.get("group_colors", {}):
		var hex_str := str(visitor["group_colors"][group_name])
		colors[group_name] = Color.from_string(hex_str, Color.WHITE)
	return colors

## Theme for a location id (falls back to parkland).
static func get_theme(location_id: String) -> int:
	return int(get_definition(location_id).get("theme", CourseTheme.Type.PARKLAND))
