extends Node
## Screen - Responsive layout adapter for the whole game (autoload).
##
## The game is designed at a 1600x1000 reference size (see project.godot) but
## renders at the window's native pixel size (stretch mode is "disabled", so
## one layout pixel == one window pixel on every platform, including the web
## build). This autoload turns the raw window size into layout decisions:
##
##  * world_scale - the extra camera zoom applied on top of the player's
##    chosen zoom level. On large windows it makes the visible course area
##    track the reference view (a 1920x1080 window sees the same tiles per
##    inch as the 1600x1000 design). On narrow windows (phones, small
##    browser windows) it is floored at 1.0 so tiles never shrink below
##    design size and stay big enough to tap.
##  * compact / portrait flags - narrow or tall windows get a compact HUD
##    (narrower status column, smaller minimap) so everything fits.
##  * available_panel_size() - the rect popup panels may occupy, keeping
##    clear of the bottom control bar.
##
## The `changed` signal fires whenever the window size (or its derived
## values) change - on live desktop resizes and on mobile rotation.

signal changed(window_size: Vector2, world_scale: float)

## Reference design resolution.
const BASE_SIZE := Vector2(1600.0, 1000.0)

## Windows narrower than this (or shorter than COMPACT_HEIGHT) use the
## compact HUD: narrower status column, smaller minimap.
const COMPACT_WIDTH := 900.0
const COMPACT_HEIGHT := 640.0

## Physical window widths at or above this scale the world with the window;
## below it the world stays at 1:1 pixel scale so tiles remain tappable.
const WORLD_SCALE_FLOOR_WIDTH := 900.0

var window_size: Vector2 = BASE_SIZE
var world_scale: float = 1.0

func _ready() -> void:
	window_size = _read_window_size()
	world_scale = compute_world_scale(window_size)
	# React to window resizes/rotation. Polling every frame is cheap enough
	# and also catches web canvas resizes that skip the root signal.
	get_tree().root.size_changed.connect(_on_root_size_changed)

func _process(_delta: float) -> void:
	var new_size := _read_window_size()
	if new_size != window_size:
		apply_size(new_size)

func _read_window_size() -> Vector2:
	return get_viewport().get_visible_rect().size

func _on_root_size_changed() -> void:
	_process(0.0)

## Recompute all derived values for a window size and emit `changed` when
## something moved. Safe to call with the current size (no-op).
func apply_size(new_size: Vector2) -> void:
	var new_world_scale := compute_world_scale(new_size)
	if new_size == window_size and new_world_scale == world_scale:
		return
	window_size = new_size
	world_scale = new_world_scale
	changed.emit(window_size, world_scale)

## Reference view scale: how big the window is relative to the 1600x1000
## design, limited by the smaller dimension.
static func compute_scale(window: Vector2) -> float:
	return minf(window.x / BASE_SIZE.x, window.y / BASE_SIZE.y)

## Camera scale for a window size (see header). Pure and unit-testable.
static func compute_world_scale(window: Vector2) -> float:
	var s := compute_scale(window)
	var floor_ := minf(1.0, WORLD_SCALE_FLOOR_WIDTH / maxf(window.x, 1.0))
	return maxf(s, floor_)

func is_compact() -> bool:
	return window_size.x < COMPACT_WIDTH or window_size.y < COMPACT_HEIGHT

func is_portrait() -> bool:
	return window_size.y > window_size.x

func is_landscape() -> bool:
	return window_size.x >= window_size.y

## Bottom control bar height (view/speed controls + tabbed toolbar).
func bottom_bar_height() -> float:
	return float(UIConstants.BOTTOM_BAR_HEIGHT)

## Vertical space below which popup panels must not sit (the bottom bar
## plus a little breathing room).
func hud_bottom_clearance() -> float:
	return bottom_bar_height() + 8.0

## The largest size a centered popup panel may take while staying fully on
## screen and clear of the bottom bar.
func available_panel_size() -> Vector2:
	var margin := Vector2(16.0, 12.0)
	var size := window_size - Vector2(margin.x * 2.0, margin.y * 2.0 + hud_bottom_clearance())
	return size.max(Vector2(120.0, 120.0))

## Full rect available to popup panels (margins + bottom-bar clearance).
func available_panel_rect() -> Rect2:
	var margin := Vector2(16.0, 12.0)
	return Rect2(
		margin.x, margin.y,
		window_size.x - margin.x * 2.0,
		window_size.y - margin.y * 2.0 - hud_bottom_clearance()
	)
