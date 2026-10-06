extends SceneTree
## Writes the built-in Golfer Skins' Re-color Layers and manifests.
##
##     godot --headless --path . --script res://tools/generate_golfer_skin_layers.gd
##
## Every animation sprite of every sprite set under assets/sprites/golfer is
## read once and each pixel is filed into the Re-color Group its colour belongs
## to, producing data/golfer_skins/<id>/skin.txt plus one
## layers/<animation>/<direction>/<frame>.layer.txt per sprite. Each group's
## colour is sampled from the artwork (the most common colour among its pixels)
## and its shade is that colour's brightness, so a freshly generated skin draws
## exactly the art it was generated from.
##
## The classification below is the one the game used before skins existed
## (Golfer._classify_player_sprite_pixel): the regions the player's own golfer
## has always been re-coloured in. It is kept here, out of the game, as the
## starting point the player's edits build on.
##
## Run it again after adding sprite art; it rewrites the built-in skins, never
## anything in user://golfer_skins, and it is not part of the test suite.

const SPRITE_ROOT := "res://assets/sprites/golfer"
const SKIN_ROOT := "res://data/golfer_skins"
const ANIMATIONS := ["idle", "walk", "swing"]
const DIRECTIONS := ["south", "south-east", "east", "north-east",
	"north", "north-west", "west", "south-west"]

## The groups every built-in skin carries, in id order.
const GROUPS := [
	{"id": 1, "name": "Shirt", "symbol": "A", "key": "shirt"},
	{"id": 2, "name": "Pants", "symbol": "B", "key": "pants"},
	{"id": 3, "name": "Cap", "symbol": "C", "key": "cap"},
	{"id": 4, "name": "Hair", "symbol": "D", "key": "hair"},
	{"id": 5, "name": "Skin", "symbol": "E", "key": "skin"},
]
const NO_GROUP := 0

## The sprite sets shipped with the game and the visitor tier each is for.
const SKINS := {
	"beginner": GolferTier.Tier.BEGINNER,
	"casual": GolferTier.Tier.CASUAL,
}


func _initialize() -> void:
	for skin_id in SKINS:
		_generate(skin_id)
	quit(0)


func _generate(skin_id: String) -> void:
	var art_root := SPRITE_ROOT.path_join(skin_id).path_join("animations")
	if not DirAccess.dir_exists_absolute(art_root):
		print("Skipping %s: no art at %s" % [skin_id, art_root])
		return

	var skin := GolferSkin.new()
	skin.id = skin_id
	skin.display_name = skin_id.capitalize()
	skin.sprite_id = skin_id
	skin.sprite_size = Vector2i(48, 48)
	skin.art_root = art_root
	skin.worn_by = [int(SKINS[skin_id])]
	skin.is_user_skin = false
	for spec in GROUPS:
		# Colours and shades are sampled from the art below.
		skin.groups.append({
			"id": int(spec["id"]), "name": str(spec["name"]),
			"symbol": str(spec["symbol"]), "color": Color.WHITE, "shade": 1.0,
		})

	var histograms := {}
	var pixels_per_group := {}
	for animation in ANIMATIONS:
		for direction in DIRECTIONS:
			var frame := 0
			while true:
				var key := GolferSkin.layer_key(animation, direction, frame)
				var path := art_root.path_join(key + ".png")
				if not FileAccess.file_exists(path):
					break
				var texture := load(path) as Texture2D
				var image := texture.get_image() if texture != null else null
				if image == null or image.is_empty():
					push_error("Could not read %s" % path)
					break
				var sprite_layer := GolferSkinLayer.create(image.get_width(), image.get_height())
				for y in image.get_height():
					for x in image.get_width():
						var group_id := classify(image.get_pixel(x, y), x, y,
							image.get_width(), image.get_height(), direction)
						if group_id == NO_GROUP:
							continue
						sprite_layer.set_cell(x, y, group_id)
						_sample(histograms, group_id, image.get_pixel(x, y))
						pixels_per_group[group_id] = int(pixels_per_group.get(group_id, 0)) + 1
				skin.set_layer(key, sprite_layer)
				frame += 1

	_apply_sampled_colors(skin, histograms, pixels_per_group)
	var folder := SKIN_ROOT.path_join(skin_id)
	if not skin.save_to(folder):
		push_error("Could not write %s" % folder)
		return
	skin.clear_unsaved_changes()
	print("%s: %d sprites, %d painted pixels -> %s" % [skin_id, skin.sprite_keys().size(),
		pixels_per_group.values().reduce(func(sum, value): return sum + value, 0), folder])
	for group in skin.group_list():
		print("    %-6s %-2s %s  shade %.2f  %d pixels" % [group["name"], group["symbol"],
			(group["color"] as Color).to_html(false), group["shade"],
			int(pixels_per_group.get(int(group["id"]), 0))])


