extends Node2D
class_name AimGuide
## AimGuide - Draws the owner's shot guide while they line up a shot: the intended
## flight arc, the carry point where the ball lands, and the roll that follows it.
##
## The guide is fed by `Golfer.preview_shot()`, which runs the real execution math
## with the random error terms removed. That means the arc/roll drawn here always
## match the physics the swing uses — wind drift, lie, elevation, slope, shot shape
## (fade/draw), punch and backspin all show up without being re-implemented here.
##
## Rendering mirrors the ball animation so the guide predicts what the player sees:
## - Flight uses `Ball`'s bell curve — straight screen-space interpolation plus a
##   mid-flight bend for fade/draw, an arc height of min(distance * 0.3, 150px)
##   scaled by punch (0.3x) or backspin (1.4x), and the cosmetic wind drift.
## - A faint terrain-following ground track is drawn under the arc for depth.
## - Roll is drawn as a dotted ground trail from the carry point to the resting
##   point, and turns red when the ball would finish in water/OB/a bunker (hazard).

const GUIDE_Z_INDEX := 10

## Arc height as a fraction of the carry distance (matches Ball flight arc).
const ARC_HEIGHT_RATIO := 0.3
const MAX_ARC_HEIGHT := 150.0
## Fade/draw mid-flight bend, as a fraction of the ground distance (matches BallManager).
const BEND_FACTOR := 0.06

const ARC_COLOR := Color(1.0, 0.92, 0.35, 0.95)
const GROUND_COLOR := Color(1.0, 0.92, 0.35, 0.20)
const ROLL_COLOR := Color(0.45, 0.86, 1.0, 0.95)
const ROLL_LINE_COLOR := Color(0.45, 0.86, 1.0, 0.35)
const BACKSPIN_COLOR := Color(0.95, 0.72, 1.0, 0.95)
const BLOCKED_COLOR := Color(1.0, 0.42, 0.32, 0.95)
const AIM_COLOR := Color(1.0, 1.0, 1.0, 0.85)
const OUT_OF_RANGE_COLOR := Color(1.0, 0.55, 0.45, 0.85)
const LABEL_SHADOW_COLOR := Color(0, 0, 0, 0.85)

const ARC_STEPS := 28
const LABEL_FONT_SIZE := 13
const SMALL_FONT_SIZE := 12

## Latest `Golfer.preview_shot()` payload; empty while no shot is being lined up.
var preview: Dictionary = {}

func _ready() -> void:
	z_index = GUIDE_Z_INDEX

## Show the guide for a preview payload. An empty payload clears it.
func show_preview(new_preview: Dictionary) -> void:
	if new_preview.is_empty():
		clear()
		return
	preview = new_preview
	queue_redraw()

func clear() -> void:
	if preview.is_empty():
		return
	preview = {}
	queue_redraw()

## Project one preview into screen-space guide geometry.
## Pure and static so tests can assert the arc rises, lands on the carry point and
## hands over to a roll trail without needing a live mouse or a draw pass.
## Returns {} when the preview (or the terrain grid) is unusable.
static func build_geometry(grid: TerrainGrid, aim_preview: Dictionary,
		arc_steps: int = ARC_STEPS) -> Dictionary:
	if grid == null or aim_preview.is_empty():
		return {}
	var origin: Vector2 = aim_preview.get("origin", Vector2.ZERO)
	var carry: Vector2 = aim_preview.get("carry", origin)
	var rest: Vector2 = aim_preview.get("rest", carry)
	if not grid.is_valid_position(Vector2i(origin.round())) or not grid.is_valid_position(Vector2i(carry.round())):
		return {}

	var origin_screen := grid.grid_to_screen_precise(origin)
	var carry_screen := grid.grid_to_screen_precise(carry)
	var rest_screen := grid.grid_to_screen_precise(rest)
	var carry_distance := origin_screen.distance_to(carry_screen)

	# Mid-flight bend for fade/draw, mirroring BallManager: derived from the ground
	# delta, then converted to a screen offset so it survives view rotation.
	var bend_screen := Vector2.ZERO
	var bend_grid := Vector2.ZERO
	var bend_deg: float = aim_preview.get("shape_bend_deg", 0.0)
	if absf(bend_deg) > 0.001:
		var delta := carry - origin
		bend_grid = Vector2(-delta.y, delta.x) * (-signf(bend_deg)) * BEND_FACTOR
		bend_screen = grid.grid_to_screen_precise(bend_grid) - grid.grid_to_screen_precise(Vector2.ZERO)

	var wind_drift := _wind_drift(grid, origin_screen, carry_screen)
	var arc_scale: float = aim_preview.get("arc_scale", 1.0)
	var max_height := minf(carry_distance * ARC_HEIGHT_RATIO, MAX_ARC_HEIGHT) * arc_scale

	var arc := PackedVector2Array()
	var ground_track := PackedVector2Array()
	var steps := maxi(arc_steps, 2)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var swell := sin(t * PI)
		# Terrain-following shadow of the ball's ground path.
		ground_track.append(grid.grid_to_screen_precise(origin.lerp(carry, t) + bend_grid * swell))
		# The arc itself matches the Ball animation: straight screen-space flight
		# with bend and wind drift swelling to the middle and decaying at landing.
		arc.append(origin_screen.lerp(carry_screen, t) + bend_screen * swell
			+ wind_drift * swell - Vector2(0.0, max_height * swell))

	var roll := PackedVector2Array()
	var roll_path: PackedVector2Array = aim_preview.get("roll_path", PackedVector2Array())
	if roll_path.size() >= 2:
		for point in roll_path:
			roll.append(grid.grid_to_screen_precise(point))
	else:
		roll.append(carry_screen)
		roll.append(rest_screen)
	if roll[0].distance_to(carry_screen) > 0.5:
		# The walk starts at the carry point; keep the trail glued to the arc end.
		roll.insert(0, carry_screen)

	return {
		"origin": origin_screen,
		"carry": carry_screen,
		"rest": rest_screen,
		"arc": arc,
		"ground_track": ground_track,
		"roll": roll,
		"apex_height": max_height,
		"carry_distance": carry_distance,
	}

