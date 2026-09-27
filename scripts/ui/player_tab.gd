extends HBoxContainer
class_name PlayerTab
## Persistent player navigation. Only the selected page participates in layout.
const TITLES = ["Aiming Shot", "Edit Player", "Player Skills", "Practice Round", "Play vs Pro", "Tournament"]
var pages: Array[VBoxContainer] = []
var buttons: Array[Button] = []
var selected := 0

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
		var scroll := ScrollContainer.new()
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body.add_child(scroll)
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 6)
		scroll.add_child(page)
		pages.append(page)
	select(0)

func select(index: int) -> void:
	selected = index
	for i in pages.size():
		pages[i].get_parent().visible = i == index
		buttons[i].set_pressed_no_signal(i == index)

func clear_page(index: int) -> VBoxContainer:
	for child in pages[index].get_children():
		pages[index].remove_child(child)
		child.queue_free()
	return pages[index]
