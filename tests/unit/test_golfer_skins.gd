extends GutTest
## Unit tests for Golfer Skins: the Re-color Layer grid, the Re-color Groups a
## skin carries, the text files they are stored as, and the frames golfers are
## drawn with once a layer has been painted.
##
## The library is pointed at a test folder under user:// (as the skin studio's
## is pointed at user://golfer_skins) so nothing here touches the player's own
## skins, and the skins that ship with the game are read from the real
## data/golfer_skins folder.

const BUILT_IN_ROOT := "res://data/golfer_skins"
const TEST_ROOT := "user://test_golfer_skins"


func before_each() -> void:
	_remove_tree(TEST_ROOT)


func after_each() -> void:
	_remove_tree(TEST_ROOT)


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			_remove_tree(path.path_join(entry))
		else:
			DirAccess.remove_absolute(path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


## A library reading the shipped skins plus the test folder.
func _library() -> GolferSkinLibrary:
	return GolferSkinLibrary.new(BUILT_IN_ROOT, TEST_ROOT)


## An image with a bright and a dark pixel of the same group, and one pixel
## outside it.
func _image() -> Image:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.set_pixel(0, 0, Color(1.0, 0.5, 0.25))     # brightest - the reference
	image.set_pixel(1, 0, Color(0.5, 0.25, 0.125))   # half brightness
	image.set_pixel(0, 1, Color(0, 0, 1))            # left out of every group
	return image


# =============================================================================
# RE-COLOR LAYERS
# =============================================================================

func test_layer_grid_holds_a_group_per_pixel() -> void:
	var layer := GolferSkinLayer.create(4, 3)
	assert_eq(layer.width, 4)
	assert_eq(layer.height, 3)
	assert_eq(layer.cells.size(), 12)
	assert_true(layer.is_empty(), "A fresh layer names no groups")
	assert_true(layer.set_cell(2, 1, 7))
	assert_eq(layer.get_cell(2, 1), 7)
	assert_eq(layer.get_cell(1, 1), GolferSkinLayer.NO_GROUP)
	assert_false(layer.set_cell(9, 9, 7), "Off the grid there is no cell to set")
	assert_eq(layer.get_cell(-1, 0), GolferSkinLayer.NO_GROUP)
	assert_eq(layer.count(7), 1)
	assert_eq(layer.used_group_ids(), [7])
	assert_false(layer.is_empty())

	assert_eq(layer.clear_group(7), 1, "Deleting a group frees its cells")
	assert_true(layer.is_empty())
	assert_eq(layer.clear_group(GolferSkinLayer.NO_GROUP), 0)

	layer.set_cell(0, 0, 3)
	layer.set_cell(1, 1, 3)
	assert_eq(layer.remap_group(3, 5), 2)
	assert_eq(layer.count(5), 2)
	assert_eq(layer.used_group_ids(), [5])


func test_layer_resize_keeps_the_cells_that_still_fit() -> void:
	var layer := GolferSkinLayer.create(3, 3)
	layer.set_cell(0, 0, 1)
	layer.set_cell(2, 2, 2)
	layer.resize(2, 2)
	assert_eq(layer.get_cell(0, 0), 1, "A cell inside the new grid is kept")
	assert_eq(layer.get_cell(2, 2), GolferSkinLayer.NO_GROUP, "A cell outside it is gone")
	assert_eq(layer.cells.size(), 4)


func test_flood_fill_stops_at_the_edge_of_the_group_and_at_transparency() -> void:
	var layer := GolferSkinLayer.create(3, 3)
	for y in 3:
		for x in 3:
			layer.set_cell(x, y, 1)
	layer.set_cell(2, 2, 2)
	var filled := layer.flood_cells(0, 0)
	assert_eq(filled.size(), 8, "The fill covers the group's run and nothing else")

	# Transparency is a wall: a fill started on the sprite cannot swallow the
	# transparent background around it, nor cross it to another solid run.
	var image := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.set_pixel(0, 0, Color.WHITE)
	image.set_pixel(1, 0, Color.WHITE)
	image.set_pixel(1, 1, Color.WHITE)
	layer.set_cell(2, 2, 1)
	assert_eq(layer.count(1), 9, "Every cell of the grid belongs to the group")
	assert_eq(layer.flood_cells(1, 1, image).size(), 3, "Only the connected solid pixels are filled")
	assert_true(layer.flood_cells(1, 1, image).has(Vector2i(0, 0)))
	assert_false(layer.flood_cells(1, 1, image).has(Vector2i(2, 2)),
		"The run beyond the transparency is not reached")


func test_layer_survives_a_round_trip_through_its_text_file() -> void:
	var layer := GolferSkinLayer.create(4, 2)
	layer.set_cell(0, 0, 1)
	layer.set_cell(3, 1, 2)
	var symbols := {1: "A", 2: "B"}
	var legend := {1: "Shirt", 2: "Pants"}
	var text := layer.serialize(symbols, legend)
	assert_true(text.contains("golfer-skin-layer %d" % GolferSkinLayer.FORMAT_VERSION),
		"The file names its format and version")
	assert_true(text.contains("size 4 2"), "The grid is written down")
	assert_true(text.contains("cells"), "and says where the pixels start")
	assert_true(text.contains("# legend: A = Shirt, B = Pants"), "Groups are named for the reader")
	assert_true(text.contains("A..."), "The cells are one character per pixel")
	assert_true(text.contains("...B"))

	var reloaded := GolferSkinLayer.parse(text, {"A": 1, "B": 2})
	assert_eq(reloaded.width, 4)
	assert_eq(reloaded.height, 2)
	assert_true(reloaded.equals(layer), "The grid comes back exactly as it was written")
	assert_eq(reloaded.warnings.size(), 0)
	assert_false(reloaded.has_art(), "A layer without painted pixels leaves the artwork alone")

	# Renaming a group never rewrites a grid: the symbols are unchanged.
	assert_eq(reloaded.serialize(symbols, {1: "Sleeves", 2: "Pants"}).contains("A = Sleeves"), true)


## A layer that has been painted carries the sprite's own pixels, in the same
## editable text file as the group grid.
func test_painted_pixels_survive_the_round_trip_through_the_layer_file() -> void:
	var layer := GolferSkinLayer.create(3, 2)
	layer.set_cell(1, 0, 1)
	var art := Image.create(3, 2, false, Image.FORMAT_RGBA8)
	art.fill(Color(0, 0, 0, 0))
	art.set_pixel(0, 0, Color("ff3366"))
	art.set_pixel(1, 0, Color(0.9, 0.9, 0.9))
	art.set_pixel(2, 1, Color("123456"))
	layer.begin_art(art)
	assert_true(layer.has_art(), "Taking the artwork in is what painting does first")
	assert_eq(layer.art_pixel(0, 0), Color("ff3366"))
	assert_eq(layer.art_pixel(1, 1).a, 0.0, "and the pixels the art leaves empty stay empty")

	var text := layer.serialize({1: "A"})
	assert_true(text.contains("art"), "The file says where the painted pixels start")
	assert_true(text.contains("ff3366"), "and writes them as hex")
	assert_true(text.contains("------"), "with a token for a transparent pixel")
	var reloaded := GolferSkinLayer.parse(text, {"A": 1})
	assert_eq(reloaded.warnings.size(), 0, str(reloaded.warnings))
	assert_true(reloaded.equals(layer), "The painted sprite comes back exactly as it was written")
	assert_eq(reloaded.art_pixel(2, 1), Color("123456"))

	# The painted pixels are what the golfer is drawn with: the re-color starts
	# from them, not from the art that ships with the game.
	var shipped := Image.create(3, 2, false, Image.FORMAT_RGBA8)
	shipped.fill(Color(0.9, 0.9, 0.9))
	var recoloured := reloaded.recolor(shipped, {1: Color("00ff00")}, {1: 0.9})
	assert_eq(recoloured.get_pixel(0, 0), Color("ff3366"),
		"A painted pixel outside every group keeps the colour it was painted")
	assert_eq(recoloured.get_pixel(2, 1), Color("123456"))
	assert_gt(recoloured.get_pixel(1, 0).g, recoloured.get_pixel(1, 0).r,
		"and a grouped pixel is re-coloured as ever")


## The brush covers a disc of pixels, so a round brush stays round on the sprite.
func test_the_brush_covers_a_disc_of_pixels() -> void:
	var layer := GolferSkinLayer.create(9, 9)
	assert_eq(layer.brush_cells(4, 4, 1), [Vector2i(4, 4)] as Array[Vector2i],
		"A one-pixel brush is the pixel itself")
	assert_eq(layer.brush_cells(4, 4, 2).size(), 4, "a two-wide brush covers four pixels")
	var wide := layer.brush_cells(4, 4, 5)
	assert_gt(wide.size(), 13, "a five-wide brush covers more than the cross")
	for cell in wide:
		assert_lt(absf(Vector2(cell - Vector2i(4, 4)).length()), 2.5, "%s is inside the disc" % cell)
	# A brush at the edge of the grid reports only the pixels that exist.
	var corner := layer.brush_cells(0, 0, 5)
	assert_lt(corner.size(), wide.size(), "a corner brush is clipped to the sprite: %s" % str(corner))
	for cell in corner:
		assert_true(layer.contains(cell.x, cell.y), "%s is on the grid" % cell)
	assert_eq(GolferSkinLayer.create(2, 2).brush_cells(-1, 0, 3), [] as Array[Vector2i],
		"and a click off the grid paints nothing")


func test_layer_file_reports_what_it_cannot_read_instead_of_failing() -> void:
	var text := "\n".join([
		"# a hand-written layer",
		"golfer-skin-layer 1",
		"size 3 3",
		"cells",
		"A.Z",
		"A?.",
	])
	var layer := GolferSkinLayer.parse(text, {"A": 1})
	assert_eq(layer.width, 3)
	assert_eq(layer.get_cell(0, 0), 1)
	assert_eq(layer.get_cell(2, 0), GolferSkinLayer.NO_GROUP, "An unknown character leaves the pixel ungrouped")
	assert_eq(layer.warnings.size(), 3,
		"Both unknown characters and the missing row are reported: %s" % str(layer.warnings))
	assert_eq(layer.warnings[1], "Unknown group character 'Z'")

	var not_a_layer := GolferSkinLayer.parse("hello", {})
	assert_true(not_a_layer.warnings.size() > 0, "A file with no cells says so")
	assert_true(not_a_layer.is_empty())


func test_layer_recolors_with_the_artworks_own_shading() -> void:
	var layer := GolferSkinLayer.create(2, 2)
	for cell in [Vector2i(0, 0), Vector2i(1, 0)]:
		layer.set_cell(cell.x, cell.y, 1)
	var image := _image()
	var shade := layer.source_maxima(image)
	assert_almost_eq(float(shade[1]), 1.0, 0.001, "The brightest pixel of the group is its reference")

	var recolored := layer.recolor(image, {1: Color(0.2, 0.4, 0.8)}, shade)
	assert_almost_eq(recolored.get_pixel(0, 0).r, 0.2, 0.01, "The brightest pixel lands on the chosen colour")
	assert_almost_eq(recolored.get_pixel(0, 1).b, 1.0, 0.01, "A pixel outside every group is left alone")
	var half := recolored.get_pixel(1, 0)
	assert_almost_eq(half.r, 0.1, 0.01, "The darker pixel keeps the artwork's shading")
	assert_almost_eq(half.b, 0.4, 0.01)
	assert_almost_eq(half.a, 1.0, 0.01, "Transparency is never invented")
	# A transparent pixel stays transparent.
	var blank := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	blank.set_pixel(0, 0, Color(0, 0, 0, 0))
	var one := GolferSkinLayer.create(1, 1)
	one.set_cell(0, 0, 1)
	assert_almost_eq(one.recolor(blank, {1: Color.RED}, {1: 1.0}).get_pixel(0, 0).a, 0.0, 0.001)

	# A group with no colour is left as it is, and so is a layer with no groups.
	assert_eq(layer.recolor(image, {}).get_pixel(0, 0), image.get_pixel(0, 0))
	assert_eq(GolferSkinLayer.create(2, 2).recolor(image, {1: Color.RED}), image)


# =============================================================================
# RE-COLOR GROUPS
# =============================================================================

func test_groups_can_be_created_renamed_and_deleted() -> void:
	var skin := GolferSkin.new()
	skin.id = "test"
	skin.display_name = "Test"
	var shirt := skin.create_group("Shirt")
	var pants := skin.create_group("Shirt")
	assert_eq(skin.group_count(), 2)
	assert_eq(str(skin.group_by_id(shirt).get("name")), "Shirt")
	assert_eq(str(skin.group_by_id(pants).get("name")), "Shirt 2", "A group name is made unique")
	assert_eq(str(skin.group_by_id(shirt).get("symbol")), "A", "Groups are painted with their own characters")
	assert_eq(str(skin.group_by_id(pants).get("symbol")), "B")

	assert_false(skin.rename_group(shirt, "Shirt 2"), "A rename onto a taken name is refused")
	assert_false(skin.rename_group(shirt, "  "), "and so is an empty one")
	assert_true(skin.rename_group(shirt, "Sleeves"))
	assert_eq(str(skin.group_by_id(shirt).get("name")), "Sleeves")
	assert_eq(str(skin.group_by_id(shirt).get("symbol")), "A", "Renaming does not re-symbol the group")

	assert_true(skin.set_group_color(shirt, Color("00ff00")))
	assert_true(skin.set_group_shade(shirt, 0.5))
	assert_eq(skin.group_shade(shirt), 0.5)


func test_a_new_group_never_inherits_a_deleted_groups_pixels() -> void:
	var skin := _test_skin()
	var layer := skin.layer(GolferSkin.layer_key("idle", "south", 0))
	var shirt := int(skin.group_by_name("Shirt").get("id"))
	var painted := layer.count(shirt)
	assert_gt(painted, 0, "The shipped Shirt group owns pixels to begin with")

	assert_true(skin.delete_group(shirt))
	assert_true(skin.group_by_id(shirt).is_empty())
	assert_eq(layer.count(shirt), 0, "Every pixel of the group is freed")
	assert_eq(layer.get_cell(1, 1), GolferSkinLayer.NO_GROUP)

	var replacement := skin.create_group("Jacket")
	assert_ne(replacement, shirt, "The new group gets an id of its own")
	assert_eq(layer.count(replacement), 0, "...so it starts with no pixels at all")


func test_deleting_a_group_reaches_layers_that_were_never_loaded() -> void:
	var written := _test_skin()
	assert_true(written.save_to(TEST_ROOT.path_join("later")))
	var library := _library()
	var skin := library.get_skin("casual")
	var shirt := int(skin.group_by_name("Shirt").get("id"))
	assert_eq(skin.loaded_layer_keys().size(), 0, "Nothing has been read off the disk yet")
	var key := GolferSkin.layer_key("walk", "north", 1)
	assert_true(skin.has_layer(key), "but the skin does have that layer on disk")
	skin.delete_group(shirt)
	assert_eq(skin.layer(key).count(shirt), 0, "A layer read after the delete still drops the group")


# =============================================================================
# THE SKIN'S TEXT FILES
# =============================================================================

func test_manifest_round_trip() -> void:
	var skin := GolferSkin.new()
	skin.id = "casual"
	skin.display_name = "Test Skin"
	skin.sprite_id = "casual"
	skin.sprite_size = Vector2i(48, 48)
	var shirt := skin.create_group("Shirt")
	skin.set_group_color(shirt, Color("123456"))
	skin.set_group_shade(shirt, 0.42)
	skin.set_wears_tier(GolferTier.Tier.PRO, true)
	var text := skin.serialize_manifest()
	assert_true(text.contains("golfer-skin 1"))
	assert_true(text.contains("id casual"))
	assert_true(text.contains("group 1 A 123456 0.420 Shirt"))

	var reloaded := GolferSkin.parse_manifest(text, "casual")
	assert_eq(reloaded.display_name, "Test Skin")
	assert_eq(reloaded.sprite_id, "casual")
	assert_eq(reloaded.sprite_size, Vector2i(48, 48))
	assert_eq(reloaded.worn_by, [GolferTier.Tier.PRO])
	assert_eq(reloaded.group_count(), 1)
	assert_eq(str(reloaded.group_by_name("Shirt").get("symbol")), "A")
	assert_eq(reloaded.group_by_id(1).get("color"), Color("123456"))
	assert_almost_eq(float(reloaded.group_by_id(1).get("shade")), 0.42, 0.0001)


func test_manifest_reports_a_newer_version_and_ignores_what_it_cannot_read() -> void:
	var skin := GolferSkin.parse_manifest("golfer-skin 99\nnonsense here\nid future\nname Future", "future")
	assert_eq(skin.id, "future")
	assert_eq(skin.display_name, "Future")
	assert_eq(skin.warnings.size(), 2, "Both the version and the unknown line are reported: %s" % str(skin.warnings))
	assert_true(str(skin.warnings[0]).contains("99"))


func test_a_skins_folder_is_a_complete_set_of_editable_text_files() -> void:
	var skin := _test_skin()
	var key := GolferSkin.layer_key("idle", "south", 0)
	skin.layer(key).set_cell(4, 4, int(skin.group_by_name("Shirt").get("id")))
	var folder := TEST_ROOT.path_join("written")
	assert_true(skin.save_to(folder), "The skin writes itself out")
	assert_true(FileAccess.file_exists(folder.path_join(GolferSkin.MANIFEST_FILE)))
	var layer_path := GolferSkin.layer_path(folder, key)
	assert_true(FileAccess.file_exists(layer_path), "Every layer is a file of its own")
	assert_true(FileAccess.get_file_as_string(layer_path).contains("A..."),
		"with the painted pixel in it: %s" % layer_path)
	# The whole skin, and not just the one layer, is written.
	assert_eq(_count_files(folder), 1 + skin.sprite_keys().size())


func _count_files(path: String) -> int:
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	var total := 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			total += _count_files(path.path_join(entry))
		else:
			total += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return total


# =============================================================================
# THE PLAYER'S OWN GOLFER
# =============================================================================

## A group called Shirt, Pants, Cap, Hair or Skin is the one the player's own
## appearance has a field for; the Edit Player page writes a colour picked for
## one of them back to the profile (see PlayerRoundManager).
func test_group_names_map_onto_the_profile_appearance() -> void:
	assert_eq(GolferSkin.profile_key_for_group("Shirt"), "shirt_color")
	assert_eq(GolferSkin.profile_key_for_group("pants"), "pants_color")
	assert_eq(GolferSkin.profile_key_for_group(" Cap "), "cap_color")
	assert_eq(GolferSkin.profile_key_for_group("Hair"), "hair_color")
	assert_eq(GolferSkin.profile_key_for_group("Skin"), "skin_tone")
	assert_eq(GolferSkin.profile_key_for_group("Trim"), "", "a group of the player's own names no field")
	assert_eq(GolferSkin.profile_key_for_group(""), "")

	var profile := PlayerGolferProfile.new()
	profile.appearance = {"shirt_color": "2878d0", "skin_tone": "76c4a1"}
	assert_eq(GolferSkin.profile_color(profile, "Shirt"), Color("2878d0"))
	assert_eq(GolferSkin.profile_color(profile, "Skin"), Color("76c4a1"))
	assert_eq(GolferSkin.profile_color(null, "Shirt"), Color.WHITE)


func test_a_recorded_skin_recolors_one_sprite_through_its_layers() -> void:
	var skin := _test_skin()
	var shirt := int(skin.group_by_name("Shirt").get("id"))
	var key := GolferSkin.layer_key("idle", "south", 0)
	var image := _image()
	var layer := GolferSkinLayer.create(2, 2)
	layer.set_cell(0, 0, shirt)
	layer.set_cell(1, 0, shirt)
	skin.set_layer(key, layer)
	skin.refresh_shades_from(image, key)
	var recolored := skin.recolor_image(image, key, {})
	assert_eq(recolored.get_pixel(0, 1), image.get_pixel(0, 1), "Pixels outside the layer are untouched")

	var overrides := {"shirt": Color("00ff00")}
	var with_profile := skin.recolor_image(image, key, overrides)
	assert_almost_eq(with_profile.get_pixel(0, 0).g, 1.0, 0.01)
	assert_lt(with_profile.get_pixel(0, 0).r, 0.1)
	# A sprite with no layer keeps the artwork.
	assert_eq(skin.recolor_image(image, GolferSkin.layer_key("swing", "north", 3), {}), image)


# =============================================================================
# THE LIBRARY
# =============================================================================

func test_the_skins_that_ship_with_the_game_are_found() -> void:
	var library := _library()
	var ids := library.skin_ids()
	assert_true(ids.has("casual"), "The Casual skin ships with the game: %s" % str(ids))
	assert_true(ids.has("beginner"), "and so does the Beginner one")
	assert_eq(library.sprite_sets(), ["beginner", "casual"], "The artwork offers both sprite sets")

	var casual := library.get_skin("casual")
	assert_false(casual.is_user_skin, "A shipped skin is not the player's own")
	assert_eq(casual.display_name, "Casual")
	assert_true(casual.wears_tier(GolferTier.Tier.CASUAL))
	assert_eq(library.skins_for_tier(GolferTier.Tier.BEGINNER)[0].id, "beginner",
		"Visiting beginners wear the Beginner skin")
	assert_eq(library.skin_for_tier(GolferTier.Tier.CASUAL).id, "casual")
	assert_true(library.get_skin("beginner").group_by_name("Shirt").size() > 0,
		"A shipped skin carries Re-color Groups to paint with: %s" % str(library.get_skin("beginner").group_list()))


func test_a_tier_with_no_skin_of_its_own_still_has_something_to_wear() -> void:
	var library := _library()
	# Serious and Pro have no artwork of their own; they fall back to the skin
	# the Casual tier wears rather than to no sprites at all.
	assert_eq(library.skin_for_tier(GolferTier.Tier.SERIOUS).id, "casual")
	assert_eq(library.skin_for_tier(GolferTier.Tier.PRO).id, "casual")

	# A player-made skin that dresses a tier takes priority over the fallback.
	var mine := library.create_skin("Tour Kit", "casual")
	mine.set_wears_tier(GolferTier.Tier.PRO, true)
	assert_true(library.save_skin(mine))
	assert_eq(library.skin_for_tier(GolferTier.Tier.PRO).id, mine.id)
	assert_eq(library.skin_for_tier(GolferTier.Tier.CASUAL).id, "casual", "The other tiers are untouched")


func test_editing_a_shipped_skin_copies_it_into_the_players_folder() -> void:
	var library := _library()
	var skin := library.get_skin("casual")
	assert_true(library.ensure_editable(skin))
	assert_true(skin.is_user_skin)
	assert_eq(skin.dir, TEST_ROOT.path_join("casual"))
	assert_false(skin.fallback_dir.is_empty(), "The shipped skin is remembered as the one to fall back on")
	assert_true(FileAccess.file_exists(skin.dir.path_join(GolferSkin.MANIFEST_FILE)))
	# Every layer came with it, and reads back identically.
	var key := GolferSkin.layer_key("idle", "south", 0)
	var shipped := FileAccess.get_file_as_string(GolferSkin.layer_path(skin.fallback_dir, key))
	var copied := FileAccess.get_file_as_string(GolferSkin.layer_path(skin.dir, key))
	assert_eq(copied, shipped)

	# An edit is written to the player's folder and reloaded from it.
	var shirt := int(skin.group_by_name("Shirt").get("id"))
	skin.layer(key).set_cell(7, 7, shirt)
	skin.mark_layer_dirty(key)
	assert_true(library.save_skin(skin))
	var reloaded := _library().get_skin("casual")
	assert_true(reloaded.is_user_skin, "The player's copy shadows the shipped skin")
	assert_eq(reloaded.layer(key).get_cell(7, 7), shirt, "and carries the painted pixel")

	# Reverting drops the copy and the shipped skin is back.
	assert_true(library.revert_skin(skin))
	var shipped_again := _library().get_skin("casual")
	assert_false(shipped_again.is_user_skin)
	assert_eq(shipped_again.layer(key).get_cell(7, 7), GolferSkinLayer.NO_GROUP)
	assert_true(library.has_skin("casual"))


func test_new_skins_get_their_own_folder_and_id() -> void:
	var library := _library()
	var first := library.create_skin("My Kit", "beginner")
	assert_eq(first.id, "my-kit")
	assert_eq(first.sprite_id, "beginner", "A new skin is drawn over the sprite set it was given")
	assert_eq(first.group_count(), 0, "and starts with no groups until the player makes one")
	assert_true(library.save_skin(first))
	assert_true(DirAccess.dir_exists_absolute(TEST_ROOT.path_join("my-kit")))

	var second := library.create_skin("My Kit", "beginner")
	assert_eq(second.id, "my-kit-2", "A second skin of the same name gets an id of its own")
	assert_eq(library.unique_skin_id("casual"), "casual-2", "An id is never taken from an existing skin")
	assert_true(library.save_skin(second))
	assert_eq(library.skins().size(), 4, "Two shipped skins and two of the player's: %s" % str(library.skin_ids()))
	# The player's skins are listed first.
	assert_eq(library.skin_ids().slice(0, 2), ["my-kit", "my-kit-2"])

	assert_true(library.delete_skin(second))
	assert_false(library.has_skin("my-kit-2"))
	assert_false(DirAccess.dir_exists_absolute(TEST_ROOT.path_join("my-kit-2")))
	assert_false(library.delete_skin(library.get_skin("casual")), "A shipped skin is not the player's to delete")


func test_a_skin_can_be_copied_with_everything_it_carries() -> void:
	var library := _library()
	var source := library.get_skin("casual")
	var key := GolferSkin.layer_key("idle", "south", 2)
	var shirt := int(source.group_by_name("Shirt").get("id"))
	source.layer(key).set_cell(3, 3, shirt)
	var copy := library.duplicate_skin(source, "Casual Copy")
	assert_not_null(copy)
	assert_eq(copy.display_name, "Casual Copy")
	assert_eq(copy.group_count(), source.group_count())
	assert_true(copy.worn_by.is_empty(),
		"The copy is not dressed on any tier: the player decides (source wears %s)" % str(source.worn_by))
	assert_eq(copy.layer(key).get_cell(3, 3), shirt, "The painting comes with the copy")
	assert_ne(copy.layer(key), source.layer(key), "and is a copy of its own")
	source.layer(key).set_cell(3, 3, GolferSkinLayer.NO_GROUP)
	assert_eq(copy.layer(key).get_cell(3, 3), shirt, "Editing the original leaves the copy alone")


func test_players_golfer_wears_the_skin_they_chose() -> void:
	var library := _library()
	var previous := GameManager.player_skin_id
	GameManager.player_skin_id = ""
	assert_eq(library.player_skin(GameManager.player_skin_id).id, "casual",
		"With nothing chosen the owner wears the Casual skin")
	var mine := library.create_skin("Sunday Best", "beginner")
	assert_true(library.save_skin(mine))
	GameManager.player_skin_id = mine.id
	assert_eq(library.player_skin(GameManager.player_skin_id).id, mine.id)
	GameManager.player_skin_id = "not-a-skin"
	assert_eq(library.player_skin(GameManager.player_skin_id).id, "casual",
		"A skin that has gone missing falls back to the Casual one")
	GameManager.player_skin_id = previous


# =============================================================================
# FRAMES
# =============================================================================

func test_frames_are_built_from_the_skins_layers() -> void:
	var library := _library()
	var skin := library.get_skin("casual")
	var frames := library.recolored_frames(skin)
	assert_not_null(frames)
	for animation in ["idle_south", "walk_north-east", "swing_west"]:
		assert_true(frames.has_animation(animation), "The golfer's %s animation is built" % animation)
	assert_eq(frames.get_frame_count("idle_south"), 4)
	assert_eq(frames.get_frame_count("swing_south"), 6)
	# Directions with no art of their own fall back to the nearest cardinal.
	assert_eq(frames.get_frame_count("walk_south-west"),
		frames.get_frame_count("walk_west"), "A missing diagonal plays the cardinal it faces")

	# Re-colouring a group changes the frames; the raw artwork stays as it is.
	var key := GolferSkin.layer_key("idle", "south", 0)
	var shirt := int(skin.group_by_name("Shirt").get("id"))
	var raw_before := library.raw_frames(skin).get_frame_texture("idle_south", 0) \
		.get_image().get_pixel(24, 21)
	var before := frames.get_frame_texture("idle_south", 0).get_image().get_pixel(24, 21)
	assert_almost_eq(maxf(before.r, maxf(before.g, before.b)),
		maxf(raw_before.r, maxf(raw_before.g, raw_before.b)), 0.01,
		"A skin drawn in the colours it was generated from keeps the artwork's shading")
	assert_true(skin.set_group_color(shirt, Color("00ff00")))
	library.invalidate(skin.id)
	var after := library.recolored_frames(skin).get_frame_texture("idle_south", 0).get_image().get_pixel(24, 21)
	assert_ne(after, before, "A new group colour reaches the frames")
	assert_gt(after.g, after.r)
	var raw := library.raw_frames(skin).get_frame_texture("idle_south", 0).get_image().get_pixel(24, 21)
	assert_eq(raw, raw_before, "The artwork behind the layer is left alone")
	assert_not_null(library.texture_for(skin, key))


func test_painting_a_pixel_reaches_the_frames_the_golfer_draws() -> void:
	var library := _library()
	var skin := library.duplicate_skin(library.get_skin("casual"), "Painted")
	var cap := int(skin.group_by_name("Cap").get("id"))
	var key := GolferSkin.layer_key("idle", "south", 0)
	var cell := Vector2i(23, 20)
	var source := library.texture_for(skin, key).get_image().get_pixel(cell.x, cell.y)
	skin.set_group_color(cap, Color("ff00ff"))
	skin.set_group_shade(cap, 1.0)
	skin.layer(key).set_cell(cell.x, cell.y, cap)
	skin.mark_layer_dirty(key)
	var painted := library.recolored_frames(skin).get_frame_texture("idle_south", 0) \
		.get_image().get_pixel(cell.x, cell.y)
	assert_ne(painted, source, "The painted pixel is drawn in the group's colour now")
	assert_gt(painted.r, painted.g, "and it is the colour the group was given")


func test_a_skin_without_art_builds_no_frames() -> void:
	var library := _library()
	var skin := library.create_skin("Empty", "no-such-sprite-set")
	assert_eq(skin.sprite_keys().size(), 0)
	assert_null(library.recolored_frames(skin), "A skin nobody can draw is not drawn")
	assert_eq(library.frame_keys(skin, "idle", "south").size(), 0)


# =============================================================================
# GOLFERS
# =============================================================================

func _test_skin() -> GolferSkin:
	## The Casual skin, loaded straight from the shipped folder (not saved
	## anywhere), with its groups as the game ships them.
	var skin := GolferSkin.parse_manifest(
		FileAccess.get_file_as_string(BUILT_IN_ROOT.path_join("casual").path_join(GolferSkin.MANIFEST_FILE)),
		"casual")
	skin.dir = BUILT_IN_ROOT.path_join("casual")
	skin.art_root = GolferSkinLibrary.SPRITE_ROOT.path_join("casual").path_join("animations")
	skin.sprite_size = Vector2i(48, 48)
	return skin


func test_a_visitor_is_drawn_in_the_skin_their_tier_wears() -> void:
	var golfer: Golfer = add_child_autofree(load("res://scenes/entities/golfer.tscn").instantiate())
	await get_tree().process_frame
	assert_true(golfer._use_sprites, "A Casual visitor is drawn with sprites")
	assert_eq(golfer.skin().id, "casual", "wearing the Casual skin")
	var frames := golfer.sprite_node().sprite_frames
	assert_true(frames.get_frame_count("idle_south") > 0)

	# A Beginner is dressed again when the tier arrives after the spawn.
	golfer.initialize_from_tier(GolferTier.Tier.BEGINNER)
	assert_eq(golfer.skin().id, "beginner", "Becoming a Beginner changes what he wears")
	var beginner_frames := golfer.sprite_node().sprite_frames
	assert_true(beginner_frames.get_frame_count("idle_south") > 0)
	assert_ne(beginner_frames.get_frame_texture("idle_south", 0),
		frames.get_frame_texture("idle_south", 0), "and it is different artwork")


func test_a_golfer_can_be_dressed_in_a_skin_by_name() -> void:
	var golfer: Golfer = add_child_autofree(load("res://scenes/entities/golfer.tscn").instantiate())
	golfer.skin_id = "beginner"
	await get_tree().process_frame
	assert_eq(golfer.skin().id, "beginner")
	var frames := golfer.sprite_node().sprite_frames
	# A tier change must not undress a golfer who was given a skin by name.
	golfer.initialize_from_tier(GolferTier.Tier.PRO)
	assert_eq(golfer.skin().id, "beginner")
	assert_eq(golfer.sprite_node().sprite_frames, frames)


func test_saving_a_skin_redresses_the_golfers_already_on_the_course() -> void:
	var manager: GolferManager = add_child_autofree(GolferManager.new())
	var golfer: Golfer = add_child_autofree(load("res://scenes/entities/golfer.tscn").instantiate())
	await get_tree().process_frame
	manager.active_golfers.append(golfer)
	var skin := golfer.skin()
	assert_not_null(skin, "The visitor wears a skin")
	var shirt := int(skin.group_by_name("Shirt").get("id"))
	var previous: Color = skin.group_by_id(shirt).get("color")
	var cell := Vector2i(24, 21)

	# What the studio does when the player presses Save Skins: change the skin,
	# drop the cached frames and say so.
	assert_true(skin.set_group_color(shirt, Color("00ff00")))
	GolferSkins.invalidate(skin.id)
	GolferSkins.skins_changed.emit()
	await get_tree().process_frame
	var frames := golfer.sprite_node().sprite_frames
	var painted := frames.get_frame_texture("idle_south", 0).get_image().get_pixelv(cell)
	assert_gt(painted.g, painted.r, "The golfer already on the course wears the new colour")

	# Put the shipped colour back for the rest of the run.
	assert_true(skin.set_group_color(shirt, previous))
	GolferSkins.invalidate(skin.id)
	GolferSkins.skins_changed.emit()
	await get_tree().process_frame
	var restored := golfer.sprite_node().sprite_frames \
		.get_frame_texture("idle_south", 0).get_image().get_pixelv(cell)
	assert_gt(restored.r, restored.g, "and a revert puts the old colour back")


## The owner's own golfer wears the skin they chose, in the colours that skin
## carries - the Edit Player page and the Edit Golfer Skins screen both edit
## those, and that is what the course draws.
func test_the_owner_wears_the_colours_of_the_skin_they_chose() -> void:
	# The golfer asks GolferSkins (the autoload) which skin to wear, so point that
	# at the test folder for the length of the test.
	var previous_library := GolferSkins.library
	var library := _library()
	GolferSkins.library = library
	var mine := library.duplicate_skin(library.get_skin("casual"), "Sunday Best")
	var shirt := int(mine.group_by_name("Shirt").get("id"))
	assert_true(mine.set_group_color(shirt, Color("00ff00")))
	assert_true(library.save_skin(mine))

	var golfer: Golfer = add_child_autofree(load("res://scenes/entities/golfer.tscn").instantiate())
	var profile := PlayerGolferProfile.new()
	profile.appearance = {"shirt_color": "2878d0", "pants_color": "2e9f55",
		"cap_color": "ecd247", "hair_color": "b34725", "skin_tone": "76c4a1"}
	var previous := GameManager.player_skin_id
	GameManager.player_skin_id = mine.id
	# The owner's golfer carries the profile (that is what makes it the owner's),
	# and is dressed in the chosen skin (see PlayerRoundManager._start_embedded).
	golfer.player_profile = profile
	golfer.apply_player_appearance(profile)
	await get_tree().process_frame

	assert_true(golfer._use_sprites, "The owner keeps the pixel renderer")
	assert_eq(golfer.skin().id, mine.id, "in the skin they picked")
	var image := golfer.sprite_node().sprite_frames.get_frame_texture("idle_south", 0) \
		.get_image()
	var shirt_pixel := image.get_pixel(24, 21)
	assert_gt(shirt_pixel.g, shirt_pixel.r, "and the shirt takes the skin's green, not the profile's blue")
	assert_gt(shirt_pixel.g, shirt_pixel.b, "the blue in the profile does not win")

	# A group of the player's own is drawn in its own colour too.
	var custom := mine.create_group("Trim")
	assert_true(mine.set_group_color(custom, Color("ff00ff")))
	assert_true(mine.set_group_shade(custom, 1.0))
	var cell := Vector2i(23, 20)
	mine.layer(GolferSkin.layer_key("idle", "south", 0)).set_cell(cell.x, cell.y, custom)
	mine.mark_layer_dirty(GolferSkin.layer_key("idle", "south", 0))
	library.invalidate(mine.id)
	golfer.refresh_skin_sprites()
	var trimmed := golfer.sprite_node().sprite_frames.get_frame_texture("idle_south", 0) \
		.get_image().get_pixelv(cell)
	assert_gt(trimmed.r, trimmed.g, "A group the profile never heard of is painted by the skin")

	GameManager.player_skin_id = previous
	GolferSkins.library = previous_library
