extends Node2D
class_name TerrainGrid
## TerrainGrid - Manages the tile grid for the golf course

@export var grid_width: int = 128
@export var grid_height: int = 128
@export var tile_width: int = 64
@export var tile_height: int = 32
@export var view_isometric: bool = true
@export_range(0, 3) var view_orientation: int = 0

## Grid <-> world projection shared by every renderer and the input handlers.
var projection: GridProjection = GridProjection.new()

const MIN_ELEVATION: int = -5
const MAX_ELEVATION: int = 5
const SLOPE_SAMPLE_STEP: float = 0.5
const ELEVATION_STEP_Y: float = 10.0

var _grid: Dictionary = {}
var _vertex_elevation: PackedInt32Array = PackedInt32Array()  # (grid_width+1) * (grid_height+1)
var _vertex_stride: int = 0  # Row length of _vertex_elevation (grid_width + 1)
var _bunker_depth_grid: Dictionary = {}  # Vector2i -> 0 (SHALLOW) or 1 (DEEP)
var _player_placed_tiles: Dictionary = {}  # Vector2i -> true for tiles player placed (for maintenance)
## Green tiles carrying a cup that is not yet part of a hole — a "Green With Hole" tile
## waiting to be paired with a tee box. Once a hole is opened the marker is consumed and
## the cup lives on as the hole's `hole_position`, so every marker here is unused.
var _cup_tiles: Dictionary = {}  # Vector2i -> true
## Index of TEE_BOX tiles, kept in step with _grid so the tee placement rule
## ("no waiting tee box on the course") is a dictionary lookup, not a grid scan.
var _tee_box_tiles: Dictionary = {}  # Vector2i -> true
var _elevation_overlay: ElevationOverlay = null
var _course_surface: CourseSurface = null
var _wildlife: CourseWildlife = null

@onready var tile_map: TileMapLayer = $TileMapLayer if has_node("TileMapLayer") else null

signal surface_refreshed
signal tile_changed(position: Vector2i, old_type: int, new_type: int)
signal elevation_changed(position: Vector2i, old_elevation: int, new_elevation: int)
signal vertex_elevation_changed(vertex: Vector2i, old_elevation: int, new_elevation: int)
signal view_rotated(orientation: int, isometric: bool)
## Emitted whenever a "Green With Hole" (cup) marker is added or removed.
signal cup_tiles_changed

## Batch mode — defers signals until end_batch() to avoid overlay redraw cascade
var _batch_mode: bool = false
var _batch_changes: Array = []  # Array of {pos, old_type, new_type}

var _ob_markers_overlay: OBMarkersOverlay = null
var _cup_overlay: CupOverlay = null
var _water_overlay: WaterOverlay = null
var _bunker_overlay: BunkerOverlay = null
var _grass_overlay: GrassOverlay = null
var _fairway_overlay: FairwayOverlay = null
var _tree_overlay: TreeOverlay = null
var _rock_overlay: RockOverlay = null
var _flower_overlay: FlowerOverlay = null
var _path_overlay: PathOverlay = null
var _debug_overlay: TerrainDebugOverlay = null
var _land_boundary_overlay: LandBoundaryOverlay = null
var _wind_flag_overlay: WindFlagOverlay = null
var _shot_heatmap_overlay: ShotHeatmapOverlay = null
var _fairway_width_overlay: FairwayWidthOverlay = null

## Shader-driven heightmap elevation system
var _heightmap: Heightmap = null
var _elevation_shader_controller: ElevationShaderController = null
var _elevation_shader_rect: ColorRect = null

## Camera tracking for viewport-culling overlays — redraw when camera moves
var _last_camera_pos: Vector2 = Vector2.ZERO
var _last_camera_zoom: float = 1.0

func _ready() -> void:
	_init_projection()
	_course_surface = CourseSurface.new()
	# Variation shader disabled — it overwrites TilesetGenerator's mowing stripe
	# patterns on fairways/greens. The FairwayOverlay handles stripes instead.
	#_apply_variation_shader()
	_initialize_grid()
	_course_surface.name = "CourseSurface"
	add_child(_course_surface)
	_course_surface.initialize(self)
	if tile_map:
		tile_map.hide()
	_setup_ob_markers_overlay()
	_setup_cup_overlay()
	# The continuous surface supplies turf, sand, water, and paths on every platform.
	# Keep the legacy overlay classes available for older tools, but don't double draw.
	# TreeOverlay and RockOverlay disabled — entities render their own sprites.
	# TREES/ROCKS terrain tiles use grass color to blend invisibly.
	_setup_flower_overlay()
	_setup_elevation_overlay()
	_setup_debug_overlay()
	_setup_noise_overlay()
	_setup_land_boundary_overlay()
	_setup_wind_flag_overlay()
	_setup_elevation_shader()
	_setup_fairway_width_overlay()
	_wildlife = CourseWildlife.new()
	_wildlife.name = "CourseWildlife"
	add_child(_wildlife)
	_wildlife.initialize(self)

	# Force a complete redraw after one frame to ensure shader is fully applied
	# This fixes the issue where initial tiles don't get shader variation
	call_deferred("_refresh_all_tiles")

func _process(_delta: float) -> void:
	# Flush any pending heightmap blur + texture uploads (batched for performance)
	if _heightmap:
		_heightmap.flush_dirty()
	# Overlays use viewport culling in _draw() so their content depends on
	# camera position. Redraw them when the camera has moved.
	var camera = get_viewport().get_camera_2d() if get_viewport() else null
	if not camera:
		return
	var cam_pos = camera.global_position
	var cam_zoom = camera.zoom.x
	if cam_pos != _last_camera_pos or cam_zoom != _last_camera_zoom:
		_last_camera_pos = cam_pos
		_last_camera_zoom = cam_zoom
		_redraw_all_overlays()

func _refresh_all_tiles() -> void:
	# Force redraw of all tiles to ensure shader is applied correctly
	# This is called deferred after _ready() to fix initial tile rendering
	if not tile_map:
		return
	for x in range(grid_width):
		for y in range(grid_height):
			_update_tile_visual(Vector2i(x, y))
	# Also force the TileMapLayer to redraw
	tile_map.queue_redraw()

func _generate_tileset() -> void:
	if not tile_map:
		return
	# Generate expanded textured tileset with autotile variants at runtime
	var texture = TilesetGenerator.generate_expanded_tileset()
	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(tile_width, tile_height)

	var source = TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(tile_width, tile_height)

	# Create tiles for expanded atlas (16 columns, 16 rows)
	for row in range(TilesetGenerator.ATLAS_ROWS):
		for col in range(TilesetGenerator.ATLAS_COLS):
			source.create_tile(Vector2i(col, row))

	tileset.add_source(source)
	tile_map.tile_set = tileset

## Regenerate the tileset (e.g. after theme change)
func regenerate_tileset() -> void:
	if _course_surface:
		_course_surface.refresh_palette()
		_course_surface.rebuild()
		_redraw_all_overlays()
		return
	_generate_tileset()
	#_apply_variation_shader()  # Re-apply shader with new theme colors
	# Re-render all existing tiles and overlays
	queue_redraw()
	if tile_map:
		tile_map.queue_redraw()
	_redraw_all_overlays()

