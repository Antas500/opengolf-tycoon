extends RefCounted
class_name GolferSkinLibrary
## GolferSkinLibrary - the catalogue of golfer skins and the factory that turns
## one into the SpriteFrames an AnimatedSprite2D plays.
##
## A *skin* is a full set of pixel art for the golfer: idle, walk and swing
## animations, eight facings each. The catalogue comes from two places:
##
##  * ``res://data/golfer_skins.json`` - the shipped skins. Thirteen themed
##    skins are drawn by ``tools/generate_golfer_skins.py``; two more records
##    mark the hand-made tier art (Beginner/Casual) as recolourable skins.
##  * the owner's profile - ``PlayerGolferProfile.custom_skins`` holds recipes
##    the player built in the Skin Designer (see ``scripts/ui/golfer_skin_designer.gd``).
##
## Every sprite ships with a *part layer*: a sidecar beside each PNG
## (``frame_000.layer.bin``) holding one byte per pixel that says which part
## that pixel was drawn as and in which shade (see PART_ORDER). Re-colouring a
## golfer reads the layer, so exactly the pixels of the parts the player
## changed are re-emitted - from the new colour's ramp for the drawn art, and
## carrying the artist's own light and dark for the hand-made tier art. Every
## other pixel, the eyes and the highlights included, is left alone.
##
## The designer's own byte-per-pixel format is the same one, which is what makes
## the two meet: the layer a frame is painted on *is* its stored pixels, so a
## painted frame keeps following the palette, and a part the player adds or
## removes from a skin is a part the layer does or does not offer.
##
## All state here is static: the catalogue, the layers and the built
## SpriteFrames are shared by every golfer, so eight visitors wearing the same
## skin cost one build.

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
## The part layer that ships beside a sprite: ``frame_000.png`` is described by
## ``frame_000.layer.bin`` (deflated, one byte per pixel, see ``pixel_index``).
const LAYER_SUFFIX := ".layer.bin"

## Which animation names exist, and how they play.
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

## How close a sprite pixel has to be to a ramp entry to be recognised as that
## part (squared distance in 0-1 RGB). Only art that ships without a part layer
## is matched this way: with a layer, the layer itself says which part a pixel
## belongs to, right down to the artist's shading.
const MATCH_TOLERANCE := 0.010

## skin id -> array of SkinDef, built once from the JSON.
static var _builtin: Array = []
static var _builtin_loaded := false
## The catalogue with the player's edits and their own skins folded in.
static var _catalogue: Array = []
static var _catalogue_signature := ""
## Built SpriteFrames, keyed by skin id + colours + revision.
static var _frames_cache: Dictionary = {}
## Part layers, keyed by file path. A layer never changes while the game runs.
static var _layer_cache: Dictionary = {}
## Which parts each skin's art draws, and how many pixels of each, keyed by the
## art's folder. Counted once per art (it means reading every frame).
static var _layer_report_cache: Dictionary = {}


