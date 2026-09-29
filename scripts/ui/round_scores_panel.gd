extends PanelContainer
class_name RoundScoresPanel
## Scores for the owner's round, docked to the top-left corner of the HUD.
##
## Practice rounds, matches against a pro and tournaments used to print their
## scores inside the Player tab's Play Course page, squeezed in beside the shot
## controls in the bottom bar. Those controls stay on the bar; the scores read
## out here, where the golfer can see them without leaving the course view.
##
## The card stays small on purpose: a title, one status line (the winner on a
## finished card), and a body that fits its content up to `MAX_BODY_HEIGHT` and
## scrolls beyond that. Live rows are refreshed in place, so a round can update
## its scores every frame without rebuilding the card.

const PANEL_WIDTH := 300.0
## Tallest the score body grows before it scrolls inside the card.
const MAX_BODY_HEIGHT := 180.0

var title_label: Label
var status_label: Label
var body: VBoxContainer

var _scroll: ScrollContainer
## Names of the rows currently in the body, so `set_scores()` can refresh the
## values in place instead of rebuilding labels each frame. Colors are cached
## with them so an unchanged score writes nothing at all.
var _row_names: Array[String] = []
var _row_values: Array[Label] = []
var _row_colors: Array[Color] = []

func _ready() -> void:
	_build_ui()
	hide()

func _build_ui() -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# Clicks on the card must not reach the course: during a round a click is a
	# shot, and the scorecard sits over the top-left corner of the course view.
	mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(UIConstants.COLOR_BG_DARK, 0.92)
	style.set_border_width_all(2)
	style.border_color = UIConstants.COLOR_BORDER
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	title_label = Label.new()
	title_label.text = "Round"
	title_label.add_theme_font_size_override("font_size", 13)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(title_label)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	status_label.visible = false
	vbox.add_child(status_label)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(_scroll)

	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(body)

## Start the readout for a round: title the card, drop whatever the last one
## left behind and show it in the top-left corner.
func begin(title: String, status: String = "") -> void:
	if is_instance_valid(title_label):
		title_label.text = title
	set_status(status)
	clear_body()
	show()

## The line under the title — empty hides it. Carries the round result once the
## card is finished.
func set_status(text: String) -> void:
	if not is_instance_valid(status_label):
		return
	status_label.text = text
	status_label.visible = not text.is_empty()

## One row per player, refreshed in place while scores change. Each entry is
## `{"name": String, "value": String, "color": Color}`; missing colors fall back
## to plain text and dim values.
func set_scores(rows: Array) -> void:
	if _rows_match(rows):
		for i in rows.size():
			var value: Label = _row_values[i]
			var text := str(_row_field(rows[i], "value"))
			if value.text != text:
				value.text = text
			var color: Color = _row_field(rows[i], "color", UIConstants.COLOR_TEXT)
			if _row_colors[i] != color:
				_row_colors[i] = color
				value.add_theme_color_override("font_color", color)
		return
	clear_body()
	for row in rows:
		_add_score_row(str(_row_field(row, "name")), str(_row_field(row, "value")),
			_row_field(row, "color", UIConstants.COLOR_TEXT))
	_fit_body.call_deferred()

## The live score rows the card is showing right now, as
## `[{"name": String, "value": String}]` in card order.
func score_rows() -> Array:
	var rows: Array = []
	for i in _row_names.size():
		var value := ""
		if is_instance_valid(_row_values[i]):
			value = _row_values[i].text
		rows.append({"name": _row_names[i], "value": value})
	return rows

## Empty the score body, whether it holds the live table or a finished card.
func clear_body() -> void:
	if not is_instance_valid(body):
		return
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	_row_names.clear()
	_row_values.clear()
	_row_colors.clear()
	_fit_body.call_deferred()

## A plain line in the body, e.g. one hole of a finished scorecard.
func add_line(text: String, color: Color = UIConstants.COLOR_TEXT) -> Label:
	return _add_body_label(text, UIConstants.FONT_SIZE_SM, color)

## A heading above one golfer's lines at the end of a round.
func add_heading(text: String, color: Color = UIConstants.COLOR_GOLD) -> Label:
	return _add_body_label(text, UIConstants.FONT_SIZE_BASE, color)

## Hide the card and drop its content — the player has left the round.
func dismiss() -> void:
	clear_body()
	set_status("")
	hide()

func _add_body_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(label)
	_fit_body.call_deferred()
	return label

func _add_score_row(name_text: String, value_text: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIConstants.SEPARATION_MD)

	var name_label := Label.new()
	name_label.text = name_text
	name_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Long names shorten instead of pushing the score off the card.
	name_label.clip_text = true
	row.add_child(name_label)

	var value_label := Label.new()
	value_label.text = value_text
	value_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", color)
	row.add_child(value_label)

	body.add_child(row)
	_row_names.append(name_text)
	_row_values.append(value_label)
	_row_colors.append(color)

## Same players in the same order: only the scores need writing.
func _rows_match(rows: Array) -> bool:
	if rows.size() != _row_names.size():
		return false
	for i in rows.size():
		if str(_row_field(rows[i], "name")) != _row_names[i]:
			return false
	return true

## One field of a score row, tolerant of callers that pass bare dictionaries.
static func _row_field(row: Variant, key: String, fallback: Variant = "") -> Variant:
	if row is Dictionary:
		return row.get(key, fallback)
	return fallback

## Grow the body to fit its content, up to the cap. A ScrollContainer does not
## inherit its children's minimum size, so the card has to measure for it.
func _fit_body() -> void:
	if not is_inside_tree() or not is_instance_valid(_scroll) or not is_instance_valid(body):
		return
	_scroll.custom_minimum_size.y = clampf(body.get_combined_minimum_size().y,
		0.0, MAX_BODY_HEIGHT)
