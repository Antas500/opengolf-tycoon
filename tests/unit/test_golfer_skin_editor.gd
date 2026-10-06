extends GutTest
## Unit tests for the Edit Golfer Skins screen: the painting surface's geometry,
## and the studio driving a skin - groups, layers, the Save that writes them out
## and the preview golfer that wears the result.
##
## The screen is pointed at a library under user:// before it is added to the
## tree, so nothing here writes to the player's own golfer_skins folder.

const BUILT_IN_ROOT := "res://data/golfer_skins"
const TEST_ROOT := "user://test_skin_editor"


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


func _library() -> GolferSkinLibrary:
	return GolferSkinLibrary.new(BUILT_IN_ROOT, TEST_ROOT)


## The studio, opened on a skin the test owns.
func _studio(confirm: bool = true) -> EditGolferSkinsScreen:
	var screen := EditGolferSkinsScreen.new()
	screen.library = _library()
	if confirm:
		screen.confirm_callback = func(_message: String, _action: String) -> bool: return true
	add_child_autofree(screen)
	screen._select_skin(screen.library.get_skin("casual"))
	screen._build()
	return screen


# =============================================================================
# THE PAINTING SURFACE
# =============================================================================

func test_the_canvas_maps_the_sprite_onto_whole_pixels() -> void:
	var canvas := GolferSkinLayerCanvas.new()
	add_child_autofree(canvas)
	canvas.size = Vector2(400, 300)
	canvas.set_artwork(Image.create(48, 48, false, Image.FORMAT_RGBA8), null)
	assert_eq(canvas.cell_size(), 6.0, "288 of the 300 short side is 6 pixels per sprite pixel")
	var rect := canvas.sprite_rect()
	assert_eq(rect.size, Vector2(288, 288))
	assert_eq(rect.position, Vector2(56, 6), "The sprite is centred in the control")
	assert_eq(canvas.cell_at(rect.position + Vector2(3, 3)), Vector2i(0, 0))
	assert_eq(canvas.cell_at(rect.position + Vector2(8, 8)), Vector2i(1, 1))
	assert_eq(canvas.cell_at(rect.end - Vector2(1, 1)), Vector2i(47, 47), "The last pixel is the bottom-right one")
	assert_eq(canvas.cell_at(rect.position - Vector2(1, 1)), Vector2i(-1, -1), "Outside the sprite there is no pixel")
	assert_eq(canvas.cell_at(Vector2(2, 2)), Vector2i(-1, -1))
	assert_eq(canvas.cell_at(rect.end + Vector2(1, 1)), Vector2i(-1, -1))


func test_the_canvas_never_stretches_the_sprite_and_never_shows_nothing() -> void:
	var canvas := GolferSkinLayerCanvas.new()
	add_child_autofree(canvas)
	canvas.set_artwork(Image.create(48, 48, false, Image.FORMAT_RGBA8), null)
	# A control smaller than the sprite's 12 pixel margin has no room at all.
	canvas.custom_minimum_size = Vector2.ZERO
	canvas.size = Vector2(10, 10)
	assert_eq(canvas.cell_size(), 0.0)
	assert_true(canvas.sprite_rect().size == Vector2.ZERO)
	assert_eq(canvas.cell_at(Vector2(5, 5)), Vector2i(-1, -1))
	# A window too small for a whole pixel per pixel falls back to a fraction,
	# so a squeezed studio still shows something.
	canvas.size = Vector2(60, 40)
	assert_almost_eq(canvas.cell_size(), 28.0 / 48.0, 0.0001)
	assert_true(canvas.sprite_rect().size.x <= canvas.size.x)
	assert_true(canvas.sprite_rect().size.y <= canvas.size.y)
	# A layer with no artwork still gives the grid its shape.
	var bare := GolferSkinLayerCanvas.new()
	add_child_autofree(bare)
	bare.custom_minimum_size = Vector2.ZERO
	bare.size = Vector2(200, 200)
	bare.set_layer(GolferSkinLayer.create(20, 20))
	assert_eq(bare.cell_size(), 9.0)
	assert_eq(bare.cell_at(Vector2(100, 100)), Vector2i(10, 10))


