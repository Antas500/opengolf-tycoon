extends GutTest
## Unit tests for the Golfer Skin catalogue, its colour pipeline and the owner's
## profile entries that keep their skins across saves.

## The catalogue the game ships: the two hand-made looks and nothing else, each
## one with every frame of its animation set on disk.
func test_the_two_hand_made_skins_ship_with_every_frame_on_disk() -> void:
	var ids: Array = []
	for skin in GolferSkinLibrary.builtin_skins():
		ids.append(skin.id)
	assert_eq(ids.size(), 2, "two skins ship with the game (got %s)" % [ids])
	assert_true(ids.has("beginner") and ids.has("casual"),
		"the hand-made Beginner and Casual looks (got %s)" % [ids])

	var missing: Array = []
	for skin in GolferSkinLibrary.builtin_skins():
		for direction in GolferSkinLibrary.DIRECTION_ORDER:
			for anim in GolferSkinLibrary.ANIMATIONS:
				var frames: int = GolferSkinLibrary.ANIMATIONS[anim]["frames"]
				for frame in frames:
					var path := "%s/animations/%s/%s/frame_%03d.png" % [skin.root, anim, direction, frame]
					if not ResourceLoader.exists(path):
						missing.append("%s/%s/%s/%d" % [skin.id, anim, direction, frame])
	assert_true(missing.is_empty(), "every skin has every frame (missing %d: %s)" % [missing.size(), missing.slice(0, 4)])

func test_every_skin_builds_playable_sprite_frames() -> void:
	for skin in GolferSkinLibrary.all_skins():
		var frames := GolferSkinLibrary.frames_for(skin, {})
		assert_not_null(frames, "%s builds SpriteFrames" % skin.id)
		if frames == null:
			continue
		for direction in GolferSkinLibrary.DIRECTION_ORDER:
			for anim in GolferSkinLibrary.ANIMATIONS:
				var animation := "%s_%s" % [anim, direction]
				assert_true(frames.has_animation(animation), "%s has %s" % [skin.id, animation])
				if frames.has_animation(animation):
					assert_eq(frames.get_frame_count(animation), int(GolferSkinLibrary.ANIMATIONS[anim]["frames"]),
						"%s %s frame count" % [skin.id, animation])

## Skins are re-coloured, not redrawn: the player's colour must land on every
## pixel the layer gives that part and leave everything else alone. The
## hand-made art is not drawn from ramps, so its own light and dark is carried
## across with the new colour.
func test_colour_overrides_repaint_one_part_and_keep_its_shading() -> void:
	var skin := GolferSkinLibrary.skin_by_id("casual")
	assert_not_null(skin)
	var art := GolferSkinLibrary.base_frame_image(skin, "south", "idle", 0)
	var plain_image: Image = GolferSkinLibrary.frames_for(skin, {}, true) \
		.get_frame_texture("idle_south", 0).get_image()
	var painted_image: Image = GolferSkinLibrary.frames_for(skin, {"shirt": Color("e01020")}, true) \
		.get_frame_texture("idle_south", 0).get_image()
	var layer := GolferSkinLibrary.frame_layer(skin, "south", "idle", 0)

	var shirt_pixels := 0
	var shades := {}
	var darkest := 2.0
	for y in GolferSkinLibrary.CANVAS:
		for x in GolferSkinLibrary.CANVAS:
			var before := plain_image.get_pixel(x, y)
			var after := painted_image.get_pixel(x, y)
			var index: int = layer[y * GolferSkinLibrary.CANVAS + x]
			if index == 0 or str(GolferSkinLibrary.decode_pixel(index)["part"]) != "shirt":
				assert_eq(after, before, "only the top's pixels are repainted (%d,%d)" % [x, y])
				continue
			shirt_pixels += 1
			shades[after.to_html(false)] = true
			darkest = minf(darkest, after.v)
			assert_ne(after, before, "the top at %d,%d takes the new colour" % [x, y])
	assert_gt(shirt_pixels, 60, "the shirt covers a good part of the sprite")
	assert_gte(shades.size(), 3, "the artist's shading survives the re-colour")
	# The new colour is a bright one, and the artist's shadowed side stays dark
	# rather than being flattened onto it.
	assert_gt(Color("e01020").v, darkest, "the pick is brighter than the darkest top pixel")
	var face := _pixel_of(skin, "skin")
	assert_ne(face.x, -1, "the art draws a face")
	assert_eq(painted_image.get_pixelv(face), art.get_pixelv(face), "which is not the top, and does not move")


func test_the_artists_palette_is_kept_when_nothing_is_overridden() -> void:
	var skin := GolferSkinLibrary.skin_by_id("casual")
	var frames := GolferSkinLibrary.frames_for(skin, {}, true)
	var image: Image = frames.get_frame_texture("idle_south", 0).get_image()
	var source: Image = GolferSkinLibrary.base_frame_image(skin, "south", "idle", 0)
	assert_eq(image.get_data(), source.get_data(), "an untouched skin is the shipped art")

## A skin the player built: its edited frames come from its own pixels, the
## frames they did not touch keep the art it was forked from.
func test_a_custom_skin_paints_over_the_base_art() -> void:
	var base := GolferSkinLibrary.skin_by_id("casual")
	var recipe := GolferSkinLibrary.new_custom_skin(base, "Test Skin")
	assert_true(recipe.custom)
	assert_eq(recipe.base_id, base.id)

	# Paint the top-left pixel of the first idle frame bright green.
	var overlay := PackedByteArray()
	overlay.resize(GolferSkinLibrary.CANVAS * GolferSkinLibrary.CANVAS)
	overlay[0] = GolferSkinLibrary.pixel_index("gear", 0)
	recipe.overlays[recipe.frame_key("idle", "south", 0)] = overlay
	recipe.revision += 1

	var frames := GolferSkinLibrary.frames_for(recipe, {}, true)
	var painted: Image = frames.get_frame_texture("idle_south", 0).get_image()
	var untouched: Image = frames.get_frame_texture("idle_south", 1).get_image()
	var base_frames := GolferSkinLibrary.frames_for(base, {}, true)
	var base_first: Image = base_frames.get_frame_texture("idle_south", 0).get_image()
	var base_second: Image = base_frames.get_frame_texture("idle_south", 1).get_image()

	assert_eq(painted.get_pixel(0, 0).a, 1.0, "the painted frame uses the skin's own pixels")
	assert_eq(untouched.get_data(), base_second.get_data(), "unpainted frames still use the base art")
	assert_ne(painted.get_data(), base_first.get_data(), "the painted frame is not the base frame any more")

