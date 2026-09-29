extends Node
## Headless smoke test for hosting a tournament through the shelf, on the real
## main scene: the event starts on the click rather than on a later day, the field
## opens with a pairing on every hole, the owner plays in it, a round settled by the
## clock still completes every card, and the results, cooldown and cleanup follow.
##
## Run:  godot --headless --path . res://tests/harness/tournament_harness.tscn

const REGIONAL := TournamentSystem.TournamentTier.REGIONAL

var main: Node2D
var tournaments
var failures: int = 0

func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _check(condition: bool, label: String) -> void:
	if condition:
		print("HARNESS: PASS: %s" % label)
	else:
		failures += 1
		printerr("HARNESS: FAIL: %s" % label)

func _live_tournament_golfers() -> Array:
	var seen: Array = []
	for golfer in main.golfer_manager.active_golfers:
		if golfer.is_tournament_golfer:
			seen.append(golfer)
	return seen

## The first label anywhere on the shelf whose text starts with `prefix`.
func _panel_label(prefix: String) -> String:
	for label in main.tournament_panel.find_children("*", "Label", true, false):
		if str(label.text).begins_with(prefix):
			return str(label.text)
	return ""

## Par of the open circuit as a tournament measures it: the back tees, which is
## what both live play and the headless fill score a hole against.
func _circuit_par() -> int:
	var total := 0
	for hole in GameManager.current_course.holes:
		if hole.is_open:
			total += int(hole.get_par_for_tee("back"))
	return total

