# The Clubhouse

> **Source:** `scripts/systems/course_clubhouse.gd`, `scripts/entities/building.gd`,
> `scripts/course/entity_layer.gd`, `scripts/entities/golfer.gd`,
> `scripts/managers/golfer_manager.gd`, `scripts/entities/course_architecture.gd`

The clubhouse is drawn as an isometric solid on its four tiles — paved terrace,
stone plinth, hipped roof, chimney and an entrance canopy on the edge golfers
walk to — by the shared building renderer. Each upgrade tier adds a storey or a
wing and never grows past the tiles it stands on. See
[isometric-buildings docs](isometric-buildings.md).

## Plain English

Every course has exactly one clubhouse, and it is not like the other buildings.
The player never buys one, cannot bulldoze one, and cannot end up with two:
whatever way a course is started — Quick Start, a generated layout, a prebuilt
package, or an empty plot — the game makes sure a clubhouse is standing somewhere
legal before play begins. A save that predates the rule (or one whose layout
could not fit the building where it wanted it) gets one on load.

The clubhouse is also where the golfers come from and go back to. A new group
does not appear on the first tee: the guests walk out of the clubhouse door and
across the course to the first tee, then start their round. When the last putt
drops they walk back to the door, spend a moment inside (that visit is what pays
the clubhouse its per-golfer income and restores their needs), and only then are
they taken off the course and the group's slot is freed up.

Because it can never be demolished, the panel for it carries the one thing you
can do to it: **Move Clubhouse**. Picking it up turns the cursor into a ghost of
the building; the next click sets it down wherever the ordinary building rules
allow (its own footprint is ignored, so nudging it a tile or two works). Escape
or a right-click puts it back. Moving is free, and Ctrl+Z still returns it.

## Where the clubhouse goes

`CourseClubhouse.ensure(terrain_grid, entity_layer, preferred)` is the single
entry point. It returns the existing clubhouse untouched if there is one, so
every caller is safe to call repeatedly. When there is none it searches square
rings outward from a list of anchors and takes the first legal footprint:

1. `preferred` — the spot the course layout left for it (Quick Start's arrival
   garden at `(54, 61)`, or the generated layouts' amenity pocket at
   `anchor + (1, 6)`).
