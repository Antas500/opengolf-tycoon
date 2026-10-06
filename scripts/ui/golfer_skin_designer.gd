extends Control
class_name GolferSkinDesigner
## GolferSkinDesigner - the Customise Golfer Skins screen.
##
## Three columns: every skin the game knows on the left, the pixel canvas in the
## middle, and a live preview with the part colour pickers on the right.
##
##  * Selecting a skin loads its art *and its part layer* - the byte-per-pixel
##    record that says which body part each pixel was drawn as. The layer is
##    what re-colouring follows: changing the top's colour repaints the pixels
##    the layer tags as the top and nothing else.
##  * The player can edit that layer: **Add part** puts a part into it (so a
##    skin of their own can carry a part its art never drew, and can be
##    re-coloured in it), **Remove part** takes one out. Selecting a part in the
##    list arms the pixel brush with it.
##  * Beyond that they can re-colour the parts, paint pixels frame by frame, or
##    press New Skin to fork the selected skin into one of their own.
##  * Edits are written to the owner's profile as they are made (a recipe per
##    skin: the parts its layer holds, the colours they changed plus a
##    part+shade index per painted pixel), so the golfer is wearing the change
##    the moment the player looks at the course - and it is saved with the game.
##  * A shipped skin that has been painted can be put back with "Revert", and a
##    skin of the player's own can be deleted.
##
## The screen is built from code, in the same house style as the rest of the UI:
## one drawn palette, no textures, and a layout that reflows between a wide
## three-column desk and a single stacked column on a phone.

signal close_requested

const BREAKPOINT := 980.0
const LEFT_WIDTH := 240
const RIGHT_WIDTH := 300

var _catalogue: Array = []
## True while the list is being rebuilt, so its own select() cannot be mistaken
## for the player picking a skin.
var _updating_list := false
var _selected: GolferSkinDesigner.SkinSelection = null
var _anim := "idle"
var _direction := "south"
var _frame := 0

var _skins_list: ItemList = null
var _name_edit: LineEdit = null
var _new_button: Button = null
var _duplicate_button: Button = null
var _revert_button: Button = null
var _use_button: Button = null
var _status: Label = null
var _anim_picker: OptionButton = null
var _direction_picker: OptionButton = null
var _frame_row: HBoxContainer = null
var _editor: SkinPixelEditor = null
var _part_row: HFlowContainer = null
var _shade_row: HFlowContainer = null
var _colour_picker: ColorPickerButton = null
var _colour_label: Label = null
var _preview: TextureRect = null
var _preview_frames: SpriteFrames = null
var _preview_small: TextureRect = null
var _preview_timer: Timer = null
var _preview_frame := 0
var _layer_list: ItemList = null
var _layer_add_picker: OptionButton = null
var _layer_note: Label = null
## True while the part layer list is being rebuilt, so its own select() cannot
## be mistaken for the player picking a part.
var _updating_layer := false
var _columns: Array[Control] = []
var _dirty_note := ""


## One entry of the designer: a skin, and the recipe the player is building for
## it. `recipe` is what gets stored on the profile.
class SkinSelection extends RefCounted:
	var skin: GolferSkinLibrary.SkinDef = null
	var recipe: Dictionary = {}
	var created: bool = false

	func display_name() -> String:
		if skin == null:
			return "?"
		return skin.name + (" (yours)" if created else "")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	reload()
	_resize_to_window()
	if has_node("/root/Screen"):
		Screen.changed.connect(_on_screen_changed)


func _exit_tree() -> void:
	if has_node("/root/Screen") and Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.disconnect(_on_screen_changed)


func _on_screen_changed(window_size: Vector2, _world_scale: float) -> void:
	var wanted := window_size.x >= BREAKPOINT
	if wanted != _wide:
		_wide = wanted
		_rebuild_body()


## ── State ────────────────────────────────────────────────────────────────

## Read the catalogue and start on the skin the owner is wearing (or the first
## one, before a profile exists).
func reload() -> void:
	GolferSkinLibrary.invalidate_catalogue()
	_catalogue = GolferSkinLibrary.all_skins()
	var wanted := GolferSkinLibrary.default_skin_id()
	var profile = GameManager.player_profile
	if profile != null and not profile.skin_id.is_empty():
		wanted = profile.skin_id
	_select_by_id(wanted)


func _select_by_id(id: String) -> void:
	for index in _catalogue.size():
		if _catalogue[index].id == id:
			_select_index(index)
			return
	if not _catalogue.is_empty():
		_select_index(0)


