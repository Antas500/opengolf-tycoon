extends Node2D
class_name StaffMember
## StaffMember - A hired employee wandering their designated area doing their job.
##
## Each staff member is tied to one grid-tile circle ("designated area"). They
## wander inside it looking for work:
##   Groundskeepers  pull weeds that sprout on the turf
##   Greeters        chat with golfers to cheer them up
##   Marshals        talk to groups to keep the pace of play moving
##   Drinks vendors  serve thirsty golfers a drink
##
## The manager owns the roster; this node only knows the one employee's data and
## pulls live golfer/weed state from GameManager each time it looks for a task.

enum State { IDLE, WALKING, WORKING }

const ARRIVE_DISTANCE: float = 8.0
## How close a golfer must stay for a service to land when the work finishes.
const SERVICE_RANGE_TILES: float = 2.5

## Job accent colours (indexed by StaffManager.Job).
const JOB_COLORS: Array = [
	Color(0.24, 0.5, 0.28),   # Groundskeeper - fairway green
	Color(0.85, 0.72, 0.3),   # Greeter - club gold
	Color(0.35, 0.5, 0.85),   # Marshal - rulebook blue
	Color(0.85, 0.42, 0.3),   # Drinks vendor - soda red
]

var staff_id: int = -1
var staff_type: int = 0
var job: int = 0
var is_premium: bool = false
var display_name: String = "Staff"

var area_center: Vector2i = Vector2i(64, 64)
var area_radius: float = 6.0

var move_speed: float = 46.0
var work_seconds: float = 2.4
var work_speed: float = 1.0
var effect: float = 0.05

var terrain_grid: TerrainGrid = null

var _state: State = State.IDLE
var _target_world: Vector2 = Vector2.ZERO
var _work_weed: Vector2i = Vector2i(-1, -1)
var _work_golfer = null
var _timer: float = 0.0
var _bob: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	z_index = 3
	queue_redraw()

func set_terrain_grid(grid: TerrainGrid) -> void:
	terrain_grid = grid

## Apply the manager's record + static data. Called on hire and whenever the
## designated area is moved.
func configure(record: Dictionary, data: Dictionary) -> void:
	staff_id = int(record.get("staff_id", staff_id))
	staff_type = int(record.get("type", staff_type))
	display_name = String(record.get("name", display_name))
	area_center = record.get("area_center", area_center)
	area_radius = float(record.get("area_radius", data.get("area_radius", area_radius)))
	job = int(data.get("job", job))
	is_premium = int(data.get("tier", 0)) == 1
	move_speed = float(data.get("move_speed", move_speed))
	work_seconds = float(data.get("work_seconds", work_seconds))
	work_speed = float(data.get("work_speed", work_speed))
	effect = float(data.get("effect", effect))
	# Re-home the wander target inside the (possibly new) area.
	_state = State.IDLE
	_timer = _rng.randf_range(0.1, 0.6)
	queue_redraw()

func _process(delta: float) -> void:
	if GameManager.is_paused or GameManager.current_speed == GameManager.GameSpeed.PAUSED:
		return
	if terrain_grid == null:
		return
	match _state:
		State.IDLE:
			_timer -= delta
			if _timer <= 0.0:
				_choose_task()
		State.WALKING:
			_process_walking(delta)
		State.WORKING:
			_process_working(delta)

func _process_walking(delta: float) -> void:
	if global_position.distance_to(_target_world) <= ARRIVE_DISTANCE:
		global_position = _target_world
		_arrive()
		return
	global_position = global_position.move_toward(_target_world, move_speed * delta)
	_bob += delta * 9.0
	queue_redraw()

func _process_working(delta: float) -> void:
	# Keep facing a moving golfer without abandoning the conversation.
	if _work_golfer and is_instance_valid(_work_golfer):
		_target_world = _work_golfer.global_position
	_timer -= delta
	if _timer <= 0.0:
		_complete_work()

func _arrive() -> void:
	if _work_weed != Vector2i(-1, -1) or _work_golfer != null:
		_state = State.WORKING
		_timer = work_seconds / maxf(work_speed, 0.1)
	else:
		_state = State.IDLE
		_timer = _rng.randf_range(0.4, 1.6)

# --- Task selection ----------------------------------------------------------

func _choose_task() -> void:
	_work_weed = Vector2i(-1, -1)
	_work_golfer = null
	var found := false
	match job:
		StaffManager.Job.GROUNDSKEEPER:
			found = _seek_weed()
		StaffManager.Job.GREETER:
			found = _seek_golfer(func(g): return 1.0 - g.current_mood + (0.0 if g.needs.thirst > 0.5 else 0.15))
		StaffManager.Job.MARSHAL:
			found = _seek_golfer(func(g): return g.needs.pace + (0.5 if g.traffic_blocked else 0.0))
		StaffManager.Job.DRINKS_VENDOR:
			found = _seek_golfer(func(g): return g.needs.thirst + (0.1 if g.current_mood < 0.5 else 0.0))
	if not found:
		_wander()

