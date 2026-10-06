extends RefCounted
class_name GolferSkinLibrary
## GolferSkinLibrary - the catalogue of golfer skins and the factory that turns
## one into the SpriteFrames an AnimatedSprite2D plays.
##
## A *skin* is a full set of pixel art for the golfer: idle, walk and swing
## animations, eight facings each. The catalogue comes from two places:
##
##  * ``res://data/golfer_skins.json`` - the shipped skins. Thirteen themed
##    skins are drawn by ``tools/generate_golfer_skins.py``; four more records
##    mark the original hand-made tier art (Beginner/Casual/Serious/Pro) as
##    palette-recolourable skins.
##  * the owner's profile - ``PlayerGolferProfile.custom_skins`` holds recipes
##    the player built in the Skin Designer (see ``scripts/ui/golfer_skin_designer.gd``).
##
## Every pixel of the themed art is drawn from a four-or-five stop *ramp* per
## body part (base, light, dark, outline). That is what lets a golfer re-colour
## "the shirt" without repainting the sprite: a pixel is matched back to the
## ramp entry it was drawn from and re-emitted from the new colour's ramp, so
## the shading survives. The designer stores its edits the same way - as a part
## + shade index per pixel - so a skin keeps its colours when they change.
##
## All state here is static: the catalogue and the built SpriteFrames are shared
## by every golfer, so eight visitors wearing the same skin cost one build.

## The shipped catalogue.
const DATA_PATH := "res://data/golfer_skins.json"

## Plain-English names for the parts, for the colour pickers and the designer.
const PART_LABELS := {
	"shirt": "Top", "pants": "Trousers", "cap": "Headwear", "hair": "Hair / beard",
	"skin": "Skin", "shoes": "Footwear", "accent": "Trim", "gear": "Equipment",
	"eye": "Eyes", "shine": "Highlights",
}

## Body parts, in ramp order. The designer stores a pixel as
## ``1 + part_index * SHADE_COUNT + shade`` (0 = transparent).
const PART_ORDER: Array[String] = [
	"shirt", "pants", "cap", "hair", "skin", "shoes", "accent", "gear",
	"eye", "shine",
]
## Parts the player is offered in the colour pickers (the other two - eyes and
## highlights - are always drawn in their fixed colours).
const PAINTABLE_PARTS: Array[String] = [
	"shirt", "pants", "cap", "hair", "skin", "shoes", "accent", "gear",
]
const SHADE_COUNT := 5
const CANVAS := 48

## Which aimation names exist, and how they play.
const ANIMATIONS := {
	"idle": {"fps": 4.0, "loop": true, "frames": 4},
	"walk": {"fps": 8.0, "loop": true, "frames": 4},
	"swing": {"fps": 10.0, "loop": false, "frames": 6},
}
const DIRECTION_ORDER: Array[String] = [
	"south", "south-east", "east", "north-east",
	"north", "north-west", "west", "south-west",
]
## Frames a facing borrows when its own art is missing (the tier art only has
## the four cardinals).
const DIAGONAL_FALLBACK := {
	"south-east": "south", "north-east": "east",
	"north-west": "north", "south-west": "west",
}

## Colours that are never re-coloured and never offered: the eyes and the
## highlights are the same in every skin. Matching them as their own parts keeps
## a re-colour from treating an eye as a very dark shirt.
const FIXED_PART_COLOURS := {
	"eye": Color(36.0 / 255.0, 26.0 / 255.0, 28.0 / 255.0),
	"shine": Color(250.0 / 255.0, 250.0 / 255.0, 245.0 / 255.0),
}
## The parts a colour picker can change.
const FIXABLE_PARTS: Array[String] = [
	"shirt", "pants", "cap", "hair", "skin", "shoes", "accent", "gear",
]

## The palette the original hand-made tier art is drawn in - the reference for
## classifying its pixels by part.
const LEGACY_REFERENCE := {
	"shirt": Color("b41929"), "pants": Color("8c6b5f"), "cap": Color("cccbe4"),
	"hair": Color("56261c"), "skin": Color("e6a38d"), "shoes": Color("2f1813"),
	"accent": Color("dddcee"),
}
## How close a sprite pixel has to be to a ramp entry to be recognised as that
## part (squared distance in 0-1 RGB). Anything further away keeps its art.
const MATCH_TOLERANCE := 0.010
## The same, for the hand-made tier art, whose shading wanders off the ramps.
const LEGACY_TOLERANCE := 0.055