## Cosmetic mid-flight wind drift, computed exactly like BallManager does for the
## animated ball so the guide and the shot share one flight path.
static func _wind_drift(grid: TerrainGrid, origin_screen: Vector2, carry_screen: Vector2) -> Vector2:
	if GameManager.wind_system == null:
		return Vector2.ZERO
	var shot_direction := (carry_screen - origin_screen).normalized()
	if shot_direction == Vector2.ZERO:
		return Vector2.ZERO
	var distance_tiles := origin_screen.distance_to(carry_screen) / grid.tile_width
	# The guide never runs for putters, so any non-zero wind sensitivity club gives
	# the same crosswind direction; Ball uses the club actually played.
	var displacement := GameManager.wind_system.get_wind_displacement(shot_direction, distance_tiles, Golfer.Club.FAIRWAY_WOOD)
	return displacement * grid.tile_width * 0.5

func _draw() -> void:
	if preview.is_empty():
		return
	var grid: TerrainGrid = GameManager.terrain_grid
	var geometry := build_geometry(grid, preview)
	if geometry.is_empty():
		return

	var backspin: bool = preview.get("is_backspin", false)
	var blocked: bool = preview.get("blocked", false)
	var roll_color := BLOCKED_COLOR if blocked else (BACKSPIN_COLOR if backspin else ROLL_COLOR)
	var roll_line_color := Color(roll_color.r, roll_color.g, roll_color.b, ROLL_LINE_COLOR.a)

	# Ground track under the arc (depth cue) and the arc itself.
	draw_polyline(_to_local_many(geometry.ground_track), GROUND_COLOR, 1.5, true)
	draw_polyline(_to_local_many(geometry.arc), ARC_COLOR, 2.5, true)

	# Aim point: crosshair at the clamped target, plus an X on the mouse target
	# when the shot is out of range and the aim had to be reined in.
	_draw_aim_marker(to_local(geometry.origin), to_local(preview.get("aim", Vector2.ZERO)))
	if bool(preview.get("clamped", false)):
		_draw_out_of_range(to_local(preview.get("raw_target", Vector2.ZERO)))

	# Carry point: ring where the ball lands and the first bounce of the roll.
	var carry_point := to_local(geometry.carry)
	draw_arc(carry_point, 8.0, 0.0, TAU, 24, ARC_COLOR, 2.0, true)
	draw_circle(carry_point, 2.0, ARC_COLOR)

	# Roll trail: faint solid line for continuity plus dots for a "rolling" read.
	var roll_points := _to_local_many(geometry.roll)
	if roll_points.size() >= 2:
		draw_polyline(roll_points, roll_line_color, 2.0, true)
		_draw_dotted_trail(roll_points, roll_color)
	_draw_rest_marker(to_local(geometry.rest), roll_color, backspin)

	_draw_labels(geometry, roll_color)

## Crosshair at the aim point plus a short tick back toward the ball.
func _draw_aim_marker(origin: Vector2, aim: Vector2) -> void:
	if origin.distance_to(aim) < 1.0:
		return
	var direction := (aim - origin).normalized()
	draw_line(aim - direction * 12.0, aim - direction * 4.0, AIM_COLOR, 1.5, true)
	draw_line(aim + direction * 4.0, aim + direction * 12.0, AIM_COLOR, 1.5, true)
	var perpendicular := Vector2(-direction.y, direction.x)
	draw_line(aim - perpendicular * 8.0, aim - perpendicular * 3.0, AIM_COLOR, 1.5, true)
	draw_line(aim + perpendicular * 3.0, aim + perpendicular * 8.0, AIM_COLOR, 1.5, true)

