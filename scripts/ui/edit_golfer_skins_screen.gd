extends Control
class_name EditGolferSkinsScreen
## EditGolferSkinsScreen - the Golfer Skin studio, opened from the title screen.
##
## The player picks a Golfer Skin - one that ships with the game or one of
## their own - and paints its Re-color Layers: one grid per animation sprite,
## where every pixel can be given to a Re-color Group ("Shirt", "Pants", "Cap",
## "Hair", "Skin", or anything the player invents). Groups can be created,
## renamed, deleted and re-coloured here; the layers they paint are written to
## editable text files (see GolferSkin) so a skin can also be edited by hand.
##
## Three arrangements, picked from the window (see layout_mode_for):
##
##  * WIDE   - desktop: the skin list, the group list and the studio side by
##             side, with nothing hidden behind a tab.
##  * TABLET - the two lists share a row above the studio.
##  * PHONE  - one scrolling column: the studio first, then the groups and the
##             skins, every control a thumb-sized target.
##
## The studio has two sides, switched by Edit:
##
##  * PIXELS - the sprite's own artwork: a colour picker and a brush paint the
##             pixels the golfer is drawn with, right-click erases one, and
##             alt-click picks up the colour already on one.
##  * GROUPS - the Re-color Groups: the same brush gives the pixels it covers to
##             the selected group, the Fill switch gives it a whole run of them
##             at once, and the groups are created, renamed, re-coloured and
##             deleted alongside.
##
## Nothing is written to disk until Save Skins is pressed, so an experiment can
## be abandoned. A built-in skin is copied to the player's own folder the first
## time it is saved and can be reverted to the shipped one afterwards.

signal back_requested()

enum Layout { WIDE, TABLET, PHONE }
## The two sides of the studio: painting a sprite's pixels, or editing the skin's
## Re-color Groups. See _set_mode.
enum Mode { PIXELS, GROUPS }

## Window widths at which the three arrangements start.
const WIDE_MIN_WIDTH := 1080.0
const TABLET_MIN_WIDTH := 760.0
## A window this short is a phone whatever its width.
const TALL_MIN_HEIGHT := 560.0
## How far the window has to move before the tree is rebuilt at new sizes.
const REPROPORTION_STEP := 0.12
const MAX_PAGE_WIDTH := 1960.0
## Width of the skin and group column when it sits beside the studio.
const SIDE_COLUMN_WIDTH := 300.0
const THUMB_SIZE := 42
const GROUP_ROW_HEIGHT := 30
## The brush widths the studio offers, in sprite pixels.
const BRUSH_SIZES: Array[int] = [1, 3, 5, 7]

const TITLE_TEXT := "Edit Golfer Skins"
const IDLE_HINT := "The layers are editable text files - Save Skins writes them to user://golfer_skins"

## The library the screen edits: the game's own, so the golfers on the course
## pick a saved skin up straight away.
var library: GolferSkinLibrary = null
## Asks the player before something destructive. Left unset in the game (a
## ConfirmDialog is shown); tests may replace it to answer for the player.
var confirm_callback: Callable = Callable()

var _skin: GolferSkin = null
## Editable copies of the manifest fields, so a rebuild never loses an edit.
var _skin_name: String = ""
## The artwork a skin is drawn over. Fixed when the skin is made: a skin's layers
## only mean anything over the sprite set they were painted on.
var _sprite_id: String = GolferSkinLibrary.DEFAULT_SPRITE_ID
var _worn_by: Array[int] = []
## The group the canvas paints with (NO_GROUP frees pixels).
var _active_group: int = GolferSkinLayer.NO_GROUP
## Which animation sprite the canvas is painting.
var _animation: String = "idle"
var _direction: String = "south"
var _frame_index: int = 0
## Show the sprite the way the skin draws it (Pixels mode): off, the canvas shows
## the artwork as painted, which is what the brush is changing.
var _show_recolor: bool = false
var _show_grid: bool = true
## The colour the Pixels side's brush paints with, and how wide it is.
var _pixel_color: Color = Color.WHITE
var _brush_size: int = 1
## Fill gives the whole run of pixels a click lands in to the active group,
## rather than that one pixel (see _paint_cell).
var _fill: bool = false
## Which side of the studio is open (see Mode).
var _mode: int = Mode.PIXELS
var _status: String = ""
var _error: bool = false
var _dirty: bool = false
var _layout_mode: int = -1
var _built_size := Vector2.ZERO

# ── Controls the refreshes talk to ────────────────────────────────────────
var _skin_list: ItemList = null
var _skin_name_edit: LineEdit = null
var _tier_checks: Array[CheckBox] = []
var _wear_button: Button = null
var _revert_button: Button = null
var _delete_button: Button = null
var _group_rows: VBoxContainer = null
## group id -> the row's pixel-count label, so painting only updates numbers.
var _group_count_labels: Dictionary = {}
var _group_name_edit: LineEdit = null
var _group_delete_button: Button = null
var _group_color_button: Button = null
var _group_shade_label: Label = null
var _palette_row: HBoxContainer = null
var _palette: HBoxContainer = null
var _pixel_color_button: ColorPickerButton = null
var _brush_picker: OptionButton = null
var _animation_picker: OptionButton = null
var _direction_picker: OptionButton = null
var _frame_strip: HBoxContainer = null
## The frame tiles' textures, updated as the sprite is painted.
var _frame_icons: Array[TextureRect] = []
var _canvas: GolferSkinLayerCanvas = null
## The painting side of the studio and the Re-color Group editor it swaps with.
var _pixel_block: Control = null
var _group_block: Control = null
var _pixels_mode_button: Button = null
var _groups_mode_button: Button = null
var _recolor_check: CheckBox = null
var _grid_check: CheckBox = null
var _fill_check: CheckBox = null
var _play_button: Button = null
var _frame_label: Label = null
var _path_label: Label = null
var _status_label: Label = null
var _save_button: Button = null
var _preview_holder: Control = null
var _preview_golfer: Golfer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if library == null:
		library = GolferSkins.library
	if has_node("/root/Screen"):
		Screen.changed.connect(_on_screen_changed)
	_select_skin(GolferSkins.player_skin())
	_build()


func _on_screen_changed(window_size: Vector2, _world_scale: float) -> void:
	if _current_layout() != _layout_mode:
		_build()
		return
	if absf(window_size.x - _built_size.x) > _built_size.x * REPROPORTION_STEP \
			or absf(window_size.y - _built_size.y) > _built_size.y * REPROPORTION_STEP:
		_build()


func _current_layout() -> int:
	return layout_mode_for(_window_size())


func _window_size() -> Vector2:
	if has_node("/root/Screen"):
		return Screen.window_size
	return get_viewport().get_visible_rect().size


## Which arrangement a window size gets. Pure, so the breakpoints are testable.
static func layout_mode_for(window_size: Vector2) -> int:
	if window_size.x >= WIDE_MIN_WIDTH and window_size.y >= TALL_MIN_HEIGHT:
		return Layout.WIDE
	if window_size.x >= TABLET_MIN_WIDTH and window_size.y >= TALL_MIN_HEIGHT:
		return Layout.TABLET
	return Layout.PHONE


# =============================================================================
# BUILD
# =============================================================================

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	# The preview golfer lived under the old tree; it is gone with it.
	_preview_golfer = null
	_layout_mode = _current_layout()
	_built_size = _window_size()

	var backdrop := MenuBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.green_anchor = Vector2(0.09, 0.94)
	add_child(backdrop)

	var page := _make_page()
	match _layout_mode:
		Layout.WIDE:
			_build_wide(page)
		Layout.TABLET:
			_build_tablet(page)
		_:
			_build_phone(page)

	_sync_mode()
	_refresh_all()
	_rebuild_preview()



