extends Node
## Run: godot --headless --path . res://tests/harness/main_menu_layout_harness.tscn
##
## Drives the real title screen through phone, tablet, rotated-phone and
## desktop window sizes and checks that each of the four arrangements (see
## MainMenu.layout_mode_for) places all six actions on screen, keeps them
## apart, and keeps them tappable. Also checks the two things the redesign is
## about: no tagline under the title any more, and a drawn backdrop behind the
## menu instead of a flat colour.
##
## Prints one PASS/FAIL line per check and exits non-zero on any failure.

var main: Node
var failures := 0

func _check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
	print("MAIN_MENU: %s: %s" % ["PASS" if ok else "FAIL", description])

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _set_window(width: int, height: int) -> void:
	get_window().size = Vector2i(width, height)
	await _frames(4)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# ------------------------------------------------------------------
	# Phone portrait: single scrollable column, big tap targets.
	# ------------------------------------------------------------------
	await _set_window(390, 844)
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await _frames(6)

	_check(main.main_menu != null, "the game opens on the title screen")
	_check(main.main_menu._layout_mode == MainMenu.Layout.PHONE,
		"390x844 uses the phone layout (got %d)" % main.main_menu._layout_mode)
	await _check_screen("phone portrait", 390.0, 844.0, 44.0)
	_check_continue_state("phone portrait")

	# ------------------------------------------------------------------
	# Rotated phone: wide and short, so nothing should need scrolling.
	# ------------------------------------------------------------------
	await _set_window(844, 390)
	_check(main.main_menu._layout_mode == MainMenu.Layout.LANDSCAPE,
		"844x390 uses the landscape layout (got %d)" % main.main_menu._layout_mode)
	await _check_screen("rotated phone", 844.0, 390.0, 40.0)
	_check(not _scrolls(main.main_menu), "rotated phone fits without scrolling")

	# ------------------------------------------------------------------
	# Tablet portrait and landscape: centred column, hero pair side by side.
	# ------------------------------------------------------------------
	await _set_window(768, 1024)
	_check(main.main_menu._layout_mode == MainMenu.Layout.TABLET,
		"768x1024 uses the tablet layout (got %d)" % main.main_menu._layout_mode)
	await _check_screen("tablet portrait", 768.0, 1024.0, 44.0)

	await _set_window(1024, 768)
	_check(main.main_menu._layout_mode == MainMenu.Layout.TABLET,
		"1024x768 uses the tablet layout (got %d)" % main.main_menu._layout_mode)
	await _check_screen("tablet", 1024.0, 768.0, 44.0)
	_check(not _scrolls(main.main_menu), "1024x768 tablet fits without scrolling")

	# ------------------------------------------------------------------
	# Desktop: the clubhouse split, with room used left and right.
	# ------------------------------------------------------------------
	await _set_window(1600, 1000)
	_check(main.main_menu._layout_mode == MainMenu.Layout.WIDE,
		"1600x1000 uses the wide layout (got %d)" % main.main_menu._layout_mode)
	await _check_screen("desktop", 1600.0, 1000.0, 44.0)
	_check(not _scrolls(main.main_menu), "desktop fits without scrolling")
	_check(_uses_side_space(main.main_menu, 1600.0),
		"desktop spreads the layout across the window instead of a centre strip")
	_check_continue_state("desktop")

	await _set_window(2560, 1440)
	_check(main.main_menu._layout_mode == MainMenu.Layout.WIDE,
		"2560x1440 uses the wide layout (got %d)" % main.main_menu._layout_mode)
	await _check_screen("large desktop", 2560.0, 1440.0, 44.0)

	# ------------------------------------------------------------------
	# Back to the phone: the layout must come back, and no tagline.
	# ------------------------------------------------------------------
	await _set_window(390, 844)
	await _frames(4)
	_check(main.main_menu._layout_mode == MainMenu.Layout.PHONE,
		"the phone layout returns when the window shrinks back")
	await _check_screen("phone portrait (again)", 390.0, 844.0, 44.0)
	_check(not _has_tagline(main.main_menu),
		"no tagline sits under the title any more")
	_check(_backdrop(main.main_menu) != null, "a drawn backdrop sits behind the menu")

	print("MAIN_MENU: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)

## Everything that has to hold for the six actions at one window size.
func _check_screen(tag: String, width: float, height: float, min_height: float) -> void:
	var menu: Control = main.main_menu
	var buttons: Array = _find_buttons(menu)
	_check(buttons.size() == 6, "%s: six actions (got %d)" % [tag, buttons.size()])

	var labels: Array = []
	for button in buttons:
		labels.append(button.text)
	for expected in ["Start New Game", "Quick Start", "Continue", "Load Game", "Settings", "Quit"]:
		_check(expected in labels, "%s: has a %s action" % [tag, expected])

	var view := Rect2(0.0, 0.0, width, height)
	var too_small: Array = []
	var off_screen: Array = []
	for button in buttons:
		var rect: Rect2 = button.get_global_rect()
		if rect.size.y < min_height - 0.5 or rect.size.x < 60.0:
			too_small.append("%s %s" % [button.text, rect.size])
		if not _within(rect, view):
			off_screen.append("%s %s" % [button.text, rect])
	_check(too_small.is_empty(), "%s: every action is a big enough target (%s)" % [tag, too_small])
	_check(off_screen.is_empty(), "%s: every action is on screen (%s)" % [tag, off_screen])

	var overlaps: Array = []
	for i in buttons.size():
		for j in range(i + 1, buttons.size()):
			var a: Rect2 = buttons[i].get_global_rect()
			var b: Rect2 = buttons[j].get_global_rect()
			if a.intersects(b, false):
				overlaps.append("%s / %s" % [buttons[i].text, buttons[j].text])
	_check(overlaps.is_empty(), "%s: actions do not overlap (%s)" % [tag, overlaps])

	# The title has to be on screen too, and the scenery behind everything.
	var title := _find_label(menu, "Title")
	_check(title != null and _within(title.get_global_rect(), view),
		"%s: the title is on screen" % tag)
	var backdrop := _backdrop(menu)
	_check(backdrop != null and backdrop.get_global_rect().size == Vector2(width, height),
		"%s: the backdrop covers the window" % tag)

## The Continue card carries the newest save's course name and day when there
## is one; with no saves it is disabled and says so. Either way the Continue
## label itself stays the button's text.
func _check_continue_state(tag: String) -> void:
	var continue_button: Button = main.main_menu._continue_button
	var saves = SaveManager.get_save_list()
	_check(continue_button != null, "%s: the Continue card exists" % tag)
	if continue_button == null:
		return
	if saves.is_empty():
		_check(continue_button.disabled, "%s: Continue is disabled with no saves" % tag)
		_check("No saved" in continue_button.tooltip_text,
			"%s: Continue explains why it is disabled" % tag)
	else:
		_check(not continue_button.disabled, "%s: Continue is live with a save on file" % tag)
		var caption: Label = _find_label(continue_button, "Caption")
		_check(caption != null and str(saves[0].get("course_name", "")) in caption.text,
			"%s: Continue names the newest course" % tag)

## Any ScrollContainer in the menu whose content is taller than its viewport.
func _scrolls(menu: Control) -> bool:
	for node in _find_all(menu, "ScrollContainer"):
		var scroll: ScrollContainer = node
		if scroll.get_v_scroll_bar().max_value > scroll.size.y + 1.0:
			return true
	return false

## On a wide window the six actions should not be a narrow centre strip: the
## leftmost and rightmost actions have to be far apart.
func _uses_side_space(menu: Control, width: float) -> bool:
	var buttons: Array = _find_buttons(menu)
	if buttons.is_empty():
		return false
	var left := INF
	var right := -INF
	for button in buttons:
		var rect: Rect2 = button.get_global_rect()
		left = minf(left, rect.position.x)
		right = maxf(right, rect.end.x)
	return (right - left) >= width * 0.6

## The old menu's "Design. Build. Manage." tagline: any label whose text is
## neither the title, the status line, a card caption nor a kicker.
func _has_tagline(menu: Control) -> bool:
	for node in _find_all(menu, "Label"):
		var label: Label = node
		if label.text.strip_edges() == "Design. Build. Manage.":
			return true
	return false

func _backdrop(menu: Control) -> Control:
	var node := menu.get_node_or_null("Backdrop")
	return node as Control if node is Control else null

func _find_label(root: Node, node_name: String) -> Label:
	for node in _find_all(root, "Label"):
		if node.name == node_name:
			return node
	return null

## Every node of a type (by class name) under `root`, including `root`.
func _find_all(root: Node, type_name: String) -> Array:
	var found: Array = []
	if root.is_class(type_name):
		found.append(root)
	for child in root.get_children():
		found.append_array(_find_all(child, type_name))
	return found

func _find_buttons(node: Node) -> Array:
	var found: Array = []
	if node == null:
		return found
	if node is Button:
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_buttons(child))
	return found

## inner sits inside outer, allowing a pixel of float slack.
func _within(inner: Rect2, outer: Rect2, slack: float = 1.0) -> bool:
	return inner.position.x >= outer.position.x - slack \
		and inner.position.y >= outer.position.y - slack \
		and inner.end.x <= outer.end.x + slack \
		and inner.end.y <= outer.end.y + slack
