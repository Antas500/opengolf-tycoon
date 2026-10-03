extends Node
## WorldMap - Company-level world state: the locations on the globe, which ones
## the player owns, and the company settings chosen on the Start New Game screen.
##
## Autoloaded as `WorldMap`. It owns three kinds of state:
##
##  * Company settings — company name, difficulty, starting-money option,
##    generated-hole count and the enabled game features (weather/wind/seasons).
##  * Location states — for every catalog location: its price, how many parcels
##    of land came pre-cleared with the purchase ("already unlocked"), and
##    whether the player owns it. Prices rise with the amount of cleared land,
##    so Reset World re-rolls the map and re-prices it.
##  * Per-location course snapshots — when the player swaps between owned
##    locations, the course they leave behind is kept in memory (and in the save
##    file) so it is exactly as they left it when they come back.

signal world_reset()
signal location_purchased(location_id: String)
signal active_location_changed(location_id: String)

## Starting-money option meaning "no budget limit".
const UNLIMITED_MONEY: int = -1

## Game feature keys used by the Start New Game screen.
const FEATURE_WEATHER := "weather"
const FEATURE_WIND := "wind"
const FEATURE_SEASONS := "seasons"
const FEATURE_KEYS: Array[String] = [FEATURE_WEATHER, FEATURE_WIND, FEATURE_SEASONS]

## Company settings (chosen on the Start New Game screen).
var company_name: String = "My Golf Company"
var difficulty: int = DifficultyPresets.Preset.NORMAL
var starting_money_option: int = 100000  # UNLIMITED_MONEY for unlimited funds
var generated_holes: int = 0
var features: Dictionary = {
	FEATURE_WEATHER: true,
	FEATURE_WIND: true,
	FEATURE_SEASONS: true,
}

## Location states: id -> { owned, unlocked: Array[Vector2i], price, seed }
var locations: Dictionary = {}
## Location currently being played (empty before the first course is bought).
var active_location_id: String = ""
## id -> save-data dictionary captured when the player left that location.
var location_snapshots: Dictionary = {}
## Seed of the current world roll (shown nowhere, kept for reproducibility).
var world_seed: int = 0
var world_ready: bool = false

func _ready() -> void:
	if not world_ready:
		# A default world keeps the world map usable before Start New Game has
		# run (legacy flows and tests start a course directly).
		new_world(default_options())

## The options Quick Start uses, and the fallback for a legacy game start.
static func default_options() -> Dictionary:
	return {
		"company_name": WorldLocations.random_company_name(),
		"difficulty": DifficultyPresets.Preset.NORMAL,
		"starting_money": 100000,
		"generated_holes": 0,
		"features": {
			FEATURE_WEATHER: true,
			FEATURE_WIND: true,
			FEATURE_SEASONS: true,
		},
	}

## Roll a brand new world from Start New Game options (or Quick Start defaults).
## Every location is re-priced and cleared of ownership; the player's choices
## decide how much land must come pre-cleared so the generated first course fits.
func new_world(options: Dictionary, rng_seed: int = -1) -> void:
	var rng := RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	world_seed = rng.seed

	company_name = str(options.get("company_name", "My Golf Company"))
	if company_name.strip_edges().is_empty():
		company_name = "My Golf Company"
	difficulty = int(options.get("difficulty", DifficultyPresets.Preset.NORMAL))
	starting_money_option = int(options.get("starting_money", 100000))
	generated_holes = int(options.get("generated_holes", 0))
	var saved_features: Dictionary = options.get("features", {})
	for key in FEATURE_KEYS:
		features[key] = bool(saved_features.get(key, true))

	locations.clear()
	location_snapshots.clear()
	active_location_id = ""
	_roll_locations(rng, generated_holes)

	world_ready = true
	# The company settings (including the opening budget) apply from here on:
	# the world map prices locations against the budget the player chose.
	apply_company_settings(true)
	world_reset.emit()

## Re-roll the pre-cleared land (and therefore the prices) of every location the
## player does not own yet. Owned land is never taken away.
func reset_world() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	world_seed = rng.seed
	_roll_locations(rng, generated_holes)
	world_reset.emit()

func _roll_locations(rng: RandomNumberGenerator, required_holes: int) -> void:
	var required: Array = WorldLocations.get_required_parcels(required_holes)
	for def in WorldLocations.get_all():
		var id := str(def["id"])
		var existing: Dictionary = locations.get(id, {})
		if bool(existing.get("owned", false)):
			# Keep land the player already paid for.
			continue
		var size := int(def["size"])
		var total := WorldLocations.get_parcel_count(size)
		var max_unlocked := WorldLocations.max_unlocked_for_size(size)
		var wanted := rng.randi_range(mini(WorldLocations.MIN_UNLOCKED_PARCELS, total), max_unlocked)
		var unlocked := _pick_unlocked(size, wanted, required, rng)
		locations[id] = {
			"owned": false,
			"unlocked": unlocked,
			"price": WorldLocations.compute_price(id, unlocked.size()),
			"seed": rng.randi(),
		}

