extends GutTest
## Unit tests for the Golfer Skin catalogue, its colour pipeline and the owner's
## profile entries that keep their skins across saves.

const SKIN_DIR := "res://assets/sprites/golfer/skins/"

func _themed_ids() -> Array:
	var ids: Array = []
	for skin in GolferSkinLibrary.builtin_skins():
		if not skin.legacy:
			ids.append(skin.id)
	return ids

## The whole point of the feature: a lot more skins than the four tier looks,
## every one of them with a full set of animation frames on disk.
func test_there_are_at_least_eight_themed_skins_with_full_animation_sets() -> void:
	var ids := _themed_ids()
	assert_gte(ids.size(), 8, "at least eight themed Golfer Skins ship with the game")

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

## Skins are re-coloured, not redrawn: the player's colour must land on the part
## they picked and leave everything else - the shading, the eyes - alone.
func test_colour_overrides_repaint_one_part_and_keep_its_shading() -> void:
	var skin := GolferSkinLibrary.skin_by_id("plain")
	assert_not_null(skin)
	var plain := GolferSkinLibrary.frames_for(skin, {})
	var painted := GolferSkinLibrary.frames_for(skin, {"shirt": Color("e01020")})
	var plain_image: Image = plain.get_frame_texture("idle_south", 0).get_image()
	var painted_image: Image = painted.get_frame_texture("idle_south", 0).get_image()

	var shirt_ramp := GolferSkinLibrary.ramp(Color("4a86c8"))
	var shirt_pixels := 0
	var changed := 0
	var shades := {}
	for y in 48:
		for x in 48:
			var before := plain_image.get_pixel(x, y)
			var after := painted_image.get_pixel(x, y)
			if before.a <= 0.01:
				continue
			var was_shirt := false
			for shade in shirt_ramp:
				if before.is_equal_approx(shade):
					was_shirt = true
					break
			if was_shirt and before != after:
				shirt_pixels += 1
				shades[after.to_html(false)] = true
			if before != after:
				changed += 1
	assert_gt(shirt_pixels, 60, "the shirt covers a good part of the sprite")
	assert_eq(changed, shirt_pixels, "only the shirt pixels were repainted")
	assert_gte(shades.size(), 2, "the shirt keeps more than one shade")
	var eye_before := plain_image.get_pixel(20, 13)
	var eye_after := painted_image.get_pixel(20, 13)
	assert_eq(eye_before, eye_after, "facial details are untouched")

func test_the_artists_palette_is_kept_when_nothing_is_overridden() -> void:
	var skin := GolferSkinLibrary.skin_by_id("wizard")
	var frames := GolferSkinLibrary.frames_for(skin, {})
	var image: Image = frames.get_frame_texture("idle_south", 0).get_image()
	var source: Image = GolferSkinLibrary.base_frame_image(skin, "south", "idle", 0)
	assert_eq(image.get_data(), source.get_data(), "an untouched skin is the shipped art")

## A skin the player built: its edited frames come from its own pixels, the
## frames they did not touch keep the art it was forked from.
func test_a_custom_skin_paints_over_the_base_art() -> void:
	var base := GolferSkinLibrary.skin_by_id("caddy" if GolferSkinLibrary.skin_by_id("caddy") != null else "caddie")
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
	var base_frames := GolferSkinLibrary.frames_for(base, {})
	var base_first: Image = base_frames.get_frame_texture("idle_south", 0).get_image()
	var base_second: Image = base_frames.get_frame_texture("idle_south", 1).get_image()

	assert_eq(painted.get_pixel(0, 0).a, 1.0, "the painted frame uses the skin's own pixels")
	assert_eq(untouched.get_data(), base_second.get_data(), "unpainted frames still use the base art")
	assert_ne(painted.get_data(), base_first.get_data(), "the painted frame is not the base frame any more")

## Stored pixels are part + shade indices, so colours can change after painting.
func test_painted_pixels_follow_a_colour_change() -> void:
	var base := GolferSkinLibrary.skin_by_id("plain")
	var recipe := GolferSkinLibrary.new_custom_skin(base, "Repaint")
	var overlay := PackedByteArray()
	overlay.resize(GolferSkinLibrary.CANVAS * GolferSkinLibrary.CANVAS)
	overlay[10] = GolferSkinLibrary.pixel_index("shirt", 0)
	recipe.overlays[recipe.frame_key("idle", "south", 0)] = overlay

	var first: Image = GolferSkinLibrary.frames_for(recipe, {}, true).get_frame_texture("idle_south", 0).get_image()
	recipe.colors["shirt"] = Color("00cc44")
	recipe.revision += 1
	var second: Image = GolferSkinLibrary.frames_for(recipe, {}, true).get_frame_texture("idle_south", 0).get_image()
	assert_eq(first.get_pixel(10, 0), Color("4a86c8"), "the painted pixel starts on the skin's shirt colour")
	assert_eq(second.get_pixel(10, 0), Color("00cc44"), "changing the shirt colour repaints it")

