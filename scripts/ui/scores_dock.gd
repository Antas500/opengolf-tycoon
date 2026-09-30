extends VBoxContainer
class_name ScoresDock
## The top-left corner of the screen, where round scores read out over the course.
##
## Cards stack downwards in the corner: the owner's round scores (a practice
## round, a match against a pro) and, while a tournament runs, the live
## leaderboard that scores it. Both used to live inside the Player tab's Play
## Course page, squeezed between the shot controls in the bottom bar; the
## controls stay there and the scores moved up here.

## Width of the corner. The board's columns set it; the round card fills it.
const WIDTH := TournamentLeaderboard.PANEL_WIDTH

var round_scores: RoundScoresPanel
var leaderboard: TournamentLeaderboard = null

func _init() -> void:
	name = "ScoresDock"
	add_theme_constant_override("separation", UIConstants.SEPARATION_MD)
	_dock_top_left()
	round_scores = RoundScoresPanel.new()
	round_scores.name = "RoundScoresPanel"
	add_child(round_scores)

## Take the live tournament board: it docks under the round card and shows
## itself for the length of an event.
func attach_leaderboard(board: TournamentLeaderboard) -> void:
	leaderboard = board
	board.embedded = true
	add_child(board)

## Pin the corner: anchored to the top-left of the HUD, growing right and down
## with its content so an empty dock takes no room at all.
func _dock_top_left() -> void:
	var margin: float = UIConstants.HUD_COLUMN_MARGIN
	set_anchor(SIDE_LEFT, 0.0)
	set_anchor(SIDE_TOP, 0.0)
	set_anchor(SIDE_RIGHT, 0.0)
	set_anchor(SIDE_BOTTOM, 0.0)
	offset_left = margin
	offset_top = margin
	offset_right = margin + WIDTH
	offset_bottom = margin
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END