## Stored pixels are part + shade indices, so colours can change after painting.
func test_painted_pixels_follow_a_colour_change() -> void:
	var base := GolferSkinLibrary.skin_by_id("casual")
	var recipe := GolferSkinLibrary.new_custom_skin(base, "Repaint")
	var overlay := PackedByteArray()
	overlay.resize(GolferSkinLibrary.CANVAS * GolferSkinLibrary.CANVAS)
	overlay[10] = GolferSkinLibrary.pixel_index("shirt", 0)
	recipe.overlays[recipe.frame_key("idle", "south", 0)] = overlay

	var first: Image = GolferSkinLibrary.frames_for(recipe, {}, true).get_frame_texture("idle_south", 0).get_image()
	recipe.colors["shirt"] = Color("00cc44")
	recipe.revision += 1
	var second: Image = GolferSkinLibrary.frames_for(recipe, {}, true).get_frame_texture("idle_south", 0).get_image()
	assert_eq(first.get_pixel(10, 0), GolferSkinLibrary.colour_for(base, "shirt"),
		"the painted pixel starts on the skin's shirt colour")
	assert_eq(second.get_pixel(10, 0), Color("00cc44"), "changing the shirt colour repaints it")

func test_encode_and_decode_round_trip_a_frame() -> void:
	# A skin of the player's own, so the shipped catalogue is left alone.
	var skin := GolferSkinLibrary.new_custom_skin(GolferSkinLibrary.skin_by_id("casual"), "Round Trip")
	var image: Image = GolferSkinLibrary.frames_for(skin, {}).get_frame_texture("walk_east", 2).get_image()
	var bytes := GolferSkinLibrary.encode_image(image, skin)
	assert_eq(bytes.size(), GolferSkinLibrary.CANVAS * GolferSkinLibrary.CANVAS)
	# No overlay stored yet: encode first, then decode from it.
	skin.overlays[skin.frame_key("walk", "east", 2)] = bytes
	var rebuilt := GolferSkinLibrary.image_from_overlay(skin, {}, GolferSkinLibrary.storage_palette(skin),
		"walk", "east", 2)
	var rebuilt_bytes := GolferSkinLibrary.encode_image(rebuilt, skin)
	assert_eq(rebuilt_bytes, bytes, "a frame survives the round trip through the editor's format")
	var painted := 0
	for index in bytes:
		if index > 0:
			painted += 1
	assert_gt(painted, 20, "and the frame is not stored empty")
	var decoded := GolferSkinLibrary.decode_pixel(bytes[20 * 48 + 24])
	assert_true(decoded.has("part"), "pixels decode back to a part")

## Every visitor can be dealt a skin. The two hand-made looks lead the Beginner
## and Casual tiers; the Tour Serious and Tour Pro visitors - whose tier art the
## game does not ship - fall back to the default skin.
func test_random_skin_for_a_tier_only_offers_that_tiers_skins() -> void:
	var tiers := [GolferTier.Tier.BEGINNER, GolferTier.Tier.CASUAL,
		GolferTier.Tier.SERIOUS, GolferTier.Tier.PRO]
	var offered := {}
	for tier in tiers:
		var options := GolferSkinLibrary.skins_for_tier(tier)
		for skin in options:
			assert_true(skin.spawn_tiers.has(GolferSkinLibrary.tier_key(tier)),
				"%s may be worn by tier %d" % [skin.id, tier])
			offered[skin.id] = true
		if options.is_empty():
			assert_eq(GolferSkinLibrary.random_skin_for_tier(tier).id,
				GolferSkinLibrary.default_skin_id(),
				"tier %d has no art of its own and falls back to the default skin" % tier)
		else:
			assert_eq(options[0].id, GolferSkinLibrary.tier_skin_id(tier),
				"the tier's own art is the common look")
	for skin in GolferSkinLibrary.builtin_skins():
		assert_true(offered.has(skin.id), "%s is offered to a tier" % skin.id)


## ── The part layers ───────────────────────────────────────────────────────

## Every pixel of every shipped frame is described by a part layer: that is what
## makes re-colouring exact rather than a guess at the colours. A frame without
## one would silently fall back to matching colours.
func test_every_shipped_frame_has_a_part_layer() -> void:
	var missing: Array = []
	var undecoded := 0
	for skin in GolferSkinLibrary.builtin_skins():
		var drawn := GolferSkinLibrary.layer_parts(skin)
		if drawn.is_empty():
			missing.append("%s (no layers at all)" % skin.id)
		for direction in GolferSkinLibrary.DIRECTION_ORDER:
			for anim in GolferSkinLibrary.ANIMATIONS:
				for frame in GolferSkinLibrary.ANIMATIONS[anim]["frames"]:
					var path := GolferSkinLibrary._frame_path(skin, direction, anim, frame)
					if path.is_empty():
						continue
					var layer := GolferSkinLibrary.frame_layer(skin, direction, anim, frame)
					if layer.size() != GolferSkinLibrary.CANVAS * GolferSkinLibrary.CANVAS:
						missing.append("%s/%s/%s/%d" % [skin.id, anim, direction, frame])
						continue
					for index in layer:
						if index == 0:
							continue
						var decoded := GolferSkinLibrary.decode_pixel(index)
						if decoded.is_empty() or not GolferSkinLibrary.PART_ORDER.has(str(decoded["part"])):
							undecoded += 1
	assert_true(missing.is_empty(), "every frame ships a layer (missing %d: %s)" % [missing.size(), missing.slice(0, 4)])
	assert_eq(undecoded, 0, "every layer byte decodes to a real part")