func test_encode_and_decode_round_trip_a_frame() -> void:
	var skin := GolferSkinLibrary.skin_by_id("ninja")
	var image: Image = GolferSkinLibrary.frames_for(skin, {}).get_frame_texture("walk_east", 2).get_image()
	var bytes := GolferSkinLibrary.encode_image(image, skin)
	assert_eq(bytes.size(), GolferSkinLibrary.CANVAS * GolferSkinLibrary.CANVAS)
	var rebuilt := GolferSkinLibrary.image_from_overlay(skin, {}, GolferSkinLibrary.storage_palette(skin),
		"walk", "east", 2) if skin.overlays.has(skin.frame_key("walk", "east", 2)) else null
	# No overlay stored yet: encode first, then decode from it.
	skin.overlays[skin.frame_key("walk", "east", 2)] = bytes
	rebuilt = GolferSkinLibrary.image_from_overlay(skin, {}, GolferSkinLibrary.storage_palette(skin),
		"walk", "east", 2)
	var rebuilt_bytes := GolferSkinLibrary.encode_image(rebuilt, skin)
	assert_eq(rebuilt_bytes, bytes, "a frame survives the round trip through the editor's format")
	var decoded := GolferSkinLibrary.decode_pixel(bytes[20 * 48 + 24])
	assert_true(decoded.has("part"), "pixels decode back to a part")

func test_random_skin_for_a_tier_only_offers_that_tiers_skins() -> void:
	for tier in [GolferTier.Tier.BEGINNER, GolferTier.Tier.CASUAL, GolferTier.Tier.SERIOUS, GolferTier.Tier.PRO]:
		var options := GolferSkinLibrary.skins_for_tier(tier)
		assert_gt(options.size(), 0, "tier %d has skins to wear" % tier)
		for skin in options:
			assert_true(skin.spawn_tiers.has(GolferSkinLibrary.tier_key(tier)),
				"%s may be worn by tier %d" % [skin.id, tier])
		assert_eq(options[0].id, GolferSkinLibrary.tier_skin_id(tier),
			"the tier's own art is the common look")

## ── The golfer ────────────────────────────────────────────────────────────

func test_a_golfer_can_be_switched_between_skins() -> void:
	var golfer: Golfer = add_child_autofree(load("res://scenes/entities/golfer.tscn").instantiate())
	await get_tree().process_frame
	golfer.is_owner_round = true
	golfer.set_skin("knight", {"shirt": Color("cc3366")})
	await get_tree().process_frame
	assert_true(golfer._use_sprites, "the golfer draws pixel art")
	assert_eq(golfer.skin_id, "knight")
	var frames: SpriteFrames = golfer._animated_sprite.sprite_frames
	assert_true(frames.has_animation("swing_north-west"), "all eight facings are playable")

	var knight: Image = GolferSkinLibrary.frames_for(GolferSkinLibrary.skin_by_id("knight"), {}).get_frame_texture("idle_south", 0).get_image()
	var worn: Image = frames.get_frame_texture("idle_south", 0).get_image()
	assert_ne(worn.get_data(), knight.get_data(), "the golfer wears the colours they were given")

func test_the_owner_plays_in_the_skin_they_chose() -> void:
	var golfer: Golfer = add_child_autofree(load("res://scenes/entities/golfer.tscn").instantiate())
	await get_tree().process_frame
	var profile := PlayerGolferProfile.new()
	profile.skin_id = "astronaut"
	profile.set_part_color("shirt", Color("22ccff"))
	golfer.apply_player_appearance(profile)
	assert_eq(golfer.skin_id, "astronaut", "the owner's profile names the skin")
	assert_true(golfer._use_sprites)
	var worn: Image = golfer._animated_sprite.sprite_frames.get_frame_texture("idle_south", 0).get_image()
	var plain: Image = GolferSkinLibrary.frames_for(GolferSkinLibrary.skin_by_id("astronaut"), {}).get_frame_texture("idle_south", 0).get_image()
	assert_ne(worn.get_data(), plain.get_data(), "and the colours they picked for it")

## ── The profile ───────────────────────────────────────────────────────────

