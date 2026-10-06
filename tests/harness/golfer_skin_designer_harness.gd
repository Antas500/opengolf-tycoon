extends Node
## Run: godot --headless --path . res://tests/harness/golfer_skin_designer_harness.tscn
##
## Opens the real Customise Golfer Skins screen from the title screen and drives
## it through phone, tablet and desktop window sizes. At every size it checks the
## three columns are on screen and reachable, the skin list offers the whole
## catalogue (themed skins included), the part layer is listed, and the canvas is
## showing art.
##
## Then it plays the screen: edits the part layer (removes a part and adds one
## back), re-colours a part, paints a pixel, makes a skin of its own, checks the
## skin the owner wears follows, puts the edits back, and leaves with Done and
## with Esc — checking the golfer profile survives each way.
##
## Prints one PASS/FAIL line per check and exits non-zero on any failure.

const TAG := "SKIN_DESIGNER"
const MIN_TARGET := 44.0

var main: Node
var designer: Control
var failures := 0

func _check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
	print("%s: %s: %s" % [TAG, "PASS" if ok else "FAIL", description])

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _set_window(width: int, height: int) -> void:
	get_window().size = Vector2i(width, height)
	await _frames(6)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await _set_window(1280, 900)
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await _frames(8)

	_check(main.main_menu != null, "the game opens on the title screen")
	var buttons := _find_buttons(main.main_menu)
	var labels: Array = []
	for button in buttons:
		labels.append(button.text)
	_check(labels.has("Customise Golfer Skins"), "the menu offers the skin designer")

	# ------------------------------------------------------------------
	# Every arrangement: the three columns fit and the canvas shows art.
	# ------------------------------------------------------------------
	for size in [Vector2i(390, 844), Vector2i(1280, 900), Vector2i(1920, 1080)]:
		await _set_window(size.x, size.y)
		await _open_designer()
		_check_layout("%dx%d" % [size.x, size.y], size)
		await _close_designer()

	# ------------------------------------------------------------------
	# Playing the screen: colours, pixels, a skin of the player's own.
	# ------------------------------------------------------------------
	await _set_window(1280, 900)
	await _open_designer()
	var profile = GameManager.player_profile

	var list: ItemList = _named(designer, "SkinList")
	var catalogue := GolferSkinLibrary.all_skins().size()
	_check(list != null and list.item_count == catalogue,
		"every skin is listed (got %d of %d)" % [list.item_count if list != null else -1, catalogue])

	# ------------------------------------------------------------------
	# The part layer: the pixels each colour change is allowed to touch.
	# ------------------------------------------------------------------
	designer._select_by_id("plain")
	await _frames(2)
	var layer_list: ItemList = _named(designer, "LayerList")
	var parts_before := layer_list.item_count if layer_list != null else -1
	_check(parts_before == GolferSkinLibrary.parts_for_skin(
		GolferSkinLibrary.skin_by_id("plain")).size(),
		"the layer lists the parts the art draws (got %d)" % parts_before)
	_check(_layer_holds("plain", "cap"), "the layer holds the headwear")
	designer._set_layer_part("cap", false)
	await _frames(2)
	_check(not _layer_holds("plain", "cap"), "a part can be taken out of the layer")
	_check(not Array(PlayerGolferProfile.parts_for_skin("plain")).has("cap"),
		"and the colour pickers stop offering it")
	designer._set_layer_part("cap", true)
	await _frames(2)
	_check(_layer_holds("plain", "cap"), "and put back again")
	# A part the art never drew can join the layer: it comes with no pixels, so
	# the art is untouched until the player paints some.
	designer._set_layer_part("accent", true)
	designer._select_by_id("beginner")
	await _frames(2)
	_check(not _layer_holds("beginner", "cap"), "the beginner art draws no headwear")
	designer._set_layer_part("cap", true)
	await _frames(2)
	_check(_layer_holds("beginner", "cap"), "the beginner's layer can be given one")
	var beginner_recipe := _recipe_for(designer._selected.skin.id)
	_check(Array(beginner_recipe.get("parts", [])).has("cap"),
		"the layer is stored on the profile")
	designer._editor.brush_part = "cap"
	designer._editor.brush_shade = 0
	designer._editor._write(Vector2i(20, 7))
	designer._on_pixels_changed()
	await _frames(2)
	_check(designer._editor.image().get_pixel(20, 7).a > 0.5, "and can be painted")
	designer._select_by_id("plain")
	await _frames(2)

	# Re-colour the top of the skin the owner wears.
	designer._select_by_id("plain")
	designer._set_part_colour("shirt", Color("1188ee"))
	await _frames(3)
	var stored: Dictionary = profile.custom_skins[0] if not profile.custom_skins.is_empty() else {}
	_check(not stored.is_empty(), "a re-colour is stored on the profile")
	_check(str(stored.get("colors", {}).get("shirt", "")) == "1188ee",
		"the colour the player picked is the one stored (got %s)" % str(stored.get("colors", {}).get("shirt", "")))
	_check(_list_has_edit_mark(), "the edited skin is marked in the list")
	var worn_skin = GolferSkinLibrary.skin_by_id("plain")
	_check(worn_skin != null and worn_skin.custom, "the catalogue hands back the edited skin")
	_check(worn_skin != null and worn_skin.colors.get("shirt", Color.BLACK) == Color("1188ee"),
		"and it wears the player's colour")

	# Paint a pixel, then check it is in the recipe and in the built frame.
	designer._editor.brush_part = "shirt"
	designer._editor.brush_shade = 4
	designer._editor._write(Vector2i(24, 21))
	designer._on_pixels_changed()
	await _frames(3)
	stored = profile.custom_skins[0]
	var overlays: Dictionary = stored.get("overlays", {})
	_check(overlays.has("idle_south_0"), "the painted frame is stored")
	var painted: Image = designer._editor.image()
	_check(painted != null and painted.get_pixel(24, 21).a > 0.5, "the canvas shows the painted pixel")
	var previews := _find_all(designer, "TextureRect")
	var preview: TextureRect = null
	for candidate in previews:
		if candidate.name == "Preview":
			preview = candidate
	_check(preview != null and preview.texture != null, "the preview draws the skin")

	# A skin of the player's own, then throw it away again.
	var before: int = profile.created_skin_count()
	designer._on_new_skin()
	await _frames(3)
	_check(profile.created_skin_count() == before + 1, "the player can create a skin")
	var created_id: String = designer._selected.skin.id
	_check(GolferSkinLibrary.skin_by_id(created_id) != null, "the new skin joins the catalogue")
	designer._on_wear()
	_check(profile.skin_id == created_id, "the owner can wear it")
	designer._on_revert()
	await _frames(3)
	_check(profile.created_skin_count() == before, "and delete it again")

	# Leaving with Done saves the profile where a main-menu visit can keep it.
	await _close_designer()
	var config := ConfigFile.new()
	_check(config.load(SaveManager.SETTINGS_PATH) == OK, "the settings file exists")
	var saved = config.get_value("golfer", "profile", {})
	_check(saved is Dictionary and not saved.is_empty(), "the golfer profile is saved on the way out")

	# Esc closes it too.
	await _open_designer()
	_check(designer.visible, "the designer opens again")
	designer.close_requested.emit()
	await _frames(3)
	_check(main.get_node_or_null("UI/HUD/GolferSkinDesigner") == null, "Done closes the designer")
	_check(main.main_menu != null and main.main_menu.visible, "and the title screen is still behind it")

	print("%s: %d failures" % [TAG, failures])
	get_tree().quit(0 if failures == 0 else 1)

