extends HBoxContainer
class_name StaffPanel
## StaffPanel - Inline staff management UI for the toolbar Staff tab.
##
## Two sections only:
##   HIRE STAFF    - one standard and one premium button per job type. The
##                   premium hire costs more but covers a bigger area, moves
##                   faster and works faster.
##   CURRENT STAFF - the roster: pay, weeds on the course, then one row per
##                   employee with a Move Area button and a Fire button.

## Emitted when the player asks to reposition a staff member's designated area.
## main.gd turns this into a click-on-the-course mode.
signal area_move_requested(staff_index: int)

const HIRE_BUTTON_SIZE := Vector2(150, 26)
const ROW_BUTTON_SIZE := Vector2(58, 22)
const FIRE_BUTTON_SIZE := Vector2(44, 22)

var _hire_buttons: Dictionary = {}       # StaffType -> Button
var _area_buttons: Array[Button] = []
var _payroll_label: Label = null
var _weed_label: Label = null
var _roster_container: VBoxContainer = null
var _area_mode_index: int = -1

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

## Highlight the row whose area is currently being repositioned.
func set_area_mode_index(index: int) -> void:
	_area_mode_index = index
	_update_area_buttons()

func _exit_tree() -> void:
	var sm = _staff_manager()
	if sm == null:
		return
	if sm.staff_changed.is_connected(_on_staff_changed):
		sm.staff_changed.disconnect(_on_staff_changed)
	if sm.condition_changed.is_connected(_on_condition_changed):
		sm.condition_changed.disconnect(_on_condition_changed)
	var weeds = _weed_manager()
	if weeds and weeds.weeds_changed.is_connected(_on_staff_changed):
		weeds.weeds_changed.disconnect(_on_staff_changed)

func _build_ui() -> void:
	add_child(_make_hire_group())
	add_child(_make_separator())
	add_child(_make_roster_group())

# --- Hire Staff --------------------------------------------------------------

func _make_hire_group() -> VBoxContainer:
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 3)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Header row
	grid.add_child(_make_header_label("Job"))
	grid.add_child(_make_header_label("Standard"))
	grid.add_child(_make_header_label("Premium"))

	for job in [
		StaffManager.Job.GROUNDSKEEPER,
		StaffManager.Job.GREETER,
		StaffManager.Job.MARSHAL,
		StaffManager.Job.DRINKS_VENDOR,
	]:
		var job_data: Dictionary = StaffManager.JOB_DATA.get(job, {})
		var job_label = Label.new()
		job_label.text = job_data.get("name", "Staff")
		job_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
		job_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT)
		job_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		job_label.tooltip_text = "%s — %s" % [job_data.get("name", "Staff"), job_data.get("action", "")]
		grid.add_child(job_label)
		_add_hire_button(grid, int(job_data.get("standard", 0)))
		_add_hire_button(grid, int(job_data.get("premium", 0)))

	return _make_group("HIRE STAFF", grid)

func _make_header_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	return label

func _add_hire_button(parent: GridContainer, staff_type: int) -> void:
	var data = StaffManager.STAFF_DATA.get(staff_type, {})
	if data.is_empty():
		return
	var btn = Button.new()
	btn.text = _hire_button_text(staff_type, 0)
	btn.tooltip_text = "%s — %s\nArea radius %.0f tiles · moves at %.0f · works %.1fx faster" % [
		data.get("name", "Staff"),
		data.get("description", ""),
		data.get("area_radius", 0.0),
		data.get("move_speed", 0.0),
		data.get("work_speed", 1.0),
	]
	btn.custom_minimum_size = HIRE_BUTTON_SIZE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	btn.pressed.connect(_on_hire_pressed.bind(staff_type))
	parent.add_child(btn)
	_hire_buttons[staff_type] = btn

func _hire_button_text(staff_type: int, hired_count: int) -> String:
	var data = StaffManager.STAFF_DATA.get(staff_type, {})
	var name_str: String = data.get("name", "Staff")
	var salary: int = int(data.get("base_salary", 0))
	if hired_count > 0:
		return "%s $%d  ×%d" % [name_str, salary, hired_count]
	return "%s $%d" % [name_str, salary]

# --- Current Staff -----------------------------------------------------------

func _make_roster_group() -> VBoxContainer:
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 3)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var status = HBoxContainer.new()
	status.add_theme_constant_override("separation", 10)
	_payroll_label = Label.new()
	_payroll_label.text = "Daily Payroll: $0"
	_payroll_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	_payroll_label.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
	status.add_child(_payroll_label)

	_weed_label = Label.new()
	_weed_label.text = "Weeds: 0"
	_weed_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	_weed_label.add_theme_color_override("font_color", UIConstants.COLOR_INFO_DIM)
	_weed_label.tooltip_text = "Weeds on the course. Groundskeepers pull them during play; weeds left over lower course condition."
	status.add_child(_weed_label)
	content.add_child(status)

	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.custom_minimum_size = Vector2(270, 108)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_container = VBoxContainer.new()
	_roster_container.add_theme_constant_override("separation", 3)
	_roster_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_roster_container)
	content.add_child(scroll)

	var group = _make_group("CURRENT STAFF", content)
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return group