## Build a location's unlocked set: the parcels the first course needs, plus
## randomly chosen extra parcels (more land is always a bigger cluster).
func _pick_unlocked(size: int, wanted: int, required: Array, rng: RandomNumberGenerator) -> Array:
	var order := WorldLocations.layout_order(size, rng, required)
	var unlocked: Array = []
	for pos in required:
		if order.has(pos) and not unlocked.has(pos):
			unlocked.append(pos)
	# The layout land is always unlocked; the roll then decides how many extra
	# parcels come ready to build on.
	var target: int = maxi(wanted, unlocked.size())
	for pos in order:
		if unlocked.size() >= target:
			break
		if not unlocked.has(pos):
			unlocked.append(pos)
	return unlocked

## True when the player owns the location.
func is_owned(location_id: String) -> bool:
	return bool(locations.get(location_id, {}).get("owned", false))

## The price of a location as currently rolled.
func get_price(location_id: String) -> int:
	return int(locations.get(location_id, {}).get("price", 0))

## The parcels that come pre-cleared with a location.
func get_unlocked_parcels(location_id: String) -> Array:
	return locations.get(location_id, {}).get("unlocked", [])

## The parcels that belong to a location's land (its full size block).
func get_location_parcels(location_id: String) -> Array:
	var def := WorldLocations.get_definition(location_id)
	if def.is_empty():
		return []
	# The block is deterministic for a location (the per-world jitter comes out
	# of its own seed) and always includes the land the generated first course
	# needs, so even a small site can host the course the player asked for.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(locations.get(location_id, {}).get("seed", 0))
	return WorldLocations.layout_order(int(def["size"]), rng,
		WorldLocations.get_required_parcels(generated_holes))

## Total number of parcels in a location's land.
func get_total_parcels(location_id: String) -> int:
	return get_location_parcels(location_id).size()

## Can the player afford this location right now?
func can_afford(location_id: String) -> bool:
	if is_owned(location_id):
		return true
	return GameManager.can_afford(get_price(location_id))

## Buy a location. Deducts the price and unlocks its pre-cleared land.
func buy_location(location_id: String) -> bool:
	if is_owned(location_id):
		return true
	if not WorldLocations.has_location(location_id):
		return false
	var price := get_price(location_id)
	if not GameManager.can_afford(price):
		EventBus.notify("Not enough money: %s costs $%s" % [
			WorldLocations.get_definition(location_id).get("name", location_id),
			_format_money(price)], "error")
		return false
	GameManager.modify_money(-price)
	EventBus.log_transaction("Bought %s" % WorldLocations.get_definition(location_id).get("name", location_id), -price)
	locations[location_id]["owned"] = true
	EventBus.notify("%s purchased! %d parcels of land came ready to build on." % [
		WorldLocations.get_definition(location_id).get("name", location_id),
		get_unlocked_parcels(location_id).size()], "success")
	location_purchased.emit(location_id)
	return true

## The location currently being played, or an empty dictionary.
func get_active_location() -> Dictionary:
	return WorldLocations.get_definition(active_location_id)

## Mark a location as the one being played.
func set_active_location(location_id: String) -> void:
	if active_location_id == location_id:
		return
	active_location_id = location_id
	active_location_changed.emit(location_id)

## Apply the company settings to the GameManager. `with_money` is true when a
## brand new game is starting (the budget option becomes the opening balance);
## a loaded game keeps the balance from the save file.
func apply_company_settings(with_money: bool = false) -> void:
	GameManager.current_difficulty = difficulty
	GameManager.company_name = company_name
	GameManager.set_feature_enabled(FEATURE_WEATHER, features[FEATURE_WEATHER])
	GameManager.set_feature_enabled(FEATURE_WIND, features[FEATURE_WIND])
	GameManager.set_feature_enabled(FEATURE_SEASONS, features[FEATURE_SEASONS])
	GameManager.set_unlimited_money(starting_money_option == UNLIMITED_MONEY)
	if with_money:
		if starting_money_option == UNLIMITED_MONEY:
			GameManager.money = GameManager.UNLIMITED_STARTING_BALANCE
		else:
			GameManager.money = starting_money_option
		EventBus.money_changed.emit(0, GameManager.money)