## The scrolling page: the header pinned at its own height on top, the studio
## and the skin list under it. Deliberately a VBoxContainer: a panel container
## would stretch the header down the whole window, which would put its buttons
## (Back, Save) under the studio where they cannot be clicked.
func _make_page() -> VBoxContainer:
	var view := _window_size()
	var pad := int(clampf(view.x * 0.020, 10.0, 28.0))
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if view.x >= 380.0 \
		else ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.name = "Page"
	# The page fills the window: its own room plus the margins around it.
	margin.custom_minimum_size = (view - Vector2(pad * 2, pad * 2)).maxf(0.0)
	scroll.add_child(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, pad)

	var column := VBoxContainer.new()
	column.name = "PageColumn"
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var header := _make_header()
	header.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	column.add_child(header)
	return column


func _build_wide(page: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "Columns"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	page.add_child(_frame(row))
	var side := VBoxContainer.new()
	side.name = "SideColumn"
	side.custom_minimum_size = Vector2(SIDE_COLUMN_WIDTH, 0)
	side.add_theme_constant_override("separation", 12)
	var skins := _make_skins_panel()
	skins.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(skins)
	row.add_child(side)
	row.add_child(_make_studio(true))


func _build_tablet(page: VBoxContainer) -> void:
	# The skin list is a band across the top, the studio gets the whole width
	# under it, so the canvas stays as large as the tablet allows.
	var band := _make_skins_panel()
	band.name = "SkinBand"
	page.add_child(band)
	page.add_child(_make_studio(true))


func _build_phone(page: VBoxContainer) -> void:
	page.add_child(_make_studio(true))
	page.add_child(_make_skins_panel())



## Keep a wide layout from stretching across a very wide window.
func _frame(content: Control) -> MarginContainer:
	var frame := MarginContainer.new()
	frame.name = "Frame"
	var side := int(maxf(0.0, (_window_size().x - MAX_PAGE_WIDTH) * 0.5))
	frame.add_theme_constant_override("margin_left", side)
	frame.add_theme_constant_override("margin_right", side)
	frame.add_child(content)
	return frame


# =============================================================================
# HEADER
# =============================================================================

## Back, the title, what just happened and Save. On a phone the title is
## smaller, Save says just "Save" and the status line drops to a row of its own,
## so the four fit across a 390 pixel window.
func _make_header() -> Control:
	var view := _window_size()
	var compact := _layout_mode == Layout.PHONE
	var row := HBoxContainer.new()
	row.name = "HeaderRow"
	row.add_theme_constant_override("separation", 10)

	var back := _make_button("Back", "Back to the main menu", UIConstants.COLOR_TEXT,
		64.0 if compact else 96.0)
	back.name = "BackButton"
	back.pressed.connect(func(): back_requested.emit())
	row.add_child(back)

	var title := Label.new()
	title.name = "Title"
	title.text = TITLE_TEXT
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size",
		int(clampf(view.x / (44.0 if compact else 42.0), 17.0, 30.0)))
	title.add_theme_color_override("font_color", MenuStyle.TITLE_COLOR)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(title)

	_save_button = _make_button("Save" if compact else "Save Skins",
		"Write this skin's groups and layers to text files", UIConstants.COLOR_TEXT,
		68.0 if compact else 124.0)
	_save_button.name = "SaveSkinsButton"
	MenuStyle.paint_primary(_save_button)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_save_button.add_theme_color_override(state, MenuStyle.INK)
	_save_button.pressed.connect(_on_save_pressed)
	row.add_child(_save_button)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_status_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not compact:
		row.add_child(_status_label)
		return row

	var column := VBoxContainer.new()
	column.name = "Header"
	column.add_theme_constant_override("separation", 4)
	column.add_child(row)
	column.add_child(_status_label)
	return column


# =============================================================================
# SKINS PANEL
# =============================================================================

func _make_skins_panel() -> Control:
	var panel := _make_sheet("SkinsSheet")
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_child(_make_section_label("Skins"))
	header.add_child(_spacer())
	var create := _make_button("New Skin", "Start a skin of your own, groups and layers and all",
		UIConstants.COLOR_TEXT, 100)
	create.name = "NewSkinButton"
	create.pressed.connect(_on_new_skin_pressed)
	header.add_child(create)
	column.add_child(header)

	_skin_list = ItemList.new()
	_skin_list.name = "SkinList"
	_skin_list.custom_minimum_size = Vector2(0, 126)
	_skin_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skin_list.select_mode = ItemList.SELECT_SINGLE
	_skin_list.item_selected.connect(_on_skin_selected)
	column.add_child(_skin_list)

	column.add_child(_make_field_label("Name"))
	_skin_name_edit = LineEdit.new()
	_skin_name_edit.name = "SkinNameEdit"
	_skin_name_edit.max_length = GolferSkin.MAX_SKIN_NAME_LENGTH
	_skin_name_edit.tooltip_text = "What this skin is called"
	_skin_name_edit.text_changed.connect(_on_skin_name_changed)
	column.add_child(_skin_name_edit)

	column.add_child(_make_field_label("Worn by visiting golfers"))
	var tier_row := HBoxContainer.new()
	tier_row.name = "TierRow"
	tier_row.add_theme_constant_override("separation", 4)
	_tier_checks = []
	for tier in GolferSkin.TIER_KEYS.size():
		var check := CheckBox.new()
		check.name = "Tier%s" % GolferSkin.TIER_KEYS[tier].capitalize()
		check.text = GolferSkin.TIER_KEYS[tier].capitalize()
		check.tooltip_text = "Visiting %s golfers wear this skin" % GolferSkin.TIER_KEYS[tier]
		check.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
		check.toggled.connect(_on_tier_toggled.bind(tier))
		_tier_checks.append(check)
		tier_row.add_child(check)
	column.add_child(tier_row)

	_path_label = Label.new()
	_path_label.name = "SkinPath"
	_path_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	_path_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_path_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_path_label)

	_wear_button = _make_button("Wear This", "Your own golfer plays in this skin",
		UIConstants.COLOR_TEXT, 92)
	_wear_button.name = "WearSkinButton"
	_wear_button.pressed.connect(_on_wear_pressed)
	var copy_button := _make_button("Duplicate", "Copy this skin - groups and layers and all",
		UIConstants.COLOR_TEXT, 92)
	copy_button.name = "DuplicateSkinButton"
	copy_button.pressed.connect(_on_duplicate_pressed)
	_revert_button = _make_button("Revert", "Throw your copy away and go back to the shipped skin",
		UIConstants.COLOR_TEXT, 80)
	_revert_button.name = "RevertSkinButton"
	_revert_button.pressed.connect(_on_revert_pressed)
	_delete_button = _make_button("Delete", "Delete this skin of yours",
		UIConstants.COLOR_DANGER_MUTED, 78)
	_delete_button.name = "DeleteSkinButton"
	_delete_button.pressed.connect(_on_delete_skin_pressed)
	if _layout_mode == Layout.PHONE:
		# Four buttons and a 390 pixel window: two rows of two.
		for pair in [[_wear_button, copy_button], [_revert_button, _delete_button]]:
			var row := HBoxContainer.new()
			row.name = "SkinActions"
			row.add_theme_constant_override("separation", 6)
			for button in pair:
				row.add_child(button)
			column.add_child(row)
	else:
		var actions := HBoxContainer.new()
		actions.name = "SkinActions"
		actions.add_theme_constant_override("separation", 6)
		for button in [_wear_button, copy_button, _revert_button, _delete_button]:
			actions.add_child(button)
		column.add_child(actions)
	return panel


