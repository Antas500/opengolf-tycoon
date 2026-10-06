extends RefCounted
class_name GolferSkin
## One Golfer Skin: the Re-color Groups the player paints with, the Re-color
## Layer of every animation sprite, and the colours the golfer wearing it is
## drawn in.
##
## A skin is a folder of editable text files - a manifest named `skin.txt` and
## one `*.layer.txt` per animation sprite (see GolferSkinLayer). Built-in skins
## live under `res://data/golfer_skins/`; as soon as the player edits one it is
## copied to `user://golfer_skins/<id>/`, where the sprites stay read-only art
## while the re-color layers are the player's own files.
##
##     # OpenGolf Tycoon golfer skin
##     golfer-skin 1
##     id casual
##     name Casual
##     sprites casual          # which sprite set in assets/sprites/golfer is worn
##     size 48 48              # one grid cell per sprite pixel
##     worn_by casual          # visitors of this tier wear the skin
##     group 1 A e65959 0.71 Shirt
##     group 2 B 404259 0.55 Pants
##     ...
##
## `group <id> <symbol> <colour> <shade> <name>`: the symbol is what the grid
## files paint with, the colour is what the group is drawn in, and the shade is
## the brightness the group's brightest pixel has in the artwork (the layer's
## reference, so a re-coloured group keeps its highlights). Names are last so
## they may contain spaces.

const FORMAT_TAG: String = "golfer-skin"
const FORMAT_VERSION: int = 1
## Where a skin keeps its text files.
const MANIFEST_FILE: String = "skin.txt"
const LAYER_DIR: String = "layers"
const LAYER_SUFFIX: String = ".layer.txt"

## Re-color Groups a skin may carry, and how much text their names take.
const MAX_GROUPS: int = 32
const MAX_GROUP_NAME_LENGTH: int = 24
const MAX_SKIN_NAME_LENGTH: int = 24
## Characters a group may be painted with in a layer file. `.` is the "no
## group" symbol and `#` starts a comment, so neither is offered.
const SYMBOL_POOL: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"

## The five colours the owner's profile carries, by the group name they belong
## to: a skin's group called "Shirt" is drawn in the profile's shirt colour.
const ROLE_NAMES: Array[String] = ["shirt", "pants", "cap", "hair", "skin"]

## Animation sets every skin's art is expected to offer, and the tier keystroke
## names written in `worn_by` (index = GolferTier.Tier).
const ANIMATIONS: Array[String] = ["idle", "walk", "swing"]
const TIER_KEYS: Array[String] = ["beginner", "casual", "serious", "pro"]

## Identity. `id` is the folder name and what saves and profiles reference;
## `display_name` is what the player reads.
var id: String = ""
var display_name: String = ""
## Which sprite set under assets/sprites/golfer supplies the animation frames.
var sprite_id: String = ""
## Pixels per sprite: the size of every Re-color Layer grid.
var sprite_size: Vector2i = Vector2i(48, 48)
## Visitors of these GolferTier.Tier values wear this skin.
var worn_by: Array[int] = []

## The skin's Re-color Groups: {id, name, symbol, color, shade}, in creation
## order. Ids are handed out once and never reused, so a deleted group can
## never inherit the pixels of the group that replaced it.
var groups: Array[Dictionary] = []

## Where the skin's text files live (empty for a skin that was never saved),
## and where to look for the layers this folder does not carry.
var dir: String = ""
var fallback_dir: String = ""
## The animations folder the sprite frames come from (set by GolferSkinLibrary).
var art_root: String = ""
## True once the skin's files are the player's own (user://), false for the
## read-only skins that ship with the game.
var is_user_skin: bool = false
## Anything odd met while loading, shown by the editor.
var warnings: PackedStringArray = PackedStringArray()

## Layer cache: sprite key -> GolferSkinLayer. Layers are read from disk the
## first time they are asked for, so opening the editor or spawning a golfer
## never pays for the sprites it does not draw.
var _layers: Dictionary = {}
## Group ids deleted while some layers were still unloaded: clearing them by id
## when a layer is read (or written) keeps a delete complete without loading
## every grid of the skin.
var _cleared_groups: Dictionary = {}
## Layer keys whose edits have not been written yet.
var _dirty_layers: Dictionary = {}
var _manifest_dirty: bool = false