func _redraw_all_overlays() -> void:
	if _cup_overlay:
		_cup_overlay.queue_redraw()
	if _wildlife:
		_wildlife.queue_redraw()
	if _water_overlay:
		_water_overlay.queue_redraw()
	if _bunker_overlay:
		_bunker_overlay.queue_redraw()
	if _grass_overlay:
		_grass_overlay.queue_redraw()
	if _fairway_overlay:
		_fairway_overlay.queue_redraw()
	if _tree_overlay:
		_tree_overlay.queue_redraw()
	if _rock_overlay:
		_rock_overlay.queue_redraw()
	if _flower_overlay:
		_flower_overlay.queue_redraw()
	if _path_overlay:
		_path_overlay.queue_redraw()
	if _shot_heatmap_overlay:
		_shot_heatmap_overlay.queue_redraw()

func _apply_variation_shader() -> void:
	if not tile_map:
		return

	# Use lighter shader on web for WebGL 2.0 performance
	var shader_path: String
	if OS.get_name() == "Web" and ResourceLoader.exists("res://shaders/terrain_variation_web.gdshader"):
		shader_path = "res://shaders/terrain_variation_web.gdshader"
	elif ResourceLoader.exists("res://shaders/terrain_variation.gdshader"):
		shader_path = "res://shaders/terrain_variation.gdshader"
	else:
		return

	var shader: Shader = load(shader_path) as Shader
	if not shader:
		return

	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = shader

	# Atlas layout for proper tile center sampling
	shader_material.set_shader_parameter("tile_size", Vector2(tile_width, tile_height))
	shader_material.set_shader_parameter("atlas_size", Vector2(
		TilesetGenerator.TILE_WIDTH * TilesetGenerator.ATLAS_COLS,
		TilesetGenerator.TILE_HEIGHT * TilesetGenerator.ATLAS_ROWS
	))

	# Get terrain base colors from theme (shader detects terrain type and uses these)
	var grass = TilesetGenerator.get_color("grass")
	var fairway = TilesetGenerator.get_color("fairway_light")
	var green = TilesetGenerator.get_color("green_light")
	var rough = TilesetGenerator.get_color("rough")
	var heavy_rough = TilesetGenerator.get_color("heavy_rough")

	shader_material.set_shader_parameter("grass_color", Vector3(grass.r, grass.g, grass.b))
	shader_material.set_shader_parameter("fairway_color", Vector3(fairway.r, fairway.g, fairway.b))
	shader_material.set_shader_parameter("green_color", Vector3(green.r, green.g, green.b))
	shader_material.set_shader_parameter("rough_color", Vector3(rough.r, rough.g, rough.b))
	shader_material.set_shader_parameter("heavy_rough_color", Vector3(heavy_rough.r, heavy_rough.g, heavy_rough.b))

	# Procedural variation amounts
	shader_material.set_shader_parameter("hue_variation", 0.04)
	shader_material.set_shader_parameter("value_variation", 0.18)
	shader_material.set_shader_parameter("saturation_variation", 0.06)

	tile_map.material = shader_material

func _initialize_grid() -> void:
	_ensure_vertex_storage()
	_tee_box_tiles.clear()
	for x in range(grid_width):
		for y in range(grid_height):
			var pos = Vector2i(x, y)
			_grid[pos] = TerrainTypes.Type.GRASS
			_update_tile_visual(pos)

func _init_projection() -> void:
	projection.configure(Vector2i(grid_width, grid_height), Vector2(tile_width, tile_height))
	projection.set_isometric(view_isometric)
	projection.set_orientation(view_orientation)
	view_orientation = projection.orientation

func get_elevation_displacement(grid_pos: Vector2) -> Vector2:
	if not view_isometric or ELEVATION_STEP_Y == 0.0:
		return Vector2.ZERO
	return Vector2(0.0, -get_elevation_at(grid_pos) * ELEVATION_STEP_Y)

func get_vertex_elevation_displacement(vertex: Vector2i) -> Vector2:
	if not view_isometric or ELEVATION_STEP_Y == 0.0:
		return Vector2.ZERO
	return Vector2(0.0, -float(get_vertex_elevation(vertex)) * ELEVATION_STEP_Y)

func screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var g := screen_to_grid_point(screen_pos)
	return Vector2i(floori(g.x), floori(g.y))

func screen_to_grid_precise(screen_pos: Vector2) -> Vector2:
	return screen_to_grid_point(screen_pos) - Vector2(0.5, 0.5)

func screen_to_grid_point(screen_pos: Vector2) -> Vector2:
	if not view_isometric or ELEVATION_STEP_Y == 0.0:
		return projection.unproject(screen_pos)

	# Raymarch vertically from highest elevation to lowest to find the front-most surface
	var best_g := projection.unproject(screen_pos)
	var best_diff: float = 999999.0
	var step_size: float = ELEVATION_STEP_Y * 0.5
	var t: float = float(MAX_ELEVATION) * ELEVATION_STEP_Y
	var min_t: float = float(MIN_ELEVATION) * ELEVATION_STEP_Y

	while t >= min_t - 0.1:
		var g := projection.unproject(screen_pos + Vector2(0.0, t))
		var h_px: float = get_elevation_at(g) * ELEVATION_STEP_Y
		var diff: float = absf(t - h_px)
		if diff < best_diff:
			best_diff = diff
			best_g = g
		if t <= h_px:
			# Surface crossed: refine with exact height at this point
			var h_final: float = get_elevation_at(g) * ELEVATION_STEP_Y
			best_g = projection.unproject(screen_pos + Vector2(0.0, h_final))
			return best_g
		t -= step_size

	return best_g

func grid_to_screen(grid_pos: Vector2i) -> Vector2:
	return projection.cell_corner(grid_pos) + get_vertex_elevation_displacement(grid_pos)

func grid_to_screen_center(grid_pos: Vector2i) -> Vector2:
	# Returns the center of the tile (for entity positioning)
	return projection.cell_center(grid_pos) + get_elevation_displacement(Vector2(grid_pos) + Vector2(0.5, 0.5))

func grid_to_screen_precise(grid_pos: Vector2) -> Vector2:
	# Returns screen position for a sub-tile grid coordinate (used for putting precision)
	var pos := grid_pos + Vector2(0.5, 0.5)
	return projection.project(pos) + get_elevation_displacement(pos)

func grid_point_to_screen(grid_pos: Vector2) -> Vector2:
	return projection.project(grid_pos) + get_elevation_displacement(grid_pos)

func tile_polygon(grid_pos: Vector2i) -> PackedVector2Array:
	var p := Vector2(grid_pos)
	return PackedVector2Array([
		grid_point_to_screen(p),
		grid_point_to_screen(p + Vector2(1, 0)),
		grid_point_to_screen(p + Vector2(1, 1)),
		grid_point_to_screen(p + Vector2(0, 1)),
	])

