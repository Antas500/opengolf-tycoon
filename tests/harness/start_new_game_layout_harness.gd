extends Node
## Run: godot --headless --path . res://tests/harness/start_new_game_layout_harness.tscn
##
## Opens the real Start New Game screen from the title screen and drives it
## through phone, rotated-phone, tablet and desktop window sizes. At every size
## it checks that the arrangement picked by StartNewGameScreen.layout_mode_for
## shows every option and both actions as big enough, non-overlapping targets
## inside the window, never cuts or trims text, never scrolls sideways, keeps
## Choose Location on screen without scrolling, and does not scroll at all in
## the arrangements that promise not to (WIDE and LANDSCAPE).
##
## Then it plays the screen with real clicks and keys: picks a difficulty,
## budget, hole count and features, renames the company, checks the summary
## and course plan follow, resizes the live window across arrangements and
## checks nothing picked is lost, and finally leaves with Esc (back to the
## title screen) and with Choose Location (on to the world map).
##
## Prints one PASS/FAIL line per check and exits non-zero on any failure.

const TAG := "START_NEW_GAME"
## 3 difficulties + 4 budgets + 5 hole counts + 3 features + random name +
## Back + Choose Location.
const BUTTON_COUNT := 18
const MIN_TARGET := 44.0

var main: Node
var failures := 0

func _check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
	print("%s: %s: %s" % [TAG, "PASS" if ok else "FAIL", description])

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

## Resize, then wait out the screen's settle delay (small same-layout resizes
## rebuild once the window stops changing) and the course plan's draw-in.
func _set_window(width: int, height: int) -> void:
	get_window().size = Vector2i(width, height)
	await _frames(4)
	await get_tree().create_timer(StartNewGameScreen.SETTLE_DELAY + 0.15).timeout
	await _frames(3)

func _screen() -> StartNewGameScreen:
	return main.get_node_or_null("UI/HUD/StartNewGameScreen") as StartNewGameScreen

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await _set_window(390, 844)
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await _frames(6)
	main._on_menu_start_new_game()
	await _frames(4)
	_check(_screen() != null, "Start New Game opens the company setup screen")
	if _screen() == null:
		_finish()
		return
	_check(_screen().get_options()["generated_holes"] == 0 and _screen().get_options()["starting_money"] == 100000,
		"the defaults are unchanged: $100,000 and no generated holes")
	# A generated course makes the plan worth checking at every size.
	_screen()._select_holes(9)

	var L := StartNewGameScreen.Layout
	var sizes := [
		[390, 844, L.PHONE, "phone portrait"],
		[360, 640, L.PHONE, "small phone"],
		[844, 390, L.LANDSCAPE, "rotated phone"],
		[640, 360, L.LANDSCAPE, "small rotated phone"],
		[1000, 620, L.LANDSCAPE, "squat window"],
		[768, 1024, L.TABLET, "tablet portrait"],
		[1024, 1366, L.TABLET, "large tablet portrait"],
		[1024, 768, L.WIDE, "tablet landscape"],
		[1000, 640, L.WIDE, "smallest wide window"],
		[1280, 720, L.WIDE, "720p desktop"],
		[1366, 657, L.WIDE, "laptop browser window"],
		[1600, 1000, L.WIDE, "desktop"],
		[2560, 1440, L.WIDE, "large desktop"],
	]
	for entry in sizes:
		await _set_window(entry[0], entry[1])
		_check_screen(str(entry[3]), float(entry[0]), float(entry[1]), int(entry[2]))

	await _play_the_screen()
	_finish()

func _finish() -> void:
	print("%s: %d failures" % [TAG, failures])
	get_tree().quit(0 if failures == 0 else 1)

# =============================================================================
# LAYOUT CHECKS
# =============================================================================

