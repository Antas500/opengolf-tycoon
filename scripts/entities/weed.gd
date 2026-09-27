extends Node2D
class_name Weed
## Weed - A clump of unsightly weeds sprouting on the course.
##
## Purely visual: it draws a small cluster of blades at its grid tile's centre
## so groundskeepers have something to walk up to and pull. The WeedManager owns
## the lifecycle; growing taller (set_growth) makes a clump more noticeable.

## Grid tile this clump sits on.
var grid_position: Vector2i = Vector2i.ZERO
## 0.0 (just sprouted) to 1.0 (fully grown).
var growth: float = 0.4

var terrain_grid: TerrainGrid = null
var _blades: Array[Polygon2D] = []
var _seed: int = 0

func _ready() -> void:
	add_to_group("weeds")
	z_index = 3  # Above the terrain, below golfers/staff
	_seed = randi()
	_build_visual()

func set_terrain_grid(grid: TerrainGrid) -> void:
	terrain_grid = grid

func set_position_in_grid(pos: Vector2i) -> void:
	grid_position = pos
	if terrain_grid:
		global_position = terrain_grid.grid_to_screen_center(pos)

func set_growth(value: float) -> void:
	growth = clampf(value, 0.0, 1.0)
	_apply_growth()

func _build_visual() -> void:
	_blades.clear()
	# Two to four blades, deterministic per clump via _seed.
	var count := 2 + (_seed % 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	for i in count:
		var blade := Polygon2D.new()
		var lean := rng.randf_range(-4.0, 4.0)
		var height := rng.randf_range(7.0, 12.0)
		var base_x := rng.randf_range(-4.0, 4.0)
		blade.polygon = PackedVector2Array([
			Vector2(base_x - 1.5, 0.0),
			Vector2(base_x + 1.5, 0.0),
			Vector2(base_x + lean, -height),
			Vector2(base_x + lean - 1.0, -height + 1.5),
		])
		blade.color = Color(0.32, 0.42, 0.16) if i % 2 == 0 else Color(0.42, 0.5, 0.2)
		_blades.append(blade)
		add_child(blade)
	_apply_growth()

func _apply_growth() -> void:
	if _blades.is_empty():
		return
	var s := 0.55 + growth * 0.65
	for blade in _blades:
		blade.scale = Vector2(s, s)
	# Fresh sprouts are paler; established clumps darken.
	var tint := lerpf(0.25, 0.0, growth)
	modulate = Color(1.0 + tint * 0.2, 1.0, 1.0 - tint * 0.1, 0.85 + growth * 0.15)

func get_weed_info() -> Dictionary:
	return {"growth": growth}