func tile_world_rect(grid_pos: Vector2i) -> Rect2:
	return projection.cell_world_rect(grid_pos)

func world_bounds() -> Rect2:
	return projection.world_bounds()

static func _apply_projection_uniforms(shader_material: ShaderMaterial, proj: GridProjection) -> void:
	shader_material.set_shader_parameter("grid_origin", proj.grid_origin())
	shader_material.set_shader_parameter("grid_axis_x", proj.axis_x())
	shader_material.set_shader_parameter("grid_axis_y", proj.axis_y())
	shader_material.set_shader_parameter("surface_origin", proj.world_bounds().position)

func rotate_view_cw() -> void:
	_apply_view(projection.orientation + 1, projection.isometric)

func rotate_view_ccw() -> void:
	_apply_view(projection.orientation - 1, projection.isometric)

func set_view_isometric(enabled: bool) -> void:
	_apply_view(projection.orientation, enabled)

func is_view_isometric() -> bool:
	return projection.isometric

func get_view_orientation() -> int:
	return projection.orientation

func set_view_orientation(orientation: int) -> void:
	_apply_view(orientation, projection.isometric)

func _apply_view(orientation: int, isometric: bool) -> void:
	projection.set_orientation(orientation)
	projection.set_isometric(isometric)
	view_orientation = projection.orientation
	view_isometric = projection.isometric
	_sync_projection_dependents()
	view_rotated.emit(projection.orientation, projection.isometric)
	EventBus.view_rotated.emit(projection.orientation, projection.isometric)

func _sync_projection_dependents() -> void:
	var bounds := projection.world_bounds()
	if _course_surface:
		_course_surface.apply_projection(projection)
	if _elevation_shader_rect:
		_elevation_shader_rect.position = bounds.position
		_elevation_shader_rect.size = bounds.size
	if _elevation_shader_controller:
		_elevation_shader_controller.apply_projection(projection)
	_redraw_all_overlays()
	if _elevation_overlay:
		_elevation_overlay.queue_redraw()
	if _ob_markers_overlay:
		_ob_markers_overlay.queue_redraw()
	if _debug_overlay:
		_debug_overlay.queue_redraw()
	if _land_boundary_overlay:
		_land_boundary_overlay.queue_redraw()
	if _wind_flag_overlay:
		_wind_flag_overlay.refresh_flag_positions()
	if _cup_overlay:
		_cup_overlay.refresh_pin_positions()
	queue_redraw()

func is_valid_position(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_width and pos.y >= 0 and pos.y < grid_height

func get_tile(pos: Vector2i) -> int:
	if not is_valid_position(pos):
		return TerrainTypes.Type.OUT_OF_BOUNDS
	return _grid.get(pos, TerrainTypes.Type.EMPTY)

## Begin batch mode — tile changes won't emit signals until end_batch()
func begin_batch() -> void:
	_batch_mode = true
	_batch_changes.clear()

## End batch mode — update TileMapLayer visuals and emit deferred signals
func end_batch() -> void:
	_batch_mode = false
	# Update TileMapLayer visuals for all changed tiles (skipped during batch)
	for change in _batch_changes:
		_update_tile_with_neighbors(change.pos)
	# Emit deferred signals so overlays update
	for change in _batch_changes:
		tile_changed.emit(change.pos, change.old_type, change.new_type)
		EventBus.terrain_tile_changed.emit(change.pos, change.old_type, change.new_type)
	_batch_changes.clear()

## End batch mode without emitting deferred signals (for bulk generation/load).
## Call refresh_all_overlays() after to rescan terrain state.
func end_batch_quiet() -> void:
	_batch_mode = false
	_batch_changes.clear()

## Force all overlays to rescan terrain from scratch and redraw.
## Use after bulk terrain changes (generation, load) that bypassed per-tile signals.
func refresh_all_overlays() -> void:
	surface_refreshed.emit()
	if _wildlife:
		_wildlife.rebuild()
	if _course_surface:
		_course_surface.rebuild()
	# Rebuild all tile visuals first (skipped during batch mode)
	_refresh_all_tiles()
	if _water_overlay and _water_overlay.has_method("_scan_water_tiles"):
		_water_overlay._scan_water_tiles()
		_water_overlay.queue_redraw()
	if _bunker_overlay and _bunker_overlay.has_method("_scan_bunker_tiles"):
		_bunker_overlay._scan_bunker_tiles()
		_bunker_overlay.queue_redraw()
	if _grass_overlay and _grass_overlay.has_method("_regenerate_grass"):
		_grass_overlay._regenerate_grass()
		_grass_overlay.queue_redraw()
	if _fairway_overlay and _fairway_overlay.has_method("_scan_tiles"):
		_fairway_overlay._scan_tiles()
		_fairway_overlay.queue_redraw()
	if _tree_overlay and _tree_overlay.has_method("_scan_tree_tiles"):
		_tree_overlay._scan_tree_tiles()
		_tree_overlay.queue_redraw()
	if _rock_overlay and _rock_overlay.has_method("_scan_rock_tiles"):
		_rock_overlay._scan_rock_tiles()
		_rock_overlay.queue_redraw()
	if _flower_overlay and _flower_overlay.has_method("_scan_flower_tiles"):
		_flower_overlay._scan_flower_tiles()
		_flower_overlay.queue_redraw()
	if _path_overlay and _path_overlay.has_method("_scan_path_tiles"):
		_path_overlay._scan_path_tiles()
		_path_overlay.queue_redraw()
	if _ob_markers_overlay and _ob_markers_overlay.has_method("_calculate_boundaries"):
		_ob_markers_overlay._calculate_boundaries()
	if _cup_overlay:
		_cup_overlay.queue_redraw()
	if _heightmap:
		_heightmap.rebuild_from_grids(self)
	if _shot_heatmap_overlay:
		_shot_heatmap_overlay.queue_redraw()
	queue_redraw()
	if tile_map:
		tile_map.queue_redraw()

func set_tile(pos: Vector2i, terrain_type: int, player_placed: bool = true) -> void:
	if not is_valid_position(pos):
		return
	var old_type = _grid.get(pos, TerrainTypes.Type.EMPTY)
	if old_type == terrain_type:
		return
	_grid[pos] = terrain_type
	# Painting over a "Green With Hole" tile with anything else removes its cup.
	if terrain_type != TerrainTypes.Type.GREEN and _cup_tiles.has(pos):
		remove_cup_tile(pos)
	if terrain_type == TerrainTypes.Type.TEE_BOX:
		_tee_box_tiles[pos] = true
	else:
		_tee_box_tiles.erase(pos)
	# Track player-placed tiles for maintenance cost calculation
	if player_placed:
		_player_placed_tiles[pos] = true
	# Skip per-tile visual updates during batch mode — a single
	# _refresh_all_tiles() after the batch is far cheaper than
	# 5 visual updates (tile + 4 neighbors) per set_tile() call.
	if not _batch_mode:
		_update_tile_with_neighbors(pos)
	if _batch_mode:
		_batch_changes.append({pos = pos, old_type = old_type, new_type = terrain_type})
	else:
		tile_changed.emit(pos, old_type, terrain_type)
		EventBus.terrain_tile_changed.emit(pos, old_type, terrain_type)

## Set tile without marking as player-placed (for auto-generation)
func set_tile_natural(pos: Vector2i, terrain_type: int) -> void:
	set_tile(pos, terrain_type, false)

func _update_tile_with_neighbors(pos: Vector2i) -> void:
	# Update the tile and all 8 neighbors for seamless autotile transitions
	_update_tile_visual(pos)
	for neighbor in _get_4_neighbors(pos):
		if is_valid_position(neighbor):
			_update_tile_visual(neighbor)

func _get_4_neighbors(pos: Vector2i) -> Array[Vector2i]:
	return [
		pos + Vector2i(0, -1),  # North
		pos + Vector2i(1, 0),   # East
		pos + Vector2i(0, 1),   # South
		pos + Vector2i(-1, 0)   # West
	]

func _calculate_edge_mask(pos: Vector2i, terrain_type: int) -> int:
	# Calculate which edges need transition visuals
	# An edge is marked if the neighbor is a DIFFERENT terrain type
	var edge_mask = 0
	var n_pos = pos + Vector2i(0, -1)
	var e_pos = pos + Vector2i(1, 0)
	var s_pos = pos + Vector2i(0, 1)
	var w_pos = pos + Vector2i(-1, 0)

	if _is_different_terrain(n_pos, terrain_type):
		edge_mask |= TilesetGenerator.EDGE_N
	if _is_different_terrain(e_pos, terrain_type):
		edge_mask |= TilesetGenerator.EDGE_E
	if _is_different_terrain(s_pos, terrain_type):
		edge_mask |= TilesetGenerator.EDGE_S
	if _is_different_terrain(w_pos, terrain_type):
		edge_mask |= TilesetGenerator.EDGE_W

	return edge_mask

func _is_different_terrain(pos: Vector2i, terrain_type: int) -> bool:
	if not is_valid_position(pos):
		return true  # Treat out-of-bounds as different
	var neighbor_type = get_tile(pos)
	if neighbor_type == terrain_type:
		return false
	# Special case: grass family transitions are smooth within family
	var grass_family = [TerrainTypes.Type.GRASS, TerrainTypes.Type.FAIRWAY,
						TerrainTypes.Type.ROUGH, TerrainTypes.Type.HEAVY_ROUGH]
	if terrain_type in grass_family and neighbor_type in grass_family:
		return false
	return true

func paint_tiles(positions: Array, terrain_type: int) -> void:
	for pos in positions:
		if pos is Vector2i:
			set_tile(pos, terrain_type)

func get_brush_tiles(center: Vector2i, brush_size: int, round_shape: bool = true) -> Array:
	var tiles: Array = []
	for offset in TerrainBrush.offsets(brush_size, round_shape):
		var pos: Vector2i = center + offset
		if is_valid_position(pos): tiles.append(pos)
	return tiles

const GREEN_PRESETS = {
	"small": [Vector2i(0, 0)],
	"medium": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
	"large": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)],
}