## Faint X where the mouse is pointing when the club cannot reach that far.
func _draw_out_of_range(raw_target: Vector2) -> void:
	var size := 6.0
	draw_line(raw_target - Vector2(size, size), raw_target + Vector2(size, size), OUT_OF_RANGE_COLOR, 2.0, true)
	draw_line(raw_target + Vector2(size, -size), raw_target - Vector2(size, -size), OUT_OF_RANGE_COLOR, 2.0, true)

## Ring at the resting point; backspin adds an arrow back toward the ball.
func _draw_rest_marker(rest: Vector2, color: Color, backspin: bool) -> void:
	draw_arc(rest, 6.0, 0.0, TAU, 20, color, 2.0, true)
	if backspin:
		# Arrow pointing back toward the ball: the ball spun backwards.
		draw_line(rest + Vector2(-7.0, 0.0), rest + Vector2(7.0, 0.0), color, 2.0, true)
		draw_line(rest + Vector2(7.0, 0.0), rest + Vector2(3.0, -4.0), color, 2.0, true)
		draw_line(rest + Vector2(7.0, 0.0), rest + Vector2(3.0, 4.0), color, 2.0, true)
	else:
		draw_circle(rest, 2.0, color)

## Dotted trail along the roll polyline (dots spaced by arc length).
func _draw_dotted_trail(points: PackedVector2Array, color: Color) -> void:
	const DOT_SPACING := 9.0
	const DOT_RADIUS := 2.4
	var carry_over := 0.0
	for i in range(points.size() - 1):
		var from := points[i]
		var to := points[i + 1]
		var segment := from.distance_to(to)
		if segment <= 0.001:
			continue
		var direction := (to - from) / segment
		var distance := carry_over
		while distance < segment:
			draw_circle(from + direction * distance, DOT_RADIUS, color)
			distance += DOT_SPACING
		carry_over = distance - segment
	# Always mark the trail's end so short rolls stay readable.
	draw_circle(points[points.size() - 1], DOT_RADIUS, color)

## Club / carry / roll readout above the ball, plus a roll caption at the rest point.
func _draw_labels(geometry: Dictionary, roll_color: Color) -> void:
	var font := ThemeDB.fallback_font
	var club_name: String = preview.get("club_name", "Shot")
	var carry_yards: int = preview.get("carry_yards", 0)
	var roll_yards: int = preview.get("roll_yards", 0)
	var backspin: bool = preview.get("is_backspin", false)
	var head := "%s · %d yd carry" % [club_name, carry_yards]
	if preview.get("punch", false):
		head += " · punch"
	var shape_bend: float = preview.get("shape_bend_deg", 0.0)
	if absf(shape_bend) > 0.001:
		head += " · fade" if shape_bend > 0.0 else " · draw"
	elif int(preview.get("shape", 0)) == 3:
		head += " · backspin"
	# Out-of-range is reported next to the club, clear of the roll captions below.
	if bool(preview.get("clamped", false)):
		head += " · out of range"
	_draw_outlined_text(font, to_local(geometry.origin) + Vector2(-6.0, -18.0), head, Color(1, 1, 1, 0.92))

	# Roll captions stack under the resting point: roll distance, then any hazard
	# the ball finished in. Short rolls skip the caption to keep the point clean.
	var rest := to_local(geometry.rest)
	var caption_lines: Array[Dictionary] = []
	if roll_yards >= 5:
		caption_lines.append({
			"text": "backspin %d yd" % roll_yards if backspin else "roll %d yd" % roll_yards,
			"color": roll_color,
			"size": LABEL_FONT_SIZE,
		})
	if bool(preview.get("blocked", false)):
		caption_lines.append({
			"text": "%s!" % str(preview.get("blocked_terrain", "hazard")).to_lower(),
			"color": BLOCKED_COLOR,
			"size": SMALL_FONT_SIZE,
		})
	for i in caption_lines.size():
		var line: Dictionary = caption_lines[i]
		_draw_outlined_text(font, rest + Vector2(10.0, 18.0 + 17.0 * i), line.text, line.color, line.size)

func _draw_outlined_text(font: Font, pos: Vector2, text: String, color: Color,
		font_size: int = LABEL_FONT_SIZE) -> void:
	font.draw_string_outline(get_canvas_item(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, 4, LABEL_SHADOW_COLOR)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _to_local_many(points: PackedVector2Array) -> PackedVector2Array:
	var local_points := PackedVector2Array()
	for point in points:
		local_points.append(to_local(point))
	return local_points
