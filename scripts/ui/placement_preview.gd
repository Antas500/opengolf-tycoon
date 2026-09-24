extends Node2D
class_name PlacementPreview
## PlacementPreview - Enhanced placement preview with ghost sprites and validity indication

signal placement_confirmed(grid_pos: Vector2i, placement_type: String)

var terrain_grid: TerrainGrid
var placement_manager: PlacementManager
var camera: IsometricCamera
var current_terrain_tool: int = -1  # Current terrain painting tool
var terrain_painting_enabled: bool = false  # Whether to show terrain preview
var elevation_mode_active: bool = false  # Whether elevation tool is active
var elevation_raising: bool = true  # True = raising, false = lowering
var elevation_sculpted: bool = false  # True = rolling hill / hollow brush
var bulldozer_mode_active: bool = false  # Whether bulldozer mode is active
var round_brush := true
var brush_size: int = 1  # Current brush size (1, 3, or 5)
var _hole_move_mode: int = 0  # 0=NONE, matches main.gd HoleMoveMode enum

# Preview state
var current_grid_pos: Vector2i = Vector2i(-1, -1)
var current_preview_valid: bool = false
var current_preview_positions: Array = []
var current_world_pos: Vector2 = Vector2.ZERO
var smooth_world_pos: Vector2 = Vector2.ZERO

# Visual settings
const VALID_COLOR := Color(0.3, 0.9, 0.3, 0.6)
const INVALID_COLOR := Color(0.9, 0.3, 0.3, 0.6)
const VALID_OUTLINE := Color(0.5, 1.0, 0.5, 0.9)
const INVALID_OUTLINE := Color(1.0, 0.4, 0.4, 0.9)
const BLOCKED_TILE_COLOR := Color(0.8, 0.2, 0.2, 0.4)
const SMOOTH_SPEED := 20.0

# Potential hole path: while a tee box waits and the Green tool is about to cut
# the cup, the hovered tile is previewed as the hole it would make.
const HOLE_PATH_COLOR := Color(1.0, 0.95, 0.72, 0.9)
const HOLE_PATH_SHADOW := Color(0.0, 0.0, 0.0, 0.35)
const HOLE_PATH_BLOCKED := Color(1.0, 0.45, 0.4, 0.9)
const HOLE_PATH_LANDING := Color(0.5, 0.85, 1.0, 0.9)  # HoleVisualizer landing-zone blue
const HOLE_PATH_TEE := Color(0.55, 0.95, 0.6, 0.95)
const HOLE_PATH_WIDTH := 2.0
const HOLE_PATH_DASH := 8.0
const HOLE_PATH_FONT_SIZE := 13
const HOLE_PATH_NOTE_FONT_SIZE := 11

## The potential hole under the cursor (HoleLayout.potential_hole()), {} when hidden.
var potential_hole: Dictionary = {}
## Planned route for potential_hole: [tee, landing..., cup], or [] while planning.
var potential_hole_route: Array[Vector2i] = []
var _hole_path_planner := HolePathPlanner.new()

# Animation state
var _garden_ghost: GardenArt
var _building_ghost: CourseArchitecture
var _pulse_time: float = 0.0
var _current_alpha: float = 0.0
var _target_alpha: float = 0.0
var _last_process_usec: int = -1
var _label_style: StyleBoxFlat

func _ready() -> void:
	_garden_ghost = GardenArt.new()
	_garden_ghost.visible = false
	add_child(_garden_ghost)
	_building_ghost = CourseArchitecture.new()
	_building_ghost.name = "BuildingGhost"
	_building_ghost.visible = false
	add_child(_building_ghost)
	set_process(true)
	z_index = 100  # Render above terrain
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(_delta: float) -> void:
	# The player keeps building while the game is paused (Engine.time_scale = 0)
	# or fast-forwarded, so animate on wall-clock time like IsometricCamera does —
	# the scaled delta would freeze the fade-in at 0 or overshoot it at 8x.
	var delta := _real_delta()
	_pulse_time += delta * 3.0

	# Show preview for entity placement, terrain painting, elevation, or bulldozer
	var show_entity_preview = placement_manager and placement_manager.placement_mode != PlacementManager.PlacementMode.NONE
	var show_terrain_preview = terrain_painting_enabled and current_terrain_tool >= 0
	var show_elevation_preview = elevation_mode_active
	var show_bulldozer_preview = bulldozer_mode_active
	var show_move_preview = _hole_move_mode != 0

	if show_entity_preview or show_terrain_preview or show_elevation_preview or show_bulldozer_preview or show_move_preview:
		_target_alpha = 1.0
		_update_preview(delta)
	else:
		_target_alpha = 0.0
		current_preview_positions = []
		_clear_potential_hole()

	# Smooth alpha transition
	_current_alpha = lerp(_current_alpha, _target_alpha, delta * 10.0)

	if _current_alpha > 0.01:
		queue_redraw()

## Seconds since the previous frame, unaffected by Engine.time_scale.
func _real_delta() -> float:
	var now := Time.get_ticks_usec()
	var elapsed := 0.0 if _last_process_usec < 0 else float(now - _last_process_usec) / 1000000.0
	_last_process_usec = now
	return minf(elapsed, 0.1)  # Guard against huge jumps (minimized window, debugger).

func set_terrain_grid(grid: TerrainGrid) -> void:
	terrain_grid = grid

func set_placement_manager(manager: PlacementManager) -> void:
	placement_manager = manager

func set_camera(cam: IsometricCamera) -> void:
	camera = cam

func set_terrain_tool(tool_type: int) -> void:
	current_terrain_tool = tool_type

func set_terrain_painting_enabled(enabled: bool) -> void:
	terrain_painting_enabled = enabled

func set_brush_size(size: int) -> void:
	brush_size = size

func set_elevation_mode(active: bool, raising: bool = true, sculpted: bool = false) -> void:
	elevation_mode_active = active
	elevation_raising = raising
	elevation_sculpted = sculpted

func set_bulldozer_mode(active: bool) -> void:
	bulldozer_mode_active = active

func set_hole_move_mode(mode: int) -> void:
	_hole_move_mode = mode

func _exit_tree() -> void:
	# A running route task reads a terrain copy the planner owns: let it finish.
	_hole_path_planner.shutdown()

