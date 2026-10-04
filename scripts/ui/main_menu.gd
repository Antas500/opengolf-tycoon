extends Control
class_name MainMenu
## MainMenu - Title screen.
##
## Six actions only: Start New Game (company setup → world map), Quick Start
## (default options → world map), Continue (newest save), Load Game, Settings
## and Quit.
##
## The old screen was one centred column of six identical buttons with a
## "Design. Build. Manage." tagline under the title. The tagline is gone and
## the six actions are now laid out by weight instead of being listed:
##
##  * Start New Game and Quick Start are hero cards - big targets, each with
##    one line saying what it does.
##  * Continue is a card carrying the newest save (course, day, slot), so a
##    returning player can see what they are about to resume.
##  * Load Game, Settings and Quit are compact tiles, kept together at the
##    quiet end of the layout so Quit never sits beside a primary action.
##
## The screen rebuilds itself when the window crosses a layout breakpoint
## (see layout_mode_for), so the same six actions use the space well at every
## size:
##
##  * WIDE (>= 1120x620) - clubhouse split: title, hero pair and the version
##    line on the left; a rail with the Continue card and the utility tiles
##    down the right.
##  * TABLET (>= 700x620) - centred column: title, hero pair side by side, a
##    full-width Continue card, then a utility row of three.
##  * LANDSCAPE (wide but short - a rotated phone or a squat browser window) -
##    title on the left, a compact action block on the right, so nothing has
##    to be scrolled to.
##  * PHONE - one scrollable column of full-width cards with a two-up utility
##    row; every target stays at least 46 px tall.
##
## Layout is container-driven inside each mode, so a live drag-resize only
## rebuilds the tree when the arrangement itself changes.
##
## The scenery behind it (MenuBackdrop) and the title mark (MenuFlagMark) are
## drawn in code - no texture assets - matching how the rest of the game draws
## its terrain, its globe and its button glyphs.

signal start_new_game_requested()
signal quick_start_requested()
signal continue_requested(save_name: String)
signal load_game_requested()
signal settings_requested()
signal quit_requested()

# =============================================================================
# LAYOUT MODES
# =============================================================================

enum Layout { WIDE, TABLET, LANDSCAPE, PHONE }

## Window width at which the title screen splits into title + continue rail.
const WIDE_MIN_WIDTH := 1120.0
## Window width at which the phone column becomes a centred tablet column.
const TABLET_MIN_WIDTH := 700.0
## Height a two-panel arrangement needs. Below it a wide window is treated as
## short (rotated phone, squat browser window) and gets the side-by-side
## compact layout instead of the tall ones.
const TALL_MIN_HEIGHT := 620.0
## How far the window has to move (as a share of itself) before the cards are
## sized again for it while staying in the same arrangement.
const REPROPORTION_STEP := 0.12

# =============================================================================
# CARD STYLING
# =============================================================================

const TITLE_TEXT := "OpenGolf Tycoon"
# The palette and card recipe are shared with the Start New Game screen (see
# MenuStyle); the names stay here so the builders below read as before.
const TITLE_COLOR := MenuStyle.TITLE_COLOR

const CARD_RADIUS := MenuStyle.CARD_RADIUS
const CARD_BG := MenuStyle.CARD_BG
const CARD_BG_HOVER := MenuStyle.CARD_BG_HOVER
const CARD_BG_PRESSED := MenuStyle.CARD_BG_PRESSED
const CARD_BG_DISABLED := MenuStyle.CARD_BG_DISABLED
const RAIL_BG := MenuStyle.RAIL_BG

## Where the backdrop's green (and its flag) sits in each arrangement, as a
## share of the window. Kept clear of that arrangement's cards.
const GREEN_ANCHORS := {
	Layout.WIDE: Vector2(0.87, 0.90),
	Layout.TABLET: Vector2(0.84, 0.91),
	Layout.LANDSCAPE: Vector2(0.16, 0.90),
	Layout.PHONE: Vector2(0.80, 0.91),
}

## Widest the two-panel layouts stretch their content. Past this the page
## centres itself instead of pulling the cards into long, thin strips.
const WIDE_MAX_WIDTH := 1800.0
const LANDSCAPE_MAX_WIDTH := 1500.0

