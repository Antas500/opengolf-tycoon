extends TerrainTileButton
class_name BuildingTileButton
## A building catalogue choice drawn as the same isometric diamond as a
## Course/Hazards terrain button.
##
## The tile uses a natural-grass preview underneath a compact architecture
## thumbnail. Building name remains centred on the diamond, while price and
## upkeep are shown by the rich TooltipManager hover popup instead of crowding
## the small tile. The native Godot tooltip is deliberately left empty so
## hovering shows a single popup.

var building_data: Dictionary = {}
var _building_art: BuildingTileArt = null

func configure_building(building_type: String, data: Dictionary) -> void:
	building_data = data.duplicate(true)
	var description := str(data.get("description", "Select this facility to place it."))
	if description.is_empty():
		description = "Select this facility to place it."
	var building_cost := int(data.get("cost", 0))
	var upkeep := int(data.get("operating_cost", 0))
	configure(
		building_type,
		str(data.get("name", building_type)),
		"",
		"",
		description,
		building_cost,
		upkeep)
	tooltip_text = ""
	accessibility_description = "%s. Build $%d. Upkeep $%d per day. %s" % [
		tool_name, building_cost, upkeep, description]

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