## skin id -> array of SkinDef, built once from the JSON.
static var _builtin: Array = []
static var _builtin_loaded := false
## The catalogue with the player's edits and their own skins folded in.
static var _catalogue: Array = []
static var _catalogue_signature := ""
## Built SpriteFrames, keyed by skin id + colours + revision.
static var _frames_cache: Dictionary = {}


## One skin: its art, its palette, and which parts the player may change.
class SkinDef extends RefCounted:
	var id: String = ""
	var name: String = "Golfer"
	var description: String = ""
	## Folder holding ``animations/<anim>/<direction>/frame_NNN.png``.
	var root: String = ""
	## True for the original hand-made tier art, which is re-coloured with the
	## legacy classifier rather than exact ramp matching.
	var legacy: bool = false
	## True for a skin the player made in the Skin Designer.
	var custom: bool = false
	## The built-in skin a custom skin was forked from.
	var base_id: String = ""
	var customizable: PackedStringArray = PackedStringArray()
	## part -> Color, the colours the art was drawn in.
	var colors: Dictionary = {}
	## Tier names this skin may spawn with ("beginner", "casual", "serious", "pro").
	var spawn_tiers: PackedStringArray = PackedStringArray()
	## Hand-painted frames: "<anim>_<direction>_<frame>" -> PackedByteArray of
	## part+shade indices (0 = transparent).
	var overlays: Dictionary = {}
	## Bumped whenever the overlays change, to invalidate built SpriteFrames.
	var revision: int = 0

	func is_customisable(part: String) -> bool:
		return customizable.has(part)

	func frame_key(anim: String, direction: String, frame: int) -> String:
		return "%s_%s_%d" % [anim, direction, frame]

	func has_overlay(anim: String, direction: String, frame: int) -> bool:
		return overlays.has(frame_key(anim, direction, frame))

	## The recipe stored in the owner's profile.
	func to_recipe() -> Dictionary:
		var stored := {}
		for key in overlays:
			var bytes: PackedByteArray = overlays[key]
			stored[key] = Array(bytes)
		var palette := {}
		for part in colors:
			var colour: Color = colors[part]
			palette[part] = colour.to_html(false)
		return {
			"id": id, "name": name, "description": description, "base": base_id,
			"colors": palette, "overlays": stored, "revision": revision,
		}

	static func from_recipe(data: Dictionary) -> SkinDef:
		var skin := SkinDef.new()
		skin.id = str(data.get("id", "custom"))
		skin.name = str(data.get("name", "My Skin"))
		skin.description = str(data.get("description", ""))
		skin.custom = true
		skin.base_id = str(data.get("base", "plain"))
		skin.root = ""
		skin.legacy = false
		var palette = data.get("colors", {})
		if palette is Dictionary:
			for part in palette:
				skin.colors[str(part)] = Color.from_string(str(palette[part]), Color.WHITE)
		skin.revision = int(data.get("revision", 0))
		var stored = data.get("overlays", {})
		if stored is Dictionary:
			for key in stored:
				skin.overlays[str(key)] = GolferSkinLibrary._to_bytes(stored[key])
		skin.customizable = PackedStringArray(PAINTABLE_PARTS)
		skin.spawn_tiers = PackedStringArray()
		return skin

	## A custom skin is drawn with the same parts as the skin it was forked from,
	## with the recipe's colours laid over them, so only those parts are offered.
	func inherit_from(base: SkinDef) -> void:
		root = base.root
		legacy = base.legacy
		customizable = PackedStringArray()
		for part in base.customizable:
			if PAINTABLE_PARTS.has(part):
				customizable.append(part)
		for part in PAINTABLE_PARTS:
			if not colors.has(part):
				colors[part] = base.colors.get(part, Color.WHITE)


# =============================================================================
# CATALOGUE
# =============================================================================