func _update_preview(delta: float) -> void:
	if not terrain_grid or not camera:
		return

	var mouse_world = camera.get_mouse_world_position()
	var grid_pos = terrain_grid.screen_to_grid(mouse_world)

	# Smooth world position for fluid movement
	current_world_pos = terrain_grid.grid_to_screen_center(grid_pos)
	smooth_world_pos = smooth_world_pos.lerp(current_world_pos, SMOOTH_SPEED * delta)

	current_grid_pos = grid_pos

	# Get positions to preview based on placement mode
	if placement_manager and placement_manager.placement_mode != PlacementManager.PlacementMode.NONE:
		match placement_manager.placement_mode:
			PlacementManager.PlacementMode.TREE:
				current_preview_positions = [grid_pos]
			PlacementManager.PlacementMode.ROCK:
				current_preview_positions = [grid_pos]
			PlacementManager.PlacementMode.BUILDING, PlacementManager.PlacementMode.DECORATION:
				current_preview_positions = _get_building_footprint(grid_pos)
			_:
				current_preview_positions = [grid_pos]
		# Check overall validity for entity placement
		current_preview_valid = placement_manager.can_place_at(grid_pos, terrain_grid)
	else:
		# Terrain painting mode - show the area the tool will actually paint
		var course: GameManager.CourseData = GameManager.current_course
		var max_brush: int = HoleLayout.max_brush_size(current_terrain_tool, terrain_grid, course)
		var effective_brush: int = brush_size if max_brush == HoleLayout.UNLIMITED_BRUSH \
				else mini(brush_size, max_brush)
		if effective_brush <= 1:
			current_preview_positions = [grid_pos]
		else:
			current_preview_positions = terrain_grid.get_brush_tiles(grid_pos, effective_brush, round_brush)
		current_preview_valid = terrain_grid.is_valid_position(grid_pos)
		if current_terrain_tool == TerrainTypes.Type.TEE_BOX:
			current_preview_valid = current_preview_valid \
					and HoleLayout.can_place_tee_box(terrain_grid, course)

	_update_potential_hole(grid_pos)
	queue_redraw()

## Refresh the potential hole for the hovered tile: shown only while terrain
## painting with the Green tool, a Green With Hole comes next and a tee box waits.
func _update_potential_hole(grid_pos: Vector2i) -> void:
	var show_path: bool = terrain_painting_enabled and _hole_move_mode == 0 \
			and not elevation_mode_active and not bulldozer_mode_active \
			and not (placement_manager and placement_manager.placement_mode != PlacementManager.PlacementMode.NONE)
	var hole: Dictionary = {}
	if show_path:
		hole = HoleLayout.potential_hole(current_terrain_tool, terrain_grid,
				GameManager.current_course, grid_pos)
	if hole.is_empty():
		_clear_potential_hole()
		return
	potential_hole = hole
	potential_hole_route = _hole_path_planner.route_for(terrain_grid, hole.tee, hole.cup, hole.par,
			hole.extra_tees.values())

func _clear_potential_hole() -> void:
	if not potential_hole.is_empty() or not potential_hole_route.is_empty():
		potential_hole = {}
		potential_hole_route = []
		queue_redraw()
	_hole_path_planner.cancel_pending()
	# Let a finished task hand its route to the cache even while hidden.
	_hole_path_planner.poll()

func _get_building_footprint(grid_pos: Vector2i) -> Array:
	var footprint = placement_manager.get_building_footprint()
	var result: Array = []
	for offset in footprint:
		result.append(grid_pos + offset)
	return result

func _draw() -> void:
	if is_instance_valid(_garden_ghost):
		_garden_ghost.visible = false
	if is_instance_valid(_building_ghost):
		_building_ghost.visible = false
	if not terrain_grid:
		return

	# Check for hole move mode preview
	if _hole_move_mode != 0:
		_draw_hole_move_preview()
		return

	if _current_alpha < 0.01:
		return

	var is_entity_mode = placement_manager and placement_manager.placement_mode != PlacementManager.PlacementMode.NONE
	var is_terrain_mode = terrain_painting_enabled and current_terrain_tool >= 0
	var is_special_mode = is_terrain_mode or elevation_mode_active or bulldozer_mode_active

	if not is_entity_mode and not is_special_mode:
		return

	# Pulsing effect
	var pulse = 0.85 + sin(_pulse_time) * 0.15
	var alpha_mod = _current_alpha * pulse

	# Draw footprint tiles
	for i in range(current_preview_positions.size()):
		var grid_pos = current_preview_positions[i]
		if terrain_grid.is_valid_position(grid_pos):
			var tile_valid: bool
			if is_entity_mode:
				tile_valid = _is_tile_valid_for_placement(grid_pos)
			else:
				tile_valid = true  # Terrain/elevation/bulldozer painting is always valid on valid tiles
			_draw_isometric_tile(grid_pos, tile_valid, alpha_mod, i == 0, is_special_mode)

	if not potential_hole.is_empty():
		_draw_potential_hole(_current_alpha)

	if elevation_mode_active:
		_draw_elevation_brush(alpha_mod)

	# Draw entity ghost preview (only for entity placement)
	if is_entity_mode:
		_draw_entity_ghost(alpha_mod)

func _draw_elevation_brush(alpha_mod: float) -> void:
	if not terrain_grid or not camera:
		return

	var mouse_world: Vector2 = camera.get_mouse_world_position()
	var center: Vector2i = terrain_grid.nearest_vertex(terrain_grid.screen_to_grid_point(mouse_world))
	if not terrain_grid.is_valid_vertex(center):
		return

	var brush_color: Color = Color(0.55, 0.78, 1.0, 0.85 * alpha_mod) if elevation_raising \
		else Color(1.0, 0.6, 0.5, 0.85 * alpha_mod)
	var vertices: Array[Vector2i] = ElevationTool.brush_vertices(
		terrain_grid, center, brush_size, elevation_sculpted)
	for vertex in vertices:
		if vertex == center:
			continue
		_draw_vertex_marker(vertex, brush_color, 0.10)

	var current_height: int = terrain_grid.get_vertex_elevation(center)
	var step: int = ElevationTool.SCULPT_AMOUNT if elevation_sculpted else 1
	if not elevation_raising:
		step = -step
	var next_height: int = clampi(current_height + step,
		terrain_grid.MIN_ELEVATION, terrain_grid.MAX_ELEVATION)
	_draw_vertex_marker(center, Color(1, 1, 1, 0.95 * alpha_mod), 0.18)

	var label: String
	if current_height == next_height:
		label = "%d (max)" % current_height if elevation_raising else "%d (min)" % current_height
	else:
		label = "%d -> %d" % [current_height, next_height]
	draw_string(
		ThemeDB.fallback_font,
		to_local(terrain_grid.grid_point_to_screen(Vector2(center))) + Vector2(10, -8),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color(1, 1, 1, 0.9 * alpha_mod)
	)