func _check_screen(tag: String, width: float, height: float, expected_mode: int) -> void:
	var screen := _screen()
	var view := Rect2(0.0, 0.0, width, height)
	_check(screen._layout_mode == expected_mode,
		"%s: %dx%d uses layout %d (got %d)" % [tag, width, height, expected_mode, screen._layout_mode])

	var buttons := _find_all(screen, "Button").filter(func(b): return b.is_visible_in_tree())
	_check(buttons.size() == BUTTON_COUNT, "%s: every option and action is a button (%d of %d)" % [
		tag, buttons.size(), BUTTON_COUNT])
	var targets: Array = buttons.duplicate()
	targets.append(screen._company_input)
	_check(screen._company_input != null and screen._company_input.is_visible_in_tree(),
		"%s: the company name field is shown" % tag)
	_check(screen._difficulty_buttons.size() == 3 and screen._money_buttons.size() == 4 \
		and screen._hole_buttons.size() == 5 and screen._feature_boxes.size() == 3,
		"%s: three difficulties, four budgets, five hole counts and three features" % tag)

	var too_small: Array = []
	var outside: Array = []
	for target in targets:
		var rect: Rect2 = target.get_global_rect()
		if rect.size.y < MIN_TARGET - 0.5 or rect.size.x < MIN_TARGET - 0.5:
			too_small.append("%s %s" % [_describe(target), rect.size])
		# Scrolling layouts only promise the horizontal extent; the rest must
		# sit entirely inside the window.
		var scrolls := expected_mode == StartNewGameScreen.Layout.PHONE or expected_mode == StartNewGameScreen.Layout.TABLET
		var inside := rect.position.x >= -1.0 and rect.end.x <= width + 1.0 if scrolls else _within(rect, view)
		if not inside:
			outside.append("%s %s" % [_describe(target), rect])
	_check(too_small.is_empty(), "%s: every target is at least %dx%d (%s)" % [tag, MIN_TARGET, MIN_TARGET, too_small])
	_check(outside.is_empty(), "%s: every target is inside the window (%s)" % [tag, outside])

	var overlaps: Array = []
	for i in targets.size():
		for j in range(i + 1, targets.size()):
			var a := _visible_rect(targets[i])
			var b := _visible_rect(targets[j])
			if a.size.x > 0.0 and b.size.x > 0.0 and a.intersects(b, false):
				overlaps.append("%s / %s" % [_describe(targets[i]), _describe(targets[j])])
	_check(overlaps.is_empty(), "%s: no two targets overlap (%s)" % [tag, overlaps])

	var next: Button = screen._next_button
	_check(next != null and _within(next.get_global_rect(), view) \
		and _visible_rect(next).size.is_equal_approx(next.get_global_rect().size),
		"%s: Choose Location is on screen without scrolling" % tag)
	_check(screen._back_button != null and _within(screen._back_button.get_global_rect(), view),
		"%s: Back is on screen" % tag)

	if expected_mode == StartNewGameScreen.Layout.WIDE or expected_mode == StartNewGameScreen.Layout.LANDSCAPE:
		_check(not _scrolls(screen), "%s: everything fits without scrolling" % tag)
	_check(screen._page.size.x <= width + 0.5, "%s: nothing runs off the side (page %.0f wide)" % [tag, screen._page.size.x])

	var cut := _cut_text(screen)
	_check(cut.is_empty(), "%s: no text is cut short or trimmed (%s)" % [tag, cut])

	var backdrop := screen.get_node_or_null("Backdrop") as Control
	_check(backdrop != null and backdrop.get_global_rect().size == Vector2(width, height),
		"%s: the drawn backdrop covers the window" % tag)

	var holes := int(screen.get_options()["generated_holes"])
	if screen._course_plan != null:
		_check(screen._course_plan.hole_count == holes and screen._course_plan.is_visible_in_tree(),
			"%s: the course plan shows the %d holes picked" % [tag, holes])
		_check(screen._course_plan.size.x >= 100.0 and screen._course_plan.size.y >= 100.0,
			"%s: the course plan is big enough to read (%s)" % [tag, screen._course_plan.size])
	else:
		_check(expected_mode == StartNewGameScreen.Layout.LANDSCAPE and height < 540.0,
			"%s: only a short landscape window leaves the course plan out" % tag)

	for button in screen._difficulty_buttons + screen._money_buttons + screen._hole_buttons:
		if str(button.accessibility_name).is_empty() or not button.has_theme_stylebox_override("hover_pressed"):
			_check(false, "%s: option buttons are named for screen readers and styled when hovered while picked" % tag)
			return