## Every skin the game can draw a golfer with: the shipped catalogue - with the
## player's edits to it folded in - followed by the skins they created.
static func all_skins() -> Array:
	var signature := _profile_signature()
	if signature != _catalogue_signature:
		_catalogue_signature = signature
		_catalogue = _rebuild_catalogue()
	return _catalogue


## The shipped skins, exactly as they were drawn - no player edits applied.
static func builtin_skins() -> Array:
	if not _builtin_loaded:
		_builtin_loaded = true
		_builtin = _load_builtin()
	return _builtin


## The recipes stored on the owner's profile, edits of shipped skins included.
static func player_skins() -> Array:
	var profile = GameManager.player_profile
	if profile == null:
		return []
	return profile.custom_skins


static func invalidate_catalogue() -> void:
	_catalogue_signature = ""


## The shipped catalogue, re-loaded when the game has just started.
static func reload_builtins() -> void:
	_builtin = []
	_builtin_loaded = false
	invalidate_catalogue()


## The skins the player made themselves (not edits of shipped ones).
static func custom_skins() -> Array:
	var skins: Array = []
	for skin in all_skins():
		if skin.custom and not _is_builtin_id(skin.id):
			skins.append(skin)
	return skins


static func skin_by_id(id: String) -> SkinDef:
	for skin in all_skins():
		if skin.id == id:
			return skin
	return null


static func is_shipped(id: String) -> bool:
	return _is_builtin_id(id)


static func _is_builtin_id(id: String) -> bool:
	for skin in builtin_skins():
		if skin.id == id:
			return true
	return false


static func _profile_signature() -> String:
	var profile = GameManager.player_profile
	if profile == null:
		return "none"
	return "%d:%d" % [profile.get_instance_id(), profile.skin_revision]


static func _rebuild_catalogue() -> Array:
	var edits: Dictionary = {}
	var created: Array = []
	for recipe in player_skins():
		if not (recipe is Dictionary):
			continue
		var id := str(recipe.get("id", ""))
		if _is_builtin_id(id):
			edits[id] = recipe
		else:
			created.append(recipe)

	var skins: Array = []
	for skin in builtin_skins():
		if edits.has(skin.id):
			skins.append(_merge_edit(skin, edits[skin.id]))
		else:
			skins.append(skin)
	for recipe in created:
		skins.append(_recipe_to_skin(recipe))
	return skins


## A shipped skin with the player's paint and colours laid over it. The art
## still comes from the shipped folder, so an edit only ever stores what the
## player actually changed.
static func _merge_edit(skin: SkinDef, recipe: Dictionary) -> SkinDef:
	var edited := SkinDef.from_recipe(recipe)
	edited.id = skin.id
	edited.name = str(recipe.get("name", skin.name))
	edited.description = skin.description
	edited.root = skin.root
	edited.legacy = skin.legacy
	edited.custom = true
	edited.base_id = skin.id
	edited.customizable = skin.customizable
	edited.spawn_tiers = skin.spawn_tiers
	for part in skin.colors:
		if not edited.colors.has(part):
			edited.colors[part] = skin.colors[part]
	return edited


## A skin the player created, forked from a shipped one.
static func _recipe_to_skin(recipe: Dictionary) -> SkinDef:
	var skin := SkinDef.from_recipe(recipe)
	var base: SkinDef = null
	for shipped in builtin_skins():
		if shipped.id == skin.base_id:
			base = shipped
			break
	if base == null:
		for shipped in builtin_skins():
			if shipped.id == default_skin_id():
				base = shipped
				break
	if base != null:
		skin.inherit_from(base)
	skin.custom = true
	return skin


## The skin new golfers start on: the original casual art.
static func default_skin_id() -> String:
	return "casual"


## The skin that stands for a visitor tier (the shipped tier art).
static func tier_skin_id(tier: int) -> String:
	return tier_key(tier)


static func tier_key(tier: int) -> String:
	match tier:
		GolferTier.Tier.BEGINNER:
			return "beginner"
		GolferTier.Tier.SERIOUS:
			return "serious"
		GolferTier.Tier.PRO:
			return "pro"
		_:
			return "casual"


