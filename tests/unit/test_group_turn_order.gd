extends GutTest
## Ready golf: the turn passes to the next golfer as soon as the shot in
## progress has come to rest. A partner who is still walking to their ball no
## longer holds the group up — they only do so while they are standing in the
## line of the shot. Before this, every fairway and green shot waited for the
## whole group to reach their ball, so a four-ball spent most of a hole still.

const TEE := Vector2i(4, 8)
const CUP := Vector2i(24, 8)

var fixture: Node2D
var golfers: GolferManager
var grid: TerrainGrid
var saved: Dictionary

func before_each() -> void:
	saved = {"course": GameManager.current_course, "grid": GameManager.terrain_grid,
		"mode": GameManager.current_mode, "speed": GameManager.current_speed,
		"tournament": GameManager.tournament_manager}
	_open_course()
	_build_grid()

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
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)

func after_each() -> void:
	golfers.clear_all_golfers()
	GameManager.tournament_manager = saved.tournament
	GameManager.current_course = saved.course
	GameManager.terrain_grid = saved.grid if is_instance_valid(saved.grid) else null
	GameManager.current_mode = saved.mode
	GameManager.current_speed = saved.speed

## One long par 4: 20 tiles from tee to cup, so a drive and an approach both
## have room to be in the air while somebody else is on the move.
func _open_course() -> void:
	var course := GameManager.CourseData.new()
	var hole := GameManager.HoleData.new()
	hole.hole_number = 1
	hole.par = 4
	hole.distance_yards = 440
	hole.tee_position = TEE
	hole.hole_position = CUP
	course.add_hole(hole)
	GameManager.current_course = course

func _build_grid() -> void:
	grid = TerrainGrid.new()
	grid.grid_width = 40
	grid.grid_height = 16
	add_child_autofree(grid)
	for x in range(grid.grid_width):
		for y in range(grid.grid_height):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.FAIRWAY)
	grid.set_tile(TEE, TerrainTypes.Type.TEE_BOX)
	grid.set_tile(CUP, TerrainTypes.Type.GREEN)
	GameManager.terrain_grid = grid

## A group member standing on `body` (grid coords) with their ball on `ball`.
## The two differ for anyone still walking, which is the whole point of the
## ready-golf check: the body is what a ball would hit.
func _make_golfer(nickname: String, ball: Vector2, body: Vector2, state: int, strokes: int) -> Golfer:
	var golfer := golfers.spawn_tournament_golfer(GolferTier.Tier.SERIOUS, 0)
	golfer.golfer_name = nickname
	golfer.current_hole = 0
	golfer.current_strokes = strokes
	golfer.ball_position = Vector2i(ball.round())
	golfer.ball_position_precise = ball
	golfer.global_position = grid.grid_to_screen_precise(body)
	golfer._change_state(state)
	return golfer

## Pin the shot the golfer intends so the geometry under test is deterministic
## instead of whatever ShotAI decides this frame.
func _aim(golfer: Golfer, target: Vector2i) -> void:
	golfer._cached_shot_target = target
	golfer._cached_shot_target_valid = true

# --- The change itself ---

## The away player goes as soon as the previous ball has come to rest, while
## their partner is still on the way to theirs.
func test_the_next_golfer_plays_while_their_partner_walks_on() -> void:
	var walker := _make_golfer("Walker", Vector2(16, 8), Vector2(5, 8), Golfer.State.WALKING, 1)
	var shooter := _make_golfer("Shooter", Vector2(14, 8), Vector2(14, 8), Golfer.State.IDLE, 1)
	_aim(shooter, CUP)
	var pair: Array[Golfer] = [walker, shooter]

	golfers._update_group(pair)

	assert_eq(shooter.current_state, Golfer.State.PREPARING_SHOT,
		"The turn passes without waiting for the walker to arrive")
	assert_eq(walker.current_state, Golfer.State.WALKING,
		"…and the walker carries on walking")