func _draw_vertex_marker(vertex: Vector2i, color: Color, marker_scale: float) -> void:
	var axis_x: Vector2 = terrain_grid.projection.axis_x() * marker_scale
	var axis_y: Vector2 = terrain_grid.projection.axis_y() * marker_scale
	var center: Vector2 = to_local(terrain_grid.grid_point_to_screen(Vector2(vertex)))
	draw_colored_polygon(PackedVector2Array([
		center - axis_x, center - axis_y, center + axis_x, center + axis_y,
	]), color)

func _is_tile_valid_for_placement(_grid_pos: Vector2i) -> bool:
	# The preview and click use one footprint-level validation result.
	return current_preview_valid

func _draw_isometric_tile(grid_pos: Vector2i, is_valid: bool, alpha_mod: float, is_primary: bool, is_terrain_mode: bool = false) -> void:

	# Fill color based on validity and mode
	var fill_color: Color
	var outline_color: Color

	if is_terrain_mode:
		# Use terrain-specific color for painting preview
		fill_color = _get_terrain_preview_color()
		outline_color = Color(1.0, 1.0, 1.0, 0.8)
	elif is_valid:
		fill_color = VALID_COLOR
		outline_color = VALID_OUTLINE
	else:
		fill_color = INVALID_COLOR if is_primary else BLOCKED_TILE_COLOR
		outline_color = INVALID_OUTLINE

	fill_color.a *= alpha_mod
	outline_color.a *= alpha_mod

	draw_colored_polygon(OverlayGeometry.tile_polygon(terrain_grid, self, grid_pos), fill_color)

	# Draw outline
	var outline_width = 2.0 if is_primary else 1.0
	draw_polyline(OverlayGeometry.tile_polyline(terrain_grid, self, grid_pos),
			outline_color, outline_width)

func _get_terrain_preview_color() -> Color:
	"""Get a preview color based on the current terrain tool or active mode"""
	if elevation_mode_active:
		if elevation_raising:
			return Color(0.5, 0.7, 1.0, 0.5)  # Light blue for raise
		else:
			return Color(1.0, 0.5, 0.5, 0.5)  # Light red for lower
	if bulldozer_mode_active:
		return Color(1.0, 0.5, 0.3, 0.5)  # Orange for bulldozer
	match current_terrain_tool:
		TerrainTypes.Type.FAIRWAY:
			return Color(0.4, 0.8, 0.4, 0.5)  # Light green
		TerrainTypes.Type.ROUGH:
			return Color(0.5, 0.7, 0.3, 0.5)  # Yellow-green
		TerrainTypes.Type.GREEN:
			return Color(0.3, 0.9, 0.5, 0.5)  # Bright green
		TerrainTypes.Type.TEE_BOX:
			return Color(0.4, 0.85, 0.45, 0.5)  # Medium green
		TerrainTypes.Type.BUNKER:
			return Color(0.9, 0.85, 0.6, 0.5)  # Sand color
		TerrainTypes.Type.WATER:
			return Color(0.3, 0.5, 0.9, 0.5)  # Blue
		TerrainTypes.Type.PATH:
			return Color(0.6, 0.55, 0.5, 0.5)  # Brown/gray
		TerrainTypes.Type.OUT_OF_BOUNDS:
			return Color(0.9, 0.3, 0.3, 0.5)  # Red
		TerrainTypes.Type.FLOWER_BED:
			return Color(0.9, 0.5, 0.7, 0.5)  # Pink
		TerrainTypes.Type.FIRM_FAIRWAY:
			return Color(0.7, 0.78, 0.4, 0.5)  # Straw green
		TerrainTypes.Type.DEEP_ROUGH:
			return Color(0.3, 0.5, 0.25, 0.5)  # Dark green
		TerrainTypes.Type.POT_BUNKER:
			return Color(0.8, 0.68, 0.45, 0.5)  # Dark sand
		TerrainTypes.Type.WASTE_BUNKER:
			return Color(0.78, 0.7, 0.55, 0.5)  # Grey-tan sand
		TerrainTypes.Type.STREAM:
			return Color(0.35, 0.7, 0.9, 0.5)  # Light blue
		TerrainTypes.Type.ROCKS:
			return Color(0.6, 0.58, 0.55, 0.5)  # Stone grey
		TerrainTypes.Type.BRUSH:
			return Color(0.4, 0.5, 0.2, 0.5)  # Olive
		_:
			return Color(0.5, 0.5, 0.5, 0.5)  # Gray default

func _draw_entity_ghost(alpha_mod: float) -> void:
	if current_preview_positions.is_empty():
		return

	var base_pos = terrain_grid.grid_to_screen_center(current_grid_pos)
	var ghost_color = VALID_COLOR if current_preview_valid else INVALID_COLOR
	ghost_color.a = alpha_mod * 0.8

	match placement_manager.placement_mode:
		PlacementManager.PlacementMode.TREE:
			_draw_tree_ghost(base_pos, ghost_color)
		PlacementManager.PlacementMode.ROCK:
			_draw_rock_ghost(base_pos, ghost_color)
		PlacementManager.PlacementMode.BUILDING:
			_draw_building_ghost(current_grid_pos, ghost_color)
		PlacementManager.PlacementMode.DECORATION:
			var top_left_dec = terrain_grid.grid_to_screen(current_grid_pos)
			_draw_decoration_ghost(top_left_dec, ghost_color)

