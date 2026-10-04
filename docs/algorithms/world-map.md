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

## The Globe

The atlas in the middle of the World Map screen (`GlobeMap`) is drawn in two layers, and
the split is what makes it both pretty and cheap:

| Layer | What it draws | When it repaints |
|-------|---------------|------------------|
| Planet (`shaders/globe_planet.gdshader` on a `ColorRect`) | The whole sphere: ocean depth and coastal shelf, land with terrain and an arid band, polar ice, a sun with a day/night terminator and a specular glint on water, the 30° graticule and the atmosphere halo | Whenever the *view* moves (drag, flick, zoom, centre-on-destination, resize) |
| Markers (`Control`) | One pin per destination plus the selected/hovered label | Whenever the *pins* change (hover, selection, buy, list refresh) |

**The mask.** The continents are still the hand-tuned `[lon, lat]` polygons in
`globe_map.gd`; they are rasterised once into a 2048×1024 equirectangular coverage mask
(`build_land_mask()`) and cached as an `ImageTexture` for the whole run — every `GlobeMap`
instances shares it. The bake is a scanline fill: a row's land spans are written in bulk,
and only the two ends of each span are written pixel by pixel with their analytic coverage,
which gives soft coastlines without testing thousands of points per row. 2048×1024 bakes in
about 15 ms in a debug build (plus ~15 ms of mipmaps when the texture is first created), so
the screen pays it once and never again. (Testing every texel with
`Geometry2D.is_point_in_polygon` instead would take seconds; rasterising the old way, at
3° steps, produced ~2,700 land points.)

**The shading.** The shader inverts the orthographic projection to get the lon/lat under
each pixel — the exact inverse of `GlobeMap.project_point`, which is what places the pins —
so the two must agree or the mask renders mirrored while the pins slide off their
destinations. Screen `+y` grows downwards and the globe's `+y` grows up, hence the negated
vertical component when the shader builds its surface normal; `tests/unit/test_globe_map.gd`
reads that sign out of the shader source and checks the round-trip on every view centre. The
shader then samples the mask three times (plus four probes for the coastal shelf), and
shades analytically — no assets, no pre-baked day/night. Relief and cloud noise are 3D
value noise sampled on the *globe's own normal*, so the pattern is anchored to the surface
(it rides the continents as they turn, and there are no radial streaks over the poles).
The sphere is a pure function of four uniforms — `view_size`, `center_lon_deg`,
`center_lat_deg`, `radius_scale` — so spinning the globe costs four uniform writes and one
draw call, with no per-frame CPU projection and no texture upload. That also means the sun
could be animated later just by moving a uniform: the mask has no camera baked into it.

**Cost, before and after.** The old globe iterated every land point (about 2,700 of them)
on every repaint, projecting each one and discarding the far half of the globe — the
projection pass alone measured ~2.3 ms per repaint in a debug build, before any of the
~1,300 `draw_circle` calls, the ocean, the graticule or the coastline. The planet is one
quad: the per-frame CPU work is the four uniform writes and the ~3 draws per destination on
the marker layer (about 80 for the full 27-destination catalog), and the markers only
repaint when the pins change — hovering or selecting a destination costs the planet
nothing.

**Why the fallback still exists.** `GlobeMap.LandStyle.DOTS` keeps the original land-dot
drawing (one small disc per rasterised land point, no shader) for callers or platforms that
want nothing to do with a `ShaderMaterial`. It builds no planet layer and rasterises its
points lazily. The planet style is the default.

**Hand feel.** A drag tracks the finger 1:1 in degrees per pixel, and letting go mid-drag
keeps the spin, decaying it at `SPIN_DECAY` per second up to `MAX_SPIN_DEG_PER_SEC`. Zoom
(wheel, buttons, pinch) eases to a target rather than jumping, and `look_at_location`
flies the globe the shortest way round over `CENTER_DURATION` seconds — always the shortest
way, so asking for Japan from Hawaii crosses the Pacific rather than unwinding across Asia.
The globe is only `_process`ed while one of those animations is running or a flick is still
coasting; an idle globe costs nothing.

**Looking at it without a GPU.** `tests/harness/globe_preview.gd` renders the polygon mask,
the baked mask and the dots fallback to PNGs. `tests/harness/planet_preview.gd` is a CPU
port of the shader (palette and tuning values parsed from its uniform defaults) that writes
the default view, the pole and the Pacific to `tmp_preview/planet_view*.png` — a look
preview for CI and GPU-less machines, never a substitute for compiling the shader.

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
| `MASK_WIDTH` / `MASK_HEIGHT` | `globe_map.gd` | 2048 × 1024 | Land-mask resolution — the globe's detail ceiling (costs ~15 ms to bake, once per run) |
| `LAND_STEP_DEG` | `globe_map.gd` | 3.0 | Land-dot spacing in the `LandStyle.DOTS` fallback (~2,700 points) |
| `MIN_RADIUS_SCALE` / `MAX_RADIUS_SCALE` | `globe_map.gd` | 0.7 / 1.6 | How far the globe can be zoomed |
| `MAX_SPIN_DEG_PER_SEC` / `SPIN_DECAY` | `globe_map.gd` | 320 / 0.02 | Flick inertia: the cap on a throw and how fast it settles |
| `CENTER_DURATION` / `ZOOM_SETTLE_RATE` | `globe_map.gd` | 0.5 s / 14 | Fly-to and zoom easing while the list drives the globe |
| `light_dir`, `ambient_floor`, `terminator_softness` | `globe_planet.gdshader` | camera-relative, 0.62, 0.34 | Sun direction, night-side brightness and how soft the terminator is |
| `relief_strength`, `biome_strength`, `ice_strength` | `globe_planet.gdshader` | 0.70 / 0.35 / 0.85 | How much terrain, desert and polar ice the land shows |
| `coast_glow`, `atmosphere_strength`, `limb_haze`, `cloud_amount` | `globe_planet.gdshader` | 0.40 / 0.55 / 0.35 / 0.14 | Coastal shelf tint, halo brightness, limb haze and cloud cover |
| `graticule_alpha` / `graticule_step_deg` | `globe_planet.gdshader` | 0.10 / 30° | Grid visibility and spacing |
| `ocean_*`, `land_*`, `ice_color`, `atmosphere_color`, … | `globe_planet.gdshader` | old dot palette (`#16314a` ocean, `#5f7d4a` land, …) | The globe's colours |
| `MONEY_OPTIONS` | `start_new_game_screen.gd` | 100K/150K/200K/-1 | Starting money choices (`-1` = Unlimited) |
| `HOLE_OPTIONS` | `start_new_game_screen.gd` | 0/3/6/9/18 | Generated-hole choices |
| `SMALL_ANCHOR` / `CHAMPIONSHIP_ANCHOR` | `generated_course.gd` | (63,63) / (53,53) | Where a generated layout is laid out |
| `LAYOUT_18_BACK` | `generated_course.gd` | 9 offsets | The back nine; must stay inside ±27 tiles of the anchor |

## Related Docs

- [Continuous Course Surface](course-surface.md) — the other shader-driven surface, and the
  theme palette the globe's colours echo
- [Premium Land](premium-land.md) — parcel quality tiers and prebuilt course packages (a
  separate expansion system inside a site)
- [Terrain Types](terrain-types.md) — what the generator paints
- [Economy](economy.md) — green fees, operating costs and the money the price is paid from