func get_green_preset_tiles(center: Vector2i, preset_name: String) -> Array:
	var offsets = GREEN_PRESETS.get(preset_name, [Vector2i(0, 0)])
	var tiles: Array = []
	for offset in offsets:
		var pos = center + offset
		if is_valid_position(pos):
			tiles.append(pos)
	return tiles

func get_bunker_depth(pos: Vector2i) -> int:
	return _bunker_depth_grid.get(pos, 0)

func set_bunker_depth(pos: Vector2i, depth: int) -> void:
	if not is_valid_position(pos):
		return
	if depth == 0:
		_bunker_depth_grid.erase(pos)
	else:
		_bunker_depth_grid[pos] = depth
	EventBus.terrain_tile_changed.emit(pos, TerrainTypes.Type.BUNKER, TerrainTypes.Type.BUNKER)
	if _course_surface:
		_course_surface.update_tile(pos)

# =============================================================================
# Cup tiles — "Green With Hole" markers waiting to be paired with a tee box
# =============================================================================

## Mark a green tile as carrying a cup (a "Green With Hole" tile).
## Only valid on GREEN terrain; returns true when a marker was added.
func add_cup_tile(pos: Vector2i) -> bool:
	if not is_valid_position(pos) or get_tile(pos) != TerrainTypes.Type.GREEN:
		return false
	if _cup_tiles.has(pos):
		return false
	_cup_tiles[pos] = true
	cup_tiles_changed.emit()
	return true

## Remove the cup marker from a tile. Returns true when a marker was removed.
func remove_cup_tile(pos: Vector2i) -> bool:
	if not _cup_tiles.has(pos):
		return false
	_cup_tiles.erase(pos)
	cup_tiles_changed.emit()
	return true

func has_cup_tile(pos: Vector2i) -> bool:
	return _cup_tiles.has(pos)

## Every green tile that carries a cup.
func get_cup_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for pos in _cup_tiles:
		tiles.append(pos)
	return tiles

## Every TEE_BOX tile on the course (index maintained by set_tile).
func get_tee_box_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for pos in _tee_box_tiles:
		tiles.append(pos)
	return tiles

## Rebuild the tee box index after bulk grid writes (load, generation).
func _reindex_tee_boxes() -> void:
	_tee_box_tiles.clear()
	for pos in _grid:
		if _grid[pos] == TerrainTypes.Type.TEE_BOX:
			_tee_box_tiles[pos] = true

func clear_cup_tiles() -> void:
	if _cup_tiles.is_empty():
		return
	_cup_tiles.clear()
	cup_tiles_changed.emit()

func serialize_cup_tiles() -> Array:
	var data: Array = []
	for pos in _cup_tiles:
		data.append("%d,%d" % [pos.x, pos.y])
	return data

func deserialize_cup_tiles(data) -> void:
	_cup_tiles.clear()
	if data == null:
		return
	for key in data:
		var parts = str(key).split(",")
		if parts.size() == 2:
			var pos = Vector2i(int(parts[0]), int(parts[1]))
			# Only keep markers that survived on a green tile.
			if is_valid_position(pos) and get_tile(pos) == TerrainTypes.Type.GREEN:
				_cup_tiles[pos] = true
	cup_tiles_changed.emit()

## Reset to bare land so a new course starts clean: every tile back to GRASS and
## all per-tile state cleared (player-placed marks, bunker depths, sculpted
## elevation, waiting cups). New Game paints natural terrain over the existing
## grid, so without this the previous course leaks into the next one — and a
## leftover tee box would block the player's very first tee.
func reset_for_new_course() -> void:
	deserialize_elevation({})  # Zero the vertex field and refresh elevation dependents.
	deserialize({})  # GRASS everywhere, clears player-placed marks and the tee index.
	_bunker_depth_grid.clear()
	clear_cup_tiles()
	if _bunker_overlay:
		_bunker_overlay.queue_redraw()

