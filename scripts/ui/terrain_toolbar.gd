extends PanelContainer
class_name TerrainToolbar
## TerrainToolbar - Tabbed toolbar docked on the right end of the bottom bar.
##
## Nine tabs:
##  - Course Terrain: one course, hazard & landscape tiles honeycomb, with the brush controls pinned to the page's bottom-left corner so they ride above the tiles instead of scrolling with them; the Open Hole action nestles into the notch between the tee box and the green tiles it pairs. Every tile on this tab replaces every other tile (ground, wild flowers and trees) and is never touched by the Bulldozer.
##  - Improvements:   walking path tile leading the decoration tiles honeycomb (the garden shed catalogue), with the Bulldozer pinned to the bottom-left corner
##  - Buildings:      optional amenity catalogue; the required clubhouse is
##                    supplied with every course, with the Bulldozer pinned to
##                    the bottom-left corner
##  - Elevation:      the Vertex, Flat Square and Gradual Square selector tools in one honeycomb, with the Elevation Brush (size and shape) the two Square tools share nestled into the notch between them — the size stepper in the V above the point where those tiles meet, the shape toggle in the V below it — while the terrain brush stays the Course Terrain tab's own
##  - Holes:          one button per course hole, three to a column, each opening that hole's context menu (the buttons are filled by main.gd)
##  - Golfers:        who is on the course, four golfers to a column, beside the recent rounds, six rounds to a column
##  - Player:         play the course, tournaments, player skills
##  - Club:           land, marketing, milestones, scorecard
##  - Staff:          hire/fire staff, course condition, payroll, and effects
##
## Content within tabs is laid out horizontally and scrolls horizontally when
## overflowing the available tab width. The Bulldozer lives on the two tabs
## whose tiles it can remove (Improvements and Buildings), pinned to each
## page's bottom-left corner so it stays put while the shelf scrolls. The
## Course Terrain brush controls are pinned to that same corner of their page
## for the same reason: the brush belongs to every tile on the tab, so it sits
## above the shelf rather than scrolling away with it.

signal course_review_pressed
signal tool_selected(tool_type: int)
signal open_hole_pressed
signal building_placement_pressed
signal building_selected(building_type: String)
signal decoration_placement_pressed
signal decoration_selected(decoration_type: String)
signal elevation_tool_pressed(tool_name: String)
signal elevation_brush_size_changed(new_size: int)
signal elevation_brush_shape_changed(square_shape: bool)
signal bulldozer_pressed
signal brush_size_changed(new_size: int)
signal brush_shape_changed(round_shape: bool)
signal play_course_pressed
signal tournaments_pressed
signal land_pressed
signal marketing_pressed
signal milestones_pressed
signal scorecard_pressed
signal golfer_row_clicked(golfer_id: int)
## Ask main.gd to start (index >= 0) or cancel (index < 0) repositioning a staff
## member's designated area.
signal staff_area_move_requested(staff_index: int)

enum Tab { TERRAIN, IMPROVEMENTS, BUILDINGS, ELEVATION, HOLES, GOLFERS, PLAYER, CLUB, STAFF }

const TAB_TITLES := {
	Tab.TERRAIN: "Terrain",
	Tab.IMPROVEMENTS: "Improvements",
	Tab.BUILDINGS: "Buildings",
	Tab.ELEVATION: "Elevation",
	Tab.HOLES: "Holes",
	Tab.GOLFERS: "Golfers",
	Tab.PLAYER: "Player",
	Tab.CLUB: "Club",
	Tab.STAFF: "Staff",
}

const TAB_TOOLTIPS := {
	Tab.TERRAIN: "Course Terrain",
	Tab.IMPROVEMENTS: "Improvements",
	Tab.BUILDINGS: "Buildings",
	Tab.ELEVATION: "Elevation",
	Tab.HOLES: "Course Holes",
	Tab.GOLFERS: "Golfers",
	Tab.PLAYER: "Player",
	Tab.CLUB: "Club",
	Tab.STAFF: "Staff",
}

const TOOL_TAB_MAP := {
	TerrainTypes.Type.TEE_BOX: Tab.TERRAIN,
	TerrainTypes.Type.GREEN: Tab.TERRAIN,
	TerrainTypes.Type.BUNKER: Tab.TERRAIN,
	TerrainTypes.Type.ROUGH: Tab.TERRAIN,
	TerrainTypes.Type.POT_BUNKER: Tab.TERRAIN,
	TerrainTypes.Type.STREAM: Tab.TERRAIN,
	TerrainTypes.Type.WATER: Tab.TERRAIN,
	TerrainTypes.Type.FAIRWAY: Tab.TERRAIN,
	TerrainTypes.Type.FIRM_FAIRWAY: Tab.TERRAIN,
	TerrainTypes.Type.DEEP_ROUGH: Tab.TERRAIN,
	TerrainTypes.Type.WASTE_BUNKER: Tab.TERRAIN,
	TerrainTypes.Type.BRUSH: Tab.TERRAIN,
	TerrainTypes.Type.ROCKS: Tab.TERRAIN,
	TerrainTypes.Type.SMALL_BOULDERS: Tab.TERRAIN,
	TerrainTypes.Type.LARGE_BOULDERS: Tab.TERRAIN,
	TerrainTypes.Type.OUT_OF_BOUNDS: Tab.TERRAIN,
	TerrainTypes.Type.TREES: Tab.TERRAIN,
	TerrainTypes.Type.OAK: Tab.TERRAIN,
	TerrainTypes.Type.PINE: Tab.TERRAIN,
	TerrainTypes.Type.MAPLE: Tab.TERRAIN,
	TerrainTypes.Type.BIRCH: Tab.TERRAIN,
	TerrainTypes.Type.CACTUS: Tab.TERRAIN,
	TerrainTypes.Type.FESCUE: Tab.TERRAIN,
	TerrainTypes.Type.CATTAILS: Tab.TERRAIN,
	TerrainTypes.Type.SHRUB: Tab.TERRAIN,
	TerrainTypes.Type.PALM: Tab.TERRAIN,
	TerrainTypes.Type.DEAD_TREE: Tab.TERRAIN,
	TerrainTypes.Type.HEATHER: Tab.TERRAIN,
	"open_hole": Tab.TERRAIN,
	TerrainTypes.Type.PATH: Tab.IMPROVEMENTS,
	TerrainTypes.Type.FLOWER_BED: Tab.TERRAIN,
	"decoration": Tab.IMPROVEMENTS,
	"building": Tab.BUILDINGS,
	"vertex": Tab.ELEVATION,
	"flat": Tab.ELEVATION,
	"gradual": Tab.ELEVATION,
	"play_course": Tab.PLAYER,
	"tournaments": Tab.PLAYER,
	"land": Tab.CLUB,
	"marketing": Tab.CLUB,
	"milestones": Tab.CLUB,
	"scorecard": Tab.CLUB,
}

## Shift + number keys pick the extra course tiles: the harsher variants of
## Rough (2), Bunker (5) and Water (6), then the stony ground — Rocks (7),
## Small Boulders (9) and Large Boulders (0) — and Brush (8).
const SHIFT_TERRAIN_HOTKEYS := {
	KEY_2: TerrainTypes.Type.DEEP_ROUGH,
	KEY_5: TerrainTypes.Type.POT_BUNKER,
	KEY_6: TerrainTypes.Type.STREAM,
	KEY_7: TerrainTypes.Type.ROCKS,
	KEY_8: TerrainTypes.Type.BRUSH,
	KEY_9: TerrainTypes.Type.SMALL_BOULDERS,
	KEY_0: TerrainTypes.Type.LARGE_BOULDERS,
}

const TOOL_ROW_HEIGHT := 30
const COURSE_TILE_COLUMNS := 8  # Top row runs tee -> out of bounds, bottom row fairway -> large boulders
const TILE_ROWS := 2  # Course and building tiles always sit in two interlocking rows
## Tiles that lead the Improvements honeycomb ahead of the decoration
## catalogue — just the walking path, which opens the top row. The shelf's
## width counts it, so adding the path keeps the two rows balanced.
const IMPROVEMENTS_LEAD_TILES := 1
## Vertical rhythm of the tile rows: two rows of TerrainTileButton.BUTTON_SIZE
## tiles span 1.5 tiles, plus the gap where the lower row tucks into the
## notches of the row above, plus the breathing room kept above the first row
## and below the last — together filling the toolbar page height without the
## rows touching each other or the edges of the page.
const TILE_H_SEPARATION := 8
const TILE_V_SEPARATION := 20
const TILE_V_PADDING := 20
## The Elevation tab's three Square Selectors share one honeycomb of a single
## row — Vertex, Flat Square, Gradual Square.
const ELEVATION_SELECTOR_COLUMNS := 3
## Flow slot of the Flat Square selector: the tile to the left of the notch the
## Elevation Brush fills, with Gradual Square following it along the row.
const ELEVATION_BRUSH_NOTCH_SLOT := 1
## Half the course tabs' vertical padding: the selector diamonds are twice as
## tall, so their single row fills the same page height as the two interlocking
## course rows and the toolbar never changes height with the tab.
const ELEVATION_V_PADDING := 15
const MAX_RECENT_ROUNDS := 30
## Paint-brush sizes in tiles. Same 1×1 through 9×9 steps as the Elevation Brush.
const BRUSH_SIZES: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
## Brush controls pinned to the Course Terrain page's bottom-left corner: a
## 2x2 plate of square cells (shape, size, smaller, bigger). The plate is held
## this narrow so its right edge stops short of the tile diamonds beside it —
## the staggered bottom row leaves that corner of the page empty, so the brush
## floats above the shelf without ever covering a tile.
const BRUSH_DOCK_CELL := 24.0
const BRUSH_DOCK_GAP := 2.0
const BRUSH_DOCK_PADDING := 1.0
## Same corner margin the pinned Bulldozer keeps on the other two tabs.
const BRUSH_DOCK_MARGIN := BulldozerButton.CORNER_MARGIN
const BRUSH_DOCK_TOOLTIP := "Paint brush: shape, size, smaller and bigger. Stays put while the tiles scroll."
## Holes stack three deep per column and the columns run off to the right, so
## the tab grows along the axis the page already scrolls on and never past the
## bottom bar's height.
const HOLE_COLUMN_HEIGHT := 3
## Golfers on the course stack four deep per column, for the same reason: the
## columns run off to the right where the page scrolls, so a busy course grows
## sideways instead of downwards past the bottom bar's height.
const GOLFER_COLUMN_HEIGHT := 4
const GOLFER_COLUMN_GAP := 10  # Between two columns of golfers
const GOLFER_ROW_GAP := 4  # Between two golfers in the same column
## Recent rounds stack six deep per column — they are one-line labels, so six of
## them still sit under the tab bar while the columns run off to the right.
const RECENT_ROUND_COLUMN_HEIGHT := 6
const RECENT_ROUND_COLUMN_GAP := 14  # Between two columns of rounds
const RECENT_ROUND_ROW_GAP := 4  # Between two rounds in the same column
const OPEN_HOLE_TOOLTIP := "Pair the waiting tee box with the waiting green with a hole"
const OPEN_HOLE_BLOCKED_TOOLTIP := "Needs exactly one unused tee box and one unused green with a hole"
## What the Bulldozer removes — improvements and buildings only. Course
## Terrain tiles are ground paint: repaint them with another tile instead.
const BULLDOZER_TOOLTIP := "Demolish decorations, walking paths and buildings. Click or drag over them. Fees: $5 per path tile, $20 per decoration or building. Course Terrain tiles are not affected — any Course Terrain tile replaces any other, including trees."