# =============================================================================
# PLAYING THE SCREEN
# =============================================================================

func _play_the_screen() -> void:
	await _set_window(1600, 1000)
	var screen := _screen()

	await _click(_button_for(screen._difficulty_buttons, DifficultyPresets.Preset.HARD))
	_check(screen.get_options()["difficulty"] == DifficultyPresets.Preset.HARD, "clicking Hard picks Hard")
	_check(_pressed_values(screen._difficulty_buttons) == [DifficultyPresets.Preset.HARD],
		"only the Hard card is shown as picked")
	_check(screen._summary_values["difficulty"].text == "Hard", "the summary rail says Hard")

	await _click(_button_for(screen._money_buttons, -1))
	_check(screen.get_options()["starting_money"] == -1, "clicking Unlimited picks an unlimited budget")
	_check(screen._summary_values["money"].text == "Unlimited", "the summary rail says Unlimited")

	await _click(_button_for(screen._hole_buttons, 18))
	_check(screen.get_options()["generated_holes"] == 18, "clicking 18 asks for an 18-hole course")
	_check(screen._course_plan.hole_count == 18 and screen._course_plan.is_revealing(),
		"the course plan starts drawing the 18 holes in")
	var waited := 0.0
	while screen._course_plan.is_revealing() and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	_check(not screen._course_plan.is_revealing(), "the course plan finishes drawing in (%.1fs)" % waited)
	_check(screen._plan_caption.text == "18 holes · par 72", "the plan caption reads 18 holes, par 72")

	await _click(screen._feature_boxes["wind"])
	_check(screen.get_options()["features"] == {"weather": true, "wind": false, "seasons": true},
		"clicking Wind turns wind off and leaves the others on")
	_check(screen._summary_values["features"].text == "Weather · Seasons", "the summary lists the features left on")
	await _click(screen._feature_boxes["wind"])
	await _click(screen._feature_boxes["wind"])
	_check(not screen.get_options()["features"]["wind"], "Wind toggles back on and off")

	screen._company_input.text = "Harness Links"
	screen._company_input.text_changed.emit("Harness Links")
	await _frames(1)
	_check(screen._summary_company.text == "Harness Links", "the rail shows the company name as it is typed")
	screen._company_input.text = ""
	screen._company_input.text_changed.emit("")
	await _frames(1)
	_check(screen._summary_company.text == StartNewGameScreen.NAME_PLACEHOLDER and \
		not str(screen.get_options()["company_name"]).is_empty(),
		"a blank name shows the placeholder and still gets a random name")
	await _click(_find_by_name(screen, "RandomNameButton"))
	_check(not screen._company_input.text.is_empty() and screen._summary_company.text == screen._company_input.text,
		"the die fills in a random name and the rail follows")
	screen._company_input.text = "Harness Links"
	screen._company_input.text_changed.emit("Harness Links")

	# Everything picked survives the screen being rebuilt for another window.
	var picked: Dictionary = screen.get_options()
	for size in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(768, 1024), Vector2i(1280, 720)]:
		await _set_window(size.x, size.y)
		screen = _screen()
		_check(screen.get_options() == picked, "%dx%d keeps every choice across the rebuild" % [size.x, size.y])
		_check(_pressed_values(screen._difficulty_buttons) == [DifficultyPresets.Preset.HARD] \
			and _pressed_values(screen._money_buttons) == [-1] and _pressed_values(screen._hole_buttons) == [18] \
			and not screen._feature_boxes["wind"].button_pressed and screen._feature_boxes["seasons"].button_pressed,
			"%dx%d shows the same picks" % [size.x, size.y])

	# A small drag inside one arrangement rebuilds once the window settles.
	await _set_window(1240, 700)
	_check(_screen()._built_size == Vector2(1240, 700), "a small resize is re-measured once the window settles")
	_check(not _scrolls(_screen()), "the re-measured window still fits without scrolling")

	# Esc goes back to the title screen.
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape)
	await _frames(3)
	_check(_screen() == null or _screen().is_queued_for_deletion(), "Esc leaves the setup screen")
	_check(main.main_menu != null and main.main_menu.visible, "Esc returns to the title screen")

	# Choose Location hands the options to the world map.
	main._on_menu_start_new_game()
	await _frames(4)
	screen = _screen()
	screen._company_input.text = "Harness Links"
	await _click(_button_for(screen._hole_buttons, 6))
	var sent: Array = []
	screen.next_requested.connect(func(options: Dictionary): sent.append(options))
	await _click(screen._next_button)
	await _frames(3)
	_check(sent.size() == 1 and sent[0]["company_name"] == "Harness Links" and sent[0]["generated_holes"] == 6,
		"Choose Location sends the company name and hole count on")
	var world_map := main.get_node_or_null("UI/HUD/WorldMapScreen")
	_check(world_map != null and world_map.visible, "Choose Location opens the world map")

