extends Node
## Run: godot --headless --path . res://tests/harness/edit_golfer_skins_harness.tscn
##
## Drives the real Edit Golfer Skins screen - opened from the title screen's
## Golfer Skins action - through desktop, tablet and phone window sizes, and
## checks that each arrangement (see EditGolferSkinsScreen.layout_mode_for)
## leaves the painting surface big enough to paint on, keeps the studio's
## controls where the player can reach them, and comes back to the menu.
##
## Where the unit tests check what painting does, this checks that it can be
## done at all: a canvas a few pixels wide, a Save button pushed off the window
## or hidden under another control would pass every unit test and still be
## useless. It hit-tests the buttons the way a click would (see _topmost).
##
## Prints one PASS/FAIL line per check and exits non-zero on any failure.

## The sprite is 48x48; a cell this small or smaller is not paintable.
const MIN_CELL := 3.0
## The harness paints into a folder of its own, so running it never touches the
## skins the player has made.
const HARNESS_ROOT := "user://harness_golfer_skins"

var main: Node
var failures := 0
## The messages the studio's confirmation dialog was asked to show.
var _prompts: PackedStringArray = PackedStringArray()

func _check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
	print("SKIN_EDITOR: %s: %s" % ["PASS" if ok else "FAIL", description])

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _set_window(width: int, height: int) -> void:
	get_window().size = Vector2i(width, height)
	await _frames(4)