func _select_index(index: int) -> void:
	if index < 0 or index >= _catalogue.size():
		return
	var selected := SkinSelection.new()
	selected.skin = _catalogue[index]
	selected.created = not GolferSkinLibrary.is_shipped(selected.skin.id)
	selected.recipe = _working_recipe(selected.skin)
	_selected = selected
	_anim = "idle"
	_direction = "south"
	_frame = 0
	_dirty_note = ""
	if _skins_list != null and _skins_list.item_count > index:
		# The list is refilled from the catalogue a moment later; selecting a row
		# that does not exist yet is not an error worth raising.
		_skins_list.select(index)
	_refresh_everything()


## The recipe the player is editing: the one already stored for this skin, or a
## fresh (empty) one for a skin they have not touched.
func _working_recipe(skin: GolferSkinLibrary.SkinDef) -> Dictionary:
	var profile = GameManager.player_profile
	if profile != null:
		var index := profile.find_skin_recipe(skin.id)
		if index >= 0:
			# A skin the player made carries its own palette; an edit of a
			# shipped skin is stored as just the changes.
			return profile.custom_skins[index].duplicate(true)
	var recipe := {
		"id": skin.id, "name": skin.name, "description": skin.description,
		"base": skin.id if GolferSkinLibrary.is_shipped(skin.id) else skin.base_id,
		"colors": {}, "overlays": {}, "revision": 0,
	}
	if not GolferSkinLibrary.is_shipped(skin.id):
		for part in skin.colors:
			var colour: Color = skin.colors[part]
			recipe["colors"][part] = colour.to_html(false)
	return recipe


## The skin as the catalogue has it right now. Every edit rebuilds the
## catalogue, so the skin the designer started from can be a revision out of
## date - and its part layer with it.
func _current_skin() -> GolferSkinLibrary.SkinDef:
	if _selected == null:
		return null
	var fresh := GolferSkinLibrary.skin_by_id(_selected.skin.id)
	return fresh if fresh != null else _selected.skin


func _working_skin() -> GolferSkinLibrary.SkinDef:
	if _selected == null:
		return null
	var current := _current_skin()
	var skin := GolferSkinLibrary.SkinDef.from_recipe(_selected.recipe)
	if GolferSkinLibrary.is_shipped(current.id):
		skin.id = current.id
		skin.name = current.name
		skin.description = current.description
		skin.root = current.root
		skin.legacy = current.legacy
		skin.custom = true
		skin.base_id = current.id
		# The layer the player is building: the recipe's own parts when it has
		# them, the art's when the recipe is fresh (see SkinDef.parts_from_recipe).
		if not skin.parts_from_recipe:
			skin.customizable = current.customizable
		for part in current.colors:
			if not skin.colors.has(part):
				skin.colors[part] = current.colors[part]
	else:
		skin.custom = true
		skin.inherit_from(current)
	return skin


## Store the working recipe on the profile and refresh everything that shows it.
func _commit(note: String = "") -> void:
	if _selected == null:
		return
	var profile = GameManager.player_profile
	if profile == null:
		return
	_selected.recipe["revision"] = int(_selected.recipe.get("revision", 0)) + 1
	profile.store_custom_skin(_selected.recipe)
	GolferSkinLibrary.invalidate_catalogue()
	GolferSkinLibrary.invalidate(_selected.skin.id)
	_dirty_note = note
	_catalogue = GolferSkinLibrary.all_skins()


## ── UI ───────────────────────────────────────────────────────────────────

var _wide := true
var _title: Label = null
var _hint: Label = null
var _page: MarginContainer = null
var _body: HBoxContainer = null
var _left: PanelContainer = null
var _middle: PanelContainer = null
var _right: PanelContainer = null


func _resize_to_window() -> void:
	_wide = _window_size().x >= BREAKPOINT
	_rebuild_body()


func _window_size() -> Vector2:
	if has_node("/root/Screen"):
		return Screen.window_size
	return get_viewport().get_visible_rect().size


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.05, 0.07, 0.06, 0.97)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(scroll)

	_page = MarginContainer.new()
	_page.name = "Page"
	_page.custom_minimum_size = _window_size()
	scroll.add_child(_page)
	for side in ["left", "right", "top", "bottom"]:
		_page.add_theme_constant_override("margin_" + side, 18)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 12)
	_page.add_child(column)

	column.add_child(_make_header())
	_body = HBoxContainer.new()
	_body.name = "Body"
	_body.add_theme_constant_override("separation", 12)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_body)

	_left = _make_left_panel()
	_middle = _make_middle_panel()
	_right = _make_right_panel()
	_columns = [_left, _middle, _right]
	_rebuild_body()

	_status = Label.new()
	_status.name = "Status"
	_status.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_status.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_set_status("Pick a skin, then re-colour a part of its layer or paint its pixels. Changes are saved as you make them.")