## One skin: its art, its palette, and which parts the player may change.
class SkinDef extends RefCounted:
	var id: String = ""
	var name: String = "Golfer"
	var description: String = ""
	## Folder holding ``animations/<anim>/<direction>/frame_NNN.png``.
	var root: String = ""
	## True for the hand-made tier art, which is re-coloured by carrying the
	## artist's own shading across instead of re-emitting a ramp stop.
	var legacy: bool = false
	## True for a skin the player made in the Skin Designer.
	var custom: bool = false
	## The built-in skin a custom skin was forked from.
	var base_id: String = ""
	## *The parts of this skin's layer*: the body parts the colour pickers offer
	## and the only ones re-colouring touches. Comes from the art's own layer
	## (``layer_report``), as edited by the player on the Customise Golfer Skins
	## screen - they can add a part the art never drew, or take one out.
	var customizable: PackedStringArray = PackedStringArray()
	## part -> Color, the colours the art was drawn in.
	var colors: Dictionary = {}
	## Tier names this skin may spawn with ("beginner", "casual", "serious", "pro").
	var spawn_tiers: PackedStringArray = PackedStringArray()
	## Hand-painted frames: "<anim>_<direction>_<frame>" -> PackedByteArray of
	## part+shade indices (0 = transparent).
	var overlays: Dictionary = {}
	## True when this skin's parts came out of its recipe rather than off the
	## art - a recipe always wins, so a layer the player edited is not put back
	## to the art's when the skin is rebuilt.
	var parts_from_recipe := false
	## Bumped whenever the overlays change, to invalidate built SpriteFrames.
	var revision: int = 0

	func is_customisable(part: String) -> bool:
		return customizable.has(part)

	## Add a part to this skin's layer, or take it out again: the parts the layer
	## offers to the colour pickers, and the only ones re-colouring touches. The
	## pixels a part owns are always the artist's - what the player changes here
	## is which parts the layer holds.
	## Returns false when that is already the case.
	func set_part(part: String, present: bool) -> bool:
		if not PAINTABLE_PARTS.has(part):
			return false
		var parts := Array(customizable)
		if present:
			parts.append(part)
		else:
			parts.erase(part)
		return set_part_order(parts)

	## Take this skin's layer from a list of parts, in whatever order they come
	## in: the layer keeps its own order (see PART_ORDER). Returns false when
	## that list is what the layer already holds.
	func set_part_order(parts) -> bool:
		var wanted := PackedStringArray()
		for candidate in PAINTABLE_PARTS:
			if parts.has(candidate):
				wanted.append(candidate)
		if wanted == customizable:
			return false
		customizable = wanted
		return true

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
			"parts": Array(customizable),
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
		# The parts this skin's layer offers. A recipe written before parts were
		# editable carries no list at all, and takes the art's own.
		skin.customizable = PackedStringArray(PAINTABLE_PARTS)
		if data.has("parts") and data["parts"] is Array:
			skin.customizable = PackedStringArray()
			for part in data["parts"]:
				if PAINTABLE_PARTS.has(str(part)):
					skin.customizable.append(str(part))
			skin.parts_from_recipe = true
		skin.spawn_tiers = PackedStringArray()
		return skin

	## A custom skin is drawn with the same parts as the skin it was forked from,
	## with the recipe's colours laid over them, so only those parts are offered.
	func inherit_from(base: SkinDef) -> void:
		root = base.root
		legacy = base.legacy
		# The art's layer, unless the recipe brought one of its own.
		if not parts_from_recipe:
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
	# The art's own layer, unless the player has edited which parts it offers.
	if not edited.parts_from_recipe:
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
	elif skin.customizable.is_empty():
		skin.customizable = PackedStringArray(PAINTABLE_PARTS)
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
# PART LAYERS
# =============================================================================

## The folder holding the art - and so the part layers - this skin is drawn
## with: a skin of the player's own borrows the layers of the skin it was forked
## from, exactly as it borrows that skin's pixels.
static func layer_root(skin: SkinDef) -> String:
	var art := source_skin(skin)
	if art != null and not art.root.is_empty():
		return art.root
	return skin.root if skin != null else ""


## One frame's part layer: a byte per pixel of the 48x48 canvas saying which
## part the artist drew that pixel as and in which shade (see ``pixel_index``);
## 0 means no part - empty canvas, the shadow, or a pixel the layer does not own
## - and a pixel like that is never re-coloured.
## Returns an empty array when the art has no layer on disk.
static func frame_layer(skin: SkinDef, direction: String, anim: String, frame: int) -> PackedByteArray:
	var art := source_skin(skin)
	if art == null:
		return PackedByteArray()
	var path := _frame_path(art, direction, anim, frame)
	if path.is_empty():
		return PackedByteArray()
	path = path.trim_suffix(".png") + LAYER_SUFFIX
	if _layer_cache.has(path):
		return _layer_cache[path]
	var layer := _read_layer(path)
	_layer_cache[path] = layer
	return layer


