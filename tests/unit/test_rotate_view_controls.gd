extends GutTest
## Unit tests for the left control stack's Rotate buttons and the compass
## needle that stands beside their N / E / S / W letter.
##
## The two Rotate buttons used to carry the Unicode glyphs ⟲ / ⟳. The game's
## font has neither character, so both buttons showed a blank face and only the
## tooltips named them. They are drawn now — a ring with a gap at the bottom and
## an arrow head at the end of the sweep — and these tests pin down the two
## things a drawing has to get right: which way each sweep travels, and where
## each head lands. The needle's quarter turns are pinned the same way, and the
## last test reads the scene itself so a hand-edit of main.tscn cannot quietly
## leave a button back on a glyph the font cannot print.

## Node paths come out of the scene's state prefixed with the scene root.
const ROTATE_CONTROLS := "./UI/HUD/BottomBar/LeftControls/RotateViewControls"

func test_font_has_no_glyph_for_the_old_rotate_arrows() -> void:
	# U+27F2 / U+27F3 — the arrows the buttons used to be labelled with.
	assert_false(ThemeDB.fallback_font.has_char(0x27F2),
		"The ⟲ glyph is missing from the font, so the button must draw its arrow")
	assert_false(ThemeDB.fallback_font.has_char(0x27F3),
		"The ⟳ glyph is missing from the font, so the button must draw its arrow")

func test_arc_sweeps_the_way_the_course_turns() -> void:
	var cw := RotateViewButton.arc_angles(true)
	var ccw := RotateViewButton.arc_angles(false)
	# Screen angles grow clockwise, so the clockwise sweep grows...
	assert_true(cw.y > cw.x, "The clockwise arrow sweeps through growing angles")
	# ...and the counter-clockwise one is the very same sweep read backwards.
	assert_true(ccw.y < ccw.x, "The counter-clockwise arrow sweeps back the other way")
	assert_almost_eq(ccw.x, cw.y, 0.0001)
	assert_almost_eq(ccw.y, cw.x, 0.0001)
	# Both leave the same gap at the bottom of the ring.
	assert_almost_eq(absf(cw.y - cw.x) + deg_to_rad(RotateViewButton.GAP_DEGREES), TAU, 0.0001)

func test_heads_sit_on_opposite_sides_of_the_ring() -> void:
	var radius := RotateViewButton.ARROW_RADIUS
	var cw_tip := RotateViewButton.head_tip(radius, true)
	var ccw_tip := RotateViewButton.head_tip(radius, false)
	# The clockwise head finishes on the lower right of the ring, the
	# counter-clockwise head mirrors it onto the lower left.
	assert_true(cw_tip.x > 0.0, "The clockwise head finishes on the right of the ring")
	assert_true(ccw_tip.x < 0.0, "The counter-clockwise head finishes on the left of the ring")
	assert_true(cw_tip.y > 0.0, "Both heads finish at the foot of the ring")
	assert_almost_eq(cw_tip.x, -ccw_tip.x, 0.001)
	assert_almost_eq(cw_tip.y, ccw_tip.y, 0.001)
	# The tip stays clear of the ring so the head reads as a head.
	assert_true(RotateViewButton.head_tip(radius, true).length() > radius)

func test_head_travels_the_way_its_arc_turns() -> void:
	# At the foot of the ring the clockwise arrow is moving leftwards across the
	# bottom of the gap, and the counter-clockwise one rightwards.
	var cw_direction := RotateViewButton.travel_direction(RotateViewButton.arc_angles(true).y, true)
	var ccw_direction := RotateViewButton.travel_direction(RotateViewButton.arc_angles(false).y, false)
	assert_true(cw_direction.x < 0.0, "The clockwise head points across the gap to the left")
	assert_true(ccw_direction.x > 0.0, "The counter-clockwise head points across the gap to the right")
	assert_almost_eq(cw_direction.x, -ccw_direction.x, 0.0001)
	assert_almost_eq(cw_direction.y, ccw_direction.y, 0.0001)

