extends Node
class_name StaffManager
## StaffManager - Owns the staff roster, payroll, course condition and the staff
## members wandering the course.
##
## Four job types, each with a standard and a premium staff type. Premium staff
## cost more per day but cover a larger designated area, move faster and do their
## job faster. Every hire walks the course inside their area looking for work:
##   Groundskeepers  pull weeds that sprout on the turf
##   Greeters        chat with golfers to cheer them up
##   Marshals        talk groups back to a sensible pace of play
##   Drinks vendors  serve thirsty golfers
##
## Course condition is derived from the weeds left on the course at the end of
## the day — hire groundskeepers and coverage keeps the rating up.

enum Job { GROUNDSKEEPER, GREETER, MARSHAL, DRINKS_VENDOR }
enum Tier { STANDARD, PREMIUM }

## The eight hireable staff types. Standard and premium variants of each job sit
## next to each other so a type's tier is (`type % 2`).
enum StaffType {
	GROUNDSKEEPER,   # Job.GROUNDSKEEPER, standard
	TECHNICIAN,      # Job.GROUNDSKEEPER, premium
	CLUB_PRO,        # Job.GREETER, standard
	CELEBRITY,       # Job.GREETER, premium
	RANGER,          # Job.MARSHAL, standard
	MARSHALL,        # Job.MARSHAL, premium
	SODA_VENDOR,     # Job.DRINKS_VENDOR, standard
	CART_REFRESHER,  # Job.DRINKS_VENDOR, premium
}

## Job-level presentation data, with the two hireable types that fill the role.
const JOB_DATA = {
	Job.GROUNDSKEEPER: {
		"name": "Groundskeepers",
		"role": "Groundskeeper",
		"action": "pull weeds from the course",
		"standard": StaffType.GROUNDSKEEPER,
		"premium": StaffType.TECHNICIAN,
	},
	Job.GREETER: {
		"name": "Greeters",
		"role": "Greeter",
		"action": "chat with golfers to cheer them up",
		"standard": StaffType.CLUB_PRO,
		"premium": StaffType.CELEBRITY,
	},
	Job.MARSHAL: {
		"name": "Marshals",
		"role": "Marshal",
		"action": "keep the pace of play moving",
		"standard": StaffType.RANGER,
		"premium": StaffType.MARSHALL,
	},
	Job.DRINKS_VENDOR: {
		"name": "Drinks Vendors",
		"role": "Drinks Vendor",
		"action": "serve thirsty golfers on the course",
		"standard": StaffType.SODA_VENDOR,
		"premium": StaffType.CART_REFRESHER,
	},
}