# =============================================================================
# HELPERS
# =============================================================================

## A real left click in the middle of `control`, through the viewport.
func _click(control: Control) -> void:
	if control == null:
		_check(false, "a control to click exists")
		return
	var at := control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_viewport().push_input(event)
		await _frames(1)
	await _frames(1)

func _button_for(buttons: Array, value: int) -> Button:
	for button in buttons:
		if int(button.get_meta("value")) == value:
			return button
	return null

func _pressed_values(buttons: Array) -> Array:
	var values := []
	for button in buttons:
		if button.button_pressed:
			values.append(int(button.get_meta("value")))
	return values

## The part of a control that is actually visible: clipped by every scroll
## container it sits in (so content scrolled under the footer is ignored).
func _visible_rect(control: Control) -> Rect2:
	var rect := control.get_global_rect()
	var node := control.get_parent()
	while node != null:
		if node is ScrollContainer:
			rect = rect.intersection((node as Control).get_global_rect())
		node = node.get_parent()
	return rect

## Any visible label whose text is cut to fewer lines than it needs, or a
## one-line label whose text is wider than the label (trimmed or clipped).
func _cut_text(root: Node) -> Array:
	var cut: Array = []
	for node in _find_all(root, "Label"):
		var label: Label = node
		if not label.is_visible_in_tree() or label.text.is_empty():
			continue
		if label.get_visible_line_count() < label.get_line_count():
			cut.append("'%s' %d/%d lines" % [label.text.left(30), label.get_visible_line_count(), label.get_line_count()])
		elif label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			var text := label.text.to_upper() if label.uppercase else label.text
			var width := label.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				label.get_theme_font_size("font_size")).x
			if width > label.size.x + 1.0:
				cut.append("'%s' %.0f > %.0f px" % [text.left(30), width, label.size.x])
	return cut

func _scrolls(screen: Control) -> bool:
	for node in _find_all(screen, "ScrollContainer"):
		var scroll: ScrollContainer = node
		if scroll.get_v_scroll_bar().max_value > scroll.size.y + 1.0:
			return true
	return false

func _describe(control: Control) -> String:
	if control is Button and control.has_meta("value"):
		return "%s(%s)" % [control.get_parent().name, str(control.get_meta("value"))]
	return str(control.name)

func _find_by_name(root: Node, node_name: String) -> Control:
	for node in _find_all(root, "Control"):
		if node.name == node_name:
			return node
	return null

## Every node of a type (by class name) under `root`, including `root`.
func _find_all(root: Node, type_name: String) -> Array:
	var found: Array = []
	if root == null:
		return found
	if root.is_class(type_name):
		found.append(root)
	for child in root.get_children():
		found.append_array(_find_all(child, type_name))
	return found

## inner sits inside outer, allowing a pixel of float slack.
func _within(inner: Rect2, outer: Rect2, slack: float = 1.0) -> bool:
	return inner.position.x >= outer.position.x - slack \
		and inner.position.y >= outer.position.y - slack \
		and inner.end.x <= outer.end.x + slack \
		and inner.end.y <= outer.end.y + slack