## The layer is the single source of truth for what a skin offers: a part the
## art draws is a part the colour pickers offer.
func test_a_skins_parts_are_the_parts_its_layer_draws() -> void:
	for skin in GolferSkinLibrary.builtin_skins():
		var drawn := GolferSkinLibrary.layer_parts(skin)
		assert_eq(Array(skin.customizable), drawn, "%s offers the parts its art draws" % skin.id)
		assert_eq(Array(PlayerGolferProfile.parts_for_skin(skin.id)), drawn,
			"%s offers them to the profile too" % skin.id)
		for part in drawn:
			assert_false(GolferSkinLibrary.layer_report(skin).get(part, 0) == 0,
				"%s really draws %s" % [skin.id, part])


## The point of the layer: a pixel only changes colour because of the part it was
## drawn as. The beginner art draws the hair and the trousers in the same navy,
## so re-colouring the trousers must leave the hair exactly as it was.
func test_recolouring_follows_the_layer_not_the_colour() -> void:
	var skin := GolferSkinLibrary.skin_by_id("beginner")
	var art := GolferSkinLibrary.base_frame_image(skin, "south", "idle", 0)
	var layer := GolferSkinLibrary.frame_layer(skin, "south", "idle", 0)
	var image: Image = GolferSkinLibrary.frames_for(skin, {"pants": Color("ff0000")}, true) \
		.get_frame_texture("idle_south", 0).get_image()
	var hair_pixels := 0
	var trouser_pixels := 0
	for y in GolferSkinLibrary.CANVAS:
		for x in GolferSkinLibrary.CANVAS:
			var index: int = layer[y * GolferSkinLibrary.CANVAS + x]
			if index == 0:
				continue
			var decoded := GolferSkinLibrary.decode_pixel(index)
			var before := art.get_pixel(x, y)
			var after := image.get_pixel(x, y)
			if str(decoded["part"]) == "hair":
				hair_pixels += 1
				assert_eq(after, before, "the hair at %d,%d is not the trousers" % [x, y])
			elif str(decoded["part"]) == "pants":
				trouser_pixels += 1
				assert_ne(after, before, "the trousers at %d,%d take the new colour" % [x, y])
	assert_gt(hair_pixels, 20, "the art draws a head of hair")
	assert_gt(trouser_pixels, 20, "and a pair of trousers")


## Re-colouring one part touches that part's pixels and nothing else - the eyes
## and highlights included.
func test_recolouring_one_part_keeps_every_other_pixel() -> void:
	for skin_id in ["beginner", "casual"]:
		var skin := GolferSkinLibrary.skin_by_id(skin_id)
		var art := GolferSkinLibrary.base_frame_image(skin, "south", "idle", 0)
		var layer := GolferSkinLibrary.frame_layer(skin, "south", "idle", 0)
		var image := art.duplicate() as Image
		var changed := GolferSkinLibrary.changed_colours(skin, {"shirt": Color("1188ee")})
		GolferSkinLibrary.recolour(image, skin, changed, "south", "idle", 0)
		var repainted := 0
		for y in GolferSkinLibrary.CANVAS:
			for x in GolferSkinLibrary.CANVAS:
				var index: int = layer[y * GolferSkinLibrary.CANVAS + x]
				var part := ""
				if index > 0:
					part = str(GolferSkinLibrary.decode_pixel(index).get("part", ""))
				if part == "shirt":
					repainted += 1
					assert_ne(image.get_pixel(x, y), art.get_pixel(x, y),
						"%s: the top at %d,%d is repainted" % [skin_id, x, y])
				else:
					assert_eq(image.get_pixel(x, y), art.get_pixel(x, y),
						"%s: %s at %d,%d keeps its art" % [skin_id, part if part else "the background", x, y])
		assert_gt(repainted, 40, "%s draws a top" % skin_id)


## A player-made skin is drawn with the art it was forked from, layer included.
func test_a_custom_skin_borrows_the_layers_of_its_base() -> void:
	var base := GolferSkinLibrary.skin_by_id("casual")
	var mine := GolferSkinLibrary.new_custom_skin(base, "Layer Test")
	assert_eq(Array(mine.customizable), Array(base.customizable), "it offers the base's parts")
	assert_eq(GolferSkinLibrary.layer_root(mine), GolferSkinLibrary.layer_root(base),
		"its layer lives with the base's art")
	assert_eq(GolferSkinLibrary.frame_layer(mine, "south", "idle", 0),
		GolferSkinLibrary.frame_layer(base, "south", "idle", 0), "and holds the same pixels")
	var drawn: Image = GolferSkinLibrary.frames_for(base, {"shirt": Color("00cc44")}, true) \
		.get_frame_texture("idle_south", 0).get_image()
	var mine_drawn: Image = GolferSkinLibrary.frames_for(mine, {"shirt": Color("00cc44")}, true) \
		.get_frame_texture("idle_south", 0).get_image()
	assert_eq(mine_drawn.get_data(), drawn.get_data(),
		"and re-colours the very same pixels the base does")


