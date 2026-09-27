extends Node2D
class_name StaffAreaOverlay
## StaffAreaOverlay - Draws each hired staff member's designated area on the course.
##
## The area is a circle in grid space, so it is projected point-by-point into
## world space to render correctly in both the isometric and top-down views.
## While the player is repositioning an employee (move_staff_area mode) that
## employee's ring is highlighted.

const FILL_ALPHA: float = 0.10
const OUTLINE_ALPHA: float = 0.45
const HIGHLIGHT_FILL_ALPHA: float = 0.22
const HIGHLIGHT_OUTLINE_ALPHA: float = 0.95

var terrain_grid: TerrainGrid = null
## Index into StaffManager.hired_staff currently being repositioned, or -1.
var highlight_index: int = -1

func set_terrain_grid(grid: TerrainGrid) -> void:
	terrain_grid = grid

func _ready() -> void:
	z_index = 1  # Above the opaque terrain, below entities
	var manager = GameManager.staff_manager
	if manager and manager.has_signal("staff_changed"):
		manager.staff_changed.connect(_on_staff_changed)
	if terrain_grid and terrain_grid.has_signal("view_rotated"):
		terrain_grid.view_rotated.connect(func(_o: int, _iso: bool): queue_redraw())
	queue_redraw()

func _on_staff_changed() -> void:
	queue_redraw()

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	if terrain_grid == null or GameManager.staff_manager == null:
		return
	var staff: Array = GameManager.staff_manager.hired_staff
	for i in range(staff.size()):
		var record: Dictionary = staff[i]
		var center: Vector2i = record.get("area_center", Vector2i.ZERO)
		var radius: float = float(record.get("area_radius", 6.0))
		var highlighted := i == highlight_index
		var fill := Color(0.4, 0.85, 0.5, HIGHLIGHT_FILL_ALPHA if highlighted else FILL_ALPHA)
		var outline := Color(1.0, 0.92, 0.55, HIGHLIGHT_OUTLINE_ALPHA) if highlighted \
			else Color(0.45, 0.9, 0.55, OUTLINE_ALPHA)
		var polygon := _projected_circle(Vector2(center), radius)
		if polygon.size() >= 3:
			draw_colored_polygon(polygon, fill)
			draw_polyline(polygon + PackedVector2Array([polygon[0]]), outline, 1.5 if not highlighted else 2.5)

## Sample a grid-space circle and project each point to world space.
func _projected_circle(center_grid: Vector2, radius: float) -> PackedVector2Array:
	var segments := 32
	var points := PackedVector2Array()
	for i in segments:
		var a := (i / float(segments)) * TAU
		var gp := center_grid + Vector2(cos(a), sin(a)) * radius
		points.append(terrain_grid.grid_point_to_screen(gp))
	return points
