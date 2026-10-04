extends GutTest
## Unit tests for the Start New Game screen's layout rules, option copy and
## drawn components.
##
## StartNewGameScreen is built from code, so the parts worth pinning down
## without a window are the pure ones: which arrangement a window size asks
## for, what each option says about itself, the course plan drawn from
## GeneratedCourse's layout table, and the line budget wrapped text reserves.
## The arrangements are checked end to end (every option on screen, tappable,
## not overlapping, no scrolling where none is promised) by
## tests/harness/start_new_game_layout_harness.gd.

const Screen := preload("res://scripts/ui/start_new_game_screen.gd")

func _mode(size: Vector2) -> int:
	return StartNewGameScreen.layout_mode_for(size)

# --- breakpoints --------------------------------------------------------------

func test_phone_sizes_use_the_single_column() -> void:
	assert_eq(_mode(Vector2(390, 844)), StartNewGameScreen.Layout.PHONE, "phone portrait")
	assert_eq(_mode(Vector2(360, 640)), StartNewGameScreen.Layout.PHONE, "small phone")
	assert_eq(_mode(Vector2(320, 568)), StartNewGameScreen.Layout.PHONE, "smallest phone")
	assert_eq(_mode(Vector2(680, 1000)), StartNewGameScreen.Layout.PHONE, "narrow and tall window")
	# Wider than tall but too narrow for two panels.
	assert_eq(_mode(Vector2(599, 400)), StartNewGameScreen.Layout.PHONE, "tiny landscape window")

func test_rotated_phones_and_squat_windows_use_the_compact_columns() -> void:
	assert_eq(_mode(Vector2(844, 390)), StartNewGameScreen.Layout.LANDSCAPE, "rotated phone")
	assert_eq(_mode(Vector2(640, 360)), StartNewGameScreen.Layout.LANDSCAPE, "small rotated phone")
	assert_eq(_mode(Vector2(1024, 600)), StartNewGameScreen.Layout.LANDSCAPE, "7-inch tablet, landscape")
	assert_eq(_mode(Vector2(1920, 500)), StartNewGameScreen.Layout.LANDSCAPE, "short and very wide")

func test_tablets_in_portrait_use_the_centred_column() -> void:
	assert_eq(_mode(Vector2(768, 1024)), StartNewGameScreen.Layout.TABLET, "tablet portrait")
	assert_eq(_mode(Vector2(820, 1180)), StartNewGameScreen.Layout.TABLET, "large tablet portrait")
	# Wide enough for two panels, but portrait: one column reads better.
	assert_eq(_mode(Vector2(1024, 1366)), StartNewGameScreen.Layout.TABLET, "12.9-inch tablet portrait")
	assert_eq(_mode(Vector2(StartNewGameScreen.TABLET_MIN_WIDTH, StartNewGameScreen.TABLET_MIN_HEIGHT)),
		StartNewGameScreen.Layout.TABLET, "the smallest tablet window")

func test_desktops_and_landscape_tablets_use_the_sheet_and_rail() -> void:
	assert_eq(_mode(Vector2(1600, 1000)), StartNewGameScreen.Layout.WIDE, "the reference window")
	assert_eq(_mode(Vector2(1280, 720)), StartNewGameScreen.Layout.WIDE, "720p")
	assert_eq(_mode(Vector2(1366, 657)), StartNewGameScreen.Layout.WIDE, "browser on a 1366x768 laptop")
	assert_eq(_mode(Vector2(2560, 1440)), StartNewGameScreen.Layout.WIDE, "large desktop")
	# Unlike the title screen, a 1024x768 tablet gets the two-panel layout.
	assert_eq(_mode(Vector2(1024, 768)), StartNewGameScreen.Layout.WIDE, "tablet landscape")
	assert_eq(_mode(Vector2(StartNewGameScreen.WIDE_MIN_WIDTH, StartNewGameScreen.WIDE_MIN_HEIGHT)),
		StartNewGameScreen.Layout.WIDE, "the smallest wide window")

func test_wide_layout_edges() -> void:
	var w := float(StartNewGameScreen.WIDE_MIN_WIDTH)
	var h := float(StartNewGameScreen.WIDE_MIN_HEIGHT)
	assert_eq(_mode(Vector2(w, h - 1.0)), StartNewGameScreen.Layout.LANDSCAPE, "one pixel too short")
	assert_eq(_mode(Vector2(w - 1.0, h)), StartNewGameScreen.Layout.LANDSCAPE, "one pixel too narrow")
	assert_eq(_mode(Vector2(1100, 1100)), StartNewGameScreen.Layout.TABLET, "a square window is not wide")