## The skins a visitor of this tier may spawn wearing, the tier's own art first
## so it stays the common look.
static func skins_for_tier(tier: int) -> Array:
	var key := tier_key(tier)
	var tier_skin: Array = []
	var themed: Array = []
	for skin in all_skins():
		if skin.custom:
			continue
		if not skin.spawn_tiers.has(key):
			continue
		if skin.id == tier_skin_id(tier):
			tier_skin.append(skin)
		else:
			themed.append(skin)
	if themed.is_empty():
		return tier_skin
	return tier_skin + themed


## Pick a skin for a spawning visitor: usually the tier's own art, sometimes one
## of the themed skins that tier is allowed to wear.
static func random_skin_for_tier(tier: int) -> SkinDef:
	var options := skins_for_tier(tier)
	if options.is_empty():
		return skin_by_id(default_skin_id())
	if options.size() == 1 or randf() < 0.55:
		return options[0]
	return options[randi() % options.size()]


## A free id for a new player-made skin.
static func next_custom_id() -> String:
	var used := {}
	for recipe in GameManager.player_profile.custom_skins:
		if recipe is Dictionary:
			used[str(recipe.get("id", ""))] = true
	var index := 1
	while used.has("custom_%d" % index):
		index += 1
	return "custom_%d" % index


## Build a new player-made skin forked from `base`.
static func new_custom_skin(base: SkinDef, display_name: String = "") -> SkinDef:
	var skin := SkinDef.new()
	skin.id = next_custom_id()
	skin.name = display_name if not display_name.is_empty() else "My Skin %s" % skin.id.get_slice("_", 1)
	skin.description = "Made in the Skin Designer."
	skin.custom = true
	skin.base_id = base.id if base != null else default_skin_id()
	skin.inherit_from(base if base != null else skin_by_id(default_skin_id()))
	return skin


# =============================================================================
# COLOURS
# =============================================================================

## base, light, dark, outline, brighter - the four-or-five shades a part is
## drawn from. Matches the generator (tools/generate_golfer_skins.py) exactly,
## so a re-coloured pixel sits beside its neighbours correctly.
static func ramp(colour: Color) -> PackedColorArray:
	return PackedColorArray([
		_quantise(colour),
		_quantise(_mix(colour, Color(1, 1, 1), 0.24)),
		_quantise(_mix(colour, Color(10.0 / 255.0, 8.0 / 255.0, 12.0 / 255.0), 0.30)),
		_quantise(_mix(colour, Color(6.0 / 255.0, 6.0 / 255.0, 10.0 / 255.0), 0.62)),
		_quantise(_mix(colour, Color(1, 1, 1), 0.42)),
	])


## Ramps are 8-bit values: the sprite art is stored that way, and quantising
## here means a re-colour writes back exactly what it read.
static func _quantise(colour: Color) -> Color:
	return Color(roundi(colour.r * 255.0) / 255.0, roundi(colour.g * 255.0) / 255.0,
		roundi(colour.b * 255.0) / 255.0, colour.a)


static func _mix(from: Color, to: Color, weight: float) -> Color:
	return Color(
		from.r + (to.r - from.r) * weight,
		from.g + (to.g - from.g) * weight,
		from.b + (to.b - from.b) * weight,
		from.a)


## Index of a part in the stored pixel format.
static func part_index(part: String) -> int:
	return PART_ORDER.find(part)


static func part_for_index(index: int) -> String:
	if index < 0 or index >= PART_ORDER.size():
		return ""
	return PART_ORDER[index]


## The colour a palette uses for a part: the player's choice when there is one,
## otherwise the colour the art was drawn in.
static func colour_for(skin: SkinDef, part: String, overrides: Dictionary = {}) -> Color:
	if overrides.has(part):
		var value = overrides[part]
		return value if value is Color else Color.from_string(str(value), Color.WHITE)
	if skin != null and skin.colors.has(part):
		var stored = skin.colors[part]
		return stored if stored is Color else Color.from_string(str(stored), Color.WHITE)
	if FIXED_PART_COLOURS.has(part):
		return FIXED_PART_COLOURS[part]
	# An edit stores only the parts the player changed: anything they left alone
	# keeps the colour the art was drawn in.
	var art := source_skin(skin)
	if art != null and art != skin and art.colors.has(part):
		var inherited = art.colors[part]
		return inherited if inherited is Color else Color.from_string(str(inherited), Color.WHITE)
	return Color.WHITE