func calculate_distance_yards(from: Vector2i, to: Vector2i) -> int:
	const YARDS_PER_TILE: float = 22.0
	var distance_tiles = Vector2(to - from).length()
	return int(distance_tiles * YARDS_PER_TILE)

func calculate_distance_yards_precise(from: Vector2, to: Vector2) -> int:
	const YARDS_PER_TILE: float = 22.0
	return int(from.distance_to(to) * YARDS_PER_TILE)

## Get the world-space rectangle currently visible in the camera viewport.
## Overlays use this to skip drawing off-screen tiles (viewport culling).
func get_visible_world_rect() -> Rect2:
	var fallback := world_bounds()
	var viewport = get_viewport()
	if not viewport:
		return fallback
	var camera = viewport.get_camera_2d()
	if not camera:
		return fallback
	var viewport_size = viewport.get_visible_rect().size
	var cam_zoom = camera.zoom
	var visible_size = viewport_size / cam_zoom
	var camera_pos = camera.global_position
	return Rect2(camera_pos - visible_size / 2.0, visible_size)

## Get the range of grid tiles currently visible in the camera viewport.
## Returns [min_tile, max_tile] as Vector2i, clamped to grid bounds.
func get_visible_tile_range() -> Array[Vector2i]:
	var world_rect = get_visible_world_rect()
	var margin = Vector2(tile_width * 3, tile_height * 4)
	var grown = world_rect.grow_individual(margin.x, margin.y, margin.x, margin.y)
	var corners: Array[Vector2] = [
		projection.unproject(grown.position),
		projection.unproject(Vector2(grown.end.x, grown.position.y)),
		projection.unproject(grown.end),
		projection.unproject(Vector2(grown.position.x, grown.end.y)),
	]
	var min_g: Vector2 = corners[0]
	var max_g: Vector2 = corners[0]
	for point in corners:
		min_g = Vector2(minf(min_g.x, point.x), minf(min_g.y, point.y))
		max_g = Vector2(maxf(max_g.x, point.x), maxf(max_g.y, point.y))
	var min_tile = Vector2i(floori(min_g.x), floori(min_g.y))
	var max_tile = Vector2i(ceili(max_g.x), ceili(max_g.y))
	min_tile = Vector2i(maxi(min_tile.x, 0), maxi(min_tile.y, 0))
	max_tile = Vector2i(mini(max_tile.x, grid_width - 1), mini(max_tile.y, grid_height - 1))
	return [min_tile, max_tile]

func get_total_maintenance_cost() -> int:
	## Only count maintenance for player-placed tiles, not auto-generated terrain.
	## Uses square-root scaling so costs grow sub-linearly with tile count,
	## preventing large courses from being crushed by per-tile costs.
	var raw_total: int = 0
	for pos in _player_placed_tiles:
		if _grid.has(pos):
			raw_total += TerrainTypes.get_maintenance_cost(_grid[pos])
	# sqrt scaling: raw $900 → ~$600, raw $1600 → ~$800, raw $100 → ~$200
	return int(sqrt(float(raw_total)) * 20.0)

func _update_tile_visual(pos: Vector2i) -> void:
	if _course_surface:
		return
	if tile_map:
		var terrain_type = get_tile(pos)
		var edge_mask = 0
		# Only calculate edge mask for autotileable terrains
		if TilesetGenerator.terrain_uses_autotile(terrain_type):
			edge_mask = _calculate_edge_mask(pos, terrain_type)
		var atlas_coords = TilesetGenerator.get_autotile_coords(terrain_type, edge_mask)
		tile_map.set_cell(pos, 0, atlas_coords)

func _setup_ob_markers_overlay() -> void:
	_ob_markers_overlay = OBMarkersOverlay.new()
	_ob_markers_overlay.name = "OBMarkersOverlay"
	add_child(_ob_markers_overlay)
	_ob_markers_overlay.initialize(self)

func _setup_cup_overlay() -> void:
	_cup_overlay = CupOverlay.new()
	_cup_overlay.name = "CupOverlay"
	add_child(_cup_overlay)
	_cup_overlay.initialize(self)

func _setup_water_overlay() -> void:
	_water_overlay = WaterOverlay.new()
	_water_overlay.name = "WaterOverlay"
	add_child(_water_overlay)
	_water_overlay.initialize(self)

func _setup_bunker_overlay() -> void:
	_bunker_overlay = BunkerOverlay.new()
	_bunker_overlay.name = "BunkerOverlay"
	add_child(_bunker_overlay)
	_bunker_overlay.initialize(self)

func _setup_grass_overlay() -> void:
	_grass_overlay = GrassOverlay.new()
	_grass_overlay.name = "GrassOverlay"
	add_child(_grass_overlay)
	_grass_overlay.setup(self)

func _setup_fairway_overlay() -> void:
	_fairway_overlay = FairwayOverlay.new()
	_fairway_overlay.name = "FairwayOverlay"
	add_child(_fairway_overlay)
	_fairway_overlay.initialize(self)

func _setup_tree_overlay() -> void:
	_tree_overlay = TreeOverlay.new()
	_tree_overlay.name = "TreeOverlay"
	add_child(_tree_overlay)
	_tree_overlay.initialize(self)

func _setup_rock_overlay() -> void:
	_rock_overlay = RockOverlay.new()
	_rock_overlay.name = "RockOverlay"
	add_child(_rock_overlay)
	_rock_overlay.initialize(self)

func _setup_flower_overlay() -> void:
	_flower_overlay = FlowerOverlay.new()
	_flower_overlay.name = "FlowerOverlay"
	add_child(_flower_overlay)
	_flower_overlay.initialize(self)

func _setup_path_overlay() -> void:
	_path_overlay = PathOverlay.new()
	_path_overlay.name = "PathOverlay"
	add_child(_path_overlay)
	_path_overlay.initialize(self)

func _setup_elevation_overlay() -> void:
	_elevation_overlay = ElevationOverlay.new()
	_elevation_overlay.name = "ElevationOverlay"
	add_child(_elevation_overlay)
	_elevation_overlay.initialize(self)

func _setup_debug_overlay() -> void:
	_debug_overlay = TerrainDebugOverlay.new()
	_debug_overlay.name = "TerrainDebugOverlay"
	add_child(_debug_overlay)
	_debug_overlay.initialize(self)

func _setup_noise_overlay() -> void:
	# Disabled - noise overlay doesn't help with tile boundary visibility
	# The terrain_variation shader handles all variation
	pass

func _setup_land_boundary_overlay() -> void:
	_land_boundary_overlay = LandBoundaryOverlay.new()
	_land_boundary_overlay.name = "LandBoundaryOverlay"
	add_child(_land_boundary_overlay)
	_land_boundary_overlay.initialize(self)

func _setup_wind_flag_overlay() -> void:
	_wind_flag_overlay = WindFlagOverlay.new()
	_wind_flag_overlay.name = "WindFlagOverlay"
	add_child(_wind_flag_overlay)
	_wind_flag_overlay.initialize(self)

