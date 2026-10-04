extends SceneTree
## Integration regression: golfers arrive from the clubhouse, and when their
## round is over they walk back to it, go inside and leave the course.
##
## The group-removal bookkeeping used to hang off `golfer_finished_round`, which
## fires when the last putt drops — several seconds before the golfer has walked
## home. Nothing was removed any more, so finished groups stood at the door
## forever. This test plays the real loop on a one-hole course: spawn, walk in,
## play, walk home, gone. It also covers the clubhouse itself: a course built
## from nothing gets one, the Bulldozer refuses it, and it can be moved.
##
## Uses dynamic loads because a `-s` script compiles before autoloads exist.

const TEE := Vector2i(60, 60)
const CUP := Vector2i(60, 50)

var main: Node
var gm: Node
var course_clubhouse
var clubhouse
var clients: Array[int] = []
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	print("CLUBHOUSE_LIFECYCLE_FAIL: ", message)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _wait_until(condition: Callable, budget: int) -> bool:
	for i in range(budget):
		if condition.call():
			return true
		await process_frame
	return condition.call()


## Both golfers of the pair have gone inside.
func _both_inside(first, second) -> bool:
	return first.current_state == 5 and second.current_state == 5


## Neither golfer of the pair is on the course any more.
func _both_gone(first, second) -> bool:
	var active: Array = main.golfer_manager.get_active_golfers()
	return not active.has(first) and not active.has(second)


## Hole out each golfer on every shot until the game ends their round (they turn
## LEAVING). Drives the same turn system a real round uses, so the walk home
## starts the way it does in play.
func _play_round(golfers: Array, budget: int) -> bool:
	for i in range(budget):
		var all_leaving := true
		for golfer in golfers:
			if golfer.current_state == 6:  # Golfer.State.LEAVING
				continue
			all_leaving = false
			if golfer.current_state != 2:  # Golfer.State.PREPARING_SHOT
				continue
			golfer.current_strokes = 3
			var hole = gm.current_course.holes[golfer.current_hole]
			golfer.ball_position = hole.hole_position
			golfer.ball_position_precise = Vector2(hole.hole_position)
			golfer._change_state(0)  # Golfer.State.IDLE
		if all_leaving:
			return true
		await process_frame
	return false


## The nearest tile the clubhouse can legally move to, asked of the game rather
## than guessed (the arrival garden and the new hole are in the way).
func _find_move_target(from: Vector2i) -> Vector2i:
	for radius in range(3, 40):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var candidate: Vector2i = from + Vector2i(dx, dy)
				if course_clubhouse.can_move_to(main.terrain_grid, main.entity_layer,
						clubhouse, candidate):
					return candidate
	return Vector2i(-1, -1)


