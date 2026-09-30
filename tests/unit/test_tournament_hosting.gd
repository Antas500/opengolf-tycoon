extends GutTest
## Hosting a tournament: it starts on the click, two competitors play each open
## hole, the owner is one of them, and the Host button never blames "no course".

const LOCAL := TournamentSystem.TournamentTier.LOCAL
const REGIONAL := TournamentSystem.TournamentTier.REGIONAL

var fixture: Node2D
var golfers: GolferManager
var leaderboard: TournamentLeaderboard
var tournaments: TournamentManager
var saved: Dictionary

func before_each() -> void:
	saved = {"course": GameManager.current_course, "grid": GameManager.terrain_grid,
		"mode": GameManager.current_mode, "speed": GameManager.current_speed,
		"money": GameManager.money, "day": GameManager.current_day,
		"rating": GameManager.course_rating, "profile": GameManager.player_profile,
		"tournament": GameManager.tournament_manager,
		"last_end": GameManager.tournament_manager.last_tournament_end_day if GameManager.tournament_manager else -100}
	_open_course(4)
	GameManager.player_profile = PlayerGolferProfile.new()
	GameManager.player_profile.golfer_name = "Owner O'Hare"
	GameManager.player_profile.initialized = true
	GameManager.current_day = 1
	GameManager.money = 25000
	# Enough stars to clear the Local bar without a terrain grid to rate.
	GameManager.course_rating = {"overall": 3.0, "difficulty": 1.0, "stars": 3}

	fixture = Node2D.new()
	add_child_autofree(fixture)
	var entities := Node2D.new()
	entities.name = "Entities"
	fixture.add_child(entities)
	for container_name in ["Golfers", "Balls"]:
		var container := Node2D.new()
		container.name = container_name
		entities.add_child(container)
	golfers = GolferManager.new()
	fixture.add_child(golfers)
	leaderboard = TournamentLeaderboard.new()
	fixture.add_child(leaderboard)
	tournaments = TournamentManager.new()
	fixture.add_child(tournaments)
	tournaments.setup(golfers, leaderboard)
	GameManager.tournament_manager = tournaments
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)

func after_each() -> void:
	GameManager.tournament_manager = saved.tournament
	GameManager.current_course = saved.course
	GameManager.terrain_grid = saved.grid if is_instance_valid(saved.grid) else null
	GameManager.current_mode = saved.mode
	GameManager.current_speed = saved.speed
	GameManager.money = saved.money
	GameManager.current_day = saved.day
	GameManager.course_rating = saved.rating
	GameManager.player_profile = saved.profile

## A course of `holes` playable par 3s, each long enough to satisfy the yardage gate.
func _open_course(holes: int) -> void:
	var course := GameManager.CourseData.new()
	for i in range(holes):
		var hole := GameManager.HoleData.new()
		hole.hole_number = i + 1
		hole.par = 3
		hole.distance_yards = 400
		hole.tee_position = Vector2i(4 + i * 4, 4)
		hole.hole_position = Vector2i(6 + i * 4, 4)
		course.add_hole(hole)
	GameManager.current_course = course

# --- The "No course data" dead end ---

func test_missing_course_reports_an_actionable_requirement() -> void:
	var result: Dictionary = TournamentSystem.check_qualification(LOCAL, null, {})
	assert_false(result.qualified, "No course cannot host a tournament")
	assert_false("No course data" in result.missing,
		"The gate must never dead-end on 'No course data'")
	assert_string_contains(result.missing[0], "holes",
		"The player is told which requirement is missing")

func test_host_button_enables_once_holes_are_open() -> void:
	GameManager.current_course = null
	# The shelf the game actually uses: embedded in the Player tab, always on
	# screen, so a course change redraws it.
	var panel := TournamentPanel.new()
	panel.embedded = true
	add_child_autofree(panel)
	panel.setup(tournaments)
	assert_true(panel.visible, "The tournament shelf is on screen")
	var blocked := tournaments.can_schedule_tournament(LOCAL)
	assert_false(blocked.can_schedule, "Nothing to play on yet")
	assert_false("No course data" in blocked.reason,
		"An empty course must not dead-end with 'No course data'")
	assert_true(panel.get_host_button(0).disabled, "Local hosting is gated")

	# Open the course; the panel refreshes on course changes rather than leaving
	# a stale greyed-out button on the shelf.
	_open_course(4)
	EventBus.hole_created.emit(1, 3, 400)
	await wait_frames(40)
	assert_true(tournaments.can_schedule_tournament(LOCAL).can_schedule,
		"A four-hole course qualifies for a Local event")
	assert_false(panel.get_host_button(0).disabled, "The Host button comes back")

