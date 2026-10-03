extends GutTest
## Unit tests for the title screen's layout breakpoints and card metrics.
##
## MainMenu is built from code, so the parts worth pinning down without a
## window are the pure ones: which arrangement a window size asks for, and how
## much room a two-line caption needs inside a card. The arrangement is
## checked end to end (all six actions on screen, no overlaps) by
## tests/harness/main_menu_layout_harness.gd.

func _mode(size: Vector2) -> int:
	return MainMenu.layout_mode_for(size)

func test_phone_sizes_use_the_single_column_layout() -> void:
	assert_eq(_mode(Vector2(390, 844)), MainMenu.Layout.PHONE, "phone portrait")
	assert_eq(_mode(Vector2(320, 568)), MainMenu.Layout.PHONE, "small phone")
	assert_eq(_mode(Vector2(600, 900)), MainMenu.Layout.PHONE, "narrow browser window")
	# Portrait is the phone layout even when the window is tall and roomy.
	assert_eq(_mode(Vector2(680, 1000)), MainMenu.Layout.PHONE, "narrow and tall")

func test_wide_short_windows_use_the_two_column_compact_layout() -> void:
	assert_eq(_mode(Vector2(844, 390)), MainMenu.Layout.LANDSCAPE, "rotated phone")
	assert_eq(_mode(Vector2(1180, 500)), MainMenu.Layout.LANDSCAPE, "squat browser window")
	# A short window is not offered the tall arrangements even when wide.
	assert_eq(_mode(Vector2(1920, 400)), MainMenu.Layout.LANDSCAPE, "short and very wide")

func test_tablet_sizes_use_the_centred_column() -> void:
	assert_eq(_mode(Vector2(768, 1024)), MainMenu.Layout.TABLET, "tablet portrait")
	assert_eq(_mode(Vector2(1024, 768)), MainMenu.Layout.TABLET, "tablet landscape")
	assert_eq(_mode(Vector2(MainMenu.TABLET_MIN_WIDTH, MainMenu.TALL_MIN_HEIGHT)),
		MainMenu.Layout.TABLET, "the smallest tablet window")

func test_desktop_sizes_use_the_split_layout() -> void:
	assert_eq(_mode(Vector2(1600, 1000)), MainMenu.Layout.WIDE, "the reference window")
	assert_eq(_mode(Vector2(1280, 800)), MainMenu.Layout.WIDE, "small laptop")
	assert_eq(_mode(Vector2(2560, 1440)), MainMenu.Layout.WIDE, "large desktop")
	assert_eq(_mode(Vector2(MainMenu.WIDE_MIN_WIDTH, MainMenu.TALL_MIN_HEIGHT)),
		MainMenu.Layout.WIDE, "the smallest wide window")

## Every size gets exactly one arrangement, and the split ones only start at
## their documented width - a regression here would leave a desktop window
## with the phone layout or two panels crammed into a phone's width.
func test_breakpoints_are_ordered() -> void:
	var sizes := [
		Vector2(360, 640), Vector2(390, 844), Vector2(844, 390), Vector2(1024, 768),
		Vector2(1120, 619), Vector2(1120, 620), Vector2(1600, 1000),
	]
	for size in sizes:
		var mode := _mode(size)
		if mode == MainMenu.Layout.WIDE or mode == MainMenu.Layout.TABLET:
			assert_gte(size.x, MainMenu.TABLET_MIN_WIDTH, "%s is wide enough for a two-panel mode" % size)
			assert_gte(size.y, MainMenu.TALL_MIN_HEIGHT, "%s is tall enough for a two-panel mode" % size)
		if mode == MainMenu.Layout.WIDE:
			assert_gte(size.x, MainMenu.WIDE_MIN_WIDTH, "%s is wide enough to split" % size)

func test_short_window_drops_out_of_the_wide_layout() -> void:
	# 1120x620 is the corner of the wide arrangement; one pixel less height and
	# the window is treated as short (the compact two-panel layout).
	assert_eq(_mode(Vector2(1120, 620)), MainMenu.Layout.WIDE)
	assert_eq(_mode(Vector2(1120, 619)), MainMenu.Layout.LANDSCAPE)

func test_card_caption_reserves_room_for_its_lines() -> void:
	assert_eq(MainMenu._caption_block(0, 2), 0.0, "no font, no caption strip")
	assert_eq(MainMenu._caption_block(14, 0), 0.0, "no lines, no caption strip")
	assert_almost_eq(MainMenu._caption_block(10, 1), 14.0, 0.001)
	# Two lines need exactly twice one line, so cards scale with their text.
	assert_almost_eq(MainMenu._caption_block(10, 2), 28.0, 0.001)
	assert_almost_eq(MainMenu._caption_block(12, 2), MainMenu._caption_block(12, 1) * 2.0, 0.001)
