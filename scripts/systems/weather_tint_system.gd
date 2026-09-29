extends Node2D
class_name WeatherTintSystem
## WeatherTintSystem - Weather-driven ambient tinting using CanvasModulate.
##
## Replaces the old DayNightSystem: with the day/night cycle removed, the scene
## stays at neutral daytime lighting and the canvas is only tinted by weather —
## gloomier (cooler, darker) under clouds and rain, clear in sunshine.
## Weather tints are applied smoothly in _process to avoid jarring jumps.

var _canvas_modulate: CanvasModulate = null
var _weather_tint: Color = Color.WHITE
var _target_weather_tint: Color = Color.WHITE  # Lerp target for smooth transitions
var _is_web: bool = false
var _web_update_timer: float = 0.0
const WEB_UPDATE_INTERVAL: float = 0.1  # Update tint at 10 FPS on web (smooth enough for gradual changes)

func _ready() -> void:
	_is_web = OS.get_name() == "Web"
	_canvas_modulate = CanvasModulate.new()
	_canvas_modulate.name = "WeatherModulate"
	if GameManager.weather_system:
		_weather_tint = GameManager.weather_system.get_sky_tint()
		_target_weather_tint = _weather_tint
	_canvas_modulate.color = _compute_tint()
	add_child(_canvas_modulate)
	EventBus.weather_changed.connect(_on_weather_changed)

func _exit_tree() -> void:
	if EventBus.weather_changed.is_connected(_on_weather_changed):
		EventBus.weather_changed.disconnect(_on_weather_changed)

func _on_weather_changed(_weather_type: int, _intensity: float) -> void:
	# Set target weather tint — actual tint will smoothly lerp toward it in _process
	if GameManager.weather_system:
		_target_weather_tint = GameManager.weather_system.get_sky_tint()
	else:
		_target_weather_tint = Color.WHITE

func _process(delta: float) -> void:
	# Smoothly interpolate weather tint toward target (prevents jarring color jumps)
	_weather_tint = _weather_tint.lerp(_target_weather_tint, clampf(delta * 2.0, 0.0, 1.0))

	# On web, throttle CanvasModulate updates since they affect all rendered pixels
	if _is_web:
		_web_update_timer += delta
		if _web_update_timer < WEB_UPDATE_INTERVAL:
			return
		_web_update_timer = 0.0

	_canvas_modulate.color = _compute_tint()

## Neutral daytime lighting (white) dimmed/cooled by the current weather.
## Weather tint uses alpha as the strength of the dimming effect.
func _compute_tint() -> Color:
	var daylight := Color.WHITE
	var weather_strength := _weather_tint.a
	var weather_color := Color(_weather_tint.r, _weather_tint.g, _weather_tint.b, 1.0)
	return daylight.lerp(daylight * weather_color, weather_strength)