# =============================================================================
# RE-COLOR GROUPS PANEL
# =============================================================================

## The Re-color Group editor: what the Groups side of the studio shows. The
## panel keeps its own name so the layout and the tests can find it, but it is a
## child of the studio rather than a sheet of its own - the mode switch is what
## brings it on screen.
func _make_group_editor() -> Control:
	var panel := PanelContainer.new()
	panel.name = "GroupsSheet"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", MenuStyle.flat(
		MenuStyle.with_alpha(MenuStyle.INSET_BG, 0.55), Color(0, 0, 0, 0), 0, 10, 8, 8, 8))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_child(_make_section_label("Re-color Groups"))
	header.add_child(_spacer())
	var create := _make_button("New Group", "Add a group this skin can paint with",
		UIConstants.COLOR_TEXT, 104)
	create.name = "NewGroupButton"
	create.pressed.connect(_on_new_group_pressed)
	header.add_child(create)
	column.add_child(header)

	# The brush gives the pixels it covers to one group: this is where that
	# group is chosen, and Fill says whether it takes the whole run it lands in.
	_palette_row = HBoxContainer.new()
	_palette_row.name = "PaletteRow"
	_palette_row.add_theme_constant_override("separation", 8)
	_palette_row.add_child(_make_field_label("Paint with"))
	_palette = HBoxContainer.new()
	_palette.name = "Palette"
	_palette.add_theme_constant_override("separation", 4)
	_palette_row.add_child(_palette)
	column.add_child(_palette_row)

	_fill_check = CheckBox.new()
	_fill_check.name = "FillCheck"
	_fill_check.text = "Fill"
	_fill_check.tooltip_text = "Fill gives every pixel of the run you click to the group being painted with"
	_fill_check.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_fill_check.button_pressed = _fill
	_fill_check.toggled.connect(_on_fill_toggled)

	# Fill rides with the hint rather than the palette row: a phone cannot fit
	# the swatches, the label and the switch on one line.
	var hint_row := HBoxContainer.new()
	hint_row.name = "GroupHintRow"
	hint_row.add_theme_constant_override("separation", 8)
	hint_row.add_child(_fill_check)
	var group_hint := Label.new()
	group_hint.name = "GroupHint"
	group_hint.text = "Brush pixels into the selected group: left-click gives them to it, right-click frees them, alt-click picks the group already on a pixel."
	group_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	group_hint.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	group_hint.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	group_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_row.add_child(group_hint)
	column.add_child(hint_row)

	var scroll := ScrollContainer.new()
	scroll.name = "GroupScroll"
	scroll.custom_minimum_size = Vector2(0, 140)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_group_rows = VBoxContainer.new()
	_group_rows.name = "GroupRows"
	_group_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_group_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_group_rows)

	column.add_child(_make_field_label("Selected group"))
	_group_name_edit = LineEdit.new()
	_group_name_edit.name = "GroupNameEdit"
	_group_name_edit.max_length = GolferSkin.MAX_GROUP_NAME_LENGTH
	_group_name_edit.tooltip_text = "Rename the selected group. Shirt, Pants, Cap, Hair and Skin are the names the Edit Player page knows."
	_group_name_edit.text_submitted.connect(_on_group_name_submitted)
	_group_name_edit.focus_exited.connect(func(): _on_group_name_submitted(_group_name_edit.text))
	column.add_child(_group_name_edit)

	var color_row := HBoxContainer.new()
	color_row.name = "GroupColorRow"
	color_row.add_theme_constant_override("separation", 8)
	_group_color_button = ColorPickerButton.new()
	_group_color_button.name = "GroupColorButton"
	_group_color_button.text = "Colour"
	_group_color_button.tooltip_text = "Pick the colour this group is drawn in"
	_group_color_button.edit_alpha = false
	_group_color_button.custom_minimum_size = Vector2(96, 32)
	_group_color_button.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_group_color_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_group_color_button.color_changed.connect(_on_group_color_chosen)
	color_row.add_child(_group_color_button)
	_group_shade_label = Label.new()
	_group_shade_label.name = "GroupShade"
	_group_shade_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_group_shade_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_group_shade_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	_group_shade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_group_shade_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_row.add_child(_group_shade_label)
	_group_delete_button = _make_button("Delete", "Delete the selected group and free its pixels",
		UIConstants.COLOR_DANGER_MUTED, 78)
	_group_delete_button.name = "DeleteGroupButton"
	_group_delete_button.pressed.connect(_on_delete_group_pressed)
	color_row.add_child(_group_delete_button)
	column.add_child(color_row)
	return panel


# =============================================================================
# STUDIO
# =============================================================================

