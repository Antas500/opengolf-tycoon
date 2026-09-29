extends Node
class_name ElevationShaderController
## ElevationShaderController - Bridges GDScript and the elevation lighting shader
##
## Syncs light direction with the day/night cycle and weather conditions.
## Camera mapping is handled in the shader via VERTEX world_position.

var _shader_material: ShaderMaterial
var _color_rect: ColorRect
var _terrain_grid: TerrainGrid

func setup(terrain_grid: TerrainGrid, color_rect: ColorRect, shader_material: ShaderMaterial) -> void:
	_terrain_grid = terrain_grid
	_color_rect = color_rect
	_shader_material = shader_material
	apply_projection(terrain_grid.projection)

func apply_projection(proj: GridProjection) -> void:
	if _shader_material == null or proj == null:
		return
	var bounds := proj.world_bounds()
	var vertical_padding: float = 128.0 if proj.isometric else 0.0
	if _color_rect:
		_color_rect.position = bounds.position - Vector2(0.0, vertical_padding)
		_color_rect.size = bounds.size + Vector2(0.0, vertical_padding * 2.0)
	_shader_material.set_shader_parameter("grid_origin", proj.grid_origin())
	_shader_material.set_shader_parameter("grid_axis_x", proj.axis_x())
	_shader_material.set_shader_parameter("grid_axis_y", proj.axis_y())
	_shader_material.set_shader_parameter("surface_origin", bounds.position - Vector2(0.0, vertical_padding))
	if _terrain_grid != null:
		_shader_material.set_shader_parameter("elevation_step_y", _terrain_grid.ELEVATION_STEP_Y)
		_shader_material.set_shader_parameter("is_isometric", _terrain_grid.view_isometric)

func _process(_delta: float) -> void:
	if not _shader_material:
		return

	# Surface relief is always visible; this overlay is for sculpting contours.
	_color_rect.visible = _terrain_grid._elevation_overlay != null and _terrain_grid._elevation_overlay._elevation_active

	# Keep the fixed daytime sun in sync with weather dimming
	_update_light_from_ws()

	# Shader LOD via zoom — disable contours when zoomed far out
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera:
		if camera.zoom.x < 0.3 or not _terrain_grid._elevation_overlay or not _terrain_grid._elevation_overlay._elevation_active:
			_shader_material.set_shader_parameter("contour_enabled", false)
		else:
			_shader_material.set_shader_parameter("contour_enabled", true)

func _update_light_from_ws() -> void:
	# With the day/night cycle removed, the sun sits fixed at a pleasant
	# late-morning angle; weather (not time) supplies light variation.
	var sun_dir: Vector2 = Vector2(0.35, -0.94).normalized()
	_shader_material.set_shader_parameter("light_direction", sun_dir)
	_shader_material.set_shader_parameter("light_intensity", 0.28)
	_shader_material.set_shader_parameter("shadow_intensity", 0.28)

	if _terrain_grid._course_surface:
		_terrain_grid._course_surface.material.set_shader_parameter("relief_light", _shader_material.get_shader_parameter("light_direction"))

	# Weather dimming
	if GameManager.weather_system:
		var weather_mod: float = GameManager.weather_system.get_light_modifier()
		var current_light: float = float(_shader_material.get_shader_parameter("light_intensity"))
		_shader_material.set_shader_parameter("light_intensity", current_light * weather_mod)