# --- Immediate start ---

func test_hosting_starts_the_tournament_at_once() -> void:
	assert_true(tournaments.host_tournament(LOCAL), "Hosting succeeds on a qualifying course")
	assert_eq(tournaments.current_tournament_state, TournamentSystem.TournamentState.IN_PROGRESS,
		"The event is under way, not booked for later")
	assert_eq(tournaments.tournament_start_day, GameManager.current_day,
		"It starts on the day it is hosted")
	assert_gt(GameManager.money, 0, "The entry fee was taken from a healthy treasury")

func test_hosting_starts_live_play_immediately() -> void:
	tournaments.host_tournament(LOCAL)
	await wait_frames(2)
	assert_true(tournaments._live_round_active, "Golfers are playing on the course already")
	assert_gt(golfers.active_golfers.size(), 0, "Bodies appear on the course with the click")

func test_tournament_does_not_end_on_a_calendar_deadline() -> void:
	tournaments.host_tournament(LOCAL)
	var later_day := GameManager.current_day + 500
	GameManager.current_day = later_day
	EventBus.day_changed.emit(later_day)
	EventBus.end_of_day.emit(later_day)
	await wait_frames(2)
	assert_eq(tournaments.current_tournament_state, TournamentSystem.TournamentState.IN_PROGRESS,
		"A tournament stays open until all competitors finish, regardless of elapsed days")
	assert_true(tournaments._live_round_active, "The live field is not settled by a day rollover")

func test_hosting_rejects_a_course_with_no_holes() -> void:
	GameManager.current_course = GameManager.CourseData.new()
	var check: Dictionary = tournaments.can_schedule_tournament(LOCAL)
	assert_false(check.can_schedule, "No open holes, no tournament")
	assert_string_contains(check.reason, "holes")

# --- Two competitors per hole, player included ---

func test_two_competitors_per_open_hole() -> void:
	assert_eq(TournamentSystem.get_group_size(), 2, "Competitors play in pairs")
	assert_eq(TournamentSystem.get_live_field_size(9), 18, "Nine holes seat nine pairings")
	assert_eq(TournamentSystem.get_live_field_size(1), 2, "One hole still gets a pairing")
	# The tier's nominal field still counts when the course is smaller.
	assert_eq(TournamentSystem.get_field_size(LOCAL, 4), 12,
		"A four-hole course keeps the Local field of twelve")
	assert_eq(TournamentSystem.get_field_size(LOCAL, 9), 18,
		"A nine-holer grows the Local field to seat a pair on every hole")
	assert_eq(TournamentSystem.get_field_size(REGIONAL, 4), 24, "Regional stays bigger than Local")

func test_field_starts_with_a_pair_on_every_hole() -> void:
	tournaments.host_tournament(LOCAL)
	# 4 open holes × 2 = 8 of the 12-man field play on the course, as 4 pairs.
	assert_eq(tournaments._live_count, 8, "Two competitors per open hole")
	assert_eq(tournaments._total_groups, 4, "The live field is four pairings")
	assert_eq(tournaments._sim_field.size(), 12, "The rest of the field is still in the event")

func test_each_open_hole_gets_its_own_pairing() -> void:
	tournaments.host_tournament(LOCAL)
	await wait_until(func() -> bool:
		return tournaments._groups_spawned >= tournaments._total_groups, 4.0)
	var by_hole := {}
	for golfer in golfers.active_golfers:
		if golfer.is_tournament_golfer:
			by_hole[golfer.current_hole] = int(by_hole.get(golfer.current_hole, 0)) + 1
	assert_eq(by_hole.size(), 4, "The field spreads out over the course")
	for hole_index in by_hole:
		assert_eq(int(by_hole[hole_index]), 2,
			"Hole %d has two competitors on it" % (hole_index + 1))

# --- The turn: a pairing wraps back to the first tee together -------------

