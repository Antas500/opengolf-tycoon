extends Node2D
class_name Building
## Building - Represents a building entity on the course

var building_type: String = "clubhouse"
var grid_position: Vector2i = Vector2i(0, 0)
var width: int = 4
var height: int = 4
var upgrade_level: int = 1  # Current upgrade level (1-3 for clubhouse)
var total_revenue: int = 0  # Lifetime revenue collected by this building

var terrain_grid: TerrainGrid
var building_data: Dictionary = {}

## The architecture node's view rotation, so the sidewalk the drawing shows is
## the side `CourseClubhouse.front_tile()` sends the golfers to.
var _facing: int = 0

signal building_selected(building: Building)
signal building_destroyed(building: Building)

func _ready() -> void:
	add_to_group("buildings")

	# Load building data if not already set
	if building_data.is_empty():
		var buildings_json = FileAccess.open("res://data/buildings.json", FileAccess.READ)
		if buildings_json:
			var data = JSON.parse_string(buildings_json.get_as_text())
			if data and data.has("buildings") and data["buildings"].has(building_type):
				building_data = data["buildings"][building_type]

	# Update size from building data if available
	if building_data.has("size"):
		var size = building_data["size"]
		width = size[0]
		height = size[1]

	# EntityLayer positions the node before adding it to the scene tree. That
	# first position uses the default 4x4 size, which happens to be the
	# clubhouse's footprint but is wrong for every other building. Recalculate
	# once the data-driven footprint is known so the visual stays on its placed
	# grid cells.
	set_position_in_grid(grid_position)
	_update_visuals()

func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		building_selected.emit(self)

func set_terrain_grid(grid: TerrainGrid) -> void:
	terrain_grid = grid

func set_position_in_grid(pos: Vector2i) -> void:
	grid_position = pos
	_update_facing()
	# Calculate world position from grid position
	if terrain_grid:
		if terrain_grid.is_view_isometric():
			var tile_w := float(terrain_grid.tile_width)
			var tile_h := float(terrain_grid.tile_height)
			var center := terrain_grid.grid_point_to_screen(
					Vector2(pos) + Vector2(width * 0.5, height * 0.5))
			global_position = center - Vector2(width * tile_w * 0.5, height * tile_h)
		else:
			global_position = terrain_grid.grid_to_screen(pos)

func get_footprint() -> Array:
	"""Returns array of grid positions occupied by this building"""
	var footprint: Array = []
	for x in range(width):
		for y in range(height):
			footprint.append(grid_position + Vector2i(x, y))
	return footprint

## A required building is part of the course itself: the clubhouse. There can
## only ever be one, it can never be bulldozed, and it is moved rather than
## demolished (see CourseClubhouse). Everything else is optional scenery.
func is_required() -> bool:
	return building_data.get("required", false)

func is_clubhouse() -> bool:
	# Literal "clubhouse" (rather than CourseClubhouse.BUILDING_TYPE) so the
	# building script does not depend on the clubhouse system that places it.
	return building_type == "clubhouse"

## Check if this building can be upgraded
func can_upgrade() -> bool:
	if not building_data.get("upgradeable", false):
		return false
	var upgrades = building_data.get("upgrades", [])
	return upgrade_level < upgrades.size()

## Get cost of next upgrade (returns 0 if can't upgrade)
func get_upgrade_cost() -> int:
	if not can_upgrade():
		return 0
	var upgrades = building_data.get("upgrades", [])
	if upgrade_level < upgrades.size():
		return upgrades[upgrade_level].get("upgrade_cost", 0)
	return 0

## Get current upgrade data
func get_current_upgrade_data() -> Dictionary:
	var upgrades = building_data.get("upgrades", [])
	if upgrade_level > 0 and upgrade_level <= upgrades.size():
		return upgrades[upgrade_level - 1]
	return {}

## Get next upgrade data (for preview)
func get_next_upgrade_data() -> Dictionary:
	var upgrades = building_data.get("upgrades", [])
	if upgrade_level < upgrades.size():
		return upgrades[upgrade_level]
	return {}

