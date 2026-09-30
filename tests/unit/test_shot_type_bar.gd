extends GutTest
## The shot-type row: one button per shot type, mutually exclusive, following
## `Golfer.shape_allowed()` so the lit button is always the shot that will be hit.

var bar: ShotTypeBar
var reported: Array[int] = []

func before_each() -> void:
	bar = ShotTypeBar.new()
	add_child_autofree(bar)
	reported.clear()
	bar.shape_selected.connect(func(shape: int): reported.append(shape))

func _press(shape: int) -> void:
	var button := bar.shot_button(shape)
	button.button_pressed = true
	button.pressed.emit()

func test_one_button_per_shot_type_in_shape_order() -> void:
	var labels: Array[String] = []
	for shape in bar.shot_count():
		labels.append(bar.shot_button(shape).text)
	assert_eq(labels, ["Straight", "Fade", "Draw", "Backspin", "Punch"])
	for shape in bar.shot_count():
		var button := bar.shot_button(shape)
		assert_true(button.toggle_mode, "Shot buttons hold their selection")
		assert_true(button.button_group != null, "Exactly one shot can be selected")
		assert_eq(int(button.get_meta("shot_type")), shape)
		assert_false(button.tooltip_text.is_empty(), "Each shot explains itself on hover")

func test_pressing_a_shot_lights_it_and_reports_it_once() -> void:
	bar.set_ready(true)
	bar.update_for_lie(TerrainTypes.Type.FAIRWAY)
	_press(2)
	assert_eq(reported, [2], "One press reports one shot")
	assert_eq(bar.selected_shape(), 2)
	assert_true(bar.shot_button(2).button_pressed)
	assert_false(bar.shot_button(0).button_pressed, "The previous shot releases")

func test_only_one_shot_is_ever_lit() -> void:
	bar.set_ready(true)
	bar.update_for_lie(TerrainTypes.Type.TEE_BOX)
	_press(1)
	_press(3)
	_press(4)
	assert_eq(bar.selected_shape(), 4)
	var lit := 0
	for shape in bar.shot_count():
		if bar.shot_button(shape).button_pressed:
			lit += 1
	assert_eq(lit, 1, "The row never lights two shots")

## Straight and low punch play from any off-green lie; the bend shots need a tee
## or fairway — `Golfer.shape_allowed()`, the execution guard's own rule.
func test_the_lie_greys_out_the_shots_it_forbids() -> void:
	bar.set_ready(true)
	bar.update_for_lie(TerrainTypes.Type.ROUGH)
	assert_false(bar.shot_button(0).disabled, "Straight is always available")
	assert_false(bar.shot_button(4).disabled, "Low punch is always available")
	for shape in [1, 2, 3]:
		assert_true(bar.shot_button(shape).disabled, "Bend shots need tee or fairway")
	bar.update_for_lie(TerrainTypes.Type.FAIRWAY)
	for shape in bar.shot_count():
		assert_false(bar.shot_button(shape).disabled, "Every shot is available from fairway")

func test_an_illegal_selection_falls_back_to_straight() -> void:
	bar.set_ready(true)
	bar.update_for_lie(TerrainTypes.Type.FAIRWAY)
	_press(2)
	assert_eq(bar.selected_shape(), 2)
	var fell_back := bar.update_for_lie(TerrainTypes.Type.BUNKER)
	assert_true(fell_back, "The caller is told to mirror the fallback")
	assert_eq(bar.selected_shape(), 0)
	assert_true(bar.shot_button(0).button_pressed, "Straight lights up in place")
	assert_eq(reported.size(), 1, "The fallback is not a new press")

func test_the_row_is_dead_while_the_owner_waits() -> void:
	bar.set_ready(true)
	bar.update_for_lie(TerrainTypes.Type.FAIRWAY)
	bar.set_ready(false)
	for shape in bar.shot_count():
		assert_true(bar.shot_button(shape).disabled, "Every shot greys out between turns")
	_press(1)
	assert_eq(reported, [], "A dead row reports nothing")
	assert_eq(bar.selected_shape(), 0, "A dead row keeps the lit shot")

## A dead row greys out, but the loaded shot keeps its ring so the owner can
## still see what is selected while they wait their turn.
func test_the_loaded_shot_stays_readable_on_a_dead_row() -> void:
	bar.set_ready(true)
	bar.update_for_lie(TerrainTypes.Type.FAIRWAY)
	bar.select_shape(2)
	bar.set_ready(false)
	assert_ne(bar.shot_button(2).get_theme_stylebox("disabled"),
		bar.shot_button(0).get_theme_stylebox("disabled"),
		"The lit shot is ringed apart from the other greyed shots")
	assert_eq(bar.shot_button(0).get_theme_stylebox("disabled"),
		bar.shot_button(4).get_theme_stylebox("disabled"),
		"Every unlit shot shares the same greyed face")

func test_select_shape_mirrors_the_golfer_without_reporting() -> void:
	bar.set_ready(true)
	bar.update_for_lie(TerrainTypes.Type.FAIRWAY)
	bar.select_shape(3)
	assert_eq(bar.selected_shape(), 3)
	assert_true(bar.shot_button(3).button_pressed)
	assert_eq(reported, [], "Mirroring the golfer is not a press")
	bar.select_shape(99)
	assert_eq(bar.selected_shape(), 0, "Out-of-range shapes fall back to straight")