func _draw_tree_ghost(pos: Vector2, color: Color) -> void:
	var tree_type = placement_manager.selected_tree_type if placement_manager else "oak"

	# Use pixel art sprite if available
	if tree_type in TreeEntity.SPRITE_PATHS:
		var tex = load(TreeEntity.SPRITE_PATHS[tree_type]) as Texture2D
		if tex:
			var base_y = TreeEntity.SPRITE_BASE_OFFSETS.get(tree_type, 40.0)
			var tex_pos = pos - Vector2(tex.get_width() / 2.0, base_y + tex.get_height() / 2.0)
			draw_texture(tex, tex_pos, Color(1, 1, 1, color.a))
			return

	# Fallback to procedural polygon ghost
	var props = TreeEntity.TREE_PROPERTIES.get(tree_type, {})
	var base_foliage = props.get("color", Color(0.2, 0.5, 0.2))
	var base_trunk = props.get("trunk_color", Color(0.4, 0.2, 0.1))

	var var_params = TreeEntity.TREE_VARIATION.get(tree_type, TreeEntity.TREE_VARIATION["oak"])
	var variation = PropVariation.generate_custom_variation(
		current_grid_pos, var_params["scale"], var_params["rotation"], var_params["hue"])

	var scale_v = variation.scale
	var visual_h = props.get("visual_height", 48.0) * scale_v
	var base_w = props.get("base_width", 32.0) * scale_v

	var varied_foliage = variation.apply_color_shift(base_foliage)
	var foliage_color = Color(varied_foliage.r, varied_foliage.g, varied_foliage.b, color.a)
	var varied_trunk = variation.apply_color_shift(base_trunk)
	var trunk_color = Color(varied_trunk.r, varied_trunk.g, varied_trunk.b, color.a)

	draw_set_transform(pos, variation.rotation)
	var o = Vector2.ZERO

	if tree_type in TreeEntity.TRUNKLESS_TYPES:
		match tree_type:
			"cactus":
				var body_w = base_w * 0.35
				draw_rect(Rect2(o.x - body_w / 2, o.y - visual_h, body_w, visual_h), foliage_color)
				draw_rect(Rect2(o.x - base_w * 0.45, o.y - visual_h * 0.7, base_w * 0.25, body_w * 0.6), foliage_color)
				draw_rect(Rect2(o.x - base_w * 0.45, o.y - visual_h * 0.85, body_w * 0.5, visual_h * 0.2), foliage_color)
				draw_rect(Rect2(o.x + base_w * 0.2, o.y - visual_h * 0.45, base_w * 0.25, body_w * 0.6), foliage_color)
				draw_rect(Rect2(o.x + base_w * 0.2, o.y - visual_h * 0.6, body_w * 0.5, visual_h * 0.2), foliage_color)
			"fescue":
				for i in range(5):
					var x_off = (i - 2) * base_w * 0.2
					draw_line(o + Vector2(x_off, 0), o + Vector2(x_off, -visual_h), foliage_color, 2.0)
			"cattails":
				for i in range(3):
					var x_off = (i - 1) * 5.0 * scale_v
					draw_line(o + Vector2(x_off, 0), o + Vector2(x_off, -visual_h), foliage_color, 1.5)
					var head_color = Color(varied_trunk.r, varied_trunk.g, varied_trunk.b, color.a)
					draw_rect(Rect2(o.x + x_off - 2 * scale_v, o.y - visual_h - 6 * scale_v, 4 * scale_v, 8 * scale_v), head_color)
			"bush":
				draw_circle(o + Vector2(0, -visual_h * 0.5), base_w * 0.45, foliage_color)
			"heather":
				draw_circle(o + Vector2(0, -visual_h * 0.4), base_w * 0.4, foliage_color)
				var flower_color = Color(0.6, 0.3, 0.6, color.a)
				draw_circle(o + Vector2(-4 * scale_v, -visual_h * 0.6), 3 * scale_v, flower_color)
				draw_circle(o + Vector2(4 * scale_v, -visual_h * 0.5), 2.5 * scale_v, flower_color)
	else:
		var trunk_w = 6.0 * scale_v
		var trunk_h = visual_h * 0.4

		match tree_type:
			"palm":
				trunk_w = 5.0 * scale_v
				trunk_h = visual_h * 0.6
				draw_rect(Rect2(o.x - trunk_w / 2, o.y - trunk_h, trunk_w, trunk_h), trunk_color)
				for angle in [0, 60, 120, 180, 240, 300]:
					var rad = deg_to_rad(angle)
					var tip = o + Vector2(cos(rad) * base_w * 0.5, -trunk_h + sin(rad) * 10 * scale_v - 8 * scale_v)
					draw_line(o + Vector2(0, -trunk_h), tip, foliage_color, 2.5)
			"dead_tree":
				trunk_w = 8.0 * scale_v
				trunk_h = visual_h * 0.5
				draw_rect(Rect2(o.x - trunk_w / 2, o.y - trunk_h, trunk_w, trunk_h), trunk_color)
				var branch_color = Color(varied_trunk.r * 0.95, varied_trunk.g * 0.94, varied_trunk.b * 0.91, color.a)
				draw_line(o + Vector2(0, -trunk_h), o + Vector2(-14 * scale_v, -visual_h), branch_color, 2.0)
				draw_line(o + Vector2(0, -trunk_h), o + Vector2(12 * scale_v, -visual_h * 0.9), branch_color, 2.0)
				draw_line(o + Vector2(0, -trunk_h * 0.8), o + Vector2(-10 * scale_v, -trunk_h * 1.2), branch_color, 1.5)
			"pine":
				draw_rect(Rect2(o.x - trunk_w / 2, o.y - trunk_h, trunk_w, trunk_h), trunk_color)
				var tri = PackedVector2Array([
					o + Vector2(0, -visual_h),
					o + Vector2(-base_w * 0.5, -trunk_h),
					o + Vector2(base_w * 0.5, -trunk_h)
				])
				draw_colored_polygon(tri, foliage_color)
			_:
				draw_rect(Rect2(o.x - trunk_w / 2, o.y - trunk_h, trunk_w, trunk_h), trunk_color)
				var foliage_r = base_w * 0.5
				draw_circle(o + Vector2(0, -trunk_h - foliage_r * 0.7), foliage_r, foliage_color)
				draw_circle(o + Vector2(0, -trunk_h - foliage_r * 1.5), foliage_r * 0.7, foliage_color)

	draw_set_transform(Vector2.ZERO, 0.0)

