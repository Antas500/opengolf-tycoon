extends ColorRect
class_name CourseSurface
## Continuous, world-anchored terrain. Two textures feed the surface shader:
##   R = terrain ID / 255, G = bunker depth, B = (tile elevation + 5) / 10, A reserved.

const PALETTE_KEYS: Array[String] = [
	"empty", "grass", "fairway_light", "rough", "heavy_rough", "green_light",
	"tee_box_light", "bunker", "water", "path", "oob", "grass", "flower_bed", "grass",
]
var _grid: TerrainGrid
var _data: Image
var _texture: ImageTexture
var _elevation_image: Image
var _elevation_texture: ImageTexture
var _palette: ImageTexture
var _dirty := false
var _elevation_dirty := false

func initialize(grid: TerrainGrid) -> void:
	_grid = grid
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_data = Image.create(grid.grid_width, grid.grid_height, false, Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(_data)
	_elevation_image = Image.create(grid.grid_width + 1, grid.grid_height + 1, false, Image.FORMAT_R8)
	_elevation_texture = ImageTexture.create_from_image(_elevation_image)
	var surface_material := ShaderMaterial.new()
	surface_material.shader = preload("res://shaders/course_surface.gdshader")
	surface_material.set_shader_parameter("terrain_data", _texture)
	surface_material.set_shader_parameter("vertex_elevation", _elevation_texture)
	surface_material.set_shader_parameter("vertex_grid_size", Vector2(grid.grid_width + 1, grid.grid_height + 1))
	surface_material.set_shader_parameter("grid_size", Vector2(grid.grid_width, grid.grid_height))
	surface_material.set_shader_parameter("tile_size", Vector2(grid.tile_width, grid.tile_height))
	material = surface_material
	apply_projection(grid.projection)
	refresh_palette()
	rebuild()
	rebuild_elevation()
	grid.tile_changed.connect(_on_tile_changed)
	grid.elevation_changed.connect(_on_elevation_changed)
	EventBus.theme_changed.connect(_on_theme_changed)
	EventBus.load_completed.connect(_on_load_completed)

func apply_projection(proj: GridProjection) -> void:
	if proj == null:
		return
	var bounds := proj.world_bounds()
	position = bounds.position
	size = bounds.size
	if material == null:
		return
	var mat := material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("grid_origin", proj.grid_origin())
	mat.set_shader_parameter("grid_axis_x", proj.axis_x())
	mat.set_shader_parameter("grid_axis_y", proj.axis_y())
	mat.set_shader_parameter("surface_origin", bounds.position)
	mat.set_shader_parameter("surface_size", bounds.size)

func refresh_palette() -> void:
	var colors := Image.create(PALETTE_KEYS.size(), 1, false, Image.FORMAT_RGBA8)
	for i in range(PALETTE_KEYS.size()):
		colors.set_pixel(i, 0, TilesetGenerator.get_color(PALETTE_KEYS[i]))
	_palette = ImageTexture.create_from_image(colors)
	material.set_shader_parameter("palette", _palette)
	material.set_shader_parameter("fringe_color", TilesetGenerator.get_color("fringe"))

func rebuild() -> void:
	for x in range(_grid.grid_width):
		for y in range(_grid.grid_height):
			_write_tile(Vector2i(x, y))
	_dirty = true

func rebuild_elevation() -> void:
	if _elevation_image == null:
		return
	for x in range(_grid.grid_width + 1):
		for y in range(_grid.grid_height + 1):
			_write_vertex(Vector2i(x, y))
	_elevation_dirty = true

func update_vertex(vertex: Vector2i) -> void:
	_write_vertex(vertex)

func _write_vertex(vertex: Vector2i) -> void:
	if _elevation_image == null or not _grid.is_valid_vertex(vertex):
		return
	var gray: float = clampf((float(_grid.get_vertex_elevation(vertex)) + 5.0) / 10.0, 0.0, 1.0)
	_elevation_image.set_pixel(vertex.x, vertex.y, Color(gray, 0.0, 0.0))
	_elevation_dirty = true

func flush_elevation() -> void:
	if _elevation_dirty and _elevation_texture != null:
		_elevation_texture.update(_elevation_image)
		_elevation_dirty = false

func _write_tile(pos: Vector2i) -> void:
	_data.set_pixel(pos.x, pos.y, Color(float(_grid.get_tile(pos)) / 255.0,
		float(_grid.get_bunker_depth(pos)), float(_grid.get_elevation(pos) + 5) / 10.0, 1.0))

func _on_tile_changed(pos: Vector2i, _old: int, _new: int) -> void:
	update_tile(pos)

func _on_elevation_changed(pos: Vector2i, _old: int, _new: int) -> void:
	update_tile(pos)

func update_tile(pos: Vector2i) -> void:
	_write_tile(pos)
	_dirty = true

func _on_theme_changed(_theme: int) -> void:
	refresh_palette()

func _on_load_completed(success: bool) -> void:
	if success:
		rebuild()
		rebuild_elevation()
		refresh_palette()

func _process(_delta: float) -> void:
	# Painting/batch generation uploads at most once per frame, never per tile.
	if _dirty:
		_texture.update(_data)
		_dirty = false
	flush_elevation()

func _exit_tree() -> void:
	if EventBus.theme_changed.is_connected(_on_theme_changed):
		EventBus.theme_changed.disconnect(_on_theme_changed)
	if EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.disconnect(_on_load_completed)