# =============================================================================
# RE-COLOR GROUPS
# =============================================================================

## Every group, in creation order.
func group_list() -> Array[Dictionary]:
	return groups


func group_count() -> int:
	return groups.size()


func group_by_id(group_id: int) -> Dictionary:
	for group in groups:
		if int(group.get("id", 0)) == group_id:
			return group
	return {}


func group_by_name(group_name: String) -> Dictionary:
	var wanted := group_name.strip_edges().to_lower()
	for group in groups:
		if str(group.get("name", "")).to_lower() == wanted:
			return group
	return {}


func has_group(group_id: int) -> bool:
	return not group_by_id(group_id).is_empty()


## A group name that is free, long enough to read and short enough for the
## editor's rows: "Shirt" becomes "Shirt 2" when a Shirt already exists.
func unique_group_name(base: String) -> String:
	var wanted := base.strip_edges().left(MAX_GROUP_NAME_LENGTH)
	if wanted.is_empty():
		wanted = "Group %d" % (groups.size() + 1)
	if group_by_name(wanted).is_empty():
		return wanted
	var suffix := 2
	while true:
		var candidate := "%s %d" % [wanted.left(MAX_GROUP_NAME_LENGTH - 3), suffix]
		if group_by_name(candidate).is_empty():
			return candidate
		suffix += 1
	return wanted


## Add a Re-color Group. `name` is made unique when it is empty or taken.
## Returns the new group's id, or 0 when the skin already carries MAX_GROUPS.
func create_group(name: String = "") -> int:
	if groups.size() >= MAX_GROUPS:
		return GolferSkinLayer.NO_GROUP
	var group_id := _next_group_id()
	var group := {
		"id": group_id,
		"name": unique_group_name(name),
		"symbol": _next_symbol(),
		"color": _suggested_color(),
		"shade": 1.0,
	}
	groups.append(group)
	_manifest_dirty = true
	return group_id


## Rename a group. Empty or duplicate names are refused so the owner's profile
## colours (which find their groups by name) always have one clear target.
func rename_group(group_id: int, new_name: String) -> bool:
	var group := group_by_id(group_id)
	if group.is_empty():
		return false
	var wanted := new_name.strip_edges().left(MAX_GROUP_NAME_LENGTH)
	if wanted.is_empty():
		return false
	var clash := group_by_name(wanted)
	if not clash.is_empty() and int(clash.get("id", 0)) != group_id:
		return false
	if str(group.get("name", "")) == wanted:
		return true
	group["name"] = wanted
	_manifest_dirty = true
	return true


## Delete a group and free every pixel that belonged to it, in every sprite of
## the skin - including the layers that have not been read yet.
func delete_group(group_id: int) -> bool:
	var index := -1
	for i in groups.size():
		if int(groups[i].get("id", 0)) == group_id:
			index = i
			break
	if index < 0:
		return false
	groups.remove_at(index)
	for key in _layers.keys():
		(_layers[key] as GolferSkinLayer).clear_group(group_id)
		_dirty_layers[key] = true
	_cleared_groups[group_id] = true
	_manifest_dirty = true
	return true


func set_group_color(group_id: int, color: Color) -> bool:
	var group := group_by_id(group_id)
	if group.is_empty():
		return false
	if group.get("color", Color.WHITE) == color:
		return true
	group["color"] = color
	_manifest_dirty = true
	return true


## The brightness a group's brightest pixel has in the artwork: what the
## group's colour is normalised against when the sprite is re-coloured.
func set_group_shade(group_id: int, shade: float) -> bool:
	var group := group_by_id(group_id)
	if group.is_empty():
		return false
	var wanted := clampf(shade, 0.01, 1.0)
	if is_equal_approx(float(group.get("shade", 1.0)), wanted):
		return true
	group["shade"] = wanted
	_manifest_dirty = true
	return true