2. `arrival_corner()` — the corner of the owned land every shipped layout keeps
   clear (Quick Start's garden, `owned land centre + (-9, -2)`). This is the spot
   an empty lot or a prebuilt package gets.
3. The centre of the owned land, then the centre of the course.

Each anchor is searched in two passes: ground that needs no clearing first, then
ground the clubhouse may clear for its own plot (trees, brush, stony ground). The
footprint must be owned, free of buildings and decorations, and on buildable
terrain — grass, rough (all three grades), deep rough, flower bed, firm fairway,
path — and never on a green, tee, fairway, bunker, water, stream or out of
bounds. Trees, brush and stony ground inside the chosen footprint are cleared and
re-laid as grass as landscaping (not as a player edit: it never enters the undo
history or the maintenance books), and the chosen door tile is cleared so guests
have somewhere to stand.

## The front door

`CourseClubhouse.front_tile()` returns the tile the golfers use: the first
walkable tile just outside the footprint, starting at the middle of the
screen-facing (south) edge and fanning out to the corners, the flanks and
finally the back. A tile shadowed by an obstacle is passed over in favour of an
open one, but a clubhouse ringed by trees still gets a door. Golfers spawn on
that tile, walk home to it, and the walking-path overlay paves up to it, so a
moved clubhouse moves its doorstep and the paving follows.

## Moving it

`CourseClubhouse.move_error()` is the single authority the move preview, the
click handler and any future UI all ask, so they can never disagree:

| Rule | Message |
| --- | --- |
| The whole footprint must be on the course | "The whole clubhouse must fit on the course." |
| The whole footprint must be owned land | "Buy this land first — the whole footprint must be owned." |
| No other building in the footprint | "Move the footprint clear of the other building." |
| No decoration in the footprint | "Remove the decoration in this footprint first." |
| No tree in the footprint | "Clear the tree first: paint another Course Terrain tile over it." |
| Buildable terrain only | "Move it off the greens, tees, sand and water." |
| Already there | "The clubhouse is already there." |

A legal move keeps the same `Building` node, so its upgrade level, architecture
and lifetime revenue all come along: `EntityLayer.move_building()` re-keys the
dictionary and repositions the node, then emits `building_moved` (the
walking-path overlay listens and re-paves). `CourseClubhouse.move_to()` checks
the rules itself as well, so a click can never drop the building somewhere the
preview said no.

## Never demolished

Three layers refuse it, so no code path can lose the course's clubhouse:

- `Building.destroy()` refuses a `required: true` building unless the caller
  passes `force: true` (only `EntityLayer.clear_all()` does, because "clear the
  layer" means empty, not "demolish what the rules allow").
- `EntityLayer.remove_building()` refuses a required building (and resolves a
  click on any footprint tile to the building covering it).
- `main.gd::_handle_bulldozer_click()` checks first and tells the player to move
  it instead, so the Bulldozer click does not even take the demolition fee.

## Arriving and leaving

The golfer state machine gained one state, appended last so saved ids never
shift: `LEAVING` (6) is the walk home and the visit at the door. `FINISHED`
still means "gone".

| Stage | What happens |
| --- | --- |
| Spawn | `GolferManager.spawn_golfer()` seats the guest on the clubhouse door tile, puts their ball on the first open tee and walks them there (`Golfer.begin_arrival_from_clubhouse()`). Because the turn system only ever picks an IDLE golfer, an arriving guest cannot be given a shot until they arrive. |
| Round over | `finish_round()` records the score, reputation and feedback as before, then calls `_begin_departure()`: the golfer walks to the door (`LEAVING`, 30 s timeout so a blocked route can never strand them). |
| At the door | `_arrive_at_clubhouse()` applies the clubhouse visit — per-golfer income for upgraded clubhouses, need restoration, satisfaction bonus — and the golfer pauses for `CLUBHOUSE_VISIT_SECONDS` (1.6 s). |
| Gone | `_leave_course()` turns the golfer `FINISHED` and emits `EventBus.golfer_left_course` exactly once. |
| Removal | `GolferManager._on_golfer_left_course()` waits until every member of the group is inside, then removes the group after a 1 s send-off pause. This is the only removal path for a finished group: the round-over signal fires before the walk and so cannot do it. |

`LEAVING` counts as off the course everywhere it matters — capacity, tee and
landing-zone clearance, hole-clear checks, staff service and amenity visits —
so a group walking home never blocks play or keeps a slot. Tournament groups use
the same path; the seating logic that spreads them over open holes is untouched
because it reads `current_hole`, which a walking golfer no longer changes.

## Tuning Levers

| Parameter | Location | Current Value | Effect |
| --- | --- | --- | --- |
| Clubhouse footprint/cost | `data/buildings.json` | 4x4, $10,000, `required` | The one building that is not optional |
| Guarantee cost | `course_clubhouse.gd::ensure` | free | The course always has one: it is never bought and never charged |
| Search radius | `course_clubhouse.gd` `SEARCH_RADIUS` | 40 tiles | How far from the anchor a home may be searched for |
| Arrival corner offset | `course_clubhouse.gd` `ARRIVAL_CORNER_OFFSET` | (-9, -2) from owned centre | Where an empty lot or prebuilt package puts its clubhouse |
| Forbidden terrain | `course_clubhouse.gd` `FORBIDDEN_TERRAINS` | greens, tees, fairways, sand, water, OB | Ground the guarantee will not build over |
| Move cost | `main.gd::_handle_building_move_click` | free | Moving is free; undo still restores the old spot |
| Visit length | `golfer.gd` `CLUBHOUSE_VISIT_SECONDS` | 1.6 s | How long a golfer stands at the door before leaving |
| Walk-home timeout | `golfer.gd` `DEPARTURE_TIMEOUT_SECONDS` | 30 s | After this the visit happens wherever the golfer is |
| Group send-off | `golfer_manager.gd::_on_golfer_left_course` | 1.0 s | Pause after the last golfer is inside before removal |
