extends Node
## GolferSkins - the Golfer Skins the game draws golfers with (autoload).
##
## Owns one GolferSkinLibrary and answers the questions the rest of the game
## asks about skins: which skin a golfer wears, and what sprite frames that
## skin is drawn with. The library is cheap to hold (it reads the skins'
## manifests, not their grids) and shares the frames it builds, so asking for
## the frames of a skin a hundred visitors wear costs one re-color.

signal skins_changed

var library: GolferSkinLibrary = GolferSkinLibrary.new()


## Read the skins' folders again, e.g. after the player edited them outside
## the game.
func reload() -> void:
	library.reload()
	skins_changed.emit()


## The skin a golfer wears: one named on the golfer itself, the one the player
## chose for their own golfer, or the skin for the golfer's tier.
func skin_for_golfer(golfer: Golfer) -> GolferSkin:
	if golfer == null:
		return null
	if not golfer.skin_id.is_empty():
		var chosen := library.get_skin(golfer.skin_id)
		if chosen != null:
			return chosen
	if golfer.player_profile != null:
		return player_skin()
	return library.skin_for_tier(golfer.golfer_tier)


## The skin the player's own golfer wears.
func player_skin() -> GolferSkin:
	return library.player_skin(GameManager.player_skin_id)


## Remember which skin the player's own golfer wears: it belongs to the player,
## not to a save, so it is written to the user settings straight away.
func set_player_skin(skin: GolferSkin) -> void:
	var wanted := skin.id if skin != null else ""
	if GameManager.player_skin_id == wanted:
		return
	GameManager.player_skin_id = wanted
	SaveManager.set_user_preference("gameplay", "player_skin", wanted)


## The animation frames a golfer is drawn with: the colours the golfer's skin
## carries (see GolferSkin), not the owner's profile - the player edits a skin's
## Re-color Groups to change how the golfers wearing it look. Null when the
## golfer's tier has no skin to wear.
func frames_for_golfer(golfer: Golfer) -> SpriteFrames:
	if golfer == null:
		return null
	var skin := skin_for_golfer(golfer)
	if skin == null:
		return null
	return library.recolored_frames(skin)


## The untouched artwork of a golfer's skin - what the re-color layers are
## painted over.
func raw_frames_for_golfer(golfer: Golfer) -> SpriteFrames:
	if golfer == null:
		return null
	return library.raw_frames(skin_for_golfer(golfer))



## Forget the frames built for a skin so the next golfer drawn picks up new
## layers or colours.
func invalidate(skin_id: String = "") -> void:
	library.invalidate(skin_id)