## Art that ships without a layer still paints and re-colours: the pixels are
## matched back to the palette instead, the way it worked before layers.
## Art with no part layer on disk - an older or hand-authored skin - still
## re-colours: the pixels are matched back against the palette instead. Both
## shipped looks have layers now, so this paints the pixels to check.
func test_art_without_a_layer_still_recolours() -> void:
	var skin := GolferSkinLibrary.skin_by_id("casual")
	var palette := GolferSkinLibrary.storage_palette(skin)
	var image := Image.create(GolferSkinLibrary.CANVAS, GolferSkinLibrary.CANVAS, false, Image.FORMAT_RGBA8)
	var top := Vector2i(5, 5)
	var hair := Vector2i(6, 5)
	image.set_pixelv(top, palette["shirt"][0])
	image.set_pixelv(hair, palette["hair"][0])
	# No frame given: with no layer to read, re-colouring matches the colours.
	GolferSkinLibrary.recolour(image, skin, {"shirt": Color("22ff22")})
	assert_eq(image.get_pixelv(top), GolferSkinLibrary.ramp(Color("22ff22"))[0],
		"a pixel drawn in the top's colour takes the new one")
	assert_eq(image.get_pixelv(hair), palette["hair"][0],
		"and a pixel drawn in another part's colour keeps its art")


## A skin whose art *is* drawn from ramps re-emits the ramp stop the layer
## records, rather than carrying the artist's brightness across. Both shipped
## looks are hand-made, so this builds a ramp-drawn skin over their art.
func test_a_ramp_drawn_skin_takes_the_shades_the_layer_records() -> void:
	var art := GolferSkinLibrary.skin_by_id("casual")
	var skin := GolferSkinLibrary.SkinDef.new()
	skin.id = "ramp_drawn"
	skin.root = art.root
	skin.colors = art.colors.duplicate()
	skin.customizable = PackedStringArray(GolferSkinLibrary.PAINTABLE_PARTS)
	var source := GolferSkinLibrary.base_frame_image(art, "south", "idle", 0)
	var image := source.duplicate() as Image
	var layer := GolferSkinLibrary.frame_layer(art, "south", "idle", 0)
	var wanted := Color("1188ee")
	var ramp := GolferSkinLibrary.ramp(wanted)
	GolferSkinLibrary.recolour(image, skin, {"shirt": wanted}, "south", "idle", 0)
	var shirt_pixels := 0
	for y in GolferSkinLibrary.CANVAS:
		for x in GolferSkinLibrary.CANVAS:
			var index: int = layer[y * GolferSkinLibrary.CANVAS + x]
			var part := ""
			if index > 0:
				part = str(GolferSkinLibrary.decode_pixel(index)["part"])
			if part != "shirt":
				assert_eq(image.get_pixel(x, y), source.get_pixel(x, y),
					"only the top moves (the %s at %d,%d)" % [part if part else "background", x, y])
				continue
			shirt_pixels += 1
			assert_eq(image.get_pixel(x, y), ramp[(index - 1) % GolferSkinLibrary.SHADE_COUNT],
				"the top at %d,%d takes the ramp stop the layer recorded" % [x, y])
	assert_gt(shirt_pixels, 40, "the art draws a top")


## The first pixel of the first idle frame the layer tags as this part - the
## frame the layer tests look at. (-1, -1) when the art draws none of it.
func _pixel_of(skin: GolferSkinLibrary.SkinDef, part: String, shade: int = -1) -> Vector2i:
	var layer := GolferSkinLibrary.frame_layer(skin, "south", "idle", 0)
	for y in GolferSkinLibrary.CANVAS:
		for x in GolferSkinLibrary.CANVAS:
			var index: int = layer[y * GolferSkinLibrary.CANVAS + x]
			if index == 0:
				continue
			var decoded := GolferSkinLibrary.decode_pixel(index)
			if str(decoded["part"]) != part:
				continue
			if shade >= 0 and int(decoded["shade"]) != shade:
				continue
			return Vector2i(x, y)
	return Vector2i(-1, -1)


## The first pixel the layer tags with this part whose art is the flat colour
## the palette gives it - the pixel a re-colour lands on exactly.
func _flat_pixel_of(skin: GolferSkinLibrary.SkinDef, part: String) -> Vector2i:
	var wanted := GolferSkinLibrary.colour_for(GolferSkinLibrary.source_skin(skin), part)
	var image := GolferSkinLibrary.base_frame_image(skin, "south", "idle", 0)
	var layer := GolferSkinLibrary.frame_layer(skin, "south", "idle", 0)
	for y in GolferSkinLibrary.CANVAS:
		for x in GolferSkinLibrary.CANVAS:
			var index: int = layer[y * GolferSkinLibrary.CANVAS + x]
			if index == 0 or str(GolferSkinLibrary.decode_pixel(index)["part"]) != part:
				continue
			if image.get_pixel(x, y) == wanted:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## ── Editing the layer ─────────────────────────────────────────────────────

## The player can take a part out of a skin's layer: the colour pickers stop
## offering it and its pixels keep the colour they have.
func test_the_designer_can_remove_a_part_from_the_layer() -> void:
	var profile := _fresh_profile()
	var designer := await _designer()
	designer._select_by_id("casual")
	designer._set_layer_part("cap", false)
	assert_true(profile.has_custom_skin("casual"), "the edit is stored on the profile")
	var skin := GolferSkinLibrary.skin_by_id("casual")
	assert_false(skin.customizable.has("cap"), "the layer no longer holds the headwear")
	assert_false(Array(PlayerGolferProfile.parts_for_skin("casual")).has("cap"),
		"so the colour pickers do not offer it")
	var art := GolferSkinLibrary.base_frame_image(skin, "south", "idle", 0)
	var image := art.duplicate() as Image
	var changed := GolferSkinLibrary.changed_colours(skin, {"cap": Color("ff0000")})
	assert_false(changed.has("cap"), "and a colour for it changes nothing")
	GolferSkinLibrary.recolour(image, skin, changed, "south", "idle", 0)
	assert_eq(image.get_data(), art.get_data(), "the frame is untouched")