## A pairing that reaches the last hole wraps back to the first tee to play the
## circuit out. The partner who has already holed out and wrapped must not be
## treated as the hole the group is on, or the competitor still on the last green
## is never given their turn again: they are left standing on the last hole
## instead of walking to the first tee with their partner.
func test_partner_on_the_last_hole_still_gets_their_turn_after_a_wrap() -> void:
	_open_course(4)
	var first := golfers.spawn_tournament_golfer(GolferTier.Tier.SERIOUS, 0)
	var second := golfers.spawn_tournament_golfer(GolferTier.Tier.SERIOUS, 0)
	golfers.seat_golfer_at_hole(first, 3)
	golfers.seat_golfer_at_hole(second, 3)

	# `first` has holed out on the last hole and wrapped: one hole carded, and
	# standing on the first tee waiting for their partner.
	first.hole_scores = [{"hole": 4, "strokes": 3, "par": 3}]
	first.current_strokes = 0
	first.current_hole = 0
	first.ball_position = GameManager.current_course.holes[0].tee_position
	first.ball_position_precise = Vector2(first.ball_position)
	first._change_state(Golfer.State.IDLE)

	# `second` is still on the last hole with the ball in the cup.
	var last_hole = GameManager.current_course.holes[3]
	second.current_hole = 3
	second.current_strokes = 3
	second.ball_position = last_hole.hole_position
	second.ball_position_precise = Vector2(last_hole.hole_position)
	second._change_state(Golfer.State.IDLE)

	var pair: Array[Golfer] = [first, second]
	assert_eq(golfers._get_group_current_hole(pair), 3,
		"The group is on the hole the trailing competitor has yet to finish")
	assert_same(golfers._determine_next_golfer_in_group(pair), second,
		"The competitor still on the last hole plays next; the wrapped partner waits")

	# Give the turn system its frame: the partner must be sent round to the first tee.
	golfers._update_group(pair)
	assert_eq(second.hole_scores.size(), 1,
		"The competitor left on the last hole finally cards it")
	assert_eq(second.current_hole, 0,
		"…and wraps to the first hole instead of being stranded on the last")

## The wrapped partner waits for the group rather than teeing off alone on the
## first hole while their partner is still on the last one.
func test_wrapped_partner_waits_for_the_group() -> void:
	_open_course(4)
	var first := golfers.spawn_tournament_golfer(GolferTier.Tier.SERIOUS, 0)
	var second := golfers.spawn_tournament_golfer(GolferTier.Tier.SERIOUS, 0)
	golfers.seat_golfer_at_hole(first, 3)
	golfers.seat_golfer_at_hole(second, 3)
	first.hole_scores = [{"hole": 4, "strokes": 3, "par": 3}]
	first.current_strokes = 0
	first.current_hole = 0
	first.ball_position = GameManager.current_course.holes[0].tee_position
	first.ball_position_precise = Vector2(first.ball_position)
	first._change_state(Golfer.State.IDLE)
	second.current_hole = 3
	second.current_strokes = 2
	second.ball_position_precise = Vector2(GameManager.current_course.holes[3].hole_position) + Vector2(2, 0)
	second.ball_position = Vector2i(second.ball_position_precise.round())
	second._change_state(Golfer.State.IDLE)

	var pair: Array[Golfer] = [first, second]
	assert_same(golfers._determine_next_golfer_in_group(pair), second,
		"The competitor on the last hole keeps the turn until the hole is done")
	assert_eq(golfers._get_group_current_hole(pair), 3,
		"The group's hole follows the competitor who is furthest back")