func _make_studio(expand: bool) -> Control:
	var panel := _make_sheet("StudioSheet")
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand:
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(_make_mode_switch())

	var compact := _layout_mode == Layout.PHONE
	var header := HBoxContainer.new()
	header.name = "StudioHeader"
	header.add_theme_constant_override("separation", 8)
	header.add_child(_make_section_label("Sprite"))
	_animation_picker = OptionButton.new()
	_animation_picker.name = "AnimationPicker"
	_animation_picker.tooltip_text = "Which animation to paint"
	_animation_picker.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	for animation in GolferSkinLibrary.ANIMATIONS:
		_animation_picker.add_item(animation.capitalize())
	_animation_picker.item_selected.connect(_on_animation_selected)
	header.add_child(_animation_picker)
	_direction_picker = OptionButton.new()
	_direction_picker.name = "DirectionPicker"
	_direction_picker.tooltip_text = "Which way the golfer is facing"
	_direction_picker.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	for direction in GolferSkinLibrary.DIRECTIONS:
		_direction_picker.add_item(direction.capitalize().replace("-", " "))
	_direction_picker.item_selected.connect(_on_direction_selected)
	header.add_child(_direction_picker)

	_recolor_check = CheckBox.new()
	_recolor_check.name = "RecolorCheck"
	_recolor_check.text = "Re-coloured"
	_recolor_check.tooltip_text = "Show the sprite the way the skin re-colours it"
	_recolor_check.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_recolor_check.button_pressed = _show_recolor
	_recolor_check.toggled.connect(_on_recolor_toggled)
	_grid_check = CheckBox.new()
	_grid_check.name = "GridCheck"
	_grid_check.text = "Grid"
	_grid_check.tooltip_text = "Show the pixel grid of the Re-color Layer"
	_grid_check.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_grid_check.button_pressed = _show_grid
	_grid_check.toggled.connect(_on_grid_toggled)
	_brush_picker = OptionButton.new()
	_brush_picker.name = "BrushSizePicker"
	_brush_picker.tooltip_text = "How wide the brush is: Pixels paints the artwork with it, Groups gives the pixels it covers to the selected Re-color Group"
	_brush_picker.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	for brush in BRUSH_SIZES:
		_brush_picker.add_item("Brush %d" % brush)
	_brush_picker.select(clampi(BRUSH_SIZES.find(_brush_size), 0, BRUSH_SIZES.size() - 1))
	_brush_picker.item_selected.connect(_on_brush_size_selected)
	if compact:
		# The views go on a row of their own rather than squeezing the pickers.
		var views := HBoxContainer.new()
		views.name = "StudioViews"
		views.add_theme_constant_override("separation", 8)
		# The Re-coloured switch rides with the Pixels block, so only the grid
		# and the brush go on this row.
		views.add_child(_grid_check)
		views.add_child(_brush_picker)
		var header_column := VBoxContainer.new()
		header_column.name = "StudioHeader"
		header_column.add_theme_constant_override("separation", 6)
		header_column.add_child(header)
		header_column.add_child(views)
		column.add_child(header_column)
	else:
		header.add_child(_spacer())
		header.add_child(_brush_picker)
		header.add_child(_grid_check)
		column.add_child(header)

	# The pixels block holds everything the painting side shows: the strip, the
	# canvas, the palette and the preview. The elements every mode shows (the
	# pickers, the canvas) live outside it.
	var pixels := VBoxContainer.new()
	pixels.name = "PixelControls"
	pixels.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pixels.add_theme_constant_override("separation", 8)
	_pixel_block = pixels
	column.add_child(pixels)

	var colour_row := HBoxContainer.new()
	colour_row.name = "PixelColourRow"
	colour_row.add_theme_constant_override("separation", 8)
	colour_row.add_child(_make_field_label("Pixel colour"))
	_pixel_color_button = ColorPickerButton.new()
	_pixel_color_button.name = "PixelColourButton"
	_pixel_color_button.text = "Colour"
	_pixel_color_button.tooltip_text = "The colour the brush paints the sprite's pixels with"
	_pixel_color_button.edit_alpha = false
	_pixel_color_button.custom_minimum_size = Vector2(96, 32)
	_pixel_color_button.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_pixel_color_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_pixel_color_button.color_changed.connect(_on_pixel_color_chosen)
	colour_row.add_child(_pixel_color_button)
	colour_row.add_child(_spacer())
	colour_row.add_child(_recolor_check)
	pixels.add_child(colour_row)

	_frame_strip = HBoxContainer.new()
	_frame_strip.name = "FrameStrip"
	_frame_strip.add_theme_constant_override("separation", 6)
	pixels.add_child(_frame_strip)

	_canvas = GolferSkinLayerCanvas.new()
	_canvas.name = "LayerCanvas"
	_canvas.custom_minimum_size = Vector2(240, 240)
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.cell_painted.connect(_on_cell_painted)
	_canvas.cell_erased.connect(_on_cell_erased)
	_canvas.cell_picked.connect(_on_cell_picked)
	column.add_child(_canvas)

	_frame_label = Label.new()
	_frame_label.name = "FrameLabel"
	_frame_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_frame_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	_frame_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_frame_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_button = _make_button("Pause", "Start or stop the preview golfer below",
		UIConstants.COLOR_TEXT, 88)
	_play_button.name = "PlayButton"
	_play_button.pressed.connect(_on_play_pressed)

	if compact:
		var controls := HBoxContainer.new()
		controls.name = "StudioControls"
		controls.add_theme_constant_override("separation", 8)
		controls.add_child(_frame_label)
		controls.add_child(_spacer())
		controls.add_child(_play_button)
		pixels.add_child(controls)
	else:
		var footer := HBoxContainer.new()
		footer.name = "StudioFooter"
		footer.add_theme_constant_override("separation", 8)
		footer.add_child(_spacer())
		footer.add_child(_frame_label)
		footer.add_child(_play_button)
		pixels.add_child(footer)

	var preview_row := HBoxContainer.new()
	preview_row.name = "PreviewRow"
	preview_row.add_theme_constant_override("separation", 10)
	_preview_holder = Control.new()
	_preview_holder.name = "GolferPreview"
	_preview_holder.custom_minimum_size = Vector2(84, 84)
	_preview_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_row.add_child(_preview_holder)
	var hint := Label.new()
	hint.name = "PreviewHint"
	hint.text = "Your golfer wearing this skin. Left-click paints the sprite with the picked colour, right-click erases a pixel, alt-click picks up the colour already there."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	hint.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_row.add_child(hint)
	pixels.add_child(preview_row)

	# The groups block, shown instead of the painting controls in Groups mode.
	_group_block = _make_group_editor()
	column.add_child(_group_block)
	return panel


# =============================================================================
# SMALL WIDGETS
# =============================================================================

## The Pixels / Groups switch that decides which side of the studio is open.
## Pixels edits the sprite's own artwork (colour picker, brush, re-coloured
## preview); Groups edits the Re-color Groups (list, name, colour, delete) and
## gives pixels to one of them with the same brush.
func _make_mode_switch() -> Control:
	var row := HBoxContainer.new()
	row.name = "ModeSwitch"
	row.add_theme_constant_override("separation", 6)
	row.add_child(_make_section_label("Edit"))
	var group := ButtonGroup.new()
	_pixels_mode_button = _make_button("Pixels", "Paint the sprite's own pixels with a colour and a brush",
		UIConstants.COLOR_TEXT, 92)
	_pixels_mode_button.name = "PixelsModeButton"
	_groups_mode_button = _make_button("Groups", "Brush pixels into the Re-color Groups, and create, rename, re-colour and delete them",
		UIConstants.COLOR_TEXT, 92)
	_groups_mode_button.name = "GroupsModeButton"
	for button in [_pixels_mode_button, _groups_mode_button]:
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(button)
	_pixels_mode_button.pressed.connect(_set_mode.bind(Mode.PIXELS))
	_groups_mode_button.pressed.connect(_set_mode.bind(Mode.GROUPS))
	_pixels_mode_button.set_pressed_no_signal(_mode == Mode.PIXELS)
	_groups_mode_button.set_pressed_no_signal(_mode == Mode.GROUPS)
	return row