func _rebuild_body() -> void:
	if _body == null:
		return
	# The header has to fit too: on a phone the long title and the count of
	# skins give way to the Done button.
	if _title != null:
		_title.text = "Customise Golfer Skins" if _wide else "Golfer Skins"
		_title.add_theme_font_size_override("font_size",
			UIConstants.FONT_SIZE_XL if _wide else UIConstants.FONT_SIZE_LG)
	if _hint != null:
		_hint.visible = _wide
	# A phone has no room for a 384 px canvas beside anything: the art and the
	# preview shrink to the column width instead of forcing the page sideways.
	if _editor != null and _editor.zoom > 4 and not _wide:
		_editor.set_zoom(4)
	if _preview != null:
		_preview.custom_minimum_size = Vector2(144, 144) if _wide else Vector2(96, 96)
	if _skins_list != null:
		_skins_list.custom_minimum_size = Vector2(0, 220) if _wide else Vector2(0, 160)
	for column in _columns:
		if column.get_parent() != null:
			column.get_parent().remove_child(column)
	if _wide:
		_body.add_child(_left)
		_body.add_child(_middle)
		_body.add_child(_right)
		_left.custom_minimum_size = Vector2(LEFT_WIDTH, 0)
		_right.custom_minimum_size = Vector2(RIGHT_WIDTH, 0)
		_middle.custom_minimum_size = Vector2(420, 0)
		_body.add_theme_constant_override("separation", 12)
	else:
		var stack := VBoxContainer.new()
		stack.name = "Stack"
		stack.add_theme_constant_override("separation", 12)
		_body.add_child(stack)
		for column in _columns:
			stack.add_child(column)
			column.custom_minimum_size = Vector2(0, 0)
		_middle.custom_minimum_size = Vector2(0, 420)


func _make_header() -> Control:
	var row := HBoxContainer.new()
	row.name = "Header"
	row.add_theme_constant_override("separation", 12)

	_title = Label.new()
	_title.name = "Title"
	_title.text = "Customise Golfer Skins"
	_title.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XL)
	_title.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_title)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = "Re-colour a part, or edit the layer of parts behind it"
	_hint.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_hint.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_hint)

	var done := Button.new()
	done.name = "DoneButton"
	done.text = "Done"
	done.custom_minimum_size = Vector2(120, 44)
	done.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	done.pressed.connect(func(): close_requested.emit())
	row.add_child(done)
	return row


func _make_panel(node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.12, 0.1, 0.96)
	style.border_color = UIConstants.COLOR_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_MD)
	label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT)
	return label


func _make_left_panel() -> PanelContainer:
	var panel := _make_panel("SkinsPanel")
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	column.add_child(_section_label("Golfer skins"))

	_skins_list = ItemList.new()
	_skins_list.name = "SkinList"
	_skins_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skins_list.custom_minimum_size = Vector2(0, 220)
	_skins_list.item_selected.connect(_on_skin_selected)
	column.add_child(_skins_list)

	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_name_edit.placeholder_text = "Skin name"
	_name_edit.max_length = PlayerGolferProfile.MAX_SKIN_NAME
	_name_edit.text_submitted.connect(func(_value: String): _on_name_changed())
	_name_edit.focus_exited.connect(_on_name_changed)
	column.add_child(_name_edit)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)

	_new_button = _small_button("New skin", _on_new_skin, "Start a skin of your own, forked from the one selected")
	row.add_child(_new_button)
	_duplicate_button = _small_button("Duplicate", _on_duplicate, "Copy the selected skin so its pixels can be painted")
	row.add_child(_duplicate_button)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	column.add_child(row2)
	_revert_button = _small_button("Revert", _on_revert, "Throw away your edits to this skin")
	row2.add_child(_revert_button)
	_use_button = _small_button("Wear it", _on_wear, "Play in this skin")
	row2.add_child(_use_button)

	column.add_child(_section_label("Part layer"))
	_layer_note = Label.new()
	_layer_note.name = "LayerNote"
	_layer_note.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	_layer_note.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	_layer_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_layer_note)

	_layer_list = ItemList.new()
	_layer_list.name = "LayerList"
	_layer_list.custom_minimum_size = Vector2(0, 132)
	_layer_list.tooltip_text = "The parts this skin's layer holds: only their pixels change colour"
	_layer_list.item_selected.connect(_on_layer_part_selected)
	column.add_child(_layer_list)

	_layer_add_picker = OptionButton.new()
	_layer_add_picker.name = "LayerAddPicker"
	_layer_add_picker.tooltip_text = "A part this skin's layer does not hold yet"
	column.add_child(_layer_add_picker)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 6)
	column.add_child(row3)
	row3.add_child(_small_button("Add part", _on_add_layer_part,
		"Put a part into this skin's layer, so its pixels can be re-coloured and painted"))
	row3.add_child(_small_button("Remove part", _on_remove_layer_part,
		"Take the selected part out of this skin's layer: its pixels stop changing colour"))
	return panel