var hole_grid: GridContainer = null  # Course holes buttons, three to a column (filled by main.gd)
var golfer_data_provider: Callable = Callable()  # -> Array of golfer row dicts

var _current_tool: int = -1
var _tool_buttons: Dictionary = {}  # tool_type -> ToolButton
var _tab_bar: TabBar = null
var _pages: Array[Control] = []  # One wrapper per tab; the scroll + fixed chrome
var _bulldozer_buttons: Array[BulldozerButton] = []  # Pinned to Improvements & Buildings
var _brush_dock: PanelContainer = null  # Pinned to the Course Terrain corner
var _brush_size: int = 1
var _round_brush := true
var _brush_limit: int = HoleLayout.UNLIMITED_BRUSH  # 1 = current tool paints a single tile
var _brush_labels: Array[Label] = []
var _brush_buttons: Array[Button] = []
var _brush_shape_buttons: Array[Button] = []
# Elevation brush: the Square Selector tools share one size and shape,
# separate from the terrain paint brush above. Switching between Flat and
# Gradual keeps the same settings, and the controls stay usable even when
# neither Square tool is selected. The two controls themselves are notch cells
# between the Square selectors, not a group of their own beside the row
# (see _add_elevation_brush_notches).
var _elevation_tool: String = ""  # "vertex" | "flat" | "gradual" | "" (none)
var _elevation_size: int = 3
var _elevation_square := true
var _elevation_brush_size_notches: Array[ElevationBrushSizeNotch] = []
var _elevation_brush_labels: Array[Label] = []
var _elevation_brush_buttons: Array[Button] = []
var _elevation_brush_shape_buttons: Array[ElevationBrushNotchButton] = []
var _open_hole_buttons: Array[ToolButton] = []
var _green_tile_button: TerrainTileButton = null
var _tee_tile_button: TerrainTileButton = null
var _green_places_cup := true
var _tee_box_can_place: bool = true
var _tee_box_blocker: String = ""
var _active_golfers_box: HBoxContainer = null  # Shelf of columns, four golfers deep
var _recent_rounds_box: HBoxContainer = null  # Shelf of columns, six rounds deep
var _recent_rounds: Array[Dictionary] = []
var player_tab: PlayerTab
var _building_registry: Dictionary = {}
var _building_shelf: TileHoneycomb = null
var _decoration_registry: Dictionary = {}
var _decoration_shelf: TileHoneycomb = null
var _decoration_tiles: Dictionary = {}  # decoration type -> DecorationTileButton
var _path_tile: TerrainTileButton = null  # Walking path tile leading the shelf
var _course_tiles: TileHoneycomb = null
var _elevation_selectors: TileHoneycomb = null  # Vertex / Flat Square / Gradual Square
var _landscape_buttons: Array[Node] = []
var _selected_string_tool: String = ""
var _refresh_timer: Timer = null
var _staff_panel: StaffPanel = null

func _ready() -> void:
	_build_ui()
	EventBus.theme_changed.connect(_on_theme_changed)

func _exit_tree() -> void:
	if EventBus.theme_changed.is_connected(_on_theme_changed):
		EventBus.theme_changed.disconnect(_on_theme_changed)

func _build_ui() -> void:
	# Panel style — docked flush into the bottom bar corner
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = UIConstants.COLOR_BG_PANEL
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_right = 0
	panel_style.corner_radius_bottom_left = 0
	panel_style.content_margin_left = 0
	panel_style.content_margin_right = 0
	panel_style.content_margin_top = 2
	panel_style.content_margin_bottom = 2
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 0
	panel_style.border_color = UIConstants.COLOR_BORDER
	add_theme_stylebox_override("panel", panel_style)

	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(300, 0)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 2)
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(main_vbox)

	_build_tab_bar(main_vbox)

	var pages_container = PanelContainer.new()
	var pages_style = StyleBoxEmpty.new()
	pages_container.add_theme_stylebox_override("panel", pages_style)
	pages_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(pages_container)

	# Build one horizontally-scrollable page per tab
	for tab_index in TAB_TITLES.size():
		var page = _build_page(tab_index)
		page.visible = (tab_index == Tab.TERRAIN)
		pages_container.add_child(page)
		_pages.append(page)

	_build_refresh_timer()

func _build_tab_bar(parent: VBoxContainer) -> void:
	_tab_bar = TabBar.new()
	_tab_bar.focus_mode = Control.FOCUS_NONE
	_tab_bar.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_tab_bar.scrolling_enabled = true
	_tab_bar.tab_alignment = TabBar.ALIGNMENT_LEFT
	_tab_bar.custom_minimum_size = Vector2(0, 24)

	# Compact tab styles
	var tab_selected = StyleBoxFlat.new()
	tab_selected.bg_color = UIConstants.COLOR_PRIMARY
	tab_selected.corner_radius_top_left = 4
	tab_selected.corner_radius_top_right = 4
	tab_selected.content_margin_left = 8
	tab_selected.content_margin_right = 8
	tab_selected.content_margin_top = 2
	tab_selected.content_margin_bottom = 2
	tab_selected.border_width_bottom = 2
	tab_selected.border_color = UIConstants.COLOR_GOLD

	var tab_unselected = StyleBoxFlat.new()
	tab_unselected.bg_color = UIConstants.COLOR_BG_BUTTON
	tab_unselected.corner_radius_top_left = 4
	tab_unselected.corner_radius_top_right = 4
	tab_unselected.content_margin_left = 8
	tab_unselected.content_margin_right = 8
	tab_unselected.content_margin_top = 2
	tab_unselected.content_margin_bottom = 2
	tab_unselected.border_width_bottom = 2
	tab_unselected.border_color = UIConstants.COLOR_BORDER

	var tab_panel = StyleBoxFlat.new()
	tab_panel.bg_color = Color(UIConstants.COLOR_BG_DARK, 0.0)
	tab_panel.content_margin_top = 0
	tab_panel.content_margin_bottom = 0

	_tab_bar.add_theme_stylebox_override("tab_selected", tab_selected)
	_tab_bar.add_theme_stylebox_override("tab_unselected", tab_unselected)
	_tab_bar.add_theme_stylebox_override("tab_hovered", tab_selected)
	_tab_bar.add_theme_stylebox_override("panel", tab_panel)
	_tab_bar.add_theme_color_override("font_selected_color", UIConstants.COLOR_TEXT)
	_tab_bar.add_theme_color_override("font_unselected_color", UIConstants.COLOR_TEXT_DIM)
	_tab_bar.add_theme_color_override("font_hovered_color", UIConstants.COLOR_TEXT)

	for tab_index in TAB_TITLES.size():
		_tab_bar.add_tab(TAB_TITLES[tab_index])
		_tab_bar.set_tab_tooltip(tab_index, TAB_TOOLTIPS[tab_index])

	_tab_bar.tab_changed.connect(_on_tab_changed)
	parent.add_child(_tab_bar)

func _build_page(tab_index: int) -> Control:
	# Each page is a plain wrapper Control holding the horizontally-scrollable
	# content plus any chrome pinned to the page itself (the Bulldozer on the
	# Improvements and Buildings tabs) so it never scrolls away with the shelf.
	var page = Control.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.gui_input.connect(_on_scroll_gui_input.bind(scroll))
	# A plain Control does not inherit its children's minimum size, so keep the
	# page at least as tall as its scrolling shelf — the same height contract
	# the scroll-only pages used to hand the toolbar.
	scroll.minimum_size_changed.connect(
		func() -> void: page.custom_minimum_size = scroll.get_combined_minimum_size())
	page.add_child(scroll)
	page.custom_minimum_size = scroll.get_combined_minimum_size()

	var h_bar = scroll.get_h_scroll_bar()
	if h_bar:
		h_bar.custom_minimum_size = Vector2(0, 4)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	scroll.add_child(hbox)

	match tab_index:
		Tab.TERRAIN:
			_build_terrain_tab(hbox)
			_pin_brush_dock(page)
		Tab.IMPROVEMENTS:
			_build_improvements_tab(hbox)
			_pin_bulldozer_button(page)
		Tab.BUILDINGS:
			_build_buildings_tab(hbox)
			_pin_bulldozer_button(page)
		Tab.ELEVATION:
			_build_elevation_tab(hbox)
		Tab.HOLES:
			_build_holes_tab(hbox)
		Tab.GOLFERS:
			_build_golfers_tab(hbox)
		Tab.PLAYER:
			_build_player_tab(hbox)
		Tab.CLUB:
			_build_club_tab(hbox)
		Tab.STAFF:
			_build_staff_tab(hbox)

	return page

## Pin the round Bulldozer button to a page's bottom-left corner. Anchored to
## the page (not the scrolling shelf) so it stays put while tiles scroll by.
func _pin_bulldozer_button(page: Control) -> void:
	var btn := BulldozerButton.new()
	btn.name = "BulldozerButton"
	btn.accessibility_name = "Bulldozer"
	btn.accessibility_description = BULLDOZER_TOOLTIP
	btn.pressed.connect(_on_tool_button_pressed.bind("bulldozer"))
	page.add_child(btn)
	btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	btn.offset_left = BulldozerButton.CORNER_MARGIN
	btn.offset_top = -BulldozerButton.CORNER_MARGIN - BulldozerButton.BUTTON_DIAMETER
	btn.offset_right = BulldozerButton.CORNER_MARGIN + BulldozerButton.BUTTON_DIAMETER
	btn.offset_bottom = -BulldozerButton.CORNER_MARGIN
	_bulldozer_buttons.append(btn)

