extends PanelContainer
class_name TournamentLeaderboard
## Live leaderboard panel shown during tournaments.
## Supports multi-round display with per-round score columns, cut line,
## and MC (missed cut) labels. In the game HUD it is docked to the top-left
## corner of the screen, above the course view, where the scores can be read
## without leaving the round; standalone mode remains useful to isolated tools
## and tests.

signal return_to_course

const PANEL_WIDTH: float = 340.0
# Top margin is measured at runtime so the board clears the status column.
const RIGHT_MARGIN: float = 10.0
## Tallest the row area grows while docked before it scrolls inside the board.
const DOCK_BODY_MAX_HEIGHT: float = 200.0

var _entries: Array = []  # Array of entry dicts
var _grid: GridContainer = null
var _scroll: ScrollContainer = null
var _title_label: Label = null
var _round_label: Label = null
var _close_btn: Button = null
var _tournament_name: String = ""
var _participant_count: int = 0
var _total_rounds: int = 1
var _current_round: int = 1
var _is_final: bool = false
var _cut_advancing: Array = []
var _cut_eliminated: Array = []
var embedded := false

func _ready() -> void:
	_build_ui()
	hide()

func _build_ui() -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL if embedded else Control.SIZE_SHRINK_BEGIN
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if embedded else Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(UIConstants.COLOR_BG_DARK, 0.92)
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = UIConstants.COLOR_BORDER
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Title row
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	_title_label = Label.new()
	_title_label.text = "Tournament Leaderboard"
	_title_label.add_theme_font_size_override("font_size", 13)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title_label)

	_close_btn = Button.new()
	_close_btn.text = "X"
	_close_btn.custom_minimum_size = Vector2(52 if embedded else 24, 24)
	_close_btn.pressed.connect(_on_close_pressed)
	_close_btn.visible = false
	title_row.add_child(_close_btn)

	# Round info label
	_round_label = Label.new()
	_round_label.text = ""
	_round_label.add_theme_font_size_override("font_size", 11)
	_round_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.visible = false
	vbox.add_child(_round_label)

	vbox.add_child(HSeparator.new())

	# Scrollable grid area
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 0 if embedded else 200)
	vbox.add_child(_scroll)

	_grid = GridContainer.new()
	_grid.columns = 1
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)

## Show leaderboard for a tournament (multi-round aware)
func show_for_tournament(tournament_name: String, participant_count: int = 0,
		total_rounds: int = 1, round_text: String = "") -> void:
	_tournament_name = tournament_name
	_participant_count = participant_count
	_total_rounds = total_rounds
	_current_round = 1
	_is_final = false
	_entries.clear()
	_cut_advancing.clear()
	_cut_eliminated.clear()

	if participant_count > 0:
		_title_label.text = "%s (%d) — LIVE" % [tournament_name, participant_count]
	else:
		_title_label.text = "%s — LIVE" % tournament_name

	_round_label.text = round_text
	_round_label.visible = round_text != ""
	_close_btn.visible = false
	_refresh_display()
	_position_panel()
	show()

## Update round info display
func update_round_info(round_num: int, total_rnds: int, round_text: String) -> void:
	_current_round = round_num
	_total_rounds = total_rnds
	_round_label.text = round_text
	_round_label.visible = round_text != ""

	if not _is_final:
		if _participant_count > 0:
			_title_label.text = "%s (%d) — LIVE" % [_tournament_name, _participant_count]
		else:
			_title_label.text = "%s — LIVE" % _tournament_name

	_refresh_display()

## Register a golfer on the leaderboard. `is_player` marks the owner's own entry
## — hosting a tournament puts you in the field, so the board calls it out.
func register_golfer(golfer_id: int, golfer_name: String, sim_id: int = -1,
		is_player: bool = false) -> void:
	_entries.append({
		"golfer_id": golfer_id,
		"sim_id": sim_id if sim_id != -1 else golfer_id,
		"name": golfer_name,
		"round_scores": [],
		"total_strokes": 0,
		"total_par": 0,
		"holes_completed": 0,
		"is_finished": false,
		"missed_cut": false,
		"is_player": is_player,
	})
	_refresh_display()

