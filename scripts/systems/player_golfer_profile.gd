extends RefCounted
class_name PlayerGolferProfile
## Persistent owner golfer. Percentages are bonuses, not AI's normalized skills.
##
## The same profile also carries the owner's look: which Golfer Skin they wear
## (see GolferSkinLibrary) and the colours they chose for its parts, plus any
## skins they built themselves in the Skin Designer.
const SKILLS = ["Power Hitter", "Long Driver", "Accurate Driver", "Accurate Irons",
	"Accurate Putter", "Draw Shot (R to L)", "Fade Shot (L to R)",
	"High Backspin Shot", "Recovery Skills", "Luck"]
## Appearance keys, one per re-colourable body part. "skin_tone" keeps its
## historic name so saves written before skins existed still load.
const COLORS = ["shirt_color", "pants_color", "cap_color", "hair_color", "skin_tone",
	"shoe_color", "accent_color", "gear_color"]
## Appearance key per part of a skin (see GolferSkinLibrary.PAINTABLE_PARTS).
const APPEARANCE_KEYS = {
	"shirt": "shirt_color", "pants": "pants_color", "cap": "cap_color",
	"hair": "hair_color", "skin": "skin_tone", "shoes": "shoe_color",
	"accent": "accent_color", "gear": "gear_color",
}
const DEFAULT_APPEARANCE = {
	"shirt_color": "e65959", "pants_color": "404059", "cap_color": "3366b3",
	"hair_color": "4d331a", "skin_tone": "f2cca6", "shoe_color": "2f2a28",
	"accent_color": "f2f2f2", "gear_color": "8a8a8a",
}
## How much room the player has for their own skins.
const MAX_CUSTOM_SKINS := 24
const MAX_SKIN_NAME := 24

var golfer_name: String = "Course Owner"
var appearance: Dictionary = DEFAULT_APPEARANCE.duplicate()
## The Golfer Skin the owner plays in.
var skin_id: String = "casual"
## Recipes built in the Skin Designer, as stored by GolferSkinLibrary.SkinDef.to_recipe().
## A recipe whose id matches a shipped skin records the player's edits to that
## skin; any other id is a skin they created from scratch.
var custom_skins: Array = []
## Bumped whenever custom_skins changes, so the skin catalogue knows to rebuild.
var skin_revision: int = 0
var points: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
var initialized: bool = false

func remaining() -> int:
	var spent := 0
	for value in points:
		spent += value
	return maxi(0, 10 - spent)

func allocate(index: int, change: int, force: bool = false) -> bool:
	if (initialized and not force) or index < 0 or index >= points.size() or abs(change) != 1:
		return false
	if points[index] + change < 0 or points[index] + change > 99:
		return false
	if change > 0 and remaining() == 0:
		return false
	points[index] += change
	return true

func reallocate(index: int, change: int) -> bool:
	return allocate(index, change, true)

func bonus(index: int) -> float:
	return points[index] * 0.1

func normalized_skill(index: int) -> float:
	return 1.0 - 0.5 / (1.0 + bonus(index))

## The appearance key holding a part's colour.
static func appearance_key(part: String) -> String:
	return APPEARANCE_KEYS.get(part, part + "_color")

## The parts of a skin the player may re-colour, in appearance-key order.
static func parts_for_skin(id: String) -> Array:
	var parts: Array = []
	var skin := GolferSkinLibrary.skin_by_id(id)
	if skin == null:
		return parts
	for part in GolferSkinLibrary.PAINTABLE_PARTS:
		if skin.is_customisable(part):
			parts.append(part)
	return parts

## The colours the owner's golfer draws its skin with, keyed by body part.
func skin_colors() -> Dictionary:
	var colors := {}
	for part in parts_for_skin(skin_id):
		colors[part] = Color.from_string(str(appearance.get(appearance_key(part), "ffffff")), Color.WHITE)
	return colors

func set_part_color(part: String, colour: Color) -> void:
	appearance[appearance_key(part)] = colour.to_html(false)

## The skin the owner wears, falling back to the default when a save names a
## skin that no longer exists.
func resolved_skin() -> GolferSkinLibrary.SkinDef:
	var skin := GolferSkinLibrary.skin_by_id(skin_id)
	if skin == null:
		skin_id = GolferSkinLibrary.default_skin_id()
		skin = GolferSkinLibrary.skin_by_id(skin_id)
	return skin

func has_custom_skin(id: String) -> bool:
	return find_skin_recipe(id) >= 0


