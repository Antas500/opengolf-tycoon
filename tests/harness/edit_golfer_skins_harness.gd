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
## done at all: a canvas a few pixels wide, or a Save button pushed off the
## window, would pass every unit test and still be useless.
##
## Prints one PASS/FAIL line per check and exits non-zero on any failure.

## The sprite is 48x48; a cell this small or smaller is not paintable.
const MIN_CELL := 3.0
## The harness paints into a folder of its own, so running it never touches the
## skins the player has made.
const HARNESS_ROOT := "user://harness_golfer_skins"

var main: Node
var failures := 0

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
	_check_studio(screen, 1600.0, 1000.0)
	_check_paint(screen, "desktop")
	_check_open_skin(screen)

	# ------------------------------------------------------------------
	# Tablet: the lists share a row above the studio.
	# ------------------------------------------------------------------
	await _set_window(1024, 768)
	await _frames(4)
	_check(screen._layout_mode == EditGolferSkinsScreen.Layout.TABLET,
		"1024x768 uses the tablet arrangement (got %d)" % screen._layout_mode)
	_check_studio(screen, 1024.0, 768.0)
	_check_paint(screen, "tablet")

	# ------------------------------------------------------------------
	# Phone: one column, nothing wider than the window, canvas still usable.
	# ------------------------------------------------------------------
	await _set_window(390, 844)
	await _frames(4)
	_check(screen._layout_mode == EditGolferSkinsScreen.Layout.PHONE,
		"390x844 uses the phone arrangement (got %d)" % screen._layout_mode)
	_check_studio(screen, 390.0, 844.0)
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
	screen._on_save_pressed()
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
		back.emit_signal("pressed")
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

func _find_button(root: Node, button_name: String) -> Button:
	for node in root.find_children(button_name, "", true, false):
		if node is Button:
			return node as Button
	return null