func _rebuild_roster() -> void:
	if _roster_container == null:
		return
	_area_buttons.clear()
	for child in _roster_container.get_children():
		_roster_container.remove_child(child)
		child.queue_free()

	var sm = _staff_manager()
	if sm == null or sm.hired_staff.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No staff hired"
		empty_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
		empty_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_roster_container.add_child(empty_label)
		_area_mode_index = -1
		return

	for i in range(sm.hired_staff.size()):
		_add_staff_row(i, sm.hired_staff[i])

func _add_staff_row(index: int, staff: Dictionary) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_roster_container.add_child(row)

	var type_data = StaffManager.STAFF_DATA.get(int(staff.type), {})
	var type_name: String = type_data.get("name", "Staff")
	var staff_name: String = staff.get("name", "Unknown")
	var radius: float = float(staff.get("area_radius", 0.0))

	var info_label = Label.new()
	info_label.text = "%s · %s · $%d" % [staff_name, type_name, int(staff.salary)]
	info_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	info_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT)
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.tooltip_text = "%s\nDesignated area: %.0f tiles around %s" % [
		type_data.get("description", ""), radius, str(staff.get("area_center", Vector2i.ZERO))
	]
	row.add_child(info_label)

	var area_btn = Button.new()
	area_btn.text = "Area"
	area_btn.custom_minimum_size = ROW_BUTTON_SIZE
	area_btn.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	area_btn.tooltip_text = "Move %s's designated area: click a tile on the course." % staff_name
	area_btn.pressed.connect(_on_area_pressed.bind(index))
	row.add_child(area_btn)
	_area_buttons.append(area_btn)

	var fire_btn = Button.new()
	fire_btn.text = "Fire"
	fire_btn.custom_minimum_size = FIRE_BUTTON_SIZE
	fire_btn.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	fire_btn.tooltip_text = "Fire %s" % staff_name
	fire_btn.pressed.connect(_on_fire_pressed.bind(index))
	row.add_child(fire_btn)

	_update_area_button(area_btn, index)

func _update_area_buttons() -> void:
	for i in range(_area_buttons.size()):
		_update_area_button(_area_buttons[i], i)

func _update_area_button(button: Button, index: int) -> void:
	if button == null:
		return
	if index == _area_mode_index:
		button.text = "Pick…"
		button.modulate = UIConstants.COLOR_GOLD
	else:
		button.text = "Area"
		button.modulate = Color.WHITE

# --- Shared helpers ----------------------------------------------------------

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

func _connect_manager() -> void:
	var sm = _staff_manager()
	if sm:
		if not sm.staff_changed.is_connected(_on_staff_changed):
			sm.staff_changed.connect(_on_staff_changed)
		if not sm.condition_changed.is_connected(_on_condition_changed):
			sm.condition_changed.connect(_on_condition_changed)
	var weeds = _weed_manager()
	if weeds and not weeds.weeds_changed.is_connected(_on_staff_changed):
		weeds.weeds_changed.connect(_on_staff_changed)

func _staff_manager() -> StaffManager:
	if GameManager == null:
		return null
	return GameManager.staff_manager

func _weed_manager() -> WeedManager:
	if GameManager == null:
		return null
	return GameManager.weed_manager

func _on_staff_changed() -> void:
	_update_display()

func _on_condition_changed(_new_condition: float) -> void:
	_update_status()

func _update_display() -> void:
	_update_status()
	_rebuild_roster()

func _update_status() -> void:
	var sm = _staff_manager()
	var payroll: int = sm.get_daily_payroll() if sm else 0
	if _payroll_label:
		_payroll_label.text = "Daily Payroll: $%d" % payroll
	if _weed_label:
		var weeds: int = sm.get_weed_count() if sm else 0
		_weed_label.text = "Weeds: %d" % weeds
		_weed_label.add_theme_color_override("font_color",
			UIConstants.COLOR_DANGER if weeds > 4 else UIConstants.COLOR_INFO_DIM)

	for staff_type in _hire_buttons:
		var count := sm.get_staff_count_by_type(staff_type) if sm else 0
		_hire_buttons[staff_type].text = _hire_button_text(staff_type, count)

func _on_hire_pressed(staff_type: int) -> void:
	var sm = _staff_manager()
	if sm:
		sm.hire_staff(staff_type)

func _on_fire_pressed(index: int) -> void:
	var sm = _staff_manager()
	if sm:
		sm.fire_staff(index)

func _on_area_pressed(index: int) -> void:
	# Toggle off if the same row was already waiting for a click.
	if _area_mode_index == index:
		_area_mode_index = -1
		_update_area_buttons()
		area_move_requested.emit(-1)
		return
	_area_mode_index = index
	_update_area_buttons()
	area_move_requested.emit(index)