func _make_sheet(node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.add_theme_stylebox_override("panel", MenuStyle.panel(MenuStyle.SHEET_BG,
		MenuStyle.with_alpha(UIConstants.COLOR_BORDER, 0.45), MenuStyle.CARD_RADIUS + 2, 12, 10))
	return panel


func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_MD)
	label.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_button(text: String, tooltip: String, color: Color, min_width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.add_theme_color_override("font_color", color)
	button.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	button.custom_minimum_size = Vector2(min_width, 32)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


## Open one side of the studio: the pixels, or the Re-color Groups.
func _set_mode(mode: int) -> void:
	if _mode == mode:
		return
	_mode = mode
	_sync_mode()
	_refresh_all()


## Show the block the mode asks for and point the canvas at it. The canvas and
## the brush stay up in both: Pixels paints the artwork, Groups gives the pixels
## the brush covers to the selected Re-color Group (see _on_cell_painted).
func _sync_mode() -> void:
	if _pixels_mode_button != null:
		_pixels_mode_button.set_pressed_no_signal(_mode == Mode.PIXELS)
	if _groups_mode_button != null:
		_groups_mode_button.set_pressed_no_signal(_mode == Mode.GROUPS)
	if _pixel_block != null:
		_pixel_block.visible = _mode == Mode.PIXELS
	if _group_block != null:
		_group_block.visible = _mode == Mode.GROUPS
	if _canvas == null:
		return
	# The Re-coloured switch belongs to the Pixels side (Fill sits in the group
	# sheet, so it follows that block on its own).
	if _recolor_check != null:
		_recolor_check.visible = _mode == Mode.PIXELS
	_canvas.show_recolor = _show_recolor and _mode == Mode.PIXELS
	_canvas.queue_redraw()


# =============================================================================
# REFRESH
# =============================================================================

func _refresh_all() -> void:
	_refresh_skin_list()
	_refresh_skin_fields()
	_refresh_groups()
	_refresh_canvas()
	_refresh_status()


## The skins in the list, with the one being edited appended when it has not
## been written yet (a brand new skin).
func _listed_skins() -> Array[GolferSkin]:
	var listed := library.skins()
	if _skin != null and not listed.has(_skin):
		listed.append(_skin)
	return listed


func _refresh_skin_list() -> void:
	if _skin_list == null:
		return
	_skin_list.clear()
	var listed := _listed_skins()
	for index in listed.size():
		var entry: GolferSkin = listed[index]
		var suffix := " (mine)" if entry.is_user_skin else ""
		if GameManager.player_skin_id == entry.id:
			suffix = " (worn by you)"
		if entry == _skin and not library.skins().has(entry):
			suffix = " (unsaved)"
		_skin_list.add_item("%s%s" % [entry.display_name, suffix])
		_skin_list.set_item_tooltip(index, _skin_location(entry))
		if entry == _skin:
			_skin_list.select(index)
			_skin_list.ensure_current_is_visible()


func _skin_location(entry: GolferSkin) -> String:
	if entry.dir.is_empty():
		return "Not saved yet"
	return ProjectSettings.globalize_path(entry.dir)


## The skin's own fields, read back from the editable copies rather than from
## the skin (which is only brought up to date by Save).
func _refresh_skin_fields() -> void:
	if _skin == null:
		return
	if _skin_name_edit != null and _skin_name_edit.text != _skin_name:
		_skin_name_edit.text = _skin_name
	for tier in _tier_checks.size():
		var check := _tier_checks[tier]
		if check.button_pressed != _worn_by.has(tier):
			check.set_pressed_no_signal(_worn_by.has(tier))
	if _path_label != null:
		var ownership := "your copy - the layers are plain text files" if _skin.is_user_skin \
			else "shipped with the game; it is copied to user://golfer_skins when you save"
		_path_label.text = "%s\n%s" % [_skin_location(_skin), ownership]
	if _wear_button != null:
		var worn := GameManager.player_skin_id == _skin.id
		_wear_button.disabled = worn or not library.has_skin(_skin.id)
		_wear_button.tooltip_text = "Your golfer already plays in this skin" if worn \
			else "Save this skin first, then your golfer can wear it" if _wear_button.disabled \
			else "Your own golfer plays in this skin"
	if _revert_button != null:
		_revert_button.disabled = _skin.fallback_dir.is_empty()
		_revert_button.tooltip_text = "Throw your copy away" if not _revert_button.disabled \
			else "This skin ships with the game - there is no copy to throw away"
	if _delete_button != null:
		_delete_button.disabled = not _skin.is_user_skin or not _skin.fallback_dir.is_empty()
		_delete_button.tooltip_text = "Delete this skin of yours" if not _delete_button.disabled \
			else "Only skins you made yourself can be deleted (use Revert on a shipped one)"
	if _save_button != null:
		_save_button.disabled = not _dirty


## One row per Re-color Group: its colour, its name and how many pixels of the
## sprite on the canvas it owns. Clicking a row makes it the group the canvas
## paints with.
func _refresh_groups() -> void:
	if _group_rows == null:
		return
	for child in _group_rows.get_children():
		_group_rows.remove_child(child)
		child.queue_free()
	_group_count_labels.clear()
	if _skin == null:
		return
	var counts := _group_pixel_counts()
	for group in _skin.group_list():
		var group_id := int(group.get("id", 0))
		var group_name := str(group.get("name", ""))
		var accent: Color = group.get("color", Color.WHITE)
		var row := Button.new()
		row.name = "Group%s" % group_name.replace(" ", "")
		row.custom_minimum_size = Vector2(0, GROUP_ROW_HEIGHT)
		row.tooltip_text = "Paint with %s" % group_name
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		MenuStyle.paint_choice(row, accent, 8)
		# A choice button's "pressed" look is its selected one, and a Button is
		# only in that state while it is held, so the selected row is painted by
		# hand: a wash of the group's colour and a full-strength border.
		if group_id == _active_group:
			row.add_theme_stylebox_override("normal", MenuStyle.flat(
				MenuStyle.CARD_BG.lerp(Color(accent.r, accent.g, accent.b, 0.95), 0.20),
				accent, 2, 8, 8, 4, 4))
		row.pressed.connect(_on_group_row_pressed.bind(group_id))

		var content := HBoxContainer.new()
		content.name = "GroupRowContent"
		content.add_theme_constant_override("separation", 8)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 8
		content.offset_right = -8
		var swatch := ColorRect.new()
		swatch.color = accent
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(swatch)
		var name_label := Label.new()
		name_label.name = "GroupName"
		name_label.text = group_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(name_label)
		var count_label := Label.new()
		count_label.name = "GroupCount"
		count_label.text = "%d px" % int(counts.get(group_id, 0))
		count_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
		count_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(count_label)
		_group_count_labels[group_id] = count_label
		row.add_child(content)
		_group_rows.add_child(row)

	var active := _skin.group_by_id(_active_group)
	if _group_name_edit != null:
		var wanted := str(active.get("name", "")) if not active.is_empty() else ""
		if _group_name_edit.text != wanted and not _group_name_edit.has_focus():
			_group_name_edit.text = wanted
		_group_name_edit.editable = not active.is_empty()
	if _group_color_button != null:
		_group_color_button.disabled = active.is_empty()
		if not active.is_empty():
			var color: Color = active.get("color", Color.WHITE)
			if _group_color_button.color != color:
				_group_color_button.set_pick_color(color)
	if _group_delete_button != null:
		_group_delete_button.disabled = active.is_empty()
	if _group_shade_label != null:
		_group_shade_label.text = "" if active.is_empty() \
			else "shade %.2f" % float(active.get("shade", 1.0))
	_refresh_palette()


## How many pixels of the sprite on the canvas each group owns.
func _group_pixel_counts() -> Dictionary:
	var counts := {}
	if _skin == null:
		return counts
	var sprite_layer := _skin.layer(_current_key())
	for group_id in sprite_layer.used_group_ids():
		counts[group_id] = sprite_layer.count(group_id)
	return counts


## The palette: one swatch per group, plus None to free a pixel.
func _refresh_palette() -> void:
	if _palette == null:
		return
	for child in _palette.get_children():
		_palette.remove_child(child)
		child.queue_free()
	if _skin == null:
		return
	var none := Button.new()
	none.name = "PaletteNone"
	none.text = "None"
	none.tooltip_text = "Left-click frees a pixel instead of painting it"
	none.custom_minimum_size = Vector2(48, 28)
	none.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	none.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_swatch(none, Color(0.28, 0.30, 0.30), _active_group == GolferSkinLayer.NO_GROUP)
	none.pressed.connect(_on_group_row_pressed.bind(GolferSkinLayer.NO_GROUP))
	_palette.add_child(none)
	for group in _skin.group_list():
		var group_id := int(group.get("id", 0))
		var swatch := Button.new()
		swatch.name = "Palette%s" % str(group.get("name", "")).replace(" ", "")
		swatch.text = str(group.get("symbol", ""))
		swatch.tooltip_text = "Paint with %s" % str(group.get("name", ""))
		swatch.custom_minimum_size = Vector2(30, 28)
		swatch.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
		swatch.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_swatch(swatch, group.get("color", Color.WHITE), _active_group == group_id)
		swatch.pressed.connect(_on_group_row_pressed.bind(group_id))
		_palette.add_child(swatch)


func _style_swatch(button: Button, color: Color, active: bool) -> void:
	var fill := Color(color.r, color.g, color.b, 0.9)
	var hover := Color(minf(color.r + 0.18, 1.0), minf(color.g + 0.18, 1.0), minf(color.b + 0.18, 1.0))
	button.add_theme_stylebox_override("normal", MenuStyle.flat(fill,
		Color.WHITE if active else Color(0, 0, 0, 0.4), 2 if active else 1, 6, 4, 2, 2))
	button.add_theme_stylebox_override("hover", MenuStyle.flat(hover, Color.WHITE, 2, 6, 4, 2, 2))
	button.add_theme_stylebox_override("pressed", MenuStyle.flat(fill.darkened(0.25), Color.WHITE, 2, 6, 4, 2, 2))
	button.add_theme_color_override("font_color", _ink_for(color))


## Dark or light ink, whichever reads on a swatch of this colour.
static func _ink_for(color: Color) -> Color:
	var luminance := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	return MenuStyle.INK if luminance > 0.55 else UIConstants.COLOR_TEXT


## The sprite on the canvas: its artwork, its re-coloured twin, the frame strip
## and the palette's pixel counts.
func _refresh_canvas() -> void:
	if _canvas == null or _skin == null:
		return
	var keys := _sprite_keys()
	_frame_index = clampi(_frame_index, 0, maxi(keys.size() - 1, 0))
	if keys.is_empty():
		_canvas.set_artwork(null, null)
		_canvas.set_layer(null)
		_refresh_frame_strip()
		return
	var key: String = keys[_frame_index]
	_canvas.set_artwork(_skin_frame_image(key, false), _skin_frame_image(key, true))
	_canvas.set_layer(_skin.layer(key))
	_canvas.group_colors = _skin.effective_colors({})
	_canvas.active_group = _active_group
	_canvas.brush_size = _brush_size
	_canvas.show_recolor = _show_recolor and _mode == Mode.PIXELS
	_canvas.show_grid = _show_grid
	_canvas.queue_redraw()
	_refresh_frame_strip()
	if _frame_label != null:
		_frame_label.text = "frame %d/%d" % [_frame_index + 1, keys.size()]


## One tile per frame of the current animation and direction. Each carries the
## re-coloured sprite, so a whole animation is visible while one frame of it is
## being painted.
func _refresh_frame_strip() -> void:
	if _frame_strip == null:
		return
	for child in _frame_strip.get_children():
		_frame_strip.remove_child(child)
		child.queue_free()
	_frame_icons.clear()
	if _skin == null:
		return
	var keys := _sprite_keys()
	for index in keys.size():
		var key: String = keys[index]
		var tile := Button.new()
		tile.name = "FrameTile%d" % index
		tile.tooltip_text = key.replace("/", " ")
		tile.custom_minimum_size = Vector2(THUMB_SIZE, THUMB_SIZE)
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var selected := index == _frame_index
		tile.add_theme_stylebox_override("normal", MenuStyle.flat(MenuStyle.INSET_BG,
			MenuStyle.ACCENT_PRIMARY if selected else MenuStyle.with_alpha(UIConstants.COLOR_BORDER, 0.5),
			2 if selected else 1, 6, 2, 2, 2))
		tile.add_theme_stylebox_override("hover", MenuStyle.flat(MenuStyle.CARD_BG_HOVER,
			MenuStyle.ACCENT_PRIMARY, 2, 6, 2, 2, 2))
		tile.add_theme_stylebox_override("pressed", MenuStyle.flat(MenuStyle.CARD_BG_PRESSED,
			MenuStyle.ACCENT_PRIMARY, 2, 6, 2, 2, 2))
		var icon := TextureRect.new()
		icon.name = "FrameIcon"
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 3
		icon.offset_top = 3
		icon.offset_right = -3
		icon.offset_bottom = -3
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = _frame_thumb(key)
		tile.add_child(icon)
		tile.pressed.connect(_on_frame_tile_pressed.bind(index))
		_frame_strip.add_child(tile)
		_frame_icons.append(icon)


func _frame_thumb(key: String) -> ImageTexture:
	var image := _skin_frame_image(key, true)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


func _refresh_status() -> void:
	if _status_label == null:
		return
	var text := _status
	if text.is_empty():
		if _skin == null:
			text = "No skins found"
		elif _dirty:
			text = "%s has unsaved changes" % _skin.display_name
		else:
			text = IDLE_HINT
	_status_label.text = text
	_status_label.add_theme_color_override("font_color",
		UIConstants.COLOR_DANGER if _error else UIConstants.COLOR_TEXT_DIM)


# =============================================================================
# ACTIONS
# =============================================================================

func _set_status(message: String, is_error: bool = false) -> void:
	_status = message
	_error = is_error
	_refresh_status()


func _mark_dirty(message: String = "") -> void:
	_dirty = true
	if message.is_empty():
		_status = ""
		_refresh_status()
	else:
		_set_status(message)
	if _save_button != null:
		_save_button.disabled = false


func _on_skin_selected(index: int) -> void:
	var listed := _listed_skins()
	if index < 0 or index >= listed.size():
		return
	_select_skin(listed[index])


## Edit a skin. With nothing to edit (a machine with no skins at all) the
## player gets a fresh one to start from.
func _select_skin(skin: GolferSkin) -> void:
	if skin == null:
		skin = library.create_skin("New Skin")
		library.save_skin(skin)
	_skin = skin
	_skin_name = skin.display_name
	_sprite_id = skin.sprite_id
	if _sprite_id.is_empty():
		_sprite_id = GolferSkinLibrary.DEFAULT_SPRITE_ID
	_worn_by = skin.worn_by.duplicate()
	_active_group = _active_group_for(skin)
	var first := skin.group_by_id(_active_group)
	if not first.is_empty():
		_on_pixel_color_chosen(first.get("color", Color.WHITE))
	_frame_index = 0
	_dirty = false
	_status = ""
	_error = false
	if is_inside_tree() and _skin_list != null:
		_refresh_all()


## The group a skin starts painting with: the first one it has.
func _active_group_for(skin: GolferSkin) -> int:
	if skin != null and skin.group_count() > 0:
		return int(skin.group_list()[0].get("id", 0))
	return GolferSkinLayer.NO_GROUP


func _on_save_pressed() -> void:
	if _skin == null:
		return
	if not _apply_fields_to_skin():
		return
	if not library.save_skin(_skin):
		_set_status("Could not write %s" % ProjectSettings.globalize_path(GolferSkinLibrary.USER_ROOT), true)
		return
	var saved := _skin
	GolferSkins.invalidate(saved.id)
	GolferSkins.skins_changed.emit()
	_select_skin(saved)
	_set_status("%s saved - %s" % [saved.display_name, IDLE_HINT])
	_refresh_all()
	_rebuild_preview()


## Push the editable copies (name, tiers) onto the skin itself. The sprite set
## is the artwork the skin was painted over: a copy of a skin keeps the set it
## came from, and it is never picked in the studio (see New Skin).
func _apply_fields_to_skin() -> bool:
	var wanted_name := _skin_name.strip_edges().left(GolferSkin.MAX_SKIN_NAME_LENGTH)
	if wanted_name.is_empty():
		_set_status("A skin needs a name", true)
		return false
	_skin.display_name = wanted_name
	_skin.sprite_id = _sprite_id if not _sprite_id.is_empty() else GolferSkinLibrary.DEFAULT_SPRITE_ID
	_skin.worn_by = _worn_by.duplicate()
	return true


func _on_skin_name_changed(text: String) -> void:
	if text.strip_edges() == _skin_name:
		return
	_skin_name = text.strip_edges().left(GolferSkin.MAX_SKIN_NAME_LENGTH)
	_mark_dirty("Name changed - Save Skins to keep it")


func _on_tier_toggled(pressed: bool, tier: int) -> void:
	if pressed and not _worn_by.has(tier):
		_worn_by.append(tier)
		_worn_by.sort()
	elif not pressed:
		_worn_by.erase(tier)
	_mark_dirty("Save Skins to keep which tiers wear this skin")


func _on_new_skin_pressed() -> void:
	var fresh := library.create_skin("New Skin %d" % (library.skins().size() + 1), _sprite_id)
	fresh.create_group("Shirt")
	fresh.create_group("Pants")
	fresh.worn_by = []
	_select_skin(fresh)
	_mark_dirty("New skin - paint its layers, then Save Skins")


## Dress the player's own golfer in this skin. It belongs to the player rather
## than to a save, so GolferSkins writes it to the user settings at once.
func _on_wear_pressed() -> void:
	if _skin == null or not library.has_skin(_skin.id):
		return
	GolferSkins.set_player_skin(_skin)
	_refresh_all()
	_rebuild_preview()


func _on_duplicate_pressed() -> void:
	if _skin == null:
		return
	if not _apply_fields_to_skin():
		return
	var copy := library.duplicate_skin(_skin, "%s Copy" % _skin.display_name)
	if copy == null:
		_set_status("Could not copy this skin", true)
		return
	_select_skin(copy)
	_mark_dirty("Copy made - Save Skins to write it out")


func _on_revert_pressed() -> void:
	if _skin == null:
		return
	var skin := _skin
	_confirm("Throw your copy of %s away and go back to the skin that ships with the game?"
		% skin.display_name, "Revert", func():
			if library.revert_skin(skin):
				_select_skin(library.get_skin(skin.id))
				_set_status("%s is back to the shipped skin" % skin.display_name)
			else:
				_set_status("Could not revert %s" % skin.display_name, true))


func _on_delete_skin_pressed() -> void:
	if _skin == null:
		return
	var skin := _skin
	_confirm("Delete the skin %s? Its groups and layers go with it." % skin.display_name,
		"Delete", func():
			if library.delete_skin(skin):
				_select_skin(GolferSkins.player_skin())
				_set_status("Deleted %s" % skin.display_name)
			else:
				_set_status("Could not delete %s" % skin.display_name, true))


# ── Re-color groups ───────────────────────────────────────────────────────

func _on_group_row_pressed(group_id: int) -> void:
	_active_group = group_id
	_refresh_groups()
	if _canvas != null:
		_canvas.active_group = group_id
		_canvas.queue_redraw()


func _on_new_group_pressed() -> void:
	if _skin == null:
		return
	var group_id := _skin.create_group()
	if group_id == GolferSkinLayer.NO_GROUP:
		_set_status("A skin can carry %d groups" % GolferSkin.MAX_GROUPS, true)
		return
	_active_group = group_id
	_mark_dirty("New group - name it and paint it, then Save Skins")
	_refresh_groups()
	_refresh_canvas()


func _on_group_name_submitted(text: String) -> void:
	if _skin == null or _active_group == GolferSkinLayer.NO_GROUP:
		return
	if not _skin.rename_group(_active_group, text):
		_set_status("A group name has to be free and not empty", true)
		if _group_name_edit != null:
			_group_name_edit.text = str(_skin.group_by_id(_active_group).get("name", ""))
		return
	_mark_dirty("Group renamed - Save Skins to write it out")
	_refresh_groups()


func _on_delete_group_pressed() -> void:
	if _skin == null or _active_group == GolferSkinLayer.NO_GROUP:
		return
	var skin := _skin
	var group_id := _active_group
	var group_name := str(skin.group_by_id(group_id).get("name", ""))
	_confirm("Delete the group %s? Every pixel it owns is freed." % group_name, "Delete", func():
		if not skin.delete_group(group_id):
			return
		_active_group = _active_group_for(skin)
		_mark_dirty("Group deleted - Save Skins to write it out")
		_refresh_groups()
		_refresh_canvas())


func _on_group_color_chosen(color: Color) -> void:
	if _skin == null or _active_group == GolferSkinLayer.NO_GROUP:
		return
	if not _skin.set_group_color(_active_group, color):
		return
	_mark_dirty("Group re-coloured - Save Skins to write it out")
	_refresh_groups()
	_refresh_canvas()
	_rebuild_preview()
	_refresh_frame_strip()


## The colour the Pixels side's brush paints with.
func _on_pixel_color_chosen(color: Color) -> void:
	_pixel_color = color
	if _pixel_color_button != null and _pixel_color_button.color != color:
		_pixel_color_button.set_pick_color(color)


## Which brush width the studio paints and groups with.
func _on_brush_size_selected(index: int) -> void:
	if index < 0 or index >= BRUSH_SIZES.size():
		return
	_brush_size = BRUSH_SIZES[index]
	if _canvas != null:
		_canvas.brush_size = _brush_size
		_canvas.queue_redraw()


# ── Painting ──────────────────────────────────────────────────────────────

## A click on the sprite: on the Pixels side the brush paints the artwork itself
## with the picked colour; on the Groups side it gives the pixels it covers to
## the selected Re-color Group (or, with Fill, the whole run it lands in).
func _on_cell_painted(cell: Vector2i) -> void:
	if _mode == Mode.PIXELS:
		_paint_art(cell, _pixel_color)
		return
	_paint_cell(cell, _active_group, _fill)


## Right-click: erase pixels of the artwork (Pixels) or free them from their
## group (Groups).
func _on_cell_erased(cell: Vector2i) -> void:
	if _mode == Mode.PIXELS:
		_paint_art(cell, Color(0, 0, 0, 0))
		return
	_paint_cell(cell, GolferSkinLayer.NO_GROUP, _fill)


## Alt-click: Pixels picks up the colour already on the pixel (an eyedropper into
## the picker); Groups selects the group the pixel belongs to, which is how the
## grouping is read off the sprite.
func _on_cell_picked(cell: Vector2i) -> void:
	if _skin == null:
		return
	if _mode == Mode.PIXELS:
		_pick_pixel_color(cell)
		return
	_active_group = _skin.layer(_current_key()).get_cell(cell.x, cell.y)
	_refresh_groups()
	if _canvas != null:
		_canvas.active_group = _active_group
		_canvas.queue_redraw()


## Paint the sprite's own pixels with the brush: the colour picked for the
## Pixels side, or - with a transparent colour - erase them, which is what the
## right button does. A painted pixel is the artwork's own colour, so it stops
## belonging to whatever Re-color Group owned it: the Groups side is what colours
## it again.
func _paint_art(cell: Vector2i, color: Color) -> void:
	if _skin == null:
		return
	var key := _current_key()
	var sprite_layer := _skin.layer(key)
	if not sprite_layer.contains(cell.x, cell.y):
		return
	sprite_layer.begin_art(_shipped_art(key))
	var changed := false
	for target in sprite_layer.brush_cells(cell.x, cell.y, _brush_size):
		if sprite_layer.set_cell(target.x, target.y, GolferSkinLayer.NO_GROUP):
			changed = true
		if sprite_layer.set_art_pixel(target.x, target.y, color):
			changed = true
	if not changed:
		return
	_after_art_edit(key, sprite_layer)


## Push an artwork edit through the skin: the group's shade is the brightness of
## its brightest pixel, so a pixel painted in a new colour re-reads it and the
## colour the player picked survives the re-color exactly.
func _after_art_edit(key: String, sprite_layer: GolferSkinLayer) -> void:
	var art := sprite_layer.art_image()
	if art != null:
		_skin.refresh_shades_from(art, key, true)
	_skin.mark_layer_dirty(key)
	_dirty = true
	_mark_dirty("Sprite pixels painted - Save Skins to write them out")
	# Only the sprite on screen and the numbers change: rebuilding the group
	# rows or the whole frame strip for every pixel of a drag would not keep up.
	_refresh_canvas_artwork()


## Take the colour already on a pixel into the picker, so the player can paint
## with a colour the artwork uses.
func _pick_pixel_color(cell: Vector2i) -> void:
	var sprite_layer := _skin.layer(_current_key())
	var color := sprite_layer.art_pixel(cell.x, cell.y)
	if not sprite_layer.has_art():
		var image := _shipped_art(_current_key())
		if image != null and not image.is_empty() and sprite_layer.contains(cell.x, cell.y):
			color = image.get_pixel(cell.x, cell.y)
	if color.a <= 0.0:
		return
	_on_pixel_color_chosen(color)
	if _pixel_color_button != null:
		_pixel_color_button.set_pick_color(color)
	_refresh_status()


## The artwork a sprite ships with, before anything is painted on it.
func _shipped_art(key: String) -> Image:
	if _skin == null:
		return null
	var texture := library.texture_for(_skin, key)
	return texture.get_image() if texture != null else null


## Give one pixel of the sprite on the canvas to a group (NO_GROUP frees it).
## With `fill`, every pixel of the run the click landed in is given to the group
## instead - the whole shirt at once, rather than one texel at a time.
func _paint_cell(cell: Vector2i, group_id: int, fill: bool = false) -> void:
	if _skin == null:
		return
	var sprite_layer := _skin.layer(_current_key())
	var cells: Array[Vector2i] = []
	if fill:
		cells = sprite_layer.flood_cells(cell.x, cell.y, _shipped_art(_current_key()))
	elif _brush_size > 1:
		# The brush covers a footprint of pixels, not just the one clicked.
		for target in sprite_layer.brush_cells(cell.x, cell.y, _brush_size):
			cells.append(target)
	else:
		cells.append(cell)
	var changed := false
	for painted: Vector2i in cells:
		if sprite_layer.get_cell(painted.x, painted.y) == group_id:
			continue
		if sprite_layer.set_cell(painted.x, painted.y, group_id):
			changed = true
	if not changed:
		return
	_skin.mark_layer_dirty(_current_key())
	_dirty = true
	_mark_dirty()
	_refresh_canvas_artwork()


## Painting only re-draws the sprite on the canvas and updates the numbers:
## rebuilding the whole studio for every pixel of a drag would not keep up.
func _refresh_canvas_artwork() -> void:
	if _canvas == null or _skin == null:
		return
	var key := _current_key()
	_canvas.set_artwork(_skin_frame_image(key, false), _skin_frame_image(key, true))
	_canvas.set_layer(_skin.layer(key))
	_canvas.queue_redraw()
	var counts := _group_pixel_counts()
	for group_id in _group_count_labels.keys():
		var label: Label = _group_count_labels[group_id]
		if label != null and is_instance_valid(label):
			label.text = "%d px" % int(counts.get(group_id, 0))
	if _frame_index < _frame_icons.size():
		_frame_icons[_frame_index].texture = _frame_thumb(key)


# ── Studio controls ───────────────────────────────────────────────────────

func _sprite_keys() -> Array[String]:
	if _skin == null:
		return []
	return library.frame_keys(_skin, _animation, _direction)


func _current_key() -> String:
	var keys := _sprite_keys()
	if keys.is_empty():
		return GolferSkin.layer_key(_animation, _direction, 0)
	return keys[clampi(_frame_index, 0, keys.size() - 1)]


## One sprite of the skin: the artwork, or the artwork re-coloured with the
## skin's own group colours.
##
## The canvas deliberately leaves the owner's golfer profile out of it: this is
## the skin the visiting golfers wear, and a group's colour has to be visible
## while it is being picked. The profile colours are what the small golfer in
## the preview wears (see _populate_preview).
func _skin_frame_image(key: String, recolored: bool) -> Image:
	if _skin == null:
		return null
	var texture := library.texture_for(_skin, key)
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	if not recolored:
		return _skin.edited_image(image, key)
	return _skin.recolor_image(image, key)


func _on_animation_selected(index: int) -> void:
	if index < 0 or index >= GolferSkinLibrary.ANIMATIONS.size():
		return
	_animation = GolferSkinLibrary.ANIMATIONS[index]
	_frame_index = 0
	_refresh_canvas()
	_rebuild_preview()


func _on_direction_selected(index: int) -> void:
	if index < 0 or index >= GolferSkinLibrary.DIRECTIONS.size():
		return
	_direction = GolferSkinLibrary.DIRECTIONS[index]
	_frame_index = 0
	_refresh_canvas()
	_rebuild_preview()


func _on_frame_tile_pressed(index: int) -> void:
	_frame_index = index
	_refresh_canvas()
	_rebuild_preview()


func _on_recolor_toggled(pressed: bool) -> void:
	_show_recolor = pressed
	if _canvas != null:
		_canvas.show_recolor = pressed and _mode == Mode.PIXELS
		_canvas.queue_redraw()


func _on_grid_toggled(pressed: bool) -> void:
	_show_grid = pressed
	if _canvas != null:
		_canvas.show_grid = pressed
		_canvas.queue_redraw()


func _on_fill_toggled(pressed: bool) -> void:
	_fill = pressed


func _on_play_pressed() -> void:
	var sprite := _preview_golfer.sprite_node() if _preview_golfer != null else null
	if sprite == null:
		_rebuild_preview()
		return
	if sprite.is_playing():
		sprite.pause()
		_play_button.text = "Play"
	else:
		sprite.play()
		_play_button.text = "Pause"


# ── The golfer preview ────────────────────────────────────────────────────

## The golfer the course owner plays as, wearing the skin being edited, in the
## animation being painted - the same sprite, at real size.
func _rebuild_preview() -> void:
	if _preview_holder == null:
		return
	if _preview_golfer != null and is_instance_valid(_preview_golfer):
		_preview_holder.remove_child(_preview_golfer)
		_preview_golfer.queue_free()
	_preview_golfer = null
	if _skin == null:
		return
	_preview_golfer = Golfer.new()
	_preview_golfer.name = "SkinPreviewGolfer"
	_preview_holder.add_child(_preview_golfer)
	_populate_preview()


func _populate_preview() -> void:
	if _preview_golfer == null or _skin == null:
		return
	_preview_golfer.skin_id = _skin.id
	_preview_golfer.player_profile = GameManager.player_profile
	_preview_golfer.position = _preview_holder.custom_minimum_size * 0.5
	if not _preview_golfer.use_skin_sprites():
		return
	var sprite := _preview_golfer.sprite_node()
	if sprite == null:
		return
	var animation := "%s_%s" % [_animation, _direction]
	if sprite.sprite_frames.has_animation(animation):
		sprite.play(animation)
	sprite.frame = _frame_index
	if _play_button != null:
		_play_button.text = "Pause" if sprite.is_playing() else "Play"


## Ask before something destructive: a ConfirmDialog in the game, the
## confirm_callback in tests.
func _confirm(message: String, confirm_text: String, action: Callable) -> void:
	if confirm_callback.is_valid():
		if bool(confirm_callback.call(message, confirm_text)):
			action.call()
		return
	var dialog := ConfirmDialog.new(message, confirm_text)
	dialog.name = "ConfirmDialog"
	dialog.confirmed.connect(func(): action.call())
	add_child(dialog)
	dialog.show()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		back_requested.emit()
		get_viewport().set_input_as_handled()