func group_shade(group_id: int) -> float:
	var group := group_by_id(group_id)
	if group.is_empty():
		return 1.0
	return maxf(float(group.get("shade", 1.0)), 0.01)


## A colour no other group on this skin uses yet, so a new group is visible.
func _suggested_color() -> Color:
	var palette := [
		Color("e65959"), Color("404259"), Color("3366b3"), Color("4d331a"),
		Color("f2cca6"), Color("8fd694"), Color("e5c57c"), Color("c07ad1"),
		Color("6fd1d1"), Color("e08a3c"), Color("f2f2f2"), Color("1a1a22"),
	]
	for color in palette:
		var taken := false
		for group in groups:
			if (group.get("color", Color.WHITE) as Color).is_equal_approx(color):
				taken = true
				break
		if not taken:
			return color
	return Color.from_hsv(fmod(0.618034 * float(groups.size() + 1), 1.0), 0.55, 0.85)


## The id a new group gets: one past every id this skin has ever handed out.
func _next_group_id() -> int:
	var highest := 0
	for group in groups:
		highest = maxi(highest, int(group.get("id", 0)))
	for cleared in _cleared_groups.keys():
		highest = maxi(highest, int(cleared))
	return highest + 1


func _next_symbol() -> String:
	for symbol in SYMBOL_POOL:
		var taken := false
		for group in groups:
			if str(group.get("symbol", "")) == symbol:
				taken = true
				break
		if not taken:
			return symbol
	return GolferSkinLayer.EMPTY_SYMBOL


## The symbol each group is painted with, and the id behind it.
func symbol_to_id() -> Dictionary:
	var table := {}
	for group in groups:
		table[str(group.get("symbol", ""))] = int(group.get("id", 0))
	return table


func id_to_symbol() -> Dictionary:
	var table := {}
	for group in groups:
		table[int(group.get("id", 0))] = str(group.get("symbol", ""))
	return table


func group_legend() -> Dictionary:
	var legend := {}
	for group in groups:
		legend[int(group.get("id", 0))] = str(group.get("name", ""))
	return legend


# =============================================================================
# RE-COLOR LAYERS
# =============================================================================

## The sprite key every animation, direction and frame is filed under, e.g.
## "idle/south/frame_000".
static func layer_key(animation: String, direction: String, frame: int) -> String:
	return "%s/%s/frame_%03d" % [animation, direction, frame]


static func parse_layer_key(key: String) -> Dictionary:
	var parts := key.split("/")
	if parts.size() != 3:
		return {}
	return {
		"animation": parts[0],
		"direction": parts[1],
		"frame": int(parts[2].trim_prefix("frame_")),
	}


## The path of a layer file inside a skin folder.
static func layer_path(skin_dir: String, key: String) -> String:
	return skin_dir.path_join(LAYER_DIR).path_join(key + LAYER_SUFFIX)


## The Re-color Layer of one sprite. Read from the skin's folder the first time
## it is asked for, from the folder it falls back on (a built-in skin the player
## has not copied yet) if the skin has no file, and created empty - the size of
## the sprite - when there is none at all.
func layer(key: String) -> GolferSkinLayer:
	if _layers.has(key):
		return _layers[key]
	var parsed: GolferSkinLayer = null
	for folder in [dir, fallback_dir]:
		if folder.is_empty():
			continue
		var path := layer_path(folder, key)
		if not FileAccess.file_exists(path):
			continue
		parsed = GolferSkinLayer.parse(FileAccess.get_file_as_string(path), symbol_to_id())
		for warning in parsed.warnings:
			warnings.append("%s: %s" % [key, warning])
		break
	if parsed == null:
		parsed = GolferSkinLayer.create(sprite_size.x, sprite_size.y)
	else:
		parsed.resize(sprite_size.x, sprite_size.y)
	for cleared_id in _cleared_groups.keys():
		parsed.clear_group(int(cleared_id))
	_layers[key] = parsed
	return parsed