## Per-type tuning. `area_radius` is in tiles, `move_speed` in pixels/second and
## `work_speed` scales both how fast a task completes and how strong it is.
const STAFF_DATA = {
	StaffType.GROUNDSKEEPER: {
		"name": "Groundskeeper", "job": Job.GROUNDSKEEPER, "tier": Tier.STANDARD,
		"base_salary": 80, "area_radius": 6.0, "move_speed": 46.0,
		"work_speed": 1.0, "work_seconds": 2.6, "effect": 0.0,
		"description": "Walks a small area pulling weeds. Restores course condition.",
	},
	StaffType.TECHNICIAN: {
		"name": "Technician", "job": Job.GROUNDSKEEPER, "tier": Tier.PREMIUM,
		"base_salary": 155, "area_radius": 11.0, "move_speed": 70.0,
		"work_speed": 1.9, "work_seconds": 2.6, "effect": 0.0,
		"description": "Covers a much larger area, moves faster and clears weeds quickly.",
	},
	StaffType.CLUB_PRO: {
		"name": "Club Pro", "job": Job.GREETER, "tier": Tier.STANDARD,
		"base_salary": 60, "area_radius": 7.0, "move_speed": 48.0,
		"work_speed": 1.0, "work_seconds": 2.0, "effect": 0.06,
		"description": "Chats with golfers in a modest area to lift their mood.",
	},
	StaffType.CELEBRITY: {
		"name": "Celebrity", "job": Job.GREETER, "tier": Tier.PREMIUM,
		"base_salary": 130, "area_radius": 12.0, "move_speed": 72.0,
		"work_speed": 1.8, "work_seconds": 2.0, "effect": 0.1,
		"description": "A name golfers love to meet — a wider area and much bigger mood boost.",
	},
	StaffType.RANGER: {
		"name": "Ranger", "job": Job.MARSHAL, "tier": Tier.STANDARD,
		"base_salary": 50, "area_radius": 8.0, "move_speed": 50.0,
		"work_speed": 1.0, "work_seconds": 1.8, "effect": 0.28,
		"description": "Nudges groups along in a modest area, restoring pace satisfaction.",
	},
	StaffType.MARSHALL: {
		"name": "Marshall", "job": Job.MARSHAL, "tier": Tier.PREMIUM,
		"base_salary": 110, "area_radius": 13.0, "move_speed": 74.0,
		"work_speed": 1.8, "work_seconds": 1.8, "effect": 0.45,
		"description": "Runs a big stretch of the course and gets groups moving again fast.",
	},
	StaffType.SODA_VENDOR: {
		"name": "Soda Vendor", "job": Job.DRINKS_VENDOR, "tier": Tier.STANDARD,
		"base_salary": 40, "area_radius": 6.0, "move_speed": 52.0,
		"work_speed": 1.0, "work_seconds": 1.6, "effect": 0.35,
		"description": "Quenches thirst in a small area of the course.",
	},
	StaffType.CART_REFRESHER: {
		"name": "Cart Refresher", "job": Job.DRINKS_VENDOR, "tier": Tier.PREMIUM,
		"base_salary": 95, "area_radius": 12.0, "move_speed": 78.0,
		"work_speed": 1.9, "work_seconds": 1.6, "effect": 0.6,
		"description": "Runs a drinks cart over a wide area and serves golfers quickly.",
	},
}

signal staff_changed()
signal condition_changed(new_condition: float)
signal staff_spawned(staff_id: int)
signal staff_fired(staff_id: int)

## Hired staff: Array of {
##   staff_id: int, type: StaffType, name: String, salary: int,
##   area_center: Vector2i, area_radius: float
## }
var hired_staff: Array = []

## Course condition: 0.0 (terrible) to 1.0 (pristine)
var course_condition: float = 1.0

var next_staff_id: int = 1

## Set by main.gd: where weeds live and where staff members are parented.
var weed_manager: WeedManager = null
var staff_container: Node2D = null
## staff_id -> StaffMember
var _entities: Dictionary = {}

func set_weed_manager(manager: WeedManager) -> void:
	weed_manager = manager

func set_staff_container(container: Node2D) -> void:
	staff_container = container
	# Any staff hired before the container existed now get their body.
	for record in hired_staff:
		_ensure_entity(record)

func get_staff_data(staff_type: int) -> Dictionary:
	return STAFF_DATA.get(staff_type, {})

func get_job_data(job: int) -> Dictionary:
	return JOB_DATA.get(job, {})

func get_job_for_type(staff_type: int) -> int:
	return int(STAFF_DATA.get(staff_type, {}).get("job", -1))

func get_types_for_job(job: int) -> Array:
	var data: Dictionary = JOB_DATA.get(job, {})
	if data.is_empty():
		return []
	return [data.standard, data.premium]

func get_daily_payroll() -> int:
	var total: int = 0
	for staff in hired_staff:
		total += int(staff.salary)
	return total

func hire_staff(staff_type: int) -> bool:
	var data: Dictionary = STAFF_DATA.get(staff_type, {})
	if data.is_empty():
		return false

	var record := {
		"staff_id": next_staff_id,
		"type": staff_type,
		"salary": int(data.base_salary),
		"name": _generate_staff_name(),
		"area_center": _default_area_center(),
		"area_radius": float(data.area_radius),
	}
	next_staff_id += 1
	hired_staff.append(record)
	_ensure_entity(record)

	staff_changed.emit()
	EventBus.notify("Hired %s ($%d/day)" % [data.name, int(data.base_salary)], "success")
	return true

