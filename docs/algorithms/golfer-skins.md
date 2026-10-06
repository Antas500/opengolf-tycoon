# Golfer Skins & the Skin Designer

## Plain English

Every golfer on the course draws from a **skin**: a complete set of pixel art for
the walk, idle and swing animations in all eight facings. Four of them are the
original hand-made tier looks (**Beginner, Casual, Serious, Pro**), and thirteen
more are themed skins drawn procedurally by `tools/generate_golfer_skins.py`
(astronaut, caddie, chef, cowboy, gardener, knight, ninja, pirate, plain, retro,
robot, suit, wizard). Visitors spawn wearing the skin their tier allows, and the
course owner wears whichever skin they picked.

A skin is not baked flat: each of its body parts (top, trousers, headwear, hair,
skin tone, footwear, trim and equipment) is drawn from a five-stop **ramp** of
one colour, and the artist's record of which part and shade every pixel came
from is what makes re-colouring possible. Change the top colour, and every
top pixel is re-emitted from the new colour's ramp with its shading intact -
eyes and highlights, which are the same in every skin, never move.

The player can change those colours on the **Customise Golfer Skins** screen,
which is opened from a tile on the title screen. The screen shows the whole
catalogue down the left, a painting canvas in the middle and a live preview with
the part colour pickers down the right. On the canvas, a left click paints and a
right click picks up the pixel under the cursor (an eyedropper). Whatever is
painted is stored as part and shade indices rather than colours, so a painted
frame keeps following the palette afterwards. **New Skin** forks the selected
skin into one of the player's own, which they can paint, name, wear and delete;
**Revert** puts an edited skin back to the shipped art.

Edits are written to the owner's profile as they are made: a game save stores
them under `player_golfer`, and the same profile is mirrored into
`user://settings.cfg` so a golfer built from the main menu survives a restart,
before any game has been saved.

## Algorithm

### The catalogue

`GolferSkinLibrary` (`scripts/systems/golfer_skin_library.gd`, all static) is the
single source of truth. The shipped catalogue comes from
`res://data/golfer_skins.json`, written by `tools/generate_golfer_skins.py`
together with the 1456 PNGs under `assets/sprites/golfer/skins/<id>/`. Each
record carries:

| Field | Meaning |
| --- | --- |
| `id`, `name`, `description` | Identity, shown in the designer and the pickers |
| `root` | Folder holding `animations/<anim>/<direction>/frame_NNN.png` |
| `legacy` | `true` for the four hand-made tier skins (palette re-coloured, not ramp-drawn) |
| `customizable[]` | The parts this skin offers to the colour pickers |
| `colors{}` | The colours the art was drawn in, one per part |
| `spawn_tiers[]` | Which visitor tiers may wear it |
| `frames` | `4 idle · 4 walk · 6 swing` per direction |

`all_skins()` merges that with the player's recipes from
`PlayerGolferProfile.custom_skins`, rebuilt whenever the profile's
`skin_revision` changes. A recipe whose id matches a shipped skin is an *edit*
of it (only the changed parts and the painted frames are stored); any other id
is a skin the player made. `builtin_skins()` always hands back the untouched art.

### Ramps

`ramp(colour)` returns the five shades every part is painted in:

```
0 base      colour
1 light     mix(colour, white, 0.24)
2 dark      mix(colour, near-black, 0.30)
3 outline   mix(colour, near-black, 0.62)
4 highlight mix(colour, white, 0.42)
```

Every value is quantised to 8 bits, so a re-colour writes back exactly what it
read (matching a sprite pixel against a ramp must not fail on a rounding error).

### Re-colouring

`changed_colours(skin, overrides)` keeps only the picks that differ from the art
skin's palette (`source_skin()`, the shipped skin a custom skin forked from), so
an untouched skin is rebuilt byte-for-byte from disk. For a themed skin,
`recolour()` matches each source pixel to the closest ramp entry of the *art's*
palette (`MATCH_TOLERANCE` = 0.010 squared RGB distance) and re-emits it from
the player's ramp, preserving the shade index. Pixels further away than the
tolerance are left alone - which is how the eyes and highlights keep their fixed
colours. The hand-made tier art is not drawn from ramps at all, so
`_recolour_legacy()` classifies it by position and hue (`classify_legacy_pixel`)
and carries the source pixel's brightness across (`shade_legacy`). That
classifier can only find the top, trousers, headwear, hair and skin tone, so
those are the parts the four tier skins offer in the colour pickers (their
footwear and trim can still be painted by hand in the designer).

