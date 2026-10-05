extends Control
class_name MenuBackdrop
## The title screen's scenery: a quiet, stylised golf hole drawn in code.
##
## The menu used to sit on a flat dark-green rectangle. This gives it a place
## instead — sky, three rolled hills, a fairway winding up to a green with a
## flag, a bunker, a few trees and slow clouds — without adding any texture
## assets, the same way the World Map's globe and the Rotate buttons draw
## themselves.
##
## Everything is expressed as a share of the control's size, so the same
## drawing fills a phone in portrait and a 2560px desktop without a rebuild.
## The colours stay dark and low-contrast on purpose: cream menu text and the
## menu's own cards have to read over the top of this.
##
## Only the flag and the clouds move (a slow sway and a drift), so the cost is
## a handful of polygons per frame.

## Where the ground starts, as a share of the height.
const HORIZON_SHARE := 0.60
## Bands used for the sky gradient and the edge scrims.
const GRADIENT_BANDS := 32
const SCRIM_BANDS := 14

const SKY_TOP := Color("0a1a15")
const SKY_HORIZON := Color("153527")
const HILL_FAR := Color("14382a")
const HILL_MID := Color("0f2b20")
const HILL_NEAR := Color("0a1f18")
const FAIRWAY_COLOR := Color("1c4a33")
const FAIRWAY_EDGE := Color("173d2a")
const GREEN_COLOR := Color("2c6739")
const FRINGE_COLOR := Color("22502d")
const SAND_COLOR := Color("c2b184")
const TREE_DARK := Color("123526")
const TREE_LIGHT := Color("1b4a33")
const TRUNK_COLOR := Color("3a3423")
const POLE_COLOR := Color("ddd7c4")
const FLAG_COLOR := Color("e5c57c")
const CUP_COLOR := Color("0d2119")
const BALL_COLOR := Color("f4edd9")
const GLOW_COLOR := Color("ffe9a8")
const CLOUD_COLOR := Color(1.0, 1.0, 1.0, 0.05)
const EDGE_COLOR := Color(0.0, 0.02, 0.01)
## Alpha of the scrim at the very top / bottom edge.
const EDGE_ALPHA := 0.35

## Where the green sits, as a share of the control's size. The title screen
## moves it per layout (see MainMenu) so the flag ends up in open sky rather
## than behind a card.
var green_anchor := Vector2(0.82, 0.86):
	set(value):
		green_anchor = value
		queue_redraw()

## Green, bunker, flag and trees are all measured against the control's
## smaller side, so the hole stays in proportion on a tall phone and on a wide
## desktop alike instead of stretching with the window.
const GREEN_RADII_SHARE := Vector2(0.110, 0.065)
const BUNKER_RADII_SHARE := Vector2(0.052, 0.032)
const FLAG_HEIGHT_SHARE := 0.15
const FLAG_WIDTH_SHARE := 0.062
const TREE_UNIT_SHARE := 0.028

## Built from GREEN_RADII_SHARE at the size being drawn.
var _unit := 0.0
var _time := 0.0

func _init() -> void:
	# The menu sits on top of the scenery: never swallow a click.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	# The flag sways and the clouds drift, so the drawing is re-issued every
	# frame. It is a few dozen primitives at most.
	_time += delta
	queue_redraw()

func _draw() -> void:
	var s := size
	if s.x <= 1.0 or s.y <= 1.0:
		return
	var horizon := s.y * HORIZON_SHARE
	_unit = minf(s.x, s.y)
	_draw_sky(s, horizon)
	_draw_glow(s)
	_draw_clouds(s)
	_draw_hills(s, horizon)
	_draw_fairway(s, horizon)
	_draw_green_and_flag(s)
	_draw_trees(s, horizon)
	_draw_edge_scrim(s)

## Vertical sky gradient, band by band (cheaper and sharper than a texture).
func _draw_sky(s: Vector2, horizon: float) -> void:
	var band := horizon / float(GRADIENT_BANDS)
	for i in GRADIENT_BANDS:
		var t := float(i) / float(GRADIENT_BANDS - 1)
		var y := band * float(i)
		draw_rect(Rect2(0.0, y - 1.0, s.x, band + 2.0), SKY_TOP.lerp(SKY_HORIZON, t))
	# Below the horizon the turf keeps darkening towards the bottom edge.
	var below := s.y - horizon
	var turf_band := below / float(GRADIENT_BANDS)
	for i in GRADIENT_BANDS:
		var t := float(i) / float(GRADIENT_BANDS - 1)
		var y := horizon + turf_band * float(i)
		draw_rect(Rect2(0.0, y - 1.0, s.x, turf_band + 2.0), SKY_HORIZON.lerp(HILL_NEAR, t))