## Pin the Course Terrain brush controls to the page's bottom-left corner: a
## compact plate of four square cells — brush shape, brush size, smaller,
## bigger. Anchored to the page (not the scrolling shelf) so the brush rides
## above the tiles and stays put while the catalogue scrolls beneath it, the
## same way the Bulldozer stays put on the two tabs it belongs to. The plate
## fits the corner the staggered tile rows leave empty, so it floats over the
## shelf without covering a single tile diamond.
func _pin_brush_dock(page: Control) -> void:
	var dock := PanelContainer.new()
	dock.name = "BrushDock"
	dock.tooltip_text = BRUSH_DOCK_TOOLTIP
	dock.mouse_filter = Control.MOUSE_FILTER_STOP
	dock.focus_mode = Control.FOCUS_NONE
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(UIConstants.COLOR_BG_PANEL, 0.9)
	for corner in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_right", "corner_radius_bottom_left"]:
		plate.set(corner, 6)
	for margin in ["content_margin_left", "content_margin_top",
			"content_margin_right", "content_margin_bottom"]:
		plate.set(margin, BRUSH_DOCK_PADDING)
	dock.add_theme_stylebox_override("panel", plate)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", int(BRUSH_DOCK_GAP))
	dock.add_child(stack)

	# Shape and the size it paints with on top, the stepper underneath.
	var shape_row := HBoxContainer.new()
	shape_row.add_theme_constant_override("separation", int(BRUSH_DOCK_GAP))
	stack.add_child(shape_row)
	var shape := _create_brush_shape(Vector2(BRUSH_DOCK_CELL, BRUSH_DOCK_CELL))
	_style_dock_cell(shape)
	shape_row.add_child(shape)
	shape_row.add_child(_create_brush_size_chip())

	var step_row := HBoxContainer.new()
	step_row.add_theme_constant_override("separation", int(BRUSH_DOCK_GAP))
	stack.add_child(step_row)
	step_row.add_child(_create_brush_step_button("-", "Smaller brush", _on_brush_decrease))
	step_row.add_child(_create_brush_step_button("+", "Bigger brush", _on_brush_increase))

	page.add_child(dock)
	var side := brush_dock_side()
	dock.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	dock.offset_left = BRUSH_DOCK_MARGIN
	dock.offset_top = -BRUSH_DOCK_MARGIN - side
	dock.offset_right = BRUSH_DOCK_MARGIN + side
	dock.offset_bottom = -BRUSH_DOCK_MARGIN
	_brush_dock = dock
	_apply_brush_limit()

## Edge of the square brush plate: two cells, the gap between them and the
## plate's own padding. The plate is deliberately held this narrow so its right
## edge stops before the staggered bottom row's first tile begins.
static func brush_dock_side() -> float:
	return BRUSH_DOCK_CELL * 2.0 + BRUSH_DOCK_GAP + BRUSH_DOCK_PADDING * 2.0

## Show on every pinned Bulldozer whether bulldozer mode is running.
func set_bulldozer_active(active: bool) -> void:
	for btn in _bulldozer_buttons:
		if is_instance_valid(btn):
			btn.set_active(active)

## The horizontally-scrollable shelf of a tab page (the wrapper's full-rect child).
func page_scroll(tab_index: int) -> ScrollContainer:
	return _pages[tab_index].get_child(0) as ScrollContainer

## The content row a tab builder laid its groups into.
func page_content(tab_index: int) -> HBoxContainer:
	return page_scroll(tab_index).get_child(0) as HBoxContainer

func _on_scroll_gui_input(event: InputEvent, scroll: ScrollContainer) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll.scroll_horizontal = maxi(0, scroll.scroll_horizontal - 50)
			scroll.accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll.scroll_horizontal += 50
			scroll.accept_event()

# =============================================================================
# Tab Builders (Horizontal Layouts)
# =============================================================================

func _build_terrain_tab(hbox: HBoxContainer) -> void:
	# The tab is nothing but the tile honeycomb: the brush controls it paints
	# with are pinned to the page's bottom-left corner (see _pin_brush_dock) so
	# they stay above the tiles instead of scrolling off with them. (Demolition
	# is not a course tool: the Bulldozer is pinned to the Improvements and
	# Buildings tabs, whose tiles it can remove. Open Hole is not a paint tool
	# either — it nestles between the tee and green tiles it pairs, see
	# _add_open_hole_notch.)

	# The course tiles share one honeycomb of two rows, the bottom row shifted
	# half a tile right so each diamond drops into a notch between the two tiles
	# above it. Top row: Tee Box, Green, Bunker, Rough, Pot Bunker, Stream,
	# Water, Out of Bounds. Bottom row: Fairway, Firm Fairway, Deep Rough,
	# Waste Bunker, Brush, Rocks, Small Boulders, Large Boulders.
	var tiles_grid = TileHoneycomb.new()
	_course_tiles = tiles_grid
	tiles_grid.name = "CourseTilesGrid"
	tiles_grid.columns = COURSE_TILE_COLUMNS
	tiles_grid.tile_size = TerrainTileButton.BUTTON_SIZE
	tiles_grid.h_separation = TILE_H_SEPARATION
	tiles_grid.v_separation = TILE_V_SEPARATION
	tiles_grid.v_padding = TILE_V_PADDING
	tiles_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Top row: the tee and the green first, then the hazards and trouble.
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.TEE_BOX, "name": "Tee Box", "hotkey": "4", "desc": "Tee for one hole — a single tile (1x1). Only one tee box may wait on the course at a time", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.GREEN, "name": "Green", "hotkey": "3", "desc": "Next green placement is a Green With Hole (one tile with a cup). The flag on this tile shows when it will place a cup.", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.BUNKER, "name": "Bunker", "hotkey": "5", "desc": "Sand trap hazard", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.ROUGH, "name": "Rough", "hotkey": "2", "desc": "Longer grass bordering fairways", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.POT_BUNKER, "name": "Pot Bunker", "hotkey": "Shift+5", "desc": "Small, deep bunker with a steep stacked-turf face. Wedge only, and the ball barely advances", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.STREAM, "name": "Stream", "hotkey": "Shift+6", "desc": "Running water hazard with a one-stroke penalty. Paint it in lines; golfers can still walk across", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.WATER, "name": "Water", "hotkey": "6", "desc": "Water hazard with penalty", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.OUT_OF_BOUNDS, "name": "Out of Bounds", "hotkey": "7", "desc": "Boundary area with stroke penalty", "tile_preview": true})
	# Bottom row: playing surfaces and natural ground, each variant beside its parent.
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.FAIRWAY, "name": "Fairway", "hotkey": "1", "desc": "Mowed playing surface for approach shots", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.FIRM_FAIRWAY, "name": "Firm Fairway", "hotkey": "9", "desc": "Fast-running links turf: a tight lie, and balls bound on and roll about 60% farther", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.DEEP_ROUGH, "name": "Deep Rough", "hotkey": "Shift+2", "desc": "Knee-high grass that grabs rolling balls. Shots from it lose accuracy and 40% of their distance", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.WASTE_BUNKER, "name": "Waste Bunker", "hotkey": "0", "desc": "Natural sandy scrubland. Not a hazard: plays like sandy rough and needs no upkeep", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.BRUSH, "name": "Brush", "hotkey": "Shift+8", "desc": "Dense scrub that swallows the ball. Only a wedge hacks it out", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.ROCKS, "name": "Rocks", "hotkey": "Shift+7", "desc": "Stony ground scattered with stones: the worst lie on the course, wedge only", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.SMALL_BOULDERS, "name": "Small Boulders", "hotkey": "Shift+9", "desc": "Stony ground paved with small boulders: the worst lie on the course, wedge only", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.LARGE_BOULDERS, "name": "Large Boulders", "hotkey": "Shift+0", "desc": "Stony ground broken up by large boulders: the worst lie on the course, wedge only", "tile_preview": true})
	# The grid carries its own breathing room above and below the rows, so it
	# keeps that spacing instead of stretching to fill the whole page height.
	hbox.add_child(_make_tab_group("", tiles_grid, true))

	_populate_landscape_tiles()

	# Open Hole pairs the tee box and the green, which share the top row's first
	# two slots: nestle the action into the notch between them. Added after the
	# catalogue tiles so the honeycomb's tile flow (course tiles first, tree
	# tiles behind them) is exactly as it was — a nestled child takes no slot.
	_add_open_hole_notch(tiles_grid, 0)

## The Open Hole action as a half-size course cell nestled into the notch
## between the tab's Tee Box and Green tiles — the pair it opens. `left_slot` is
## the flow slot of the tile to the left of the notch, so slot 0 puts it between
## the tee box and the green.
func _add_open_hole_notch(tiles_grid: TileHoneycomb, left_slot: int) -> OpenHoleNotchButton:
	var open_hole_btn := OpenHoleNotchButton.new()
	open_hole_btn.name = "OpenHoleButton"
	open_hole_btn.configure("open_hole", "Open Hole", "[H]", "H", OPEN_HOLE_TOOLTIP)
	open_hole_btn.tool_pressed.connect(_on_tool_button_pressed)
	tiles_grid.set_notch_child(open_hole_btn, left_slot)
	_open_hole_buttons.append(open_hole_btn)
	_tool_buttons["open_hole"] = open_hole_btn
	return open_hole_btn

func _build_improvements_tab(hbox: HBoxContainer) -> void:
	# Every improvement — the walking path and each ornament in The Garden Shed —
	# sits in one honeycomb of the same interlocking isometric tiles used by
	# Course Terrain and Buildings: two rows, no heading (the tiles carry their
	# own captions), and a rich hover tooltip per tile. The path leads the top
	# row because it is the improvement players reach for while they shape the
	# course, so it opens the tab instead of standing beside it in its own box.
	# The page scrolls sideways when the catalogue is wider than the window.
	_decoration_shelf = TileHoneycomb.new()
	_decoration_shelf.name = "DecorationShelf"
	_decoration_shelf.tile_size = TerrainTileButton.BUTTON_SIZE
	_decoration_shelf.h_separation = TILE_H_SEPARATION
	_decoration_shelf.v_separation = TILE_V_SEPARATION
	_decoration_shelf.v_padding = TILE_V_PADDING
	_decoration_shelf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_decoration_shelf.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_add_path_tile()
	_populate_decoration_shelf()
	hbox.add_child(_make_tab_group("", _decoration_shelf, true))