func fire_staff(index: int) -> bool:
	if index < 0 or index >= hired_staff.size():
		return false
	var record: Dictionary = hired_staff[index]
	var data: Dictionary = STAFF_DATA.get(record.type, {})
	hired_staff.remove_at(index)
	_remove_entity(int(record.staff_id))
	staff_changed.emit()
	staff_fired.emit(int(record.staff_id))
	EventBus.notify("Fired %s" % data.get("name", "Staff"), "info")
	return true

## Move a staff member's designated area to a new grid tile.
func move_staff_area(index: int, center: Vector2i) -> bool:
	if index < 0 or index >= hired_staff.size():
		return false
	var record: Dictionary = hired_staff[index]
	record.area_center = center
	var entity: StaffMember = _entities.get(int(record.staff_id), null)
	if entity and is_instance_valid(entity):
		entity.configure(record, STAFF_DATA.get(record.type, {}))
	staff_changed.emit()
	return true

func get_staff_area(index: int) -> Vector2i:
	if index < 0 or index >= hired_staff.size():
		return Vector2i(-1, -1)
	return hired_staff[index].area_center

func get_staff_count_by_type(staff_type: int) -> int:
	var count := 0
	for staff in hired_staff:
		if int(staff.type) == staff_type:
			count += 1
	return count

func get_staff_count_by_job(job: int) -> int:
	var count := 0
	for staff in hired_staff:
		if get_job_for_type(int(staff.type)) == job:
			count += 1
	return count

func get_staff_count_by_tier(tier: int) -> int:
	var count := 0
	for staff in hired_staff:
		if int(STAFF_DATA.get(int(staff.type), {}).get("tier", -1)) == tier:
			count += 1
	return count

func get_weed_count() -> int:
	var weeds := _weeds()
	return weeds.get_weed_count() if weeds else 0

## The weed manager, preferring the one wired in directly and falling back to the
## GameManager reference (which is how the running game exposes it).
func _weeds() -> WeedManager:
	if weed_manager:
		return weed_manager
	return GameManager.weed_manager

## Called at the end of the day: course condition follows the weeds left on the
## course, softened by groundskeepers' coverage. Payroll is charged separately.
func process_daily_maintenance() -> void:
	var holes := _open_hole_count()
	var weeds := _weeds()
	var pressure := weeds.get_pressure(holes) if weeds else 0.0
	var coverage := clampf(float(get_staff_count_by_job(Job.GROUNDSKEEPER)) / float(maxi(1, holes)), 0.0, 1.0)
	# Weeds the groundcrew never reached still hurt, but a staffed course shrugs
	# off most of the pressure.
	var target := clampf(1.0 - pressure * (1.0 - coverage * 0.7), 0.0, 1.0)
	course_condition = target
	condition_changed.emit(course_condition)

func get_condition_description() -> String:
	if course_condition >= 0.9:
		return "Pristine"
	elif course_condition >= 0.7:
		return "Good"
	elif course_condition >= 0.5:
		return "Fair"
	elif course_condition >= 0.3:
		return "Poor"
	else:
		return "Terrible"

## Marshals keep groups moving. Standard and premium marshals each add to the
## base pace rating, capped at 1.0.
func get_pace_modifier() -> float:
	var modifier := 0.6
	for staff in hired_staff:
		var data: Dictionary = STAFF_DATA.get(int(staff.type), {})
		if int(data.get("job", -1)) != Job.MARSHAL:
			continue
		modifier += 0.12 if int(data.get("tier", 0)) == Tier.STANDARD else 0.2
	return minf(1.0, modifier)

func get_payroll_for_job(job: int) -> int:
	var total := 0
	for staff in hired_staff:
		if get_job_for_type(int(staff.type)) == job:
			total += int(staff.salary)
	return total

# --- Entity lifecycle --------------------------------------------------------

func _ensure_entity(record: Dictionary) -> void:
	if staff_container == null or GameManager.terrain_grid == null:
		return
	var id := int(record.staff_id)
	if _entities.has(id) and is_instance_valid(_entities[id]):
		_entities[id].configure(record, STAFF_DATA.get(int(record.type), {}))
		return
	var member := StaffMember.new()
	member.name = "Staff%d" % id
	member.set_terrain_grid(GameManager.terrain_grid)
	staff_container.add_child(member)
	member.configure(record, STAFF_DATA.get(int(record.type), {}))
	member.global_position = GameManager.terrain_grid.grid_to_screen_center(record.area_center)
	_entities[id] = member
	staff_spawned.emit(id)