## A low sun behind the hills: a stack of faint discs whose overlaps build a
## soft glow with no visible banding.
func _draw_glow(s: Vector2) -> void:
	var center := Vector2(s.x * 0.76, s.y * 0.30)
	var radius := _unit * 0.20
	for i in range(10, 0, -1):
		draw_circle(center, radius * float(i) / 10.0,
			Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.013))

## Clouds: three clusters of overlapping ellipses drifting left to right.
func _draw_clouds(s: Vector2) -> void:
	var span := s.x + 360.0
	var clusters := [
		{"y": 0.16, "scale": 1.0, "speed": 5.0, "x": 0.18},
		{"y": 0.26, "scale": 0.72, "speed": 8.0, "x": 0.62},
		{"y": 0.10, "scale": 0.55, "speed": 11.5, "x": 0.86},
	]
	for cluster in clusters:
		var drift := fposmod(float(cluster["x"]) * span + _time * float(cluster["speed"]), span)
		var center := Vector2(drift - 180.0, s.y * float(cluster["y"]))
		var cloud_scale: float = float(cluster["scale"]) * minf(s.x, s.y) * 0.05
		_ellipse(center, Vector2(cloud_scale * 2.4, cloud_scale * 0.85), CLOUD_COLOR)
		_ellipse(center + Vector2(-cloud_scale * 1.1, cloud_scale * 0.22), Vector2(cloud_scale * 1.5, cloud_scale * 0.7), CLOUD_COLOR)
		_ellipse(center + Vector2(cloud_scale * 1.2, cloud_scale * 0.3), Vector2(cloud_scale * 1.3, cloud_scale * 0.6), CLOUD_COLOR)

## Three rolled hill ridges, far to near, each closed down to the bottom edge.
func _draw_hills(s: Vector2, horizon: float) -> void:
	var colors := [HILL_FAR, HILL_MID, HILL_NEAR]
	for layer in 3:
		var base_y := horizon + s.y * (0.015 + 0.075 * float(layer))
		var amplitude := s.y * (0.030 - 0.005 * float(layer))
		var points := PackedVector2Array()
		var steps := 24
		for i in steps + 1:
			var t := float(i) / float(steps)
			var ridge := 0.5 + 0.5 * sin(t * TAU * (1.5 + float(layer)) + float(layer) * 1.7)
			points.append(Vector2(t * s.x, base_y - amplitude * ridge))
		points.append(Vector2(s.x, s.y))
		points.append(Vector2(0.0, s.y))
		draw_colored_polygon(points, colors[layer])

## A fairway ribbon climbing from the lower left towards the green: two curves
## with a closing taper, so it reads as a hole without any texture work.
func _draw_fairway(s: Vector2, horizon: float) -> void:
	var steps := 20
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var x := s.x * (-0.05 + 0.92 * t)
		var center_y := horizon + s.y * (0.30 - 0.16 * sin(t * PI * 0.85))
		var half := s.y * (0.055 - 0.030 * t)
		upper.append(Vector2(x, center_y - half))
		lower.append(Vector2(x, center_y + half))
	var ribbon := upper
	for i in range(lower.size() - 1, -1, -1):
		ribbon.append(lower[i])
	draw_colored_polygon(ribbon, FAIRWAY_EDGE)
	# Inner stripe: the same ribbon, slightly tighter, for a mown look.
	var inner := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var x := s.x * (-0.05 + 0.92 * t)
		var center_y := horizon + s.y * (0.30 - 0.16 * sin(t * PI * 0.85))
		inner.append(Vector2(x, center_y - s.y * (0.040 - 0.022 * t)))
	for i in range(steps, -1, -1):
		var t := float(i) / float(steps)
		var x := s.x * (-0.05 + 0.92 * t)
		var center_y := horizon + s.y * (0.30 - 0.16 * sin(t * PI * 0.85))
		inner.append(Vector2(x, center_y + s.y * (0.040 - 0.022 * t)))
	draw_colored_polygon(inner, FAIRWAY_COLOR)