## Replace a layer, e.g. with a freshly parsed or generated one.
func set_layer(key: String, sprite_layer: GolferSkinLayer) -> void:
	sprite_layer.resize(sprite_size.x, sprite_size.y)
	for cleared_id in _cleared_groups.keys():
		sprite_layer.clear_group(int(cleared_id))
	_layers[key] = sprite_layer
	_dirty_layers[key] = true


func has_layer(key: String) -> bool:
	return _layers.has(key) or _layer_file_exists(key)


func _layer_file_exists(key: String) -> bool:
	for folder in [dir, fallback_dir]:
		if not folder.is_empty() and FileAccess.file_exists(layer_path(folder, key)):
			return true
	return false


## Layer keys that have been read or written on this skin.
func loaded_layer_keys() -> Array[String]:
	var keys: Array[String] = []
	for key in _layers.keys():
		keys.append(str(key))
	keys.sort()
	return keys


## Read every layer file the skin has, without touching any sprite.
func preload_layers() -> void:
	for key in sprite_keys():
		layer(key)


func mark_layer_dirty(key: String) -> void:
	_dirty_layers[key] = true


func has_unsaved_changes() -> bool:
	return _manifest_dirty or not _dirty_layers.is_empty()


func clear_unsaved_changes() -> void:
	_manifest_dirty = false
	_dirty_layers.clear()


## Every animation sprite the skin's artwork offers, e.g. "idle/south/frame_000",
## in playing order. Empty when the skin has no art on disk.
func sprite_keys() -> Array[String]:
	var keys: Array[String] = []
	if art_root.is_empty():
		return keys
	for animation in ANIMATIONS:
		var animation_dir := art_root.path_join(animation)
		for direction in GolferSkinLibrary.DIRECTIONS:
			var direction_dir := animation_dir.path_join(direction)
			var frame := 0
			while frame < GolferSkinLibrary.MAX_FRAMES:
				var path := direction_dir.path_join("frame_%03d.png" % frame)
				if not FileAccess.file_exists(path):
					break
				keys.append(layer_key(animation, direction, frame))
				frame += 1
	return keys


# =============================================================================
# COLOURS
# =============================================================================

## The colour a group is drawn in, with the owner's profile colours taking over
## the groups whose names match the profile's slots ("Shirt", "Pants", "Cap",
## "Hair", "Skin"). `overrides` maps a role name to a Color.
func color_for_group(group_id: int, overrides: Dictionary = {}) -> Color:
	var group := group_by_id(group_id)
	if group.is_empty():
		return Color.WHITE
	if not overrides.is_empty():
		var role := str(group.get("name", "")).to_lower()
		if overrides.has(role):
			return overrides[role]
	return group.get("color", Color.WHITE)


## The colour table a sprite is re-coloured with: group id -> Color.
func effective_colors(overrides: Dictionary = {}) -> Dictionary:
	var colors := {}
	for group in groups:
		colors[int(group.get("id", 0))] = color_for_group(int(group.get("id", 0)), overrides)
	return colors


## The owner profile's colours as group-name overrides.
## The PlayerGolferProfile appearance key a group's name stands for, or "" for
## a group the player's own appearance has no field for. Shirt/Pants/Cap/Hair/
## Skin map onto the profile's five colours, so a colour picked for one of those
## groups can be written back to the player's own appearance (see
## PlayerRoundManager's Edit Player page).
static func profile_key_for_group(group_name: String) -> String:
	var role := group_name.strip_edges().to_lower()
	if role.is_empty() or not ROLE_NAMES.has(role):
		return ""
	return "skin_tone" if role == "skin" else role + "_color"


## The colour the profile's appearance gives one of those roles, or Color.WHITE
## with `found` false when it names none.
static func profile_color(profile: PlayerGolferProfile, group_name: String) -> Color:
	if profile == null:
		return Color.WHITE
	var key := profile_key_for_group(group_name)
	if key.is_empty():
		return Color.WHITE
	var raw: Variant = profile.appearance.get(key, null)
	if raw is String:
		return Color.from_string(str(raw), Color.WHITE)
	if raw is Color:
		return raw
	return Color.WHITE