## Every size gets exactly one arrangement, and none is offered below the
## size it was designed for.
func test_breakpoints_respect_their_minimums() -> void:
	for x in range(300, 2700, 97):
		for y in range(300, 1600, 89):
			var size := Vector2(x, y)
			match _mode(size):
				StartNewGameScreen.Layout.WIDE:
					assert_true(size.x >= StartNewGameScreen.WIDE_MIN_WIDTH and size.y >= StartNewGameScreen.WIDE_MIN_HEIGHT \
						and size.x > size.y, "%s qualifies for WIDE" % size)
				StartNewGameScreen.Layout.TABLET:
					assert_true(size.x >= StartNewGameScreen.TABLET_MIN_WIDTH \
						and size.y >= StartNewGameScreen.TABLET_MIN_HEIGHT, "%s qualifies for TABLET" % size)
				StartNewGameScreen.Layout.LANDSCAPE:
					assert_true(size.x >= StartNewGameScreen.LANDSCAPE_MIN_WIDTH and size.x > size.y,
						"%s qualifies for LANDSCAPE" % size)

# --- option copy -----------------------------------------------------------

func test_money_labels() -> void:
	assert_eq(StartNewGameScreen._money_label(100000), "$100,000")
	assert_eq(StartNewGameScreen._money_label(1500000), "$1,500,000")
	assert_eq(StartNewGameScreen._money_label(-1), "Unlimited")
	assert_eq(StartNewGameScreen._money_short_label(150000), "$150K")
	assert_eq(StartNewGameScreen._money_short_label(-1), "Unlimited")

func test_every_money_option_has_a_caption() -> void:
	for option in StartNewGameScreen.MONEY_OPTIONS:
		assert_true(StartNewGameScreen.MONEY_CAPTIONS.has(option), "caption for %d" % option)
		assert_false(str(StartNewGameScreen.MONEY_CAPTIONS.get(option, "")).is_empty())

func test_hole_copy_names_the_par_the_generator_uses() -> void:
	for count in StartNewGameScreen.HOLE_OPTIONS:
		if count == 0:
			assert_string_contains(StartNewGameScreen.hole_hint(0), "Build every hole yourself")
			assert_string_contains(StartNewGameScreen.plan_caption(0), "Empty plot")
			continue
		var par := GeneratedCourse.get_par_for_count(count)
		assert_string_contains(StartNewGameScreen.hole_hint(count), "%d holes (%d par)" % [count, par])
		assert_string_contains(StartNewGameScreen.hole_hint_short(count), "%d holes (par %d)" % [count, par])
		assert_eq(StartNewGameScreen.plan_caption(count), "%d holes · par %d" % [count, par])
		assert_string_contains(StartNewGameScreen._holes_tooltip(count), "Par %d" % par)

func test_difficulty_effects_are_read_from_the_presets() -> void:
	var easy := StartNewGameScreen.difficulty_effects(DifficultyPresets.Preset.EASY)
	assert_eq(easy, ["Upkeep −20%", "Golfers +20%", "Building costs −20%", "Reputation decay −50%"] as Array[String])
	var hard := StartNewGameScreen.difficulty_effects(DifficultyPresets.Preset.HARD)
	assert_eq(hard, ["Upkeep +30%", "Golfers −20%", "Building costs +20%", "Reputation decay +100%"] as Array[String])
	# Normal is the baseline every other preset is measured against.
	assert_eq(StartNewGameScreen.difficulty_effects(DifficultyPresets.Preset.NORMAL).size(), 0)
	assert_eq(StartNewGameScreen.difficulty_effects_line(DifficultyPresets.Preset.NORMAL), "Standard costs and demand")
	assert_eq(StartNewGameScreen.difficulty_effects_line(DifficultyPresets.Preset.EASY), "Upkeep −20% · Golfers +20%")
	assert_eq(StartNewGameScreen.difficulty_effects_line(DifficultyPresets.Preset.HARD, 4).count(" · "), 3)

