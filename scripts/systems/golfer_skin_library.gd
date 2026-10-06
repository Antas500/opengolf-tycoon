extends RefCounted
class_name GolferSkinLibrary
## Finds the Golfer Skins that ship with the game and the ones the player has
## made, and turns them into the sprite frames a golfer is drawn with.
##
## A skin is a folder of editable text files (see GolferSkin). Built-in skins
## live in `res://data/golfer_skins/`; whatever the player edits or creates is
## written to `user://golfer_skins/`, which shadows a built-in skin of the same
## id. The sprite art itself is never copied: a skin names the sprite set it
## wears (`sprites casual`) and the frames come from
## `res://assets/sprites/golfer/<set>/animations/`.
##
## Frames are built once and shared: every golfer wearing the same skin - with
## the same colours - draws from one SpriteFrames resource, so a crowd of
## visitors costs one re-color of the artwork, not one each.

const BUILT_IN_ROOT: String = "res://data/golfer_skins"
const USER_ROOT: String = "user://golfer_skins"
const SPRITE_ROOT: String = "res://assets/sprites/golfer"
## The sprite set a skin wears when the player does not pick one.
const DEFAULT_SPRITE_ID: String = "casual"

## Animations, the order they are played in and their playback settings (the
## same ones Golfer has always used for its sprite renderer).
const ANIMATIONS: Array[String] = ["idle", "walk", "swing"]
const ANIMATION_FPS := {"idle": 4.0, "walk": 8.0, "swing": 10.0}
const ANIMATION_LOOP := {"idle": true, "walk": true, "swing": false}
const MAX_FRAMES: int = 16
const DIRECTIONS: Array[String] = ["south", "south-east", "east", "north-east",
	"north", "north-west", "west", "south-west"]
## Directions whose art may be missing: they fall back to the nearest cardinal
## (the same fallback the golfer's sprite renderer has always used).
const DIAGONAL_FALLBACKS := {
	"south-east": "south", "north-east": "east",
	"north-west": "north", "south-west": "west",
}

var built_in_root: String = BUILT_IN_ROOT
var user_root: String = USER_ROOT
var sprite_root: String = SPRITE_ROOT

## id -> GolferSkin, kept sorted with the built-in skins first.
var _skins: Dictionary = {}
var _order: Array[String] = []
var _raw_frames: Dictionary = {}
var _recolored_frames: Dictionary = {}
var _textures: Dictionary = {}


func _init(skins_root: String = BUILT_IN_ROOT, player_root: String = USER_ROOT,
		art_root: String = SPRITE_ROOT) -> void:
	built_in_root = skins_root
	user_root = player_root
	sprite_root = art_root
	reload()


# =============================================================================
# THE SKINS ON DISK
# =============================================================================

## Read every skin folder again, built-ins first so a player's copy of a
## built-in skin wins.
func reload() -> void:
	_skins.clear()
	_order.clear()
	_raw_frames.clear()
	_recolored_frames.clear()
	for root in [built_in_root, user_root]:
		for folder in _skin_folders(root):
			var skin := _read_skin(folder, folder.begins_with(user_root))
			_register(skin, folder)
	_reorder()
	_delete_unused_user_dir()