## The walking path drawn as a course tile and laid in the first slot of the
## Improvements honeycomb. It is a painting tool rather than a catalogue entry,
## so `_populate_decoration_shelf()` preserves it while it rebuilds the shelf.
func _add_path_tile() -> void:
	if is_instance_valid(_path_tile):
		return
	_path_tile = _add_tool_button(_decoration_shelf, {
		"type": TerrainTypes.Type.PATH,
		"name": "Path",
		"hotkey": "8",
		"desc": "Thin dirt walking path laid over rough, deep rough, waste bunker, brush, rocks, boulders, streams, wild flowers and trees. Each tile is a dot; edge-adjacent dots join into one trail, and a trail that reaches the clubhouse is paved.",
		"tile_preview": true,
	}) as TerrainTileButton

func _on_theme_changed(_theme: int) -> void:
	_populate_landscape_tiles()

func _populate_landscape_tiles() -> void:
	if not is_instance_valid(_course_tiles):
		return
	# Detach old landscape tiles immediately so repeated theme changes cannot
	# leave duplicate tiles in the layout or stale entries in the tool lookup.
	for key in _tool_buttons.keys():
		if _tool_buttons[key] in _landscape_buttons:
			_tool_buttons.erase(key)
	for child in _landscape_buttons:
		_course_tiles.remove_child(child)
		child.queue_free()
	_landscape_buttons.clear()

	var theme_id: int = CourseTheme.Type.PARKLAND
	if GameManager:
		theme_id = GameManager.current_theme
	var theme_trees: Array = CourseTheme.get_tree_types(theme_id)
	var total_tiles: int = 1 + theme_trees.size()
	_course_tiles.columns = COURSE_TILE_COLUMNS + ceili(float(total_tiles) / TILE_ROWS)

	# Wild Flowers terrain tile
	var fb_btn := _add_tool_button(_course_tiles, {
		"type": TerrainTypes.Type.FLOWER_BED,
		"name": "Wild Flowers",
		"hotkey": "Shift+F",
		"desc": "Colorful landscaping",
		"tile_preview": true
	})
	_tool_buttons[TerrainTypes.Type.FLOWER_BED] = fb_btn

	# Woodland: one ordinary paint tile per species the theme grows. They behave
	# like every other tile on the tab — cost, replacement and the Bulldozer all
	# read them from TerrainTypes — and only the canopy differs (TreeOverlay).
	for tree_type in theme_trees:
		var tree_btn := _add_tool_button(_course_tiles, {
			"type": tree_type,
			"name": TerrainTypes.get_type_name(tree_type),
			"desc": _tree_tile_description(tree_type),
			"tile_preview": true,
		})
		_landscape_buttons.append(tree_btn)

	# Extend both existing course rows, rather than starting another honeycomb.
	# Keeping the first COURSE_TILE_COLUMNS tiles in each row preserves the
	# course layout. A child nestled into a notch (the Open Hole button) is not
	# a tile, so it is not part of this flow and keeps its place between the tee
	# and the green.
	var tiles: Array[Control] = _course_tiles.flow_children()
	_landscape_buttons.assign(tiles.slice(COURSE_TILE_COLUMNS * TILE_ROWS))
	for i in _course_tiles.columns - COURSE_TILE_COLUMNS:
		_course_tiles.move_child(_landscape_buttons[i], COURSE_TILE_COLUMNS + i)
	_update_selection_highlight()

func _build_buildings_tab(hbox: HBoxContainer) -> void:
	# Optional facilities use the same interlocking isometric buttons as Course
	# & Hazards. Required buildings (currently the clubhouse) are supplied with
	# the course and aren't construction choices in this shelf.
	# Tiles are laid out in two rows (columns follow the catalogue size, see
	# _populate_building_shelf) and the page scrolls sideways when needed.
	_building_shelf = TileHoneycomb.new()
	_building_shelf.name = "BuildingShelf"
	_building_shelf.columns = tile_columns(_optional_building_types().size())
	_building_shelf.tile_size = TerrainTileButton.BUTTON_SIZE
	_building_shelf.h_separation = TILE_H_SEPARATION
	_building_shelf.v_separation = TILE_V_SEPARATION
	_building_shelf.v_padding = TILE_V_PADDING
	_building_shelf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_building_shelf.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# No group heading or INFO blurb: the tiles speak for themselves and the
	# rich hover tooltip carries each facility's cost and upkeep.
	# The shelf carries its own breathing room above and below the rows, so it
	# keeps that spacing instead of stretching to fill the whole page height.
	hbox.add_child(_make_tab_group("", _building_shelf, true))
	_populate_building_shelf()

func set_building_registry(registry: Dictionary) -> void:
	_building_registry = registry.duplicate(true)
	_populate_building_shelf()

func _populate_building_shelf() -> void:
	if not is_instance_valid(_building_shelf):
		return
	for child in _building_shelf.get_children():
		_building_shelf.remove_child(child)
		child.queue_free()
	var building_types := _optional_building_types()
	_building_shelf.columns = tile_columns(building_types.size())
	for building_type in building_types:
		var data: Dictionary = _building_registry[building_type]
		var button := BuildingTileButton.new()
		button.configure_building(str(building_type), data)
		button.pressed.connect(_on_building_card_pressed.bind(str(building_type)))
		_building_shelf.add_child(button)

## The clubhouse (and any other required building) is created as part of the
## course, so required entries remain in the registry for game logic but don't
## appear as player-placeable choices.
func _optional_building_types() -> Array:
	var building_types: Array = []
	for building_type in _building_registry:
		var data: Dictionary = _building_registry[building_type]
		if data.get("required", false):
			continue
		building_types.append(building_type)
	return building_types

## Columns needed to lay `count` catalogue tiles out in TILE_ROWS rows.
static func tile_columns(count: int) -> int:
	return maxi(1, ceili(float(count) / TILE_ROWS))

func _on_building_card_pressed(building_type: String) -> void:
	_reveal_tab_for_tool("building")
	building_selected.emit(building_type)

# =============================================================================
# Improvements shelf: the walking path tile plus the decoration catalogue
# =============================================================================

func set_decoration_registry(registry: Dictionary) -> void:
	_decoration_registry = registry.duplicate(true)
	_populate_decoration_shelf()

func _populate_decoration_shelf() -> void:
	if not is_instance_valid(_decoration_shelf):
		return
	for child in _decoration_shelf.get_children():
		if child == _path_tile:
			continue  # The path leads the shelf; it is not part of the catalogue.
		_decoration_shelf.remove_child(child)
		child.queue_free()
	_decoration_tiles.clear()
	_decoration_shelf.columns = tile_columns(_decoration_registry.size() + IMPROVEMENTS_LEAD_TILES)
	for dec_type in ordered_decoration_types():
		var data: Dictionary = _decoration_registry[dec_type]
		var button := DecorationTileButton.new()
		button.configure_decoration(str(dec_type), data)
		button.pressed.connect(_on_decoration_card_pressed.bind(str(dec_type)))
		_decoration_shelf.add_child(button)
		_decoration_tiles[str(dec_type)] = button
	if is_instance_valid(_path_tile):
		# Rebuilt rows append after the new catalogue tiles, so put the path back
		# in slot 0: the first tile of the top row of the honeycomb.
		_decoration_shelf.move_child(_path_tile, 0)
	refresh_decoration_unlocks()

## Decoration types in the order The Garden Shed listed them: one category
## after another, each keeping the catalogue's own order. Types with an
## unknown category trail the shelf in catalogue order.
func ordered_decoration_types() -> Array:
	var ordered: Array = []
	for category in DecorationTileButton.CATEGORY_ORDER:
		for dec_type in _decoration_registry:
			if str(_decoration_registry[dec_type].get("category", "")) == category:
				ordered.append(dec_type)
	for dec_type in _decoration_registry:
		if not ordered.has(dec_type):
			ordered.append(dec_type)
	return ordered

func _on_decoration_card_pressed(decoration_type: String) -> void:
	var button: DecorationTileButton = _decoration_tiles.get(decoration_type, null)
	if button and button.disabled:
		return  # Locked ornaments stay on the shelf but cannot be placed.
	_reveal_tab_for_tool("decoration")
	decoration_selected.emit(decoration_type)

## Re-check every ornament against the current rating, reputation and hole
## count: the shelf opens with what the course has unlocked so far.
func refresh_decoration_unlocks() -> void:
	for dec_type in _decoration_tiles:
		var button: DecorationTileButton = _decoration_tiles[dec_type]
		if not is_instance_valid(button):
			continue
		button.set_locked(not is_decoration_unlocked(button.decoration_data),
			decoration_unlock_text(button.decoration_data))

func is_decoration_unlocked(decoration_data: Dictionary) -> bool:
	if not GameManager:
		return true
	var unlock = decoration_data.get("unlock")
	if unlock == null or not unlock is Dictionary or unlock.is_empty():
		return true
	match str(unlock.get("type", "")):
		"star_rating":
			return GameManager.course_rating.get("stars", 0) >= int(unlock.get("value", 99))
		"reputation":
			return GameManager.reputation >= int(unlock.get("value", 999))
		"holes_built":
			var hole_count: int = GameManager.current_course.holes.size() if GameManager.current_course else 0
			return hole_count >= int(unlock.get("value", 99))
	return false

## Human-readable form of a decoration's unlock requirement ("" when it has none).
func decoration_unlock_text(decoration_data: Dictionary) -> String:
	var unlock = decoration_data.get("unlock")
	if unlock == null or not unlock is Dictionary or unlock.is_empty():
		return ""
	match str(unlock.get("type", "")):
		"star_rating":
			return "%d★ rating" % int(unlock.get("value", 0))
		"reputation":
			return "%d reputation" % int(unlock.get("value", 0))
		"holes_built":
			return "%d holes" % int(unlock.get("value", 0))
	return ""

