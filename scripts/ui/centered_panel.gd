extends PanelContainer
class_name CenteredPanel
## CenteredPanel - Base class for panels that center themselves on screen
##
## Provides consistent centering behavior with proper layout calculation.
## Subclasses should call show_centered() instead of show() to display centered.
##
## Responsive: the panel is clamped to the screen area available to popups
## (see Screen.available_panel_rect) so it never covers the bottom control
## bar or spills off a phone-sized window. If the clamped size is smaller
## than the content, the content is lazily wrapped in a ScrollContainer so
## the rest stays reachable.

var _natural_size: Vector2 = Vector2.ZERO
var _scroll_wrapper: ScrollContainer = null

func _ready() -> void:
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_build_ui()
	hide()
	# Re-center while open when the window is resized or rotated.
	if has_node("/root/Screen"):
		Screen.changed.connect(_on_screen_changed)

## Override this in subclasses to build the panel's UI
func _build_ui() -> void:
	pass

func _on_screen_changed(_size: Vector2, _world_scale: float) -> void:
	if visible:
		_layout_to_screen()

## Shows the panel centered on screen with proper layout calculation
func show_centered() -> void:
	# Position offscreen first to trigger layout calculation without visual flash
	position = Vector2(-1000, -1000)
	# Free positioning: some call sites set centered anchors, which would
	# fight the explicit position computed below.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	# Grow from the panel's own top-left corner (GROW_DIRECTION_BEGIN), not from
	# the opposite anchor: the position below is measured in that direction.
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	show()
	# Wait for layout engine to process children sizes
	await get_tree().process_frame
	_layout_to_screen()

## Size and place the panel within the responsive available rect.
func _layout_to_screen() -> void:
	var viewport_size := get_viewport().get_visible_rect().size

	# The content's natural size is measured once (before any scroll
	# wrapper shrinks the minimum size) and then only ever grown.
	var content_size := get_combined_minimum_size()
	if _natural_size == Vector2.ZERO:
		_natural_size = content_size
	else:
		_natural_size = _natural_size.max(content_size)

	if has_node("/root/Screen"):
		_natural_size = _natural_size.max(custom_minimum_size)
		var area := Screen.available_panel_rect()
		var clamped := _natural_size.clamp(Vector2.ZERO, area.size)

		# Content that no longer fits the clamped size becomes scrollable
		# (vertically and/or horizontally).
		if _natural_size.y > clamped.y + 1.0 or _natural_size.x > clamped.x + 1.0:
			_ensure_scrollable()
		if _scroll_wrapper != null:
			_scroll_wrapper.horizontal_scroll_mode = (
				ScrollContainer.SCROLL_MODE_AUTO if _natural_size.x > clamped.x + 1.0
				else ScrollContainer.SCROLL_MODE_DISABLED
			)

		size = clamped
		# A Control can never be laid out smaller than its minimum size, so
		# clamp the minimum too (the natural size stays cached for larger
		# windows).
		custom_minimum_size = clamped
		position = area.position + (area.size - clamped) / 2.0
	else:
		size = _natural_size
		position = (viewport_size - _natural_size) / 2.0

## Toggle visibility - shows centered when opening
func toggle() -> void:
	if visible:
		hide()
	else:
		show_centered()

## Wrap the single content child in a ScrollContainer so clamped panels
## keep their overflow reachable instead of clipping it.
func _ensure_scrollable() -> void:
	if _scroll_wrapper != null:
		return
	if get_child_count() != 1:
		return  # Only panels with one content child can be wrapped safely
	var child: Control = get_child(0)
	_scroll_wrapper = ScrollContainer.new()
	_scroll_wrapper.name = "ResponsiveScroll"
	_scroll_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_wrapper.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	remove_child(child)
	add_child(_scroll_wrapper)
	_scroll_wrapper.add_child(child)
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