func _skin_folders(root: String) -> Array[String]:
	var folders: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return folders
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			folders.append(root.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	folders.sort()
	return folders


func _read_skin(folder: String, is_user: bool) -> GolferSkin:
	var manifest_path := folder.path_join(GolferSkin.MANIFEST_FILE)
	var folder_id := folder.get_file()
	var skin := GolferSkin.parse_manifest(FileAccess.get_file_as_string(manifest_path), folder_id)
	skin.dir = folder
	skin.fallback_dir = ""
	skin.is_user_skin = is_user
	return skin


## Add a skin, keeping an already registered built-in as the fallback of the
## player's copy and resolving where its sprite art lives.
func _register(skin: GolferSkin, folder: String) -> void:
	var existing: GolferSkin = _skins.get(skin.id, null)
	if existing != null:
		if skin.is_user_skin:
			skin.fallback_dir = existing.dir
		else:
			skin.fallback_dir = existing.fallback_dir
			skin.dir = existing.dir
	_skins[skin.id] = skin
	skin.art_root = _art_root_for(skin, folder)


## The sprite sets the artwork offers, e.g. ["beginner", "casual"] - the
## folders under assets/sprites/golfer that carry a full idle animation.
func sprite_sets() -> Array[String]:
	var sets: Array[String] = []
	var dir := DirAccess.open(sprite_root)
	if dir == null:
		return sets
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with(".") \
				and FileAccess.file_exists(sprite_probe_path(entry)):
			sets.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	sets.sort()
	return sets


## The first sprite of a set: what tells a full set from an empty folder.
func sprite_probe_path(sprite_id: String) -> String:
	return sprite_root.path_join(sprite_id).path_join("animations").path_join("idle") \
		.path_join("south").path_join("frame_000.png")


## A skin's own animations folder when it ships art, else the sprite set it
## names under assets/sprites/golfer.
func _art_root_for(skin: GolferSkin, folder: String) -> String:
	if not folder.is_empty():
		var own := folder.path_join("animations")
		if DirAccess.dir_exists_absolute(own):
			return own
	if skin.sprite_id.is_empty():
		return ""
	return sprite_root.path_join(skin.sprite_id).path_join("animations")


## Keep the skin list in the order the editor shows it: the skins that ship
## with the game first, then the player's own, each by name.
func _reorder() -> void:
	_order = []
	for key in _skins.keys():
		_order.append(str(key))
	_order.sort_custom(_sort_skins)


func _sort_skins(a: String, b: String) -> bool:
	var skin_a: GolferSkin = _skins[a]
	var skin_b: GolferSkin = _skins[b]
	if skin_a.is_user_skin != skin_b.is_user_skin:
		return skin_a.is_user_skin
	return a.naturalnocasecmp_to(b) < 0


# =============================================================================
# LOOKUP
# =============================================================================

func skins() -> Array[GolferSkin]:
	var list: Array[GolferSkin] = []
	for id in _order:
		list.append(_skins[id])
	return list


func skin_ids() -> Array[String]:
	return _order.duplicate()


func get_skin(skin_id: String) -> GolferSkin:
	return _skins.get(skin_id, null)


func has_skin(skin_id: String) -> bool:
	return _skins.has(skin_id)


func is_user_skin(skin_id: String) -> bool:
	var skin: GolferSkin = get_skin(skin_id)
	return skin != null and skin.is_user_skin


## The skins that dress visitors of this tier: the ones the player has said
## wear it, or - when nobody has been dressed for it - the tier's own shipped
## skin. Serious and Pro visitors have no artwork of their own and so wear the
## Casual skin, exactly the sprite set every visitor wore before skins.
func skins_for_tier(tier: int) -> Array[GolferSkin]:
	var list: Array[GolferSkin] = []
	for skin in skins():
		if skin.wears_tier(tier):
			list.append(skin)
	if not list.is_empty():
		return list
	var default_skin := get_skin(default_skin_id_for_tier(tier))
	if default_skin != null:
		list.append(default_skin)
	return list


static func default_skin_id_for_tier(tier: int) -> String:
	if tier == GolferTier.Tier.BEGINNER:
		return "beginner"
	return "casual"


## The skin a visitor of this tier wears. `rng` may be passed to make the pick
## repeatable (tests); left out, one of the tier's skins is picked at random so
## a course with several skins dressed for one tier sees them all.
func skin_for_tier(tier: int, rng: RandomNumberGenerator = null) -> GolferSkin:
	var candidates := skins_for_tier(tier)
	if candidates.is_empty():
		return null
	if candidates.size() == 1:
		return candidates[0]
	if rng != null:
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	return candidates[randi_range(0, candidates.size() - 1)]


## The skin the owner golfer wears: the one the player picked, else the skin
## the Casual tier wears.
func player_skin(chosen_id: String = "") -> GolferSkin:
	if not chosen_id.is_empty():
		var chosen := get_skin(chosen_id)
		if chosen != null:
			return chosen
	return skin_for_tier(GolferTier.Tier.CASUAL)


# =============================================================================
# MAKING AND SAVING SKINS
# =============================================================================

## A brand new skin: the player's own groups and layers over an existing sprite
## set, with nothing painted yet.
func create_skin(display_name: String, sprite_id: String = DEFAULT_SPRITE_ID) -> GolferSkin:
	var skin := GolferSkin.new()
	skin.display_name = display_name.strip_edges().left(GolferSkin.MAX_SKIN_NAME_LENGTH)
	if skin.display_name.is_empty():
		skin.display_name = "New Skin"
	skin.id = unique_skin_id(GolferSkin.slug(skin.display_name))
	skin.sprite_id = sprite_id
	skin.sprite_size = sprite_size_of(sprite_id)
	skin.art_root = _art_root_for(skin, "")
	skin.is_user_skin = true
	return skin


## A copy of an existing skin - its groups and every painted layer - under a
## new name. The copy is not dressed on any tier: the player decides.
func duplicate_skin(source: GolferSkin, display_name: String = "") -> GolferSkin:
	if source == null:
		return null
	var name := display_name.strip_edges()
	if name.is_empty():
		name = "%s Copy" % source.display_name
	var skin := create_skin(name, source.sprite_id)
	skin.sprite_size = source.sprite_size
	skin.groups = []
	for group in source.group_list():
		skin.groups.append(group.duplicate(true))
	# The copy is not dressed on any tier: a second skin for the same visitors
	# would only make it a coin toss which one they turn up in.
	skin.worn_by = []
	source.preload_layers()
	for key in source.loaded_layer_keys():
		skin.set_layer(key, source.layer(key).duplicate_layer())
	return skin


## An id no skin uses: the slug of the name, then -2, -3... for the next.
func unique_skin_id(base_id: String) -> String:
	var wanted := base_id if not base_id.is_empty() else "skin"
	if not has_skin(wanted):
		return wanted
	var suffix := 2
	while has_skin("%s-%d" % [wanted, suffix]):
		suffix += 1
	return "%s-%d" % [wanted, suffix]


## The size of a sprite set's art, so a new skin's layers match its pixels.
func sprite_size_of(sprite_id: String) -> Vector2i:
	var first := sprite_probe_path(sprite_id)
	if not ResourceLoader.exists(first):
		return Vector2i(48, 48)
	var texture := load(first) as Texture2D
	if texture == null:
		return Vector2i(48, 48)
	return Vector2i(texture.get_width(), texture.get_height())


## Give a built-in skin a player-owned copy: its manifest and every layer file
## are written to the user folder, which from then on shadows the shipped one.
func ensure_editable(skin: GolferSkin) -> bool:
	if skin == null:
		return false
	if skin.is_user_skin and not skin.dir.is_empty() and skin.dir.begins_with(user_root):
		return true
	var folder := user_root.path_join(skin.id)
	var source_dir := skin.dir
	if not GolferSkin._make_dir(folder):
		return false
	var manifest := FileAccess.open(folder.path_join(GolferSkin.MANIFEST_FILE), FileAccess.WRITE)
	if manifest != null:
		manifest.store_string(skin.serialize_manifest())
		manifest.close()
	_copy_layers(source_dir, folder)
	if not source_dir.is_empty() and source_dir != folder:
		skin.fallback_dir = source_dir
	skin.dir = folder
	skin.is_user_skin = true
	return true


## Copy every layer file of a skin folder (recursively) into another.
func _copy_layers(from_dir: String, to_dir: String) -> void:
	if from_dir.is_empty():
		return
	var from_layers := from_dir.path_join(GolferSkin.LAYER_DIR)
	var dir := DirAccess.open(from_layers)
	if dir == null:
		return
	for path in _files_under(from_layers):
		var relative := path.trim_prefix(from_layers).trim_prefix("/")
		var target := to_dir.path_join(GolferSkin.LAYER_DIR).path_join(relative)
		GolferSkin._make_dir(target.get_base_dir())
		DirAccess.copy_absolute(path, target)


func _files_under(root: String) -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return files
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := root.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				files.append_array(_files_under(full))
		else:
			files.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	files.sort()
	return files


## Write a skin out (copying a built-in one into the player's folder first),
## then let every golfer draw the new colours.
func save_skin(skin: GolferSkin) -> bool:
	if skin == null:
		return false
	# A skin the player makes always lives in the user folder.
	if skin.id.is_empty():
		return false
	if not ensure_editable(skin):
		return false
	if not skin.save_to(user_root.path_join(skin.id)):
		return false
	_register(skin, skin.dir)
	_reorder()
	_order.sort_custom(_sort_skins)
	invalidate(skin.id)
	return true


## Throw away the player's copy of a skin, leaving the shipped one. Only skins
## that have a built-in original can be reverted.
func revert_skin(skin: GolferSkin) -> bool:
	if skin == null or skin.fallback_dir.is_empty():
		return false
	if not _remove_dir(user_root.path_join(skin.id)):
		return false
	reload()
	return true


## Delete a player-made skin. Built-in skins can only be reverted.
func delete_skin(skin: GolferSkin) -> bool:
	if skin == null or not skin.is_user_skin:
		return false
	if not _remove_dir(user_root.path_join(skin.id)):
		return false
	if skin.fallback_dir.is_empty():
		_skins.erase(skin.id)
	else:
		var shipped := _read_skin(skin.fallback_dir, false)
		shipped.fallback_dir = ""
		_skins[skin.id] = shipped
	_reorder()
	invalidate(skin.id)
	return true


## Delete a folder and everything in it.
static func _remove_dir(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return false
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if dir.current_is_dir():
			if entry.begins_with("."):
				pass
			elif not _remove_dir(full):
				return false
		elif DirAccess.remove_absolute(full) != OK:
			return false
		entry = dir.get_next()
	dir.list_dir_end()
	return DirAccess.remove_absolute(path) == OK


## Remove folders that no longer hold a skin (a half-copied one, say), so the
## user folder reads as the list of the player's skins.
func _delete_unused_user_dir() -> void:
	var dir := DirAccess.open(user_root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			var folder := user_root.path_join(entry)
			if not FileAccess.file_exists(folder.path_join(GolferSkin.MANIFEST_FILE)):
				_remove_dir(folder)
		entry = dir.get_next()
	dir.list_dir_end()


# =============================================================================
# FRAMES AND TEXTURES
# =============================================================================

## Every sprite of the skin's artwork, as one animation per direction
## ("idle_south", "walk_north-east"...), exactly as the golfer plays them.
func raw_frames(skin: GolferSkin) -> SpriteFrames:
	if skin == null:
		return null
	if _raw_frames.has(skin.id):
		return _raw_frames[skin.id]
	var frames := _build_frames(skin, {}, false)
	_raw_frames[skin.id] = frames
	return frames


## The same animations with the skin's colours (and any owner profile colours)
## applied through the Re-color Layers.
func recolored_frames(skin: GolferSkin, overrides: Dictionary = {}) -> SpriteFrames:
	if skin == null:
		return null
	var cache_key := "%s|%s" % [skin.id, _fingerprint(overrides)]
	var cached: Variant = _recolored_frames.get(cache_key, null)
	if cached != null:
		return cached
	var frames := _build_frames(skin, overrides, true)
	_recolored_frames[cache_key] = frames
	return frames


func _build_frames(skin: GolferSkin, overrides: Dictionary, recolor: bool) -> SpriteFrames:
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")
	var colors := skin.effective_colors(overrides)
	var shades := {}
	for group in skin.group_list():
		shades[int(group.get("id", 0))] = maxf(float(group.get("shade", 1.0)), 0.01)
	var recolored: Dictionary = {}
	var built := false
	for animation in ANIMATIONS:
		for direction in DIRECTIONS:
			var keys := frame_keys(skin, animation, direction)
			if keys.is_empty():
				continue
			var animation_name := "%s_%s" % [animation, direction]
			frames.add_animation(animation_name)
			frames.set_animation_speed(animation_name, float(ANIMATION_FPS[animation]))
			frames.set_animation_loop(animation_name, bool(ANIMATION_LOOP[animation]))
			for key in keys:
				var texture: Texture2D = null
				if recolor and not skin.layer(key).is_empty():
					texture = _recolored_texture(skin, key, colors, shades, recolored)
				else:
					texture = texture_for(skin, key)
				if texture != null:
					frames.add_frame(animation_name, texture)
					built = true
	if not built:
		return null
	return frames


func _recolored_texture(skin: GolferSkin, key: String, colors: Dictionary,
		shades: Dictionary, cache: Dictionary) -> Texture2D:
	if cache.has(key):
		return cache[key]
	var texture := texture_for(skin, key)
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	var sprite_layer := skin.layer(key)
	if sprite_layer.is_empty():
		cache[key] = texture
		return texture
	var result := ImageTexture.create_from_image(sprite_layer.recolor(image, colors, shades))
	cache[key] = result
	return result


## The recolored copy of one sprite, for the editor's preview.
func recolor_texture(skin: GolferSkin, key: String, overrides: Dictionary = {}) -> Texture2D:
	var texture := texture_for(skin, key)
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	var colors := skin.effective_colors(overrides)
	var shades := {}
	for group in skin.group_list():
		shades[int(group.get("id", 0))] = maxf(float(group.get("shade", 1.0)), 0.01)
	return ImageTexture.create_from_image(skin.layer(key).recolor(image, colors, shades))


## The sprite itself, straight off disk (cached).
func texture_for(skin: GolferSkin, key: String) -> Texture2D:
	if skin == null or skin.art_root.is_empty():
		return null
	var path := skin.art_root.path_join(key + ".png")
	if _textures.has(path):
		return _textures[path]
	var texture := load(path) as Texture2D
	_textures[path] = texture
	return texture


## The layer keys of one animation and direction, in frame order. Diagonals
## whose art was never drawn fall back to the nearest cardinal, so the frames
## the editor paints are the frames the golfer shows.
func frame_keys(skin: GolferSkin, animation: String, direction: String) -> Array[String]:
	var keys: Array[String] = []
	if skin == null or skin.art_root.is_empty():
		return keys
	var animation_dir := skin.art_root.path_join(animation)
	var chosen := direction
	if not DirAccess.dir_exists_absolute(animation_dir.path_join(chosen)):
		chosen = str(DIAGONAL_FALLBACKS.get(direction, ""))
		if chosen.is_empty() or not DirAccess.dir_exists_absolute(animation_dir.path_join(chosen)):
			return keys
	var frame := 0
	while frame < MAX_FRAMES:
		var key := GolferSkin.layer_key(animation, chosen, frame)
		if not FileAccess.file_exists(skin.art_root.path_join(key + ".png")):
			break
		keys.append(key)
		frame += 1
	return keys


## The (animation, direction) pairs the skin can actually play.
func animation_names(skin: GolferSkin) -> Array[String]:
	var names: Array[String] = []
	for animation in ANIMATIONS:
		for direction in DIRECTIONS:
			if not frame_keys(skin, animation, direction).is_empty():
				names.append("%s_%s" % [animation, direction])
	return names


func _fingerprint(overrides: Dictionary) -> String:
	if overrides.is_empty():
		return "-"
	var parts := PackedStringArray()
	var keys := overrides.keys()
	keys.sort()
	for key in keys:
		var color: Color = overrides[key]
		parts.append("%s=%s" % [key, color.to_html(false)])
	return ",".join(parts)


## Forget the frames built for a skin (or for every skin when the id is empty)
## so the next golfer drawn picks up fresh layers and colours.
func invalidate(skin_id: String = "") -> void:
	if skin_id.is_empty():
		_raw_frames.clear()
		_recolored_frames.clear()
		return
	_raw_frames.erase(skin_id)
	for key in _recolored_frames.keys():
		if str(key).begins_with(skin_id + "|"):
			_recolored_frames.erase(key)