func _build_elevation_tab(hbox: HBoxContainer) -> void:
	# The three Square Selectors share one honeycomb of interlocking diamonds —
	# Vertex, Flat Square and Gradual Square in a single row — and the Elevation
	# Brush that belongs to the two Square tools nestles into the notch between
	# them instead of standing in a group of its own beside the row: the size
	# stepper in the V above the point where those tiles meet, the shape toggle
	# in the V below it. The same treatment the Open Hole action gets on the
	# Course Terrain tab (see TileHoneycomb.set_notch_child).
	var selectors = TileHoneycomb.new()
	selectors.name = "ElevationSelectors"
	_elevation_selectors = selectors
	selectors.columns = ELEVATION_SELECTOR_COLUMNS
	selectors.tile_size = ElevationSelectorButton.SELECTOR_TILE_SIZE
	selectors.h_separation = TILE_H_SEPARATION
	selectors.v_separation = TILE_V_SEPARATION
	selectors.v_padding = ELEVATION_V_PADDING
	selectors.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_add_tool_button(selectors, {"type": "vertex", "elevation_preview": true, "name": "Vertex", "icon": "◆", "hotkey": "V", "desc": "Right click raises, left click lowers, a single grid vertex by one step"})
	_add_tool_button(selectors, {"type": "flat", "elevation_preview": true, "name": "Flat Square", "icon": "■", "hotkey": "+", "desc": "Right click: raise the square's lowest vertices one level. Left click: lower its highest ones one level. Even ground moves as one slab"})
	_add_tool_button(selectors, {"type": "gradual", "elevation_preview": true, "name": "Gradual Square", "icon": "▲", "hotkey": "-", "desc": "Right click raises, left click lowers, the middle of the square; nearby vertices keep at most one step of slope"})
	# The grid carries its own breathing room above and below the row, so it keeps
	# that spacing instead of stretching to fill the whole page height.
	hbox.add_child(_make_tab_group("", selectors, true))

	# The brush controls ride in the notch between the two Square tools, so they
	# are added after the tiles: a nestled child takes no slot, and the row stays
	# exactly Vertex, Flat Square, Gradual Square.
	_add_elevation_brush_notches(selectors)

## Nestle the Elevation Brush controls into the notch between the Elevation
## tab's Flat Square and Gradual Square tiles — the two tools the brush belongs
## to. The size stepper takes the V above the point where those tiles meet (the
## same notch the Open Hole action fills on the Course Terrain tab) and the shape
## toggle the V below it, where the next row of a honeycomb would tuck in.
func _add_elevation_brush_notches(selectors: TileHoneycomb) -> void:
	selectors.set_notch_child(_make_elevation_brush_size_notch(), ELEVATION_BRUSH_NOTCH_SLOT, true)
	selectors.set_notch_child(_make_elevation_brush_shape_notch(), ELEVATION_BRUSH_NOTCH_SLOT, false)
	# Size and shape stay usable whether or not a Square tool is selected.
	_update_elevation_brush_group()

## The Elevation Brush size stepper — smaller, the size it paints with, bigger —
## as a half-size selector diamond in the V above the Square tiles. Its three
## cells keep the wiring they had when they stood in a brush group of their own:
## the same `_elevation_brush_buttons` and `_elevation_brush_labels` the toolbar
## refreshes as the tool changes.
func _make_elevation_brush_size_notch() -> ElevationBrushSizeNotch:
	var notch := ElevationBrushSizeNotch.new()
	notch.name = "ElevationBrushSizeNotch"

	var decrease := notch.decrease_button
	decrease.tooltip_text = "Smaller elevation brush"
	decrease.accessibility_name = decrease.tooltip_text
	decrease.accessibility_description = decrease.tooltip_text
	decrease.pressed.connect(_on_elevation_brush_decrease)
	_elevation_brush_buttons.append(decrease)

	_elevation_brush_labels.append(notch.size_label)

	var increase := notch.increase_button
	increase.tooltip_text = "Bigger elevation brush"
	increase.accessibility_name = increase.tooltip_text
	increase.accessibility_description = increase.tooltip_text
	increase.pressed.connect(_on_elevation_brush_increase)
	_elevation_brush_buttons.append(increase)

	_elevation_brush_size_notches.append(notch)
	return notch

## The Elevation Brush shape toggle — square or round — as a half-size selector
## diamond in the V below the Square tiles.
func _make_elevation_brush_shape_notch() -> ElevationBrushNotchButton:
	var notch := ElevationBrushNotchButton.new()
	notch.name = "ElevationBrushShapeNotch"
	notch.focus_mode = Control.FOCUS_NONE
	notch.toggle_mode = true
	notch.pressed.connect(_on_elevation_brush_shape_toggled)
	_elevation_brush_shape_buttons.append(notch)
	return notch

func _build_holes_tab(hbox: HBoxContainer) -> void:
	# The Course Terrain tab owns the Open Hole action, and each hole's context
	# menu owns that hole's open/closed toggle and its statistics. Keep this tab
	# to the holes themselves — one button each, three to a column, no per-hole
	# toggle or delete buttons and no group heading.
	hole_grid = GridContainer.new()
	hole_grid.name = "HoleGrid"
	hole_grid.columns = 1
	hole_grid.add_theme_constant_override("h_separation", 6)
	hole_grid.add_theme_constant_override("v_separation", 4)
	hole_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(hole_grid)

## Re-seat the hole buttons so they read three deep down each column before the
## next column starts. main.gd adds and removes one button per hole, but the
## grid fills row-major, so the children are put back into column-major order
## after every change and the grid is widened to exactly the columns they need.
## Each button carries its hole number as metadata.
func layout_hole_buttons() -> void:
	if not hole_grid:
		return
	var buttons: Array[Control] = []
	for child in hole_grid.get_children():
		if child is Control and not child.is_queued_for_deletion():
			buttons.append(child)
	buttons.sort_custom(func(a: Control, b: Control) -> bool:
		return int(a.get_meta("hole_number", 0)) < int(b.get_meta("hole_number", 0)))
	if buttons.is_empty():
		hole_grid.columns = 1
		return
	var column_count := int(ceil(float(buttons.size()) / float(HOLE_COLUMN_HEIGHT)))
	hole_grid.columns = column_count
	var slot := 0
	for row in HOLE_COLUMN_HEIGHT:
		for column in column_count:
			var index := column * HOLE_COLUMN_HEIGHT + row
			if index < buttons.size():
				hole_grid.move_child(buttons[index], slot)
				slot += 1

func _build_golfers_tab(hbox: HBoxContainer) -> void:
	var on_course_group = VBoxContainer.new()
	on_course_group.add_theme_constant_override("separation", 2)
	on_course_group.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var lbl1 = Label.new()
	lbl1.text = "ON THE COURSE"
	lbl1.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	lbl1.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	on_course_group.add_child(lbl1)

	_active_golfers_box = HBoxContainer.new()
	_active_golfers_box.name = "ActiveGolfersShelf"
	# The gap between columns: the rows inside a column keep their own tighter
	# rhythm, so this is the breathing room that tells two columns apart.
	_active_golfers_box.add_theme_constant_override("separation", GOLFER_COLUMN_GAP)
	_active_golfers_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	on_course_group.add_child(_active_golfers_box)
	hbox.add_child(on_course_group)

	hbox.add_child(_make_separator())

	var recent_group = VBoxContainer.new()
	recent_group.add_theme_constant_override("separation", 2)
	recent_group.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var lbl2 = Label.new()
	lbl2.text = "RECENT ROUNDS"
	lbl2.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	lbl2.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	recent_group.add_child(lbl2)

	_recent_rounds_box = HBoxContainer.new()
	_recent_rounds_box.name = "RecentRoundsShelf"
	_recent_rounds_box.add_theme_constant_override("separation", RECENT_ROUND_COLUMN_GAP)
	_recent_rounds_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recent_group.add_child(_recent_rounds_box)
	hbox.add_child(recent_group)

func _build_player_tab(hbox: HBoxContainer) -> void:
	player_tab = PlayerTab.new()
	# Match the terrain shelf, not the full bottom bar (which includes tabs).
	player_tab.custom_minimum_size.y = TerrainTileButton.BUTTON_SIZE.y * 1.5 \
		+ TILE_V_SEPARATION + 2.0 * TILE_V_PADDING
	hbox.add_child(player_tab)

func select_player_section(index: int) -> void:
	select_tab(Tab.PLAYER)
	player_tab.select(index)

func _build_club_tab(hbox: HBoxContainer) -> void:
	var ops_box = HBoxContainer.new()
	ops_box.add_theme_constant_override("separation", 4)
	ops_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_add_tool_button(ops_box, {"type": "land", "name": "Land", "icon": "[L]", "hotkey": "L", "desc": "Buy land parcels to expand the course"})
	_add_tool_button(ops_box, {"type": "marketing", "name": "Marketing", "icon": "[M]", "hotkey": "M", "desc": "Marketing campaigns to attract golfers"})
	_add_tool_button(ops_box, {"type": "milestones", "name": "Milestones", "icon": "[G]", "hotkey": "G", "desc": "Goals and achievements"})
	_add_tool_button(ops_box, {"type": "scorecard", "name": "Scorecard", "icon": "[K]", "hotkey": "K", "desc": "Course scorecard and records"})
	ops_box.add_child(_make_review_button())
	hbox.add_child(_make_tab_group("OPERATIONS", ops_box))

	hbox.add_child(_make_separator())

	hbox.add_child(_make_tip_label("Expand land parcels, launch marketing campaigns, track milestones and check course records."))

func _build_staff_tab(hbox: HBoxContainer) -> void:
	# Staff management lives in the tab itself — condition, hire/fire, roster, effects.
	_staff_panel = StaffPanel.new()
	_staff_panel.name = "StaffPanel"
	_staff_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_staff_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_staff_panel.area_move_requested.connect(func(index: int):
		staff_area_move_requested.emit(index))
	hbox.add_child(_staff_panel)

## Reflect the active area-repositioning mode back into the roster buttons.
func set_staff_area_mode_index(index: int) -> void:
	if _staff_panel:
		_staff_panel.set_area_mode_index(index)

# =============================================================================
# Helper Widgets
# =============================================================================

func _make_tab_group(title: String, content: Control, center_content: bool = false) -> VBoxContainer:
	var group = VBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	group.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if not title.is_empty():
		var lbl = Label.new()
		lbl.text = title.to_upper()
		lbl.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
		lbl.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
		group.add_child(lbl)

	# Tile grids already carry their own breathing room above and below the
	# rows, so they keep their natural height instead of stretching to fill it.
	if center_content:
		content.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	group.add_child(content)
	return group

func _make_separator() -> VSeparator:
	var sep = VSeparator.new()
	sep.custom_minimum_size = Vector2(1, 28)
	sep.modulate = Color(1, 1, 1, 0.2)
	return sep

func _make_tip_label(text: String) -> Control:
	var group = VBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	group.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var lbl_title = Label.new()
	lbl_title.text = "INFO"
	lbl_title.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	lbl_title.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	group.add_child(lbl_title)

	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	lbl.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	group.add_child(lbl)
	return group

## What a woodland tile does: it paints the species' own ground, and the course
## draws the tree on it. Kept in one place so every species tile says the same.
func _tree_tile_description(tree_type: int) -> String:
	var species := TerrainTypes.get_type_name(tree_type).to_lower()
	var ground := TerrainTypes.get_tree_ground(tree_type)
	return "Woodland: %s canopy over %s. Blocks a shot that finds it, and the " % [species, ground] \
			+ "ball plays badly from among the roots."