## And put one back - a part the art never drew, so a skin of the player's own
## can carry a part the base skin does not.
func test_the_designer_can_add_a_part_to_the_layer() -> void:
	var profile := _fresh_profile()
	var designer := await _designer()
	designer._select_by_id("beginner")
	assert_false(GolferSkinLibrary.skin_by_id("beginner").customizable.has("cap"),
		"the beginner art draws no headwear")
	var before := GolferSkinLibrary.frames_for(GolferSkinLibrary.skin_by_id("beginner"), {}, true) \
		.get_frame_texture("idle_south", 0).get_image().get_data()
	designer._set_layer_part("cap", true)
	var skin := GolferSkinLibrary.skin_by_id("beginner")
	assert_true(skin.customizable.has("cap"), "the layer holds it now")
	assert_true(Array(PlayerGolferProfile.parts_for_skin("beginner")).has("cap"),
		"and the colour pickers offer it")
	var after := GolferSkinLibrary.frames_for(skin, {}, true) \
		.get_frame_texture("idle_south", 0).get_image().get_data()
	assert_eq(after, before, "adding a part does not change the art: it has no pixels to change")
	assert_true(profile.has_custom_skin("beginner"), "the edit is stored")


## Painting a pixel of a part the layer does not hold puts that part in, so the
## pixels the player paints are re-colourable like any other.
func test_painting_a_part_puts_it_into_the_layer() -> void:
	var profile := _fresh_profile()
	var designer := await _designer()
	designer._select_by_id("beginner")
	designer._editor.brush_part = "cap"
	designer._editor.brush_shade = 0
	designer._editor._write(Vector2i(20, 8))
	designer._on_pixels_changed()
	var recipe: Dictionary = profile.custom_skins[0]
	assert_true(Array(recipe.get("parts", [])).has("cap"), "the painted part joins the layer")
	var skin := GolferSkinLibrary.skin_by_id("beginner")
	assert_true(skin.customizable.has("cap"))
	var image: Image = GolferSkinLibrary.frames_for(skin, {}, true) \
		.get_frame_texture("idle_south", 0).get_image()
	assert_eq(image.get_pixel(20, 8), GolferSkinLibrary.ramp(
		GolferSkinLibrary.colour_for(skin, "cap"))[0], "and the painted pixel is there")


## A recipe is a save file, so the layer's parts have to survive a round trip -
## and a recipe written before layers were editable has to keep working.
func test_the_layer_survives_a_save_and_an_older_recipe() -> void:
	var profile := _fresh_profile()
	profile.store_custom_skin({"id": "custom_5", "name": "Layered", "base": "beginner",
		"colors": {"shirt": "00ff00"}, "overlays": {}, "parts": ["shirt", "pants", "skin"], "revision": 1})
	var saved: Dictionary = JSON.parse_string(JSON.stringify(profile.serialize()))
	GameManager.player_profile = PlayerGolferProfile.from_data(saved)
	var skin := GolferSkinLibrary.skin_by_id("custom_5")
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(Array(skin.customizable), ["shirt", "pants", "skin"], "the player's layer comes back")
	# An edit written by an older build carries no list at all: it keeps the
	# layer the art shipped with.
	var art_layer := GolferSkinLibrary.layer_parts(GolferSkinLibrary.skin_by_id("casual"))
	profile.store_custom_skin({"id": "casual", "name": "Older Edit", "base": "casual",
		"colors": {"shirt": "ff00ff"}, "overlays": {}})
	GolferSkinLibrary.invalidate_catalogue()
	var edited := GolferSkinLibrary.skin_by_id("casual")
	assert_eq(Array(edited.customizable), art_layer,
		"an older recipe keeps the art's own layer")


## ── The golfer ────────────────────────────────────────────────────────────

func test_a_golfer_can_be_switched_between_skins() -> void:
	var golfer: Golfer = add_child_autofree(load("res://scenes/entities/golfer.tscn").instantiate())
	await get_tree().process_frame
	golfer.is_owner_round = true
	golfer.set_skin("beginner", {"shirt": Color("cc3366")})
	await get_tree().process_frame
	assert_true(golfer._use_sprites, "the golfer draws pixel art")
	assert_eq(golfer.skin_id, "beginner")
	var frames: SpriteFrames = golfer._animated_sprite.sprite_frames
	assert_true(frames.has_animation("swing_north-west"), "all eight facings are playable")

	var as_drawn: Image = GolferSkinLibrary.frames_for(
		GolferSkinLibrary.skin_by_id("beginner"), {}, true).get_frame_texture("idle_south", 0).get_image()
	var worn: Image = frames.get_frame_texture("idle_south", 0).get_image()
	assert_ne(worn.get_data(), as_drawn.get_data(), "the golfer wears the colours they were given")

func test_the_owner_plays_in_the_skin_they_chose() -> void:
	var golfer: Golfer = add_child_autofree(load("res://scenes/entities/golfer.tscn").instantiate())
	await get_tree().process_frame
	var profile := PlayerGolferProfile.new()
	profile.skin_id = "beginner"
	profile.set_part_color("shirt", Color("22ccff"))
	golfer.apply_player_appearance(profile)
	assert_eq(golfer.skin_id, "beginner", "the owner's profile names the skin")
	assert_true(golfer._use_sprites)
	var worn: Image = golfer._animated_sprite.sprite_frames.get_frame_texture("idle_south", 0).get_image()
	var as_drawn: Image = GolferSkinLibrary.frames_for(
		GolferSkinLibrary.skin_by_id("beginner"), {}, true).get_frame_texture("idle_south", 0).get_image()
	assert_ne(worn.get_data(), as_drawn.get_data(), "and the colours they picked for it")