func _make_middle_panel() -> PanelContainer:
	var panel := _make_panel("CanvasPanel")
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var toolbar := HBoxContainer.new()
	toolbar.name = "Toolbar"
	toolbar.add_theme_constant_override("separation", 8)
	column.add_child(toolbar)

	_anim_picker = OptionButton.new()
	_anim_picker.name = "AnimPicker"
	for anim in GolferSkinLibrary.ANIMATIONS:
		_anim_picker.add_item(str(anim).capitalize())
	_anim_picker.item_selected.connect(func(index: int):
		_anim = str(GolferSkinLibrary.ANIMATIONS.keys()[index])
		_frame = 0
		_refresh_frame_row()
		_refresh_canvas())
	toolbar.add_child(_anim_picker)

	_direction_picker = OptionButton.new()
	_direction_picker.name = "DirectionPicker"
	for direction in GolferSkinLibrary.DIRECTION_ORDER:
		_direction_picker.add_item(str(direction).replace("-", " ").capitalize())
	_direction_picker.item_selected.connect(func(index: int):
		_direction = GolferSkinLibrary.DIRECTION_ORDER[index]
		_frame = 0
		_refresh_frame_row()
		_refresh_canvas())
	toolbar.add_child(_direction_picker)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	toolbar.add_child(_small_button("Eraser", func():
		_editor.erasing = not _editor.erasing
		_refresh_brush_row(),
		"Toggle the eraser"))
	toolbar.add_child(_small_button("−", func(): _editor.zoom_out(), "Zoom out"))
	toolbar.add_child(_small_button("+", func(): _editor.zoom_in(), "Zoom in"))

	_frame_row = HBoxContainer.new()
	_frame_row.name = "FrameRow"
	_frame_row.add_theme_constant_override("separation", 4)
	column.add_child(_frame_row)

	_editor = SkinPixelEditor.new()
	_editor.name = "Canvas"
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor.pixels_changed.connect(_on_pixels_changed)
	_editor.part_picked.connect(func(_part: String, _shade: int): _refresh_brush_row())
	column.add_child(_editor)

	column.add_child(_section_label("Pixel palette"))
	# A flow container, so the eight part buttons wrap onto a second line on a
	# phone instead of pushing the page wider than the screen.
	_part_row = HFlowContainer.new()
	_part_row.name = "PartRow"
	_part_row.add_theme_constant_override("h_separation", 4)
	_part_row.add_theme_constant_override("v_separation", 4)
	column.add_child(_part_row)

	_shade_row = HFlowContainer.new()
	_shade_row.name = "ShadeRow"
	_shade_row.add_theme_constant_override("h_separation", 4)
	_shade_row.add_theme_constant_override("v_separation", 4)
	column.add_child(_shade_row)

	var hint := Label.new()
	hint.text = "Left click paints · right click picks the pixel under the cursor"
	hint.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	hint.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	# Wraps rather than setting the width of the middle column: on a phone that
	# is what would push the Done button off the edge of the screen.
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	return panel


