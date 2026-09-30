extends HBoxContainer
class_name PlayerTab
## Persistent player navigation. Only the selected page participates in layout.
## "Play Course" combines the round sections — Practice Round, Play vs Pro and
## Tournament — and swaps to the aiming HUD (the shot controls) while a round is
## in progress. Scores are not part of it: they read out in the HUD's top-left
## corner (ScoresDock), over the course view.
const TITLES = ["Play Course", "Edit Player", "Player Skills"]
## Page indices inside `pages`, matching the order of TITLES.
const PAGE_PLAY := 0
const PAGE_EDIT := 1
const PAGE_SKILLS := 2
## Meta flag for Play Course nodes that survive setup rebuilds.
const PERSISTENT_META := "player_tab_persistent"

var pages: Array[HBoxContainer] = []
var buttons: Array[Button] = []
## The aiming view for a round in progress: the shot-type row pinned along the
## top, with the scrolling control columns under it.
var aim_view: VBoxContainer
## One button per shot type, running along the top of the Play Course page.
var shot_bar: ShotTypeBar
var aim_page: HBoxContainer
var aim_scroll: ScrollContainer
var selected := 0
var playing := false

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var navigation := VBoxContainer.new()
	navigation.custom_minimum_size.x = 140
	navigation.add_theme_constant_override("separation", 0)
	add_child(navigation)
	var group := ButtonGroup.new()
	var body := Control.new()
	# The toolbar supplies the available height, not a second full bottom bar.
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	for i in TITLES.size():
		var button := Button.new()
		button.text = TITLES[i]
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.pressed.connect(select.bind(i))
		navigation.add_child(button)
		buttons.append(button)
		pages.append(_make_page(body))
	# Alternate view for the Play Course page: the aiming HUD during a round.
	# The shot-type buttons run along its top; the control columns scroll under
	# them, so the whole shot set stays readable no matter how far the shelf
	# scrolls sideways.
	aim_view = VBoxContainer.new()
	aim_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	aim_view.add_theme_constant_override("separation", UIConstants.SEPARATION_MD)
	body.add_child(aim_view)
	shot_bar = ShotTypeBar.new()
	aim_view.add_child(shot_bar)
	aim_scroll = _make_scroll(aim_view, false)
	aim_page = HBoxContainer.new()
	aim_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aim_page.add_theme_constant_override("separation", 16)
	aim_scroll.add_child(aim_page)
	select(0)

## Full-rect scrolling shelf on the tab body, or a shelf that fills what the shot
## row leaves when it is stacked inside the aiming view.
func _make_scroll(parent: Control, fill_rect: bool = true) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	if fill_rect:
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.gui_input.connect(_on_scroll_gui_input.bind(scroll))
	parent.add_child(scroll)
	return scroll

func _make_page(body: Control) -> HBoxContainer:
	var page := HBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 16)
	_make_scroll(body).add_child(page)
	return page

func select(index: int) -> void:
	selected = index
	for i in pages.size():
		pages[i].get_parent().visible = i == index
		buttons[i].set_pressed_no_signal(i == index)
	_sync_aim_view()

## While playing, the Play Course page shows the aiming HUD instead of the
## combined round-setup sections.
func set_playing(value: bool) -> void:
	playing = value
	_sync_aim_view()

func _sync_aim_view() -> void:
	if not is_instance_valid(aim_view):
		return
	pages[PAGE_PLAY].get_parent().visible = selected == PAGE_PLAY and not playing
	pages[PAGE_PLAY].visible = not playing
	aim_view.visible = selected == PAGE_PLAY and playing
	aim_page.visible = playing
	aim_scroll.visible = selected == PAGE_PLAY and playing

func clear_page(index: int) -> HBoxContainer:
	for child in pages[index].get_children():
		pages[index].remove_child(child)
		child.queue_free()
	return pages[index]

## Empty the aiming page of round content. Scores are not part of it: they read
## out in the HUD's top-left corner (see ScoresDock), so everything the round put
## on this page is the shot controls and goes.
func clear_aim_page() -> HBoxContainer:
	for child in aim_page.get_children():
		aim_page.remove_child(child)
		child.queue_free()
	return aim_page

## Empty the Play Course page of round-setup content, keeping nodes added via
## add_persistent (the management tournament panel).
func clear_play_page() -> HBoxContainer:
	var page := pages[PAGE_PLAY]
	for child in page.get_children():
		if child.has_meta(PERSISTENT_META):
			continue
		page.remove_child(child)
		child.queue_free()
	return page

## Add a node that survives Play Course setup rebuilds.
func add_persistent(node: Node) -> void:
	node.set_meta(PERSISTENT_META, true)
	pages[PAGE_PLAY].add_child(node)

## Move persistent nodes (the management tournament panel) after the owner
## round choices. They share the same horizontal shelf.
func restage_persistent() -> void:
	var page := pages[PAGE_PLAY]
	for child in page.get_children():
		if child.has_meta(PERSISTENT_META):
			page.move_child(child, page.get_child_count() - 1)

## A short column on a horizontal shelf. Its width is stable so wrapped text
## cannot collapse when the viewport narrows; overflow belongs to the shelf.
static func add_column(shelf: HBoxContainer, width: float = 220) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = width
	column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	column.add_theme_constant_override("separation", 4)
	shelf.add_child(column)
	return column

func _on_scroll_gui_input(event: InputEvent, scroll: ScrollContainer) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll.scroll_horizontal = maxi(0, scroll.scroll_horizontal - 50)
			scroll.accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll.scroll_horizontal += 50
			scroll.accept_event()