## The walk, not just the turn: the partner left on the last hole holes out,
## wraps, and sets off for the first tee on the course itself.
func test_the_partner_walks_round_to_the_first_tee_after_wrapping() -> void:
	_open_course(4)
	var grid: TerrainGrid = autofree(TerrainGrid.new())
	grid.grid_width = 40
	grid.grid_height = 12
	add_child_autofree(grid)
	for x in range(40):
		for y in range(12):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.FAIRWAY)
	for hole in GameManager.current_course.holes:
		grid.set_tile(hole.tee_position, TerrainTypes.Type.TEE_BOX)
		grid.set_tile(hole.hole_position, TerrainTypes.Type.GREEN)
	GameManager.terrain_grid = grid

	var first := golfers.spawn_tournament_golfer(GolferTier.Tier.SERIOUS, 0)
	var second := golfers.spawn_tournament_golfer(GolferTier.Tier.SERIOUS, 0)
	golfers.seat_golfer_at_hole(second, 3)
	# `first` has wrapped and is standing on the first tee.
	golfers.seat_golfer_at_hole(first, 0)
	first.hole_scores = [{"hole": 4, "strokes": 3, "par": 3}]
	first.current_strokes = 0
	first._change_state(Golfer.State.IDLE)
	# `second` is on the last green with the ball in the cup.
	var last_hole = GameManager.current_course.holes[3]
	second.current_hole = 3
	second.current_strokes = 3
	second.ball_position = last_hole.hole_position
	second.ball_position_precise = Vector2(last_hole.hole_position)
	second._change_state(Golfer.State.IDLE)

	golfers._update_group([first, second] as Array[Golfer])
	assert_eq(second.current_hole, 0, "The partner wraps to the first hole")
	assert_eq(second.current_state, Golfer.State.WALKING,
		"The partner walks off the last green instead of standing on it")
	assert_false(second.path.is_empty(), "…along a route to the first tee")
	var destination: Vector2 = second.path[second.path.size() - 1]
	var first_tee: Vector2 = grid.grid_to_screen_center(GameManager.current_course.holes[0].tee_position)
	assert_almost_eq(destination.distance_to(first_tee), 0.0, 2.0,
		"…which ends on the first tee")

## The whole circuit from every starting hole: whichever tee a pairing is seated
## on, both competitors card every hole of the course exactly once and finish the
## round. Before the wrap fix the partner left on the last green never carded
## another hole (the round stalled a shot short), and once the pairing had gone
## round to the first tee it was sent back onto the holes it teed off on, so its
## card covered more than the rest of the field's.
func test_a_pairing_plays_the_circuit_once_from_any_starting_hole() -> void:
	for start_hole in 4:
		_open_course(4)
		var first := golfers.spawn_tournament_golfer(GolferTier.Tier.SERIOUS, 0)
		var second := golfers.spawn_tournament_golfer(GolferTier.Tier.SERIOUS, 0)
		golfers.seat_golfer_at_hole(first, start_hole)
		golfers.seat_golfer_at_hole(second, start_hole)
		var pair: Array[Golfer] = [first, second]

		# Each turn: hole the ball out and let the turn system move the pairing on.
		for _step in 200:
			golfers._update_group(pair)
			for golfer in pair:
				if golfer.current_state != Golfer.State.PREPARING_SHOT:
					continue
				var hole = GameManager.current_course.holes[golfer.current_hole]
				golfer.current_strokes = 3
				golfer.ball_position = hole.hole_position
				golfer.ball_position_precise = Vector2(hole.hole_position)
				golfer._change_state(Golfer.State.IDLE)
			if first.current_state == Golfer.State.FINISHED \
					and second.current_state == Golfer.State.FINISHED:
				break

		var carded := []
		for golfer in pair:
			for hs in golfer.hole_scores:
				carded.append(int(hs.hole))
		carded.sort()
		assert_eq(carded, [1, 1, 2, 2, 3, 3, 4, 4],
			"Seated on hole %d, both competitors card every hole once" % (start_hole + 1))
		assert_eq(first.current_state, Golfer.State.FINISHED,
			"Seated on hole %d, the first competitor finishes" % (start_hole + 1))
		assert_eq(second.current_state, Golfer.State.FINISHED,
			"Seated on hole %d, the second competitor finishes too" % (start_hole + 1))
		golfers.clear_all_golfers()

## Once the whole pairing has wrapped, the first tee belongs to the group again.
func test_wrapped_pair_tees_off_on_the_first_hole() -> void:
	_open_course(4)
	var first := golfers.spawn_tournament_golfer(GolferTier.Tier.SERIOUS, 0)
	var second := golfers.spawn_tournament_golfer(GolferTier.Tier.SERIOUS, 0)
	var pair: Array[Golfer] = [first, second]
	for golfer in pair:
		golfers.seat_golfer_at_hole(golfer, 3)
		golfer.hole_scores = [{"hole": 4, "strokes": 3, "par": 3}]
		golfer.current_strokes = 0
		golfer.current_hole = 0
		golfer.ball_position = GameManager.current_course.holes[0].tee_position
		golfer.ball_position_precise = Vector2(golfer.ball_position)
		golfer._change_state(Golfer.State.IDLE)
	assert_eq(golfers._get_group_current_hole(pair), 0, "Wrapped, the group is on the first hole")
	var next = golfers._determine_next_golfer_in_group(pair)
	assert_not_null(next, "Someone from the pairing tees off on the first hole")
	assert_eq(next.current_hole, 0, "…and it is the first hole they play")

