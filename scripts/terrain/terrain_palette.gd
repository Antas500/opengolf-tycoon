extends RefCounted
class_name TerrainPalette
## Theme-aware fallback colors for terrain rendering and tool previews.

static var _active_colors: Dictionary = {}

const TERRAIN_COLORS := {
	"grass": Color("719447"),
	"fairway_light": Color("8bb954"),
	"fairway_dark": Color("7ba74b"),
	"green_light": Color("a4ca67"),
	"green_dark": Color("97bc5b"),
	"fringe": Color("749b45"),
	"rough": Color("5f803b"),
	"heavy_rough": Color("4a6935"),
	"bunker": Color("eddeb0"),
	"water": Color("47877e"),
	"empty": Color(0.18, 0.22, 0.18),
	"tee_box_light": Color("96ba5e"),
	"tee_box_dark": Color("85a650"),
	"path": Color("c9bc98"),
	"oob": Color(0.40, 0.33, 0.30),
	"trees": Color(0.20, 0.42, 0.20),
	"flower_bed": Color(0.45, 0.32, 0.22),
	"rocks": Color(0.48, 0.46, 0.42),
	"firm_fairway": Color("9aad58"),
	"pot_bunker": Color("d8c690"),
	"stream": Color("5aa3a6"),
	"deep_rough": Color("3e5a2e"),
	"waste_bunker": Color("c9b98e"),
	"brush": Color("58622e"),
}

static func set_theme_colors(colors: Dictionary) -> void:
	_active_colors = colors

static func get_color(key: String) -> Color:
	if _active_colors.has(key):
		return _active_colors[key]
	return TERRAIN_COLORS.get(key, Color.MAGENTA)