func test_profile_keeps_the_skin_and_the_players_own_skins() -> void:
	var profile := PlayerGolferProfile.new()
	profile.skin_id = "pirate"
	profile.set_part_color("cap", Color("123456"))
	profile.store_custom_skin({"id": "custom_1", "name": "Mine", "base": "plain",
		"colors": {"shirt": "ff0000"}, "overlays": {}})
	var loaded := PlayerGolferProfile.from_data(JSON.parse_string(JSON.stringify(profile.serialize())))
	assert_eq(loaded.skin_id, "pirate")
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
	var pirate_parts := PlayerGolferProfile.parts_for_skin("pirate")
	assert_true(pirate_parts.has("shirt"))
	assert_true(pirate_parts.has("cap"))
	assert_true(pirate_parts.has("accent"))

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
	profile.skin_id = "wizard"
	var designer := await _designer()
	assert_not_null(designer._skins_list, "the skin list is built")
	assert_eq(designer._skins_list.item_count, GolferSkinLibrary.all_skins().size(),
		"every skin is offered")
	assert_eq(designer._selected.skin.id, "wizard", "it opens on the skin the owner wears")
	assert_not_null(designer._editor, "there is a canvas to paint on")
	assert_true(PlayerGolferProfile.parts_for_skin("wizard").size() > 0, "the parts are offered")


## Re-colouring a shipped skin stores the edit on the profile and the catalogue
## hands back a skin wearing it.
func test_the_designer_recolours_a_shipped_skin() -> void:
	var profile := _fresh_profile()
	var designer := await _designer()
	designer._select_by_id("plain")
	designer._set_part_colour("shirt", Color("1188ee"))
	assert_true(profile.has_custom_skin("plain"), "the edit is stored")
	var edited = GolferSkinLibrary.all_skins()[0]
	for skin in GolferSkinLibrary.all_skins():
		if skin.id == "plain":
			edited = skin
	assert_eq(edited.colors["shirt"], Color("1188ee"), "the catalogue wears the new colour")
	var frames := GolferSkinLibrary.frames_for(edited, {}, true)
	var image: Image = frames.get_frame_texture("idle_south", 0).get_image()
	assert_eq(image.get_pixel(24, 21), Color("1188ee"), "the top is repainted")
	assert_true(GolferSkinLibrary.is_shipped("plain"), "it is still a shipped skin")
	assert_false(GolferSkinLibrary.custom_skins().has(edited), "an edit is not one of the player's own skins")


func test_the_designer_makes_new_skins_of_the_players_own() -> void:
	var profile := _fresh_profile()
	var designer := await _designer()
	designer._select_by_id("knight")
	designer._on_new_skin()
	assert_eq(profile.created_skin_count(), 1, "the new skin is stored")
	var created: Array = GolferSkinLibrary.custom_skins()
	assert_eq(created.size(), 1)
	assert_eq(created[0].base_id, "knight", "it was forked from the selected skin")
	assert_false(GolferSkinLibrary.is_shipped(created[0].id), "it is the player's own")
	assert_true(designer._selected.skin.id == created[0].id, "the designer moves onto it")
	var frames := GolferSkinLibrary.frames_for(created[0], {}, true)
	assert_eq(frames.get_frame_count("idle_south"), 4, "it comes with a full set of frames")


## Painting one pixel keeps the rest of the frame: the first stroke seeds the
## stored pixels from the art, then paints over the one the brush touched.
func test_the_designer_paints_a_pixel_and_keeps_the_rest_of_the_frame() -> void:
	var profile := _fresh_profile()
	var designer := await _designer()
	designer._select_by_id("plain")
	designer._editor.brush_part = "shirt"
	designer._editor.brush_shade = 4
	designer._editor._write(Vector2i(24, 21))
	designer._on_pixels_changed()
	var key := "idle_south_0"
	assert_true(designer._selected.recipe["overlays"].has(key), "the painted frame is stored")
	var recipe: Dictionary = profile.custom_skins[0]
	assert_true(recipe["overlays"].has(key))
	var bytes := GolferSkinLibrary._to_bytes(recipe["overlays"][key])
	assert_eq(bytes.size(), GolferSkinLibrary.CANVAS * GolferSkinLibrary.CANVAS,
		"the whole frame is stored, not just the one pixel")

	var shown := GolferSkinLibrary.skin_by_id("plain")
	var stored := GolferSkinLibrary.SkinDef.from_recipe(recipe)
	var painted: Image = GolferSkinLibrary.frames_for(stored, {}, true).get_frame_texture("idle_south", 0).get_image()
	# The frame the player started from: the shipped art, not the edited skin
	# the catalogue now hands back.
	var shipped: Image = GolferSkinLibrary.base_frame_image(
		GolferSkinLibrary.source_skin(shown), "south", "idle", 0)
	assert_eq(painted.get_pixel(24, 21), GolferSkinLibrary.ramp(Color("4a86c8"))[4],
		"the painted pixel wears the brush's shade")
	assert_ne(painted.get_pixel(24, 21), shipped.get_pixel(24, 21), "which is not the shade the artist used")
	assert_eq(painted.get_pixel(24, 15), shipped.get_pixel(24, 15), "the head is untouched")
	assert_eq(painted.get_pixel(20, 11), shipped.get_pixel(20, 11), "the headwear is untouched")
	assert_eq(painted.get_pixel(0, 0).a, 0.0, "empty space stays empty")