## ── The profile ───────────────────────────────────────────────────────────

func test_profile_keeps_the_skin_and_the_players_own_skins() -> void:
	var profile := PlayerGolferProfile.new()
	profile.skin_id = "beginner"
	profile.set_part_color("cap", Color("123456"))
	profile.store_custom_skin({"id": "custom_1", "name": "Mine", "base": "casual",
		"colors": {"shirt": "ff0000"}, "overlays": {}})
	var loaded := PlayerGolferProfile.from_data(JSON.parse_string(JSON.stringify(profile.serialize())))
	assert_eq(loaded.skin_id, "beginner")
	assert_eq(loaded.appearance["cap_color"], "123456")
	assert_eq(loaded.custom_skins.size(), 1)
	assert_eq(loaded.custom_skins[0]["name"], "Mine")

func test_a_save_naming_an_unknown_skin_falls_back() -> void:
	var profile := PlayerGolferProfile.from_data({"skin": "not_a_skin"})
	assert_eq(profile.skin_id, GolferSkinLibrary.default_skin_id())
	assert_not_null(profile.resolved_skin())

func test_appearance_parts_match_the_skin() -> void:
	for skin in GolferSkinLibrary.builtin_skins():
		for part in PlayerGolferProfile.parts_for_skin(skin.id):
			assert_true(skin.is_customisable(part), "%s offers %s" % [skin.id, part])
	var casual_parts := PlayerGolferProfile.parts_for_skin("casual")
	assert_true(casual_parts.has("shirt"), "the Club Casual art draws a top")
	assert_true(casual_parts.has("cap"), "and headwear")
	assert_true(casual_parts.has("accent"), "and trim")
	var beginner_parts := PlayerGolferProfile.parts_for_skin("beginner")
	assert_true(beginner_parts.has("shirt"), "the Weekend Beginner art draws a top")
	assert_false(beginner_parts.has("cap"), "but no headwear")

## A save can name a skin the game no longer ships - a look that was removed,
## or one of the player's own forked from it. It must come back drawing the
## default art rather than as a golfer with no pixels.
func test_a_save_naming_a_removed_skin_still_draws() -> void:
	GameManager.player_profile = PlayerGolferProfile.from_data({"skin": "knight", "custom_skins": [
		{"id": "custom_3", "name": "Old Look", "base": "knight",
			"colors": {"shirt": "00aaff"}, "overlays": {}, "revision": 1}]})
	var profile = GameManager.player_profile
	GolferSkinLibrary.invalidate_catalogue()
	assert_eq(profile.skin_id, GolferSkinLibrary.default_skin_id(),
		"the skin the save names is not in the catalogue any more")
	assert_not_null(profile.resolved_skin(), "but the golfer still has a skin to wear")
	var skin := GolferSkinLibrary.skin_by_id("custom_3")
	assert_not_null(skin, "the skin of the player's own is still in the catalogue")
	if skin == null:
		return
	assert_false(skin.root.is_empty(), "and it knows where its art lives")
	assert_eq(GolferSkinLibrary.layer_root(skin),
		GolferSkinLibrary.layer_root(GolferSkinLibrary.skin_by_id(GolferSkinLibrary.default_skin_id())),
		"it borrows the default look's art and layer")
	var frames := GolferSkinLibrary.frames_for(skin, {}, true)
	assert_eq(frames.get_frame_count("idle_south"), 4, "so it still draws a full set of frames")


## ── The designer ──────────────────────────────────────────────────────────

## The designer edits the owner's profile, so each test starts from a clean one
## and the suite's profile is put back afterwards.
func _fresh_profile() -> PlayerGolferProfile:
	var profile := PlayerGolferProfile.new()
	GameManager.player_profile = profile
	GolferSkinLibrary.invalidate_catalogue()
	return profile


func _designer() -> GolferSkinDesigner:
	var designer: GolferSkinDesigner = add_child_autofree(GolferSkinDesigner.new())
	await get_tree().process_frame
	await get_tree().process_frame
	return designer


func test_the_designer_lists_every_skin_and_opens_on_the_owners() -> void:
	var profile := _fresh_profile()
	profile.skin_id = "beginner"
	var designer := await _designer()
	assert_not_null(designer._skins_list, "the skin list is built")
	assert_eq(designer._skins_list.item_count, GolferSkinLibrary.all_skins().size(),
		"every skin is offered")
	assert_eq(designer._selected.skin.id, "beginner", "it opens on the skin the owner wears")
	assert_not_null(designer._editor, "there is a canvas to paint on")
	assert_true(PlayerGolferProfile.parts_for_skin("beginner").size() > 0, "the parts are offered")


## Re-colouring a shipped skin stores the edit on the profile and the catalogue
## hands back a skin wearing it.
func test_the_designer_recolours_a_shipped_skin() -> void:
	var profile := _fresh_profile()
	var designer := await _designer()
	designer._select_by_id("casual")
	designer._set_part_colour("shirt", Color("1188ee"))
	assert_true(profile.has_custom_skin("casual"), "the edit is stored")
	var edited = GolferSkinLibrary.all_skins()[0]
	for skin in GolferSkinLibrary.all_skins():
		if skin.id == "casual":
			edited = skin
	assert_eq(edited.colors["shirt"], Color("1188ee"), "the catalogue wears the new colour")
	var frames := GolferSkinLibrary.frames_for(edited, {}, true)
	var image: Image = frames.get_frame_texture("idle_south", 0).get_image()
	var art := GolferSkinLibrary.base_frame_image(edited, "south", "idle", 0)
	var spot := _flat_pixel_of(edited, "shirt")
	assert_ne(spot.x, -1, "the art draws a top")
	assert_eq(image.get_pixelv(spot), Color("1188ee"), "the top is repainted")
	assert_ne(image.get_pixelv(spot), art.get_pixelv(spot), "onto the new colour, not the artist's")
	assert_true(GolferSkinLibrary.is_shipped("casual"), "it is still a shipped skin")
	assert_false(GolferSkinLibrary.custom_skins().has(edited), "an edit is not one of the player's own skins")


