extends Node2D
class_name BuildingTileArt
## Small footprint-aware building preview used by BuildingTileButton.
##
## Building catalogue buttons use the same diamond footprint as the terrain
## swatches, but keep the existing course-architecture drawings as their icon.
## The preview is deliberately compact so it stays inside the diamond while
## leaving the button caption readable on top.

const PREVIEW_SIZE := Vector2(84, 42)
const TILE_PIXEL_SIZE := Vector2(64, 32)

var building_type := ""
var building_data: Dictionary = {}

func configure(kind: String, data: Dictionary) -> void:
	building_type = kind
	building_data = data.duplicate(true)
	queue_redraw()

func _draw() -> void:
	if building_type.is_empty():
		return

	var dimensions: Array = building_data.get("size", [1, 1])
	if dimensions.size() < 2:
		return

	var footprint := Vector2(
		maxf(1.0, float(dimensions[0])) * TILE_PIXEL_SIZE.x,
		maxf(1.0, float(dimensions[1])) * TILE_PIXEL_SIZE.y)
	# CourseArchitecture draws its own depth and roof overhang. Fit the complete
	# footprint, rather than just its facade, into the middle of the diamond.
	var scale_factor := minf(0.34, 66.0 / maxf(footprint.x, 1.0))
	var baseline := footprint.y - 12.0
	var origin := Vector2(
		(PREVIEW_SIZE.x - footprint.x * scale_factor) * 0.5,
		34.0 - baseline * scale_factor)

	draw_set_transform(origin, 0.0, Vector2.ONE * scale_factor)
	CourseArchitecture.draw_building(self, building_type, footprint)
	draw_set_transform(Vector2.ZERO)
