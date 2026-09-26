extends TerrainTileButton
class_name DecorationTileButton
## A decoration catalogue choice drawn as the same isometric diamond as a
## Course Terrain or Buildings tile.
##
## Every ornament The Garden Shed used to list is a tile here: the artwork is
## the one used on the course, the caption is the decoration's name, and price,
## upkeep and unlock requirements live in the rich TooltipManager hover popup
## instead of crowding the small tile. The native Godot tooltip is deliberately
## left empty so hovering shows a single popup.
##
## Locked ornaments stay on the shelf, greyed out and unselectable, and their
## tooltip says what still has to be earned.

## Catalogue categories in the order The Garden Shed listed them, so related
## ornaments stay side by side on the shelf.
const CATEGORY_ORDER := ["landscaping", "water", "structures", "furniture", "sculptures"]
const CATEGORY_TITLES := {
	"landscaping": "Landscaping",
	"water": "Water features",
	"structures": "Structures",
	"furniture": "Furniture",
	"sculptures": "Sculptures",
}
const DEFAULT_DESCRIPTION := "Aesthetic decoration that raises the course rating."

var decoration_type: String = ""
var decoration_data: Dictionary = {}
var locked: bool = false
var _decoration_art: DecorationTileArt = null

func configure_decoration(type: String, data: Dictionary) -> void:
	decoration_type = type
	decoration_data = data.duplicate(true)
	configure(
		type,
		str(data.get("name", type.capitalize())),
		"",
		"",
		tooltip_description(data),
		int(data.get("cost", 0)),
		int(data.get("daily_upkeep", 0)))
	tooltip_text = ""
	_update_accessibility()

func _ready() -> void:
	super._ready()
	# super._ready() rewrites the accessibility text for a shortcut. Restore the
	# catalogue wording now that the tile exists — decoration tiles have none.
	_update_accessibility()
	_build_decoration_art()
	_update_visual_state()

func _build_decoration_art() -> void:
	_decoration_art = DecorationTileArt.new()
	_decoration_art.name = "DecorationPreview"
	_decoration_art.configure(decoration_type)
	add_child(_decoration_art)
	# TerrainTileButton creates its caption before this preview is added. Keep
	# the caption last so the drawing never obscures the name.
	if _name_label:
		move_child(_decoration_art, _name_label.get_index())

## Grey out the tile while its unlock requirement is unmet, and say what it
## needs. Locked tiles stay visible — players can see what to aim for — but can
## never be selected.
func set_locked(value: bool, requirement: String = "") -> void:
	# An unlocked tile never mentions the requirement it has already met.
	var text := tooltip_description(decoration_data, requirement if value else "")
	if locked == value and disabled == value and tool_description == text:
		return  # The shelf re-checks every second; nothing has changed.
	locked = value
	disabled = value
	tool_description = text
	_update_accessibility()
	_update_visual_state()

## Hover text: the catalogue category, the decoration's own description and —
## while locked — the requirement still standing in the way.
static func tooltip_description(data: Dictionary, requirement: String = "") -> String:
	var description := str(data.get("description", ""))
	if description.is_empty():
		description = DEFAULT_DESCRIPTION
	var category := category_title(str(data.get("category", "")))
	var line := "%s: %s" % [category, description] if not category.is_empty() else description
	if requirement.is_empty():
		return line
	return "Locked — requires %s. %s" % [requirement, line]

static func category_title(category: String) -> String:
	return CATEGORY_TITLES.get(category, "")

func _update_accessibility() -> void:
	accessibility_description = "%s Cost $%d. Upkeep $%d per day." % [
		tool_description, cost, maintenance]
