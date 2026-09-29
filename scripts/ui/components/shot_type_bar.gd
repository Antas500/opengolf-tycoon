extends HBoxContainer
class_name ShotTypeBar
## The owner's five shot choices as separate buttons along the top of the Play
## Course tab — one button per shot type instead of a drop-down selector, so the
## whole set stays visible and the shot that is lined up reads at a glance.
##
## The buttons are mutually exclusive (`ButtonGroup`), and the lit button is
## exactly the shot `Golfer.play_shot()` will hit: pressing one emits
## `shape_selected` with the shape index (0 straight, 1 fade, 2 draw,
## 3 high backspin, 4 low punch), which the round manager writes onto the golfer.
##
## Availability is `Golfer.shape_allowed()`, the execution guard's own rule:
## straight and low punch work from any off-green lie, fade, draw and high
## backspin need a tee or fairway. A lie that no longer allows the chosen shape
## falls back to straight here, exactly as `Golfer.preview_shot()` and
## `play_shot()` do, so the lit button never lies about the shot being hit.
##
## The row greys out (`set_ready(false)`) rather than disappearing while the
## owner waits for their turn, matching how the rest of the aiming HUD behaves.

## Emitted when the owner presses a shot type. The index matches `Golfer.player_shape`.
signal shape_selected(shape: int)

## One entry per shot type, in `Golfer.player_shape` order. `name` is the button
## label; `title`/`description` feed the tooltip.
const SHOTS := [
	{
		"name": "Straight",
		"title": "Straight shot",
		"description": "No bend — the ball flies at the aim point. Available from every lie.",
	},
	{
		"name": "Fade",
		"title": "Fade shot (L to R)",
		"description": "Bends 8° left to right. Tee and fairway only.",
	},
	{
		"name": "Draw",
		"title": "Draw shot (R to L)",
		"description": "Bends 8° right to left. Tee and fairway only.",
	},
	{
		"name": "Backspin",
		"title": "High backspin shot",
		"description": "Steep landing that reverses the roll on green and fairway turf. Tee and fairway only.",
	},
	{
		"name": "Punch",
		"title": "Low punch shot",
		"description": "70% range, a flat trajectory, less wind drift and extra roll. Available from every lie.",
	},
]

## Height of the row. Matches a toolbar tool button so the top of the tab keeps
## the same visual weight as the rest of the bottom bar.
const BUTTON_HEIGHT := 30

var _buttons: Array[Button] = []
var _group := ButtonGroup.new()
## The lit shape (0-4), always the shot the golfer will hit.
var _shape := 0
## Shape the buttons were last painted for, so style overrides only change when
## the selection moves instead of once a frame.
var _painted_shape := -1
## True while the owner is lining up a shot; the whole row is dead otherwise.
var _ready_for_shot := false
## Lie the row is showing availability for (-1 until the first sample).
var _terrain := -1
## Greyed face for a dead row / a shot this lie forbids, and the ringed version
## that keeps the lit shot readable while the row is dead. Shared by every
## button; built on demand so a selection can be set before `_ready()`.
var _disabled_style: StyleBoxFlat
var _lit_disabled_style: StyleBoxFlat

func _ready() -> void:
	add_theme_constant_override("separation", UIConstants.SEPARATION_SM)
	_group.allow_unpress = false
	_ensure_styles()
	for index in SHOTS.size():
		var button := _make_button(index)
		add_child(button)
		_buttons.append(button)
	_painted_shape = -1  # First sync always paints the disabled/lit styles.
	_sync_buttons()

func _make_button(index: int) -> Button:
	var shot: Dictionary = SHOTS[index]
	var button := Button.new()
	button.name = "Shot%s" % shot["name"]
	button.text = shot["name"]
	# Plain tooltip as a fallback for contexts without the TooltipManager autoload.
	button.tooltip_text = "%s — %s" % [shot["title"], shot["description"]]
	button.toggle_mode = true
	button.button_group = _group
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = BUTTON_HEIGHT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.set_meta("shot_type", index)
	button.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_style_button(button)
	button.add_theme_stylebox_override("disabled", _disabled_style)
	button.pressed.connect(_on_button_pressed.bind(index))
	button.mouse_entered.connect(_on_button_hover.bind(index))
	button.mouse_exited.connect(_on_button_exit)
	return button

## The two greys of a dead row: a plain face for every unlit shot, and a muted
## gold ring on the loaded one so the selection survives the wait for a turn.
func _ensure_styles() -> void:
	if _disabled_style != null:
		return
	_disabled_style = _flat_style(UIConstants.COLOR_BG_DARK, UIConstants.COLOR_BORDER)
	_lit_disabled_style = _flat_style(UIConstants.COLOR_BG_DARK, UIConstants.COLOR_GOLD_DIM, 2)

