extends PanelContainer
class_name TileInspector
## Read-only, mouse-following tile details. Does not capture pointer input.

const MOUSE_OFFSET := Vector2(20, 20)
const VIEWPORT_MARGIN := 10.0

var _title: Label
var _details: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	hide()
	var style := StyleBoxFlat.new()
	style.bg_color = UIConstants.COLOR_BG_PANEL
	style.border_color = UIConstants.COLOR_GOLD
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	_title = Label.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
	column.add_child(_title)
	_details = Label.new()
	_details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_details.add_theme_color_override("font_color", UIConstants.COLOR_TEXT)
	column.add_child(_details)

## Kept separate from presentation so every layer can be tested without a mouse.
static func describe_tile(grid: TerrainGrid, entities: EntityLayer, tile: Vector2i) -> Dictionary:
	if not grid.is_valid_position(tile):
		return {}
	var ground: int = grid.get_tile(tile)
	var terrain := TerrainTypes.get_type_name(ground)
	# A woodland tile says what the species is planted in, since each one paints
	# its own ground: litter, needles, sand, silt, peat or straw.
	var planted := TerrainTypes.get_tree_ground(ground)
	if not planted.is_empty():
		terrain = "%s (%s)" % [terrain, planted]
	var improvements: Array[String] = []
	var buildings := "None"
	if grid.has_walking_path(tile):
		improvements.append("Walking Path")
	if entities:
		var decoration := entities.get_decoration_at(tile)
		if decoration:
			improvements.append(decoration.decoration_data.get("name", decoration.decoration_type.capitalize()))
		var building := entities.get_building_containing(tile)
		if building:
			buildings = building.get_display_name()
	return {
		"terrain": terrain,
		"improvements": ", ".join(improvements) if not improvements.is_empty() else "None",
		"buildings": buildings,
	}

func show_tile(grid: TerrainGrid, entities: EntityLayer, tile: Vector2i, mouse: Vector2) -> void:
	var details := describe_tile(grid, entities, tile)
	if details.is_empty():
		hide()
		return
	_title.text = "Inspect • Tile (%d, %d)" % [tile.x, tile.y]
	_details.text = "Terrain: %s\nImprovements: %s\nBuildings: %s" % [
		details.terrain, details.improvements, details.buildings]
	reset_size()
	var bounds := get_viewport_rect().size
	var target := mouse + MOUSE_OFFSET
	if target.x + size.x > bounds.x - VIEWPORT_MARGIN:
		target.x = mouse.x - size.x - MOUSE_OFFSET.x
	if target.y + size.y > bounds.y - VIEWPORT_MARGIN:
		target.y = mouse.y - size.y - MOUSE_OFFSET.y
	position = target.clamp(Vector2.ONE * VIEWPORT_MARGIN,
		(bounds - size - Vector2.ONE * VIEWPORT_MARGIN).max(Vector2.ONE * VIEWPORT_MARGIN))
	show()