## The colours a golfer would draw this skin with: the player's picks for the
## parts they changed, the artist's palette for the rest.
static func palette_for(skin: SkinDef, overrides: Dictionary = {}) -> Dictionary:
	var palette := {}
	for part in PART_ORDER:
		palette[part] = ramp(colour_for(skin, part, overrides))
	return palette


# =============================================================================
# FRAMES
# =============================================================================

## The SpriteFrames for a skin, re-coloured with `overrides` (part -> Color).
## Built once and shared: pass `fresh` to force a rebuild after an edit.
static func frames_for(skin: SkinDef, overrides: Dictionary = {}, fresh: bool = false) -> SpriteFrames:
	if skin == null:
		skin = skin_by_id(default_skin_id())
	var key := cache_key(skin, overrides)
	if not fresh and _frames_cache.has(key):
		return _frames_cache[key]
	var frames := _build_frames(skin, overrides)
	_frames_cache[key] = frames
	return frames


static func cache_key(skin: SkinDef, overrides: Dictionary = {}) -> String:
	if skin == null:
		return ""
	var parts: Array = []
	for part in overrides:
		var colour := colour_for(skin, part, overrides)
		parts.append("%s=%s" % [part, colour.to_html(false)])
	parts.sort()
	return "%s|%s|%d" % [skin.id, ",".join(parts), skin.revision]


## Drop built frames: everything, one skin, or one skin's exact colour set.
static func invalidate(skin_id: String = "") -> void:
	if skin_id.is_empty():
		_frames_cache.clear()
		return
	var stale: Array = []
	for key in _frames_cache:
		if str(key).begins_with(skin_id + "|"):
			stale.append(key)
	for key in stale:
		_frames_cache.erase(key)


## The skin whose art a skin is drawn with: a player-made skin borrows the art
## of the built-in skin it was forked from and only paints over some frames.
static func source_skin(skin: SkinDef) -> SkinDef:
	if skin == null or not skin.custom:
		return skin
	# A skin of the player's own borrows the art of the skin it was forked from;
	# that art always comes from the shipped folder, never from an edited copy
	# of it (the edits are colours and pixels, not new art).
	var current := skin
	var seen := {}
	while current != null and current.custom and not seen.has(current.id):
		seen[current.id] = true
		var next: SkinDef = null
		for shipped in builtin_skins():
			if shipped.id == current.base_id:
				next = shipped
				break
		if next == null:
			for candidate in all_skins():
				if candidate.id == current.base_id:
					next = candidate
					break
		if next == null or next == current:
			break
		current = next
	return current if current != null else skin


## The colours that actually change how a frame is drawn: the picks that differ
## from the skin's own palette. Anything else is left exactly as it was drawn, so
## an untouched skin is byte-for-byte the shipped art.
static func changed_colours(skin: SkinDef, overrides: Dictionary) -> Dictionary:
	var changed := {}
	if skin == null:
		return overrides
	var art := source_skin(skin)
	for part in FIXABLE_PARTS:
		if not overrides.has(part) and not (skin.custom and skin.colors.has(part)):
			continue
		var wanted := colour_for(skin, part, overrides)
		var original := colour_for(art, part)
		if wanted != original:
			changed[part] = wanted
	return changed


static func _build_frames(skin: SkinDef, overrides: Dictionary) -> SpriteFrames:
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")
	var palette := palette_for(skin, overrides)
	for anim in ANIMATIONS:
		var info: Dictionary = ANIMATIONS[anim]
		for direction in DIRECTION_ORDER:
			var animation := "%s_%s" % [anim, direction]
			frames.add_animation(animation)
			frames.set_animation_speed(animation, info["fps"])
			frames.set_animation_loop(animation, info["loop"])
			for frame in info["frames"]:
				var texture := frame_texture(skin, overrides, palette, anim, direction, frame)
				if texture != null:
					frames.add_frame(animation, texture, 1.0)
	return frames