## Start New Game is the headline action: gold, the palette's "special" colour.
const ACCENT_PRIMARY := MenuStyle.ACCENT_PRIMARY
## Quick Start and Continue are the green, everyday path into the game.
const ACCENT_SECONDARY := MenuStyle.ACCENT_SECONDARY
const ACCENT_UTILITY := MenuStyle.ACCENT_UTILITY
const ACCENT_QUIT := MenuStyle.ACCENT_QUIT

var _continue_button: Button = null
var _load_button: Button = null
## Layout mode the visible tree was built for; -1 until the first build.
var _layout_mode: int = -1
## The scrollable page wrapper (sized to the window - see _make_page).
var _page: MarginContainer = null
## Window size the visible tree was measured for.
var _built_size := Vector2.ZERO
## Save list snapshot taken once per build (get_save_list() reads the disk).
var _saves: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if has_node("/root/Screen"):
		Screen.changed.connect(_on_screen_changed)
	_build()

func _on_screen_changed(window_size: Vector2, _world_scale: float) -> void:
	if _current_layout() != _layout_mode:
		_build()
		return
	# Same arrangement: the page is sized to the window itself (a
	# ScrollContainer sizes its child to the child's minimum, see _make_page),
	# so it has to be told about the new window even when nothing else changes.
	if _page != null:
		_page.custom_minimum_size = window_size
	# Card heights and type are measured from the window at build time, so the
	# tree is put back through the builders once the window has moved enough
	# for those proportions to look stale - but not on every pixel of a drag.
	if absf(window_size.x - _built_size.x) > _built_size.x * REPROPORTION_STEP \
			or absf(window_size.y - _built_size.y) > _built_size.y * REPROPORTION_STEP:
		_build()

## The layout the current window calls for.
func _current_layout() -> int:
	return layout_mode_for(_window_size())

func _window_size() -> Vector2:
	if has_node("/root/Screen"):
		return Screen.window_size
	return get_viewport().get_visible_rect().size

## Which of the four arrangements a window size gets. Pure, so the breakpoints
## can be unit-tested without a window.
static func layout_mode_for(window_size: Vector2) -> int:
	if window_size.x >= WIDE_MIN_WIDTH and window_size.y >= TALL_MIN_HEIGHT:
		return Layout.WIDE
	if window_size.x >= TABLET_MIN_WIDTH and window_size.y >= TALL_MIN_HEIGHT:
		return Layout.TABLET
	if window_size.x >= TABLET_MIN_WIDTH and window_size.x > window_size.y:
		return Layout.LANDSCAPE
	return Layout.PHONE

# =============================================================================
# BUILD
# =============================================================================

## Tear the screen down and build it again for the current window. The menu is
## rebuilt rather than re-arranged because each layout nests its cards
## differently; the state that matters (the save list) is re-read here.
func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_layout_mode = _current_layout()
	_built_size = _window_size()
	_saves = SaveManager.get_save_list()

	var backdrop := MenuBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Where the drawn flag lands: clear of the cards in each arrangement.
	backdrop.green_anchor = GREEN_ANCHORS[_layout_mode]
	add_child(backdrop)

	match _layout_mode:
		Layout.WIDE:
			_build_wide()
		Layout.TABLET:
			_build_tablet()
		Layout.LANDSCAPE:
			_build_landscape()
		_:
			_build_phone()

