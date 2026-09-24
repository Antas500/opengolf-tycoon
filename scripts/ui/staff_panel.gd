extends HBoxContainer
class_name StaffPanel
## StaffPanel - Inline staff management UI for the toolbar Staff tab.
##
## Shows course condition, payroll, hire buttons for the 4 staff types,
## a roster of hired staff with fire buttons, and current effects.
## Lives in the tabbed toolbar rather than a separate popup window.

const HIRE_BUTTON_SIZE := Vector2(158, 28)
const FIRE_BUTTON_SIZE := Vector2(40, 24)

var _condition_bar: ProgressBar = null
var _condition_label: Label = null
var _payroll_label: Label = null
var _staff_list_container: HBoxContainer = null
var _pace_label: Label = null
var _cart_label: Label = null
var _pro_shop_label: Label = null
var _hire_buttons: Dictionary = {}  # StaffType -> Button
var _bar_fill_style: StyleBoxFlat = null

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alignment = BoxContainer.ALIGNMENT_BEGIN
	_build_ui()
	_connect_manager()
	_update_display()

func refresh() -> void:
	_connect_manager()
	_update_display()

func _exit_tree() -> void:
	var sm = _staff_manager()
	if sm == null:
		return
	if sm.staff_changed.is_connected(_on_staff_changed):
		sm.staff_changed.disconnect(_on_staff_changed)
	if sm.condition_changed.is_connected(_on_condition_changed):
		sm.condition_changed.disconnect(_on_condition_changed)

func _build_ui() -> void:
	add_child(_make_condition_group())
	add_child(_make_separator())
	add_child(_make_hire_group())
	add_child(_make_separator())
	add_child(_make_roster_group())
	add_child(_make_separator())
	add_child(_make_effects_group())

func _make_condition_group() -> VBoxContainer:
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.alignment = BoxContainer.ALIGNMENT_CENTER

	var bar_row = HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 6)
	bar_row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(bar_row)

	_condition_bar = ProgressBar.new()
	_condition_bar.min_value = 0
	_condition_bar.max_value = 100
	_condition_bar.value = 100
	_condition_bar.show_percentage = false
	_condition_bar.custom_minimum_size = Vector2(110, 16)
	_condition_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_condition_bar.tooltip_text = "Course condition. Groundskeepers restore it; it degrades without them."
	var bar_bg = StyleBoxFlat.new()
	bar_bg.bg_color = UIConstants.COLOR_BG_DARK
	bar_bg.set_corner_radius_all(3)
	_condition_bar.add_theme_stylebox_override("background", bar_bg)
	_bar_fill_style = StyleBoxFlat.new()
	_bar_fill_style.bg_color = UIConstants.COLOR_SUCCESS
	_bar_fill_style.set_corner_radius_all(3)
	_condition_bar.add_theme_stylebox_override("fill", _bar_fill_style)
	bar_row.add_child(_condition_bar)

	_condition_label = Label.new()
	_condition_label.text = "100%  Pristine"
	_condition_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	_condition_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT)
	_condition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar_row.add_child(_condition_label)

	_payroll_label = Label.new()
	_payroll_label.text = "Daily Payroll: $0"
	_payroll_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	_payroll_label.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
	content.add_child(_payroll_label)

	return _make_group("CONDITION", content)

func _make_hire_group() -> VBoxContainer:
	var hire_grid = GridContainer.new()
	hire_grid.columns = 2
	hire_grid.add_theme_constant_override("h_separation", 6)
	hire_grid.add_theme_constant_override("v_separation", 4)
	hire_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_add_hire_button(hire_grid, StaffManager.StaffType.GROUNDSKEEPER)
	_add_hire_button(hire_grid, StaffManager.StaffType.MARSHAL)
	_add_hire_button(hire_grid, StaffManager.StaffType.CART_OPERATOR)
	_add_hire_button(hire_grid, StaffManager.StaffType.PRO_SHOP)

	return _make_group("HIRE STAFF", hire_grid)

func _make_roster_group() -> VBoxContainer:
	_staff_list_container = HBoxContainer.new()
	_staff_list_container.add_theme_constant_override("separation", 8)
	_staff_list_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_staff_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_staff_list_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	var group = _make_group("CURRENT STAFF", _staff_list_container)
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return group

func _make_effects_group() -> VBoxContainer:
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.alignment = BoxContainer.ALIGNMENT_CENTER

	_pace_label = _make_effect_label("Pace: 60%")
	_cart_label = _make_effect_label("Carts: 70%")
	_pro_shop_label = _make_effect_label("Pro Shop: +$0/golfer")
	content.add_child(_pace_label)
	content.add_child(_cart_label)
	content.add_child(_pro_shop_label)

	return _make_group("EFFECTS", content)

func _make_effect_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	label.add_theme_color_override("font_color", UIConstants.COLOR_INFO_DIM)
	return label

func _make_group(title: String, content: Control) -> VBoxContainer:
	var group = VBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	group.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var lbl = Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	lbl.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	group.add_child(lbl)

	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	group.add_child(content)
	return group

