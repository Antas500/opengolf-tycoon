extends RefCounted
class_name MenuStyle
## The palette and card styling shared by the out-of-game menu screens (the
## title screen and the Start New Game setup screen).
##
## Both screens sit on the same drawn MenuBackdrop and use the same dark,
## translucent cards with an accent-coloured border, so the colours and the
## StyleBoxFlat recipe live here once instead of being copied between them.

const TITLE_COLOR := Color("e7f3d6")

const CARD_RADIUS := 12
const CARD_BG := Color(0.043, 0.098, 0.078, 0.88)
const CARD_BG_HOVER := Color(0.086, 0.180, 0.141, 0.95)
const CARD_BG_PRESSED := Color(0.027, 0.063, 0.051, 0.97)
const CARD_BG_DISABLED := Color(0.043, 0.098, 0.078, 0.55)
const RAIL_BG := Color(0.031, 0.071, 0.059, 0.72)
## A large form panel: like the rail, but dense enough that the backdrop's
## flag and trees read as behind it rather than through it.
const SHEET_BG := Color(0.031, 0.071, 0.059, 0.88)
## Recessed surfaces inside a card: text fields, the course plan's frame.
const INSET_BG := Color(0.020, 0.051, 0.039, 0.92)

## Gold is the palette's "special" colour: the headline action on each screen.
const ACCENT_PRIMARY := UIConstants.COLOR_GOLD
## The green, everyday path into the game.
const ACCENT_SECONDARY := Color("7fb08a")
const ACCENT_UTILITY := Color("6d8a76")
const ACCENT_QUIT := UIConstants.COLOR_DANGER_MUTED
## Golfer skin designer: a warmer green, distinct from the utility tiles.
const ACCENT_SKINS := Color("9bbf7a")
## Dark ink for text sitting on a gold fill.
const INK := Color("10241f")

## StyleBoxFlat with uniform side margins, its own top margin and the room a
## caption needs below the label.
static func flat(bg: Color, border: Color, border_width: int, radius: int,
		pad: int, top: int, bottom: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = float(pad)
	style.content_margin_right = float(pad)
	style.content_margin_top = float(top)
	style.content_margin_bottom = float(bottom)
	return style

static func with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)

## Paint a card button: dark translucent panel, accent border, a hover that
## lights the border up, and content margins that keep the button's own label
## clear of a caption strip along the bottom edge.
static func paint_card(button: Button, accent: Color, caption_block: float, pad: int,
		text_color: Color, hover_color: Color) -> void:
	var bottom := pad + int(caption_block)
	var styles := {
		"normal": flat(CARD_BG, with_alpha(accent, 0.42), 1, CARD_RADIUS, pad, pad, bottom),
		"hover": flat(CARD_BG_HOVER, accent, 2, CARD_RADIUS, pad - 1, pad - 1, bottom - 1),
		"pressed": flat(CARD_BG_PRESSED, accent, 2, CARD_RADIUS, pad - 1, pad - 1, bottom - 1),
		"focus": flat(Color(0, 0, 0, 0), with_alpha(accent, 0.75), 2, CARD_RADIUS, pad, pad, bottom),
		"disabled": flat(CARD_BG_DISABLED, with_alpha(accent, 0.18), 1, CARD_RADIUS, pad, pad, bottom),
	}
	var font_colors := {
		"normal": text_color,
		"hover": hover_color,
		"pressed": text_color,
		"focus": hover_color,
		"disabled": UIConstants.COLOR_TEXT_MUTED,
	}
	for state in styles:
		button.add_theme_stylebox_override(state, styles[state])
		# "normal" is the Button theme's plain `font_color`.
		button.add_theme_color_override("font_color" if state == "normal" else "font_%s_color" % state,
			font_colors[state])