## The green, its fringe, a bunker, the cup, the ball and the flagstick. The
## flag cloth sways, which is where the motion in the whole backdrop comes from.
func _draw_green_and_flag(s: Vector2) -> void:
	var center := Vector2(s.x * green_anchor.x, s.y * green_anchor.y)
	var radii := GREEN_RADII_SHARE * _unit

	# Bunker, tucked behind the green.
	_ellipse(center + Vector2(-radii.x * 1.20, radii.y * 0.45), BUNKER_RADII_SHARE * _unit, SAND_COLOR)

	# Fringe ring, then the putting surface.
	_ellipse(center, radii * 1.14, FRINGE_COLOR)
	_ellipse(center, radii, GREEN_COLOR)

	# Pole: from the cup up into the sky.
	var pole_base := center + Vector2(radii.x * -0.18, radii.y * 0.10)
	var pole_length := _unit * FLAG_HEIGHT_SHARE
	var pole_top := pole_base - Vector2(0.0, pole_length)
	var pole_width := maxf(1.5, _unit * 0.0022)
	draw_line(pole_base, pole_top, POLE_COLOR, pole_width, true)

	# Cloth: a small triangle whose tip is pushed around by a two-part sine,
	# so the flag flutters rather than snapping between two poses.
	var cloth_width := _unit * FLAG_WIDTH_SHARE
	var cloth_height := pole_length * 0.30
	var sway := sin(_time * 1.5) * cloth_width * 0.22 + sin(_time * 3.3) * cloth_width * 0.07
	draw_colored_polygon(PackedVector2Array([
		pole_top,
		pole_top + Vector2(cloth_width + sway, cloth_height * 0.34),
		pole_top + Vector2(cloth_width * 0.55 + sway * 0.5, cloth_height * 0.72),
		pole_top + Vector2(0.0, cloth_height),
	]), FLAG_COLOR)

	# Cup and ball on the putting surface.
	var cup := center + Vector2(radii.x * 0.30, radii.y * 0.05)
	_ellipse(cup, Vector2(pole_width * 1.6, pole_width * 1.1), CUP_COLOR)
	var ball_center := center + Vector2(radii.x * 0.72, radii.y * 0.42)
	draw_circle(ball_center, maxf(1.0, _unit * 0.0035), BALL_COLOR)

## Trees on the near ridge: a trunk, a dark canopy and a lit crown.
func _draw_trees(s: Vector2, horizon: float) -> void:
	var spots := [
		{"x": 0.10, "y": 0.20, "scale": 1.0},
		{"x": 0.21, "y": 0.26, "scale": 0.75},
		{"x": 0.34, "y": 0.16, "scale": 0.6},
		{"x": 0.62, "y": 0.24, "scale": 0.85},
		{"x": 0.93, "y": 0.20, "scale": 0.7},
	]
	var unit := _unit * TREE_UNIT_SHARE
	for spot in spots:
		var base := Vector2(s.x * float(spot["x"]), horizon + s.y * float(spot["y"]))
		var tree_scale: float = float(spot["scale"]) * unit
		var trunk := maxf(1.5, tree_scale * 0.16)
		draw_line(base, base - Vector2(0.0, tree_scale * 1.05), TRUNK_COLOR, trunk, true)
		var crown := base - Vector2(0.0, tree_scale * 1.6)
		draw_circle(crown, tree_scale * 0.85, TREE_DARK)
		draw_circle(crown + Vector2(-tree_scale * 0.45, tree_scale * 0.22), tree_scale * 0.55, TREE_DARK)
		draw_circle(crown + Vector2(tree_scale * 0.42, tree_scale * 0.16), tree_scale * 0.48, TREE_LIGHT)

## Darken the top and bottom edges so the title text and the version line have
## something to sit on wherever the window is a different shape.
func _draw_edge_scrim(s: Vector2) -> void:
	var band_h := s.y * 0.12 / float(SCRIM_BANDS)
	for i in SCRIM_BANDS:
		var t := 1.0 - float(i) / float(SCRIM_BANDS)
		var alpha := EDGE_ALPHA * t * t
		draw_rect(Rect2(0.0, band_h * float(i), s.x, band_h + 1.0),
			Color(EDGE_COLOR.r, EDGE_COLOR.g, EDGE_COLOR.b, alpha))
		draw_rect(Rect2(0.0, s.y - band_h * float(i + 1), s.x, band_h + 1.0),
			Color(EDGE_COLOR.r, EDGE_COLOR.g, EDGE_COLOR.b, alpha))

## Fill an axis-aligned ellipse with a polygon (CanvasItem has no draw_ellipse).
func _ellipse(center: Vector2, radii: Vector2, color: Color, segments: int = 40) -> void:
	var points := PackedVector2Array()
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)