func _add_tool_button(parent: Control, tool_def: Dictionary) -> ToolButton:
	var tool_type = tool_def["type"]
	var cost = 0
	var maintenance = 0
	if tool_type is int:
		cost = TerrainTypes.get_placement_cost(tool_type)
		maintenance = TerrainTypes.get_maintenance_cost(tool_type)

	var btn: ToolButton
	var desc := str(tool_def.get("desc", ""))
	# Every Course Terrain paint tile overwrites every other tile on the tab.
	if tool_type is int and TOOL_TAB_MAP.get(tool_type, -1) == Tab.TERRAIN:
		desc = _with_course_tile_replacement(desc)
	if tool_def.get("elevation_preview", false):
		btn = ElevationSelectorButton.new()
		btn.configure(tool_type, tool_def["name"], "", tool_def.get("hotkey", ""),
			desc, cost, maintenance)
		btn.set_brush_square(_elevation_square)
	elif tool_def.get("tile_preview", false):
		btn = TerrainTileButton.new()
		btn.configure(tool_type, tool_def["name"], "", tool_def.get("hotkey", ""),
			desc, cost, maintenance)
	else:
		btn = ToolButton.create(tool_type, tool_def["name"], tool_def.get("icon", ""),
			tool_def.get("hotkey", ""), desc, cost, maintenance)
	btn.tool_pressed.connect(_on_tool_button_pressed)
	parent.add_child(btn)

	if btn is TerrainTileButton:
		btn.custom_minimum_size = (btn as TerrainTileButton).button_size()
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		btn.custom_minimum_size = Vector2(0, TOOL_ROW_HEIGHT)
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
		btn.add_theme_constant_override("icon_max_width", 18)

	if not (tool_type is String and _is_menu_action(tool_type)):
		_tool_buttons[tool_type] = btn
		if tool_type is int:
			if tool_type == TerrainTypes.Type.GREEN:
				_green_tile_button = btn as TerrainTileButton
			elif tool_type == TerrainTypes.Type.TEE_BOX:
				_tee_tile_button = btn as TerrainTileButton

	return btn

func _is_menu_action(tool_type: String) -> bool:
	return tool_type in ["land", "marketing", "milestones", "scorecard", "tournaments", "play_course"]

func _make_small_group_label(text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	lbl.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	return lbl

## Brush size stepper row ("-" label "+"), used by the Elevation tab's brush
## group; the caller sets size flags. The Course Terrain tab's brush lives in
## the pinned corner dock instead (see _pin_brush_dock).
func _create_brush_row() -> HBoxContainer:
	var brush_row = HBoxContainer.new()
	brush_row.alignment = BoxContainer.ALIGNMENT_CENTER
	brush_row.add_theme_constant_override("separation", 3)

	var brush_decrease = Button.new()
	brush_decrease.text = "-"
	brush_decrease.custom_minimum_size = Vector2(24, 26)
	brush_decrease.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	brush_decrease.pressed.connect(_on_brush_decrease)
	brush_row.add_child(brush_decrease)
	_brush_buttons.append(brush_decrease)

	var brush_label = Label.new()
	brush_label.text = "%dx%d" % [_brush_size, _brush_size]
	brush_label.custom_minimum_size = Vector2(30, 0)
	brush_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brush_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	brush_label.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
	brush_row.add_child(brush_label)
	_brush_labels.append(brush_label)

	var brush_increase = Button.new()
	brush_increase.text = "+"
	brush_increase.custom_minimum_size = Vector2(24, 26)
	brush_increase.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	brush_increase.pressed.connect(_on_brush_increase)
	brush_row.add_child(brush_increase)
	_brush_buttons.append(brush_increase)
	return brush_row

## Round/square brush shape picker. Shared by the pinned Course Terrain brush
## dock and the Elevation tab's brush group; the caller passes the cell it has
## room for. A toggle button that swaps between Square and Circle icons.
func _create_brush_shape(cell_size: Vector2 = Vector2(32, 26)) -> Button:
	var shape := Button.new()
	shape.focus_mode = Control.FOCUS_NONE
	shape.custom_minimum_size = cell_size
	shape.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	shape.toggle_mode = true
	_update_brush_shape_button(shape)
	shape.pressed.connect(_on_brush_shape_toggled)
	_brush_shape_buttons.append(shape)
	return shape

## The brush size readout in the pinned dock: one square cell showing the size
## the selected tool actually paints with. It shares `_brush_labels` with the
## Elevation tab's wider stepper, so both always read the same number.
func _create_brush_size_chip() -> Label:
	var chip := Label.new()
	chip.name = "BrushSizeChip"
	chip.text = "%dx%d" % [_brush_size, _brush_size]
	chip.custom_minimum_size = Vector2(BRUSH_DOCK_CELL, BRUSH_DOCK_CELL)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	chip.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = UIConstants.COLOR_BG_DARK
	chip_style.corner_radius_top_left = 4
	chip_style.corner_radius_top_right = 4
	chip_style.corner_radius_bottom_right = 4
	chip_style.corner_radius_bottom_left = 4
	chip.add_theme_stylebox_override("normal", chip_style)
	_brush_labels.append(chip)
	return chip

## One square step button of the pinned brush dock (smaller / bigger).
func _create_brush_step_button(caption: String, tip: String, action: Callable) -> Button:
	var btn := Button.new()
	btn.text = caption
	btn.tooltip_text = tip
	btn.accessibility_name = tip
	btn.accessibility_description = tip
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	btn.pressed.connect(action)
	_style_dock_cell(btn)
	_brush_buttons.append(btn)
	return btn

## Give a brush dock cell its fixed square footprint. The theme's button
## styleboxes carry content margins of their own, which would push the cell —
## and so the whole plate — past the corner the tile rows leave clear, so the
## dock draws its own flush cells instead.
func _style_dock_cell(control: Control) -> void:
	control.custom_minimum_size = Vector2(BRUSH_DOCK_CELL, BRUSH_DOCK_CELL)
	if control is Button:
		var faces := {
			"normal": UIConstants.COLOR_BG_BUTTON,
			"hover": UIConstants.COLOR_BG_HOVER,
			"pressed": UIConstants.COLOR_PRIMARY_PRESSED,
			"hover_pressed": UIConstants.COLOR_PRIMARY_PRESSED,
			"focus": UIConstants.COLOR_BG_BUTTON,
			"disabled": UIConstants.COLOR_BG_DARK,
		}
		for state in faces:
			var box := StyleBoxFlat.new()
			box.bg_color = faces[state]
			box.corner_radius_top_left = 4
			box.corner_radius_top_right = 4
			box.corner_radius_bottom_right = 4
			box.corner_radius_bottom_left = 4
			for margin in ["content_margin_left", "content_margin_top",
					"content_margin_right", "content_margin_bottom"]:
				box.set(margin, 0.0)
			control.add_theme_stylebox_override(state, box)
		control.add_theme_color_override("font_disabled_color", UIConstants.COLOR_TEXT_MUTED)

func _update_brush_shape_button(btn: Button) -> void:
	if _round_brush:
		btn.text = "○"
		btn.tooltip_text = "Round brush (Circle) — click for Square"
	else:
		btn.text = "□"
		btn.tooltip_text = "Square brush — click for Round (Circle)"
	btn.button_pressed = _round_brush
	btn.accessibility_name = "Brush shape"
	btn.accessibility_description = btn.tooltip_text

func _make_brush_group() -> VBoxContainer:
	var group = VBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	group.size_flags_vertical = Control.SIZE_EXPAND_FILL

	group.add_child(_make_small_group_label("BRUSH"))

	var shape := _create_brush_shape()
	shape.size_flags_vertical = Control.SIZE_EXPAND_FILL
	group.add_child(shape)

	var brush_row := _create_brush_row()
	brush_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	group.add_child(brush_row)

	_apply_brush_limit()
	return group

## The sizes the Elevation Brush offers. Flat Square and Gradual Square share
## the same 1x1 through 9x9 list, and the stepper keeps that range even when
## neither Square tool is selected.
func _elevation_brush_sizes() -> Array:
	return ElevationTool.BRUSH_SIZES

func _elevation_brush_size() -> int:
	return _elevation_size

func _elevation_brush_square() -> bool:
	return _elevation_square

## Set the selected elevation selector tool and sync the brush controls: the
## notch cells keep the shared size and shape, and stay enabled whether or not
## a Square tool is selected.
func set_elevation_tool(tool_name: String) -> void:
	_elevation_tool = tool_name
	_update_elevation_brush_group()

## Read back the shared Elevation Brush settings.
func get_elevation_brush_size() -> int:
	return _elevation_brush_size()

func get_elevation_brush_square() -> bool:
	return _elevation_brush_square()

## Mirror the shared brush settings in the two notch cells. Size and shape stay
## enabled even when the Vertex tool is selected or no Square tool is selected,
## so the player can set the brush before (or after) picking Flat or Gradual.
func _update_elevation_brush_group() -> void:
	for button in _elevation_brush_buttons:
		if is_instance_valid(button):
			button.disabled = false
	for shape in _elevation_brush_shape_buttons:
		if is_instance_valid(shape):
			shape.set_brush_enabled(true)
			_update_elevation_brush_shape_button(shape)
	for notch in _elevation_brush_size_notches:
		if is_instance_valid(notch):
			notch.set_brush_enabled(true)
	_update_elevation_brush_label()

func _update_elevation_brush_label() -> void:
	var sizes: Array = _elevation_brush_sizes()
	var brush_size: int = _elevation_brush_size()
	if not sizes.is_empty() and not (brush_size in sizes):
		brush_size = sizes.min() if brush_size < sizes.min() else sizes.max()
		_elevation_size = brush_size
	var text := "%dx%d" % [brush_size, brush_size]
	for label in _elevation_brush_labels:
		if is_instance_valid(label):
			label.text = text
			label.tooltip_text = "Elevation brush size %s tiles" % text

func _update_elevation_brush_shape_button(btn: ElevationBrushNotchButton) -> void:
	if _elevation_brush_square():
		btn.set_caption("□")
		btn.tooltip_text = "Square elevation brush — click for Round"
	else:
		btn.set_caption("○")
		btn.tooltip_text = "Round elevation brush — click for Square"
	btn.button_pressed = not _elevation_brush_square()
	btn.accessibility_name = "Elevation brush shape"
	btn.accessibility_description = btn.tooltip_text

func _on_elevation_brush_decrease() -> void:
	var sizes: Array = _elevation_brush_sizes()
	var idx: int = sizes.find(_elevation_brush_size())
	if idx > 0:
		_set_elevation_brush_size(sizes[idx - 1])

func _on_elevation_brush_increase() -> void:
	var sizes: Array = _elevation_brush_sizes()
	var idx: int = sizes.find(_elevation_brush_size())
	if idx >= 0 and idx < sizes.size() - 1:
		_set_elevation_brush_size(sizes[idx + 1])

func _set_elevation_brush_size(value: int) -> void:
	_elevation_size = value
	_update_elevation_brush_label()
	elevation_brush_size_changed.emit(value)

func _on_elevation_brush_shape_toggled() -> void:
	_elevation_square = not _elevation_square
	for tool_name in ["flat", "gradual"]:
		var selector = _tool_buttons.get(tool_name)
		if is_instance_valid(selector) and selector is ElevationSelectorButton:
			selector.set_brush_square(_elevation_square)
	for shape in _elevation_brush_shape_buttons:
		if is_instance_valid(shape):
			_update_elevation_brush_shape_button(shape)
	elevation_brush_shape_changed.emit(_elevation_brush_square())

func _make_review_button() -> Button:
	var review := Button.new()
	review.text = "Review"
	review.tooltip_text = "Course review and next steps"
	review.custom_minimum_size = Vector2(72, TOOL_ROW_HEIGHT)
	review.size_flags_vertical = Control.SIZE_EXPAND_FILL
	review.pressed.connect(func(): course_review_pressed.emit())
	return review

func _make_review_group() -> VBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_make_review_button())
	return _make_tab_group("REVIEW", row)

