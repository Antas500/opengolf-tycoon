extends GutTest
## Unit tests for the IsometricCamera's responsive world scale and the
## touch-gesture pan/zoom API.

var camera: IsometricCamera

func before_each() -> void:
	camera = autofree(IsometricCamera.new())
	add_child(camera)
	camera.set_zoom_level(1.0, true)
	camera._target_position = Vector2.ZERO

func test_apply_world_scale_multiplies_the_rendered_zoom() -> void:
	camera.set_zoom_level(1.0, true)
	camera.apply_world_scale(2.0)
	# Design zoom stays 1.0; the rendered zoom carries the world scale.
	await get_tree().process_frame
	assert_almost_eq(camera.zoom.x, 2.0, 0.001)
	assert_almost_eq(camera.get_zoom_level(), 1.0, 0.001)

func test_zoom_api_works_in_design_units_regardless_of_world_scale() -> void:
	camera.apply_world_scale(3.0)
	camera.set_zoom_level(1.5, true)
	await get_tree().process_frame
	assert_almost_eq(camera.get_zoom_level(), 1.5, 0.001)
	assert_almost_eq(camera.zoom.x, 4.5, 0.001)
	# Clamps still apply in design space (min 0.5 / max 2.0).
	camera.set_zoom_level(9.0, true)
	await get_tree().process_frame
	assert_almost_eq(camera.get_zoom_level(), 2.0, 0.001)

func test_world_scale_is_stable_while_the_player_zooms() -> void:
	camera.apply_world_scale(1.25)
	camera.set_zoom_level(1.0, true)
	await get_tree().process_frame
	var z0: float = camera.zoom.x
	camera.set_zoom_level(2.0, true)
	for i in 10:
		await get_tree().process_frame
	# After the smoothing settles, rendered zoom = 2.0 (design) x 1.25.
	assert_almost_eq(camera.zoom.x / camera.get_zoom_level(), 1.25, 0.01)
	assert_gt(z0, 0.0)

func test_pan_screen_offset_moves_target_by_screen_pixels_over_zoom() -> void:
	camera.set_zoom_level(1.0, true)
	camera.apply_world_scale(2.0)  # rendered zoom 2.0
	camera._target_position = Vector2(100, 50)
	camera.pan_screen_offset(Vector2(20, 10))
	# 20 screen px at rendered zoom 2.0 = 10 world units left.
	assert_eq(camera._target_position, Vector2(90, 45))

func test_zoom_by_factor_keeps_the_anchored_world_point_under_the_center() -> void:
	var vp := get_viewport().get_visible_rect().size
	# Anchor the zoom at the viewport center: the camera center must not move.
	camera.set_zoom_level(1.0, true)
	camera.apply_world_scale(1.0)
	camera._target_position = Vector2(123, 77)
	camera.zoom_by_factor(1.5, vp / 2.0)
	assert_almost_eq(camera._target_zoom, 1.5, 0.001)
	assert_eq(camera._target_position, Vector2(123, 77))

func test_zoom_by_factor_anchors_off_center_points() -> void:
	var vp := get_viewport().get_visible_rect().size
	camera.set_zoom_level(1.0, true)
	camera.apply_world_scale(1.0)
	camera._target_position = Vector2.ZERO
	var center := vp / 2.0 + Vector2(100, -50)
	# The world point under `center` before the zoom:
	var point_before: Vector2 = center - vp / 2.0  # zoom 1.0, position 0
	camera.zoom_by_factor(2.0, center)
	# After zooming to 2.0, the same world point must map to the same screen
	# position: screen = T + (world - 0) * 2  =>  world = (screen - T) / 2.
	var point_after: Vector2 = (center - vp / 2.0) / 2.0 + camera._target_position
	assert_almost_eq(point_after.x, point_before.x, 0.01)
	assert_almost_eq(point_after.y, point_before.y, 0.01)

func test_zoom_by_factor_clamps_to_design_limits() -> void:
	var vp := get_viewport().get_visible_rect().size
	camera.set_zoom_level(1.0, true)
	camera.apply_world_scale(1.0)
	camera.zoom_by_factor(100.0, vp / 2.0)
	assert_eq(camera._target_zoom, 2.0)
	camera.zoom_by_factor(0.001, vp / 2.0)
	assert_eq(camera._target_zoom, 0.5)

func test_apply_world_scale_ignores_non_positive_values() -> void:
	camera.set_zoom_level(1.0, true)
	var before: float = camera.zoom.x
	camera.apply_world_scale(0.0)
	camera.apply_world_scale(-5.0)
	await get_tree().process_frame
	assert_almost_eq(camera.zoom.x, before, 0.001)