## Click a control with a real mouse event, exactly as the player would: the
## viewport does the hit-testing, so this only reaches the button when nothing
## is drawn over it.
func _click(control: Control) -> void:
	if control == null:
		_check(false, "a control to click exists")
		return
	var at := control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_viewport().push_input(event)
		await _frames(1)
	await _frames(1)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await _set_window(1600, 1000)
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await _frames(6)

	var menu_button := _find_button(main.main_menu, "GolferSkinsButton")
	_check(menu_button != null, "the title screen has an Edit Golfer Skins action")
	if menu_button != null:
		menu_button.emit_signal("pressed")
	await _frames(6)
	var screen: EditGolferSkinsScreen = main.get_node_or_null("UI/HUD/EditGolferSkinsScreen")
	_check(screen != null, "the action opens the skin studio")
	if screen == null:
		print("SKIN_EDITOR: %d failures" % failures)
		get_tree().quit(1)
		return
	# Point the studio at a folder of its own before anything is saved.
	_remove_tree(HARNESS_ROOT)
	screen.library = GolferSkinLibrary.new(GolferSkinLibrary.BUILT_IN_ROOT, HARNESS_ROOT)
	screen._select_skin(screen.library.get_skin("casual"))
	screen._build()
	await _frames(2)

	# ------------------------------------------------------------------
	# Desktop: the studio, the groups and the skins are all on screen.
	# ------------------------------------------------------------------
	_check(screen._layout_mode == EditGolferSkinsScreen.Layout.WIDE,
		"1600x1000 uses the wide arrangement (got %d)" % screen._layout_mode)
	await _check_studio(screen, 1600.0, 1000.0)
	_check_paint(screen, "desktop")
	await _check_mode_switch(screen)
	await _check_groups(screen)
	_check_open_skin(screen)

	# ------------------------------------------------------------------
	# Tablet: the lists share a row above the studio.
	# ------------------------------------------------------------------
	await _set_window(1024, 768)
	await _frames(4)
	_check(screen._layout_mode == EditGolferSkinsScreen.Layout.TABLET,
		"1024x768 uses the tablet arrangement (got %d)" % screen._layout_mode)
	await _check_studio(screen, 1024.0, 768.0)
	_check_paint(screen, "tablet")

	# ------------------------------------------------------------------
	# Phone: one column, nothing wider than the window, canvas still usable.
	# ------------------------------------------------------------------
	await _set_window(390, 844)
	await _frames(4)
	_check(screen._layout_mode == EditGolferSkinsScreen.Layout.PHONE,
		"390x844 uses the phone arrangement (got %d)" % screen._layout_mode)
	await _check_studio(screen, 390.0, 844.0)
	_check(not _overflows_horizontally(screen),
		"nothing in the phone column is wider than the window")
	var scroll := screen.get_node_or_null("Scroll")
	_check(scroll == null or not scroll.get_h_scroll_bar().visible,
		"the studio scrolls down, never sideways")
	_check_paint(screen, "phone")

	await _set_window(844, 390)
	await _frames(4)
	_check(screen._layout_mode == EditGolferSkinsScreen.Layout.PHONE,
		"a short window is a phone whatever its width (got %d)" % screen._layout_mode)
	_check(_canvas_rect(screen).size.x <= 844.0, "the canvas fits the window")

	# ------------------------------------------------------------------
	# Saving and going back.
	# ------------------------------------------------------------------
	await _set_window(1600, 1000)
	await _frames(4)
	var skin: GolferSkin = screen._skin
	screen._on_cell_painted(_free_cell(screen))
	_check(screen._dirty, "painting leaves the skin unsaved")
	var save_button := _find_button(screen, "SaveSkinsButton")
	_check(save_button != null and not save_button.disabled, "Save Skins is live with changes to write")
	await _click(save_button)
	_check(not screen._dirty, "Save writes the skin out (status: %s)" % screen._status)
	_check(screen.library.has_skin(skin.id), "the studio's skin is in the library")
	_check(screen._skin.dir.begins_with(HARNESS_ROOT),
		"and it lives in the player's own folder (got %s)" % screen._skin.dir)
	_check(FileAccess.file_exists(screen._skin.dir.path_join(GolferSkin.MANIFEST_FILE)),
		"as an editable text file")
	# Dress the owner's golfer in it, then put the choice back.
	var worn_before := GameManager.player_skin_id
	screen._on_wear_pressed()
	_check(GameManager.player_skin_id == skin.id, "Wear This dresses the owner's golfer")
	screen._on_wear_pressed()
	_check(GameManager.player_skin_id == skin.id, "...only once")
	SaveManager.set_user_preference("gameplay", "player_skin", worn_before)
	GameManager.player_skin_id = worn_before

	var back := _find_button(screen, "BackButton")
	_check(back != null, "the studio has a Back action")
	if back != null:
		await _click(back)
	await _frames(4)
	_check(main.get_node_or_null("UI/HUD/EditGolferSkinsScreen") == null,
		"Back closes the studio")
	_check(main.main_menu.visible, "and the title screen is back")

	_remove_tree(HARNESS_ROOT)
	print("SKIN_EDITOR: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)


## Remove a folder under user:// and everything in it.
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


# =============================================================================
# CHECKS
# =============================================================================

## Everything the studio needs at one window size, as the player sees it.
func _check_studio(screen: EditGolferSkinsScreen, width: float, height: float) -> void:
	_check(screen._skin != null, "a skin is open to paint")
	_check(screen._canvas != null and screen._canvas.layer != null,
		"the painting surface has a layer on it")
	var rect := _canvas_rect(screen)
	_check(rect.size.x > 0.0 and rect.size.y > 0.0, "the canvas has room at %dx%d" % [width, height])
	_check(screen._canvas.cell_size() >= MIN_CELL,
		"one sprite pixel is %.1f screen pixels across (at least %.0f)" % [
			screen._canvas.cell_size(), MIN_CELL])
	_check(rect.position.x >= -0.5 and rect.end.x <= width + 0.5,
		"the canvas is inside the window horizontally")
	_check(screen._frame_strip.get_child_count() > 0, "the frame strip is built")
	_check(screen._group_rows.get_child_count() == screen._skin.group_count(),
		"every Re-color Group has a row")
	_check(screen._palette.get_child_count() == screen._skin.group_count() + 1,
		"the palette offers every group plus None")
	var first_group := screen._group_rows.get_child(0) as Control
	_check(first_group != null and first_group.get_global_rect().size.y >= 24.0,
		"a group row is a big enough target")
	_check(screen._save_button.get_global_rect().size.x >= 40.0, "Save is a real button")
	_check(screen._canvas.active_group > 0, "a group is selected to paint with")

	# The buttons the player cannot do without have to be the control a click
	# lands on - not just to exist and to sit inside the window.
	var tag := "%dx%d" % [int(width), int(height)]
	var save := _find_button(screen, "SaveSkinsButton")
	await _check_reachable(screen, _find_button(screen, "BackButton"), "Back", tag)
	_check(save != null and save.is_visible_in_tree(), "%s: Save Skins is on the screen" % tag)
	await _check_reachable(screen, _find_button(screen, "PixelsModeButton"), "the Pixels switch", tag)
	await _check_reachable(screen, _find_button(screen, "GroupsModeButton"), "the Groups switch", tag)
	# The Colour picker and the group buttons live in the other half of the
	# studio: reach for them there, then come back to Pixels. The layout needs a
	# frame to settle after the switch.
	var mode := screen._mode
	screen._set_mode(EditGolferSkinsScreen.Mode.GROUPS)
	await _frames(2)
	await _check_reachable(screen, screen._group_color_button, "the Colour picker", tag)
	await _check_reachable(screen, _find_button(screen, "NewGroupButton"), "New Group", tag)
	screen._set_mode(mode)
	await _frames(2)
	# The Sprite Set picker was removed: no picker, no row for it.
	_check(screen.find_children("SpritePicker*", "", true, false).is_empty(),
		"%s: there is no Sprite Set picker" % tag)
	var sprite_labels := 0
	for label in screen.find_children("*", "Label", true, false):
		if (label as Label).text.to_lower().contains("sprite set"):
			sprite_labels += 1
	_check(sprite_labels == 0, "%s: and no Sprite Set row" % tag)


## Painting through the screen at the size the window gives the canvas.
func _check_paint(screen: EditGolferSkinsScreen, tag: String) -> void:
	var layer: GolferSkinLayer = screen._canvas.layer
	var cell := _free_cell(screen)
	_check(cell.x >= 0, "%s: the sprite has a pixel to paint" % tag)
	var group := screen._canvas.active_group
	screen._on_cell_painted(cell)
	_check(layer.get_cell(cell.x, cell.y) == group,
		"%s: clicking a pixel gives it to the active group" % tag)
	screen._on_cell_erased(cell)
	_check(layer.get_cell(cell.x, cell.y) == GolferSkinLayer.NO_GROUP,
		"%s: right-clicking frees it again" % tag)
	screen._on_cell_painted(cell)
	# One click with the Fill tool takes the whole run of pixels it lands in.
	var filled_from := _cell_of_another_group(screen, group)
	if filled_from.x >= 0:
		var run := screen._canvas.layer.flood_cells(filled_from.x, filled_from.y, screen._canvas.image)
		var before := screen._canvas.layer.count(group)
		screen._on_fill_toggled(true)
		screen._on_cell_painted(filled_from)
		screen._on_fill_toggled(false)
		_check(screen._canvas.layer.count(group) == before + run.size(),
			"%s: Fill takes the whole run (%d pixels) in one click" % [tag, run.size()])

	# Re-colouring is checked on a pixel the artwork actually draws - a
	# transparent pixel stays transparent whatever colour its group takes (see
	# GolferSkinLayer.recolor) - and that the active group now owns, whichever
	# skin is open (the Beginner art has groups that own almost no pixels yet).
	var marked := _drawn_cell(screen)
	_check(marked.x >= 0, "%s: the sprite has a drawn pixel" % tag)
	screen._on_cell_painted(marked)
	screen._on_group_color_chosen(Color(0.25, 0.75, 0.35))
	var painted := screen._canvas.preview_image.get_pixel(marked.x, marked.y)
	_check(painted.g > painted.r and painted.g > painted.b,
		"%s: the re-coloured sprite shows the group's new colour" % tag)


## Pixels mode and Groups mode are two sides of the same studio: the pixel
## controls give way to the group editor, the canvas stays up to show and pick
## the groups, and the switch goes back and forth.
func _check_mode_switch(screen: EditGolferSkinsScreen) -> void:
	screen._set_mode(EditGolferSkinsScreen.Mode.PIXELS)
	_check(screen._pixel_block.visible and not screen._group_block.visible,
		"Pixels mode shows the painting controls and hides the group editor")
	_check(screen._recolor_check.visible and screen._fill_check.visible,
		"with the Re-coloured and Fill switches on hand")
	_check(screen._groups_mode_button != null and not screen._groups_mode_button.button_pressed,
		"and the Pixels switch lit")

	await _click(screen._groups_mode_button)
	_check(screen._mode == EditGolferSkinsScreen.Mode.GROUPS,
		"clicking the Groups switch changes mode")
	_check(screen._group_block.visible and not screen._pixel_block.visible,
		"Groups mode shows the group editor and hides the painting controls")
	_check(not screen._recolor_check.visible and not screen._fill_check.visible,
		"the painting switches stand down")
	_check(screen._group_rows.get_child_count() == screen._skin.group_count(),
		"every Re-color Group still has a row")
	_check(not screen._canvas.show_recolor,
		"the canvas drops the re-colour wash so the groups are read off the artwork")

	# A click on the sprite in Groups mode picks the group the pixel belongs to,
	# which is how the player reads which group a part of the sprite is.
	var picked := _cell_of_another_group(screen, screen._canvas.active_group)
	if picked.x >= 0:
		var owned_by := screen._skin.layer(screen._current_key()).get_cell(picked.x, picked.y)
		screen._on_cell_picked(picked)
		_check(screen._canvas.active_group == owned_by,
			"clicking the sprite selects the group under the pixel")
		_check(screen._group_rows.get_child_count() > 0, "and the row list follows the selection")

	await _click(screen._pixels_mode_button)
	_check(screen._mode == EditGolferSkinsScreen.Mode.PIXELS, "clicking Pixels comes back")
	_check(screen._pixel_block.visible and screen._canvas.show_recolor,
		"and the painting surface is back to the re-coloured sprite")


## The Colour button opens a picker (it is a ColorPickerButton, which brings its
## own popup) and the colour is written to the group of the open skin.
func _check_groups(screen: EditGolferSkinsScreen) -> void:
	_check(screen._group_color_button is ColorPickerButton,
		"the Colour button is a picker that opens its own popup")
	screen._set_mode(EditGolferSkinsScreen.Mode.GROUPS)
	var group := screen._active_group
	if group == GolferSkinLayer.NO_GROUP:
		for entry in screen._skin.group_list():
			group = int(entry.get("id", 0))
			break
	_check(group != GolferSkinLayer.NO_GROUP, "a Re-color Group is selected to edit")
	if group == GolferSkinLayer.NO_GROUP:
		return
	screen._on_group_row_pressed(group)
	# Clicking Colour opens a real picker (the old ColorPicker.popup() call was
	# what broke this), and the colour it hands back reaches the group.
	await _click(screen._group_color_button)
	var picker := (screen._group_color_button as ColorPickerButton).get_popup()
	_check(picker != null and picker.visible, "clicking Colour opens the colour picker")
	if picker != null:
		picker.hide()
		await _frames(1)
	var wanted := Color(0.2, 0.6, 0.9)
	screen._on_group_color_chosen(wanted)
	_check(screen._skin.group_by_id(group).get("color").is_equal_approx(wanted),
		"picking a colour re-colours the group")
	_check(screen._dirty, "and leaves the skin to be saved")
	var swatch := screen._group_color_button as ColorPickerButton
	_check(swatch.color.is_equal_approx(wanted), "and the picker shows the group's colour")

	# New group, rename it, then delete it again: the three group actions.
	var before := screen._skin.group_count()
	screen._on_new_group_pressed()
	_check(screen._skin.group_count() == before + 1, "New Group adds a Re-color Group")
	var added := screen._skin.group_list()[screen._skin.group_count() - 1]
	var id := int(added.get("id"))
	screen._active_group = id
	screen._on_group_name_submitted("Collars")
	_check(str(screen._skin.group_by_id(id).get("name")) == "Collars", "the name field renames it")
	screen._active_group = id
	# Deleting a group asks first (see _confirm): answer the dialog and check it
	# warned about the pixels it would free.
	screen.confirm_callback = func(message: String, _confirm_text: String) -> bool:
		_prompts.append(message)
		return true
	_prompts.clear()
	screen._on_delete_group_pressed()
	screen.confirm_callback = Callable()
	_check(_prompts.size() == 1 and _prompts[0].contains("Collars"),
		"Delete asks before freeing a group's pixels (got %s)" % str(_prompts))
	_check(screen._skin.group_by_id(id).is_empty(), "and removes it once confirmed")
	screen._set_mode(EditGolferSkinsScreen.Mode.PIXELS)


## Opening the shipped skins and the player's own, as the list does.
func _check_open_skin(screen: EditGolferSkinsScreen) -> void:
	var ids := screen.library.skin_ids()
	_check(ids.size() >= 2, "the shipped skins are listed: %s" % str(ids))
	for index in screen._skin_list.item_count:
		var listed: String = screen._skin_list.get_item_text(index)
		if listed.begins_with("Beginner"):
			screen._on_skin_selected(index)
			break
	_check(screen._skin.id == "beginner",
		"picking another skin opens it (got %s)" % screen._skin.id)
	_check(screen._canvas.layer == screen._skin.layer(screen._current_key()),
		"and the canvas paints the new skin's layer")


## A pixel of the sprite that belongs to some group other than this one.
func _cell_of_another_group(screen: EditGolferSkinsScreen, group: int) -> Vector2i:
	for y in 48:
		for x in 48:
			var owned_by := screen._canvas.layer.get_cell(x, y)
			if owned_by != GolferSkinLayer.NO_GROUP and owned_by != group:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## A pixel the artwork draws in a colour dark or bright enough to keep a
## shade of it (fully transparent and pitch black pixels are both skipped).
func _drawn_cell(screen: EditGolferSkinsScreen) -> Vector2i:
	var image := screen._canvas.image
	for y in 48:
		for x in 48:
			var color := image.get_pixel(x, y)
			if color.a > 0.2 and maxf(color.r, maxf(color.g, color.b)) > 0.15:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## The first pixel of the sprite that belongs to no group.
func _free_cell(screen: EditGolferSkinsScreen) -> Vector2i:
	for y in 48:
		for x in 48:
			if screen._canvas.layer.get_cell(x, y) == GolferSkinLayer.NO_GROUP:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _canvas_rect(screen: EditGolferSkinsScreen) -> Rect2:
	return screen._canvas.get_global_rect()

## True when any control under the screen reaches past the window's right edge.
func _overflows_horizontally(screen: EditGolferSkinsScreen) -> bool:
	var limit := float(get_window().size.x)
	var offenders: PackedStringArray = []
	_walk(screen, limit, offenders)
	for offender in offenders:
		print("  overflows: ", offender)
	return not offenders.is_empty()

func _walk(node: Node, limit: float, offenders: PackedStringArray) -> void:
	if node is Control and (node as Control).is_visible_in_tree():
		var rect := (node as Control).get_global_rect()
		# Controls inside a scroll container are allowed to be wider than the
		# window as long as the container scrolls (it does not, in the phone
		# arrangement: it is built to fit).
		if rect.end.x > limit + 1.0 and not _inside_scroll(node):
			offenders.append("%s %s" % [node.name, rect])
	for child in node.get_children():
		_walk(child, limit, offenders)

func _inside_scroll(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false

## True when a click at the button's centre would land on the button (or one of
## its own children) rather than on something drawn over it. A button below the
## fold of a scrolling column is reachable: the harness scrolls to it first, the
## way the player would.
func _check_reachable(root: Control, button: Button, description: String, tag: String) -> void:
	if button == null:
		_check(false, "%s: %s is on the screen" % [tag, description])
		return
	_check(button.is_visible_in_tree() and not button.disabled,
		"%s: %s is enabled and shown" % [tag, description])
	await _scroll_into_view(button)
	var rect := button.get_global_rect()
	var centre := rect.position + rect.size * 0.5
	var hit := _topmost(root, centre)
	# _topmost returns "<name>:<class>"; the click reaches the button when the
	# winner is the button itself or a control inside it (a picker draws its own
	# swatch, so the hit may be a child of the button).
	var owner_name := hit.split(":")[0]
	var landed := owner_name == str(button.name)
	if not landed and button.is_ancestor_of(_find_node_named(root, owner_name)):
		landed = true
	_check(landed, "%s: a click at %s lands on %s (got %s)" % [
		tag, centre.round(), description, hit])


## Put a control inside the window by scrolling every column above it, then give
## the layout a frame to settle before it is hit-tested.
func _scroll_into_view(control: Control) -> void:
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			(parent as ScrollContainer).ensure_control_visible(control)
		parent = parent.get_parent()
	await _frames(2)


func _find_node_named(root: Node, wanted: String) -> Node:
	for node in root.find_children(wanted, "", true, false):
		return node
	return null


## The topmost Control that would receive a click at this global point, walking
## the tree in reverse draw order (last child on top) and honouring clipping.
func _topmost(root: Control, global_point: Vector2) -> String:
	var clip := root.get_global_rect()
	var children := root.get_children()
	for i in range(children.size() - 1, -1, -1):
		var child := children[i]
		if not (child is Control) or not child.is_visible_in_tree():
			continue
		var control := child as Control
		var rect: Rect2 = control.get_global_rect()
		var allowed := clip.intersection(rect) if control.clip_contents else clip
		if not (allowed.has_point(global_point) and rect.has_point(global_point)):
			continue
		var deeper := _topmost(control, global_point)
		if not deeper.is_empty():
			return deeper
		if control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return "%s:%s" % [control.name, control.get_class()]
	if root.get_global_rect().has_point(global_point) \
			and root.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return "%s:self" % root.name
	return ""


func _find_button(root: Node, button_name: String) -> Button:
	for node in root.find_children(button_name, "", true, false):
		if node is Button:
			return node as Button
	return null