func run() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	gm = root.get_node("GameManager")
	var bus = root.get_node("EventBus")
	course_clubhouse = load("res://scripts/systems/course_clubhouse.gd")
	bus.golfer_left_course.connect(func(id: int): clients.append(id))

	main._on_main_menu_new_game("Clubhouse lifecycle", 0)
	await _frames(6)

	# One hole to play, painted the way a player would.
	main._on_tool_selected(TerrainTypes.Type.TEE_BOX)
	main.undo_manager.begin_stroke()
	main._paint_terrain_stamp(TEE)
	main.undo_manager.end_stroke()
	main._on_tool_selected(TerrainTypes.Type.GREEN)
	main.undo_manager.begin_stroke()
	main._paint_terrain_stamp(CUP)
	main.undo_manager.end_stroke()
	main._on_open_hole_pressed()
	await _frames(6)
	check(gm.current_course.holes.size() == 1, "The test course opens one hole")

	# ------------------------------------------------------------- the clubhouse
	clubhouse = course_clubhouse.find(main.entity_layer)
	check(clubhouse != null, "A course built from nothing gets a clubhouse")
	check(clubhouse.grid_position == course_clubhouse.arrival_corner(),
			"at the arrival corner of the owned land, got %s" % clubhouse.grid_position)
	var door: Vector2i = course_clubhouse.front_tile(clubhouse, main.terrain_grid, main.entity_layer)
	check(door.x >= 0, "The clubhouse has a front door")
	check(not main.entity_layer.is_tile_occupied_by_building(door),
			"Golfers can stand at the door")
	check(gm.current_course.holes[0].tee_position == TEE,
			"and the clubhouse did not land on the hole")

	# The Bulldozer refuses it, through the real click path.
	main._on_bulldozer_pressed()
	main._handle_bulldozer_click(Vector2i(clubhouse.grid_position.x + 1,
			clubhouse.grid_position.y + 1))
	check(course_clubhouse.find(main.entity_layer) == clubhouse,
			"The Bulldozer cannot demolish the clubhouse")
	main._cancel_bulldozer_mode()

	# It can be moved, and the door follows it.
	var old_pos: Vector2i = clubhouse.grid_position
	var moved_to := _find_move_target(old_pos)
	check(moved_to.x >= 0, "There is a legal tile to move the clubhouse to")
	main._on_building_move_requested(clubhouse)
	check(main._moving_building == clubhouse, "Move Clubhouse picks the building up")
	main._handle_building_move_click(moved_to)
	check(clubhouse.grid_position == moved_to,
			"The clubhouse moves to %s, got %s" % [moved_to, clubhouse.grid_position])
	check(main._moving_building == null, "and the move mode ends after the click")
	var new_door: Vector2i = course_clubhouse.front_tile(clubhouse, main.terrain_grid, main.entity_layer)
	check(new_door != door, "The door moves with the building (%s -> %s)" % [door, new_door])
	# Put it back where it belongs before the guests arrive.
	course_clubhouse.move_to(main.entity_layer, clubhouse, old_pos)
	check(clubhouse.grid_position == old_pos, "and it can be moved back")
	await _frames(2)

	# ---------------------------------------------------------------- arriving
	gm.set_mode(gm.GameMode.SIMULATING)
	gm.set_speed(gm.GameSpeed.FAST)
	gm.is_paused = false
	# No other guests during the test: a group spawning ahead would block the
	# guest being watched (traffic is real, but it makes this test a lottery).
	main.golfer_manager.min_spawn_cooldown_seconds = 1000000.0
	var guest_group: int = main.golfer_manager.next_group_id
	var golfer = main.golfer_manager.spawn_golfer("Lifecycle guest", 0.5, guest_group)
	var door_screen: Vector2 = main.terrain_grid.grid_to_screen_center(door)
	check(golfer.current_state == 1,  # Golfer.State.WALKING
			"A new guest starts out walking, got state %d" % golfer.current_state)
	check(golfer.global_position.distance_to(door_screen) < 4.0,
			"A new guest starts at the clubhouse door, %.1f pixels away" %
			golfer.global_position.distance_to(door_screen))

	var tee_screen: Vector2 = main.terrain_grid.grid_to_screen_center(TEE)
	var arrived: bool = await _wait_until(
			func(): return golfer.global_position.distance_to(tee_screen) < 8.0, 6000)
	check(arrived, "The guest walks in from the clubhouse to the first tee")

	# ---------------------------------------------------------------- leaving
	# Play the round out: hole out on every shot until the game ends it.
	var played: bool = await _play_round([golfer], 6000)
	check(played, "The guest plays the hole and the round ends (state %d)"
			% golfer.current_state)
	check(golfer.current_state == 6,  # Golfer.State.LEAVING
			"A finished round walks home, got state %d" % golfer.current_state)

	var inside: bool = await _wait_until(func(): return golfer.current_state == 5, 6000)
	check(inside, "The golfer reaches the clubhouse and goes inside (state %d)"
			% golfer.current_state)
	check(clients.has(golfer.golfer_id), "Leaving the course is announced once")
	var removed: bool = await _wait_until(
			func(): return not main.golfer_manager.get_active_golfers().has(golfer), 900)
	check(removed, "A golfer who has gone inside is taken off the course")

	# A whole group walks home together and leaves once the last one is inside.
	var pair_group: int = main.golfer_manager.next_group_id
	var first = main.golfer_manager.spawn_golfer("Group first", 0.5, pair_group)
	var second = main.golfer_manager.spawn_golfer("Group second", 0.5, pair_group)
	var pair_played: bool = await _play_round([first, second], 6000)
	check(pair_played, "Both partners play their round to the end")
	var both_inside: bool = await _wait_until(_both_inside.bind(first, second), 6000)
	check(both_inside, "Both partners walk home and go inside")
	var group_gone: bool = await _wait_until(_both_gone.bind(first, second), 900)
	check(group_gone, "The group is taken off the course once the last one is inside")

	if failures == 0:
		print("CLUBHOUSE_LIFECYCLE_PASS: a new course gets a clubhouse that cannot be bulldozed but can be moved, and golfers arrive from it, walk home to it and leave")
	quit(1 if failures > 0 else 0)