func _setup_elevation_shader() -> void:
	# Create heightmap data model
	_heightmap = Heightmap.new(grid_width, grid_height, GameManager.heightmap_noise_seed)

	# Load platform-appropriate shader
	var shader_path: String
	if OS.get_name() == "Web" and ResourceLoader.exists("res://shaders/elevation_lighting_web.gdshader"):
		shader_path = "res://shaders/elevation_lighting_web.gdshader"
	elif ResourceLoader.exists("res://shaders/elevation_lighting.gdshader"):
		shader_path = "res://shaders/elevation_lighting.gdshader"
	else:
		return

	var shader: Shader = load(shader_path) as Shader
	if not shader:
		return

	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = shader
	shader_material.set_shader_parameter("heightmap", _heightmap.get_texture())
	shader_material.set_shader_parameter("heightmap_size", Vector2(grid_width * Heightmap.PIXELS_PER_TILE, grid_height * Heightmap.PIXELS_PER_TILE))
	shader_material.set_shader_parameter("grid_size", Vector2(grid_width, grid_height))
	shader_material.set_shader_parameter("tile_size", Vector2(tile_width, tile_height))
	_apply_projection_uniforms(shader_material, projection)

	# Create full-viewport ColorRect for shader overlay
	_elevation_shader_rect = ColorRect.new()
	_elevation_shader_rect.name = "ElevationShaderRect"
	_elevation_shader_rect.z_index = 0  # Same as terrain; renders above TileMapLayer by tree order, below entities
	_elevation_shader_rect.material = shader_material
	_elevation_shader_rect.color = Color(1, 1, 1, 0)  # Transparent base — shader controls all output
	_elevation_shader_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Cover the projected course (a diamond under isometric, sized to its AABB).
	var bounds := projection.world_bounds()
	_elevation_shader_rect.position = bounds.position
	_elevation_shader_rect.size = bounds.size
	add_child(_elevation_shader_rect)

	# Create controller node to update uniforms each frame
	_elevation_shader_controller = ElevationShaderController.new()
	_elevation_shader_controller.name = "ElevationShaderController"
	add_child(_elevation_shader_controller)
	_elevation_shader_controller.setup(self, _elevation_shader_rect, material)

	# Connect signals for heightmap updates
	_heightmap.initialize(self)
	tile_changed.connect(_on_tile_changed_heightmap)

	# Build initial heightmap from current grid state
	_heightmap.rebuild_from_grids(self)

func _on_tile_changed_heightmap(pos: Vector2i, _old: int, _new_type: int) -> void:
	if _heightmap:
		_heightmap.refresh_tile(pos)

func _setup_fairway_width_overlay() -> void:
	_fairway_width_overlay = FairwayWidthOverlay.new()
	_fairway_width_overlay.name = "FairwayWidthOverlay"
	add_child(_fairway_width_overlay)
	_fairway_width_overlay.initialize(self)

func toggle_fairway_width_overlay() -> void:
	if _fairway_width_overlay:
		_fairway_width_overlay.toggle()

## Set up shot heatmap overlay (called from main.gd after tracker is created)
func setup_shot_heatmap_overlay(tracker: ShotHeatmapTracker) -> void:
	_shot_heatmap_overlay = ShotHeatmapOverlay.new()
	_shot_heatmap_overlay.name = "ShotHeatmapOverlay"
	add_child(_shot_heatmap_overlay)
	_shot_heatmap_overlay.initialize(self, tracker)

## Toggle shot heatmap visibility
func toggle_shot_heatmap() -> void:
	if _shot_heatmap_overlay:
		_shot_heatmap_overlay.toggle()

## Cycle shot heatmap mode (density <-> trouble)
func cycle_shot_heatmap_mode() -> void:
	if _shot_heatmap_overlay:
		_shot_heatmap_overlay.cycle_mode()

## Check if shot heatmap is enabled
func is_shot_heatmap_enabled() -> bool:
	return _shot_heatmap_overlay and _shot_heatmap_overlay.is_enabled()

## Toggle debug overlay visibility
func toggle_debug_overlay() -> void:
	if _debug_overlay:
		_debug_overlay.toggle()

## Check if debug overlay is enabled
func is_debug_overlay_enabled() -> bool:
	return _debug_overlay and _debug_overlay.is_enabled()

## Vertex field dimensions: a WxH tile grid has (W+1)x(H+1) vertices.
func vertex_grid_size() -> Vector2i:
	return Vector2i(grid_width + 1, grid_height + 1)

func is_valid_vertex(vertex: Vector2i) -> bool:
	return vertex.x >= 0 and vertex.x <= grid_width \
		and vertex.y >= 0 and vertex.y <= grid_height

## Allocate (or re-allocate) the packed vertex height buffer
func _ensure_vertex_storage() -> void:
	var stride: int = grid_width + 1
	var needed: int = stride * (grid_height + 1)
	if needed <= 0:
		return
	if _vertex_elevation.size() == needed and _vertex_stride == stride:
		return
	var previous: PackedInt32Array = _vertex_elevation
	var previous_stride: int = _vertex_stride
	_vertex_elevation = PackedInt32Array()
	_vertex_elevation.resize(needed)
	_vertex_elevation.fill(0)
	_vertex_stride = stride
	if previous.size() == 0 or previous_stride <= 0:
		return
	var rows: int = mini(int(previous.size() / float(previous_stride)), grid_height + 1)
	var cols: int = mini(previous_stride, stride)
	for y in rows:
		for x in cols:
			_vertex_elevation[y * stride + x] = previous[y * previous_stride + x]

func _vertex_index(vertex: Vector2i) -> int:
	return vertex.y * (grid_width + 1) + vertex.x

## Height stored at a grid vertex (clamped to MIN_ELEVATION..MAX_ELEVATION).
func get_vertex_elevation(vertex: Vector2i) -> int:
	if not is_valid_vertex(vertex):
		return 0
	_ensure_vertex_storage()
	return _vertex_elevation[_vertex_index(vertex)]

func set_vertex_elevation(vertex: Vector2i, height: int) -> void:
	if not is_valid_vertex(vertex):
		return
	_ensure_vertex_storage()
	var index: int = _vertex_index(vertex)
	var new_height: int = clampi(height, MIN_ELEVATION, MAX_ELEVATION)
	var old_height: int = _vertex_elevation[index]
	if old_height == new_height:
		return

	var affected: Array[Vector2i] = tiles_around_vertex(vertex)
	var before: Dictionary = {}
	for tile in affected:
		before[tile] = get_elevation(tile)

	_vertex_elevation[index] = new_height
	vertex_elevation_changed.emit(vertex, old_height, new_height)
	_queue_elevation_refresh(vertex, affected)

	for tile in affected:
		var after: int = get_elevation(tile)
		if int(before[tile]) != after:
			elevation_changed.emit(tile, int(before[tile]), after)
	if _elevation_overlay:
		_elevation_overlay.queue_redraw()