## One frame, ready to hand to an AnimatedSprite2D.
static func frame_texture(skin: SkinDef, overrides: Dictionary, palette: Dictionary,
		anim: String, direction: String, frame: int) -> Texture2D:
	if skin.has_overlay(anim, direction, frame):
		var painted := image_from_overlay(skin, overrides, palette, anim, direction, frame)
		if painted != null:
			return ImageTexture.create_from_image(painted)
	var source := base_frame_image(skin, direction, anim, frame)
	if source == null:
		return null
	var image := source.duplicate() as Image
	if image == null:
		return null
	var changed := changed_colours(skin, overrides)
	recolour(image, skin, changed)
	return ImageTexture.create_from_image(image)


## The untouched art for one frame (the skin's own palette), with the facing
## fallback applied. Cached per skin: the source art never changes.
static func base_frame_image(skin: SkinDef, direction: String, anim: String, frame: int) -> Image:
	var art := source_skin(skin)
	if art == null:
		return null
	var path := _frame_path(art, direction, anim, frame)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var texture = load(path)
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


static func _frame_path(skin: SkinDef, direction: String, anim: String, frame: int) -> String:
	var facing := direction
	var path := "%s/animations/%s/%s/frame_%03d.png" % [skin.root, anim, facing, frame]
	if ResourceLoader.exists(path):
		return path
	if DIAGONAL_FALLBACK.has(facing):
		path = "%s/animations/%s/%s/frame_%03d.png" % [skin.root, anim, DIAGONAL_FALLBACK[facing], frame]
		if ResourceLoader.exists(path):
			return path
	return ""


# =============================================================================
# RE-COLOURING
# =============================================================================

## Re-colour an image in place: the player's parts get their chosen colour, in
## the shade the pixel was drawn in.
static func recolour(image: Image, skin: SkinDef, overrides: Dictionary) -> void:
	if overrides.is_empty():
		return
	# Eyes and highlights are the same in every skin.
	for part in overrides.keys():
		if not FIXABLE_PARTS.has(part):
			overrides.erase(part)
	if skin != null and skin.legacy:
		_recolour_legacy(image, overrides)
		return
	var wanted: Array = []
	for part in overrides:
		wanted.append(part)
	if wanted.is_empty():
		return
	var palette := palette_for(skin, overrides)
	var width := image.get_width()
	var height := image.get_height()
	for y in height:
		for x in width:
			var source := image.get_pixel(x, y)
			if source.a <= 0.01:
				continue
			# The pixels on hand are the artist's: match them against the art's
			# palette, then emit them from the player's.
			var found := match_pixel(source, skin, source_skin(skin))
			if found.is_empty():
				continue
			var part: String = found["part"]
			if not overrides.has(part):
				continue
			var shades: PackedColorArray = palette[part]
			image.set_pixel(x, y, shades[mini(int(found["shade"]), shades.size() - 1)])


## Find which part a drawn pixel belongs to: the ramp entry it is closest to.
## Returns {} when the pixel is not art from a known palette.
## `palette_skin` picks whose colours to match against: the art's own palette
## (used when re-colouring a freshly drawn frame) or, by default, the skin's -
## which is what the pixels of an already-coloured frame are drawn from.
static func match_pixel(source: Color, skin: SkinDef, palette_skin: SkinDef = null) -> Dictionary:
	var best := {}
	var best_distance := MATCH_TOLERANCE
	var palette_source := palette_skin if palette_skin != null else skin
	for part in PART_ORDER:
		var colour := colour_for(palette_source, part)
		var shades := ramp(colour)
		for shade in shades.size():
			var distance := _distance_squared(source, shades[shade])
			if distance < best_distance:
				best_distance = distance
				best = {"part": part, "shade": shade}
	return best


static func _distance_squared(a: Color, b: Color) -> float:
	var dr := a.r - b.r
	var dg := a.g - b.g
	var db := a.b - b.b
	return dr * dr + dg * dg + db * db


