extends TerrainTileButton
class_name BuildingTileButton
## A building catalogue choice drawn as the same isometric diamond as a
## Course/Hazards terrain button.
##
## The tile uses a natural-grass preview underneath a compact architecture
## thumbnail. Building name remains centred on the diamond, while price and
## upkeep stay available through the normal rich tooltip and accessibility
## description instead of crowding the small tile.

var building_data: Dictionary = {}
var _building_art: BuildingTileArt = null

func configure_building(building_type: String, data: Dictionary) -> void:
	building_data = data.duplicate(true)
	var description := str(data.get("description", "Select this facility to place it."))
	if description.is_empty():
		description = "Select this facility to place it."
	var cost := int(data.get("cost", 0))
	var upkeep := int(data.get("operating_cost", 0))
	configure(
		building_type,
		str(data.get("name", building_type)),
		"",
		"",
		description,
		cost,
		upkeep)
	tooltip_text = _make_tooltip()
	accessibility_description = "%s. Build $%d. Upkeep $%d per day. %s" % [
		tool_name, cost, upkeep, description]

func _ready() -> void:
	super._ready()
	_build_building_art()
	_update_visual_state()

func _build_building_art() -> void:
	_building_art = BuildingTileArt.new()
	_building_art.name = "BuildingPreview"
	_building_art.position = Vector2.ZERO
	_building_art.configure(tool_type, building_data)
	add_child(_building_art)
	# TerrainTileButton creates its caption before this preview is added. Keep
	# the caption last so the building drawing never obscures the name.
	if _name_label:
		move_child(_building_art, _name_label.get_index())

func _make_tooltip() -> String:
	var name := str(building_data.get("name", tool_name))
	var cost := int(building_data.get("cost", 0))
	var upkeep := int(building_data.get("operating_cost", 0))
	var description := str(building_data.get("description", "Select this facility to place it."))
	return "%s\nBuild: $%d\nUpkeep: $%d/day\n%s" % [name, cost, upkeep, description]