### Painted pixels

The designer stores pixels as a single byte per pixel:

```
0            transparent
1 + part*5 + shade   a shade of a part (see PART_ORDER)
```

`encode_image()` turns a frame back into those bytes (`match_pixel` against the
skin's own palette, since the frame on the canvas is already the player's
colours) and `image_from_overlay()` draws them back out of any palette - so a
painted frame follows later colour changes. Tier art is encoded with
`_encode_legacy_pixel()`: the part comes from the legacy classifier and the
shade is the ramp entry closest to the pixel's brightness, so painting over a
tier skin re-draws that frame in the flat ramp style.

An edit stores a whole frame the first time one of its pixels is painted, so a
partially painted frame keeps the rest of the art.

### Frames and caching

`frames_for(skin, overrides, fresh)` is the SpriteFrames factory shared by every
golfer. Animations are named `<anim>_<direction>` (`walk_north-east`), speed and
looping come from `ANIMATIONS` (idle 4 fps loop, walk 8 fps loop, swing 10 fps
one-shot), and a facing with no art of its own borrows one
(`DIAGONAL_FALLBACK`). Built frames are cached on
`"<id>|<part=hex,…>|<revision>"`; `invalidate(skin_id)` clears a skin's entries
after an edit. Eight visitors wearing one skin therefore cost one build.

### Spawning

`skins_for_tier(tier)` puts the tier's own art first and then the themed skins
that tier may wear; `random_skin_for_tier(tier)` picks the tier look about 55%
of the time and a themed skin otherwise. `golfer.gd` deals a skin in
`assign_visitor_skin()` for visitor rounds; for the owner round,
`apply_player_appearance(profile)` reads the profile's `skin_id` and colours.
A legacy tier skin keeps the golfer's own `shirt_color`/`pants_color`/… so the
existing tier colour variation still applies.

### The designer

`scripts/ui/golfer_skin_designer.gd` (screen) and
`scripts/ui/skin_pixel_editor.gd` (canvas) are the Customise Golfer Skins
screen. It is one of the popup screens `main.gd` adds to the HUD and hides while
gameplay UI is hidden, opened from the title screen's seventh action
(`customise_skins_requested`). The canvas paints part+shade indices
(`pixel_index`/`decode_pixel`), draws a line between mouse samples so fast drags
still paint, and offers an eraser, zoom and an eyedropper. The screen writes
every change straight to `PlayerGolferProfile.custom_skins` and calls
`SaveManager.save_golfer_profile()` when it closes, so a crash never costs more
than the stroke in progress.

## Tuning Levers

| Lever | Location | Value | Effect |
| --- | --- | --- | --- |
| Themed skins | `tools/generate_golfer_skins.py` (`SKINS`, `_draw_pack`) | 13 | How many extra skins ship; regenerate with `python3 tools/generate_golfer_skins.py` |
| Ramp stops | `GolferSkinLibrary.ramp()` | 0.24 / 0.30 / 0.62 / 0.42 | How much light, dark and outline the shading has |
| Match tolerance | `GolferSkinLibrary.MATCH_TOLERANCE` | 0.010 | How close a pixel must be to a ramp entry to be re-coloured |
| Legacy tolerance | `GolferSkinLibrary.LEGACY_TOLERANCE` | 0.055 | The same for the hand-made tier art |
| Tier-art share | `GolferSkinLibrary.random_skin_for_tier()` | 0.55 | How often a visitor wears their tier's own look instead of a themed skin |
| Own-skin limit | `PlayerGolferProfile.MAX_CUSTOM_SKINS` | 24 | How many skins of their own a player may keep |
| Name length | `PlayerGolferProfile.MAX_SKIN_NAME` | 24 | Longest skin name the designer accepts |
| Designer breakpoint | `GolferSkinDesigner.BREAKPOINT` | 980 px | Below this the three columns stack into one scrolling column |