func test_the_pixel_editor_eyedropper_reads_the_pixel_under_the_cursor() -> void:
	var editor: SkinPixelEditor = add_child_autofree(SkinPixelEditor.new())
	await get_tree().process_frame
	var skin := GolferSkinLibrary.skin_by_id("plain")
	var palette := GolferSkinLibrary.palette_for(skin, {})
	editor.set_palette(palette)
	var image: Image = GolferSkinLibrary.base_frame_image(skin, "south", "idle", 0)
	editor.set_image(image)
	editor.brush_part = "gear"
	editor.brush_shade = 0
	editor._pick(Vector2i(24, 21))
	assert_eq(editor.brush_part, "shirt", "the eyedropper finds the top")
	assert_true(editor.brush_shade >= 0 and editor.brush_shade < GolferSkinLibrary.SHADE_COUNT)
	assert_false(editor.erasing)
	editor._pick(Vector2i(0, 0))
	assert_true(editor.erasing, "picking empty space arms the eraser")


func test_the_designer_reverts_an_edited_shipped_skin() -> void:
	var profile := _fresh_profile()
	var designer := await _designer()
	designer._select_by_id("pirate")
	designer._set_part_colour("shirt", Color("ff00ff"))
	assert_true(profile.has_custom_skin("pirate"))
	designer._on_revert()
	assert_false(profile.has_custom_skin("pirate"), "the edit is thrown away")
	var skin = GolferSkinLibrary.all_skins()[0]
	for candidate in GolferSkinLibrary.all_skins():
		if candidate.id == "pirate":
			skin = candidate
	assert_false(skin.custom, "the shipped skin is back")
	var art := GolferSkinLibrary.frames_for(skin, {}, true).get_frame_texture("idle_south", 0).get_image()
	var shipped: Image = GolferSkinLibrary.frames_for(GolferSkinLibrary.skin_by_id("pirate"), {}, true) \
		.get_frame_texture("idle_south", 0).get_image()
	assert_eq(art.get_data(), shipped.get_data(), "byte-for-byte the shipped art")


func test_the_designer_can_dress_the_owner_in_the_selected_skin() -> void:
	var profile := _fresh_profile()
	var designer := await _designer()
	designer._select_by_id("chef")
	designer._on_wear()
	assert_eq(profile.skin_id, "chef", "the owner plays in the skin they picked")


## The main-menu designer has no game to save yet, so the profile is kept in the
## user settings file as well.
func test_the_players_skins_survive_a_main_menu_visit() -> void:
	var profile := _fresh_profile()
	profile.skin_id = "ninja"
	profile.store_custom_skin({"id": "custom_9", "name": "Mine", "base": "plain",
		"colors": {"shirt": "00ff00"}, "overlays": {}})
	SaveManager.save_golfer_profile()
	GameManager.player_profile = PlayerGolferProfile.new()
	var config := ConfigFile.new()
	assert_eq(config.load(SaveManager.SETTINGS_PATH), OK)
	var stored = config.get_value("golfer", "profile", {})
	assert_true(stored is Dictionary and not stored.is_empty(), "the profile is written to the settings file")
	var restored := PlayerGolferProfile.from_data(stored)
	assert_eq(restored.skin_id, "ninja")
	assert_eq(restored.custom_skins.size(), 1)


## A skin the player painted has to come back the same after a save: recipes
## keep part+shade indices, so a JSON round trip must not lose the pixels.
func test_a_painted_skin_survives_a_save_and_a_reload() -> void:
	var profile := _fresh_profile()
	profile.skin_id = "cowboy"
	var recipe := {"id": "custom_1", "name": "My Own", "base": "cowboy",
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
	assert_eq(loaded.skin_id, "cowboy")
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
	profile.store_custom_skin({"id": "custom_4", "name": "Mine", "base": "ninja",
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
		"base": "chef", "colors": {"shirt": "123456"}, "overlays": {}, "revision": 1})
	var draft := PlayerGolferProfile.from_data({"skin": "plain", "custom_skins": []})
	draft.merge_skins_from(profile)
	assert_eq(draft.skin_id, "plain", "the save decides the look")
	assert_eq(draft.created_skin_count(), 1, "the skin built on the title screen is kept")
	assert_true(draft.has_custom_skin("custom_7"))
	# And it does not duplicate a skin the save already has.
	draft.merge_skins_from(profile)
	assert_eq(draft.created_skin_count(), 1)