func test_difficulty_tooltip_spells_out_the_overdraft() -> void:
	assert_string_contains(StartNewGameScreen.difficulty_tooltip(DifficultyPresets.Preset.EASY), "−$5,000")
	assert_string_contains(StartNewGameScreen.difficulty_tooltip(DifficultyPresets.Preset.HARD), "below $0")

## The budget is picked separately on this screen, so a difficulty must not
## promise more (or less) starting money - the preset value is not used.
func test_difficulty_descriptions_do_not_promise_a_budget() -> void:
	for preset in DifficultyPresets.get_all_presets():
		var description := str(DifficultyPresets.get_modifiers(preset).get("description", "")).to_lower()
		assert_false("starting money" in description, "%d: %s" % [preset, description])
		assert_false("tight budget" in description, "%d: %s" % [preset, description])

func test_feature_summaries() -> void:
	var all_on := {"weather": true, "wind": true, "seasons": true}
	assert_eq(StartNewGameScreen.features_summary(all_on), "Weather · Wind · Seasons")
	assert_eq(StartNewGameScreen.features_summary({"weather": false, "wind": true, "seasons": false}), "Wind")
	assert_eq(StartNewGameScreen.features_summary({}), "None")
	assert_eq(StartNewGameScreen.footer_summary("Hard", -1, 0, {}),
		"Hard  ·  Unlimited  ·  Empty plot  ·  No features")
	assert_eq(StartNewGameScreen.footer_summary("Normal", 100000, 9, all_on),
		"Normal  ·  $100,000  ·  9 holes (par 36)  ·  Weather, Wind, Seasons")

# --- defaults and options ------------------------------------------------------

func test_options_keep_the_world_map_contract() -> void:
	var screen: StartNewGameScreen = Screen.new()
	var options := screen.get_options()
	assert_false(str(options["company_name"]).is_empty(), "a company name is always filled in")
	assert_eq(options["difficulty"], DifficultyPresets.Preset.NORMAL)
	assert_eq(options["starting_money"], 100000)
	assert_eq(options["generated_holes"], 0)
	assert_eq(options["features"], {"weather": true, "wind": true, "seasons": true})
	screen.free()

# --- course plan -----------------------------------------------------------

func test_course_plan_lays_out_every_generated_hole_inside_the_plot() -> void:
	for count in StartNewGameScreen.HOLE_OPTIONS:
		var data := CoursePlanPreview.plan(count)
		var plot: Rect2 = data["plot"]
		var holes: Array = data["holes"]
		assert_eq(holes.size(), count, "%d holes drawn" % count)
		for hole in holes:
			assert_true(plot.has_point(hole["tee"]), "%d: tee %s inside %s" % [count, hole["tee"], plot])
			assert_true(plot.has_point(hole["green"]), "%d: green %s inside %s" % [count, hole["green"], plot])
		# The starter buildings come with a generated course, not an empty plot.
		assert_eq((data["amenities"] as Array).size(), 0 if count == 0 else GeneratedCourse.AMENITY_SPOTS.size())

func test_course_plan_uses_the_parcels_the_course_is_built_on() -> void:
	var parcel := float(LandManager.PARCEL_SIZE)
	assert_eq((CoursePlanPreview.plan(9)["plot"] as Rect2).size, Vector2(2, 2) * parcel, "2x2 parcels up to 9 holes")
	assert_eq((CoursePlanPreview.plan(18)["plot"] as Rect2).size, Vector2(3, 3) * parcel, "3x3 parcels for 18")
	assert_eq((CoursePlanPreview.plan(18)["parcel_lines"] as Array).size(), 2)

func test_course_plan_follows_the_generator_layout() -> void:
	var layout := GeneratedCourse.layout_for(6)
	var holes: Array = CoursePlanPreview.plan(6)["holes"]
	for i in layout.size():
		assert_eq(holes[i]["tee"], Vector2(layout[i][0]))
		assert_eq(holes[i]["green"], Vector2(layout[i][1]))

func test_course_plan_draws_one_flag_per_hole() -> void:
	for count in [3, 9, 18]:
		var preview := CoursePlanPreview.new()
		preview.size = Vector2(300, 300)
		preview.set_hole_count(count, false)
		var canvas := RecordingCanvas.new()
		preview._paint(canvas)
		# Hole numbers are the only text the plan draws.
		assert_eq(canvas.strings.size(), count, "%d numbered tees" % count)
		preview.free()

# --- glyphs ------------------------------------------------------------------