func test_the_designer_makes_new_skins_of_the_players_own() -> void:
	var profile := _fresh_profile()
	var designer := await _designer()
	designer._select_by_id("beginner")
	designer._on_new_skin()
	assert_eq(profile.created_skin_count(), 1, "the new skin is stored")
	var created: Array = GolferSkinLibrary.custom_skins()
	assert_eq(created.size(), 1)
	assert_eq(created[0].base_id, "beginner", "it was forked from the selected skin")
	assert_false(GolferSkinLibrary.is_shipped(created[0].id), "it is the player's own")
	assert_true(designer._selected.skin.id == created[0].id, "the designer moves onto it")
	var frames := GolferSkinLibrary.frames_for(created[0], {}, true)
	assert_eq(frames.get_frame_count("idle_south"), 4, "it comes with a full set of frames")


## Painting one pixel keeps the rest of the frame: the first stroke seeds the
## stored pixels from the layer, then paints over the one the brush touched.
func test_the_designer_paints_a_pixel_and_keeps_the_rest_of_the_frame() -> void:
	var profile := _fresh_profile()
	var designer := await _designer()
	designer._select_by_id("casual")
	var painter := GolferSkinLibrary.skin_by_id("casual")
	var brush := _pixel_of(painter, "shirt")
	assert_ne(brush.x, -1, "the art draws a top to paint over")
	var painted_at := brush.y * GolferSkinLibrary.CANVAS + brush.x
	var was: int = GolferSkinLibrary.frame_layer(painter, "south", "idle", 0)[painted_at]
	designer._editor.brush_part = "shirt"
	designer._editor.brush_shade = 4
	designer._editor._write(brush)
	designer._on_pixels_changed()
	var key := "idle_south_0"
	assert_true(designer._selected.recipe["overlays"].has(key), "the painted frame is stored")
	var recipe: Dictionary = profile.custom_skins[0]
	assert_true(recipe["overlays"].has(key))
	var bytes := GolferSkinLibrary._to_bytes(recipe["overlays"][key])
	assert_eq(bytes.size(), GolferSkinLibrary.CANVAS * GolferSkinLibrary.CANVAS,
		"the whole frame is stored, not just the one pixel")

	var stored := GolferSkinLibrary.SkinDef.from_recipe(recipe)
	var painted: Image = GolferSkinLibrary.frames_for(stored, {}, true).get_frame_texture("idle_south", 0).get_image()
	assert_eq(painted.get_pixelv(brush),
		GolferSkinLibrary.ramp(GolferSkinLibrary.colour_for(painter, "shirt"))[4],
		"the painted pixel wears the brush's shade")
	assert_eq(bytes[painted_at], GolferSkinLibrary.pixel_index("shirt", 4), "and it is the brush's byte")
	# The frame the stroke started on is the layer itself: every stored byte but
	# the painted one comes straight off it.
	var as_drawn := GolferSkinLibrary.frame_bytes(painter, "south", "idle", 0)
	var differences: Array = []
	for index in GolferSkinLibrary.CANVAS * GolferSkinLibrary.CANVAS:
		if bytes[index] != as_drawn[index]:
			differences.append(index)
	assert_eq(differences, [painted_at],
		"only the painted pixel differs from the layer the stroke started on")
	# And the layer the whole game shares is left as the artist drew it.
	assert_eq(GolferSkinLibrary.frame_layer(painter, "south", "idle", 0)[painted_at], was,
		"painting does not write into the shipped layer")
	assert_eq(painted.get_pixel(0, 0).a, 0.0, "empty space stays empty")


func test_the_pixel_editor_eyedropper_reads_the_pixel_under_the_cursor() -> void:
	var editor: SkinPixelEditor = add_child_autofree(SkinPixelEditor.new())
	await get_tree().process_frame
	var skin := GolferSkinLibrary.skin_by_id("casual")
	var palette := GolferSkinLibrary.palette_for(skin, {})
	editor.set_palette(palette)
	var image: Image = GolferSkinLibrary.base_frame_image(skin, "south", "idle", 0)
	editor.set_image(image)
	var top := _flat_pixel_of(skin, "shirt")
	assert_ne(top.x, -1, "the art draws a top")
	editor.brush_part = "gear"
	editor.brush_shade = 0
	editor._pick(top)
	assert_eq(editor.brush_part, "shirt", "the eyedropper finds the top")
	assert_eq(editor.brush_shade, 0, "and the shade the artist drew it in")
	assert_false(editor.erasing)
	editor._pick(Vector2i(0, 0))
	assert_true(editor.erasing, "picking empty space arms the eraser")


func test_the_designer_reverts_an_edited_shipped_skin() -> void:
	var profile := _fresh_profile()
	var designer := await _designer()
	designer._select_by_id("casual")
	designer._set_part_colour("shirt", Color("ff00ff"))
	assert_true(profile.has_custom_skin("casual"))
	designer._on_revert()
	assert_false(profile.has_custom_skin("casual"), "the edit is thrown away")
	var skin = GolferSkinLibrary.all_skins()[0]
	for candidate in GolferSkinLibrary.all_skins():
		if candidate.id == "casual":
			skin = candidate
	assert_false(skin.custom, "the shipped skin is back")
	var art := GolferSkinLibrary.frames_for(skin, {}, true).get_frame_texture("idle_south", 0).get_image()
	var shipped: Image = GolferSkinLibrary.frames_for(GolferSkinLibrary.skin_by_id("casual"), {}, true) \
		.get_frame_texture("idle_south", 0).get_image()
	assert_eq(art.get_data(), shipped.get_data(), "byte-for-byte the shipped art")