func find_skin_recipe(id: String) -> int:
	for index in custom_skins.size():
		if custom_skins[index] is Dictionary and str(custom_skins[index].get("id", "")) == id:
			return index
	return -1

## Add or replace a player-made skin recipe, keeping the profile's copy in step
## with the designer.
func store_custom_skin(recipe: Dictionary) -> bool:
	var id := str(recipe.get("id", ""))
	if id.is_empty():
		return false
	var index := find_skin_recipe(id)
	if index >= 0:
		custom_skins[index] = recipe.duplicate(true)
		skin_revision += 1
		return true
	if created_skin_count() >= MAX_CUSTOM_SKINS:
		return false
	custom_skins.append(recipe.duplicate(true))
	skin_revision += 1
	return true

## How many skins the player made themselves (edits of shipped skins are not
## counted against the limit).
func created_skin_count() -> int:
	var count := 0
	for recipe in custom_skins:
		if recipe is Dictionary and not GolferSkinLibrary.is_shipped(str(recipe.get("id", ""))):
			count += 1
	return count

## Throw away the player's edits to one skin, shipped or their own.
func remove_custom_skin(id: String) -> bool:
	var index := find_skin_recipe(id)
	if index < 0:
		return false
	custom_skins.remove_at(index)
	skin_revision += 1
	if skin_id == id and GolferSkinLibrary.is_shipped(id):
		pass
	elif skin_id == id:
		skin_id = GolferSkinLibrary.default_skin_id()
	return true

## Take another profile's look and skins across into this one - used when a new
## game starts, so the golfer the player built in the designer stays theirs.
func carry_over_from(other: PlayerGolferProfile) -> void:
	if other == null:
		return
	appearance = other.appearance.duplicate()
	skin_id = other.skin_id
	custom_skins = other.custom_skins.duplicate(true)
	skin_revision = other.skin_revision
	if not other.golfer_name.is_empty():
		golfer_name = other.golfer_name


## Add any of another profile's own skins this one does not have. Used when a
## game is loaded: the save's look wins, but skins built on the title screen
## before the save was opened are not thrown away.
func merge_skins_from(other: PlayerGolferProfile) -> void:
	if other == null:
		return
	for recipe in other.custom_skins:
		if not (recipe is Dictionary):
			continue
		var id := str(recipe.get("id", ""))
		if id.is_empty() or has_custom_skin(id) or created_skin_count() >= MAX_CUSTOM_SKINS:
			continue
		custom_skins.append(recipe.duplicate(true))
		skin_revision += 1


func serialize() -> Dictionary:
	return {"name": golfer_name, "appearance": appearance.duplicate(),
		"skin": skin_id, "custom_skins": custom_skins.duplicate(true),
		"points": points.duplicate(), "initialized": initialized}

static func from_data(data: Dictionary) -> PlayerGolferProfile:
	var profile := PlayerGolferProfile.new()
	profile.golfer_name = str(data.get("name", "Course Owner")).strip_edges().left(32)
	if profile.golfer_name.is_empty():
		profile.golfer_name = "Course Owner"
	var colors = data.get("appearance", {})
	if colors is Dictionary:
		for key in COLORS:
			if not colors.has(key):
				continue
			profile.appearance[key] = Color.from_string(str(colors[key]),
				Color.from_string(str(profile.appearance[key]), Color.WHITE)).to_html(false)
	var saved_skins = data.get("custom_skins", [])
	if saved_skins is Array:
		for recipe in saved_skins:
			if recipe is Dictionary:
				profile.custom_skins.append(recipe.duplicate(true))
	# A save may name one of the player's own skins: those live in the recipes
	# being loaded here, so they are checked against the draft profile rather
	# than the catalogue (which still knows only the previous profile).
	var wanted_skin := str(data.get("skin", GolferSkinLibrary.default_skin_id()))
	profile.skin_id = GolferSkinLibrary.default_skin_id()
	if GolferSkinLibrary.skin_by_id(wanted_skin) != null or profile.has_custom_skin(wanted_skin):
		profile.skin_id = wanted_skin
	var saved = data.get("points", [])
	if saved is Array and saved.size() == SKILLS.size():
		for i in SKILLS.size():
			profile.points[i] = clampi(int(saved[i]), 0, 99)
	profile.initialized = bool(data.get("initialized", false))
	if not profile.initialized:
		var budget := 10
		for i in profile.points.size():
			profile.points[i] = mini(profile.points[i], budget)
			budget -= profile.points[i]
	return profile
