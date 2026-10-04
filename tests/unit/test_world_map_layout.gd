extends GutTest
## Breakpoint and layout contract for the responsive world atlas.

func test_desktop_windows_get_a_map_and_directory_split() -> void:
	assert_eq(WorldMapScreen.layout_mode_for(Vector2(1600, 1000)), WorldMapScreen.LayoutMode.DESKTOP)
	assert_eq(WorldMapScreen.layout_mode_for(Vector2(1280, 800)), WorldMapScreen.LayoutMode.DESKTOP)
	assert_eq(WorldMapScreen.layout_mode_for(Vector2(1920, 1080)), WorldMapScreen.LayoutMode.DESKTOP)

func test_tablet_orientation_selects_the_destination_shelf_layout() -> void:
	assert_eq(WorldMapScreen.layout_mode_for(Vector2(1024, 768)), WorldMapScreen.LayoutMode.TABLET_LANDSCAPE)
	assert_eq(WorldMapScreen.layout_mode_for(Vector2(768, 1024)), WorldMapScreen.LayoutMode.TABLET_PORTRAIT)
	assert_eq(WorldMapScreen.layout_mode_for(Vector2(700, 900)), WorldMapScreen.LayoutMode.TABLET_PORTRAIT)

func test_phone_landscape_gets_a_compact_side_by_side_picker() -> void:
	assert_eq(WorldMapScreen.layout_mode_for(Vector2(844, 390)), WorldMapScreen.LayoutMode.PHONE_LANDSCAPE)
	assert_eq(WorldMapScreen.layout_mode_for(Vector2(640, 360)), WorldMapScreen.LayoutMode.PHONE_LANDSCAPE)
	assert_eq(WorldMapScreen.layout_mode_for(Vector2(1920, 500)), WorldMapScreen.LayoutMode.PHONE_LANDSCAPE)

func test_phone_portrait_gets_a_scrollable_journal() -> void:
	assert_eq(WorldMapScreen.layout_mode_for(Vector2(390, 844)), WorldMapScreen.LayoutMode.PHONE_PORTRAIT)
	assert_eq(WorldMapScreen.layout_mode_for(Vector2(320, 568)), WorldMapScreen.LayoutMode.PHONE_PORTRAIT)
	assert_eq(WorldMapScreen.layout_mode_for(Vector2(600, 900)), WorldMapScreen.LayoutMode.PHONE_PORTRAIT)

func test_short_landscape_window_never_uses_the_tall_desktop_layout() -> void:
	assert_eq(WorldMapScreen.layout_mode_for(Vector2(1200, 650)), WorldMapScreen.LayoutMode.TABLET_LANDSCAPE)
	assert_ne(WorldMapScreen.layout_mode_for(Vector2(1600, 600)), WorldMapScreen.LayoutMode.DESKTOP)