func test_the_designer_can_dress_the_owner_in_the_selected_skin() -> void:
	var profile := _fresh_profile()
	var designer := await _designer()
	designer._select_by_id("beginner")
	designer._on_wear()
	assert_eq(profile.skin_id, "beginner", "the owner plays in the skin they picked")


## The main-menu designer has no game to save yet, so the profile is kept in the
## user settings file as well.
func test_the_players_skins_survive_a_main_menu_visit() -> void:
	var profile := _fresh_profile()
	profile.skin_id = "casual"
	profile.store_custom_skin({"id": "custom_9", "name": "Mine", "base": "beginner",
		"colors": {"shirt": "00ff00"}, "overlays": {}})
	SaveManager.save_golfer_profile()
	GameManager.player_profile = PlayerGolferProfile.new()
	var config := ConfigFile.new()
	assert_eq(config.load(SaveManager.SETTINGS_PATH), OK)
	var stored = config.get_value("golfer", "profile", {})
	assert_true(stored is Dictionary and not stored.is_empty(), "the profile is written to the settings file")
	var restored := PlayerGolferProfile.from_data(stored)
	assert_eq(restored.skin_id, "casual")
	assert_eq(restored.custom_skins.size(), 1)


## A skin the player painted has to come back the same after a save: recipes
## keep part+shade indices, so a JSON round trip must not lose the pixels.
func test_a_painted_skin_survives_a_save_and_a_reload() -> void:
	var profile := _fresh_profile()
	profile.skin_id = "beginner"
	var recipe := {"id": "custom_1", "name": "My Own", "base": "beginner",
		"colors": {"shirt": "ff8800"}, "overlays": {}, "revision": 1}
	var pixels := PackedByteArray()
	pixels.resize(GolferSkinLibrary.CANVAS * GolferSkinLibrary.CANVAS)
	pixels[24 * 48 + 24] = GolferSkinLibrary.pixel_index("shirt", 4)
	pixels[24 * 48 + 20] = GolferSkinLibrary.pixel_index("shoes", 0)
	pixels[24 * 48 + 30] = GolferSkinLibrary.pixel_index("gear", 2)
	recipe["overlays"]["idle_south_0"] = Array(pixels)
	profile.store_custom_skin(recipe)

	var saved: Dictionary = JSON.parse_string(JSON.stringify(profile.serialize()))
	var loaded := PlayerGolferProfile.from_data(saved)
	GameManager.player_profile = loaded
	assert_eq(loaded.skin_id, "beginner")
	assert_eq(loaded.created_skin_count(), 1)

	var skin := GolferSkinLibrary.skin_by_id("custom_1")
	assert_not_null(skin, "the painted skin is in the catalogue after reloading")
	if skin == null:
		return
	assert_eq(skin.colors["shirt"], Color("ff8800"), "and keeps its colours")
	var frames := GolferSkinLibrary.frames_for(skin, {}, true)
	var image: Image = frames.get_frame_texture("idle_south", 0).get_image()
	var shirt := GolferSkinLibrary.ramp(Color("ff8800"))
	assert_eq(image.get_pixel(24, 24), shirt[4], "the painted top pixel is there")
	assert_eq(image.get_pixel(20, 24).a, 1.0, "the painted footwear pixel is there")
	assert_eq(image.get_pixel(30, 24).a, 1.0, "the painted equipment pixel is there")
	# A frame nobody painted is the base art with the skin's colours on it.
	var untouched: Image = frames.get_frame_texture("idle_south", 1).get_image()
	var art := GolferSkinLibrary.source_skin(skin)
	var expected: Image = GolferSkinLibrary.frame_texture(art, {"shirt": Color("ff8800")},
		GolferSkinLibrary.palette_for(art, {"shirt": Color("ff8800")}), "idle", "south", 1).get_image()
	assert_eq(untouched.get_data(), expected.get_data(), "frame 1 is the recoloured art, not painted")


## The owner can wear a skin they made themselves, and it survives a reload.
func test_a_save_can_name_one_of_the_players_own_skins() -> void:
	var profile := _fresh_profile()
	profile.store_custom_skin({"id": "custom_4", "name": "Mine", "base": "beginner",
		"colors": {"shirt": "00ff00"}, "overlays": {}, "revision": 1})
	profile.skin_id = "custom_4"
	var saved: Dictionary = JSON.parse_string(JSON.stringify(profile.serialize()))
	GameManager.player_profile = PlayerGolferProfile.new()
	var loaded := PlayerGolferProfile.from_data(saved)
	assert_eq(loaded.skin_id, "custom_4", "the player's own skin is still the one they wear")
	GameManager.player_profile = loaded
	assert_not_null(loaded.resolved_skin(), "and the catalogue can draw it")
	assert_eq(loaded.resolved_skin().id, "custom_4")


## Loading a game keeps the save's golfer, but not at the cost of the skins the
## player built from the title screen since they last saved.
func test_loading_a_game_does_not_throw_away_new_skins() -> void:
	var profile := _fresh_profile()
	profile.store_custom_skin({"id": "custom_7", "name": "Title Screen Skin",
		"base": "beginner", "colors": {"shirt": "123456"}, "overlays": {}, "revision": 1})
	var draft := PlayerGolferProfile.from_data({"skin": "casual", "custom_skins": []})
	draft.merge_skins_from(profile)
	assert_eq(draft.skin_id, "casual", "the save decides the look")
	assert_eq(draft.created_skin_count(), 1, "the skin built on the title screen is kept")
	assert_true(draft.has_custom_skin("custom_7"))
	# And it does not duplicate a skin the save already has.
	draft.merge_skins_from(profile)
	assert_eq(draft.created_skin_count(), 1)