## Attach the live node id to a field entry already on the board, so per-hole
## scores from the course update the right row.
func bind_live_golfer(sim_id: int, golfer_id: int) -> void:
	for entry in _entries:
		if entry.sim_id == sim_id:
			entry.golfer_id = golfer_id
			return

## Is this golfer (by either id) already on the board?
func has_golfer(id: int) -> bool:
	for entry in _entries:
		if entry.golfer_id == id or entry.sim_id == id:
			return true
	return false

## Update score for a live golfer (per-hole update)
func update_score(golfer_id: int, _hole: int, strokes: int, par: int) -> void:
	for entry in _entries:
		if entry.golfer_id == golfer_id:
			entry.total_strokes += strokes
			entry.total_par += par
			entry.holes_completed += 1
			break
	_refresh_display()

## Mark a live golfer as finished
func mark_finished(golfer_id: int, total_strokes: int) -> void:
	for entry in _entries:
		if entry.golfer_id == golfer_id:
			entry.is_finished = true
			entry.total_strokes = total_strokes
			break
	_refresh_display()

## Set simulated results for batch-completed golfers
func set_simulated_results(results: Array) -> void:
	for result in results:
		for entry in _entries:
			if entry.golfer_id == result.golfer_id:
				entry.total_strokes = result.total_strokes
				entry.total_par = result.total_par
				entry.holes_completed = result.holes_completed
				entry.is_finished = true
				break
	_refresh_display()

## Set round score for a simulated golfer (multi-round)
func set_round_score(sim_id: int, round_number: int,
		round_strokes: int, round_par: int,
		cumulative_strokes: int, cumulative_par: int) -> void:
	for entry in _entries:
		if entry.sim_id == sim_id or entry.golfer_id == sim_id:
			while entry.round_scores.size() < round_number:
				entry.round_scores.append(null)
			entry.round_scores[round_number - 1] = {
				"strokes": round_strokes,
				"par": round_par,
			}
			entry.total_strokes = cumulative_strokes
			entry.total_par = cumulative_par
			entry.is_finished = true
			entry.holes_completed = -1
			break
	_refresh_display()

## Apply cut line: mark eliminated golfers
func apply_cut_line(advancing: Array, eliminated: Array) -> void:
	_cut_advancing = advancing
	_cut_eliminated = eliminated
	for entry in _entries:
		if entry.sim_id in eliminated:
			entry.missed_cut = true
	_refresh_display()

func show_final_results() -> void:
	_is_final = true
	if embedded:
		_close_btn.text = "Return"
		_close_btn.visible = true
	if _participant_count > 0:
		_title_label.text = "%s (%d) — FINAL" % [_tournament_name, _participant_count]
	else:
		_title_label.text = "%s — FINAL" % _tournament_name
	_round_label.visible = false
	_close_btn.visible = true
	_refresh_display()

func _refresh_display() -> void:
	for child in _grid.get_children():
		child.queue_free()

	# Header row
	var header = _create_header_row()
	_grid.add_child(header)

	# Sort: advancing by score-to-par, then eliminated
	var sorted = _entries.duplicate()
	sorted.sort_custom(func(a, b):
		if a.missed_cut != b.missed_cut:
			return not a.missed_cut
		var a_diff = a.total_strokes - a.total_par if a.total_par > 0 else 999
		var b_diff = b.total_strokes - b.total_par if b.total_par > 0 else 999
		return a_diff < b_diff
	)

	var cut_line_shown = false
	for i in range(sorted.size()):
		var entry = sorted[i]

		# Show cut line separator
		if entry.missed_cut and not cut_line_shown and not _cut_eliminated.is_empty():
			cut_line_shown = true
			_grid.add_child(_create_cut_line_separator())

		var rank_text = "%d" % (i + 1)
		var score_text = _format_total_score(entry)
		var thru_text = _get_thru_text(entry)
		var score_color = _get_score_color(entry.total_strokes - entry.total_par, entry.total_par)

		if entry.missed_cut:
			score_color = UIConstants.COLOR_TEXT_DIM

		var row = _create_entry_row(rank_text, entry.name, entry.round_scores,
			score_text, thru_text, score_color, entry.missed_cut, entry.get("is_player", false))
		_grid.add_child(row)

	if embedded:
		_fit_body.call_deferred()