## The hand-made tier art is re-coloured the way it always was: parts are found
## by where they sit on the sprite and what hue they are, and the shading is
## carried across from the source pixel's own brightness.
static func _recolour_legacy(image: Image, overrides: Dictionary) -> void:
	var width := image.get_width()
	var height := image.get_height()
	for y in height:
		for x in width:
			var source := image.get_pixel(x, y)
			if source.a <= 0.01:
				continue
			var part := classify_legacy_pixel(source, x, y, width, height, "")
			if part.is_empty() or not overrides.has(part):
				continue
			var target := colour_for(null, part, overrides)
			image.set_pixel(x, y, shade_legacy(source, target, LEGACY_REFERENCE[part].v))


## Which part of the hand-made tier art a pixel belongs to. Direction-aware:
## the back-facing frames show more hair, the side views keep it behind the face.
static func classify_legacy_pixel(source: Color, x: int, y: int, width: int, height: int,
		direction: String) -> String:
	var vertical := float(y) / float(maxi(height, 1))
	var horizontal := float(x) / float(maxi(width, 1))

	if vertical <= 0.34 and source.b > source.r * 1.025 \
			and absf(source.r - source.g) < 0.18 and source.r > 0.30:
		return "cap"

	var hair_area := vertical <= 0.32
	if direction.begins_with("north"):
		hair_area = vertical <= 0.46
	elif direction.contains("east"):
		hair_area = vertical <= 0.44 and horizontal < 0.50
	elif direction.contains("west"):
		hair_area = vertical <= 0.44 and horizontal > 0.50
	if hair_area and source.r > source.g * 1.08 and source.g > source.b * 1.01 \
			and source.r >= 0.22 and source.r < 0.50:
		return "hair"

	if source.r > source.g * 1.9 and source.r > source.b * 1.55:
		return "shirt"

	var is_warm_skin := source.r > source.g and source.g > source.b \
		and source.r > 0.42 and source.r - source.g > 0.045 \
		and source.r - source.g < 0.48 and source.g - source.b > 0.015
	var is_face_or_arm_area := vertical < 0.58 \
		or (vertical < 0.72 and (horizontal < 0.40 or horizontal > 0.60))
	if is_warm_skin and is_face_or_arm_area:
		return "skin"

	if vertical >= 0.58 and vertical < 0.83 and source.r > source.g * 1.04 \
			and source.g >= source.b * 0.95 and source.r < 0.76:
		return "pants"

	return ""


## Re-colour while keeping the source pixel's light/dark value as shading.
static func shade_legacy(source: Color, target: Color, reference_value: float) -> Color:
	var source_value := maxf(source.r, maxf(source.g, source.b))
	var shade := source_value / reference_value if reference_value > 0.0 else 1.0
	return Color(minf(1.0, target.r * shade), minf(1.0, target.g * shade),
		minf(1.0, target.b * shade), source.a)


# =============================================================================
# PAINTED PIXELS (the Skin Designer's storage format)
# =============================================================================

## Turn a drawn frame back into part+shade indices, so it can be re-coloured
## later. Pixels that do not belong to a ramp (a stray artefact, or the parts
## drawn in fixed colours) are stored as 0, which reads as transparent - the
## designer only ever encodes art it drew itself.
## The palette a hand-painted frame is stored against - a custom skin's own
## colours, or the skin's shipped palette.
static func storage_palette(skin: SkinDef) -> Dictionary:
	return palette_for(skin, {})


static func encode_image(image: Image, skin: SkinDef, direction: String = "") -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(CANVAS * CANVAS)
	var legacy := skin != null and skin.legacy
	for y in CANVAS:
		for x in CANVAS:
			var index := 0
			if x < image.get_width() and y < image.get_height():
				var source := image.get_pixel(x, y)
				if source.a > 0.01:
					index = _encode_legacy_pixel(source, x, y, direction, skin) if legacy \
						else _encode_ramp_pixel(source, skin)
			bytes[y * CANVAS + x] = index
	return bytes


static func _encode_ramp_pixel(source: Color, skin: SkinDef) -> int:
	var found := match_pixel(source, skin)
	if found.is_empty():
		return 0
	return pixel_index(str(found["part"]), int(found["shade"]))