## What the check measures: a partner whose ball has landed in the landing zone
## is nowhere near it yet while they are still walking back there.
func test_the_check_uses_where_a_partner_stands_not_where_their_ball_landed() -> void:
	var walker := _make_golfer("Walker", Vector2(22, 8), Vector2(5, 8), Golfer.State.WALKING, 1)
	var shooter := _make_golfer("Shooter", Vector2(14, 8), Vector2(14, 8), Golfer.State.IDLE, 1)
	_aim(shooter, CUP)
	var pair: Array[Golfer] = [walker, shooter]

	assert_true(golfers._is_walking_group_clear(shooter, pair),
		"A partner walking up the fairway is clear even though their ball lies in the landing zone")

	walker.global_position = grid.grid_to_screen_precise(Vector2(21, 8))
	assert_false(golfers._is_walking_group_clear(shooter, pair),
		"…and is not clear once they walk into it")

## A partner already at their ball never held a shot up before the change and
## still does not — only walkers are checked.
func test_a_partner_at_rest_never_holds_up_the_shot() -> void:
	var standing := _make_golfer("Standing", Vector2(21, 8), Vector2(21, 8), Golfer.State.IDLE, 1)
	var shooter := _make_golfer("Shooter", Vector2(14, 8), Vector2(14, 8), Golfer.State.IDLE, 1)
	_aim(shooter, CUP)

	assert_true(golfers._is_walking_group_clear(shooter, [standing, shooter] as Array[Golfer]),
		"Standing in the landing zone is fine; walking through it is not")

# --- What still has to hold the group up ---

## The one thing the group does wait for: the shot in progress.
func test_the_group_still_waits_while_the_previous_shot_is_in_the_air() -> void:
	var watcher := _make_golfer("Watcher", Vector2(16, 8), Vector2(16, 8), Golfer.State.WATCHING, 1)
	var shooter := _make_golfer("Shooter", Vector2(14, 8), Vector2(14, 8), Golfer.State.IDLE, 1)
	_aim(shooter, CUP)

	golfers._update_group([watcher, shooter] as Array[Golfer])

	assert_eq(shooter.current_state, Golfer.State.IDLE,
		"Nobody plays while a partner's ball is still in the air")

## A walker in the landing zone of a full swing still holds the shot — the
## blanket walking gate went, the safety did not.
func test_a_partner_walking_into_the_landing_zone_holds_the_shot() -> void:
	var walker := _make_golfer("Walker", Vector2(21, 9), Vector2(21, 8), Golfer.State.WALKING, 1)
	var shooter := _make_golfer("Shooter", Vector2(14, 8), Vector2(14, 8), Golfer.State.IDLE, 1)
	_aim(shooter, CUP)

	golfers._update_group([walker, shooter] as Array[Golfer])

	assert_eq(shooter.current_state, Golfer.State.IDLE,
		"The shot waits for a partner standing where the ball is going")
	assert_false(walker.traffic_blocked or shooter.traffic_blocked,
		"…without blaming the group ahead: it is their own partner in the way")

## On the green the whole route is kept clear, so a putt is never struck while a
## partner is bending over the cup — and goes the moment they step aside.
func test_a_putt_waits_for_a_partner_at_the_cup_and_goes_when_they_step_aside() -> void:
	var partner := _make_golfer("Partner", Vector2(CUP), Vector2(CUP), Golfer.State.WALKING, 2)
	var putter := _make_golfer("Putter", Vector2(23, 8), Vector2(23, 8), Golfer.State.IDLE, 2)
	_aim(putter, CUP)
	var pair: Array[Golfer] = [partner, putter]

	golfers._update_group(pair)
	assert_eq(putter.current_state, Golfer.State.IDLE,
		"The putt waits while a partner stands over the cup")

	partner.global_position = grid.grid_to_screen_precise(Vector2(28, 8))
	golfers._update_group(pair)
	assert_eq(putter.current_state, Golfer.State.PREPARING_SHOT,
		"…and is struck as soon as they step clear of the line")

## The tee keeps its free pass: everyone in the group tees off in turn, so a
## partner walking down the fairway to their drive never holds up the tee.
func test_a_partner_on_the_fairway_never_holds_up_a_tee_shot() -> void:
	var walker := _make_golfer("Walker", Vector2(18, 9), Vector2(18, 8), Golfer.State.WALKING, 1)
	var teeing := _make_golfer("Teeing", Vector2(TEE), Vector2(TEE), Golfer.State.IDLE, 0)
	_aim(teeing, CUP)

	golfers._update_group([walker, teeing] as Array[Golfer])

	assert_eq(teeing.current_state, Golfer.State.PREPARING_SHOT,
		"The group still tees off one after another")