func _draw_rock_ghost(pos: Vector2, color: Color) -> void:
	# Use pixel art sprite if available
	var rock_size = placement_manager.selected_rock_size if placement_manager else "medium"
	if rock_size in Rock.SPRITE_PATHS:
		var tex = load(Rock.SPRITE_PATHS[rock_size]) as Texture2D
		if tex:
			var offset_y = Rock.SPRITE_BASE_OFFSETS.get(rock_size, 12.0)
			var tex_pos = pos - Vector2(tex.get_width() / 2.0, offset_y)
			draw_texture(tex, tex_pos, Color(1, 1, 1, color.a))
			return

	# Fallback to procedural polygon ghost
	var rock_color = Color(0.5, 0.5, 0.5, color.a)
	var points = PackedVector2Array([
		pos + Vector2(-12, 0),
		pos + Vector2(-8, -10),
		pos + Vector2(0, -14),
		pos + Vector2(10, -8),
		pos + Vector2(14, 0),
		pos + Vector2(8, 6),
		pos + Vector2(-6, 4)
	])
	draw_colored_polygon(points, rock_color)

	var highlight = rock_color
	highlight.a *= 0.5
	draw_circle(pos + Vector2(-3, -6), 4, highlight)

func _draw_building_ghost(grid_pos: Vector2i, color: Color) -> void:
	var footprint = placement_manager.get_building_footprint()
	var fw = 1
	var fh = 1
	for offset in footprint:
		fw = max(fw, offset.x + 1)
		fh = max(fh, offset.y + 1)

	var w = fw * 64.0
	var h = fh * 32.0
	var pos: Vector2
	if terrain_grid != null:
		if terrain_grid.is_view_isometric():
			var center := terrain_grid.grid_point_to_screen(
					Vector2(grid_pos) + Vector2(fw * 0.5, fh * 0.5))
			pos = center - Vector2(w * 0.5, h)
		else:
			pos = terrain_grid.grid_to_screen(Vector2i(grid_pos))
	else:
		pos = Vector2(grid_pos)
	var building_type = placement_manager.selected_building_type

	if not is_instance_valid(_building_ghost):
		return
	_building_ghost.kind = building_type
	_building_ghost.footprint = Vector2(w, h)
	_building_ghost.position = pos
	_building_ghost.modulate = Color(color.r * 1.5, color.g * 1.5, color.b * 1.5, color.a)
	_building_ghost.visible = true
	_building_ghost.queue_redraw()

func _draw_decoration_ghost(pos: Vector2, color: Color) -> void:
	"""Draw ghost preview for decoration placement using Decoration sprites/fallback"""
	var footprint = placement_manager.get_placement_footprint()
	var fw = 1
	var fh = 1
	for offset in footprint:
		fw = max(fw, offset.x + 1)
		fh = max(fh, offset.y + 1)

	var w = fw * 64.0
	var h = fh * 32.0
	var a = color.a
	var dec_type = placement_manager.selected_decoration_type

	var layout := PathFurniture.layout(terrain_grid, current_grid_pos, dec_type)
	var anchor := terrain_grid.grid_to_screen_center(current_grid_pos) + Vector2(layout.offset)
	if GardenArt.has_art(dec_type):
		_garden_ghost.kind = dec_type
		_garden_ghost.position = anchor
		_garden_ghost.modulate = Color(1, 1, 1, a) if current_preview_valid else Color(1, .45, .4, a)
		_garden_ghost.visible = true
		_garden_ghost.queue_redraw()
		return
	if PathFurniture.has_art(dec_type):
		draw_set_transform(anchor)
		PathFurniture.draw_item(self, dec_type, layout.facing, a)
		draw_set_transform(Vector2.ZERO)
		return

	# Use the same foot anchor and deterministic transform as the placed sprite.
	if dec_type in Decoration.SPRITE_PATHS:
		var sprite_path = Decoration.SPRITE_PATHS[dec_type]
		if ResourceLoader.exists(sprite_path):
			var tex = load(sprite_path) as Texture2D
			if tex:
				var variation := Decoration.visual_variation(dec_type, current_grid_pos)
				var offset_y: float = Decoration.SPRITE_BASE_OFFSETS.get(dec_type, 16.0)
				var tint := variation.apply_color_shift(Color.WHITE)
				tint.a = a
				draw_set_transform(anchor, variation.rotation, Vector2.ONE * variation.scale)
				draw_texture(tex, -tex.get_size() * 0.5 - Vector2(0, offset_y), tint)
				draw_set_transform(Vector2.ZERO)
				return

	# Procedural fallback: simple colored shape
	var dec_color = Decoration.DECORATION_COLORS.get(dec_type, Color(0.5, 0.5, 0.5))
	dec_color.a = a
	var cx = pos.x + w / 2.0
	var cy = pos.y + h / 2.0
	# Draw a diamond/rhombus shape
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, pos.y + 2),
		Vector2(pos.x + w - 4, cy),
		Vector2(cx, pos.y + h - 2),
		Vector2(pos.x + 4, cy)
	]), dec_color)

func _draw_ghost_clubhouse(pos: Vector2, w: float, h: float, a: float) -> void:
	var cx = pos.x + w / 2.0
	# Wall
	draw_rect(Rect2(pos.x, pos.y + h * 0.18, w, h * 0.82), Color(0.96, 0.94, 0.88, a))
	# Roof
	draw_colored_polygon(PackedVector2Array([
		Vector2(pos.x - 6, pos.y + h * 0.16),
		Vector2(cx, pos.y - h * 0.22),
		Vector2(pos.x + w + 6, pos.y + h * 0.16)
	]), Color(0.52, 0.32, 0.26, a))
	# Door
	var dw = w * 0.22
	draw_rect(Rect2(cx - dw / 2.0, pos.y + h * 0.42, dw, h * 0.58), Color(0.48, 0.3, 0.18, a))
	# Windows
	for xr in [0.18, 0.78]:
		draw_rect(Rect2(pos.x + w * xr - 11, pos.y + h * 0.34, 22, 28), Color(0.6, 0.78, 0.88, a))

func _draw_ghost_pro_shop(pos: Vector2, w: float, h: float, a: float) -> void:
	# White building with green awning
	draw_rect(Rect2(pos.x, pos.y + h * 0.15, w, h * 0.85), Color(0.95, 0.95, 0.92, a))
	# Green awning roof
	draw_colored_polygon(PackedVector2Array([
		Vector2(pos.x - 3, pos.y + h * 0.12),
		Vector2(pos.x + w + 3, pos.y + h * 0.12),
		Vector2(pos.x + w + 5, pos.y + h * 0.2),
		Vector2(pos.x - 5, pos.y + h * 0.2)
	]), Color(0.2, 0.5, 0.3, a))
	# Storefront window
	draw_rect(Rect2(pos.x + w * 0.1, pos.y + h * 0.3, w * 0.55, h * 0.55), Color(0.75, 0.88, 0.95, a))
	# Door
	draw_rect(Rect2(pos.x + w * 0.72, pos.y + h * 0.45, w * 0.2, h * 0.55), Color(0.55, 0.4, 0.25, a))

