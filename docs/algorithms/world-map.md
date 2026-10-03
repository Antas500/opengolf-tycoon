# World Map, Locations & Site Land

## Plain English

The company grows by buying **course locations** around the world instead of expanding a
single blank plot. Each location is a named destination (Monterey, Scotland, Jamaica, …)
with its own theme, size and globe position. Buying one unlocks a block of parcels on the
standard 6×6 `LandManager` grid and hands the player a fresh site; the company's money,
reputation, calendar and milestones carry across every site, while terrain, buildings,
staff, holes and land belong to the site being played.

The map is different in every world: before the player looks at it, each location rolls
how much of its land comes already cleared. More cleared land means a higher asking price,
so the same destination can be a bargain in one world and a stretch in the next.
**Reset World** re-rolls that for every unowned location.

## Running the Numbers

### Location sizes

| Size | Parcels | Approx. tiles | Hole capacity | Base price |
|------|---------|---------------|---------------|-----------|
| Small | 9 | 60×60 | 9 | $15,000 |
| Medium | 12 | 80×60 | 12 | $24,000 |
| Large | 16 | 80×80 | 16 | $36,000 |
| Championship | 20 | 100×80 | 18 | $52,000 |

Parcels are 20×20 tiles on the existing 6×6 grid, so the parcel count is what actually
changes — the "tiles" column is the bounding box of a typical growth order.

### Asking price

```
price = (size_base_price + unlocked_parcels × $2,200)
        × theme_land_multiplier
        × location_prestige
```

rounded to the nearest $100. `theme_land_multiplier` comes from `CourseTheme`'s
`land_cost_multiplier` (resort and city land is dearer, links and marshland cheaper) and
`location_prestige` is a per-destination 0.95–1.30 factor (famous destinations cost more).
A location's cost is therefore a direct read of how much land the player is buying:
`get_price_for_land(id, unlocked_count)` is exposed for exactly that reason.

### How much land starts unlocked

```
wanted = rng.randi_range(min(4, total), max_unlocked_for_size(size))
max_unlocked_for_size(size) = round(parcels × 0.75)
```

so a Championship site rolls 4–15 pre-cleared parcels and a Small site 4–7.
`layout_order()` turns that count into a shaped block: parcels are ordered by distance
from the grid centre with a per-world random tiebreak, so more land is always a tighter,
more usable cluster rather than a scatter of islands.

### Never roll away the course

Every unlocked set starts from the parcels the biggest requested course needs:

- up to 9 generated holes → the central 2×2 cluster, parcels `(2,2) … (3,3)`
- 18 generated holes → the 3×3 block `(1,1) … (3,3)`, which contains every offset in
  `LAYOUT_18_FRONT` + `LAYOUT_18_BACK`

`WorldLocations.get_required_parcels(holes)` supplies that block and
`layout_order(size, rng, required)` guarantees it is ordered in. `WorldMap.get_location_parcels()`
uses the same call, so the land a site lays down after purchase is always buildable —
`Reset World` can change the price but never makes a destination unusable.

## Generated First Course

What the World Map builds on a new site depends on the **Generated Holes** choice from the
Start New Game screen:

| Holes | Layout | Par |
|-------|--------|-----|
| 0 | none — a bare plot | — |
| 3 | first 3 holes of `LAYOUT_9` | 12 |
| 6 | first 6 holes of `LAYOUT_9` | 24 |
| 9 | `LAYOUT_9` (front nine) | 36 |
| 18 | `LAYOUT_18_FRONT` (= `LAYOUT_9`) + `LAYOUT_18_BACK` | 72 |

The back nine is a counter-clockwise loop outside the front nine with all offsets inside
±27 tiles of the anchor, so it fits the 3×3 required block. `GeneratedCourse.get_anchor(n)`
returns the tile the course is laid out around (`SMALL_ANCHOR` = (63,63) for ≤9 holes,
`CHAMPIONSHIP_ANCHOR` = (53,53) for 18), which is also where the camera focuses when the
site loads. The generator then drops the starter amenities — clubhouse, coffee house,
snack bar, restroom from `AMENITY_SPOTS` — into the pocket beside the first fairway,
skipping any spot whose footprint would overlap a play surface or building.

## Company vs Site

| Company-wide | Per site |
|--------------|----------|
| money, unlimited flag | terrain, elevation |
| reputation, milestones, analytics | entities, buildings, staff |
| calendar (day/date) | holes, land parcels |
| world map: owned locations, unlocked land, active location | course-local statistics and records |

`SaveManager.build_location_snapshot()` strips `SNAPSHOT_COMPANY_KEYS` and keeps only
`SITE_STATE_KEYS`; `switch_to_location()` re-injects the company state afterwards, so
switching sites never resets the business. Saves are `SAVE_VERSION = 5`.

## Reset World

`WorldMap.reset_world()` re-seeds a fresh RNG, keeps any location the player already owns
(they paid for that land), re-rolls every other location's unlocked parcels and price, and
emits `world_reset`. It never touches the company's money, the active site or its snapshot.

## Tuning Levers

| Parameter | Location | Default | Effect |
|-----------|----------|---------|--------|
| `LAND_VALUE_PER_PARCEL` | `world_locations.gd` | $2,200 | How much each pre-cleared parcel adds to the price |
| `MIN_UNLOCKED_PARCELS` | `world_locations.gd` | 4 | Floor on pre-cleared land (the central 2×2) |
| `CHAMPIONSHIP_PARCELS` | `world_locations.gd` | 9 | Parcels reserved for an 18-hole layout |
| `SIZE_DATA[*].base_price` | `world_locations.gd` | $15K–$52K | Site size base cost |
| `LOCATIONS[*].prestige` | `world_locations.gd` | 0.95–1.30 | Per-destination price premium |
| `land_cost_multiplier` | `course_theme.gd` | theme-specific | Theme's land price multiplier |
| `max_unlocked_for_size()` | `world_locations.gd` | 75% of parcels | Ceiling on the pre-cleared roll |
| `MONEY_OPTIONS` | `start_new_game_screen.gd` | 100K/150K/200K/-1 | Starting money choices (`-1` = Unlimited) |
| `HOLE_OPTIONS` | `start_new_game_screen.gd` | 0/3/6/9/18 | Generated-hole choices |
| `SMALL_ANCHOR` / `CHAMPIONSHIP_ANCHOR` | `generated_course.gd` | (63,63) / (53,53) | Where a generated layout is laid out |
| `LAYOUT_18_BACK` | `generated_course.gd` | 9 offsets | The back nine; must stay inside ±27 tiles of the anchor |

## Related Docs

- [Premium Land](premium-land.md) — parcel quality tiers and prebuilt course packages (a
  separate expansion system inside a site)
- [Terrain Types](terrain-types.md) — what the generator paints
- [Economy](economy.md) — green fees, operating costs and the money the price is paid from