func _make_right_panel() -> PanelContainer:
	var panel := _make_panel("PreviewPanel")
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	column.add_child(_section_label("Preview"))

	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 8)
	preview_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(preview_row)

	_preview = TextureRect.new()
	_preview.name = "Preview"
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.custom_minimum_size = Vector2(144, 144)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_row.add_child(_preview)

	_preview_small = TextureRect.new()
	_preview_small.name = "PreviewSmall"
	_preview_small.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_small.custom_minimum_size = Vector2(48, 48)
	_preview_small.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_small.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_small.tooltip_text = "How the skin looks on the course"
	preview_row.add_child(_preview_small)

	_preview_timer = Timer.new()
	_preview_timer.wait_time = 0.25
	_preview_timer.autostart = true
	_preview_timer.timeout.connect(_on_preview_tick)
	add_child(_preview_timer)

	column.add_child(_section_label("Colours"))
	_colour_label = Label.new()
	_colour_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_colour_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	_colour_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_colour_label)

	_colour_picker = ColorPickerButton.new()
	_colour_picker.name = "ColourPicker"
	_colour_picker.edit_alpha = false
	_colour_picker.custom_minimum_size = Vector2(0, 30)
	_colour_picker.color_changed.connect(_on_colour_changed)
	column.add_child(_colour_picker)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 120)
	var rows := VBoxContainer.new()
	rows.name = "ColourRows"
	scroll.add_child(rows)
	column.add_child(scroll)
	_colour_rows = rows

	return panel

var _colour_rows: VBoxContainer = null


## ── Refresh ──────────────────────────────────────────────────────────────

func _refresh_everything() -> void:
	_refresh_skin_list()
	_refresh_name_and_buttons()
	_refresh_frame_row()
	_refresh_canvas()
	_refresh_brush_row()
	_refresh_colour_rows()
	_refresh_layer_list()
	_refresh_preview()


func _refresh_skin_list() -> void:
	if _skins_list == null:
		return
	_updating_list = true
	_skins_list.clear()
	var selected := 0
	for index in _catalogue.size():
		var skin: GolferSkinLibrary.SkinDef = _catalogue[index]
		var label := skin.name
		if not GolferSkinLibrary.is_shipped(skin.id):
			label += "  (yours)"
		elif _has_edits(skin.id):
			label += "  (edited)"
		_skins_list.add_item(label)
		if _selected != null and skin.id == _selected.skin.id:
			selected = index
	_skins_list.select(selected)
	_updating_list = false


func _has_edits(id: String) -> bool:
	var profile = GameManager.player_profile
	return profile != null and profile.has_custom_skin(id)


func _refresh_name_and_buttons() -> void:
	if _selected == null:
		return
	var shipped := GolferSkinLibrary.is_shipped(_selected.skin.id)
	if _name_edit != null:
		_name_edit.text = str(_selected.recipe.get("name", _selected.skin.name))
		_name_edit.editable = not shipped
		_name_edit.tooltip_text = "Shipped skins keep their names" if shipped else "Name your skin"
	if _duplicate_button != null:
		_duplicate_button.disabled = not shipped
	if _revert_button != null:
		_revert_button.disabled = not _has_edits(_selected.skin.id)
	if _use_button != null:
		var profile = GameManager.player_profile
		_use_button.disabled = profile != null and profile.skin_id == _selected.skin.id


func _refresh_frame_row() -> void:
	if _frame_row == null:
		return
	for child in _frame_row.get_children():
		child.queue_free()
	var count: int = int(GolferSkinLibrary.ANIMATIONS[_anim]["frames"])
	for index in count:
		var button := Button.new()
		button.text = str(index + 1)
		button.custom_minimum_size = Vector2(34, 28)
		button.toggle_mode = true
		button.button_pressed = index == _frame
		button.pressed.connect(func():
			_frame = index
			_refresh_frame_row()
			_refresh_canvas())
		_frame_row.add_child(button)


## The frame the player is painting: their own pixels when there are any, the
## base art re-coloured with the recipe's colours otherwise.
func _refresh_canvas() -> void:
	if _editor == null or _selected == null:
		return
	var skin := _working_skin()
	var palette := GolferSkinLibrary.palette_for(skin, {})
	_editor.set_palette(palette)
	_editor.set_image(_frame_image(skin, palette))
	_refresh_preview()


func _frame_image(skin: GolferSkinLibrary.SkinDef, palette: Dictionary) -> Image:
	var key := skin.frame_key(_anim, _direction, _frame)
	if _selected.recipe.get("overlays", {}).has(key):
		# A frame the player has painted: rebuild it from the stored pixels.
		var stored := GolferSkinLibrary.SkinDef.from_recipe(_selected.recipe)
		stored.id = skin.id
		stored.base_id = skin.base_id
		stored.root = skin.root
		stored.legacy = skin.legacy
		stored.custom = true
		for part in skin.colors:
			if not stored.colors.has(part):
				stored.colors[part] = skin.colors[part]
		var painted := GolferSkinLibrary.image_from_overlay(stored, {}, palette, _anim, _direction, _frame)
		if painted != null:
			return painted
	var image := GolferSkinLibrary.base_frame_image(skin, _direction, _anim, _frame)
	var copy: Image = null
	if image != null:
		copy = image.duplicate() as Image
	if copy == null:
		copy = Image.create_empty(GolferSkinLibrary.CANVAS, GolferSkinLibrary.CANVAS, false, Image.FORMAT_RGBA8)
		copy.fill(Color(0, 0, 0, 0))
	var changed := GolferSkinLibrary.changed_colours(skin, {})
	if not changed.is_empty():
		GolferSkinLibrary.recolour(copy, skin, changed, _direction, _anim, _frame)
	return copy


