# Golfer Skins & the Skin Designer

## Plain English

Every golfer on the course draws from a **skin**: a complete set of pixel art for
the walk, idle and swing animations in all eight facings. Two of them are
hand-made tier looks (**Weekend Beginner** and **Club Casual**) and thirteen more
are themed skins drawn procedurally by `tools/generate_golfer_skins.py`
(astronaut, caddie, chef, cowboy, knight, lumberjack, ninja, pirate, plain,
retro, robot, suit, wizard). Visitors spawn wearing the skin their tier allows:
the hand-made art leads the Beginner and Casual tiers, while the Serious and Pro
tiers have no art of their own and are dressed from the themed skins. The course
owner wears whichever skin they picked.

A skin is not baked flat: every sprite ships with a **part layer** beside it, a
byte per pixel recording which body part the artist drew that pixel as (top,
trousers, headwear, hair, skin tone, footwear, trim, equipment) and in which of
the colour's five shades. That layer is what decides which pixels change colour.
Change the top colour and every pixel the layer tags as the top is re-emitted
from the new colour with its shading intact - a very dark shirt is never
mistaken for hair, and the eyes and highlights, which are the same in every
skin, never move.

The layer is the skin's own list of parts, and the player can edit it on the
**Customise Golfer Skins** screen, which is opened from a tile on the title
screen. The screen shows the whole catalogue down the left, a painting canvas in
the middle and a live preview with the part colour pickers down the right.

* **Add part** puts a part into the skin's layer - offered by the colour pickers
  from then on - and **Remove part** takes one out, so its pixels keep the
  colours they have.
* Selecting a part in the layer list arms the pixel brush with it; painting a
  part the layer does not hold yet adds it.
* On the canvas, a left click paints and a right click picks up the pixel under
  the cursor (an eyedropper). Whatever is painted is stored as part and shade
  indices rather than colours, so a painted frame keeps following the palette
  afterwards.
* **New Skin** forks the selected skin into one of the player's own, which they
  can paint, re-colour, name, wear and delete; **Revert** puts an edited skin
  back to the shipped art.

Edits are written to the owner's profile as they are made: a game save stores
them under `player_golfer`, and the same profile is mirrored into
`user://settings.cfg` so a golfer built from the main menu survives a restart,
before any game has been saved.

## Algorithm

### The catalogue

`GolferSkinLibrary` (`scripts/systems/golfer_skin_library.gd`, all static) is the
single source of truth. The shipped catalogue comes from
`res://data/golfer_skins.json`, written by `tools/generate_golfer_skins.py`
together with the 1456 PNGs under `assets/sprites/golfer/skins/<id>/` and a part
layer beside each one. Each record carries:

| Field | Meaning |
| --- | --- |
| `id`, `name`, `description` | Identity, shown in the designer and the pickers |
| `root` | Folder holding `animations/<anim>/<direction>/frame_NNN.png` (+ `.layer.bin`) |
| `legacy` | `true` for the hand-made tier art (shading carried across, not re-emitted from a ramp) |
| `customizable[]` | The parts this skin's layer holds - the parts the colour pickers offer |
| `colors{}` | The colours the art was drawn in, one per part |
| `spawn_tiers[]` | Which visitor tiers may wear it |
| `frames` | `4 idle · 4 walk · 6 swing` per direction |