## A re-coloured copy of one sprite image. Returns the image untouched when the
## sprite has no layer or the layer names no group.
## The sprite as this skin holds it: the layer's own painted pixels when the
## player has painted any, else the artwork that ships with the game. What the
## golfer is drawn with before any group colour is applied.
func edited_image(image: Image, key: String) -> Image:
	var sprite_layer := layer(key)
	if sprite_layer != null and sprite_layer.has_art():
		var art := sprite_layer.art_image()
		if art != null:
			return art
	return image


func recolor_image(image: Image, key: String, overrides: Dictionary = {}) -> Image:
	if image == null or image.is_empty():
		return image
	var sprite_layer := layer(key)
	if sprite_layer.is_empty():
		return image
	return sprite_layer.recolor(image, effective_colors(overrides), _shades())


func _shades() -> Dictionary:
	var shades := {}
	for group in groups:
		shades[int(group.get("id", 0))] = maxf(float(group.get("shade", 1.0)), 0.01)
	return shades


## Take the brightest pixels found in one sprite as the reference brightness of
## the groups they belong to (never lowering one already set from other sprites,
## so a group's shading stays consistent across the animation).
func refresh_shades_from(image: Image, key: String, replace: bool = false) -> void:
	var maxima := layer(key).source_maxima(image)
	for group_id in maxima:
		var found := float(maxima[group_id])
		set_group_shade(int(group_id), found if replace else maxf(group_shade(int(group_id)), found))


# =============================================================================
# TIERS
# =============================================================================

static func tier_key(tier: int) -> String:
	if tier < 0 or tier >= TIER_KEYS.size():
		return ""
	return TIER_KEYS[tier]


func wears_tier(tier: int) -> bool:
	return tier in worn_by


func set_wears_tier(tier: int, wears: bool) -> void:
	if wears and not worn_by.has(tier):
		worn_by.append(tier)
		worn_by.sort()
		_manifest_dirty = true
	elif not wears and worn_by.has(tier):
		worn_by.erase(tier)
		_manifest_dirty = true


# =============================================================================
# TEXT FILES
# =============================================================================

## The manifest: everything about the skin except the grids themselves.
func serialize_manifest() -> String:
	var lines := PackedStringArray()
	lines.append("# OpenGolf Tycoon golfer skin - Re-color Groups and what wears it.")
	lines.append("# The layers/ folder holds one re-color layer per animation sprite.")
	lines.append("%s %d" % [FORMAT_TAG, FORMAT_VERSION])
	lines.append("id %s" % id)
	lines.append("name %s" % display_name)
	lines.append("sprites %s" % sprite_id)
	lines.append("size %d %d" % [sprite_size.x, sprite_size.y])
	var tiers := PackedStringArray()
	for tier in worn_by:
		tiers.append(tier_key(tier))
	lines.append("worn_by %s" % " ".join(tiers).strip_edges())
	for group in groups:
		var color: Color = group.get("color", Color.WHITE)
		lines.append("group %d %s %s %.3f %s" % [
			int(group.get("id", 0)), str(group.get("symbol", "")),
			color.to_html(false), float(group.get("shade", 1.0)), str(group.get("name", ""))])
	return "\n".join(lines) + "\n"


## Read a manifest. The skin's folder and its art are filled in by
## GolferSkinLibrary, which knows where skins live.
static func parse_manifest(text: String, skin_id: String = "") -> GolferSkin:
	var skin := GolferSkin.new()
	skin.id = skin_id
	skin.display_name = skin_id
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	for raw_line in lines:
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts := line.split(" ", false)
		match parts[0]:
			FORMAT_TAG:
				var version := int(parts[1]) if parts.size() > 1 else FORMAT_VERSION
				if version > FORMAT_VERSION:
					skin.warnings.append("Written by a newer version of the game (%d)" % version)
			"id":
				if parts.size() > 1:
					skin.id = parts[1]
			"name":
				if parts.size() > 1:
					skin.display_name = line.trim_prefix("name ").strip_edges()
			"sprites":
				if parts.size() > 1:
					skin.sprite_id = parts[1]
			"size":
				if parts.size() > 2:
					skin.sprite_size = Vector2i(maxi(int(parts[1]), 1), maxi(int(parts[2]), 1))
			"worn_by":
				for key in parts.slice(1):
					var tier := TIER_KEYS.find(str(key).to_lower())
					if tier >= 0 and not skin.worn_by.has(tier):
						skin.worn_by.append(tier)
				skin.worn_by.sort()
			"group":
				skin._read_group_line(line)
			_:
				skin.warnings.append("Ignored unknown line: %s" % line.left(32))
	if skin.display_name.is_empty():
		skin.display_name = skin.id
	return skin