func _make_separator() -> VSeparator:
	var sep = VSeparator.new()
	sep.custom_minimum_size = Vector2(1, 28)
	sep.modulate = Color(1, 1, 1, 0.2)
	return sep

func _add_hire_button(parent: GridContainer, staff_type: int) -> void:
	var data = StaffManager.STAFF_DATA.get(staff_type, {})
	var btn = Button.new()
	btn.text = _hire_button_text(staff_type, 0)
	btn.tooltip_text = data.get("description", "")
	btn.custom_minimum_size = HIRE_BUTTON_SIZE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	btn.pressed.connect(_on_hire_pressed.bind(staff_type))
	parent.add_child(btn)
	_hire_buttons[staff_type] = btn

func _hire_button_text(staff_type: int, hired_count: int) -> String:
	var data = StaffManager.STAFF_DATA.get(staff_type, {})
	var name_str: String = data.get("name", "Staff")
	var salary: int = data.get("base_salary", 50)
	if hired_count > 0:
		return "+ %s $%d  ×%d" % [name_str, salary, hired_count]
	return "+ %s $%d" % [name_str, salary]

func _connect_manager() -> void:
	var sm = _staff_manager()
	if sm == null:
		return
	if not sm.staff_changed.is_connected(_on_staff_changed):
		sm.staff_changed.connect(_on_staff_changed)
	if not sm.condition_changed.is_connected(_on_condition_changed):
		sm.condition_changed.connect(_on_condition_changed)

func _staff_manager() -> StaffManager:
	if GameManager == null:
		return null
	return GameManager.staff_manager

func _on_staff_changed() -> void:
	_update_display()

func _on_condition_changed(_new_condition: float) -> void:
	_update_status()

func _update_display() -> void:
	_update_status()
	_rebuild_roster()

func _update_status() -> void:
	if _condition_bar == null:
		return

	var sm = _staff_manager()
	var condition: float = sm.course_condition if sm else 1.0
	var condition_pct := condition * 100.0
	_condition_bar.value = condition_pct

	if condition >= 0.7:
		_bar_fill_style.bg_color = UIConstants.COLOR_SUCCESS
	elif condition >= 0.5:
		_bar_fill_style.bg_color = UIConstants.COLOR_WARNING
	else:
		_bar_fill_style.bg_color = UIConstants.COLOR_DANGER

	var description := sm.get_condition_description() if sm else "Pristine"
	_condition_label.text = "%d%%  %s" % [int(condition_pct), description]
	_condition_bar.tooltip_text = "Course condition: %d%% (%s). Groundskeepers restore it; it degrades without them." % [
		int(condition_pct), description
	]

	var payroll: int = sm.get_daily_payroll() if sm else 0
	_payroll_label.text = "Daily Payroll: $%d" % payroll

	var pace_pct: int = int((sm.get_pace_modifier() if sm else 0.6) * 100)
	var cart_pct: int = int((sm.get_cart_modifier() if sm else 0.7) * 100)
	var pro_bonus: int = int(sm.get_pro_shop_revenue_bonus() if sm else 0)
	_pace_label.text = "Pace: %d%%" % pace_pct
	_cart_label.text = "Carts: %d%%" % cart_pct
	_pro_shop_label.text = "Pro Shop: +$%d/golfer" % pro_bonus

	for staff_type in _hire_buttons:
		var count := sm.get_staff_count_by_type(staff_type) if sm else 0
		_hire_buttons[staff_type].text = _hire_button_text(staff_type, count)

func _rebuild_roster() -> void:
	if _staff_list_container == null:
		return

	for child in _staff_list_container.get_children():
		_staff_list_container.remove_child(child)
		child.queue_free()

	var sm = _staff_manager()
	if sm == null or sm.hired_staff.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No staff hired"
		empty_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
		empty_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_staff_list_container.add_child(empty_label)
		return

	for i in range(sm.hired_staff.size()):
		_add_staff_row(i, sm.hired_staff[i])

func _add_staff_row(index: int, staff: Dictionary) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_staff_list_container.add_child(row)

	var type_data = StaffManager.STAFF_DATA.get(staff.type, {})
	var type_name: String = type_data.get("name", "Staff")
	var staff_name: String = staff.get("name", "Unknown")

	var info_label = Label.new()
	info_label.text = "%s (%s) $%d" % [staff_name, type_name, staff.salary]
	info_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	info_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT)
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(info_label)

	var fire_btn = Button.new()
	fire_btn.text = "Fire"
	fire_btn.custom_minimum_size = FIRE_BUTTON_SIZE
	fire_btn.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	fire_btn.tooltip_text = "Fire %s" % staff_name
	fire_btn.pressed.connect(_on_fire_pressed.bind(index))
	row.add_child(fire_btn)

func _on_hire_pressed(staff_type: int) -> void:
	var sm = _staff_manager()
	if sm:
		sm.hire_staff(staff_type)

func _on_fire_pressed(index: int) -> void:
	var sm = _staff_manager()
	if sm:
		sm.fire_staff(index)
