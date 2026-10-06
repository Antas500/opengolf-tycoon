# World Map & New Game Flow — Product Spec

**Author:** Claude (Product)
**Date:** 2026-10-03
**Status:** Completed (2026-10-03)
**Priority:** HIGH
**Version:** 0.4.9-alpha context

---

## Problem Statement

Starting a game asked one question ("which theme?") and dropped the player onto a
blank 40×40 tile square. There was no notion of *where* the course was — a Monterey
links course and a Phoenix desert course were the same parcel of land with different
colors — and no reason to ever buy a second site. The main menu also mixed prose
("New Game (with theme selection and course naming)") with function, and there was no
front-loaded place to decide difficulty, starting capital, course size or which
simulation systems the player actually wanted.

This spec covers the replacement: a short, unambiguous main menu, a **Start New Game**
setup screen, and a **World Map** that turns the company's growth into buying and
switching between named destinations.

---

## Feature Design

### 1. Main Menu

Exactly six entries, in this order:

| Entry | Behaviour |
|-------|-----------|
| **Start New Game** | Opens the setup screen |
| **Quick Start** | Defaults (random company name, Normal, $100,000, 0 generated holes, all features on) → World Map |
| **Continue** | Loads the most recent auto-save/manual save straight back into the course |
| **Load Game** | Opens the save/load panel |
| **Settings** | Opens the settings panel |
| **Quit** | Quits the game |

The old theme cards and course-name field were removed from the menu — theme is a
property of the *location* the player buys on the World Map.

### 2. Start New Game Screen

| Field | Options |
|-------|---------|
| Company Name | Free text, defaults to a random name (`LineEdit`) |
| Difficulty | Easy / Normal / Hard (`DifficultyPresets.Preset`) |
| Starting Money | $100,000 / $150,000 / $200,000 / Unlimited |
| Generated Holes | 0 / 3 / 6 / 9 / 18 — how many holes the generator builds on the first course |
| Game Features | Weather / Wind / Seasons toggles (all on by default) |

**Next** hands the whole dictionary to the world map. **Back** returns to the menu.

Unlimited money is encoded as `WorldMap.UNLIMITED_MONEY = -1`; the HUD shows
`$999,999,999`, every debit is swallowed, `can_afford()` is always true and
`is_bankrupt()` always false. The option itself is preserved through `GameManager.new_game`
so a reload stays unlimited.

### 3. World Map Screen

- **Globe** — an orthographic projection of the world drawn procedurally (hand-tuned land
  polygons of `[lon, lat]` constants in `globe_map.gd`, projected per frame with
  `project_point()` and shaded through a land mask). One marker per location; owned
  locations render differently from buyable ones, the selected one is highlighted and the
  globe turns to face it (`look_at_location`).
- **Location list** — one row per location with **Name**, **Theme**, **Size** and
  **Cost**; rows for owned and unowned sites are visually distinct, and a row shows
  whether the site is currently being played.
- **Buy / Play** — selecting a row shows a Buy button (cost, disabled when unaffordable)
  or a Play button for owned sites. Buying spends money and unlocks the site's parcels.
- **Reset World** — re-rolls the per-location unlocked land and therefore every price,
  giving a fresh map without restarting.
- **Layout** — globe left / list right on wide windows; on a *tall* narrow window
  (portrait phone, tablet) the globe stacks above the list. A squat window stays side by
  side, since a stacked pair needs ~660px of height to show both.
- **Back** — returns to the menu when opened from the menu, or to the course when opened
  from the pause menu.

Players return to the World Map at any time (pause menu → **World Map**) to buy more
locations and swap which one they are playing.

### 4. Locations

27 destinations, each with a `CourseTheme` theme, a size (Small 9 / Medium 12 /
Large 16 / Championship 20 parcels), a `lat`/`lon` for the globe marker and a prestige
factor (0.95–1.30). The requested set is all present:

Monterey, San Diego, Rocky Mountains, Las Vegas, Phoenix, Hawaii, Oahu, Nova Scotia,
Northeast, Carolina, Florida, plus Chicago, New York, Ireland, Scotland, Wales,
South England, Spain, Portugal, Jamaica, Bahamas, Japan, Dubai, South Africa,
Australia, New Zealand and (as "Pacific Northwest") Vancouver.

### 5. Pricing & Land

A location is a block of parcels on the existing 6×6 parcel grid, always containing the
central 2×2 cluster and — when the player asked for 18 generated holes — the 3×3 block
`(1,1)..(3,3)` needed to fit the championship layout. Land is laid down by
`WorldLocations.layout_order(size, rng, required)` so the required block can never be
rolled out of reach.

```
price = (size_base_price + unlocked_parcels × $2,200) × theme_land_multiplier × prestige
```

