extends RefCounted
class_name PropVariation
## Deterministic scale, rotation, and color variation for placed props.

static var map_seed: int = 0

class VariationResult:
	var scale: float = 1.0
	var rotation: float = 0.0  # In radians
	var hue_shift: float = 0.0
	var saturation_shift: float = 0.0
	var value_shift: float = 0.0

	func apply_color_shift(base_color: Color) -> Color:
		var h = base_color.h + hue_shift
		var s = clampf(base_color.s + saturation_shift, 0.0, 1.0)
		var v = clampf(base_color.v + value_shift, 0.0, 1.0)
		if h < 0.0:
			h += 1.0
		elif h > 1.0:
			h -= 1.0
		return Color.from_hsv(h, s, v, base_color.a)

static func set_map_seed(seed_value: int) -> void:
	map_seed = seed_value

static func _position_to_seed(grid_pos: Vector2i, extra_salt: int = 0) -> int:
	var hash_val = map_seed
	hash_val = hash_val * 31 + grid_pos.x * 73856093
	hash_val = hash_val * 31 + grid_pos.y * 19349663
	hash_val = hash_val * 31 + extra_salt * 83492791
	return absi(hash_val)

static func _seeded_random(grid_pos: Vector2i, channel: int = 0) -> float:
	var seed_val = _position_to_seed(grid_pos, channel)
	seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
	return float(seed_val) / float(0x7FFFFFFF)

static func _seeded_range(grid_pos: Vector2i, min_val: float, max_val: float, channel: int = 0) -> float:
	return lerpf(min_val, max_val, _seeded_random(grid_pos, channel))

static func generate_custom_variation(
	grid_pos: Vector2i,
	scale_range: Vector2 = Vector2(0.85, 1.15),
	rotation_range: Vector2 = Vector2(-8.0, 8.0),
	hue_range: Vector2 = Vector2(-0.03, 0.03),
	saturation_range: Vector2 = Vector2(-0.1, 0.1),
	value_range: Vector2 = Vector2(-0.08, 0.08)
) -> VariationResult:
	var result = VariationResult.new()
	result.scale = _seeded_range(grid_pos, scale_range.x, scale_range.y, 0)
	result.rotation = deg_to_rad(_seeded_range(grid_pos, rotation_range.x, rotation_range.y, 1))
	result.hue_shift = _seeded_range(grid_pos, hue_range.x, hue_range.y, 2)
	result.saturation_shift = _seeded_range(grid_pos, saturation_range.x, saturation_range.y, 3)
	result.value_shift = _seeded_range(grid_pos, value_range.x, value_range.y, 4)
	return result