func test_buttons_are_drawn_not_typed() -> void:
	var ccw_button := RotateViewButton.new()
	add_child_autofree(ccw_button)
	assert_eq(ccw_button.text, "", "The sweep is the label: no glyph is typed on the face")
	assert_false(ccw_button.clockwise, "The Q button sweeps counter-clockwise")
	# The drawn arrow keeps the footprint the text buttons had.
	assert_eq(ccw_button.custom_minimum_size, Vector2(28, 24))

	var cw_button := RotateViewButton.new()
	cw_button.clockwise = true
	add_child_autofree(cw_button)
	assert_true(cw_button.clockwise, "The Shift+Q button sweeps clockwise")
	assert_eq(cw_button.text, "")

func test_needle_points_the_way_the_course_faces() -> void:
	assert_true(CompassNeedle.needle_direction(0).is_equal_approx(Vector2.UP), "N points up")
	assert_true(CompassNeedle.needle_direction(1).is_equal_approx(Vector2.RIGHT), "E points right")
	assert_true(CompassNeedle.needle_direction(2).is_equal_approx(Vector2.DOWN), "S points down")
	assert_true(CompassNeedle.needle_direction(3).is_equal_approx(Vector2.LEFT), "W points left")

func test_needle_turns_a_quarter_turn_per_rotation() -> void:
	var needle := CompassNeedle.new()
	add_child_autofree(needle)
	assert_eq(needle.orientation, 0, "A fresh needle faces north")
	needle.orientation = 3
	assert_eq(needle.orientation, 3, "West")
	# A fourth rotation comes full circle, and rotating back from north is west.
	needle.orientation = 4
	assert_eq(needle.orientation, 0, "Four quarter turns come back to north")
	needle.orientation = -1
	assert_eq(needle.orientation, 3, "Turning back from north faces west")

func test_scene_brackets_the_compass_with_the_two_rotate_arrows() -> void:
	var scene: PackedScene = load("res://scenes/main/main.tscn")
	var state := scene.get_state()
	var children := _child_names(state, ROTATE_CONTROLS)
	assert_eq(children, ["RotateCCWBtn", "OrientationNeedle", "OrientationLabel", "RotateCWBtn"],
		"The needle and its letter stand between the two Rotate arrows")

	var ccw := _node_index(state, ROTATE_CONTROLS + "/RotateCCWBtn")
	var cw := _node_index(state, ROTATE_CONTROLS + "/RotateCWBtn")
	var needle := _node_index(state, ROTATE_CONTROLS + "/OrientationNeedle")
	assert_ne(ccw, -1, "The counter-clockwise button is in the scene")
	assert_ne(cw, -1, "The clockwise button is in the scene")
	assert_ne(needle, -1, "The compass needle is in the scene")

	assert_eq(_script_name(state, ccw), "RotateViewButton")
	assert_eq(_script_name(state, cw), "RotateViewButton")
	assert_eq(_script_name(state, needle), "CompassNeedle")

	# Only the clockwise button sweeps clockwise.
	assert_eq(_property(state, cw, "clockwise"), true)
	assert_null(_property(state, ccw, "clockwise"))
	# Neither button falls back to the glyphs the font cannot print.
	for button in [ccw, cw]:
		var text = _property(state, button, "text")
		assert_true(text == null or text == "", "No glyph text is left on the Rotate buttons")

func _node_index(state: SceneState, path: String) -> int:
	for i in state.get_node_count():
		if str(state.get_node_path(i)) == path:
			return i
	return -1

## The children of `parent`, in the order the scene lists them.
func _child_names(state: SceneState, parent: String) -> Array[String]:
	var names: Array[String] = []
	for i in state.get_node_count():
		var path := str(state.get_node_path(i))
		if path.begins_with(parent + "/") and path.get_slice_count("/") == parent.get_slice_count("/") + 1:
			names.append(state.get_node_name(i))
	return names

func _property(state: SceneState, node_index: int, name: String) -> Variant:
	for p in state.get_node_property_count(node_index):
		if state.get_node_property_name(node_index, p) == name:
			return state.get_node_property_value(node_index, p)
	return null

func _script_name(state: SceneState, node_index: int) -> String:
	var script: Script = _property(state, node_index, "script")
	return script.get_global_name() if script else ""