func _run() -> void:
	await _frames(20)
	main._on_main_menu_quick_start("Tournament Harness", 0)
	await _frames(150)
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.ULTRA)
	await _frames(30)

	tournaments = GameManager.tournament_manager
	var open_holes = GameManager.get_open_hole_count()
	var circuit_par = _circuit_par()
	var profile_name = GameManager.player_profile.golfer_name

	# The shelf is the Player tab's Play page; opening it is what a player does.
	main._toggle_tournament_panel()
	await _frames(30)
	var host_button = main.tournament_panel.get_host_button(REGIONAL)
	_check(host_button != null, "the Regional card carries a Host button")
	_check(not host_button.disabled,
		"the button is live on a qualifying course (tooltip: %s)" % host_button.tooltip_text)
	_check(tournaments.can_schedule_tournament(REGIONAL).reason == "",
		"hosting reports no outstanding requirement")

	# --- It starts straight away --------------------------------------------
	var day_before = GameManager.current_day
	var field_expected = TournamentSystem.get_field_size(REGIONAL, open_holes)
	var rounds_expected = tournaments.ROUNDS_PER_TIER[REGIONAL]
	var money_before = GameManager.money
	# No frame between the two reads: `pressed` is synchronous, and a day rolling
	# over in between would move operating costs into the same comparison.
	host_button.pressed.emit()
	var fee = TournamentSystem.TIER_DATA[REGIONAL].entry_cost
	_check(GameManager.money == money_before - fee,
		"the entry fee ($%d) was charged on the click" % fee)
	await _frames(2)
	_check(tournaments.current_tournament_state == TournamentSystem.TournamentState.IN_PROGRESS,
		"the tournament is live on the frame it was hosted")
	_check(tournaments.tournament_start_day == day_before,
		"it is dated today (day %d), not a day still to come" % tournaments.tournament_start_day)
	_check(tournaments.current_round == 1, "round 1 is under way")
	_check(tournaments._sim_field.size() == field_expected,
		"the field is assembled on the click (%d entries)" % field_expected)

	# --- Two competitors on every hole --------------------------------------
	_check(TournamentSystem.get_group_size() == 2, "competitors play in pairs")
	_check(tournaments._live_count == open_holes * 2,
		"the field seats two per open hole (%d on %d holes)" % [tournaments._live_count, open_holes])
	_check(tournaments._total_groups == open_holes,
		"one pairing per hole: %d groups" % tournaments._total_groups)
	await _frames(90)
	var by_hole := {}
	var group_sizes := {}
	for golfer in _live_tournament_golfers():
		by_hole[golfer.current_hole] = int(by_hole.get(golfer.current_hole, 0)) + 1
		group_sizes[golfer.group_id] = int(group_sizes.get(golfer.group_id, 0)) + 1
	var pairs_only := true
	for size in group_sizes.values():
		if int(size) != 2:
			pairs_only = false
	_check(pairs_only, "every competitor is in a pairing of two (%s)" % group_sizes)
	# A catch-up group can share a hole with the one ahead while it clears the
	# green, so the check is that the field is spread over the course at all.
	_check(by_hole.size() >= mini(4, open_holes),
		"the field is spread over the course, not queued on the first tee (%s)" % by_hole)
	_check(not _live_tournament_golfers().is_empty(), "golfers are on the course playing")

	# --- The owner is one of them -------------------------------------------
	var owner_seen := false
	for golfer in _live_tournament_golfers():
		if golfer.golfer_name == profile_name:
			owner_seen = true
	_check(owner_seen, "the owner's golfer (%s) is out there" % profile_name)
	_check(int(tournaments._sim_field[0].id) == TournamentManager.PLAYER_SIM_ID \
			and tournaments._sim_field[0].name == profile_name,
		"the owner leads off the field, so they tee off in the first pairing")
	var owner_row_found := false
	for entry in tournaments._leaderboard._entries:
		if entry.get("is_player", false):
			owner_row_found = true
	_check(owner_row_found, "the live leaderboard carries the owner's row")
	_check(int(tournaments.get_player_standing().get("field_size", 0)) == field_expected,
		"the shelf scores the owner against the whole field")

	# --- And the shelf says so ----------------------------------------------
	main.tournament_panel._refresh_display()
	await _frames(5)
	_check("In Progress" in main.tournament_panel._status_label.text,
		"the panel shows the running event (%s)" % main.tournament_panel._status_label.text.replace("\n", " | "))
	_check(_panel_label("You:").begins_with("You:"),
		"the panel shows the owner's scoreline (%s)" % _panel_label("You:"))

	# --- Play It Out settles the event on full cards -------------------------
	var settle = main.tournament_panel.get_settle_button()
	_check(settle != null, "the running event offers Play It Out")
	settle.pressed.emit()
	await _frames(30)
	_check(not tournaments.is_tournament_in_progress(), "the event is over")
	var results: Dictionary = tournaments.tournament_results
	_check(not results.is_empty(), "results were published")
	var rounds_played = int(results.get("rounds_played", 0))
	_check(rounds_played == rounds_expected,
		"all %d round(s) of the event were scored" % rounds_played)
	var entries: Array = results.get("all_entries", [])
	_check(entries.size() == field_expected,
		"every entry in the field was scored (%d of %d)" % [entries.size(), field_expected])
	var cards_ok := true
	for entry in entries:
		if int(entry.total_par) != circuit_par * rounds_played:
			cards_ok = false
	var pars := {}
	for entry in entries:
		pars[int(entry.total_par)] = int(pars.get(int(entry.total_par), 0)) + 1
	_check(cards_ok, "every card covers the circuit once per round (par %d × %d): %s" % [
		circuit_par, rounds_played, pars])
	_check(entries.any(func(e): return e.get("is_player", false)),
		"the owner's result is in the book")
	_check(_live_tournament_golfers().is_empty(), "nobody stays on the course after the event")
	_check(GameManager.money > money_before,
		"the event paid for itself (%d -> %d)" % [money_before, GameManager.money])

	# --- Cooldown, and the button tells you so -------------------------------
	_check(tournaments.get_cooldown_remaining() > 0,
		"the cooldown started (%d days)" % tournaments.get_cooldown_remaining())
	main.tournament_panel._refresh_display()
	await _frames(5)
	_check(main.tournament_panel.get_host_button(REGIONAL) == null,
		"the tier cards step aside during the cooldown")
	_check("Cooldown" in main.tournament_panel._status_label.text,
		"the panel says why: %s" % main.tournament_panel._status_label.text.replace("\n", " | "))
	_check("Must wait" in str(tournaments.can_schedule_tournament(REGIONAL).reason),
		"hosting again during the cooldown names the wait")

	print("HARNESS: done, %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