func test_the_canvas_asks_the_screen_to_paint_erase_and_pick() -> void:
	var canvas := GolferSkinLayerCanvas.new()
	add_child_autofree(canvas)
	canvas.size = Vector2(200, 200)
	canvas.set_artwork(Image.create(48, 48, false, Image.FORMAT_RGBA8), null)
	var painted: Array[Vector2i] = []
	var erased: Array[Vector2i] = []
	var picked: Array[Vector2i] = []
	canvas.cell_painted.connect(func(reported: Vector2i): painted.append(reported))
	canvas.cell_erased.connect(func(reported: Vector2i): erased.append(reported))
	canvas.cell_picked.connect(func(reported: Vector2i): picked.append(reported))

	var rect := canvas.sprite_rect()
	var span := canvas.cell_size()
	var first := rect.position + Vector2(5, 5)          # sprite pixel (1, 1)
	var second := first + Vector2(span, 0)             # the pixel to its right
	canvas._gui_input(_mouse_button(first, MOUSE_BUTTON_LEFT, true))
	canvas._gui_input(_mouse_motion(second, true))
	canvas._gui_input(_mouse_button(second, MOUSE_BUTTON_LEFT, false))
	assert_eq(painted.size(), 2, "A press and a drag each paint a pixel: %s" % str(painted))
	assert_eq(painted[0], Vector2i(1, 1))
	assert_eq(painted[1], Vector2i(2, 1))

	canvas._gui_input(_mouse_button(first, MOUSE_BUTTON_RIGHT, true))
	assert_eq(erased, [Vector2i(1, 1)] as Array[Vector2i], "right-click frees a pixel")

	canvas._gui_input(_mouse_button(second, MOUSE_BUTTON_LEFT, true, true))
	assert_eq(picked, [Vector2i(2, 1)] as Array[Vector2i], "alt-click picks the group already on a pixel")

	# Outside the sprite nothing is reported at all.
	canvas._gui_input(_mouse_button(Vector2(1, 1), MOUSE_BUTTON_LEFT, true))
	canvas._gui_input(_mouse_button(Vector2(1, 1), MOUSE_BUTTON_RIGHT, true))
	assert_eq(painted.size(), 2)
	assert_eq(erased.size(), 1)