func _draw_ghost_restaurant(pos: Vector2, w: float, h: float, a: float) -> void:
	var cx = pos.x + w / 2.0
	# Warm brick walls
	draw_rect(Rect2(pos.x, pos.y + h * 0.15, w, h * 0.85), Color(0.75, 0.55, 0.45, a))
	# Peaked roof
	draw_colored_polygon(PackedVector2Array([
		Vector2(pos.x - 3, pos.y + h * 0.15),
		Vector2(cx, pos.y - h * 0.15),
		Vector2(pos.x + w + 3, pos.y + h * 0.15)
	]), Color(0.45, 0.3, 0.25, a))
	# Warm glowing windows
	for i in range(3):
		var xo = pos.x + w * (0.18 + i * 0.28)
		draw_rect(Rect2(xo - 11, pos.y + h * 0.38, 22, h * 0.29), Color(1.0, 0.9, 0.6, a * 0.9))
	# Door
	draw_rect(Rect2(pos.x + w * 0.42, pos.y + h * 0.78, w * 0.16, h * 0.22), Color(0.45, 0.3, 0.2, a))

func _draw_ghost_snack_bar(pos: Vector2, w: float, h: float, a: float) -> void:
	# Yellow kiosk
	draw_rect(Rect2(pos.x, pos.y + h * 0.2, w, h * 0.8), Color(0.95, 0.8, 0.3, a))
	# Red striped awning
	draw_colored_polygon(PackedVector2Array([
		Vector2(pos.x - 4, pos.y + h * 0.15),
		Vector2(pos.x + w + 4, pos.y + h * 0.15),
		Vector2(pos.x + w + 6, pos.y + h * 0.28),
		Vector2(pos.x - 6, pos.y + h * 0.28)
	]), Color(0.9, 0.3, 0.2, a))
	# White stripes on awning
	for i in range(5):
		var x1 = pos.x + i * w / 4.5
		draw_rect(Rect2(x1, pos.y + h * 0.16, w / 9, h * 0.11), Color(0.95, 0.95, 0.95, a))
	# Counter window
	draw_rect(Rect2(pos.x + w * 0.1, pos.y + h * 0.35, w * 0.8, h * 0.4), Color(0.25, 0.2, 0.18, a))

func _draw_ghost_driving_range(pos: Vector2, w: float, h: float, a: float) -> void:
	# Green turf outfield
	draw_rect(Rect2(pos.x, pos.y, w, h * 0.35), Color(0.35, 0.65, 0.35, a))
	# Concrete pad
	draw_rect(Rect2(pos.x, pos.y + h * 0.35, w, h * 0.65), Color(0.75, 0.72, 0.68, a))
	# Canopy roof
	draw_colored_polygon(PackedVector2Array([
		Vector2(pos.x - 3, pos.y + h * 0.32),
		Vector2(pos.x + w + 3, pos.y + h * 0.32),
		Vector2(pos.x + w + 5, pos.y + h * 0.42),
		Vector2(pos.x - 5, pos.y + h * 0.42)
	]), Color(0.4, 0.35, 0.3, a))
	# Hitting mats
	for i in range(3):
		var mx = pos.x + w * (0.2 + i * 0.28)
		draw_rect(Rect2(mx - 18, pos.y + h * 0.55, 36, h * 0.35), Color(0.25, 0.55, 0.3, a))

func _draw_ghost_cart_shed(pos: Vector2, w: float, h: float, a: float) -> void:
	# Back wall
	draw_rect(Rect2(pos.x, pos.y + h * 0.15, w, h * 0.45), Color(0.55, 0.48, 0.42, a))
	# Concrete floor
	draw_rect(Rect2(pos.x, pos.y + h * 0.6, w, h * 0.4), Color(0.7, 0.68, 0.65, a))
	# Roof
	draw_colored_polygon(PackedVector2Array([
		Vector2(pos.x - 4, pos.y + h * 0.1),
		Vector2(pos.x + w + 4, pos.y + h * 0.1),
		Vector2(pos.x + w + 6, pos.y + h * 0.22),
		Vector2(pos.x - 6, pos.y + h * 0.22)
	]), Color(0.35, 0.32, 0.28, a))
	# Golf carts
	for i in range(2):
		var cx = pos.x + w * (0.25 + i * 0.45)
		draw_rect(Rect2(cx - 20, pos.y + h * 0.45, 40, h * 0.4), Color(0.95, 0.95, 0.9, a))
		draw_rect(Rect2(cx - 18, pos.y + h * 0.35, 36, h * 0.13), Color(0.3, 0.5, 0.35, a))

func _draw_ghost_restroom(pos: Vector2, w: float, h: float, a: float) -> void:
	# Light gray building
	draw_rect(Rect2(pos.x, pos.y + h * 0.2, w, h * 0.8), Color(0.88, 0.88, 0.85, a))
	# Flat roof
	draw_colored_polygon(PackedVector2Array([
		Vector2(pos.x - 2, pos.y + h * 0.15),
		Vector2(pos.x + w + 2, pos.y + h * 0.15),
		Vector2(pos.x + w + 3, pos.y + h * 0.25),
		Vector2(pos.x - 3, pos.y + h * 0.25)
	]), Color(0.45, 0.42, 0.38, a))
	# Two doors
	for i in range(2):
		var dx = pos.x + w * (0.2 + i * 0.45)
		draw_rect(Rect2(dx - 10, pos.y + h * 0.38, 20, h * 0.62), Color(0.5, 0.45, 0.4, a))
	# Gender signs
	draw_rect(Rect2(pos.x + w * 0.15, pos.y + h * 0.45, w * 0.1, h * 0.13), Color(0.3, 0.5, 0.7, a))
	draw_rect(Rect2(pos.x + w * 0.6, pos.y + h * 0.45, w * 0.1, h * 0.13), Color(0.7, 0.4, 0.5, a))