## Wide desktop: title and hero cards on the left, a Continue rail on the
## right, so a 1600-2600 px window is a two-column clubhouse rather than a
## narrow strip of buttons in the middle of the screen.
func _build_wide() -> void:
	var view := _window_size()
	var pad := int(clampf(view.x * 0.030, 24.0, 56.0))
	var page := _make_page(pad)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", int(clampf(view.x * 0.020, 18.0, 44.0)))
	_frame(page, view, WIDE_MAX_WIDTH).add_child(row)

	var title_font := int(clampf(minf(view.x / 26.0, view.y / 13.0), 40.0, 78.0))
	var hero_height := clampf(view.y * 0.150, 114.0, 180.0)
	var hero_font := int(clampf(view.x / 62.0, 22.0, 32.0))
	var caption_font := int(clampf(view.x / 128.0, 12.0, 15.0))

	# ── Left: the title lockup, the two ways into the game, the version line.
	var hero_column := VBoxContainer.new()
	hero_column.name = "HeroColumn"
	hero_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_column.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_column.add_theme_constant_override("separation", int(clampf(view.y * 0.026, 14.0, 28.0)))
	row.add_child(hero_column)

	hero_column.add_child(_make_title_block(false, title_font))
	hero_column.add_child(_make_rule(clampf(view.x * 0.085, 90.0, 240.0), 3.0, false))
	hero_column.add_child(_make_hero_row(hero_height, hero_font, caption_font))
	hero_column.add_child(_make_status_line(false, caption_font))

	# ── Right: the rail. Continue is dealt with first, the utilities below it.
	var rail := PanelContainer.new()
	rail.name = "Rail"
	rail.custom_minimum_size = Vector2(clampf(view.x * 0.235, 300.0, 430.0), 0)
	# The rail is a card around its own contents, not a column stretched to the
	# window: it stays centred beside the hero column on a tall display.
	rail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rail.add_theme_stylebox_override("panel", _style(
		RAIL_BG, _with_alpha(UIConstants.COLOR_BORDER, 0.45), 1, CARD_RADIUS + 2,
		int(clampf(view.x * 0.014, 14.0, 24.0)), 18, 20))
	row.add_child(rail)

	var rail_column := VBoxContainer.new()
	rail_column.name = "RailColumn"
	rail_column.alignment = BoxContainer.ALIGNMENT_CENTER
	rail_column.add_theme_constant_override("separation", 12)
	rail.add_child(rail_column)

	rail_column.add_child(_make_kicker("YOUR COURSE", caption_font))
	rail_column.add_child(_make_continue_card(
		clampf(view.y * 0.185, 118.0, 200.0), hero_font - 2, caption_font))
	rail_column.add_child(_make_rule(0.0, 1.0, true, _with_alpha(UIConstants.COLOR_BORDER, 0.5)))
	rail_column.add_child(_make_utility_rows(
		clampf(view.y * 0.072, 54.0, 78.0), hero_font - 6, caption_font, true))