## `group <id> <symbol> <colour> <shade> <name...>` - the name runs to the end
## of the line so it may contain spaces.
func _read_group_line(line: String) -> void:
	var parts := line.split(" ", false, 5)
	if parts.size() < 5:
		warnings.append("Ignored a group line with too few fields: %s" % line.left(32))
		return
	var group_id := int(parts[1])
	var symbol := parts[2]
	var color := Color.from_string(parts[3], Color.WHITE)
	var shade := clampf(float(parts[4]), 0.01, 1.0)
	var group_name := ""
	if parts.size() > 5:
		group_name = parts[5].strip_edges().left(MAX_GROUP_NAME_LENGTH)
	if group_id <= 0 or group_id > 255:
		warnings.append("Ignored group %d: ids run from 1 to 255" % group_id)
		return
	if symbol.length() != 1 or symbol == GolferSkinLayer.EMPTY_SYMBOL or symbol == "#":
		warnings.append("Group %d uses '%s' as its symbol; falling back to a free one" % [group_id, symbol])
		symbol = _next_symbol()
		if group_name.is_empty():
			group_name = "Group %d" % group_id
	if group_name.is_empty():
		group_name = "Group %d" % group_id
	groups.append({
		"id": group_id,
		"name": unique_group_name(group_name),
		"symbol": symbol,
		"color": color,
		"shade": shade,
	})


## Write the skin: the manifest and every layer file the artwork has, so a skin
## folder is complete and editable by hand. Returns false when the folder could
## not be written.
func save_to(folder: String) -> bool:
	if folder.is_empty():
		return false
	var layers_dir := folder.path_join(LAYER_DIR)
	if not _make_dir(folder) or not _make_dir(layers_dir):
		return false
	var manifest := FileAccess.open(folder.path_join(MANIFEST_FILE), FileAccess.WRITE)
	if manifest == null:
		return false
	manifest.store_string(serialize_manifest())
	manifest.close()

	var symbols := id_to_symbol()
	var legend := group_legend()
	var keys := sprite_keys()
	# Layers the artwork does not list (an edited file for a sprite that has
	# since been removed) are still written, so no edit is silently dropped.
	for key in _layers.keys():
		if not keys.has(str(key)):
			keys.append(str(key))
	for key in keys:
		_write_layer(folder, str(key), symbols, legend)
	dir = folder
	is_user_skin = true
	clear_unsaved_changes()
	return true


func _write_layer(folder: String, key: String, symbols: Dictionary, legend: Dictionary) -> void:
	var key_dir := folder.path_join(LAYER_DIR).path_join(key.get_base_dir())
	if not _make_dir(key_dir):
		return
	var file := FileAccess.open(layer_path(folder, key), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(layer(key).serialize(symbols, legend))
	file.close()


static func _make_dir(path: String) -> bool:
	if DirAccess.dir_exists_absolute(path):
		return true
	return DirAccess.make_dir_recursive_absolute(path) == OK


## The id a display name suggests: lowercase, dashes for spaces, no punctuation.
static func slug(text: String, fallback: String = "skin") -> String:
	var slugged := ""
	for character in text.strip_edges().to_lower():
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9"):
			slugged += character
		elif character == " " or character == "-" or character == "_":
			if not slugged.ends_with("-"):
				slugged += "-"
	slugged = slugged.trim_prefix("-").trim_suffix("-").left(24)
	return slugged if not slugged.is_empty() else fallback