func _refresh_brush_row() -> void:
	if _part_row == null or _selected == null:
		return
	for child in _part_row.get_children():
		child.queue_free()
	# Every part can be painted - painting one the layer does not hold yet puts
	# it in (see _on_pixels_changed) - while the colour pickers offer exactly
	# the parts the layer holds.
	var parts := GolferSkinLibrary.PAINTABLE_PARTS
	for part in parts:
		var button := Button.new()
		button.text = GolferSkinLibrary.PART_LABELS.get(part, part)
		button.toggle_mode = true
		button.button_pressed = (part == _editor.brush_part and not _editor.erasing)
		button.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
		var colour := GolferSkinLibrary.colour_for(_working_skin(), part)
		var style := StyleBoxFlat.new()
		style.bg_color = colour
		style.set_corner_radius_all(3)
		style.content_margin_left = 6
		style.content_margin_right = 6
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("pressed", style)
		button.pressed.connect(func():
			_editor.brush_part = part
			_editor.erasing = false
			_refresh_brush_row()
			_refresh_colour_rows())
		_part_row.add_child(button)

	for child in _shade_row.get_children():
		child.queue_free()
	var shades := GolferSkinLibrary.ramp(GolferSkinLibrary.colour_for(_working_skin(), _editor.brush_part))
	for index in shades.size():
		var button := Button.new()
		button.custom_minimum_size = Vector2(30, 26)
		button.toggle_mode = true
		button.button_pressed = index == _editor.brush_shade and not _editor.erasing
		button.tooltip_text = "Shade %d" % (index + 1)
		var style := StyleBoxFlat.new()
		style.bg_color = shades[index]
		style.set_corner_radius_all(3)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("pressed", style)
		button.pressed.connect(func():
			_editor.brush_shade = index
			_editor.erasing = false
			_refresh_brush_row())
		_shade_row.add_child(button)


## The part layer the player is editing: the parts this skin holds, how many
## pixels of the art each one owns, and the parts still on offer to add.
func _refresh_layer_list() -> void:
	if _layer_list == null or _selected == null:
		return
	_updating_layer = true
	var skin := _working_skin()
	var counts := GolferSkinLibrary.layer_report(_selected.skin)
	_layer_list.clear()
	for part in skin.customizable:
		_layer_list.add_item("%s — %d px" % [GolferSkinLibrary.PART_LABELS.get(part, part),
			int(counts.get(part, 0))])
		if _editor != null and part == _editor.brush_part:
			_layer_list.select(_layer_list.item_count - 1)
	if _layer_add_picker != null:
		_layer_add_picker.clear()
		for part in GolferSkinLibrary.PAINTABLE_PARTS:
			if skin.customizable.has(part):
				continue
			_layer_add_picker.add_item(GolferSkinLibrary.PART_LABELS.get(part, part))
			_layer_add_picker.set_item_metadata(_layer_add_picker.item_count - 1, part)
		_layer_add_picker.disabled = _layer_add_picker.item_count == 0
	if _layer_note != null:
		var drawn := skin.customizable.size()
		var available: int = GolferSkinLibrary.PAINTABLE_PARTS.size()
		if drawn > 0:
			_layer_note.text = "%d of %d parts · only these pixels change colour" % [drawn, available]
		else:
			_layer_note.text = "No parts: nothing on this skin changes colour yet."
	_updating_layer = false


## Selecting a part in the layer arms the pixel brush with it, so the list is
## also the quickest way to carry on painting a part.
func _on_layer_part_selected(index: int) -> void:
	if _updating_layer or _selected == null or _editor == null:
		return
	var skin := _working_skin()
	if index < 0 or index >= skin.customizable.size():
		return
	_editor.brush_part = skin.customizable[index]
	_editor.erasing = false
	_refresh_brush_row()
	_refresh_colour_rows()
	_refresh_layer_list()