## Grow the board to fit its field, up to the cap, so a small field does not
## leave an empty card behind. A ScrollContainer does not inherit its child's
## minimum size, so the board has to measure for it while docked.
func _fit_body() -> void:
	if not embedded or not is_inside_tree() or not is_instance_valid(_scroll) \
			or not is_instance_valid(_grid):
		return
	_scroll.custom_minimum_size.y = clampf(_grid.get_combined_minimum_size().y,
		0.0, DOCK_BODY_MAX_HEIGHT)

func _create_header_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	row.add_child(_make_label("", 20, UIConstants.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT))

	var name_lbl = _make_label("Name", 0, UIConstants.COLOR_TEXT_DIM)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	if _total_rounds > 1:
		for r in range(_total_rounds):
			row.add_child(_make_label("R%d" % (r + 1), 28, UIConstants.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT))

	row.add_child(_make_label("Tot", 35, UIConstants.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_make_label("Thru", 28, UIConstants.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT))

	return row

func _create_entry_row(rank: String, player_name: String, round_scores: Array,
		score: String, thru: String, color: Color, missed_cut: bool,
		is_player: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var name_color = Color.WHITE if not missed_cut else UIConstants.COLOR_TEXT_DIM
	if is_player:
		name_color = UIConstants.COLOR_GOLD

	row.add_child(_make_label(rank, 20, UIConstants.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT))

	var name_lbl = _make_label(player_name + (" (you)" if is_player else ""), 0, name_color)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	row.add_child(name_lbl)

	if _total_rounds > 1:
		for r in range(_total_rounds):
			var r_text = "-"
			var r_color = UIConstants.COLOR_TEXT_DIM
			if r < round_scores.size() and round_scores[r] != null:
				var diff = round_scores[r].strokes - round_scores[r].par
				r_text = _format_score_diff(diff)
				r_color = _get_score_color(diff, round_scores[r].par)
				if missed_cut:
					r_color = UIConstants.COLOR_TEXT_DIM
			row.add_child(_make_label(r_text, 28, r_color, HORIZONTAL_ALIGNMENT_RIGHT))

	row.add_child(_make_label(score, 35, color, HORIZONTAL_ALIGNMENT_RIGHT))

	var thru_text = "MC" if missed_cut else thru
	var thru_color = UIConstants.COLOR_SCORE_OVER if missed_cut else UIConstants.COLOR_TEXT_DIM
	row.add_child(_make_label(thru_text, 28, thru_color, HORIZONTAL_ALIGNMENT_RIGHT))

	return row

func _create_cut_line_separator() -> HBoxContainer:
	var row := HBoxContainer.new()
	var sep_label = Label.new()
	sep_label.text = "— CUT LINE —"
	sep_label.add_theme_font_size_override("font_size", 10)
	sep_label.add_theme_color_override("font_color", UIConstants.COLOR_SCORE_OVER)
	sep_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sep_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sep_label)
	return row

func _make_label(text: String, min_width: int, color: Color,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = alignment
	if min_width > 0:
		label.custom_minimum_size = Vector2(min_width, 0)
	return label

func _format_total_score(entry: Dictionary) -> String:
	if entry.total_par == 0:
		return "-"
	return _format_score_diff(entry.total_strokes - entry.total_par)

func _format_score_diff(diff: int) -> String:
	if diff == 0:
		return "E"
	elif diff > 0:
		return "+%d" % diff
	else:
		return "%d" % diff

func _get_thru_text(entry: Dictionary) -> String:
	if entry.is_finished:
		return "F"
	if entry.holes_completed > 0:
		return "%d" % entry.holes_completed
	return "-"

func _get_score_color(diff: int, total_par: int) -> Color:
	if total_par == 0:
		return UIConstants.COLOR_TEXT_DIM
	if diff < 0:
		return UIConstants.COLOR_SCORE_UNDER
	if diff == 0:
		return UIConstants.COLOR_SCORE_PAR
	return UIConstants.COLOR_SCORE_OVER

func _on_close_pressed() -> void:
	if embedded and _is_final:
		hide()
		return_to_course.emit()
	else:
		hide()

func _position_panel() -> void:
	if embedded:
		return
	await get_tree().process_frame
	var vp_size = get_viewport().get_visible_rect().size
	position = Vector2(vp_size.x - size.x - RIGHT_MARGIN, UIConstants.get_hud_column_clearance(self))