## Give the current location's land to the land manager: pre-cleared parcels are
## owned, every other parcel of the location's block stays purchasable.
func apply_location_land(location_id: String) -> void:
	var land_manager = GameManager.land_manager
	if not land_manager:
		return
	land_manager.set_location_parcels(get_location_parcels(location_id))
	land_manager.grant_parcels(get_unlocked_parcels(location_id))

## Apply the money option without touching difficulty or features (used when a
## legacy start path begins a game directly).
func apply_starting_money() -> void:
	GameManager.set_unlimited_money(starting_money_option == UNLIMITED_MONEY)

## Store the course a player just left.
func take_snapshot(location_id: String, snapshot: Dictionary) -> void:
	if location_id.is_empty():
		return
	location_snapshots[location_id] = snapshot

func has_snapshot(location_id: String) -> bool:
	return location_snapshots.has(location_id)

func get_snapshot(location_id: String) -> Dictionary:
	return location_snapshots.get(location_id, {})

func clear_snapshot(location_id: String) -> void:
	location_snapshots.erase(location_id)

## Ensure a world exists for a game started outside the normal flow (legacy
## "new game" entry points, tests and harnesses). The location matching the
## requested theme is owned and made active.
func ensure_legacy_world(theme: int) -> String:
	if not world_ready or locations.is_empty():
		new_world(default_options())
	var preferred := ""
	for def in WorldLocations.get_all():
		if int(def["theme"]) == theme and WorldLocations.get_definition(str(def["id"]))["size"] != WorldLocations.Size.CHAMPIONSHIP:
			preferred = str(def["id"])
			break
	if preferred.is_empty():
		preferred = str(WorldLocations.get_all()[0]["id"])
	locations[preferred]["owned"] = true
	set_active_location(preferred)
	return preferred

## ── Serialization ─────────────────────────────────────────────────────────

func serialize() -> Dictionary:
	var location_data: Dictionary = {}
	for id in locations:
		var state: Dictionary = locations[id]
		var unlocked: Array = []
		for parcel in state.get("unlocked", []):
			unlocked.append({"x": parcel.x, "y": parcel.y})
		location_data[id] = {
			"owned": bool(state.get("owned", false)),
			"unlocked": unlocked,
			"price": int(state.get("price", 0)),
			"seed": int(state.get("seed", 0)),
		}
	var snapshots: Dictionary = {}
	for id in location_snapshots:
		snapshots[id] = location_snapshots[id]
	return {
		"seed": world_seed,
		"company_name": company_name,
		"difficulty": DifficultyPresets.to_string_name(difficulty),
		"starting_money": starting_money_option,
		"generated_holes": generated_holes,
		"features": features.duplicate(),
		"active_location": active_location_id,
		"locations": location_data,
		"snapshots": snapshots,
	}

func deserialize(data: Dictionary) -> void:
	if data.is_empty():
		return
	world_seed = int(data.get("seed", 0))
	company_name = str(data.get("company_name", company_name))
	difficulty = DifficultyPresets.from_string(str(data.get("difficulty", "normal")))
	starting_money_option = int(data.get("starting_money", 100000))
	generated_holes = int(data.get("generated_holes", 0))
	var saved_features: Dictionary = data.get("features", {})
	for key in FEATURE_KEYS:
		features[key] = bool(saved_features.get(key, true))

	var saved_locations: Dictionary = data.get("locations", {})
	if saved_locations.is_empty():
		# Older saves predate the world map: keep the rolled world, no owners.
		world_ready = true
	else:
		locations.clear()
		for id in saved_locations:
			var state: Dictionary = saved_locations[id]
			var unlocked: Array = []
			for parcel in state.get("unlocked", []):
				unlocked.append(Vector2i(int(parcel.get("x", 0)), int(parcel.get("y", 0))))
			locations[id] = {
				"owned": bool(state.get("owned", false)),
				"unlocked": unlocked,
				"price": int(state.get("price", 0)),
				"seed": int(state.get("seed", 0)),
			}
		world_ready = true

	location_snapshots.clear()
	var saved_snapshots: Dictionary = data.get("snapshots", {})
	for id in saved_snapshots:
		var snapshot = saved_snapshots[id]
		if snapshot is Dictionary:
			location_snapshots[id] = snapshot
	active_location_id = str(data.get("active_location", ""))
	# Difficulty, budget option and the enabled features travel with the world.
	# The balance itself comes from the save file, not the budget option.
	apply_company_settings(false)
	world_reset.emit()

func _format_money(amount: int) -> String:
	var s := str(absi(amount))
	var result := ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			result += ","
		result += s[i]
	return result