func _on_add_layer_part() -> void:
	if _layer_add_picker == null or _layer_add_picker.item_count == 0:
		return
	_set_layer_part(str(_layer_add_picker.get_item_metadata(_layer_add_picker.selected)), true)


func _on_remove_layer_part() -> void:
	var selected := _layer_list.get_selected_items()
	if selected.is_empty():
		return
	var skin := _working_skin()
	_set_layer_part(skin.customizable[selected[0]], false)


## Put a part into a skin's layer, or take it out, and store the layer's parts
## on the skin's recipe. A skin starts with the parts its art drew; from here
## the player decides which of them - and which they add themselves - the colour
## pickers offer, and so which pixels change colour.
func _set_layer_part(part: String, present: bool) -> void:
	if _selected == null:
		return
	var skin := _working_skin()
	if not skin.set_part(part, present):
		return
	_selected.recipe["parts"] = Array(skin.customizable)
	var label: String = GolferSkinLibrary.PART_LABELS.get(part, part)
	_commit("")
	if present:
		_set_status("%s is in this skin's layer: its pixels change colour, and can be painted." % label)
	else:
		_set_status("%s is out of this skin's layer: its pixels keep the colour they have." % label)
	_refresh_everything()


func _refresh_colour_rows() -> void:
	if _colour_rows == null or _selected == null:
		return
	for child in _colour_rows.get_children():
		child.queue_free()
	var skin := _working_skin()
	_colour_picker.color = GolferSkinLibrary.colour_for(skin, _editor.brush_part if _editor != null else "shirt")
	_colour_label.text = "Re-colouring: %s" % GolferSkinLibrary.PART_LABELS.get(_editor.brush_part, _editor.brush_part)
	for part in skin.customizable:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var label := Label.new()
		label.text = GolferSkinLibrary.PART_LABELS.get(part, part)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
		row.add_child(label)
		var swatch := ColorRect.new()
		swatch.color = GolferSkinLibrary.colour_for(skin, part)
		swatch.custom_minimum_size = Vector2(28, 20)
		row.add_child(swatch)
		var picker := ColorPickerButton.new()
		picker.edit_alpha = false
		picker.custom_minimum_size = Vector2(60, 24)
		picker.color = GolferSkinLibrary.colour_for(skin, part)
		picker.color_changed.connect(func(value: Color): _set_part_colour(part, value))
		row.add_child(picker)
		_colour_rows.add_child(row)


func _refresh_preview() -> void:
	if _preview == null or _selected == null:
		return
	var skin := _working_skin()
	_preview_frames = GolferSkinLibrary.frames_for(skin, {}, true)
	_show_preview_frame()
	if _preview_small != null:
		_preview_small.texture = _preview_frames.get_frame_texture("idle_%s" % _direction, 0)


func _on_preview_tick() -> void:
	if _selected == null or _preview == null or _preview_frames == null:
		return
	var count: int = int(GolferSkinLibrary.ANIMATIONS[_anim]["frames"])
	_preview_frame = (_preview_frame + 1) % maxi(count, 1)
	_show_preview_frame()


func _show_preview_frame() -> void:
	var animation := "%s_%s" % [_anim, _direction]
	if _preview_frames == null or not _preview_frames.has_animation(animation):
		return
	if _preview != null:
		_preview.texture = _preview_frames.get_frame_texture(animation, _preview_frame)


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


## ── Actions ──────────────────────────────────────────────────────────────

func _on_skin_selected(index: int) -> void:
	if _updating_list:
		return
	_select_index(index)


func _on_name_changed() -> void:
	if _selected == null or _name_edit == null:
		return
	if GolferSkinLibrary.is_shipped(_selected.skin.id):
		return
	var wanted := _name_edit.text.strip_edges().left(PlayerGolferProfile.MAX_SKIN_NAME)
	if wanted.is_empty() or wanted == str(_selected.recipe.get("name", "")):
		return
	_selected.recipe["name"] = wanted
	_commit("Renamed to %s." % wanted)
	_refresh_skin_list()
	_refresh_name_and_buttons()


