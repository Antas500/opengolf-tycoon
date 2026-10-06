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
## The tools: left-click paints a pixel with the selected Re-color Group,
## right-click frees it, alt-click picks up the group a pixel already belongs to,
## and the Fill switch gives every pixel of the run a click lands in to the
## selected group - the whole of a shirt in one click.
##
## Nothing is written to disk until Save Skins is pressed, so an experiment can
## be abandoned. A built-in skin is copied to the player's own folder the first
## time it is saved and can be reverted to the shipped one afterwards.

signal back_requested()

enum Layout { WIDE, TABLET, PHONE }

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
var _sprite_id: String = ""
var _worn_by: Array[int] = []
## The group the canvas paints with (NO_GROUP frees pixels).
var _active_group: int = GolferSkinLayer.NO_GROUP
## Which animation sprite the canvas is painting.
var _animation: String = "idle"
var _direction: String = "south"
var _frame_index: int = 0
var _show_recolor: bool = true
var _show_grid: bool = true
## Fill gives the whole run of pixels a click lands in to the active group,
## rather than that one pixel (see _paint_cell).
var _fill: bool = false
var _status: String = ""
var _error: bool = false
var _dirty: bool = false
var _layout_mode: int = -1
var _built_size := Vector2.ZERO

# ── Controls the refreshes talk to ────────────────────────────────────────
var _skin_list: ItemList = null
var _skin_name_edit: LineEdit = null
var _sprite_picker: OptionButton = null
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
var _palette: HBoxContainer = null
var _animation_picker: OptionButton = null
var _direction_picker: OptionButton = null
var _frame_strip: HBoxContainer = null
## The frame tiles' textures, updated as the sprite is painted.
var _frame_icons: Array[TextureRect] = []
var _canvas: GolferSkinLayerCanvas = null
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

	_refresh_all()
	_rebuild_preview()



func _make_page() -> MarginContainer:
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
	return margin


func _build_wide(page: MarginContainer) -> void:
	page.add_child(_make_header())
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
	var groups := _make_groups_panel()
	groups.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(groups)
	row.add_child(side)
	row.add_child(_make_studio(true))


func _build_tablet(page: MarginContainer) -> void:
	page.add_child(_make_header())
	var column := VBoxContainer.new()
	column.name = "Columns"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	page.add_child(_frame(column))
	var row := HBoxContainer.new()
	row.name = "Lists"
	row.add_theme_constant_override("separation", 12)
	row.add_child(_make_skins_panel())
	row.add_child(_make_groups_panel())
	column.add_child(row)
	column.add_child(_make_studio(false))


func _build_phone(page: MarginContainer) -> void:
	page.add_child(_make_header())
	var column := VBoxContainer.new()
	column.name = "Columns"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	page.add_child(_frame(column))
	column.add_child(_make_studio(true))
	column.add_child(_make_groups_panel())
	column.add_child(_make_skins_panel())


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

	column.add_child(_make_field_label("Sprite set"))
	_sprite_picker = OptionButton.new()
	_sprite_picker.name = "SpritePicker"
	_sprite_picker.tooltip_text = "The artwork this skin is drawn over"
	_sprite_picker.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	for sprite_id in library.sprite_sets():
		_sprite_picker.add_item(sprite_id.capitalize())
		_sprite_picker.set_item_metadata(_sprite_picker.item_count - 1, sprite_id)
	_sprite_picker.item_selected.connect(_on_sprite_selected)
	column.add_child(_sprite_picker)

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

func _make_groups_panel() -> Control:
	var panel := _make_sheet("GroupsSheet")
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
	_group_name_edit.tooltip_text = "Rename the selected group. Groups called Shirt, Pants, Cap, Hair or Skin also take the colours of the player's own golfer."
	_group_name_edit.text_submitted.connect(_on_group_name_submitted)
	_group_name_edit.focus_exited.connect(func(): _on_group_name_submitted(_group_name_edit.text))
	column.add_child(_group_name_edit)

	var color_row := HBoxContainer.new()
	color_row.name = "GroupColorRow"
	color_row.add_theme_constant_override("separation", 8)
	_group_color_button = _make_button("Colour", "Pick the colour this group is drawn in",
		UIConstants.COLOR_TEXT, 84)
	_group_color_button.name = "GroupColorButton"
	_group_color_button.pressed.connect(_on_group_color_pressed)
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
	_fill_check = CheckBox.new()
	_fill_check.name = "FillCheck"
	_fill_check.text = "Fill"
	_fill_check.tooltip_text = "Fill gives every pixel of the run you click to the group being painted with"
	_fill_check.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_fill_check.button_pressed = _fill
	_fill_check.toggled.connect(_on_fill_toggled)
	if compact:
		# The views go on a row of their own rather than squeezing the pickers.
		var views := HBoxContainer.new()
		views.name = "StudioViews"
		views.add_theme_constant_override("separation", 8)
		views.add_child(_recolor_check)
		views.add_child(_grid_check)
		views.add_child(_fill_check)
		var header_column := VBoxContainer.new()
		header_column.name = "StudioHeader"
		header_column.add_theme_constant_override("separation", 6)
		header_column.add_child(header)
		header_column.add_child(views)
		column.add_child(header_column)
	else:
		header.add_child(_spacer())
		header.add_child(_recolor_check)
		header.add_child(_grid_check)
		header.add_child(_fill_check)
		column.add_child(header)

	_frame_strip = HBoxContainer.new()
	_frame_strip.name = "FrameStrip"
	_frame_strip.add_theme_constant_override("separation", 6)
	column.add_child(_frame_strip)

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

	var palette_row := HBoxContainer.new()
	palette_row.name = "PaletteRow"
	palette_row.add_theme_constant_override("separation", 8)
	palette_row.add_child(_make_field_label("Paint with"))
	_palette = HBoxContainer.new()
	_palette.name = "Palette"
	_palette.add_theme_constant_override("separation", 4)
	palette_row.add_child(_palette)

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
		# The palette keeps a row of its own on a phone, with the frame and the
		# play button on the next one down.
		palette_row.add_child(_spacer())
		column.add_child(palette_row)
		var controls := HBoxContainer.new()
		controls.name = "StudioControls"
		controls.add_theme_constant_override("separation", 8)
		controls.add_child(_frame_label)
		controls.add_child(_spacer())
		controls.add_child(_play_button)
		column.add_child(controls)
	else:
		var footer := HBoxContainer.new()
		footer.name = "StudioFooter"
		footer.add_theme_constant_override("separation", 8)
		footer.add_child(palette_row)
		footer.add_child(_spacer())
		footer.add_child(_frame_label)
		footer.add_child(_play_button)
		column.add_child(footer)

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
	hint.text = "Your golfer wearing this skin. Left-click paints a pixel with the selected group, right-click frees it, alt-click picks up the group already on it."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	hint.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_row.add_child(hint)
	column.add_child(preview_row)
	return panel