## Paint a selectable (toggle) card. Unselected it is an ordinary card; the
## selected one fills with a wash of its accent and carries a full-strength
## border, so the choice reads at a glance even without colour (the border
## weight changes too).
static func paint_choice(button: Button, accent: Color, radius: int = CARD_RADIUS) -> void:
	var selected_bg := CARD_BG.lerp(Color(accent.r, accent.g, accent.b, 0.95), 0.15)
	var selected_hover := CARD_BG_HOVER.lerp(Color(accent.r, accent.g, accent.b, 0.95), 0.20)
	var styles := {
		"normal": flat(CARD_BG, with_alpha(accent, 0.30), 1, radius, 0, 0, 0),
		"hover": flat(CARD_BG_HOVER, with_alpha(accent, 0.85), 1, radius, 0, 0, 0),
		"pressed": flat(selected_bg, accent, 2, radius, 0, 0, 0),
		"hover_pressed": flat(selected_hover, accent, 2, radius, 0, 0, 0),
		"focus": flat(Color(0, 0, 0, 0), with_alpha(UIConstants.COLOR_TEXT, 0.55), 2, radius + 2, 0, 0, 0),
		"disabled": flat(CARD_BG_DISABLED, with_alpha(accent, 0.15), 1, radius, 0, 0, 0),
	}
	# The focus ring sits just outside the card so it never hides the border
	# that marks the selection.
	(styles["focus"] as StyleBoxFlat).set_expand_margin_all(3.0)
	for state in styles:
		button.add_theme_stylebox_override(state, styles[state])

## Paint the screen's one solid call to action: a gold fill with dark ink.
static func paint_primary(button: Button, radius: int = CARD_RADIUS) -> void:
	var gold := ACCENT_PRIMARY
	var styles := {
		"normal": flat(gold, gold.lightened(0.25), 1, radius, 0, 0, 0),
		"hover": flat(gold.lightened(0.12), Color(1, 1, 1, 0.85), 2, radius, 0, 0, 0),
		"pressed": flat(gold.darkened(0.12), gold.darkened(0.3), 2, radius, 0, 0, 0),
		"focus": flat(Color(0, 0, 0, 0), with_alpha(UIConstants.COLOR_TEXT, 0.8), 2, radius + 3, 0, 0, 0),
		"disabled": flat(with_alpha(gold, 0.35), with_alpha(gold, 0.2), 1, radius, 0, 0, 0),
	}
	(styles["focus"] as StyleBoxFlat).set_expand_margin_all(4.0)
	for state in styles:
		button.add_theme_stylebox_override(state, styles[state])

## A rounded panel (cards, rails, insets) with its own padding.
static func panel(bg: Color, border: Color, radius: int, pad_x: int, pad_y: int,
		border_width: int = 1) -> StyleBoxFlat:
	return flat(bg, border, border_width, radius, pad_x, pad_y, pad_y)

## Height of `lines` lines of text at `font_size` in the game's font, including
## Label's line spacing between them. Lets builders size cards up front
## instead of waiting a frame for wrapped labels to measure themselves.
static func text_block(font: Font, font_size: int, lines: int, line_spacing: float = 3.0) -> float:
	if font == null or font_size <= 0 or lines <= 0:
		return 0.0
	return font.get_height(font_size) * float(lines) + line_spacing * float(lines - 1)

## How many lines `text` takes when word-wrapped at `width` - the same greedy
## break a Label with AUTOWRAP_WORD_SMART makes. Screens use it to reserve a
## fixed height for wrapped text, so layouts are measurable before the first
## layout pass and never cut a description short.
static func wrapped_lines(text: String, font: Font, font_size: int, width: float) -> int:
	if font == null or text.is_empty():
		return 1
	var limit := maxf(width - 1.0, 1.0)
	var space := _string_width(" ", font, font_size)
	var lines := 1
	var line := ""
	for word in text.split(" ", false):
		# Each candidate line is measured whole (a shaped line is a few pixels
		# wider than its words measured one by one), and with the space that
		# follows it: the text server only breaks after the space.
		var candidate := word if line.is_empty() else line + " " + word
		if not line.is_empty() and _string_width(candidate, font, font_size) + space > limit:
			lines += 1
			line = word
		else:
			line = candidate
		# A word wider than the line is broken across lines by the label.
		var overflow := _string_width(line, font, font_size)
		if overflow > limit and line == word:
			lines += ceili(overflow / limit) - 1
	return lines

static func _string_width(text: String, font: Font, font_size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