## Upgrade to next level
func upgrade() -> bool:
	if not can_upgrade():
		return false

	var cost = get_upgrade_cost()
	if not GameManager.can_afford(cost):
		if GameManager.is_bankrupt():
			EventBus.notify("Spending blocked! Balance below -$1,000", "error")
		else:
			EventBus.notify("Cannot afford upgrade ($%d)" % cost, "error")
		return false

	GameManager.modify_money(-cost)
	EventBus.log_transaction("Upgraded %s" % building_type, -cost)

	upgrade_level += 1

	# Refresh visuals - use call_deferred to avoid race with queue_free
	for child in get_children():
		if child.name == "Visual":
			child.queue_free()
	call_deferred("_update_visuals")

	EventBus.building_upgraded.emit(self, upgrade_level)
	return true

## Get display name based on upgrade level
func get_display_name() -> String:
	var upgrade_data = get_current_upgrade_data()
	if upgrade_data.has("name"):
		return upgrade_data["name"]
	return building_data.get("name", building_type.capitalize())

## Get income per golfer based on upgrade level
func get_income_per_golfer() -> int:
	var upgrade_data = get_current_upgrade_data()
	if upgrade_data.has("income_per_golfer"):
		return upgrade_data["income_per_golfer"]
	return building_data.get("income_per_golfer", 0)

## Get satisfaction bonus based on upgrade level
func get_satisfaction_bonus() -> float:
	var upgrade_data = get_current_upgrade_data()
	if upgrade_data.has("satisfaction_bonus"):
		return upgrade_data["satisfaction_bonus"]
	return 0.0

## Get daily operating cost from building data
func get_operating_cost() -> int:
	return building_data.get("operating_cost", 0)

## Take the building off the course. A required building (the clubhouse) has
## no destroy path at all — callers that might touch one must go through
## CourseClubhouse.move_to instead (or pass force for teardown-only flows).
func destroy(force: bool = false) -> void:
	if is_required() and not force:
		push_warning("Refusing to destroy required building: %s" % building_type)
		return
	building_destroyed.emit(self)
	queue_free()

## Keep the drawing's view rotation in step with the course's.
func _update_facing() -> void:
	if terrain_grid == null:
		return
	_facing = terrain_grid.get_view_orientation()
	var visual := get_node_or_null("Visual/Architecture") as CourseArchitecture
	if visual and visual.facing != _facing:
		visual.facing = _facing
		visual.queue_redraw()

func _update_visuals() -> void:
	"""Create visual representation for the building with shadows"""
	# Remove old visuals and click areas immediately before rebuilding upgrades.
	for child in get_children():
		if child.name in ["Visual", "ClickArea"]:
			remove_child(child)
			child.queue_free()
	# Create a Node2D to hold the visual
	var visual = Node2D.new()
	visual.name = "Visual"
	add_child(visual)

	# The footprint in pixels: one tile is one 64x32 isometric diamond.
	var tile_w = 64
	var tile_h = 32

	var size_x = width * tile_w
	var size_y = height * tile_h

	# All facilities share the same architecture and placement-preview geometry.
	var architecture := CourseArchitecture.new()
	architecture.name = "Architecture"
	architecture.kind = building_type
	architecture.footprint = Vector2(size_x, size_y)
	architecture.level = upgrade_level
	architecture.facing = _facing
	visual.add_child(architecture)

	# Add click detection area
	var click_area = Area2D.new()
	click_area.name = "ClickArea"
	click_area.input_pickable = true
	add_child(click_area)

	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(size_x, size_y)
	collision.shape = shape
	collision.position = Vector2(int(size_x / 2.0), int(size_y / 2.0))
	click_area.add_child(collision)

	# Connect click detection
	click_area.input_event.connect(_on_click_area_input_event)

func get_building_info() -> Dictionary:
	return {
		"type": building_type,
		"position": grid_position,
		"width": width,
		"height": height,
		"cost": building_data.get("cost", 0),
		"upgrade_level": upgrade_level,
		"data": building_data
	}

## Restore building from saved data
func restore_from_info(info: Dictionary) -> void:
	var new_level = info.get("upgrade_level", 1)
	if new_level != upgrade_level:
		upgrade_level = new_level
		# Refresh visuals to match upgraded state
		for child in get_children():
			if child.name == "Visual" or child.name == "ClickArea":
				child.queue_free()
		# Use call_deferred to ensure old nodes are freed first
		call_deferred("_update_visuals")
