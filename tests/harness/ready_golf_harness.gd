extends Node
## Headless pace harness: a foursome plays the quick-start course and the
## harness reports how the group's turn-taking actually ran — how many shots
## went in while a partner was still walking to their ball, and how long the
## group spent standing around with nobody able to play.
##
## Three seeds are run and reported separately, because shot outcomes are random
## and one round proves little on its own.
##
## Run:  godot --headless --path . res://tests/harness/ready_golf_harness.tscn

const HOLES_TO_PLAY := 3
const FRAME_BUDGET := 6000
const SEEDS := [20260930, 4711, 8675309]
## The course is generated with randf, so pin the generator too or the three
## runs play a different course every time the harness is started.
const COURSE_SEED := 13579

var main: Node2D
var golfers: GolferManager
var group: Array[Golfer] = []
var measuring := false
var done := false

var sim_seconds := 0.0
var frames := 0
var shots := 0
var shots_with_a_partner_walking := 0
## Frames with somebody still walking, nobody mid-shot, and a golfer standing
## ready to play: the group has a turn to give away and is not giving it. That
## is the stall the ready-golf turn order is meant to remove.
var walker_stall_frames := 0
var stall_seconds := 0.0

var totals := {"shots": 0, "walked": 0, "stall": 0.0, "sim": 0.0, "frames": 0}


func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _process(delta: float) -> void:
	if not measuring or group.is_empty():
		return
	frames += 1
	sim_seconds += delta

	var walking := 0
	var mid_shot := 0
	var ready_count := 0
	for golfer in group:
		if not is_instance_valid(golfer):
			continue
		match golfer.current_state:
			Golfer.State.WALKING:
				walking += 1
			Golfer.State.PREPARING_SHOT, Golfer.State.SWINGING, Golfer.State.WATCHING:
				mid_shot += 1
			Golfer.State.IDLE:
				if golfer._amenity_phase == 0:
					ready_count += 1

	if walking > 0 and mid_shot == 0 and ready_count > 0:
		walker_stall_frames += 1
		stall_seconds += delta

	var carded := true
	for golfer in group:
		if not is_instance_valid(golfer) or golfer.hole_scores.size() < HOLES_TO_PLAY:
			carded = false
			break
	if carded:
		done = true


func _run() -> void:
	await _frames(10)
	print("HARNESS: quick-starting new game")
	seed(COURSE_SEED)
	main._on_main_menu_quick_start("Harness Course", 0)
	await _frames(60)

	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.ULTRA)
	# No other tee times: the measurement is this foursome alone on the course.
	GameManager.tee_booking_interval = 100000

	golfers = main.get_node("GolferManager")
	EventBus.shot_taken.connect(_on_shot_taken)

	for run_seed in SEEDS:
		await _measure(run_seed)

	print("HARNESS: TOTAL shots=%d shots_while_a_partner_walked=%d" % [totals.shots, totals.walked])
	print("HARNESS: TOTAL walker_stall=%.1f sim seconds of %.1f (%.1f%%)" % [
		totals.stall, totals.sim, 100.0 * totals.stall / maxf(totals.sim, 0.001)])
	print("HARNESS: done, quitting")
	await _frames(5)
	get_tree().quit(0)


func _measure(run_seed: int) -> void:
	golfers.clear_all_golfers()
	group.clear()
	sim_seconds = 0.0
	frames = 0
	shots = 0
	shots_with_a_partner_walking = 0
	walker_stall_frames = 0
	stall_seconds = 0.0
	done = false

	seed(run_seed)
	for i in 4:
		var golfer := golfers.spawn_golfer("Pace Tester %d" % (i + 1), 0.65, 0)
		if golfer:
			golfer.initialize_from_tier(GolferTier.Tier.CASUAL)
			group.append(golfer)

	measuring = true
	for _i in FRAME_BUDGET:
		await get_tree().process_frame
		if done:
			break
	measuring = false

	totals.shots += shots
	totals.walked += shots_with_a_partner_walking
	totals.stall += stall_seconds
	totals.sim += sim_seconds
	totals.frames += frames

	print("HARNESS: RESULT seed=%d holes_carded=%d shots=%d shots_while_a_partner_walked=%d" % [
		run_seed, _holes_carded(), shots, shots_with_a_partner_walking])
	print("HARNESS: RESULT seed=%d walker_stall_frames=%d (%.1f sim seconds of %.1f, %.1f%%)" % [
		run_seed, walker_stall_frames, stall_seconds, sim_seconds,
		100.0 * stall_seconds / maxf(sim_seconds, 0.001)])
	if not done:
		print("HARNESS: RESULT seed=%d frame budget reached before the group finished" % run_seed)


func _holes_carded() -> int:
	var carded := 0
	for golfer in group:
		if is_instance_valid(golfer):
			carded += golfer.hole_scores.size()
	return carded


func _on_shot_taken(golfer_id: int, _hole: int, _stroke: int) -> void:
	if not measuring:
		return
	shots += 1
	for golfer in group:
		if not is_instance_valid(golfer) or golfer.golfer_id == golfer_id:
			continue
		if golfer.current_state == Golfer.State.WALKING:
			shots_with_a_partner_walking += 1
			return