# =============================================================================
# SMALL WIDGETS
# =============================================================================

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
	if _sprite_picker != null:
		for index in _sprite_picker.item_count:
			if str(_sprite_picker.get_item_metadata(index)) == _sprite_id:
				_sprite_picker.select(index)
				break
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
		var color: Color = active.get("color", Color.WHITE)
		_group_color_button.add_theme_color_override("font_color",
			color if not active.is_empty() else UIConstants.COLOR_TEXT_MUTED)
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
	_canvas.show_recolor = _show_recolor
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


## Push the editable copies (name, sprite set, tiers) onto the skin itself.
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


## Change the artwork the skin is drawn over. The layers already read keep
## their pixels; any that no longer fit the new sprite are dropped (see
## GolferSkinLayer.resize).
func _on_sprite_selected(index: int) -> void:
	if _sprite_picker == null or index < 0 or index >= _sprite_picker.item_count:
		return
	var sprite_id := str(_sprite_picker.get_item_metadata(index))
	if sprite_id.is_empty() or sprite_id == _sprite_id:
		return
	_sprite_id = sprite_id
	if _skin != null:
		var sprite_size := library.sprite_size_of(sprite_id)
		_skin.sprite_size = sprite_size
		_skin.art_root = GolferSkinLibrary.SPRITE_ROOT.path_join(sprite_id).path_join("animations")
		for key in _skin.loaded_layer_keys():
			_skin.layer(key).resize(sprite_size.x, sprite_size.y)
	_frame_index = 0
	_mark_dirty("Sprite set changed - Save Skins to write it out")
	_refresh_canvas()
	_rebuild_preview()


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


func _on_group_color_pressed() -> void:
	if _skin == null or _active_group == GolferSkinLayer.NO_GROUP:
		return
	var group := _skin.group_by_id(_active_group)
	if group.is_empty():
		return
	_open_color_picker(group.get("color", Color.WHITE), _on_group_color_chosen)


## Show a colour picker at a fixed spot; the callback gets the chosen colour.
func _open_color_picker(color: Color, on_chosen: Callable) -> void:
	var picker := ColorPicker.new()
	picker.name = "SkinColorPicker"
	picker.color = color
	picker.edit_alpha = false
	picker.color_changed.connect(func(value: Color): on_chosen.call(value))
	add_child(picker)
	picker.position = Vector2(120.0, 160.0)
	picker.popup()


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


# ── Painting ──────────────────────────────────────────────────────────────

func _on_cell_painted(cell: Vector2i) -> void:
	_paint_cell(cell, _active_group, _fill)


func _on_cell_erased(cell: Vector2i) -> void:
	_paint_cell(cell, GolferSkinLayer.NO_GROUP, _fill)


func _on_cell_picked(cell: Vector2i) -> void:
	if _skin == null:
		return
	_active_group = _skin.layer(_current_key()).get_cell(cell.x, cell.y)
	_refresh_groups()
	if _canvas != null:
		_canvas.active_group = _active_group
		_canvas.queue_redraw()


## Give one pixel of the sprite on the canvas to a group (NO_GROUP frees it).
## With `fill`, every pixel of the run the click landed in is given to the group
## instead - the whole shirt at once, rather than one texel at a time.
func _paint_cell(cell: Vector2i, group_id: int, fill: bool = false) -> void:
	if _skin == null:
		return
	var sprite_layer := _skin.layer(_current_key())
	var cells: Array[Vector2i] = [cell]
	if fill:
		cells = sprite_layer.flood_cells(cell.x, cell.y, _canvas.image if _canvas != null else null)
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


## Painting only re-colours the sprite on the canvas and updates the numbers:
## rebuilding the whole studio for every pixel of a drag would not keep up.
func _refresh_canvas_artwork() -> void:
	if _canvas == null or _skin == null:
		return
	var key := _current_key()
	_canvas.set_preview(_skin_frame_image(key, true))
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
		return image
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
		_canvas.show_recolor = pressed
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
