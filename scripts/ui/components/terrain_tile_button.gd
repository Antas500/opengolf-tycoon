extends ToolButton
class_name TerrainTileButton
## A course-painting tool drawn as one 2:1 isometric cell of CourseSurface.
## The preview samples grass around the chosen material, just like an isolated
## painted tile on the grid. Only the Terrain tab's paint tools use this button;
## other ToolButtons keep their usual rectangular appearance.
##
## The button is exactly the diamond — its name sits centred on the tile and the
## row below tucks into the notch it leaves (see TileHoneycomb) — so only the
## diamond itself answers to the mouse (see _has_point).

const TILE_SIZE := Vector2(84, 42)  # One projected course cell, 2:1 isometric.
const BUTTON_SIZE := TILE_SIZE      # No padding: rows interlock on the grid.
const NAME_FONT_SIZE := UIConstants.FONT_SIZE_XS
const NAME_FONT_SIZE_MIN := 8  # Longest names shrink instead of spilling out.
static var _white_texture: ImageTexture

static func tile_corners() -> PackedVector2Array:
	var center := BUTTON_SIZE * 0.5
	return PackedVector2Array([
		Vector2(center.x, center.y - TILE_SIZE.y * 0.5),
		Vector2(center.x + TILE_SIZE.x * 0.5, center.y),
		Vector2(center.x, center.y + TILE_SIZE.y * 0.5),
		Vector2(center.x - TILE_SIZE.x * 0.5, center.y),
	])

var _surface_material: ShaderMaterial
var _outline: Line2D
var _name_label: Label
var _hovered := false

func _ready() -> void:
	super._ready()
	_build_tile()
	focus_entered.connect(_update_visual_state)
	focus_exited.connect(_update_visual_state)
	EventBus.theme_changed.connect(_on_theme_changed)

func _exit_tree() -> void:
	if EventBus.theme_changed.is_connected(_on_theme_changed):
		EventBus.theme_changed.disconnect(_on_theme_changed)

func _update_button() -> void:
	# The tile and its caption replace ToolButton's flat sprite and button text.
	text = ""
	icon = null
	custom_minimum_size = BUTTON_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	accessibility_name = tool_name
	# The shortcut stays in the tooltip and the screen reader — not on the tile.
	accessibility_description = "%s Shortcut %s." % [tool_description, hotkey]
	if _name_label:
		_name_label.text = tool_name
		_fit_name_label()

func _create_styles() -> void:
	# No rectangular chrome: hover and selection are drawn around the diamond.
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, empty)

func _apply_styles() -> void:
	pass  # ToolButton.set_selected() still tracks selection; the outline shows it.

## True when `point` (local to the button) falls on the diamond rather than in
## the empty corners of its bounding box.
static func point_on_tile(point: Vector2) -> bool:
	var offset := (point - TILE_SIZE * 0.5).abs()
	return offset.x / (TILE_SIZE.x * 0.5) + offset.y / (TILE_SIZE.y * 0.5) <= 1.0

## Only the diamond is clickable. Rows of the honeycomb overlap as rectangles,
## so a rectangular hit area would let a lower tile steal clicks from the tile
## whose notch it sits in.
func _has_point(point: Vector2) -> bool:
	return TerrainTileButton.point_on_tile(point)

func _build_tile() -> void:
	var corners := tile_corners()
	var shadow := Polygon2D.new()
	shadow.polygon = corners
	shadow.position = Vector2(0, 2)
	shadow.color = Color(0, 0, 0, 0.4)
	add_child(shadow)

	var tile := Polygon2D.new()
	tile.polygon = corners
	# A 1px white texture ensures the polygon supplies interpolated UVs to the
	# course shader; all the actual colors come from its terrain palette.
	if _white_texture == null:
		var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		white.fill(Color.WHITE)
		_white_texture = ImageTexture.create_from_image(white)
	tile.texture = _white_texture
	tile.uv = PackedVector2Array([
		Vector2(0.5, 0), Vector2(1, 0.5), Vector2(0.5, 1), Vector2(0, 0.5),
	])
	tile.antialiased = true
	_surface_material = _make_surface_material()
	tile.material = _surface_material
	add_child(tile)

	_outline = Line2D.new()
	_outline.points = PackedVector2Array([corners[0], corners[1],
		corners[2], corners[3], corners[0]])
	_outline.antialiased = true
	add_child(_outline)

	# The name rides on the tile itself, centred on the diamond. The label
	# covers the whole button so the text stays centred whatever its width.
	_name_label = Label.new()
	_name_label.text = tool_name
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_constant_override("outline_size", 3)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)
	_fit_name_label()  # Font size first: it drives the label's minimum size.
	# Covering the whole tile keeps the text centred on the diamond whatever
	# the name's width, and stops the caption from being clipped to its text.
	_name_label.custom_minimum_size = BUTTON_SIZE
	_name_label.size = BUTTON_SIZE

	_refresh_palette()
	_update_visual_state()