func _draw_ghost_bench(pos: Vector2, w: float, h: float, a: float) -> void:
	# Metal frame legs
	var frame_color = Color(0.25, 0.25, 0.28, a)
	for xr in [0.18, 0.82]:
		draw_rect(Rect2(pos.x + w * xr - 4, pos.y + h * 0.25, 8, h * 0.7), frame_color)
	# Wooden backrest slats
	for i in range(3):
		var sy = pos.y + h * (0.28 + i * 0.08)
		var c = Color(0.55, 0.38, 0.22, a) if i % 2 == 0 else Color(0.65, 0.48, 0.3, a)
		draw_rect(Rect2(pos.x + w * 0.15, sy, w * 0.7, 5), c)
	# Wooden seat slats
	for i in range(3):
		var sy = pos.y + h * (0.52 + i * 0.1)
		var c = Color(0.55, 0.38, 0.22, a) if i % 2 == 0 else Color(0.65, 0.48, 0.3, a)
		draw_rect(Rect2(pos.x + w * 0.12, sy, w * 0.76, 6), c)

func _draw_ghost_generic(pos: Vector2, w: float, h: float, a: float) -> void:
	# Gray building
	draw_rect(Rect2(pos.x, pos.y + h * 0.2, w, h * 0.8), Color(0.72, 0.7, 0.68, a))
	# Flat roof
	draw_colored_polygon(PackedVector2Array([
		Vector2(pos.x - 2, pos.y + h * 0.15),
		Vector2(pos.x + w + 2, pos.y + h * 0.15),
		Vector2(pos.x + w + 3, pos.y + h * 0.25),
		Vector2(pos.x - 3, pos.y + h * 0.25)
	]), Color(0.5, 0.45, 0.4, a))
	# Window
	draw_rect(Rect2(pos.x + w * 0.3, pos.y + h * 0.35, w * 0.4, h * 0.25), Color(0.7, 0.82, 0.9, a))
	# Door
	draw_rect(Rect2(pos.x + w * 0.4, pos.y + h * 0.65, w * 0.2, h * 0.35), Color(0.45, 0.35, 0.28, a))

# =============================================================================
# POTENTIAL HOLE PATH
# =============================================================================

## Draw the hole the hovered tile would make: the waiting tee, the expected shot
## route (dashed; a straight provisional line while a par 4/5 route is planned),
## the landing zones, the cup-to-be and a "Hole N · Par P · Y yds" plaque.
func _draw_potential_hole(alpha: float) -> void:
	var hole := potential_hole
	var tee: Vector2i = hole.tee
	var cup: Vector2i = hole.cup
	var hole_ready: bool = hole.ready
	var planned: bool = not potential_hole_route.is_empty()

	var points := PackedVector2Array()
	if planned:
		for waypoint in potential_hole_route:
			points.append(OverlayGeometry.tile_center(terrain_grid, self, waypoint))
	else:
		# Par 4/5 route still being planned: a provisional straight line.
		points.append(OverlayGeometry.tile_center(terrain_grid, self, tee))
		points.append(OverlayGeometry.tile_center(terrain_grid, self, cup))

	# The waiting tee this cup would pair with.
	var pulse := 0.75 + sin(_pulse_time) * 0.25
	draw_polyline(OverlayGeometry.tile_polyline(terrain_grid, self, tee),
			Color(HOLE_PATH_TEE, HOLE_PATH_TEE.a * alpha * pulse), 2.0)
	# Forward (red) / middle (white) tees Open Hole will add when multi-tee is on,
	# in HoleVisualizer's tee-marker colours.
	var extra_tees: Dictionary = hole.get("extra_tees", {})
	for tee_key in extra_tees:
		var marker_color := Color(0.9, 0.2, 0.2) if tee_key == "forward" else Color(0.9, 0.9, 0.9)
		draw_colored_polygon(OverlayGeometry.tile_polygon(terrain_grid, self, extra_tees[tee_key]),
				Color(marker_color, 0.3 * alpha * pulse))

	# Route: a soft dark underlay keeps the dashes readable on any turf.
	var line_color := HOLE_PATH_COLOR if hole_ready else HOLE_PATH_BLOCKED
	line_color.a *= alpha * (1.0 if planned else 0.6)
	if points[0].distance_to(points[points.size() - 1]) >= 1.0:
		draw_polyline(points, Color(HOLE_PATH_SHADOW, HOLE_PATH_SHADOW.a * alpha),
				HOLE_PATH_WIDTH + 2.0, true)
	for i in range(points.size() - 1):
		if points[i].distance_to(points[i + 1]) >= 1.0:
			draw_dashed_line(points[i], points[i + 1], line_color, HOLE_PATH_WIDTH,
					HOLE_PATH_DASH, true, true)

	# Landing zones, styled like the markers HoleVisualizer draws once the hole opens.
	for i in range(1, points.size() - 1):
		draw_circle(points[i], 5.0, Color(0.0, 0.0, 0.0, 0.5 * alpha))
		draw_circle(points[i], 3.5, Color(HOLE_PATH_LANDING, HOLE_PATH_LANDING.a * alpha))

	var cup_point := points[points.size() - 1]
	var pin_top := _draw_potential_cup(cup, cup_point, alpha, hole_ready)
	_draw_potential_hole_label(hole, pin_top, alpha)