## The part+shade bytes for one frame of a skin - what the designer paints on.
## The art's own layer when it ships with one; a frame that has none is read
## back off the drawn pixels instead, so an older or hand-authored skin still
## paints and re-colours the way it always did.
static func frame_bytes(skin: SkinDef, direction: String, anim: String, frame: int) -> PackedByteArray:
	var layer := frame_layer(skin, direction, anim, frame)
	if layer.size() == CANVAS * CANVAS:
		return layer
	var image := base_frame_image(skin, direction, anim, frame)
	if image == null:
		return PackedByteArray()
	return encode_image(image, skin)


static func _read_layer(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		push_warning("GolferSkinLibrary: no part layer for %s - that art will not be re-coloured" % path)
		return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("GolferSkinLibrary: cannot open the part layer %s" % path)
		return PackedByteArray()
	var raw := file.get_buffer(file.get_length())
	file.close()
	var layer := raw.decompress_dynamic(CANVAS * CANVAS, FileAccess.COMPRESSION_DEFLATE)
	if layer.size() != CANVAS * CANVAS:
		push_warning("GolferSkinLibrary: the part layer %s is not %dx%d" % [path, CANVAS, CANVAS])
		return PackedByteArray()
	return layer


## Which parts a skin's art draws, and how much of each: part -> pixel count
## over every frame, in PART_ORDER. This is the layer a skin starts life with -
## the parts the Customise Golfer Skins screen lists, offers colours for and
## lets the player add to or take away from. Counted once per art: a layer never
## changes while the game runs.
static func layer_report(skin: SkinDef) -> Dictionary:
	var root := layer_root(skin)
	if _layer_report_cache.has(root):
		return _layer_report_cache[root]
	var counts := {}
	var art := source_skin(skin)
	if art != null:
		for direction in DIRECTION_ORDER:
			for anim in ANIMATIONS:
				var frames: int = ANIMATIONS[anim]["frames"]
				for frame in frames:
					var layer := frame_layer(art, direction, anim, frame)
					for index in layer:
						if index == 0:
							continue
						@warning_ignore("integer_division")
						var part := part_for_index((index - 1) / SHADE_COUNT)
						if part.is_empty():
							continue
						counts[part] = int(counts.get(part, 0)) + 1
	_layer_report_cache[root] = counts
	return counts


## The parts the *art's* layer covers, in the order the colour pickers want them
## (``PAINTABLE_PARTS``, the same order as PART_ORDER). What a skin offers is
## ``skin.customizable``: it starts here, and from then on it is the player's to
## edit - so this is the palette of parts the art draws, not the current layer.
static func layer_parts(skin: SkinDef) -> Array:
	var counts := layer_report(skin)
	var parts: Array = []
	for part in PAINTABLE_PARTS:
		if counts.has(part):
			parts.append(part)
	return parts


## The parts of a skin the player may re-colour and paint: exactly the parts its
## layer holds, whether they came from the art or the player put them there.
static func parts_for_skin(skin: SkinDef) -> Array:
	if skin == null:
		return []
	var parts: Array = []
	for part in PAINTABLE_PARTS:
		if skin.is_customisable(part):
			parts.append(part)
	return parts


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
## from the skin's own palette, for the parts this skin's layer still offers.
## Anything else is left exactly as it was drawn, so an untouched skin is
## byte-for-byte the shipped art.
static func changed_colours(skin: SkinDef, overrides: Dictionary) -> Dictionary:
	var changed := {}
	if skin == null:
		return overrides
	var art := source_skin(skin)
	for part in FIXABLE_PARTS:
		if not skin.customizable.has(part):
			continue
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


## One frame, ready to hand to an AnimatedSprite2D: the player's painted pixels
## when this frame has any, otherwise the art with its part layer applied.
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
	recolour(image, skin, changed, direction, anim, frame)
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

## Re-colour an image in place, from its part layer: the pixels of the parts the
## player changed are re-emitted in their new colour and every other pixel keeps
## the one the artist drew. Which pixels a part owns is the layer's job (see
## ``frame_layer``), so this is exact - a very dark shirt is never mistaken for
## hair, and the eyes and highlights never move.
##
## Pass the frame the image is of (``direction``/``anim``/``frame``) whenever it
## is known: that is what finds the layer. Without it - or for art that ships
## without a layer - the pixels are matched back against the art's own palette
## instead, the way re-colouring worked before layers existed.
static func recolour(image: Image, skin: SkinDef, overrides: Dictionary,
		direction: String = "", anim: String = "", frame: int = -1) -> void:
	if overrides.is_empty():
		return
	# Eyes and highlights are the same in every skin.
	for part in overrides.keys():
		if not FIXABLE_PARTS.has(part):
			overrides.erase(part)
	if overrides.is_empty():
		return
	var layer := PackedByteArray()
	if not direction.is_empty():
		layer = frame_layer(skin, direction, anim, frame)
	if layer.size() == CANVAS * CANVAS:
		_recolour_from_layer(image, skin, overrides, layer)
		return
	_recolour_by_pixel(image, skin, overrides)


## The main path: walk the layer, and re-emit the pixels of every changed part
## from that part's ramp in the shade the artist used.
static func _recolour_from_layer(image: Image, skin: SkinDef, overrides: Dictionary,
		layer: PackedByteArray) -> void:
	var palette := palette_for(skin, overrides)
	var art := source_skin(skin)
	var legacy := art != null and art.legacy
	var width := mini(image.get_width(), CANVAS)
	var height := mini(image.get_height(), CANVAS)
	for y in height:
		for x in width:
			var index: int = layer[y * CANVAS + x]
			if index == 0:
				continue
			@warning_ignore("integer_division")
			var part := part_for_index((index - 1) / SHADE_COUNT)
			if part.is_empty() or not overrides.has(part):
				continue
			var source := image.get_pixel(x, y)
			if source.a <= 0.01:
				continue
			if legacy:
				# The hand-made art was not drawn from ramps, so its own
				# light and dark is carried across onto the new colour.
				image.set_pixel(x, y, shade_legacy(source, colour_for(skin, part, overrides),
					colour_for(art, part).v))
			else:
				var shades: PackedColorArray = palette[part]
				image.set_pixel(x, y, shades[mini((index - 1) % SHADE_COUNT, shades.size() - 1)])


## The fallback for art with no layer on disk: match each drawn pixel against
## the palette the artist used and re-emit it from the player's.
static func _recolour_by_pixel(image: Image, skin: SkinDef, overrides: Dictionary) -> void:
	var palette := palette_for(skin, overrides)
	var width := image.get_width()
	var height := image.get_height()
	for y in height:
		for x in width:
			var source := image.get_pixel(x, y)
			if source.a <= 0.01:
				continue
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


## Re-colour while keeping the source pixel's light/dark value as shading.
static func shade_legacy(source: Color, target: Color, reference_value: float) -> Color:
	var source_value := maxf(source.r, maxf(source.g, source.b))
	var shade := source_value / reference_value if reference_value > 0.0 else 1.0
	return Color(minf(1.0, target.r * shade), minf(1.0, target.g * shade),
		minf(1.0, target.b * shade), source.a)


# =============================================================================
# PAINTED PIXELS (the Skin Designer's storage format)
# =============================================================================

## The palette a hand-painted frame is stored against - a custom skin's own
## colours, or the skin's shipped palette.
static func storage_palette(skin: SkinDef) -> Dictionary:
	return palette_for(skin, {})


## Read a drawn frame back as part+shade indices, so it can be re-coloured
## later: a pixel takes the ramp entry it is closest to, and one that is not art
## from a known palette (a stray artefact, or a part drawn in the fixed colours)
## is stored as 0. Only used for art that ships without a part layer - art that
## has one hands out the artist's own pixels through ``frame_bytes``.
static func encode_image(image: Image, skin: SkinDef) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(CANVAS * CANVAS)
	for y in CANVAS:
		for x in CANVAS:
			var index := 0
			if x < image.get_width() and y < image.get_height():
				var source := image.get_pixel(x, y)
				if source.a > 0.01:
					var found := match_pixel(source, skin)
					if not found.is_empty():
						index = pixel_index(str(found["part"]), int(found["shade"]))
			bytes[y * CANVAS + x] = index
	return bytes


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