func _remove_entity(staff_id: int) -> void:
	var member = _entities.get(staff_id, null)
	_entities.erase(staff_id)
	if member and is_instance_valid(member):
		if member.get_parent():
			member.get_parent().remove_child(member)
		member.queue_free()

func clear_all_staff() -> void:
	for id in _entities.keys():
		_remove_entity(int(id))
	_entities.clear()
	hired_staff.clear()
	next_staff_id = 1
	course_condition = 1.0

func get_entity(staff_id: int) -> StaffMember:
	return _entities.get(staff_id, null)

func _open_hole_count() -> int:
	if GameManager.has_method("get_open_hole_count"):
		return maxi(1, GameManager.get_open_hole_count())
	return 1

func _default_area_center() -> Vector2i:
	var grid: TerrainGrid = GameManager.terrain_grid
	var course = GameManager.current_course
	if course and course.holes.size() > 0:
		var sum := Vector2.ZERO
		var count := 0
		for hole in course.holes:
			sum += Vector2(hole.tee_position)
			count += 1
		if count > 0:
			var avg := sum / float(count)
			return Vector2i(int(avg.x), int(avg.y))
	# No holes yet: base the area at the clubhouse if one exists.
	var layer = GameManager.entity_layer
	if layer and layer.has_method("get_all_buildings"):
		for building in layer.get_all_buildings():
			if building.building_type == "clubhouse":
				return building.grid_position
	if grid:
		return Vector2i(grid.grid_width / 2, grid.grid_height / 2)
	return Vector2i(64, 64)

static func _generate_staff_name() -> String:
	var first_names = ["Alex", "Sam", "Jordan", "Pat", "Chris", "Morgan", "Casey", "Riley", "Quinn", "Drew"]
	var last_initials = ["A", "B", "C", "D", "E", "F", "G", "H", "J", "K", "L", "M", "N", "P", "R", "S", "T", "W"]
	return first_names[randi() % first_names.size()] + " " + last_initials[randi() % last_initials.size()] + "."

## Serialization
func serialize() -> Dictionary:
	var staff_arr: Array = []
	for s in hired_staff:
		var center: Vector2i = s.area_center
		staff_arr.append({
			"staff_id": int(s.staff_id),
			"type": int(s.type),
			"salary": int(s.salary),
			"name": s.get("name", "Staff"),
			"area_center": {"x": center.x, "y": center.y},
			"area_radius": float(s.area_radius),
		})
	return {
		"hired_staff": staff_arr,
		"course_condition": course_condition,
		"next_staff_id": next_staff_id,
	}

func deserialize(data: Dictionary) -> void:
	# Drop the old bodies before rebuilding the roster.
	for id in _entities.keys():
		_remove_entity(int(id))
	_entities.clear()
	hired_staff.clear()
	course_condition = float(data.get("course_condition", 1.0))
	var max_id := 0
	for s in data.get("hired_staff", []):
		var center_data = s.get("area_center", {})
		var center := Vector2i(64, 64)
		if center_data is Dictionary and center_data.has("x"):
			center = Vector2i(int(center_data.x), int(center_data.y))
		elif center_data is Vector2i:
			center = center_data
		var record := {
			"staff_id": int(s.get("staff_id", 0)),
			"type": int(s.type),
			"salary": int(s.salary),
			"name": s.get("name", "Staff"),
			"area_center": center,
			"area_radius": float(s.get("area_radius", STAFF_DATA.get(int(s.type), {}).get("area_radius", 6.0))),
		}
		hired_staff.append(record)
		max_id = maxi(max_id, int(record.staff_id))
	next_staff_id = maxi(int(data.get("next_staff_id", 0)), max_id + 1)
	for record in hired_staff:
		_ensure_entity(record)
	staff_changed.emit()