func _build_refresh_timer() -> void:
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 1.0
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(_on_refresh_tick)
	add_child(_refresh_timer)

# =============================================================================
# Costs for special string tools
# =============================================================================

# =============================================================================
# Tab handling
# =============================================================================

func _on_tab_changed(tab_index: int) -> void:
	_show_page(tab_index)

func _show_page(tab_index: int) -> void:
	for i in _pages.size():
		_pages[i].visible = (i == tab_index)
	match tab_index:
		Tab.IMPROVEMENTS:
			refresh_decoration_unlocks()
		Tab.GOLFERS:
			_refresh_golfer_lists()
		Tab.PLAYER:
			_refresh_player_skills()
		Tab.STAFF:
			if _staff_panel:
				_staff_panel.refresh()

func select_tab(tab_index: int) -> void:
	if tab_index >= 0 and tab_index < _pages.size():
		_tab_bar.current_tab = tab_index
		_show_page(tab_index)

func _tab_index_for_tool(tool_type) -> int:
	return TOOL_TAB_MAP.get(tool_type, -1)

func _reveal_tab_for_tool(tool_type) -> void:
	var tab_index = _tab_index_for_tool(tool_type)
	if tab_index >= 0:
		select_tab(tab_index)

func _on_refresh_tick() -> void:
	if not is_visible_in_tree():
		return
	if _tab_bar and _tab_bar.current_tab == Tab.GOLFERS:
		_refresh_golfer_lists()
	elif _tab_bar and _tab_bar.current_tab == Tab.PLAYER:
		_refresh_player_skills()
	elif _tab_bar and _tab_bar.current_tab == Tab.IMPROVEMENTS:
		# Star rating, reputation and hole count all move during play, so the
		# open decoration shelf keeps up with what has been unlocked.
		refresh_decoration_unlocks()

# =============================================================================
# Golfer tab
# =============================================================================

func record_completed_round(data: Dictionary) -> void:
	_recent_rounds.push_front(data)
	if _recent_rounds.size() > MAX_RECENT_ROUNDS:
		_recent_rounds.resize(MAX_RECENT_ROUNDS)
	if is_visible_in_tree() and _tab_bar and _tab_bar.current_tab == Tab.GOLFERS:
		_refresh_golfer_lists()

func _refresh_golfer_lists() -> void:
	if _active_golfers_box == null or _recent_rounds_box == null:
		return

	# The old columns leave their shelves straight away. A child waiting on
	# queue_free() is still in the tree, so it would still take up shelf space
	# and sit beside the fresh columns until the end of the frame.
	_clear_shelf(_active_golfers_box)
	_clear_shelf(_recent_rounds_box)

	var rows: Array = []
	if golfer_data_provider.is_valid():
		rows = golfer_data_provider.call()

	var golfer_rows: Array[Control] = []
	if rows.is_empty():
		golfer_rows.append(_make_empty_label("No golfers on the course."))
	else:
		for row_data in rows:
			golfer_rows.append(_make_golfer_row(row_data))
	_stack_in_columns(_active_golfers_box, golfer_rows, GOLFER_COLUMN_HEIGHT, GOLFER_ROW_GAP)

	var round_rows: Array[Control] = []
	if _recent_rounds.is_empty():
		round_rows.append(_make_empty_label("No rounds played yet."))
	else:
		for round_data in _recent_rounds:
			round_rows.append(_make_round_row(round_data))
	_stack_in_columns(_recent_rounds_box, round_rows, RECENT_ROUND_COLUMN_HEIGHT,
		RECENT_ROUND_ROW_GAP)

## Take every column off a shelf. The columns are only removed here and freed at
## the end of the frame, so a refresh can never free a row out from under a
## signal it is still emitting.
func _clear_shelf(shelf: HBoxContainer) -> void:
	for child in shelf.get_children():
		shelf.remove_child(child)
		child.queue_free()

## Fill a shelf with items stacked column_height deep: the first column takes
## the first column_height items, the next column takes the next, and so on.
## Each column is a VBox of its own, so a short last column never pulls the
## items above it across — the way a GridContainer, which counts its rows off
## the children it is given, would. The columns run off to the right where the
## page already scrolls, so the tab never grows past the bottom bar's height.
func _stack_in_columns(shelf: HBoxContainer, items: Array[Control], column_height: int,
		row_gap: int) -> void:
	var column: VBoxContainer = null
	for index in items.size():
		if index % column_height == 0:
			column = VBoxContainer.new()
			column.add_theme_constant_override("separation", row_gap)
			column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			shelf.add_child(column)
		column.add_child(items[index])

func _make_empty_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	return label

func _make_golfer_row(row_data: Dictionary) -> Control:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var mood: float = row_data.get("mood", 0.5)
	var mood_dot = Label.new()
	mood_dot.text = "●"
	mood_dot.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	if mood >= 0.66:
		mood_dot.add_theme_color_override("font_color", UIConstants.COLOR_MOOD_HAPPY)
	elif mood >= 0.33:
		mood_dot.add_theme_color_override("font_color", UIConstants.COLOR_MOOD_NEUTRAL)
	else:
		mood_dot.add_theme_color_override("font_color", UIConstants.COLOR_MOOD_UNHAPPY)
	mood_dot.tooltip_text = "Mood: %d%%" % int(mood * 100)
	row.add_child(mood_dot)

	var golfer_btn = Button.new()
	golfer_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	golfer_btn.clip_text = false
	golfer_btn.custom_minimum_size = Vector2(0, 26)
	golfer_btn.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	golfer_btn.text = "%s (%s) · H%d · %d str" % [
		row_data.get("name", "Golfer"),
		GolferTier.get_tier_name(row_data.get("tier", 1)),
		row_data.get("hole", 1),
		row_data.get("strokes", 0),
	]
	golfer_btn.tooltip_text = "%s (%s) on Hole %d (%d strokes) - Click to follow" % [
		row_data.get("name", "Golfer"),
		GolferTier.get_tier_name(row_data.get("tier", 1)),
		row_data.get("hole", 1),
		row_data.get("strokes", 0),
	]
	golfer_btn.pressed.connect(_on_golfer_row_pressed.bind(row_data.get("id", -1)))
	row.add_child(golfer_btn)
	return row

func _make_round_row(round_data: Dictionary) -> Control:
	var diff: int = int(round_data.get("strokes", 0)) - int(round_data.get("par", 0))
	var label = Label.new()
	label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	var round_day: int = int(round_data.get("day", 1))
	label.text = "%s%s: %d (%s%d) · %s" % [
		"★ " if round_data.get("owner", false) else "",
		round_data.get("name", "Golfer"),
		round_data.get("strokes", 0),
		"+" if diff > 0 else "",
		diff,
		GameCalendar.format_date_short(round_day),
	]
	label.add_theme_color_override("font_color", UIConstants.get_score_color(diff))
	label.tooltip_text = "%s's round (%s) on %s: %d strokes (%+d)" % [
		round_data.get("name", "Golfer"),
		GolferTier.get_tier_name(round_data.get("tier", 1)),
		GameCalendar.format_date(round_day),
		round_data.get("strokes", 0),
		diff,
	]
	return label

func _on_golfer_row_pressed(golfer_id: int) -> void:
	if golfer_id >= 0:
		golfer_row_clicked.emit(golfer_id)

# =============================================================================
# Player tab
# =============================================================================

## The Player tab's skill readout belongs to PlayerRoundManager's Player Skills
## page; all the toolbar keeps in step is the badge on the Player Skills button,
## which counts the points still to spend.
func _refresh_player_skills() -> void:
	if is_instance_valid(player_tab):
		player_tab.refresh_skill_badge()

# =============================================================================
# Tool selection
# =============================================================================

func _on_tool_button_pressed(tool_type) -> void:
	# Tee Box is unselectable while an unused tee waits on the course.
	if tool_type is int and tool_type == TerrainTypes.Type.TEE_BOX and not _tee_box_can_place:
		if _current_tool == TerrainTypes.Type.TEE_BOX:
			clear_selection()
		return

	_reveal_tab_for_tool(tool_type)

	if tool_type is int:
		_current_tool = tool_type
		_selected_string_tool = ""
		_update_selection_highlight()
		tool_selected.emit(tool_type)
	else:
		match tool_type:
			"building":
				building_placement_pressed.emit()
			"decoration":
				decoration_placement_pressed.emit()
			"open_hole":
				open_hole_pressed.emit()
			"vertex":
				elevation_tool_pressed.emit("vertex")
			"flat":
				elevation_tool_pressed.emit("flat")
			"gradual":
				elevation_tool_pressed.emit("gradual")
			"bulldozer":
				bulldozer_pressed.emit()
			"play_course":
				play_course_pressed.emit()
			"tournaments":
				tournaments_pressed.emit()
			"land":
				land_pressed.emit()
			"marketing":
				marketing_pressed.emit()
			"milestones":
				milestones_pressed.emit()
			"scorecard":
				scorecard_pressed.emit()