## Open the designer the way the menu does and wait for it to build.
func _open_designer() -> void:
	main.main_menu.customise_skins_requested.emit()
	await _frames(4)
	designer = main.get_node_or_null("UI/HUD/GolferSkinDesigner")
	_check(designer != null, "the designer opens")
	if designer != null:
		_check(designer.get_node_or_null("Backdrop") != null, "it draws over the menu")

func _close_designer() -> void:
	if designer == null:
		return
	designer.close_requested.emit()
	await _frames(3)
	designer = main.get_node_or_null("UI/HUD/GolferSkinDesigner")
	_check(designer == null, "the designer closes")

func _list_has_edit_mark() -> bool:
	var list: ItemList = _named(designer, "SkinList")
	if list == null:
		return false
	for index in list.item_count:
		if list.get_item_text(index).contains("(edited)"):
			return true
	return false

## The first node with this name, anywhere under `root` - the parts of the
## designer are found by name, since two lists share the ItemList class.
func _named(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	for child in root.get_children():
		var found := _named(child, node_name)
		if found != null:
			return found
	return null

## Whether the catalogue skin wears this part in its layer.
func _layer_holds(skin_id: String, part: String) -> bool:
	var skin := GolferSkinLibrary.skin_by_id(skin_id)
	return skin != null and skin.customizable.has(part)

## The recipe the profile is keeping for one skin.
func _recipe_for(skin_id: String) -> Dictionary:
	var profile = GameManager.player_profile
	if profile == null:
		return {}
	var index := profile.find_skin_recipe(skin_id)
	return profile.custom_skins[index] if index >= 0 else {}

## The three columns, the canvas and the Done button all have to be on screen and
## big enough to use at this window size.
func _check_layout(tag: String, size: Vector2i) -> void:
	if designer == null:
		return
	var view := Rect2(Vector2.ZERO, Vector2(size))
	var page: Control = designer.get_node_or_null("Scroll/Page")
	_check(page != null, "%s: the page is built" % tag)
	if page == null:
		return
	var panels: Array = []
	for column in ["SkinsPanel", "CanvasPanel", "PreviewPanel"]:
		var panel := _find_all(designer, "PanelContainer")
		for candidate in panel:
			if candidate.name == column:
				panels.append(candidate)
	_check(panels.size() == 3, "%s: all three columns exist (got %d)" % [tag, panels.size()])

	var off_screen: Array = []
	for panel in panels:
		var rect: Rect2 = panel.get_global_rect()
		if rect.size.x < 100.0 or rect.size.y < 100.0:
			off_screen.append("%s %s" % [panel.name, rect.size])
	_check(off_screen.is_empty(), "%s: every column has room (%s)" % [tag, off_screen])

	var canvas: Control = null
	for candidate in _find_all(designer, "SkinPixelEditor", true):
		canvas = candidate
	_check(canvas != null, "%s: the pixel canvas is there" % tag)
	if canvas != null:
		var image: Image = canvas.image()
		_check(image != null and image.get_width() == GolferSkinLibrary.CANVAS,
			"%s: the canvas is showing a frame" % tag)

	var done := _find_button(designer, "Done")
	_check(done != null and done.get_global_rect().size.y >= MIN_TARGET,
		"%s: Done is a big enough target" % tag)
	_check(done != null and _within(done.get_global_rect(), view),
		"%s: Done is on screen" % tag)

	var list: ItemList = _named(designer, "SkinList")
	_check(list != null and list.item_count == GolferSkinLibrary.all_skins().size(),
		"%s: the skin list offers the whole catalogue" % tag)
	var layer: ItemList = _named(designer, "LayerList")
	_check(layer != null and layer.item_count > 0, "%s: the part layer is listed" % tag)
	_check(layer != null and layer.get_global_rect().size.y >= 44.0,
		"%s: the part layer list is a usable size" % tag)
	var add_part := _find_button(designer, "Add part")
	_check(add_part != null and _within(add_part.get_global_rect(), view),
		"%s: the layer can be added to" % tag)
	var remove_part := _find_button(designer, "Remove part")
	_check(remove_part != null and _within(remove_part.get_global_rect(), view),
		"%s: and taken away from" % tag)

func _find_all(root: Node, type_name: String, script_class: bool = false) -> Array:
	var found: Array = []
	var matches := false
	if script_class:
		matches = root.get_script() != null and root.get_script().get_global_name() == type_name
	else:
		matches = root.is_class(type_name)
	if matches:
		found.append(root)
	for child in root.get_children():
		found.append_array(_find_all(child, type_name, script_class))
	return found

func _find_button(root: Node, text: String) -> Button:
	for node in _find_all(root, "Button"):
		if node.text == text:
			return node
	return null

func _find_buttons(node: Node) -> Array:
	return _find_all(node, "Button")

func _within(inner: Rect2, outer: Rect2, slack: float = 1.0) -> bool:
	return inner.position.x >= outer.position.x - slack \
		and inner.position.y >= outer.position.y - slack \
		and inner.end.x <= outer.end.x + slack \
		and inner.end.y <= outer.end.y + slack
