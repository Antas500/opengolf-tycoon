extends Control
class_name PauseMenu
## PauseMenu - Full-screen pause overlay with game options
##
## Triggered by Escape key. Provides Resume, Save, Load, Quit to Menu, and
## Quit to Desktop options. Dims the game behind it.
##
## The simulation is frozen while this menu is open, but the player can still
## look around the course: pointer events that land on the dimmed backdrop
## (not on the menu panel) are forwarded to the isometric camera, which runs
## on wall-clock time.

signal resume_requested
signal save_requested
signal load_requested
signal settings_requested
signal quit_to_menu_requested
signal quit_to_desktop_requested

## Set by Main so camera controls work while the game is paused behind the
## menu. Null when the camera is unavailable (forwarding is then skipped).
var camera: IsometricCamera = null

var _bg: ColorRect = null
var _panel: PanelContainer = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()

func _build_ui() -> void:
	# Semi-transparent dark overlay
	var bg = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_bg = bg
	add_child(bg)

	# Center container for the menu panel
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Menu panel
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.1, 0.95)
	style.border_color = UIConstants.COLOR_PRIMARY
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(320, 0)
	_panel = panel
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Game Paused"
	title.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XL)
	title.add_theme_color_override("font_color", Color(0.85, 0.95, 0.75))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Separator
	vbox.add_child(HSeparator.new())

	# Course info
	var info_label = Label.new()
	info_label.text = "%s - Day %d" % [GameManager.course_name, GameManager.current_day]
	info_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	info_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	# Menu buttons
	_add_menu_button(vbox, "Resume", _on_resume_pressed)
	_add_menu_button(vbox, "Save Game", _on_save_pressed)
	_add_menu_button(vbox, "Load Game", _on_load_pressed)
	_add_menu_button(vbox, "Settings", _on_settings_pressed)

	# Separator before destructive actions
	vbox.add_child(HSeparator.new())

	_add_menu_button(vbox, "Quit to Menu", _on_quit_to_menu_pressed, UIConstants.COLOR_WARNING)
	_add_menu_button(vbox, "Quit to Desktop", _on_quit_to_desktop_pressed, UIConstants.COLOR_DANGER)

	# Hint at bottom
	var hint = Label.new()
	hint.text = "Look around while paused: middle-mouse drag or WASD to pan, scroll to zoom\nPress Escape to resume"
	hint.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	hint.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

func _add_menu_button(parent: VBoxContainer, text: String, callback: Callable, text_color: Color = Color.WHITE) -> void:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(260, 40)
	btn.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_MD)
	if text_color != Color.WHITE:
		btn.add_theme_color_override("font_color", text_color)
	btn.pressed.connect(callback)
	parent.add_child(btn)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_resume_pressed()
			get_viewport().set_input_as_handled()
		return

	# The game is paused behind this menu, but the player should still be
	# able to look around the course. This overlay is full-screen with
	# MOUSE_FILTER_STOP, so pointer events never reach the camera's
	# _unhandled_input — forward the ones that are over the dimmed backdrop
	# (not over the menu panel) to the camera instead.
	if camera != null and _is_camera_event(event):
		camera.handle_input_event(event, true)

## True when a pointer event should be forwarded to the camera: the pointer
## is over the dimmed backdrop rather than an interactive part of the menu,
## or the camera is already mid-drag (so the drag keeps flowing — including
## the release — even if the pointer moves over the panel).
func _is_camera_event(event: InputEvent) -> bool:
	if event is InputEventMagnifyGesture:
		return _hover_is_backdrop()
	if event is InputEventMouseMotion:
		return camera.is_dragging() or _hover_is_backdrop()
	if event is InputEventMouseButton:
		if camera.is_dragging():
			return true
		if not _hover_is_backdrop():
			return false
		return event.button_index == MOUSE_BUTTON_MIDDLE \
			or event.button_index == MOUSE_BUTTON_WHEEL_UP \
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN
	return false

func _hover_is_backdrop() -> bool:
	var hovered := _get_hovered_control()
	if hovered == null:
		return false
	return not _is_inside_panel(hovered)

## The control under the pointer. Split out so tests can simulate hover
## state (headless runs have no real mouse, so the viewport never reports a
## hovered control).
func _get_hovered_control() -> Control:
	return get_viewport().gui_get_hovered_control()

func _is_inside_panel(control: Control) -> bool:
	var node: Node = control
	while node != null and node != self:
		if node == _panel:
			return true
		node = node.get_parent()
	return false

func _on_resume_pressed() -> void:
	resume_requested.emit()

func _on_save_pressed() -> void:
	save_requested.emit()

func _on_load_pressed() -> void:
	load_requested.emit()

func _on_settings_pressed() -> void:
	settings_requested.emit()

func _on_quit_to_menu_pressed() -> void:
	quit_to_menu_requested.emit()

func _on_quit_to_desktop_pressed() -> void:
	quit_to_desktop_requested.emit()