## The hand-made tier art is not drawn from ramps, so a painted frame is stored
## as the part the pixel sits in plus the ramp entry closest to its brightness.
## Painting over tier art therefore re-draws it in the flat ramp style.
static func _encode_legacy_pixel(source: Color, x: int, y: int, direction: String, skin: SkinDef) -> int:
	var part := classify_legacy_pixel(source, x, y, CANVAS, CANVAS, direction)
	if part.is_empty() or not FIXABLE_PARTS.has(part):
		return 0
	var reference_value: float = LEGACY_REFERENCE[part].v
	var ratio := source.v / reference_value if reference_value > 0.0 else 1.0
	var target := colour_for(skin, part)
	var wanted := Color(minf(1.0, target.r * ratio), minf(1.0, target.g * ratio),
		minf(1.0, target.b * ratio))
	var shades := ramp(target)
	var best := 0
	var best_distance := INF
	for shade in shades.size():
		var distance := _distance_squared(wanted, shades[shade])
		if distance < best_distance:
			best_distance = distance
			best = shade
	return pixel_index(part, best)


## The image for a hand-painted frame: each stored index drawn from its ramp.
static func image_from_overlay(skin: SkinDef, _overrides: Dictionary, palette: Dictionary,
		anim: String, direction: String, frame: int) -> Image:
	var bytes: PackedByteArray = skin.overlays.get(skin.frame_key(anim, direction, frame))
	if bytes == null or bytes.size() != CANVAS * CANVAS:
		return null
	var image := Image.create_empty(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in CANVAS:
		for x in CANVAS:
			var index: int = bytes[y * CANVAS + x]
			if index == 0:
				continue
			@warning_ignore("integer_division")
			var part := part_for_index((index - 1) / SHADE_COUNT)
			if part.is_empty():
				continue
			var shades: PackedColorArray = palette.get(part, ramp(Color.WHITE))
			image.set_pixel(x, y, shades[(index - 1) % SHADE_COUNT])
	return image


## The index the designer stores for one part/shade pair (0 = transparent).
static func pixel_index(part: String, shade: int) -> int:
	var index := part_index(part)
	if index < 0:
		return 0
	return 1 + index * SHADE_COUNT + clampi(shade, 0, SHADE_COUNT - 1)


## The part/shade a stored pixel stands for, or {} for an empty pixel.
static func decode_pixel(index: int) -> Dictionary:
	if index <= 0:
		return {}
	@warning_ignore("integer_division")
	var part := part_for_index((index - 1) / SHADE_COUNT)
	return {"part": part, "shade": (index - 1) % SHADE_COUNT}


static func _to_bytes(value) -> PackedByteArray:
	if value is PackedByteArray:
		return value
	var bytes := PackedByteArray()
	if value is Array:
		for entry in value:
			bytes.append(clampi(int(entry), 0, 255))
	return bytes


# =============================================================================
# LOADING
# =============================================================================

static func _load_builtin() -> Array:
	var skins: Array = []
	if not FileAccess.file_exists(DATA_PATH):
		push_error("GolferSkinLibrary: missing %s" % DATA_PATH)
		return skins
	var text := FileAccess.get_file_as_string(DATA_PATH)
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("GolferSkinLibrary: %s is not valid JSON" % DATA_PATH)
		return skins
	for record in parsed.get("skins", []):
		if record is Dictionary:
			skins.append(_skin_from_record(record))
	return skins


static func _skin_from_record(record: Dictionary) -> SkinDef:
	var skin := SkinDef.new()
	skin.id = str(record.get("id", ""))
	skin.name = str(record.get("name", skin.id))
	skin.description = str(record.get("description", ""))
	skin.root = str(record.get("root", ""))
	skin.legacy = bool(record.get("legacy", false))
	skin.custom = false
	var customisable = record.get("customizable", [])
	if customisable is Array:
		for part in customisable:
			skin.customizable.append(str(part))
	var palette = record.get("colors", {})
	if palette is Dictionary:
		for part in palette:
			skin.colors[str(part)] = Color.from_string(str(palette[part]), Color.WHITE)
	var tiers = record.get("spawn_tiers", [])
	if tiers is Array:
		for tier in tiers:
			skin.spawn_tiers.append(str(tier))
	return skin