## Record one pixel of a group: how often the artwork uses each colour in it.
func _sample(histograms: Dictionary, group_id: int, color: Color) -> void:
	var counts: Dictionary = histograms.get(group_id, {})
	var hex := color.to_html(false)
	counts[hex] = int(counts.get(hex, 0)) + 1
	histograms[group_id] = counts


## Colour each group after the artwork: the colour the region is mostly made of
## is what the group is drawn in, and that colour's brightness is the group's
## shade reference. The region's flat colour therefore lands exactly on the
## player's chosen colour, with the artwork's shadows shading down from it.
func _apply_sampled_colors(skin: GolferSkin, histograms: Dictionary,
		pixels_per_group: Dictionary) -> void:
	for group in skin.group_list():
		var group_id := int(group["id"])
		var counts: Dictionary = histograms.get(group_id, {})
		if counts.is_empty():
			continue
		var best := ""
		var best_count := -1
		for hex in counts:
			var count := int(counts[hex])
			if count > best_count:
				best = str(hex)
				best_count = count
		var color := Color.from_string(best, Color.WHITE)
		skin.set_group_color(group_id, color)
		skin.set_group_shade(group_id, maxf(maxf(color.r, color.g), color.b))


## Which Re-color Group a pixel of the shipped artwork belongs to: the flat
## colour regions of the 48x48 golfer sprites, told apart by hue and by where
## they sit (hair above the face, trousers below the belt, the cap's cool
## near-white, the polo's strong red).
func classify(source: Color, x: int, y: int, width: int, height: int, direction: String) -> int:
	if source.a <= 0.01:
		return NO_GROUP
	var vertical := float(y) / maxf(height, 1)
	var horizontal := float(x) / maxf(width, 1)

	# Cap: a cool, near-white lavender in the stock palette.
	if vertical <= 0.34 and source.b > source.r * 1.025 \
			and absf(source.r - source.g) < 0.18 and source.r > 0.30:
		return 3

	# Hair: brown, above the face; the back-facing frame shows more of it.
	var hair_area := vertical <= 0.32
	if direction.begins_with("north"):
		hair_area = vertical <= 0.46
	elif direction.contains("east"):
		hair_area = vertical <= 0.44 and horizontal < 0.50
	elif direction.contains("west"):
		hair_area = vertical <= 0.44 and horizontal > 0.50
	if hair_area and source.r > source.g * 1.08 and source.g > source.b * 1.01 \
			and source.r >= 0.22 and source.r < 0.50:
		return 4

	# Shirt: the polo's strong red separates it from skin and hair.
	if source.r > source.g * 1.9 and source.r > source.b * 1.55:
		return 1

	# Skin: warm, mid-bright, and on the face or the arms.
	var is_warm_skin := source.r > source.g and source.g > source.b \
		and source.r > 0.42 and source.r - source.g > 0.045 \
		and source.r - source.g < 0.48 and source.g - source.b > 0.015
	var is_face_or_arm_area := vertical < 0.58 \
		or (vertical < 0.72 and (horizontal < 0.40 or horizontal > 0.60))
	if is_warm_skin and is_face_or_arm_area:
		return 5

	# Trousers fill the lower body; the shoes below them keep their leather.
	if vertical >= 0.58 and vertical < 0.83 and source.r > source.g * 1.04 \
			and source.g >= source.b * 0.95 and source.r < 0.76:
		return 2

	return NO_GROUP