## Tablet: a centred column - title, hero pair side by side, a full-width
## Continue card, then the three utilities in one row.
func _build_tablet() -> void:
	var view := _window_size()
	var pad := int(clampf(view.x * 0.028, 20.0, 34.0))
	var page := _make_page(pad)
	var content_width := minf(view.x - float(pad) * 2.0, 880.0)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.custom_minimum_size = Vector2(content_width, 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", int(clampf(view.y * 0.024, 12.0, 22.0)))
	page.add_child(_centered(column))

	var title_font := int(clampf(view.x / 21.0, 32.0, 50.0))
	var hero_height := clampf(view.y * 0.160, 118.0, 170.0)
	var hero_font := int(clampf(view.x / 46.0, 20.0, 28.0))
	var caption_font := int(clampf(view.x / 92.0, 12.0, 15.0))

	column.add_child(_make_title_block(true, title_font, content_width))
	column.add_child(_make_rule(clampf(content_width * 0.22, 80.0, 200.0), 3.0, true))
	column.add_child(_make_hero_row(hero_height, hero_font, caption_font))
	column.add_child(_make_continue_card(clampf(view.y * 0.150, 104.0, 150.0), hero_font, caption_font))
	column.add_child(_make_utility_rows(clampf(view.y * 0.085, 58.0, 80.0), hero_font - 4, caption_font, false))
	column.add_child(_make_status_line(true, caption_font))

## Wide but short (rotated phone, squat browser window): the title takes the
## left side and the actions the right, so the whole menu fits without
## scrolling — where the tall layouts would have to stack and scroll.
func _build_landscape() -> void:
	var view := _window_size()
	var pad := int(clampf(view.y * 0.055, 12.0, 26.0))
	var page := _make_page(pad)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", int(clampf(view.x * 0.030, 16.0, 34.0)))
	_frame(page, view, LANDSCAPE_MAX_WIDTH).add_child(row)

	var title_font := int(clampf(view.y / 9.5, 26.0, 42.0))
	var hero_height := clampf(view.y * 0.290, 96.0, 150.0)
	var hero_font := int(clampf(view.y / 21.0, 18.0, 24.0))
	var caption_font := int(clampf(view.y / 42.0, 11.0, 14.0))

	var brand := VBoxContainer.new()
	brand.name = "Brand"
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.size_flags_vertical = Control.SIZE_EXPAND_FILL
	brand.size_flags_stretch_ratio = 0.85
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	brand.add_theme_constant_override("separation", int(clampf(view.y * 0.030, 8.0, 18.0)))
	row.add_child(brand)
	brand.add_child(_make_title_block(false, title_font, view.x * 0.36))
	brand.add_child(_make_rule(clampf(view.x * 0.055, 70.0, 160.0), 3.0, false))
	brand.add_child(_make_status_line(false, caption_font))

	var actions := VBoxContainer.new()
	actions.name = "Actions"
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	actions.size_flags_stretch_ratio = 1.15
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", int(clampf(view.y * 0.030, 8.0, 16.0)))
	row.add_child(actions)
	actions.add_child(_make_hero_row(hero_height, hero_font, caption_font))
	actions.add_child(_make_continue_card(clampf(view.y * 0.225, 76.0, 116.0), hero_font, caption_font))
	# No captions on the squat tiles: at ~150 px wide a sentence would only be
	# trimmed to an ellipsis.
	actions.add_child(_make_utility_rows(clampf(view.y * 0.160, 52.0, 76.0), hero_font - 3, 0, false))

## Phone: one column, cards stacked full width, Load and Settings sharing a
## row to save vertical space, Quit on its own quiet line at the bottom.
func _build_phone() -> void:
	var view := _window_size()
	var pad := int(clampf(view.x * 0.045, 12.0, 22.0))
	var page := _make_page(pad)
	var content_width := minf(view.x - float(pad) * 2.0, 460.0)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.custom_minimum_size = Vector2(content_width, 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", int(clampf(view.y * 0.016, 8.0, 16.0)))
	page.add_child(_centered(column))

	var title_font := int(clampf(view.x / 11.0, 26.0, 40.0))
	var hero_font := int(clampf(view.x / 17.0, 19.0, 26.0))
	var caption_font := int(clampf(view.x / 34.0, 11.0, 15.0))
	var hero_height := clampf(view.y * 0.125, 88.0, 118.0)

	column.add_child(_make_title_block(true, title_font, content_width))
	column.add_child(_make_start_card(hero_height, hero_font, caption_font))
	column.add_child(_make_quick_card(hero_height, hero_font, caption_font))
	column.add_child(_make_continue_card(clampf(view.y * 0.110, 78.0, 104.0), hero_font - 1, caption_font))
	column.add_child(_make_phone_utility_row(clampf(view.y * 0.085, 54.0, 76.0), hero_font - 2))
	column.add_child(_make_quit_tile(clampf(view.y * 0.065, 46.0, 62.0), hero_font - 3, 0))
	column.add_child(_make_status_line(true, caption_font))

# =============================================================================
# PAGE FURNITURE
# =============================================================================

## The scrollable page every layout sits in: full-rect, vertical scroll only,
## content centred while it fits and reachable when it does not (short phones,
## heavy translations, large system fonts).
func _make_page(pad: int) -> MarginContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Below the narrowest phone the cards cannot shrink any further (their own
	# minimum width is the floor), so sideways scrolling is allowed rather than
	# clipping the right-hand edge of the layout away.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED \
		if _window_size().x >= 360.0 else ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.name = "Page"
	# A ScrollContainer sizes its child to the child's minimum size, it does not
	# stretch it, so the page asks for the whole window itself. Content that is
	# taller than that grows past it and scrolls; anything shorter stays
	# centred in a full window.
	margin.custom_minimum_size = _window_size()
	_page = margin
	scroll.add_child(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, pad)
	return margin

## A frame that keeps a two-panel layout's content from stretching edge to
## edge on a very wide window: the extra width becomes an even margin either
## side, and the row still fills the page vertically.
func _frame(page: MarginContainer, view: Vector2, max_width: float) -> MarginContainer:
	var frame := MarginContainer.new()
	frame.name = "Frame"
	var side := int(maxf(0.0, (view.x - max_width) * 0.5))
	frame.add_theme_constant_override("margin_left", side)
	frame.add_theme_constant_override("margin_right", side)
	page.add_child(frame)
	return frame

## Wrap a fixed-width column so it is centred in the page, horizontally and
## vertically, while it still fits.
func _centered(column: Control) -> CenterContainer:
	var center := CenterContainer.new()
	center.name = "Center"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(column)
	return center

## Title lockup: the drawn mark and the wordmark in one row. `available_width`
## (0 to skip) keeps the pair inside a narrow column - "OpenGolf Tycoon" plus
## the mark and its gap measure roughly 9.8 x the font size, so the font is
## capped to fit rather than allowed to overflow.
func _make_title_block(centered: bool, title_font: int, available_width: float = 0.0) -> Control:
	var font := title_font
	if available_width > 0.0:
		font = mini(font, int(available_width / 9.8))
	font = maxi(font, 18)

	var row := HBoxContainer.new()
	row.name = "TitleBlock"
	row.alignment = BoxContainer.ALIGNMENT_CENTER if centered else BoxContainer.ALIGNMENT_BEGIN
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if centered else Control.SIZE_SHRINK_BEGIN
	row.add_theme_constant_override("separation", int(float(font) * 0.22))

	var mark := MenuFlagMark.new()
	mark.name = "Mark"
	mark.mark_size = float(font) * 1.05
	row.add_child(mark)

	var label := Label.new()
	label.name = "Title"
	label.text = TITLE_TEXT
	label.add_theme_font_size_override("font_size", font)
	label.add_theme_color_override("font_color", TITLE_COLOR)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row

## A hairline used as a rule under the title or between rail sections. Width 0
## fills whatever it is placed in.
func _make_rule(width: float, thickness: float, centered: bool, color: Color = ACCENT_PRIMARY) -> Control:
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = color
	rule.custom_minimum_size = Vector2(width, thickness)
	if width <= 0.0:
		rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if centered else Control.SIZE_SHRINK_BEGIN
	return rule

## Version and save count - the quiet line that closes the layout.
func _make_status_line(centered: bool, font_size: int) -> Control:
	var version := str(ProjectSettings.get_setting("application/config/version", "0.4.7"))
	var text := "v%s" % version
	if _saves.is_empty():
		text += "  |  no saved courses yet"
	else:
		text += "  |  %d saved course%s" % [_saves.size(), "" if _saves.size() == 1 else "s"]

	var label := Label.new()
	label.name = "Status"
	label.text = text
	label.add_theme_font_size_override("font_size", maxi(font_size, 11))
	label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if centered else Control.SIZE_SHRINK_BEGIN
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _make_kicker(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = "Kicker"
	label.text = text
	label.add_theme_font_size_override("font_size", maxi(font_size, 11))
	label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

# =============================================================================
# ACTIONS
# =============================================================================

## Start New Game and Quick Start side by side, each taking half the row.
func _make_hero_row(height: float, title_font: int, caption_font: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "HeroRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	row.add_child(_make_start_card(height, title_font, caption_font))
	row.add_child(_make_quick_card(height, title_font, caption_font))
	return row

func _make_start_card(height: float, title_font: int, caption_font: int) -> Button:
	var button := _make_card("Start New Game",
		"Set up your company, then buy the location for your first course.",
		"Set up your golf company, then choose where to build your first course",
		height, title_font, caption_font, ACCENT_PRIMARY)
	button.name = "StartNewGameButton"
	button.pressed.connect(func(): start_new_game_requested.emit())
	return button

func _make_quick_card(height: float, title_font: int, caption_font: int) -> Button:
	var button := _make_card("Quick Start",
		"Straight to the world map: random company, Normal difficulty, $100,000.",
		"Jump straight in: random company name, Normal difficulty, $100,000 and all features on",
		height, title_font, caption_font, ACCENT_SECONDARY)
	button.name = "QuickStartButton"
	button.pressed.connect(func(): quick_start_requested.emit())
	return button

## The newest save as a card. The caption names the course, its day and the
## slot it lives in; with no saves the card is disabled and says so.
func _make_continue_card(height: float, title_font: int, caption_font: int) -> Button:
	var newest: Dictionary = _saves[0] if not _saves.is_empty() else {}
	var caption := "No saved courses yet - start a new game to begin one."
	var tooltip := "No saved games yet"
	var accent := ACCENT_UTILITY
	if not newest.is_empty():
		caption = "%s  |  Day %d  |  %s" % [
			newest.get("course_name", ""), int(newest.get("day", 0)), newest.get("name", "")]
		tooltip = "%s — Day %d (%s)" % [
			newest.get("course_name", ""), int(newest.get("day", 0)), newest.get("name", "")]
		accent = ACCENT_SECONDARY

	var button := _make_card("Continue", caption, tooltip, height, title_font, caption_font, accent)
	button.name = "ContinueButton"
	button.disabled = newest.is_empty()
	_continue_button = button
	button.pressed.connect(func(): continue_requested.emit(continue_save_name()))
	return button

## Load Game / Settings / Quit: side by side when the row is roomy, stacked
## down the rail when it is not. `caption_font` 0 leaves the tiles as plain
## labels (the squat-window layout, where a caption would only be truncated).
func _make_utility_rows(height: float, title_font: int, caption_font: int,
		stacked: bool) -> Control:
	var tiles: Array[Button] = [
		_make_load_tile(height, title_font, caption_font),
		_make_settings_tile(height, title_font, caption_font),
		_make_quit_tile(height, title_font, caption_font),
	]
	if stacked:
		var column := VBoxContainer.new()
		column.name = "UtilityRows"
		column.add_theme_constant_override("separation", 12)
		for tile in tiles:
			column.add_child(tile)
		return column

	var row := HBoxContainer.new()
	row.name = "UtilityRows"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	for tile in tiles:
		row.add_child(tile)
	return row

## Phone utility row: Load and Settings share one line. No captions - the
## column is only ~180 px wide, and the labels say it all at this size.
func _make_phone_utility_row(height: float, title_font: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "UtilityRows"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	row.add_child(_make_load_tile(height, title_font, 0))
	row.add_child(_make_settings_tile(height, title_font, 0))
	return row

func _make_load_tile(height: float, title_font: int, caption_font: int) -> Button:
	var caption := "No saved courses yet"
	if not _saves.is_empty():
		caption = "%d saved course%s" % [_saves.size(), "" if _saves.size() == 1 else "s"]
	var button := _make_tile("Load Game", caption, "Choose a saved game", height,
		title_font, caption_font, ACCENT_UTILITY)
	button.name = "LoadGameButton"
	button.disabled = _saves.is_empty()
	if button.disabled:
		button.tooltip_text = "No saved games yet"
	_load_button = button
	button.pressed.connect(func(): load_game_requested.emit())
	return button

func _make_settings_tile(height: float, title_font: int, caption_font: int) -> Button:
	var button := _make_tile("Settings", "Audio, display and gameplay",
		"Audio, display and gameplay options", height, title_font, caption_font, ACCENT_UTILITY)
	button.name = "SettingsButton"
	button.pressed.connect(func(): settings_requested.emit())
	return button

func _make_quit_tile(height: float, title_font: int, caption_font: int) -> Button:
	var button := _make_tile("Quit", "Leave the game", "Leave the game", height,
		title_font, caption_font, ACCENT_QUIT, UIConstants.COLOR_DANGER_MUTED)
	button.name = "QuitButton"
	button.pressed.connect(func(): quit_requested.emit())
	return button

# =============================================================================
# CARD BUILDING BLOCKS
# =============================================================================

## A hero or Continue card: the action's name is the button's own label (so
## tooltips, keyboard focus and tests all read the action), with one line of
## explanation pinned to the card's lower edge. That caption is a child of the
## button with mouse_filter IGNORE, so clicking it clicks the card too.
func _make_card(text: String, caption: String, tooltip: String, height: float,
		title_font: int, caption_font: int, accent: Color) -> Button:
	var button := _make_button_shell(text, tooltip, title_font, UIConstants.COLOR_TEXT)
	var block := _caption_block(caption_font, CAPTION_LINES)
	button.custom_minimum_size.y = maxf(height, float(title_font) * 1.45 + block + 24.0)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_paint_card(button, accent, block, 20, UIConstants.COLOR_TEXT, Color.WHITE)
	if not caption.is_empty():
		button.add_child(_make_caption(caption, caption_font, CAPTION_LINES, UIConstants.COLOR_TEXT_DIM))
	return button

## A compact tile: same card treatment, smaller type, an optional single-line
## caption.
func _make_tile(text: String, caption: String, tooltip: String, height: float,
		title_font: int, caption_font: int, accent: Color,
		text_color: Color = UIConstants.COLOR_TEXT) -> Button:
	var button := _make_button_shell(text, tooltip, title_font, text_color)
	var show_caption := not caption.is_empty() and caption_font > 0
	var block := _caption_block(caption_font, 1) if show_caption else 0.0
	button.custom_minimum_size.y = maxf(height, float(title_font) * 1.45 + block + 24.0)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT if show_caption else HORIZONTAL_ALIGNMENT_CENTER
	var hover_color := Color.WHITE if text_color == UIConstants.COLOR_TEXT else text_color.lightened(0.25)
	_paint_card(button, accent, block, 14, text_color, hover_color)
	if show_caption:
		button.add_child(_make_caption(caption, caption_font, 1, UIConstants.COLOR_TEXT_DIM))
	return button

## Shared Button set-up: full-width and pointing-hand, with the label's own
## width left in the minimum size - a card may be narrower than its text only
## where the layout has room to give it more (never inside a clipped strip).
func _make_button_shell(text: String, tooltip: String, title_font: int, text_color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", title_font)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	return button

## One line (or `lines`) of explanation, anchored to the bottom of its button
## so it moves with the card. Longer text is trimmed with an ellipsis rather
## than allowed to grow up into the title.
func _make_caption(text: String, font_size: int, lines: int, color: Color) -> Label:
	var label := Label.new()
	label.name = "Caption"
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = lines
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = 20.0
	label.offset_right = -20.0
	label.offset_top = -(_caption_block(font_size, lines) + 12.0)
	label.offset_bottom = -12.0
	return label

## How many lines a card caption may take before it is trimmed.
const CAPTION_LINES := 2

## Vertical room a caption of `lines` lines needs at this font size.
static func _caption_block(font_size: int, lines: int) -> float:
	if font_size <= 0 or lines <= 0:
		return 0.0
	return float(font_size) * 1.4 * float(lines)

## Paint a card: dark translucent panel, accent border, hover that lights the
## border up, and content margins that keep the button's own label clear of
## the caption strip along the bottom edge.
func _paint_card(button: Button, accent: Color, caption_block: float, pad: int,
		text_color: Color, hover_color: Color) -> void:
	MenuStyle.paint_card(button, accent, caption_block, pad, text_color, hover_color)

## StyleBoxFlat with uniform side margins, its own top margin and the room a
## caption needs below the label.
static func _style(bg: Color, border: Color, border_width: int, radius: int,
		pad: int, top: int, bottom: int) -> StyleBoxFlat:
	return MenuStyle.flat(bg, border, border_width, radius, pad, top, bottom)

static func _with_alpha(color: Color, alpha: float) -> Color:
	return MenuStyle.with_alpha(color, alpha)

# =============================================================================
# INPUT
# =============================================================================

## The newest save name, or an empty string when there is none.
func continue_save_name() -> String:
	var saves = SaveManager.get_save_list()
	if saves.is_empty():
		return ""
	return str(saves[0].get("name", ""))

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("quick_start"):
		quick_start_requested.emit()
		get_viewport().set_input_as_handled()