func adjust_vertex_elevation(vertex: Vector2i, delta: int) -> int:
	var updated: int = clampi(get_vertex_elevation(vertex) + delta, MIN_ELEVATION, MAX_ELEVATION)
	set_vertex_elevation(vertex, updated)
	return updated

func vertices_of_tile(pos: Vector2i) -> Array[Vector2i]:
	return [pos, pos + Vector2i(1, 0), pos + Vector2i(1, 1), pos + Vector2i(0, 1)]

func tiles_around_vertex(vertex: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for offset in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var tile: Vector2i = vertex + offset
		if is_valid_position(tile):
			tiles.append(tile)
	return tiles

func nearest_vertex(grid_point: Vector2) -> Vector2i:
	return Vector2i(
		clampi(roundi(grid_point.x), 0, grid_width),
		clampi(roundi(grid_point.y), 0, grid_height))

func get_tile_corner_heights(pos: Vector2i) -> Vector4:
	_ensure_vertex_storage()
	var x0: int = clampi(pos.x, 0, grid_width)
	var y0: int = clampi(pos.y, 0, grid_height)
	var x1: int = mini(x0 + 1, grid_width)
	var y1: int = mini(y0 + 1, grid_height)
	var stride: int = grid_width + 1
	return Vector4(
		float(_vertex_elevation[y0 * stride + x0]),
		float(_vertex_elevation[y0 * stride + x1]),
		float(_vertex_elevation[y1 * stride + x0]),
		float(_vertex_elevation[y1 * stride + x1]))

func get_elevation_at(grid_point: Vector2) -> float:
	_ensure_vertex_storage()
	var gx: float = clampf(grid_point.x, 0.0, float(grid_width))
	var gy: float = clampf(grid_point.y, 0.0, float(grid_height))
	var x0: int = clampi(int(floor(gx)), 0, grid_width)
	var y0: int = clampi(int(floor(gy)), 0, grid_height)
	var x1: int = mini(x0 + 1, grid_width)
	var y1: int = mini(y0 + 1, grid_height)
	var fx: float = gx - float(x0)
	var fy: float = gy - float(y0)
	var stride: int = grid_width + 1
	var h00: float = float(_vertex_elevation[y0 * stride + x0])
	var h10: float = float(_vertex_elevation[y0 * stride + x1])
	var h01: float = float(_vertex_elevation[y1 * stride + x0])
	var h11: float = float(_vertex_elevation[y1 * stride + x1])
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)

func get_elevation_at_precise(precise_pos: Vector2) -> float:
	return get_elevation_at(precise_pos + Vector2(0.5, 0.5))

func get_tile_height(pos: Vector2i) -> float:
	if not is_valid_position(pos):
		return 0.0
	return get_elevation_at(Vector2(pos) + Vector2(0.5, 0.5))

func get_elevation(pos: Vector2i) -> int:
	return roundi(get_tile_height(pos))

func set_elevation(pos: Vector2i, height: int) -> void:
	if not is_valid_position(pos):
		return
	var clamped: int = clampi(height, MIN_ELEVATION, MAX_ELEVATION)
	for vertex in vertices_of_tile(pos):
		set_vertex_elevation(vertex, clamped)

func get_elevation_difference(from: Vector2i, to: Vector2i) -> int:
	return roundi(get_tile_height(to) - get_tile_height(from))

func get_slope_at(grid_point: Vector2) -> Vector2:
	var step: float = SLOPE_SAMPLE_STEP
	var dhdx: float = (get_elevation_at(grid_point + Vector2(step, 0.0)) \
		- get_elevation_at(grid_point - Vector2(step, 0.0))) / (2.0 * step)
	var dhdy: float = (get_elevation_at(grid_point + Vector2(0.0, step)) \
		- get_elevation_at(grid_point - Vector2(0.0, step))) / (2.0 * step)
	return Vector2(-dhdx, -dhdy)

## Downhill gradient for "precise" game coordinates (integers are tile centres).
func get_slope_at_precise(precise_pos: Vector2) -> Vector2:
	return get_slope_at(precise_pos + Vector2(0.5, 0.5))

## Downhill slope direction at a tile (unit vector, zero on flat ground).
func get_slope_direction(pos: Vector2i) -> Vector2:
	if not is_valid_position(pos):
		return Vector2.ZERO
	var slope: Vector2 = get_slope_at(Vector2(pos) + Vector2(0.5, 0.5))
	return slope.normalized() if slope.length_squared() > 0.000001 else Vector2.ZERO

## Downhill slope direction at a tile-space point (unit vector).
func get_slope_direction_at(grid_point: Vector2) -> Vector2:
	var slope: Vector2 = get_slope_at(grid_point)
	return slope.normalized() if slope.length_squared() > 0.000001 else Vector2.ZERO

func vertex_enclosed_by_type(vertex: Vector2i, terrain_type: int) -> bool:
	var tiles: Array[Vector2i] = tiles_around_vertex(vertex)
	if tiles.is_empty():
		return false
	for tile in tiles:
		if get_tile(tile) != terrain_type:
			return false
	return true

func set_enclosed_elevation(bounds: Rect2i, terrain_type: int, height: int,
		height_fn: Callable = Callable()) -> void:
	var from_x: int = maxi(bounds.position.x, 0)
	var from_y: int = maxi(bounds.position.y, 0)
	var to_x: int = mini(bounds.end.x, grid_width)
	var to_y: int = mini(bounds.end.y, grid_height)
	for vx in range(from_x, to_x + 1):
		for vy in range(from_y, to_y + 1):
			var vertex := Vector2i(vx, vy)
			if not vertex_enclosed_by_type(vertex, terrain_type):
				continue
			var target: int = height
			if height_fn.is_valid():
				target = int(height_fn.call(vertex))
			set_vertex_elevation(vertex, target)

func get_nonzero_vertices() -> Array[Vector2i]:
	_ensure_vertex_storage()
	var result: Array[Vector2i] = []
	var stride: int = grid_width + 1
	for y in range(grid_height + 1):
		for x in range(stride):
			if _vertex_elevation[y * stride + x] != 0:
				result.append(Vector2i(x, y))
	return result

func is_vertex_editable(vertex: Vector2i, entity_layer: EntityLayer = null,
		protect_surfaces: bool = false) -> bool:
	if not is_valid_vertex(vertex):
		return false
	for tile in tiles_around_vertex(vertex):
		if protect_surfaces and get_tile(tile) in [TerrainTypes.Type.WATER,
				TerrainTypes.Type.PATH, TerrainTypes.Type.OUT_OF_BOUNDS]:
			return false
		if entity_layer and entity_layer.is_tile_occupied_by_building(tile):
			return false
		if GameManager.land_manager and not GameManager.land_manager.is_tile_owned(tile):
			return false
	return true

func _queue_elevation_refresh(vertex: Vector2i, tiles: Array[Vector2i]) -> void:
	if _course_surface:
		_course_surface.update_vertex(vertex)
	if _heightmap:
		_heightmap.refresh_tiles(tiles)