func _mouse_button(position: Vector2, button: MouseButton, pressed: bool,
		alt: bool = false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = button as MouseButton
	event.pressed = pressed
	event.alt_pressed = alt
	return event


## A held left button being dragged across the canvas.
func _mouse_motion(position: Vector2, held: bool) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	return event


# =============================================================================
# THE STUDIO
# =============================================================================

func test_the_studio_opens_on_a_skin_with_every_part_of_it_showing() -> void:
	var screen := _studio()
	var skin := screen._skin
	assert_eq(skin.id, "casual")
	assert_not_null(screen._canvas)
	assert_eq(screen._canvas.layer, skin.layer(screen._current_key()), "The canvas paints the sprite on screen")
	assert_not_null(screen._canvas.image, "its artwork")
	assert_not_null(screen._canvas.preview_image, "and its re-coloured twin")
	assert_eq(screen._sprite_keys().size(), 4, "the idle animation has four frames")
	assert_eq(screen._frame_strip.get_child_count(), 4, "one tile per frame")
	assert_eq(screen._group_rows.get_child_count(), skin.group_count(), "one row per group")
	assert_eq(screen._palette.get_child_count(), skin.group_count() + 1, "a swatch per group, plus None")
	assert_not_null(screen._pixel_color_button, "the Pixels side has a colour picker to paint with")
	assert_not_null(screen._brush_picker, "and a brush to paint with")
	assert_eq(screen._brush_size, 1, "one pixel wide until the player asks for more")
	assert_false(screen._canvas.show_recolor,
		"the canvas opens on the artwork the brush is changing")
	assert_eq(screen._skin_name_edit.text, "Casual")
	assert_eq(screen._active_group, int(skin.group_list()[0].get("id")), "The first group starts selected")
	assert_not_null(screen._preview_golfer, "the golfer wearing the skin is previewed")
	assert_true(screen._preview_golfer.use_skin_sprites())
	assert_true(screen._save_button.disabled, "An untouched skin has nothing to save yet")
	assert_false(screen._dirty)


func test_painting_marks_the_skin_unsaved_and_saving_writes_it_out() -> void:
	var screen := _studio()
	screen._set_mode(EditGolferSkinsScreen.Mode.GROUPS)
	var key := screen._current_key()
	var layer := screen._skin.layer(key)
	var empty := _first_free_cell(layer)
	assert_false(screen._dirty)
	screen._on_cell_painted(empty)
	assert_eq(layer.get_cell(empty.x, empty.y), screen._active_group, "The pixel takes the active group")
	assert_true(screen._dirty, "and the skin is unsaved")
	assert_false(screen._save_button.disabled, "Save lights up")
	screen._on_save_pressed()
	assert_false(screen._dirty)
	var folder := TEST_ROOT.path_join("casual")
	assert_true(FileAccess.file_exists(folder.path_join(GolferSkin.MANIFEST_FILE)), "the skin is written out")
	assert_true(FileAccess.file_exists(GolferSkin.layer_path(folder, key)))
	# The written layer reads back with the painted pixel in it.
	var reloaded := _library().get_skin("casual")
	assert_eq(reloaded.layer(key).get_cell(empty.x, empty.y), screen._active_group)
	assert_true(reloaded.is_user_skin)

	# A colour change is an edit too, and reaches the sprite on the canvas. The
	# active group owns the shirt pixels, so its colour is what they change to.
	var shirt_pixel := Vector2i(24, 21)
	assert_eq(layer.get_cell(shirt_pixel.x, shirt_pixel.y), screen._active_group)
	var before := screen._canvas.preview_image.get_pixel(shirt_pixel.x, shirt_pixel.y)
	screen._on_group_color_chosen(Color("00ff00"))
	assert_true(screen._dirty, "A re-colour is an edit")
	assert_ne(screen._canvas.preview_image.get_pixel(shirt_pixel.x, shirt_pixel.y), before,
		"and the preview sprite shows it")
	assert_gt(screen._canvas.preview_image.get_pixel(shirt_pixel.x, shirt_pixel.y).g,
		screen._canvas.preview_image.get_pixel(shirt_pixel.x, shirt_pixel.y).r,
		"the pixel is drawn in the new colour")


## Painted pixels and grouped pixels both go into the skin's own editable text
## files, and a skin saved that way is the skin that is drawn.
func test_painted_pixels_are_saved_and_read_back() -> void:
	var screen := _studio()
	var key := screen._current_key()
	var spot := Vector2i(24, 21)
	screen._set_mode(EditGolferSkinsScreen.Mode.PIXELS)
	screen._on_pixel_color_chosen(Color8(240, 51, 102))
	screen._on_cell_painted(spot)
	screen._set_mode(EditGolferSkinsScreen.Mode.GROUPS)
	var cap := int(screen._skin.group_by_name("Cap").get("id"))
	screen._on_group_row_pressed(cap)
	screen._on_cell_painted(Vector2i(24, 9))
	screen._on_save_pressed()
	assert_false(screen._dirty)

	# The file says what was painted, in a layer a person could edit.
	var text := FileAccess.get_file_as_string(GolferSkin.layer_path(TEST_ROOT.path_join("casual"), key))
	assert_true(text.contains("art"), "the layer file carries the painted pixels")
	assert_true(text.contains("f03366"), "written as hex")
	var reloaded := _library().get_skin("casual").layer(key)
	assert_true(reloaded.has_art())
	assert_eq(reloaded.art_pixel(spot.x, spot.y), Color8(240, 51, 102), "and they come back")
	assert_eq(reloaded.get_cell(24, 9), cap, "along with the group the other pixel was given to")

	# And that is what the golfer is drawn with.
	var frames := _library().recolored_frames(_library().get_skin("casual"))
	assert_eq(frames.get_frame_texture("idle_south", 0).get_image().get_pixel(spot.x, spot.y),
		Color8(240, 51, 102), "the golfer wears the painted pixel")


func test_the_canvas_never_reports_a_cell_outside_the_grid() -> void:
	var screen := _studio()
	screen._set_mode(EditGolferSkinsScreen.Mode.GROUPS)
	var layer := screen._skin.layer(screen._current_key())
	var before := layer.count(screen._active_group)
	screen._on_cell_painted(Vector2i(-1, 5))
	screen._on_cell_painted(Vector2i(48, 5))
	screen._on_cell_painted(Vector2i(5, 99))
	assert_eq(layer.count(screen._active_group), before, "Off the grid nothing changes")
	assert_false(screen._dirty)
	# And the same with the brush on the Pixels side.
	screen._set_mode(EditGolferSkinsScreen.Mode.PIXELS)
	screen._on_cell_painted(Vector2i(-1, 5))
	screen._on_cell_painted(Vector2i(48, 5))
	assert_false(layer.has_art(), "painting off the grid does not even take the artwork in")
	assert_false(screen._dirty)


func test_erasers_and_pickers_reach_the_layer() -> void:
	var screen := _studio()
	screen._set_mode(EditGolferSkinsScreen.Mode.GROUPS)
	var layer := screen._skin.layer(screen._current_key())
	var cell := Vector2i(24, 21)
	assert_ne(layer.get_cell(cell.x, cell.y), GolferSkinLayer.NO_GROUP, "A shirt pixel to work with")
	screen._on_cell_erased(cell)
	assert_eq(layer.get_cell(cell.x, cell.y), GolferSkinLayer.NO_GROUP, "Right-click frees the pixel")
	assert_eq(screen._skin.layer(screen._current_key()).get_cell(24, 21), 0)
	screen._on_group_row_pressed(GolferSkinLayer.NO_GROUP)
	assert_eq(screen._active_group, GolferSkinLayer.NO_GROUP, "None can be painted with, which frees pixels")
	screen._on_cell_painted(Vector2i(24, 21))
	assert_eq(layer.get_cell(24, 21), GolferSkinLayer.NO_GROUP, "so painting with None erases")

	screen._on_group_row_pressed(int(screen._skin.group_by_name("Cap").get("id")))
	var cap := screen._active_group
	screen._on_cell_painted(cell)
	screen._on_cell_picked(cell)
	assert_eq(screen._active_group, cap, "alt-click picks up the group on the pixel")
	screen._on_cell_picked(Vector2i(0, 0))
	assert_eq(screen._active_group, GolferSkinLayer.NO_GROUP, "and an ungrouped pixel picks None")


func test_the_fill_tool_gives_a_whole_run_of_pixels_to_the_active_group() -> void:
	var screen := _studio()
	screen._set_mode(EditGolferSkinsScreen.Mode.GROUPS)
	var layer := screen._skin.layer(screen._current_key())
	var clicked := Vector2i(24, 21)
	var shirt := layer.get_cell(clicked.x, clicked.y)
	assert_ne(shirt, GolferSkinLayer.NO_GROUP, "The click lands on a grouped pixel")
	var run := layer.flood_cells(clicked.x, clicked.y, screen._canvas.image)
	assert_gt(run.size(), 1, "The shirt is a run of %d pixels" % run.size())

	var cap := int(screen._skin.group_by_name("Cap").get("id"))
	var shirt_before := layer.count(shirt)
	assert_false(screen._fill_check.button_pressed, "Painting is one pixel at a time until Fill is asked for")
	screen._on_fill_toggled(true)
	screen._on_group_row_pressed(cap)
	screen._on_cell_painted(clicked)
	for painted_cell in run:
		assert_eq(layer.get_cell(painted_cell.x, painted_cell.y), cap,
			"%s belongs to the group that was painted with" % painted_cell)
	assert_eq(layer.count(cap), int(screen._group_pixel_counts().get(cap, 0)),
		"the row's pixel count is updated with it")
	assert_eq(layer.count(shirt), shirt_before - run.size(), "and the old group is that much smaller")
	assert_true(screen._dirty, "One click is one edit")


## The Pixels side: a colour and a brush paint the sprite's own pixels - what
## the golfer is drawn with - and the colour comes from the picker.
func test_the_pixel_brush_paints_the_artwork_with_the_picked_colour() -> void:
	var screen := _studio()
	var key := screen._current_key()
	var layer := screen._skin.layer(key)
	screen._set_mode(EditGolferSkinsScreen.Mode.PIXELS)
	assert_false(layer.has_art(), "an untouched skin draws the artwork that ships with it")

	var spot := Vector2i(24, 21)
	screen._on_pixel_color_chosen(Color("ff3366"))
	screen._on_cell_painted(spot)
	assert_true(layer.has_art(), "painting takes the sprite's artwork into the layer")
	assert_eq(layer.art_pixel(spot.x, spot.y), Color("ff3366"), "and the pixel takes the picked colour")
	assert_eq(layer.get_cell(spot.x, spot.y), GolferSkinLayer.NO_GROUP,
		"a painted pixel is the artwork's own colour, so it leaves its Re-color Group")
	assert_true(screen._dirty, "the edit is unsaved")
	assert_eq(screen._canvas.image.get_pixel(spot.x, spot.y), Color("ff3366"),
		"the canvas shows the pixel as painted")

	# The brush covers its footprint, not just the pixel clicked.
	screen._on_brush_size_selected(EditGolferSkinsScreen.BRUSH_SIZES.find(5))
	assert_eq(screen._canvas.brush_size, 5, "the brush picker sets the canvas brush too")
	var middle := Vector2i(10, 10)
	screen._on_cell_painted(middle)
	var footprint := layer.brush_cells(middle.x, middle.y, 5)
	assert_gt(footprint.size(), 1, "a 5-wide brush covers %d pixels" % footprint.size())
	for spot2 in footprint:
		assert_eq(layer.art_pixel(spot2.x, spot2.y), Color("ff3366"),
			"%s is painted by the brush" % spot2)

	# Right-click erases the pixels the brush covers, and alt-click picks up a
	# colour already on the sprite.
	screen._on_cell_erased(middle)
	var erased := 0
	for spot3 in footprint:
		if layer.art_pixel(spot3.x, spot3.y).a <= 0.0:
			erased += 1
	assert_eq(erased, footprint.size(), "right-click empties the whole footprint")
	screen._on_group_row_pressed(GolferSkinLayer.NO_GROUP)
	screen._on_cell_picked(spot)
	assert_eq(screen._pixel_color, Color("ff3366"), "alt-click picks up the colour already on a pixel")

	# The painted pixel reaches the golfer: the frames are built from the layer.
	var frames := _library().recolored_frames(screen._skin)
	assert_eq(frames.get_frame_texture("idle_south", 0).get_image().get_pixel(spot.x, spot.y),
		Color("ff3366"), "the golfer is drawn with the painted pixel")


## The Groups side: the same brush gives the pixels it covers to the selected
## Re-color Group.
func test_the_group_brush_gives_a_footprint_of_pixels_to_the_selected_group() -> void:
	var screen := _studio()
	screen._set_mode(EditGolferSkinsScreen.Mode.GROUPS)
	var layer := screen._skin.layer(screen._current_key())
	var cap := int(screen._skin.group_by_name("Cap").get("id"))
	screen._on_group_row_pressed(cap)
	assert_eq(screen._active_group, cap, "the group list selects what the brush gives pixels to")

	var spot := Vector2i(24, 21)
	screen._on_brush_size_selected(EditGolferSkinsScreen.BRUSH_SIZES.find(3))
	screen._on_cell_painted(spot)
	for covered in layer.brush_cells(spot.x, spot.y, 3):
		assert_eq(layer.get_cell(covered.x, covered.y), cap, "%s belongs to the Cap group" % covered)
	assert_false(layer.has_art(), "grouping pixels does not touch the artwork")

	# Right-click frees the footprint again.
	screen._on_cell_erased(spot)
	for covered in layer.brush_cells(spot.x, spot.y, 3):
		assert_eq(layer.get_cell(covered.x, covered.y), GolferSkinLayer.NO_GROUP,
			"%s is free again" % covered)


func test_groups_can_be_created_renamed_and_deleted_in_the_studio() -> void:
	var screen := _studio()
	var skin := screen._skin
	var starting := skin.group_count()
	screen._on_new_group_pressed()
	assert_eq(skin.group_count(), starting + 1)
	assert_eq(screen._active_group, int(skin.group_list()[-1].get("id")), "The new group is selected")
	assert_eq(screen._group_rows.get_child_count(), starting + 1, "and it has a row of its own")
	assert_eq(screen._palette.get_child_count(), starting + 2)

	screen._on_group_name_submitted("Trim")
	assert_eq(str(skin.group_by_id(screen._active_group).get("name")), "Trim")
	assert_true(screen._dirty)
	# A name already taken is refused and the field goes back to the old one.
	screen._on_group_name_submitted("Shirt")
	assert_eq(str(skin.group_by_id(screen._active_group).get("name")), "Trim")
	assert_true(screen._error, "and the player is told why")

	var trim := screen._active_group
	screen._on_delete_group_pressed()
	assert_true(skin.group_by_id(trim).is_empty(), "The group is gone (the test answers the confirmation)")
	assert_eq(screen._group_rows.get_child_count(), starting)
	assert_ne(screen._active_group, trim, "and another group takes over the brush")


func test_the_skin_can_be_renamed_dressed_and_copied() -> void:
	var screen := _studio()
	screen._on_skin_name_changed("Sunday Best")
	assert_true(screen._dirty)
	screen._on_tier_toggled(true, GolferTier.Tier.PRO)
	screen._on_save_pressed()
	var saved := _library().get_skin("casual")
	assert_eq(saved.display_name, "Sunday Best", "The name reaches the written skin")
	assert_true(saved.wears_tier(GolferTier.Tier.PRO))
	assert_true(screen._skin_name_edit.text == "Sunday Best")

	screen = _studio()
	var before_count := _library().skin_ids().size()
	screen._on_duplicate_pressed()
	screen._on_save_pressed()
	var ids := _library().skin_ids()
	assert_eq(ids.size(), before_count + 1, "The copy is saved: %s" % str(ids))
	assert_true(ids.has("sunday-best-copy"), "and named after the skin it was copied from: %s" % str(ids))
	assert_eq(screen._skin.display_name, "Sunday Best Copy")


func test_a_new_skin_starts_blank_and_takes_the_sprite_set_of_the_editor() -> void:
	var screen := _studio()
	screen._on_new_skin_pressed()
	var skin := screen._skin
	assert_eq(skin.group_count(), 2, "A new skin starts with the two groups most golfers have")
	assert_eq(screen._group_rows.get_child_count(), 2)
	assert_true(screen._dirty)
	assert_eq(skin.layer(screen._current_key()).used_group_ids(), [],
		"A new skin owns no pixels: its layers are empty until they are painted")
	assert_eq(screen._canvas.layer.width, 48, "but its layers are the size of the artwork under them")
	screen._on_save_pressed()
	var folder := TEST_ROOT.path_join(skin.id)
	assert_true(FileAccess.file_exists(folder.path_join(GolferSkin.MANIFEST_FILE)), "and it saves like any other")
	assert_false(screen._dirty)


func test_the_frames_strip_follows_the_animation_and_direction_pickers() -> void:
	var screen := _studio()
	assert_eq(screen._frame_strip.get_child_count(), 4, "idle has four frames")
	screen._on_animation_selected(GolferSkinLibrary.ANIMATIONS.find("swing"))
	assert_eq(screen._animation, "swing")
	assert_eq(screen._frame_strip.get_child_count(), 6, "the swing has six")
	assert_eq(screen._current_key(), "swing/south/frame_000")
	screen._frame_index = 3
	screen._on_animation_selected(GolferSkinLibrary.ANIMATIONS.find("idle"))
	assert_eq(screen._frame_index, 0, "Changing the sprite starts at its first frame")
	screen._on_direction_selected(GolferSkinLibrary.DIRECTIONS.find("north"))
	assert_eq(screen._current_key(), "idle/north/frame_000")
	screen._on_frame_tile_pressed(2)
	assert_eq(screen._current_key(), "idle/north/frame_002")
	assert_eq(screen._canvas.layer, screen._skin.layer("idle/north/frame_002"))


func test_the_canvas_switches_between_the_artwork_and_the_recolored_sprite() -> void:
	var screen := _studio()
	assert_false(screen._canvas.show_recolor, "Pixels mode paints the artwork itself, so that is what shows")
	screen._on_recolor_toggled(true)
	assert_true(screen._canvas.show_recolor, "and the Re-coloured switch previews how the golfer is drawn")
	assert_true(screen._show_recolor)
	screen._on_grid_toggled(false)
	assert_false(screen._canvas.show_grid)
	screen._set_mode(EditGolferSkinsScreen.Mode.GROUPS)
	assert_false(screen._canvas.show_recolor, "the Groups side always shows the artwork under its washes")
	assert_false(screen._canvas.show_grid, "and the grid switch is shared, so it stays off")


func test_the_layout_breakpoints_cover_the_three_arrangements() -> void:
	assert_eq(EditGolferSkinsScreen.layout_mode_for(Vector2(1600, 1000)), EditGolferSkinsScreen.Layout.WIDE)
	assert_eq(EditGolferSkinsScreen.layout_mode_for(Vector2(1280, 800)), EditGolferSkinsScreen.Layout.WIDE)
	assert_eq(EditGolferSkinsScreen.layout_mode_for(Vector2(1024, 768)), EditGolferSkinsScreen.Layout.TABLET)
	assert_eq(EditGolferSkinsScreen.layout_mode_for(Vector2(768, 1024)), EditGolferSkinsScreen.Layout.TABLET)
	assert_eq(EditGolferSkinsScreen.layout_mode_for(Vector2(390, 844)), EditGolferSkinsScreen.Layout.PHONE)
	assert_eq(EditGolferSkinsScreen.layout_mode_for(Vector2(844, 390)), EditGolferSkinsScreen.Layout.PHONE,
		"a short window is a phone whatever its width")
	assert_eq(EditGolferSkinsScreen.layout_mode_for(
		Vector2(EditGolferSkinsScreen.WIDE_MIN_WIDTH, EditGolferSkinsScreen.TALL_MIN_HEIGHT)),
		EditGolferSkinsScreen.Layout.WIDE, "the smallest wide window")
	assert_eq(EditGolferSkinsScreen.layout_mode_for(Vector2(1079, 560)), EditGolferSkinsScreen.Layout.TABLET)


## The first pixel of the sprite that belongs to no group.
func _first_free_cell(layer: GolferSkinLayer) -> Vector2i:
	for y in layer.height:
		for x in layer.width:
			if layer.get_cell(x, y) == GolferSkinLayer.NO_GROUP:
				return Vector2i(x, y)
	return Vector2i(-1, -1)