## Flat styles matching `ToolButton`: dark face, gold-ringed face when held down.
func _style_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _flat_style(UIConstants.COLOR_BG_BUTTON, UIConstants.COLOR_BORDER))
	button.add_theme_stylebox_override("hover", _flat_style(UIConstants.COLOR_PRIMARY_HOVER, UIConstants.COLOR_PRIMARY))
	button.add_theme_stylebox_override("pressed", _flat_style(UIConstants.COLOR_PRIMARY, UIConstants.COLOR_GOLD, 2))
	button.add_theme_stylebox_override("hover_pressed", _flat_style(UIConstants.COLOR_PRIMARY, UIConstants.COLOR_GOLD, 2))
	button.add_theme_stylebox_override("focus", _flat_style(Color.TRANSPARENT, UIConstants.COLOR_GOLD))
	button.add_theme_color_override("font_color", UIConstants.COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", UIConstants.COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", UIConstants.COLOR_TEXT)
	button.add_theme_color_override("font_hover_pressed_color", UIConstants.COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", UIConstants.COLOR_TEXT_MUTED)

static func _flat_style(bg_color: Color, border_color: Color, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style

func _on_button_pressed(index: int) -> void:
	# Disabled buttons cannot be pressed, but a programmatic press must not put
	# the row on a shot the lie forbids: snap back to the lit shape instead.
	if not _ready_for_shot or not Golfer.shape_allowed(index, _terrain):
		_sync_buttons()
		return
	_shape = index
	# Enforce the one-lit-button rule here as well as in the ButtonGroup, so a
	# programmatic press can never leave two shots looking selected.
	_sync_buttons()
	shape_selected.emit(index)

func _on_button_hover(index: int) -> void:
	var manager := get_node_or_null("/root/TooltipManager")
	if manager == null:
		return
	var shot: Dictionary = SHOTS[index]
	manager.show_tooltip({
		"title": shot["title"],
		"description": shot["description"],
	}, _buttons[index])

func _on_button_exit() -> void:
	var manager := get_node_or_null("/root/TooltipManager")
	if manager:
		manager.hide_tooltip()

## Keep every button's disabled/pressed look on the current shot and lie.
func _sync_buttons() -> void:
	_ensure_styles()
	var moved := _painted_shape != _shape
	_painted_shape = _shape
	for index in _buttons.size():
		var button := _buttons[index]
		button.set_pressed_no_signal(index == _shape)
		button.disabled = not _ready_for_shot or not Golfer.shape_allowed(index, _terrain)
		if moved:
			button.add_theme_stylebox_override("disabled",
				_lit_disabled_style if index == _shape else _disabled_style)

# ============================================================================
# PUBLIC API
# ============================================================================

## One button per shot type, in `Golfer.player_shape` order.
func shot_count() -> int:
	return _buttons.size()

## The button for `shape`, clamped into range so callers can tab by index.
func shot_button(shape: int) -> Button:
	return _buttons[clampi(shape, 0, maxi(0, _buttons.size() - 1))]

## The shot the row is lit on (0 straight … 4 low punch).
func selected_shape() -> int:
	return _shape

## Light `shape` without emitting `shape_selected` — the round manager mirrors the
## golfer's shot here, and the execution guard's fallback to straight lands on the
## button without re-triggering the owner's own press.
func select_shape(shape: int) -> void:
	if shape < 0 or shape >= _buttons.size():
		shape = 0
	_shape = shape
	_sync_buttons()

## The whole row is live only while the owner is lining up a shot; otherwise it
## greys out like the rest of the aiming HUD.
func set_ready(ready: bool) -> void:
	if _ready_for_shot == ready:
		return
	_ready_for_shot = ready
	_sync_buttons()

func is_ready_for_shot() -> bool:
	return _ready_for_shot

## Refresh which shots the current lie allows. Returns `true` when the lit shot
## had to fall back to straight because the lie no longer allows it (the ball
## rolled out of the fairway), so the caller can mirror the change on the golfer.
func update_for_lie(terrain: int) -> bool:
	_terrain = terrain
	var fell_back := _shape != 0 and not Golfer.shape_allowed(_shape, terrain)
	if fell_back:
		_shape = 0
	_sync_buttons()
	return fell_back

## Whether `shape` can be played from `terrain` — the row's own rule, shown on
## the buttons as the enabled/disabled state.
static func shape_available(shape: int, terrain: int) -> bool:
	return Golfer.shape_allowed(shape, terrain)
