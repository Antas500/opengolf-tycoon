extends HBoxContainer
class_name PlayerTab
## Persistent player navigation. Only the selected page participates in layout.
## "Play Course" combines the round sections — Practice Round, Play vs Pro and
## Tournament — and swaps to the aiming HUD while a round is in progress.
const TITLES = ["Play Course", "Edit Player", "Player Skills"]
## Page indices inside `pages`, matching the order of TITLES.
const PAGE_PLAY := 0
const PAGE_EDIT := 1
const PAGE_SKILLS := 2
## Meta flag for Play Course nodes that survive setup rebuilds.
const PERSISTENT_META := "player_tab_persistent"

var pages: Array[VBoxContainer] = []
var buttons: Array[Button] = []
var aim_page: VBoxContainer
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
	body.custom_minimum_size = Vector2(400, 190)
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
	aim_scroll = _make_scroll(body)
	aim_page = VBoxContainer.new()
	aim_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aim_page.add_theme_constant_override("separation", 6)
	aim_scroll.add_child(aim_page)
	select(0)

func _make_scroll(body: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	return scroll

func _make_page(body: Control) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 6)
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
	if not is_instance_valid(aim_scroll):
		return
	pages[PAGE_PLAY].visible = not playing
	aim_page.visible = playing
	aim_scroll.visible = selected == PAGE_PLAY and playing

func clear_page(index: int) -> VBoxContainer:
	for child in pages[index].get_children():
		pages[index].remove_child(child)
		child.queue_free()
	return pages[index]

func clear_aim_page() -> VBoxContainer:
	for child in aim_page.get_children():
		aim_page.remove_child(child)
		child.queue_free()
	return aim_page

## Empty the Play Course page of round-setup content, keeping nodes added via
## add_persistent (the management tournament panel).
func clear_play_page() -> VBoxContainer:
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

## Move persistent nodes (the tournament panel) to the bottom of the Play
## Course page so its start button lands right below them.
func restage_persistent() -> void:
	var page := pages[PAGE_PLAY]
	for child in page.get_children():
		if child.has_meta(PERSISTENT_META):
			page.move_child(child, page.get_child_count() - 1)