## Get the heightmap texture for external use (e.g., shader debugging)
func get_heightmap_texture() -> ImageTexture:
	if _heightmap:
		return _heightmap.get_texture()
	return null

## Toggle elevation overlay prominence
func set_elevation_overlay_active(active: bool) -> void:
	if _elevation_overlay:
		_elevation_overlay.set_elevation_mode_active(active)

## Get tiles of a given type that are at the boundary (adjacent to a different type)
func get_boundary_tiles(terrain_type: int) -> Array:
	var boundary: Array = []
	for x in range(grid_width):
		for y in range(grid_height):
			var pos = Vector2i(x, y)
			if get_tile(pos) != terrain_type:
				continue
			# Check if any neighbor is a different type
			var neighbors = [
				pos + Vector2i(1, 0), pos + Vector2i(-1, 0),
				pos + Vector2i(0, 1), pos + Vector2i(0, -1)
			]
			for neighbor in neighbors:
				if not is_valid_position(neighbor):
					continue
				if get_tile(neighbor) != terrain_type:
					boundary.append(pos)
					break
	return boundary

## Flood-fill to find all connected tiles of the same type
func get_connected_tiles(start_pos: Vector2i, terrain_type: int) -> Array:
	var connected: Array = []
	var visited: Dictionary = {}
	var queue: Array = [start_pos]

	while queue.size() > 0:
		var pos = queue.pop_front()
		if visited.has(pos):
			continue
		visited[pos] = true

		if not is_valid_position(pos):
			continue
		if get_tile(pos) != terrain_type:
			continue

		connected.append(pos)

		# Check 4 neighbors
		queue.append(pos + Vector2i(1, 0))
		queue.append(pos + Vector2i(-1, 0))
		queue.append(pos + Vector2i(0, 1))
		queue.append(pos + Vector2i(0, -1))

	return connected

## Get tiles in a corridor between two points (for difficulty calculation)
func get_tiles_in_corridor(from: Vector2i, to: Vector2i, width: int) -> Array:
	var tiles: Array = []
	var direction = Vector2(to - from)
	var length = direction.length()
	if length < 1.0:
		return tiles

	var normalized = direction.normalized()
	var perp = Vector2(-normalized.y, normalized.x)
	var half_width = width / 2.0

	var steps = int(length) + 1
	for i in range(steps):
		var t = float(i) / float(max(steps - 1, 1))
		var center = Vector2(from) + direction * t

		for w in range(-int(half_width), int(half_width) + 1):
			var sample_pos = Vector2i(center + perp * float(w))
			if is_valid_position(sample_pos) and sample_pos not in tiles:
				tiles.append(sample_pos)

	return tiles

func serialize() -> Dictionary:
	var data: Dictionary = {}
	for pos in _grid:
		if _grid[pos] != TerrainTypes.Type.GRASS:
			data["%d,%d" % [pos.x, pos.y]] = _grid[pos]
	return data

func serialize_player_placed() -> Array:
	## Serialize player-placed tile positions for maintenance tracking
	var data: Array = []
	for pos in _player_placed_tiles:
		data.append("%d,%d" % [pos.x, pos.y])
	return data

func serialize_elevation() -> Dictionary:
	_ensure_vertex_storage()
	var data: Dictionary = {}
	var stride: int = grid_width + 1
	for y in range(grid_height + 1):
		for x in range(stride):
			var height: int = _vertex_elevation[y * stride + x]
			if height != 0:
				data["%d,%d" % [x, y]] = height
	return data

func serialize_bunker_depth() -> Dictionary:
	var data: Dictionary = {}
	for pos in _bunker_depth_grid:
		data["%d,%d" % [pos.x, pos.y]] = _bunker_depth_grid[pos]
	return data

func deserialize(data: Dictionary) -> void:
	_initialize_grid()
	_player_placed_tiles.clear()
	# First pass: set all terrain types
	for key in data:
		var parts = key.split(",")
		if parts.size() == 2:
			var pos = Vector2i(int(parts[0]), int(parts[1]))
			if is_valid_position(pos):
				_grid[pos] = int(data[key])
	# Second pass: update visuals with correct autotile edges
	for x in range(grid_width):
		for y in range(grid_height):
			_update_tile_visual(Vector2i(x, y))

	_reindex_tee_boxes()
	if _course_surface:
		_course_surface.rebuild()

func deserialize_player_placed(data: Array) -> void:
	## Restore player-placed tile tracking for maintenance
	_player_placed_tiles.clear()
	for key in data:
		var parts = key.split(",")
		if parts.size() == 2:
			var pos = Vector2i(int(parts[0]), int(parts[1]))
			if is_valid_position(pos):
				_player_placed_tiles[pos] = true

func deserialize_elevation(data: Dictionary) -> void:
	_ensure_vertex_storage()
	_vertex_elevation.fill(0)
	for key in data:
		var parts = str(key).split(",")
		if parts.size() == 2:
			var vertex = Vector2i(int(parts[0]), int(parts[1]))
			if is_valid_vertex(vertex):
				_vertex_elevation[_vertex_index(vertex)] = clampi(int(data[key]),
						MIN_ELEVATION, MAX_ELEVATION)
	_after_elevation_bulk_load()

func migrate_tile_elevation(data: Dictionary) -> void:
	var tiles: Dictionary = {}
	for key in data:
		var parts = str(key).split(",")
		if parts.size() == 2:
			var pos = Vector2i(int(parts[0]), int(parts[1]))
			if is_valid_position(pos):
				tiles[pos] = clampi(int(data[key]), MIN_ELEVATION, MAX_ELEVATION)
	_ensure_vertex_storage()
	_vertex_elevation.fill(0)
	for y in range(grid_height + 1):
		for x in range(grid_width + 1):
			var vertex := Vector2i(x, y)
			var total: int = 0
			var count: int = 0
			# Missing tiles are sea level — the legacy map only stored non-zero ones.
			for tile in tiles_around_vertex(vertex):
				total += int(tiles.get(tile, 0))
				count += 1
			if count > 0:
				_vertex_elevation[_vertex_index(vertex)] = roundi(float(total) / float(count))
	_after_elevation_bulk_load()

## Rebuild every elevation-derived texture after a bulk write (load, migration).
func _after_elevation_bulk_load() -> void:
	if _course_surface:
		_course_surface.rebuild_elevation()
	if _elevation_overlay:
		_elevation_overlay.invalidate()
		_elevation_overlay.queue_redraw()
	if _heightmap:
		_heightmap.rebuild_from_grids(self)

func deserialize_bunker_depth(data: Dictionary) -> void:
	_bunker_depth_grid.clear()
	for key in data:
		var parts = key.split(",")
		if parts.size() == 2:
			var pos = Vector2i(int(parts[0]), int(parts[1]))
			if is_valid_position(pos):
				_bunker_depth_grid[pos] = int(data[key])

	if _course_surface:
		_course_surface.rebuild()