func test_every_glyph_kind_draws_something() -> void:
	for kind in SetupGlyph.Kind.values():
		var glyph := SetupGlyph.make(kind, 24.0)
		glyph.size = glyph.custom_minimum_size
		var canvas := RecordingCanvas.new()
		glyph._paint(canvas)
		assert_gt(canvas.calls, 0, "glyph kind %d draws" % kind)
		glyph.free()

func test_switch_glyph_is_wider_and_shows_its_state() -> void:
	var glyph := SetupGlyph.make(SetupGlyph.Kind.SWITCH, 20.0)
	assert_almost_eq(glyph.custom_minimum_size.x, 35.0, 0.01)
	glyph.size = glyph.custom_minimum_size
	var on_canvas := RecordingCanvas.new()
	glyph._paint(on_canvas)
	glyph.on = false
	var off_canvas := RecordingCanvas.new()
	glyph._paint(off_canvas)
	assert_ne(on_canvas.knob_x, off_canvas.knob_x, "the knob moves when switched off")
	glyph.free()

func test_difficulty_glyph_lights_one_bar_per_level() -> void:
	var lit := []
	for level in [1, 2, 3]:
		var glyph := SetupGlyph.make(SetupGlyph.Kind.DIFFICULTY, 24.0, level, Color.RED)
		glyph.size = glyph.custom_minimum_size
		var canvas := RecordingCanvas.new()
		glyph._paint(canvas)
		lit.append(canvas.count_color(Color.RED))
		glyph.free()
	assert_eq(lit, [1, 2, 3])

# --- wrapped text ----------------------------------------------------------------

## The line budget reserved for wrapped text must never be smaller than what
## the label really needs, or the screen would cut descriptions short.
func test_wrapped_line_estimate_never_undercounts_a_real_label() -> void:
	var texts := [
		StartNewGameScreen.hole_hint(9), StartNewGameScreen.hole_hint(0),
		str(DifficultyPresets.get_modifiers(DifficultyPresets.Preset.EASY).get("description", "")),
		str(DifficultyPresets.get_modifiers(DifficultyPresets.Preset.HARD).get("description", "")),
	]
	var font: Font = ThemeDB.fallback_font
	for font_size in [12, 13, 16, 21]:
		for width in [150.0, 175.0, 230.0, 368.0, 520.0]:
			for text in texts:
				var label := Label.new()
				label.text = text
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				label.add_theme_font_size_override("font_size", font_size)
				add_child_autofree(label)
				label.size = Vector2(width, 600)
				var estimate := MenuStyle.wrapped_lines(text, font, font_size, width)
				assert_gte(estimate, label.get_line_count(), "%dpx at %.0f: %s" % [font_size, width, text])
				assert_lte(estimate, label.get_line_count() + 1, "within a line of the real count")

## Draws nothing; records what a glyph or plan asked a canvas to draw.
class RecordingCanvas:
	var calls := 0
	var strings: Array = []
	var colors: Array = []
	var knob_x := -1.0

	func draw_rect(_rect: Rect2, color: Color, _filled: bool = true, _width: float = -1.0, _aa: bool = false) -> void:
		calls += 1
		colors.append(color)

	func draw_circle(position: Vector2, _radius: float, color: Color, _filled: bool = true,
			_width: float = -1.0, _aa: bool = false) -> void:
		calls += 1
		colors.append(color)
		knob_x = position.x

	func draw_colored_polygon(_points: PackedVector2Array, color: Color, _uvs: PackedVector2Array = PackedVector2Array(),
			_texture: Texture2D = null) -> void:
		calls += 1
		colors.append(color)

	func draw_polyline(_points: PackedVector2Array, color: Color, _width: float = -1.0, _aa: bool = false) -> void:
		calls += 1
		colors.append(color)

	func draw_line(_from: Vector2, _to: Vector2, color: Color, _width: float = -1.0, _aa: bool = false) -> void:
		calls += 1
		colors.append(color)

	func draw_string(_font: Font, _pos: Vector2, text: String, _align: int = 0, _width: float = -1.0,
			_size: int = 16, _color: Color = Color.WHITE, _justify: int = 3, _direction: int = 0,
			_orientation: int = 0) -> void:
		calls += 1
		strings.append(text)

	func count_color(color: Color) -> int:
		var n := 0
		for c in colors:
			if (c as Color).is_equal_approx(color):
				n += 1
		return n