func _on_new_skin() -> void:
	var profile = GameManager.player_profile
	if profile == null:
		return
	if profile.created_skin_count() >= PlayerGolferProfile.MAX_CUSTOM_SKINS:
		_set_status("You have reached the limit of %d skins of your own." % PlayerGolferProfile.MAX_CUSTOM_SKINS)
		return
	var base := _working_skin()
	var fresh := GolferSkinLibrary.new_custom_skin(base, "")
	_selected = SkinSelection.new()
	_selected.skin = fresh
	_selected.recipe = fresh.to_recipe()
	_selected.created = true
	_commit("Made a new skin from %s. Paint it, or change its colours." % base.name)
	reload()
	_select_by_id(fresh.id)
	_set_status("New skin created — it is yours to paint and name.")


func _on_duplicate() -> void:
	if _selected == null:
		return
	_on_new_skin()


func _on_revert() -> void:
	if _selected == null:
		return
	var profile = GameManager.player_profile
	if profile == null:
		return
	var id := _selected.skin.id
	var removed_name := _selected.skin.name
	var created := not GolferSkinLibrary.is_shipped(id)
	profile.remove_custom_skin(id)
	GolferSkinLibrary.invalidate_catalogue()
	GolferSkinLibrary.invalidate(id)
	reload()
	_select_by_id(GolferSkinLibrary.default_skin_id() if created else id)
	if created:
		_set_status("Deleted %s." % removed_name)
	else:
		_set_status("Put %s back to the shipped art." % removed_name)


func _on_wear() -> void:
	if _selected == null:
		return
	var profile = GameManager.player_profile
	if profile == null:
		return
	profile.skin_id = _selected.skin.id
	_set_status("Your golfer now plays in %s." % _selected.skin.name)
	_refresh_name_and_buttons()


## A stroke finished on the canvas: store what it painted as part+shade indices.
func _on_pixels_changed() -> void:
	if _selected == null or _editor == null:
		return
	var written := _editor.take_written()
	if written.is_empty():
		return
	var skin := _working_skin()
	var key := skin.frame_key(_anim, _direction, _frame)
	var bytes := _overlay_bytes(skin, key)
	var parts := PackedStringArray(skin.customizable)
	for pixel in written:
		var index: int = int(written[pixel])
		bytes[int(pixel.y) * GolferSkinLibrary.CANVAS + int(pixel.x)] = index
		# A part the player paints joins the skin's layer, so the pixels they
		# put down can be re-coloured like any other.
		var decoded := GolferSkinLibrary.decode_pixel(index)
		if not decoded.is_empty() and not parts.has(str(decoded["part"])):
			parts.append(str(decoded["part"]))
	_selected.recipe["overlays"][key] = Array(bytes)
	if skin.set_part_order(parts):
		_selected.recipe["parts"] = Array(skin.customizable)
	_commit("Painted %s / %s frame %d." % [_anim.capitalize(), _direction.replace("-", " "), _frame + 1])
	_refresh_everything()


## The stored pixels for one frame: what is already there, or the frame's part
## layer, so a first stroke starts from the pixels the artist drew - each one
## already tagged with the part and shade it belongs to.
func _overlay_bytes(skin: GolferSkinLibrary.SkinDef, key: String) -> PackedByteArray:
	var stored = _selected.recipe.get("overlays", {}).get(key)
	if stored is Array or stored is PackedByteArray:
		var bytes := PackedByteArray()
		for entry in stored:
			bytes.append(clampi(int(entry), 0, 255))
		if bytes.size() == GolferSkinLibrary.CANVAS * GolferSkinLibrary.CANVAS:
			return bytes
	return GolferSkinLibrary.frame_bytes(skin, _direction, _anim, _frame)


func _on_colour_changed(value: Color) -> void:
	if _editor == null:
		return
	_set_part_colour(_editor.brush_part, value)


func _set_part_colour(part: String, value: Color) -> void:
	if _selected == null or part.is_empty():
		return
	var colours: Dictionary = _selected.recipe.get("colors", {})
	colours[part] = value.to_html(false)
	_selected.recipe["colors"] = colours
	_commit("")
	if _selected.created:
		# A skin of the player's own stores every part's colour, so it keeps its
		# identity if the shipped skin it was forked from ever changes.
		var skin := _working_skin()
		for other in PlayerGolferProfile.parts_for_skin(_selected.skin.id):
			colours[other] = GolferSkinLibrary.colour_for(skin, other).to_html(false)
		_selected.recipe["colors"] = colours
		_commit("")
	_refresh_skin_list()
	_refresh_name_and_buttons()
	_refresh_canvas()
	_refresh_brush_row()
	_refresh_colour_rows()


func _small_button(text: String, action: Callable, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	button.pressed.connect(action)
	return button


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_requested.emit()
		get_viewport().set_input_as_handled()