## Cup ellipse plus a small gold pin, previewing the waiting pin CupOverlay will
## plant. Returns the top of the pin so the plaque can sit above it.
func _draw_potential_cup(cup: Vector2i, cup_point: Vector2, alpha: float, hole_ready: bool) -> Vector2:
	var right := OverlayGeometry.point_in_tile(terrain_grid, self, cup, Vector2(1.0, 0.5))
	var bottom := OverlayGeometry.point_in_tile(terrain_grid, self, cup, Vector2(0.5, 1.0))
	var radius := Vector2((right - cup_point).length(), (bottom - cup_point).length()) \
			* CupOverlay.CUP_RADIUS_SCALE
	var ellipse := PackedVector2Array()
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		ellipse.append(cup_point + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(ellipse, Color(CupOverlay.CUP_COLOR, CupOverlay.CUP_COLOR.a * alpha))

	var pin_color := CupOverlay.WAITING_PIN_COLOR if hole_ready else HOLE_PATH_BLOCKED
	var pole_top := cup_point - Vector2(0.0, CupOverlay.WAITING_POLE_HEIGHT * 0.75)
	draw_line(cup_point, pole_top, Color(0.95, 0.95, 0.92, 0.9 * alpha), 1.5, true)
	draw_colored_polygon(PackedVector2Array([
		pole_top,
		pole_top + Vector2(CupOverlay.WAITING_FLAG_LENGTH * 0.8, 3.5),
		pole_top + Vector2(0.0, 7.0),
	]), Color(pin_color, alpha))
	return pole_top

## "Hole N · Par P · Y yds", plus why the pair can't open yet. Drawn at a constant
## on-screen size so it stays legible however far the camera is zoomed out.
func _draw_potential_hole_label(hole: Dictionary, anchor: Vector2, alpha: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var title := "Hole %d · Par %d · %d yds" % [hole.hole_number, hole.par, hole.distance_yards]
	var note: String = hole.reason
	var title_size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, HOLE_PATH_FONT_SIZE)
	var note_size := Vector2.ZERO
	if not note.is_empty():
		note_size = font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, HOLE_PATH_NOTE_FONT_SIZE)
	var padding := Vector2(8.0, 4.0)
	var box_size := Vector2(maxf(title_size.x, note_size.x), title_size.y + note_size.y) + padding * 2.0
	var box := Rect2(Vector2(-box_size.x * 0.5, -box_size.y - 6.0), box_size)

	if _label_style == null:
		_label_style = StyleBoxFlat.new()
		_label_style.set_corner_radius_all(4)
		_label_style.set_border_width_all(1)
	_label_style.bg_color = Color(0.125, 0.247, 0.196, 0.87 * alpha)  # HoleVisualizer plaque green
	_label_style.border_color = Color(UIConstants.COLOR_GOLD if hole.ready else HOLE_PATH_BLOCKED, alpha)

	var screen_scale := 1.0 / camera.zoom.x if camera and camera.zoom.x > 0.0 else 1.0
	draw_set_transform(anchor, 0.0, Vector2(screen_scale, screen_scale))
	draw_style_box(_label_style, box)
	var baseline := box.position.y + padding.y + font.get_ascent(HOLE_PATH_FONT_SIZE)
	draw_string(font, Vector2(box.position.x + padding.x, baseline), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, HOLE_PATH_FONT_SIZE, Color(UIConstants.COLOR_TEXT, alpha))
	if not note.is_empty():
		baseline += title_size.y
		draw_string(font, Vector2(box.position.x + padding.x, baseline), note,
				HORIZONTAL_ALIGNMENT_LEFT, -1, HOLE_PATH_NOTE_FONT_SIZE,
				Color(1.0, 0.72, 0.68, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_hole_move_preview() -> void:
	if not camera or not terrain_grid:
		return

	var mouse_world = camera.get_mouse_world_position()
	var hover_pos = terrain_grid.screen_to_grid(mouse_world)
	if not terrain_grid.is_valid_position(hover_pos):
		return

	# Determine validity and color based on mode
	var is_valid = false
	var preview_color: Color
	var label_text: String

	# HoleMoveMode: 1=PIN, 2=TEE, 3=GREEN (matches main.gd enum)
	match _hole_move_mode:
		1:  # MOVING_PIN
			is_valid = terrain_grid.get_tile(hover_pos) == TerrainTypes.Type.GREEN
			preview_color = Color(0.3, 0.9, 0.5, 0.5) if is_valid else Color(0.9, 0.3, 0.3, 0.3)
			label_text = "Pin"
		2:  # MOVING_TEE
			var tile = terrain_grid.get_tile(hover_pos)
			is_valid = not TerrainTypes.is_water(tile) and tile != TerrainTypes.Type.OUT_OF_BOUNDS
			preview_color = Color(0.4, 0.85, 0.45, 0.5) if is_valid else Color(0.9, 0.3, 0.3, 0.3)
			label_text = "Tee"
		3:  # MOVING_GREEN
			var tile = terrain_grid.get_tile(hover_pos)
			is_valid = not TerrainTypes.is_water(tile) and tile != TerrainTypes.Type.OUT_OF_BOUNDS
			preview_color = Color(0.3, 0.9, 0.5, 0.5) if is_valid else Color(0.9, 0.3, 0.3, 0.3)
			label_text = "Green"
		4:  # MOVING_FORWARD_TEE
			var tile = terrain_grid.get_tile(hover_pos)
			is_valid = not TerrainTypes.is_water(tile) and tile != TerrainTypes.Type.OUT_OF_BOUNDS
			preview_color = Color(0.9, 0.3, 0.3, 0.5) if is_valid else Color(0.9, 0.3, 0.3, 0.3)
			label_text = "Fwd Tee"
		5:  # MOVING_MIDDLE_TEE
			var tile = terrain_grid.get_tile(hover_pos)
			is_valid = not TerrainTypes.is_water(tile) and tile != TerrainTypes.Type.OUT_OF_BOUNDS
			preview_color = Color(0.85, 0.85, 0.85, 0.5) if is_valid else Color(0.9, 0.3, 0.3, 0.3)
			label_text = "Mid Tee"

	if not is_valid:
		return

	var pulse = 0.7 + sin(_pulse_time) * 0.3
	preview_color.a *= pulse
	draw_colored_polygon(OverlayGeometry.tile_polygon(terrain_grid, self, hover_pos), preview_color)
	draw_polyline(OverlayGeometry.tile_polyline(terrain_grid, self, hover_pos),
			Color(1.0, 1.0, 1.0, 0.7 * pulse), 2.0)

	var font = ThemeDB.fallback_font
	var center = terrain_grid.grid_to_screen_center(hover_pos)
	draw_string(font, center + Vector2(-20, -20), label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(1, 1, 1, 0.9))

# =============================================================================
# PUBLIC API
# =============================================================================

func get_preview_valid() -> bool:
	return current_preview_valid

func get_preview_positions() -> Array:
	return current_preview_positions

func get_current_grid_pos() -> Vector2i:
	return current_grid_pos

func confirm_placement() -> void:
	if current_preview_valid and current_grid_pos != Vector2i(-1, -1):
		var placement_type = ""
		match placement_manager.placement_mode:
			PlacementManager.PlacementMode.TREE:
				placement_type = "tree"
			PlacementManager.PlacementMode.ROCK:
				placement_type = "rock"
			PlacementManager.PlacementMode.BUILDING:
				placement_type = "building"
			PlacementManager.PlacementMode.DECORATION:
				placement_type = "decoration"
		placement_confirmed.emit(current_grid_pos, placement_type)