## A card that is a few holes short is topped up hole by hole, wrapping back to
## the first tee instead of running out of course and leaving the round short.
func test_a_short_card_is_filled_hole_by_hole() -> void:
	var sg := TournamentSimulator.SimGolfer.new()
	sg.name = "Casey Jackson"
	var result = TournamentSimulator.simulate_remaining(sg, 2, 6, 6, 2)
	assert_eq(result.hole_scores.size(), 2, "Only the two missing holes are filled in")
	assert_eq(result.total_par, 12, "The card ends up covering all four holes")
	assert_eq(result.total_strokes, 12, "Strokes are filled in alongside the par")

## A golfer who teed off on a later hole and played only a few before wrapping
## is topped up with exactly the holes it is missing — never replaying a hole it
## already finished and never dropping another (a consecutive fill used to
## double-count the played block and leave the card short).
func test_a_wrapped_short_card_fills_exactly_the_missing_holes() -> void:
	var pars := [3, 4, 5, 4, 3, 4, 5, 4, 3]  # sums to 35
	var course := GameManager.CourseData.new()
	for i in pars.size():
		var hole := GameManager.HoleData.new()
		hole.hole_number = i + 1
		hole.par = pars[i]
		hole.tee_position = Vector2i(4 + i, 4)
		hole.hole_position = Vector2i(6 + i, 4)
		course.add_hole(hole)
	GameManager.current_course = course
	# Teed off hole index 2, finished holes 2 and 3 (par 5 and 4); seven holes left.
	var sg := TournamentSimulator.SimGolfer.new()
	sg.name = "Wrap Wanda"
	var played := {2: true, 3: true}
	var pre_par: int = int(pars[2]) + int(pars[3])
	var result = TournamentSimulator.simulate_remaining(sg, 0, pre_par, pre_par, 7, played)
	assert_eq(result.hole_scores.size(), 7, "Exactly the seven missing holes are filled")
	assert_eq(result.total_par, 35, "The card covers every hole exactly once")


func test_player_is_one_of_the_competitors() -> void:
	tournaments.host_tournament(LOCAL)
	var entry = tournaments._sim_field[0]
	assert_eq(entry.id, TournamentManager.PLAYER_SIM_ID, "The owner leads off the field")
	assert_eq(entry.name, "Owner O'Hare", "The owner plays under their own name")
	assert_true(tournaments.is_player_entry(entry.id), "The field entry is flagged as the player")
	var found := false
	for board_entry in leaderboard._entries:
		if board_entry.get("is_player", false):
			found = true
			assert_eq(board_entry.name, "Owner O'Hare", "The leaderboard row is the owner's")
	assert_true(found, "The live leaderboard carries the owner")

func test_player_competitor_is_on_the_course() -> void:
	tournaments.host_tournament(LOCAL)
	await wait_frames(2)
	var owner_seen := false
	var group_sizes := {}
	for golfer in golfers.active_golfers:
		if not golfer.is_tournament_golfer:
			continue
		group_sizes[golfer.group_id] = int(group_sizes.get(golfer.group_id, 0)) + 1
		if golfer.golfer_name == "Owner O'Hare":
			owner_seen = true
	assert_true(owner_seen, "The owner's golfer is out there playing")
	assert_eq(group_sizes.values().max(), 2, "Tournament groups are pairs")

func test_player_skills_come_from_the_profile() -> void:
	GameManager.player_profile.points[4] = 10  # Accurate Putter
	var sg = tournaments._make_player_sim_golfer()
	assert_almost_eq(sg.putting_skill, GameManager.player_profile.normalized_skill(4), 0.0001,
		"Allocated skill points carry into the tournament field")
	assert_gt(sg.putting_skill, 0.5, "Investing in putting beats the baseline")