rounded to the nearest $100. `Reset World` re-rolls how many parcels a site starts with
(between its layout minimum and its full size), which changes its cost — more cleared
land, more money.

### 6. Generated Holes & First Course

`Generated Holes` on the setup screen controls the first course the generator builds
(`GeneratedCourse.generate(n, …)`), from a bare plot (0) to a full 18-hole par-72
course laid out on `LAYOUT_18_FRONT = LAYOUT_9` plus a new counter-clockwise
`LAYOUT_18_BACK`. The generator also drops the starter amenity cluster (clubhouse,
coffee house, snack bar, restroom) into the clear pocket beside the first fairway, and
the camera focuses the course anchor when the site is entered.

### 7. Company vs Site State

Money, reputation, calendar, milestones and analytics belong to the **company**; terrain,
entities, holes, land, staff and course-local statistics belong to the **site**.
`SaveManager` keeps a per-location snapshot (`build_location_snapshot()` strips the
company keys) and `switch_to_location()` re-injects company state on the way back in.
Save format is `SAVE_VERSION = 5`; the `world_map` block stores the company settings,
every location's owned/unlocked state, the active location and the per-location
snapshots.

### 8. Feature Toggles

Weather / Wind / Seasons off mean: weather stays sunny (spawn ×1.0), wind stays calm
(zero displacement), seasons stay in summer with neutral modifiers. The HUD reflects
this — the weather and wind readouts show "Off" and the date shows "Year-round".

---

## Data Model

```
WorldMap (autoload, scripts/autoload/world_map_state.gd)
  company_name, difficulty, starting_money_option, generated_holes, features
  locations: { id: { size, theme, unlocked: [parcels], owned, price } }
  active_location_id, location_snapshots, world_seed
  new_world(options, seed) / reset_world()
  buy_location(id) / can_afford(id) / is_owned(id) / get_price(id)
  get_location_parcels(id) / get_unlocked_parcels(id) / apply_location_land(id)
  set_active_location(id) / take_snapshot(id, snap) / get_snapshot(id)
  ensure_legacy_world(theme)   # keeps the old direct-start entry points working

WorldLocations (scripts/systems/world_locations.gd) — static catalog
  LOCATIONS, SIZE_DATA, get_all(), get_theme(id)
  growth_order(size, rng), layout_order(size, rng, required)
  get_required_parcels(holes), get_parcel_count(size), get_hole_capacity(size)
  compute_price(id, unlocked_count) / get_price_for_land() alias, random_company_name()

GlobeMap (scripts/ui/globe_map.gd)
  set_locations(list) / set_selected(id) / look_at_location(id)
  signal location_clicked(id)
  static project_point(lon, lat, center_lon, center_lat) / is_land(lon, lat) / build_land_points()

WorldMapScreen (scripts/ui/world_map_screen.gd)
  refresh() / select_location(id)
  signals play_location_requested(id), back_requested
```

---

## Implementation Sequence

1. `WorldLocations` catalog + pricing; `WorldMap` autoload and `project.godot` registration.
2. `StartNewGameScreen` and the rewritten six-entry `MainMenu`.
3. `GlobeMap` (land polygons, projection, markers, click picking).
4. `WorldMapScreen` (globe + rows + Buy/Play + Reset World), responsive compact layout.
5. `main.gd` wiring: menu → setup → world map → first course; pause menu → world map;
   site switching and snapshots.
6. `SaveManager` v5 (world_map block, company/site split).
7. `GeneratedCourse`: 18-hole par-72 layout, amenity pocket, layout-aware land blocks.
8. Feature gates in the HUD and the simulation systems.

---

## Success Criteria

- Main menu contains exactly the six entries above — no theme cards, no course-name field.
- Setup screen offers every listed option and Quick Start uses the documented defaults.
- Globe shows a marker per location and a click selects it; the list shows name, theme,
  size and cost.
- Reset World re-randomises unlocked land and visibly changes prices.
- Buying a location debits money and unlocks its land; the player can switch between
  owned sites and the company (money, calendar, reputation) persists across the switch.
- The generated first course matches the requested hole count — an 18-hole first course
  is par 72 and every tee and green is on owned land.
- Weather/Wind/Seasons off remove those systems' effects and say so in the HUD.
- All of the above survives save/load (`SAVE_VERSION = 5`).

---

## Out of Scope

- Per-parcel land quality tiers and prebuilt course packages — see
  [`premium-land-prebuilt-courses.md`](premium-land-prebuilt-courses.md); those are a
  separate, still-open idea for land *inside* a site.
- Multiplayer, course sharing, or cross-company competition.
- Real geography data — the globe's land mask is a hand-tuned constant polygon set.
