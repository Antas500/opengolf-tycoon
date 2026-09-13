# Landforms and clubhouse life

## Plain English

Vertex Selector and Square Selector tools make exact changes to the existing
elevation map: one corner at a time, or one square leveled before it is lifted.
Left-click lowers, Right-click raises, and each click touches only the selected
vertex or square. They preserve buildings and land ownership, and use the
existing undo/save system. Quick Start holes 2, 5, and 8 now have raised tees,
crowned greens, and a shallow valley between them. Other courses are not
reshaped on load. These are real elevation changes used by the simulation;
the rendering still uses the existing world coordinates, without geometric
terrain displacement or an isometric-grid migration.

Height steps of two or more levels across a tile read as vertical cliffs:
exposed rock with faint strata in the surface renderer, rock outlines in the
elevation overlay, and cliff helpers (`is_cliff_tile`, `get_cliff_edges`) on
the grid. The terrain generator stamps flat-topped plateaus (and occasional
sunken quarries) with abrupt cliff rims, mostly on Mountain, Desert, and
Tropical themes.

Facilities share warm cream siding, green shutters, tiled gable roofs, and fixed
window/door proportions. Clubhouses grow by adding facade bays at each upgrade.
An attached veranda and compact stone apron replace the detached oversized patio.
Flower boxes, a clock dormer, striped shop awnings, cart bays, and chimney smoke
identify the different facilities. Windows turn warm at dusk. Recessed porch
floors, shaded posts, sheltered benches, entrance gables, climbing roses, and
wall lanterns add depth at the front door. Upgraded clubhouses fly a small
animated pennant; restaurants have a sheltered bistro table.

Every facility has purpose-specific detail: pro-shop merchandise, golf bags and
chalkboards; restaurant window boxes; snack-hut menus and cup signage; restroom
trellises and a sheltered threshold; cart-shed ventilation, equipment and wheel
stops; and range-pavilion bracing, mat dividers and ball baskets. All are cosmetic
and share the built/ghost geometry. The buildable bench uses the same grounded
`park_bench` renderer as decorative benches.

Golfer preparation gains a small address waggle. Finishing under par produces a
brief happy hop and glints; over par produces a slump; par gets a small nod. These
poses accompany the existing score thoughts and walking/swing sprites.

## Algorithms

The Vertex Selector adjusts one vertex by ±1 per click. The Square Selector
raises the square's lowest corner(s) or lowers its highest corner(s); once all
four corners are even, the whole square moves together. Clamp resulting levels
to -5..5. Pinned corners (buildings, unowned land) still count toward the level
target but never move. Collect each changed vertex's old and new elevation for
the existing undo manager. There is no brush falloff: unselected vertices are
never touched. Quick Start raises green pads to +2 and tees to +3 in small
rings, plus a -1 mid-fairway swale. Plateau stamps flatten every vertex inside
an organic disc to one height and leave the outside untouched, so the rim is a
cliff face.

The surface texture's blue channel stores `(base elevation + 5) / 10`. A second,
linearly filtered sampler reads that same texture at ±1.5 tiles to estimate a
broad normal. Sun direction drives restrained material shading (0.75–1.12), with
flat ground remaining neutral. Existing detailed elevation shading/contours are
visible only while an elevation selector is active. Four extra texture samples avoid the repeating
sub-tile profile patches. Elevation edits update the same coalesced texture upload;
physics elevations do not change through rendering.

`CourseArchitecture` draws buildings and placement ghosts from identical geometry.
World footprints stay unchanged. Facades are horizontal; depth recedes by
`(-0.55 * depth, -0.5 * depth)`. Clubhouse facade widths are 138, 166, and 194
pixels, with fixed 14-pixel doors. Roof planes share one ridge and masonry return.
Foundation, porch posts, stairs, and apron use the same base coordinate.
The 10 Hz cosmetic clock respects pause; chimney smoke and window light are drawn
from the actual architecture, replacing offsets tied to old sprite dimensions.
Rebuilding removes the old visual and click area before adding replacements.

`GolferExpression` is a parent of the existing Visual node. Its local position,
rotation, and scale affect only the body, keeping the actor's world position,
ball, path, and labels unchanged. A real-time 2.2-second reaction begins after
`finish_hole`. Starting preparation or a swing cancels any remaining reaction.
The existing shot-preparation duration, swing completion signal, and shot timing
remain authoritative. Pause freezes the cosmetic timer.

## Tuning levers

| Setting | Value | Effect |
| --- | --- | --- |
| Selector step | ±1 | Height change per click |
| Cliff step | 2 levels | Corner/edge step that reads as a cliff |
| Cliff shading | 1.75 → 3.0 levels/tile | Rock blend ramp in the surface shader |
| Plateau height | ±2..±4 | Mesa tops and sunken quarry floors |
| Plateau radius | 4–9 vertices | Generator mesa size |
| Landscape gradient step | 1.5 tiles | Broader, more readable lighting |
| Architecture redraw | 10 Hz | Bounded ambient drawing |
| Reaction duration | 2.2 real seconds | Readable without slowing the game |
| Happy hop height | 4 pixels | Small celebration with feet returning to ground |

Integration tests check single-vertex/square edits, level-then-lift, save/undo,
buildings and height limits, cliff detection, plateau rims, monotonic upgrade
growth and unique visual/click areas, pose isolation, pause, and
cancellation when the next shot starts. Native QA includes the clubhouse,
illustrated reaction poses, Quick Start holes with raised tees, and a live simulation.