`customizable[]` is written from what the generator actually drew, so it matches
the layer exactly: an outfit that never draws its "trousers" (a wizard's robe
covers the legs, a caddie's towel is drawn as trim) does not offer that part
until the player adds it.

`all_skins()` merges that with the player's recipes from
`PlayerGolferProfile.custom_skins`, rebuilt whenever the profile's
`skin_revision` changes. A recipe whose id matches a shipped skin is an *edit*
of it (the layer's parts, the changed colours and the painted frames are what is
stored); any other id is a skin the player made. A recipe written before layers
were editable carries no `parts` list at all and keeps the art's own.
`builtin_skins()` always hands back the untouched art.

### Ramps

`ramp(colour)` returns the five shades a part is painted in:

```
0 base      colour
1 light     mix(colour, white, 0.24)
2 dark      mix(colour, near-black, 0.30)
3 outline   mix(colour, near-black, 0.62)
4 highlight mix(colour, white, 0.42)
```

Every value is quantised to 8 bits, so a re-colour writes back exactly what it
read (matching a sprite pixel against a ramp must not fail on a rounding error).

### Part layers

`frame_layer(skin, direction, anim, frame)` reads
`<frame>.png` → `<frame>.layer.bin`: a deflated 48x48 byte array, one byte per
pixel. A skin of the player's own borrows the layers of the shipped skin it was
forked from (`layer_root()` resolves the fork back to that skin), exactly as it
borrows those pixels; the byte is the same value the designer stores for a
painted pixel:

```
0                    no part: empty canvas, the drop shadow, the shadow under the
                     hat brim - anything that is not a body part. Never re-coloured.
1 + part*5 + shade   a shade of a part (see PART_ORDER)
```

`tools/generate_golfer_skins.py` writes the layers:

* The **drawn (themed) skins** know their parts by construction: `Painter.to_layer()`
  records `(part, shade)` for every pixel it puts down, so the layer is exact -
  including the parts drawn in the fixed colours (eyes, highlights).
* The **hand-made tier art** was not drawn by the tool, so its layers are
  authored there instead (`CASUAL_ART`, `BEGINNER_ART`), as a key: the tones the
  artist drew each part in, plus the band of the figure (head / body / waist /
  legs / feet) a pixel has to sit in to belong to one part rather than another.
  That is how one dark brown can be the hair's outline above the neck, a crease
  in the top on the shirt, the belt at the waist, the trouser seam below it and
  the sole at the feet, and how a pupil (drawn in the hair's own tone) is found
  by having skin on all sides of it. Anything the key does not list takes the
  part of the nearest tone it does, so the layer always covers the whole figure.
  The shade is the ramp stop closest to the tone the pixel was drawn in.

`layer_report(skin)` counts the pixels of each part over the skin's whole art
(once per art, cached) and `layer_parts()` lists them in `PART_ORDER`:
`PlayerGolferProfile.parts_for_skin()` and the designer's colour pickers come
straight off it.

### Re-colouring

`changed_colours(skin, overrides)` keeps only the picks that differ from the art
skin's palette (`source_skin()`, the shipped skin a custom skin forked from) and
only for the parts the skin's layer holds, so an untouched skin is rebuilt
byte-for-byte from disk. `recolour()` then walks the layer:

* A pixel whose part the player changed is re-emitted - from the new colour's
  ramp, in the shade the layer recorded, for the drawn art.
* The hand-made tier art was not drawn from ramps, so its own light and dark is
  carried across instead (`shade_legacy(source, target, reference)` scales the
  new colour by how bright the pixel was against the colour the artist used).
* Every other pixel, and every pixel the layer marks 0, keeps the art exactly.

Canvas-space distance is all `recolour()` needs, so it works on any 48x48 frame.
Passing the frame it is of (`direction`/`anim`/`frame`) is what finds the layer;
without it - or for art that ships without one - the pixels are matched back
against the art's palette (`MATCH_TOLERANCE` = 0.010 squared RGB distance)
instead, the way re-colouring worked before layers existed.

### Painted pixels

The designer paints the same byte-per-pixel format the layers use, so the two
meet: the layer *is* the frame's stored pixels. The first stroke on a frame
seeds those bytes from `frame_bytes()`, which is the frame's own layer (or, for
art without one, `encode_image()` matching each pixel against the skin's
palette). A painted frame is then drawn from the palette by
`image_from_overlay()`, so it follows later colour changes, and its opaque
pixels are exactly the pixels re-colouring is allowed to touch.

An edit stores a whole frame the first time one of its pixels is painted, so a
partially painted frame keeps the rest of the art. Painting a part the layer
does not hold yet adds it to the skin's layer (`set_part_order()`), which is how
a skin of the player's own can carry a part the shipped art never drew.

### Frames and caching

`frames_for(skin, overrides, fresh)` is the SpriteFrames factory shared by every
golfer. Animations are named `<anim>_<direction>` (`walk_north-east`), speed and
looping come from `ANIMATIONS` (idle 4 fps loop, walk 8 fps loop, swing 10 fps
one-shot), and a facing with no art of its own borrows one
(`DIAGONAL_FALLBACK`). Built frames are cached on
`"<id>|<part=hex,…>|<revision>"`; `invalidate(skin_id)` clears a skin's entries
after an edit. Eight visitors wearing one skin therefore cost one build.

### Spawning

`skins_for_tier(tier)` puts the tier's own art first - for the tiers whose art
the game ships - and then the themed skins that tier may wear;
`random_skin_for_tier(tier)` picks the tier look about 55% of the time and a
themed skin otherwise. `golfer.gd` deals a skin in `assign_visitor_skin()` for
visitor rounds; for the owner round, `apply_player_appearance(profile)` reads
the profile's `skin_id` and colours. A legacy tier skin keeps the golfer's own
`shirt_color`/`pants_color`/… so the existing tier colour variation still
applies.

### The designer

`scripts/ui/golfer_skin_designer.gd` (screen) and
`scripts/ui/skin_pixel_editor.gd` (canvas) are the Customise Golfer Skins
screen. It is one of the popup screens `main.gd` adds to the HUD and hides while
gameplay UI is hidden, opened from the title screen's seventh action
(`customise_skins_requested`).

The left column carries the skin list, the naming buttons and the **part layer**
list: one row per part the skin holds, with the number of pixels of the art that
part owns, the parts left to add, and Add part / Remove part. Selecting a row
arms the pixel brush with that part. The middle column is the canvas: it paints
part+shade indices (`pixel_index`/`decode_pixel`), draws a line between mouse
samples so fast drags still paint, and offers an eraser, zoom and an eyedropper
(which only picks parts the layer holds). The screen writes every change - the
layer's parts included - straight to `PlayerGolferProfile.custom_skins` and
calls `SaveManager.save_golfer_profile()` when it closes, so a crash never costs
more than the stroke in progress.

The designer always works from the *current* catalogue skin (`_current_skin()`),
because every edit rebuilds the catalogue and the skin the designer selected can
be a revision out of date - its layer with it.

## Tuning Levers

| Lever | Location | Value | Effect |
| --- | --- | --- | --- |
| Themed skins | `tools/generate_golfer_skins.py` (`SKINS`, `_draw_pack`) | 13 | How many extra skins ship; regenerate with `python3 tools/generate_golfer_skins.py` |
| Part layers | `tools/generate_golfer_skins.py` (`Painter.to_layer`, `legacy_layer`) | one `.layer.bin` per frame | Which pixels each part owns; re-run the tool after editing the tier-art key |
| Ramp stops | `GolferSkinLibrary.ramp()` | 0.24 / 0.30 / 0.62 / 0.42 | How much light, dark and outline the shading has |
| Match tolerance | `GolferSkinLibrary.MATCH_TOLERANCE` | 0.010 | How close a pixel must be to a ramp entry to be re-coloured - art with no layer only |
| Tier-art share | `GolferSkinLibrary.random_skin_for_tier()` | 0.55 | How often a visitor wears their tier's own look instead of a themed skin |
| Own-skin limit | `PlayerGolferProfile.MAX_CUSTOM_SKINS` | 24 | How many skins of their own a player may keep |
| Name length | `PlayerGolferProfile.MAX_SKIN_NAME` | 24 | Longest skin name the designer accepts |
| Designer breakpoint | `GolferSkinDesigner.BREAKPOINT` | 980 px | Below this the three columns stack into one scrolling column |