## Shrink oversized names so they stay inside the diamond.
func _fit_name_label() -> void:
	var font := _name_label.get_theme_font("font")
	if font == null:
		_name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
		return
	var size := NAME_FONT_SIZE
	while size > NAME_FONT_SIZE_MIN and \
			font.get_string_size(tool_name, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x \
			> BUTTON_SIZE.x - 8.0:
		size -= 1
	_name_label.add_theme_font_size_override("font_size", size)

func _make_surface_material() -> ShaderMaterial:
	# The actual course shader operates on a 3x3 grid: the middle cell is this
	# tool's terrain, and the surrounding cells are natural grass. The shader's
	# grid origin places that middle cell exactly within the diamond's UVs.
	var terrain_data := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	terrain_data.fill(Color(float(TerrainTypes.Type.GRASS) / 255.0, 0, 0.5, 1))
	terrain_data.set_pixel(1, 1, Color(float(tool_type) / 255.0, 0, 0.5, 1))
	var elevation := Image.create(4, 4, false, Image.FORMAT_R8)
	elevation.fill(Color(0.5, 0, 0))

	var tile_size := Vector2(TilesetGenerator.TILE_WIDTH, TilesetGenerator.TILE_HEIGHT)
	var half_tile := tile_size * 0.5
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/course_surface.gdshader")
	mat.set_shader_parameter("terrain_data", ImageTexture.create_from_image(terrain_data))
	mat.set_shader_parameter("vertex_elevation", ImageTexture.create_from_image(elevation))
	mat.set_shader_parameter("grid_size", Vector2(3, 3))
	mat.set_shader_parameter("vertex_grid_size", Vector2(4, 4))
	mat.set_shader_parameter("tile_size", tile_size)
	mat.set_shader_parameter("grid_origin", Vector2(half_tile.x, -tile_size.y))
	mat.set_shader_parameter("grid_axis_x", half_tile)
	mat.set_shader_parameter("grid_axis_y", Vector2(-half_tile.x, half_tile.y))
	mat.set_shader_parameter("surface_origin", Vector2.ZERO)
	mat.set_shader_parameter("surface_size", tile_size)
	mat.set_shader_parameter("elevation_step_y", 0.0)  # Flat preview, no relief offset.
	mat.set_shader_parameter("is_isometric", true)
	return mat

func _refresh_palette() -> void:
	_surface_material.set_shader_parameter("palette", CourseSurface.make_palette_texture())
	_surface_material.set_shader_parameter("fringe_color", TilesetGenerator.get_color("fringe"))

func _on_theme_changed(_theme: int) -> void:
	_refresh_palette()

func _on_mouse_entered() -> void:
	_hovered = true
	_update_visual_state()
	super._on_mouse_entered()

func _on_mouse_exited() -> void:
	_hovered = false
	_update_visual_state()
	super._on_mouse_exited()

func set_selected(selected: bool) -> void:
	super.set_selected(selected)
	_update_visual_state()

func _update_visual_state() -> void:
	if _outline == null:
		return
	if is_selected():
		_outline.default_color = UIConstants.COLOR_GOLD
		_outline.width = 2.5
		_name_label.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
	elif _hovered or has_focus():
		_outline.default_color = UIConstants.COLOR_TEXT_DIM
		_outline.width = 2.0
		_name_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT)
	else:
		_outline.default_color = UIConstants.COLOR_BORDER
		_outline.width = 1.0
		_name_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	# The name sits on the tile, so it always carries a dark outline to stay
	# readable over pale surfaces such as sand and water.
	_name_label.add_theme_color_override("font_outline_color", Color(0.04, 0.09, 0.07, 0.9))