func _seek_weed() -> bool:
	var weed_manager = GameManager.weed_manager
	if weed_manager == null:
		return false
	var pos: Vector2i = weed_manager.find_closest_weed(_grid_point(), area_radius)
	if pos == Vector2i(-1, -1):
		return false
	_work_weed = pos
	_target_world = terrain_grid.grid_to_screen_center(pos)
	_state = State.WALKING
	return true

func _seek_golfer(scorer: Callable) -> bool:
	var golfer_manager = GameManager.golfer_manager
	if golfer_manager == null:
		return false
	var active = golfer_manager.get("active_golfers")
	if active == null:
		return false
	var best = null
	var best_score := INF
	for golfer in active:
		if golfer == null or not is_instance_valid(golfer):
			continue
		if not golfer.is_staff_service_available():
			continue
		var golfer_grid: Vector2 = terrain_grid.screen_to_grid_point(golfer.global_position)
		if golfer_grid.distance_to(Vector2(area_center)) > area_radius:
			continue
		var score: float = scorer.call(golfer)
		if score < best_score:
			best_score = score
			best = golfer
	if best == null:
		return false
	_work_golfer = best
	_target_world = best.global_position
	_state = State.WALKING
	return true

func _wander() -> void:
	var angle := _rng.randf() * TAU
	var radius := area_radius * sqrt(_rng.randf())
	var grid_target := Vector2(area_center) + Vector2(cos(angle), sin(angle)) * radius
	grid_target.x = clampf(grid_target.x, 0.0, terrain_grid.grid_width - 1)
	grid_target.y = clampf(grid_target.y, 0.0, terrain_grid.grid_height - 1)
	_target_world = terrain_grid.grid_point_to_screen(grid_target)
	_state = State.WALKING

func _complete_work() -> void:
	match job:
		StaffManager.Job.GROUNDSKEEPER:
			if _work_weed != Vector2i(-1, -1) and GameManager.weed_manager:
				GameManager.weed_manager.remove_weed(_work_weed)
		StaffManager.Job.GREETER:
			_service_golfer("receive_greeting")
		StaffManager.Job.MARSHAL:
			_service_golfer("receive_pace_help")
		StaffManager.Job.DRINKS_VENDOR:
			_service_golfer("receive_drink")
	_work_weed = Vector2i(-1, -1)
	_work_golfer = null
	_state = State.IDLE
	_timer = _rng.randf_range(0.5, 1.8)

func _service_golfer(method: String) -> void:
	if _work_golfer == null or not is_instance_valid(_work_golfer):
		return
	var golfer_grid: Vector2 = terrain_grid.screen_to_grid_point(_work_golfer.global_position)
	if golfer_grid.distance_to(_grid_point()) > SERVICE_RANGE_TILES:
		return
	if not _work_golfer.has_method(method):
		return
	_work_golfer.call(method, effect * work_speed)

func _grid_point() -> Vector2:
	return terrain_grid.screen_to_grid_point(global_position)

# --- Visuals -----------------------------------------------------------------

func _draw() -> void:
	var bob := sin(_bob) * 1.2 if _state == State.WALKING else 0.0
	# Soft ground shadow.
	var shadow := _ellipse_points(Vector2(0, 0), 10.0, 4.5)
	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.22))

	var base: Color = JOB_COLORS[job] if job >= 0 and job < JOB_COLORS.size() else Color.WHITE
	var accent: Color = Color(0.9, 0.78, 0.35) if is_premium else base.darkened(0.3)
	if is_premium:
		base = base.lightened(0.12)

	var y := bob
	# Legs
	draw_rect(Rect2(-5, -10 + y, 4, 10), base.darkened(0.35))
	draw_rect(Rect2(1, -10 + y, 4, 10), base.darkened(0.35))
	# Torso / overalls
	draw_rect(Rect2(-6, -22 + y, 12, 13), base)
	# Arms
	draw_rect(Rect2(-9, -21 + y, 3, 10), base.darkened(0.15))
	draw_rect(Rect2(6, -21 + y, 3, 10), base.darkened(0.15))
	# Head
	draw_circle(Vector2(0, -27 + y), 5.0, Color(0.93, 0.79, 0.68))
	# Cap: premium staff get a gold band.
	draw_rect(Rect2(-7, -32 + y, 14, 3), accent)
	draw_rect(Rect2(-5, -36 + y, 10, 5), accent.darkened(0.1))
	# Premium badge so the upgraded hire reads at a glance.
	if is_premium:
		draw_circle(Vector2(0, -18 + y), 2.2, Color(1.0, 0.9, 0.5))

func _ellipse_points(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 20:
		var a := (i / 20.0) * TAU
		points.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return points