func _update_selection_highlight() -> void:
	for tool_type in _tool_buttons.keys():
		var btn = _tool_buttons[tool_type]
		if is_instance_valid(btn) and btn is ToolButton:
			var is_match = false
			if typeof(tool_type) == typeof(_current_tool) and tool_type == _current_tool:
				is_match = true
			elif not _selected_string_tool.is_empty() and str(tool_type) == _selected_string_tool:
				is_match = true
			btn.set_selected(is_match)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return

	if GameManager.current_mode == GameManager.GameMode.MAIN_MENU:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_command_or_control_pressed():
			return

		var focused = get_viewport().gui_get_focus_owner()
		if focused is LineEdit or focused is TextEdit:
			return

		if event.shift_pressed:
			match event.keycode:
				KEY_1:  # Shift+1 = !
					select_tab(Tab.TERRAIN)
					_on_tool_button_pressed(TerrainTypes.Type.BUNKER)
					get_viewport().set_input_as_handled()
					return
				# Deep Rough, Pot Bunker, Stream, Rocks, Brush, the
				# boulder fields.
				KEY_2, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0:
					_on_tool_button_pressed(SHIFT_TERRAIN_HOTKEYS[event.keycode])
					get_viewport().set_input_as_handled()
					return
				KEY_EQUAL:  # Shift+= = + selects the Flat Square selector
					_on_tool_button_pressed("flat")
					get_viewport().set_input_as_handled()
					return
				KEY_MINUS:  # Shift+- = _ selects the Gradual Square selector
					_on_tool_button_pressed("gradual")
					get_viewport().set_input_as_handled()
					return
				KEY_R:  # Shift+R = routing overlay (handled in main.gd)
					return

		match event.keycode:
			KEY_EQUAL:  # = opens the Course Terrain tab
				select_tab(Tab.TERRAIN)
				get_viewport().set_input_as_handled()
			KEY_PERIOD:  # . opens the Improvements tab
				select_tab(Tab.IMPROVEMENTS)
				get_viewport().set_input_as_handled()
			KEY_E:  # E opens the Elevation tab
				select_tab(Tab.ELEVATION)
				get_viewport().set_input_as_handled()
			KEY_V:  # V selects the Vertex selector
				_on_tool_button_pressed("vertex")
			KEY_MINUS:  # - selects the Gradual Square selector
				_on_tool_button_pressed("gradual")
			KEY_1:
				_on_tool_button_pressed(TerrainTypes.Type.FAIRWAY)
			KEY_2:
				_on_tool_button_pressed(TerrainTypes.Type.ROUGH)
			KEY_3:
				_on_tool_button_pressed(TerrainTypes.Type.GREEN)
			KEY_4:
				_on_tool_button_pressed(TerrainTypes.Type.TEE_BOX)
			KEY_5:
				_on_tool_button_pressed(TerrainTypes.Type.BUNKER)
			KEY_6:
				_on_tool_button_pressed(TerrainTypes.Type.WATER)
			KEY_7:
				_on_tool_button_pressed(TerrainTypes.Type.OUT_OF_BOUNDS)
			KEY_8:
				_on_tool_button_pressed(TerrainTypes.Type.PATH)
			KEY_9:
				_on_tool_button_pressed(TerrainTypes.Type.FIRM_FAIRWAY)
			KEY_0:
				_on_tool_button_pressed(TerrainTypes.Type.WASTE_BUNKER)
			KEY_T:
				select_tab(Tab.TERRAIN)
				var theme_trees: Array = CourseTheme.get_tree_types(GameManager.current_theme) if GameManager else []
				if not theme_trees.is_empty():
					_on_tool_button_pressed(theme_trees[0])
			KEY_F:
				if event.shift_pressed:
					select_tab(Tab.TERRAIN)
					_on_tool_button_pressed(TerrainTypes.Type.FLOWER_BED)
			KEY_B:
				_on_tool_button_pressed("building")
			KEY_O:
				_on_tool_button_pressed("decoration")
			KEY_H:
				_on_tool_button_pressed("open_hole")
			KEY_X:
				_on_tool_button_pressed("bulldozer")
			KEY_P:
				select_tab(Tab.STAFF)
				get_viewport().set_input_as_handled()

# =============================================================================
# Public API
# =============================================================================

func set_current_tool(tool_type: int) -> void:
	# Prevent selecting Tee when an unused tee waits.
	if tool_type == TerrainTypes.Type.TEE_BOX and not _tee_box_can_place:
		clear_selection()
		return
	_current_tool = tool_type
	_selected_string_tool = ""
	_update_selection_highlight()

func get_current_tool() -> int:
	return _current_tool

func clear_selection() -> void:
	_current_tool = -1
	_selected_string_tool = ""
	_update_selection_highlight()

func has_selection() -> bool:
	return (_current_tool >= 0 and _current_tool in _tool_buttons) or (not _selected_string_tool.is_empty() and _selected_string_tool in _tool_buttons)

func get_brush_size() -> int:
	return _brush_size

func _on_brush_shape_selected(index: int) -> void:
	# Kept for compatibility; OptionButton no longer used — toggle maps 0=round, 1=square.
	_round_brush = index == 0
	for button in _brush_shape_buttons:
		if is_instance_valid(button):
			_update_brush_shape_button(button)
	brush_shape_changed.emit(_round_brush)

func _on_brush_shape_toggled() -> void:
	_round_brush = not _round_brush
	for button in _brush_shape_buttons:
		if is_instance_valid(button):
			_update_brush_shape_button(button)
	brush_shape_changed.emit(_round_brush)

func _on_brush_decrease() -> void:
	var idx = BRUSH_SIZES.find(_brush_size)
	if idx > 0:
		_brush_size = BRUSH_SIZES[idx - 1]
		_update_brush_label()
		brush_size_changed.emit(_brush_size)

func _on_brush_increase() -> void:
	var idx = BRUSH_SIZES.find(_brush_size)
	if idx < BRUSH_SIZES.size() - 1:
		_brush_size = BRUSH_SIZES[idx + 1]
		_update_brush_label()
		brush_size_changed.emit(_brush_size)

func _update_brush_label() -> void:
	var shown: int = effective_brush_size()
	var text := "%dx%d" % [shown, shown]
	for label in _brush_labels:
		if is_instance_valid(label):
			label.text = text
			label.tooltip_text = "Brush size %s" % text

## The brush size the selected tool actually paints with. Tee boxes, and a green
## that is about to become a Green With Hole, are capped at a single tile.
func effective_brush_size() -> int:
	if _brush_limit != HoleLayout.UNLIMITED_BRUSH:
		return mini(_brush_size, _brush_limit)
	return _brush_size

## Cap (or uncap) the brush for the selected tool: 1 = single tile, 0 = no cap.
func set_brush_limit(limit: int) -> void:
	if _brush_limit == limit:
		return
	_brush_limit = limit
	_apply_brush_limit()

func _apply_brush_limit() -> void:
	var locked: bool = _brush_limit == 1
	for button in _brush_buttons:
		if is_instance_valid(button):
			button.disabled = locked
	for shape in _brush_shape_buttons:
		if is_instance_valid(shape):
			shape.disabled = locked
	_update_brush_label()

func set_brush_size(value: int) -> void:
	if value in BRUSH_SIZES:
		_brush_size = value
		_update_brush_label()
		brush_size_changed.emit(value)

## Keep the Green tile's flag and tooltip in sync with what the next green paints.
func set_green_placement_state(places_cup: bool) -> void:
	_green_places_cup = places_cup
	if not is_instance_valid(_green_tile_button):
		return
	_green_tile_button.set_green_places_cup(places_cup)
	if places_cup:
		_green_tile_button.tool_description = _with_course_tile_replacement(
				"The next placement will be a Green With Hole: one tile with a cup and flag.")
	else:
		_green_tile_button.tool_description = _with_course_tile_replacement(
				"The next placement will be a Green Without Hole. It uses the selected brush and adds no cup.")
	_green_tile_button.accessibility_description = "%s Shortcut %s." % [
		_green_tile_button.tool_description, _green_tile_button.hotkey]

## Append the shared replacement sentence without doubling it.
func _with_course_tile_replacement(desc: String) -> String:
	var sentence := TerrainTypes.REPLACES_ANY_COURSE_TILE
	if desc.contains(sentence):
		return desc
	if desc.is_empty():
		return sentence
	return desc + " " + sentence

func green_will_place_cup() -> bool:
	return _green_places_cup

## Enable/disable the Open Hole buttons and explain what is still missing. The
## nestled diamond draws its ring from the button's state — gold while a tee and
## a cup are waiting — so it is repainted here, after the switch.
func set_open_hole_state(can_open: bool, reason: String = "") -> void:
	for button in _open_hole_buttons:
		if not is_instance_valid(button):
			continue
		button.disabled = not can_open
		button.tool_description = OPEN_HOLE_TOOLTIP if can_open or reason.is_empty() \
				else "%s. %s" % [OPEN_HOLE_BLOCKED_TOOLTIP, reason]
		button._update_visual_state()

## Grey out, unselect and make unselectable the Tee tile while an unused tee waits.
func set_tee_box_state(can_place: bool, reason: String = "") -> void:
	_tee_box_can_place = can_place
	_tee_box_blocker = reason
	var btn: ToolButton = _tool_buttons.get(TerrainTypes.Type.TEE_BOX, null) as ToolButton
	if not is_instance_valid(btn):
		btn = _tee_tile_button
	if not is_instance_valid(btn):
		return

	# If the tee was selected and now becomes unavailable, unselect it.
	if not can_place and _current_tool == TerrainTypes.Type.TEE_BOX:
		clear_selection()

	btn.disabled = not can_place

	# Greyed out visual — modulate plus outline handled in TerrainTileButton,
	# but also set here so the change is immediate even if _update_visual_state
	# hasn't run yet.
	if not can_place:
		btn.modulate = Color(0.45, 0.45, 0.45, 0.65)
		var base_desc := "Tee for one hole — a single tile (1x1). Only one tee box may wait on the course at a time"
		if not reason.is_empty():
			btn.tool_description = "%s (%s)" % [base_desc, reason]
		else:
			btn.tool_description = "%s (Blocked — a tee box is already waiting. Open the hole first (H).)" % base_desc
	else:
		btn.modulate = Color(1, 1, 1, 1)
		btn.tool_description = "Tee for one hole — a single tile (1x1). Only one tee box may wait on the course at a time"

	btn.accessibility_description = "%s Shortcut %s." % [btn.tool_description, btn.hotkey]

	# Ensure the diamond outline reflects the disabled state immediately.
	btn._update_visual_state()

func set_view_state(_orientation: int, _isometric: bool) -> void:
	pass
