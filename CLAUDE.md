# OpenGolf Tycoon — Codebase Context

A SimGolf (2002) spiritual successor built in **Godot 4.6+** with GDScript. Players design golf courses, manage operations, attract golfers, and host tournaments.

**Main scene:** `res://scenes/main/main.tscn` (Node2D root)
**Engine:** Godot 4.6, Forward+ renderer, native window-pixel rendering (responsive; 1600x1000 design reference)
**License:** MIT | **Version:** 0.1.0 (Alpha)

## Project Structure

```
scripts/
├── autoload/       # Singletons: GameManager, EventBus, WorldMap, SaveManager, FeedbackManager, SoundManager, ShadowSystem
├── course/         # HoleVisualizer, DifficultyCalculator, EntityLayer
├── effects/        # RainOverlay, HoleInOneCelebration, SandSprayEffect
├── entities/       # Golfer, Ball, Building, Tree, Rock, Flag
├── managers/       # GolferManager, BallManager, HoleManager, PlacementManager, BuildingRegistry, TournamentManager
├── systems/        # WorldLocations, GeneratedCourse, WindSystem, WeatherSystem, CourseRatingSystem, CourseTheme, FeedbackTriggers, GolferTier, TournamentSystem, DayNightSystem, CourseRecords, ShotAI, GolferNeeds, SeasonSystem, MilestoneSystem, TutorialSystem, DifficultyPresets, ColorblindMode
├── terrain/        # TerrainGrid, TerrainTypes, TerrainPalette, + overlay classes (cup, tee aim arrows, OB stakes, shot heatmap, …)
├── tools/          # HoleCreationTool, ElevationTool, UndoManager
├── ui/             # UI components (MainMenu, StartNewGameScreen, WorldMapScreen, GlobeMap, PauseMenu, SettingsMenu, MiniMap, FinancialPanel, MilestonesPanel, HoleStatsPanel, CourseScorecardPanel, SaveLoadPanel, HotkeyPanel, etc.)
│   └── components/  # Reusable widgets (tile honeycomb/buttons, compass needle, rotate arrows, MenuBackdrop, MenuFlagMark, MenuStyle, SetupGlyph, CoursePlanPreview)
├── main/           # main.gd (scene controller)
└── utils/          # IsometricCamera
scenes/
├── main/main.tscn  # Primary game scene
└── entities/golfer.tscn
data/
├── buildings.json      # 8 building types with upgrade tiers
├── terrain_types.json  # 20 terrain type definitions
└── golfer_traits.json  # 5 golfer archetypes with spawn weights
assets/
├── sprites/             # Course objects, golfers, buildings, and decorations
└── themes/              # Shared UI theme resources
```

## Architecture

### Autoloads (Singletons, registered in project.godot)

1. **Screen** (`scripts/autoload/screen_manager.gd`) — Responsive layout adapter (see "Responsive Layout & Touch" below). Exposes `window_size`, `world_scale`, `is_compact()`, `available_panel_rect()`, `bottom_bar_height()` and a `changed` signal; pure `compute_scale()`/`compute_world_scale()` statics are unit-tested.
2. **TouchInput** (`scripts/autoload/touch_input.gd`) — Translates raw touch gestures into game input (tap → synthetic LMB click, one-finger drag → camera pan or terrain paint, two-finger → pan + pinch zoom, two-finger tap → synthetic RMB/cancel). The engine's `emulate_mouse_from_touch` is **off**; this autoload is the only touch path. `camera` and `paint_mode_provider` are wired by main.gd.
3. **GameManager** (`scripts/autoload/game_manager.gd`) — Central game state: money (settled by the Start New Game screen — Easy/Normal/Hard presets, or Unlimited via `WorldMap.UNLIMITED_MONEY = -1`), reputation (0-100), day/hour cycle, game mode (MAIN_MENU/BUILDING/SIMULATING/PLAYING/PAUSED), game speed (PAUSED/NORMAL/FAST/ULTRA), current_theme (CourseTheme.Type). Holds `CourseData`, `DailyStatistics`, `HoleStatistics` inner classes. References terrain_grid, wind_system, weather_system, entity_layer, tournament_manager.
4. **EventBus** (`scripts/autoload/event_bus.gd`) — ~60 signals for decoupled cross-system communication. Categories: game state, economy, terrain/building, course design, golfers, shots, UI, wind/weather, camera, selection, day cycle, tournaments, save/load. Has `notify()` and `log_transaction()` convenience methods.
5. **SaveManager** (`scripts/autoload/save_manager.gd`) — JSON-based persistence (v5 format). Auto-saves on day change. Serializes game state, terrain, entities, holes, wind, weather, tournaments, course records, course theme, and the company world map (`world_map`: settings, per-location owned/unlocked land, active location and a snapshot per owned site). Company-level state (money, reputation, calendar, milestones, analytics) is shared; `build_location_snapshot()` strips `SNAPSHOT_COMPANY_KEYS` so each site snapshot holds only `SITE_STATE_KEYS`, and `switch_to_location()` re-injects the company state. Golfers are NOT persisted (they respawn naturally on load). Emits `theme_changed` on load to refresh overlays.
6. **FeedbackManager** (`scripts/autoload/feedback_manager.gd`) — Aggregates golfer thought bubbles into daily satisfaction metrics (positive/negative/neutral counts, satisfaction rating 0.0-1.0).
7. **WorldMap** (`scripts/autoload/world_map_state.gd`) — The company's world: company name, difficulty, starting-money option, requested generated holes and the Weather/Wind/Seasons feature flags, plus one entry per location (`size`, `theme`, unlocked parcels, owned, price). Owns `active_location_id` and a snapshot per owned site (see "World Map & Locations").

### Key Design Patterns

- **Signal-driven architecture**: Systems communicate through EventBus signals, not direct references. Past tense for events (`golfer_finished_hole`), present tense for state changes (`money_changed`).
- **Manager pattern**: Dedicated manager per entity type (GolferManager, BallManager, HoleManager). Managers handle spawning, removal, lifecycle.
- **State machines**: Golfer states (IDLE/WALKING/PREPARING_SHOT/SWINGING/WATCHING/FINISHED), Ball states (AT_REST/IN_FLIGHT/ROLLING/IN_WATER/OUT_OF_BOUNDS), Game modes.
- **Data-driven config**: Buildings, terrain types, golfer traits loaded from JSON files in `data/`.
- **Overlay pattern**: Each terrain visual effect (water shimmer, bunker stipple, etc.) is a separate overlay class managed by TerrainGrid.
- **RefCounted systems**: WindSystem, WeatherSystem, CourseRatingSystem are stateless/near-stateless with static calculation methods.

### Scene Tree (main.tscn)

```
Main (Node2D) ← main.gd
├── TerrainGrid (Node2D) ← terrain_grid.gd (builds the shader-driven CourseSurface)
├── Entities (Node2D)
│   ├── Golfers, Balls, Buildings (Node2D containers)
├── GolferManager, BallManager, HoleManager (Node)
├── Holes (Node2D)
├── IsometricCamera (Camera2D)
└── UI (CanvasLayer)
    └── HUD (Control) → HUDStatusColumn (top-right stats column), ScoresDock (top-left corner: the owner's round scorecard for practice rounds and matches against a pro, and the live tournament leaderboard while an event runs — `scripts/ui/scores_dock.gd` + `scripts/ui/round_scores_panel.gd`), BottomBar (view/speed controls + tabbed TerrainToolbar: Terrain / Improve / Build / Elev / Holes / Golfers / Player / Club / Staff). The Player tab's Play Course page is the owner's round HUD: while a round runs its setup sections swap for the aiming view, whose top row is one button per shot type — straight, fade, draw, high backspin, low punch (`scripts/ui/components/shot_type_bar.gd`, so the whole set is visible and the lit button is the shot `Golfer.play_shot()` will hit) — above the scrolling control columns. The view controls are one row: a counter-clockwise Rotate arrow (`scripts/ui/components/rotate_view_button.gd`, hotkey Q), the compass needle and its letter (`scripts/ui/components/compass_needle.gd` — the arrow sweeps counter-clockwise or clockwise, the needle turns a quarter turn per rotation to point the way the course faces: N up, E right, S down, W left), a clockwise Rotate arrow (Shift+Q), and beneath them the speed controls. Both arrows are *drawn*, never typed: the font carries no ⟲ / ⟳ glyphs. The Staff tab has exactly two sections (no separate Staff Management window): **Hire Staff**, one standard and one premium button per job type, and **Current Staff**, the payroll/weed status line plus a row per employee with a Move Area button (click a tile to set that employee's designated area) and a Fire button. Hired staff appear on the course as `StaffMember` nodes under `Entities/Staff`, wander a grid-space circle ("designated area", drawn by `scripts/ui/staff_area_overlay.gd`) and work at what they find there: Groundskeepers pull weeds grown by `scripts/managers/weed_manager.gd` (which set the daily course condition), Greeters cheer golfers' mood, Marshals restore pace, Drinks Vendors quench the golfer thirst need. Each job's premium type (Technician / Celebrity / Marshall / Cart Refresher) costs more but has a bigger area, moves faster and works faster. The Improvements tab holds one honeycomb of isometric tiles — the Path tool leading the top row, then the decoration catalogue (no separate Garden Shed window): `scripts/ui/components/decoration_tile_button.gd` + `decoration_tile_art.gd`, filled from `data/decorations.json` by `TerrainToolbar.set_decoration_registry()`. The Improvements and Buildings tabs each pin a round Bulldozer button (`scripts/ui/components/bulldozer_button.gd`) to their bottom-left corner; it only demolishes paths, decorations and buildings — every Course Terrain tile (ground, flower beds, trees and boulders) replaces every other and ignores it. The clubhouse is the exception: it refuses the Bulldozer and is moved from its own panel instead (`CourseClubhouse`). The Course Terrain tab pins its brush controls to that same corner (`TerrainToolbar._pin_brush_dock`): a square plate of four cells — shape, size, smaller, bigger — held narrow enough to sit in the gap the staggered tile rows leave, so it floats above the shelf without covering a tile and never scrolls away with it. The Course Terrain tab's Open Hole action is a half-size course cell (`scripts/ui/components/open_hole_notch_button.gd`) nestled into the notch between the Tee Box and Green tiles it pairs (`TileHoneycomb.set_notch_child`), so it takes no slot along either row; its gold ring appears while a tee and a cup are waiting. The Holes tab is one button per hole, stacked three to a column (`TerrainToolbar.layout_hole_buttons`, filled by `main.gd._on_hole_created`), and a button opens that hole's context menu — the same one the course's tee, green and flag open, holding the pin, tee, green, par, open/closed toggle, statistics and Delete Hole (behind a `ConfirmDialog`) — so no Open/Close or Delete button sits beside it.
```

## Algorithm Documentation

Detailed algorithm docs live in **`docs/algorithms/`** — see [`docs/algorithms/README.md`](docs/algorithms/README.md) for the full index. Each doc has a plain-English explanation and the actual math/code, plus a tuning levers table.

**When modifying any algorithm or adding a new one, update the corresponding doc in `docs/algorithms/`.** If adding a new system, create a new markdown file and add it to the README index.

Key docs: [clubhouse](docs/algorithms/clubhouse.md) · [shot-accuracy](docs/algorithms/shot-accuracy.md) · [putting](docs/algorithms/putting-system.md) · [shot-ai](docs/algorithms/shot-ai-target-finding.md) · [ball-physics](docs/algorithms/ball-physics.md) · [wind](docs/algorithms/wind-system.md) · [weather](docs/algorithms/weather-system.md) · [course-rating](docs/algorithms/course-rating.md) · [difficulty](docs/algorithms/difficulty-calculator.md) · [stroke-index](docs/algorithms/stroke-index.md) · [economy](docs/algorithms/economy.md) · [reputation](docs/algorithms/reputation.md) · [golfer-spawning](docs/algorithms/golfer-spawning.md) · [satisfaction](docs/algorithms/satisfaction-feedback.md) · [golfer-needs](docs/algorithms/golfer-needs.md) · [tournaments](docs/algorithms/tournament-system.md) · [game-calendar](docs/algorithms/game-calendar.md) · [staff-and-weeds](docs/algorithms/staff-and-weeds.md) · [group-turn-order](docs/algorithms/group-turn-order.md)

## Core Systems

### Terrain
- **TerrainGrid**: 128x128 grid (64x32 px tiles). `_grid` dict (Vector2i → terrain type int), `_vertex_elevation` packed array (vertex → level 0..10, with flat ground at `BASE_ELEVATION` = 5).
- **GridProjection** (`terrain/grid_projection.gd`): the single grid ↔ world map. Renders the grid top-down or as 2:1 isometric diamonds and spins it through four 90° view orientations (SimGolf-style rotate). Purely affine, so `unproject()` is exact for mouse picking and both terrain shaders can invert it per fragment. The projected course always fills the same world rectangle, so camera bounds, the minimap and land boundaries are rotation-independent.
- **Overlays** draw per-tile shapes through `OverlayGeometry` (`terrain/overlay_geometry.gd`), which projects tile outlines/centres into the overlay's local space so they render as diamonds when isometric. Each tee tile's painted aim arrow (`terrain/tee_aim_overlay.gd`) is one of them: it points at the hole's cup, curving round the corner of a dogleg ([tee-aim-arrow](docs/algorithms/tee-aim-arrow.md)).
- **20 terrain types**: EMPTY, GRASS, FAIRWAY, ROUGH, HEAVY_ROUGH, GREEN, TEE_BOX, BUNKER, WATER, PATH, OUT_OF_BOUNDS, TREES, FLOWER_BED, ROCKS, FIRM_FAIRWAY, POT_BUNKER, STREAM, DEEP_ROUGH, WASTE_BUNKER, BRUSH. New ids are only ever appended (saves store raw ints). Gameplay code checks families — `TerrainTypes.is_water()`, `is_out_of_play()`, `is_bunker()`, `is_sand()`, `is_fairway()`, `is_rough()` — so variants behave like their parents; see `docs/algorithms/terrain-types.md`.
- **CourseSurface / TerrainPalette**: The course is rendered as a continuous shader-driven surface; TerrainPalette supplies theme-aware colors through `set_theme_colors()` and `get_color()`.

### Golfer Simulation
- **Golfer** (`scripts/entities/golfer.gd`, ~61KB — most complex file): Skills (driving/accuracy/putting/recovery 0.0-1.0), personality (aggression/patience), 5 clubs (DRIVER/FAIRWAY_WOOD/IRON/WEDGE/PUTTER) with range/accuracy data. Shot calculation, target evaluation, tree collision, hazard avoidance. Group play (1-4 per group, "away" rule, double-par pickup). Explicit needs system (energy/comfort/hunger/thirst/pace) via `GolferNeeds` class.
- **GolferNeeds** (`scripts/systems/golfer_needs.gd`): Tracks 5 needs (energy, comfort, hunger, thirst, pace) that decay per-hole and while waiting. Buildings restore needs (bench→energy, restroom→comfort, snack bar/restaurant→hunger and some thirst, clubhouse→all). Low needs trigger thought bubbles; critical needs apply mood penalties. Tier-modified decay rates. See [golfer-needs docs](docs/algorithms/golfer-needs.md).
- **Staff & Weeds** (`scripts/managers/staff_manager.gd`, `scripts/managers/weed_manager.gd`, `scripts/entities/staff_member.gd`): Four job types, each with a standard and premium hire. Staff walk a designated grid circle and work at what they find — groundskeepers pull weeds (which set daily course condition), greeters cheer mood, marshals restore pace, vendors quench thirst. See [staff docs](docs/algorithms/staff-and-weeds.md).
- **ShotAI** (`scripts/systems/shot_ai.gd`): Structured decision pipeline for club selection and target finding. Multi-shot planning, wind compensation, recovery mode, Monte Carlo risk analysis. See [shot-ai docs](docs/algorithms/shot-ai-target-finding.md).
- **GolferManager**: Spawns groups based on green fee, max 8 concurrent golfers, spawn rate modified by course rating and weather. 4 tiers: BEGINNER/CASUAL/SERIOUS/PRO. Guests arrive through the clubhouse: a new group appears at its door and walks to the first tee before the turn system can pick them, and a finished group walks back to the door before it is taken off the course (state `LEAVING` — see [clubhouse docs](docs/algorithms/clubhouse.md)). See [golfer-spawning docs](docs/algorithms/golfer-spawning.md).
- **Group turn order** (`golfer_manager.gd:_update_group`): one shot at a time per group — honor off the tee, the away rule through the green. The group waits for the shot in progress to come to rest and for the group ahead to clear the landing cone, but **not** for its own members to finish walking: partners carry on walking to their ball while the next golfer away plays, and only hold the turn up while they stand in the line of that shot (landing cone for a full swing, the whole route for a chip or putt). See [group-turn-order docs](docs/algorithms/group-turn-order.md).
- **Ball**: Parabolic flight animation, terrain-based rolling distances, wind visual offset. Signals: `ball_landed`, `ball_state_changed`. See [ball-physics docs](docs/algorithms/ball-physics.md).

#### Shot Accuracy — Angular Dispersion Model
Shot error uses an **angular dispersion** model rather than absolute tile offsets. The shot direction is rotated by a miss angle sampled from a **gaussian (bell curve) distribution**, so most shots land near the target line with occasional big hooks/slices in the tails. Full details: [shot-accuracy docs](docs/algorithms/shot-accuracy.md). Key properties:

- **`miss_tendency`** (per-golfer, -1.0 to +1.0): Persistent hook/slice bias. Negative = hook, positive = slice. Amplitude set by tier (beginners: 0.4–0.8, pros: 0.0–0.15). Generated in `GolferTier.generate_skills()`.
- **Angular spread**: `max_spread_deg = (1.0 - total_accuracy) * 12.0`, with `spread_std_dev = max_spread / 2.5`. ~95% of shots land within `max_spread_deg` of target line.
- **Tendency bias**: `miss_tendency * (1.0 - total_accuracy) * 6.0` degrees added to every shot — lower-skill golfers can't compensate for their natural shot shape.
- **Shanks**: Rare catastrophic miss (35–55° off-line, 30–60% distance). Probability: `(1.0 - total_accuracy) * 4%`. Only on full swings (not putts/wedges). Direction follows `miss_tendency` sign.
- **Distance loss**: Topped/fat shots use gaussian distribution: `abs(gaussian) * (1.0 - accuracy) * 12%` max distance loss. Most shots near full distance.
- **Gaussian helper** (`_gaussian_random()`): Central Limit Theorem approximation using sum of 4 `randf()` calls. Mean ~0, std dev ~1, range ~±3.5.
- **Accuracy factors**: `total_accuracy = club_accuracy_modifier * skill_accuracy * lie_modifier`, with floors for wedges (0.80–0.96) and putts (skill-scaled). Club modifiers: Driver 0.70, FW 0.78, Iron 0.85, Wedge 0.95, Putter 0.98.

### Economy
- Green fee configurable $10-$200. Bankruptcy threshold at -$1000. See [economy docs](docs/algorithms/economy.md).
- Buildings: 8 types (Clubhouse, Pro Shop, Restaurant, Snack Bar, Driving Range, Cart Shed, Restroom, Bench). Proximity-based revenue. The clubhouse is the one `required: true` building: every course starts with one (a save without one heals on load), it can never be demolished, and it is relocated from its panel with Move Clubhouse. 3 upgrade tiers. See [clubhouse docs](docs/algorithms/clubhouse.md).
- Building architecture (`scripts/entities/course_architecture.gd`): every facility is drawn as an isometric solid on its own footprint — authored in grid space (tiles across, tiles down, pixels up) and projected through the terrain's own 2:1 axes, so its walls and roof follow the diamonds of the tiles it occupies and turn with the view (`Building` hands the architecture the grid's view orientation). The same `draw_building()` renders the placed building, the placement ghost and the Buildings-tab tile. Buildings are procedural only; the pixel-art building sprites were retired. See [isometric-buildings docs](docs/algorithms/isometric-buildings.md).
- CourseRatingSystem: 4-star rating from Condition (30%), Design (20%), Value (30%), Pace (20%). See [course-rating docs](docs/algorithms/course-rating.md).
- Reputation: 0-100, daily decay by star level, per-golfer mood-based gains. See [reputation docs](docs/algorithms/reputation.md).

### Weather & Time
- **WindSystem**: Per-day direction walk/speed (0-30 mph), rare daily reshuffles. Club-specific sensitivity (Driver 1.0x, Putter 0.0x). See [wind docs](docs/algorithms/wind-system.md).
- **WeatherSystem**: 6 types (SUNNY → HEAVY_RAIN). State machine with multi-day spells. See [weather docs](docs/algorithms/weather-system.md).
- **GameCalendar / tempo**: Real Gregorian calendar starting Sat 1 Jan 2000; day = 3.5 s at NORMAL, course never closes (no day/night cycle); YearSummary panel at year end; WeatherTintSystem tints by weather only. See [calendar docs](docs/algorithms/game-calendar.md).
- **TournamentSystem**: 4 tiers (Local/Regional/National/Championship) with escalating requirements. See [tournament docs](docs/algorithms/tournament-system.md).

### Course Themes
- **CourseTheme** (`scripts/systems/course_theme.gd`): Static class with 10 theme types (PARKLAND, DESERT, LINKS, MOUNTAIN, CITY, RESORT, HEATHLAND, WOODLAND, TROPICAL, MARSHLAND). Each theme provides:
  - `get_terrain_colors()` → per-theme color palette for all terrain types
  - `get_gameplay_modifiers()` → wind_base_strength, distance_modifier, maintenance_cost_multiplier, green_fee_baseline
  - `get_accent_color()`, `get_description()` → UI display helpers
- **Theme selection**: A theme belongs to the **location** the player buys on the World Map; `StartNewGameScreen` collects company name, difficulty, starting money, generated holes and the Weather/Wind/Seasons features, and the World Map's first course inherits that location's theme. `MainMenu` no longer offers theme cards — it links straight to the World Map for Quick Start, and to the setup screen for Start New Game.
- **Theme application flow**:
  1. `GameManager.new_game()` sets `current_theme` and updates `TerrainPalette` colors
  2. `EventBus.theme_changed` is emitted
  3. `CourseSurface` and theme-aware UI listeners refresh their palettes from the signal
- **Save/load**: Theme stored as string in save data, restored via `CourseTheme.from_string()`. On load, theme colors re-applied and `theme_changed` emitted.
- **Theme-aware components**: TerrainPalette, WaterOverlay, GrassOverlay, terrain shader parameters.

### World Map & Locations
- **WorldLocations** (`scripts/systems/world_locations.gd`): static catalog of **27 destinations** (Monterey, San Diego, Rocky Mountains, Las Vegas, Phoenix, Hawaii, Oahu, Nova Scotia, Northeast, Carolina, Florida, Chicago, New York, Ireland, Scotland, Wales, South England, Spain, Portugal, Jamaica, Bahamas, Japan, Dubai, South Africa, Australia, New Zealand, Pacific Northwest). Each carries a `CourseTheme` theme, a globe position (`lat`/`lon`), a size and a prestige factor. Sizes are SMALL 9 / MEDIUM 12 / LARGE 16 / CHAMPIONSHIP 20 parcels with base prices $15K/$24K/$36K/$52K; `compute_price(id, unlocked)` = (base + unlocked × `LAND_VALUE_PER_PARCEL` $2,200) × theme multiplier × prestige, rounded to $100.
- **Land blocks**: a location's land is a parcel block on the existing 6×6 `LandManager` grid that always contains the central 2×2 cluster and, for an 18-hole first course, the 3×3 block covering parcels (1,1)..(3,3). `layout_order(size, rng, required)` orders the block so `_pick_unlocked()`'s roll (how much land comes pre-cleared, and therefore the price) can never drop a parcel the biggest generated course needs. `WorldMap.get_location_parcels()` uses the same helper, so switching to a site always lays down a buildable block.
- **WorldMap** (`scripts/autoload/world_map_state.gd`): `new_world(options, seed)`, `reset_world()` (re-rolls every location's unlocked land and price), `buy_location(id)`, `is_owned`, `can_afford`, `get_price`, `apply_location_land`, `set_active_location`, `take_snapshot`/`get_snapshot`, `serialize`/`deserialize`. Feature flags live here too (`FEATURE_WEATHER` / `FEATURE_WIND` / `FEATURE_SEASONS`); off means sunny weather, calm wind and a neutral year-round season, and the HUD reads "Off" / "Year-round".
- **GlobeMap** (`scripts/ui/globe_map.gd`): procedural orthographic globe, drawn in two layers so view changes never pay for the continents. **Planet**: hand-tuned land polygons of `[lon, lat]` constants (never `PackedVector2Array()` straight from the raw arrays — build `Vector2(float(lon), float(lat))` per point) are rasterised once into a 2048×1024 equirectangular coverage mask (`build_land_mask()`, scanline fill + analytic span ends, ~15 ms, texture cached for the whole run) which `shaders/globe_planet.gdshader` turns back into a shaded sphere — sea depth and coastal shelf, 3D value-noise relief and clouds (sampled on the globe's own normal, so nothing swims or streaks at the poles), an arid band, polar ice, a camera-relative sun with a day/night terminator and a specular glint, 30° graticule and an atmosphere halo. The sphere stays a pure function of `(view_size, center_lon, center_lat, radius_scale)` — the script never bakes the camera into the mask — so the sun, cloud and terminator detail could be animated later just by changing uniforms. **Markers**: a separate `Control` layer holding the pins and labels, repainted on hover/selection/list refresh while the planet is left alone (`_redraw_markers()` vs `_redraw_view()`); `view_sync_count()` exposes that split for tests. `LandStyle.DOTS` keeps the old land-dot drawing (no shader) for callers that want it. Public API: `set_locations`, `set_selected`, `look_at_location` (eased over `CENTER_DURATION`, shortest way round, with drag/flick inertia in `_process`), `set_view_state`/`get_view_state`, `set_land_style`, `location_clicked(id)`, static `project_point(lon, lat, center_lon, center_lat)`, `is_land(lon, lat)`, `build_land_points()`, `build_land_mask()`, `mask_uv(lon, lat)`.
- **WorldMapScreen** (`scripts/ui/world_map_screen.gd`): globe beside the location list (globe left / list right), one row per location showing **Name / Theme / Size / Cost** with Buy or Play, a **Reset World** button, and `play_location_requested(id)` / `back_requested` signals. `refresh()` rebuilds the rows from `WorldMap`. Layout rules that matter: the globe only *stacks* above the list when the window is compact **and** at least `STACKED_MIN_HEIGHT` (660px) tall — a squat window (landscape phone, small browser window) keeps them side by side, otherwise the list is pushed off the bottom of the screen; and the list panel always keeps `SIZE_EXPAND_FILL` with a `custom_minimum_size` on its ScrollContainer, because with a shrink flag the panel collapses to its bare minimum and the ScrollContainer clips every row — the Buy/Play buttons vanish while the panel still looks "on screen". Compact windows use shorter rows (`COMPACT_ROW_HEIGHT`) so at least four rows stay visible.
- **StartNewGameScreen** (`scripts/ui/start_new_game_screen.gd`): company name, difficulty, starting money (`MONEY_OPTIONS` = 100000/150000/200000/-1 Unlimited), generated holes (`HOLE_OPTIONS` = 0/3/6/9/18) and the three feature toggles; emits `next_requested(options)` (Choose Location) and `back_requested` (Back or Esc). `get_options()` returns `{company_name (random when blank), difficulty, starting_money, generated_holes, features}`; defaults are Normal / $100,000 / 0 holes / all features on. Tests drive it through `_company_input` (LineEdit), `_feature_boxes[key]` (toggle Buttons — set `button_pressed`), `_select_difficulty/_money/_holes()` and `_on_next_pressed()`, so keep those names. Choices live in plain fields (`_difficulty`, `_money`, `_holes`, `_features`, `_company_name`) and survive every rebuild. Each option is a "choice card": a toggle Button (empty text, `accessibility_name`, `meta "value"`, one ButtonGroup per section) under a content layer with mouse input ignored; the course plan is `CoursePlanPreview`, drawn from `GeneratedCourse.layout_for(n)` — the same table the generator paints from. Layout details under "Responsive Layout & Touch".
- **First course / site entry**: `main._on_world_map_play_location(id)` restores that location's snapshot if one exists, otherwise `_start_new_course_at_location()` calls `GameManager.new_game("<Location> Golf Club", location theme, WorldMap.difficulty, {company_name, starting_money, unlimited, generated_holes, features})` and `GeneratedCourse.generate(n, …)` builds the requested holes (18 holes = par 72, front nine `LAYOUT_9`, back nine `LAYOUT_18_BACK`, starter amenity cluster from `AMENITY_SPOTS`; `layout_for(n)` exposes the hole table to the setup screen's plan preview). `Switch` keeps company money/reputation/calendar and swaps the site snapshot.
- **Legacy entry points**: `_on_main_menu_new_game(name, theme, difficulty, options)` and `_on_main_menu_quick_start(name, theme)` still start a playable course directly through `WorldMap.ensure_legacy_world(theme)` for older scripts and tests.

### Holes
- **HoleCreationTool**: opens a hole from the two tiles the player painted — one unused Tee Box and one unused **Green With Hole** — via **H** or the Open Hole tile on the Course Terrain tab, which is nestled into the notch between those two tiles (`scripts/ui/components/open_hole_notch_button.gd`, placed with `TileHoneycomb.set_notch_child`). See [hole-creation docs](docs/algorithms/hole-creation.md).
- **HoleLayout** (`scripts/tools/hole_layout.gd`): single source of truth for the rules. Tee Box always paints 1x1 and is blocked while an unused tee box waits. The Green tool paints a 1x1 **Green With Hole** (cup cut into the tile) while no cup is waiting, and an ordinary **Green Without Hole** at the normal brush size once one is. `open_hole_request()` reports whether a pair is ready and why not.
- **TerrainGrid cup tiles**: `_cup_tiles` marks greens carrying a cup; dropped when the tile stops being green, restored by undo/redo, saved as `cup_tiles`. `_tee_box_tiles` indexes tee tiles so the placement rule is a lookup.
- **CupOverlay**: renders the cup and a gold waiting pin on every Green With Hole that is not part of a hole yet.
- **Potential hole path**: while a tee box waits and the Green tool will cut the cup, `PlacementPreview` draws the hole the hovered tile would make: a dashed route with landing zones, the cup, and a `Hole N · Par P · Y yds` plaque. It turns red, with the reason, when the pair couldn't open. `HoleLayout.potential_hole()` decides when it shows and what it says. `HolePathPlanner` plans the route with the same `ShotPathCalculator` the open hole uses, on a `WorkerThreadPool` task against `TerrainGrid.create_analysis_copy()`, and caches it until `terrain_revision` changes.
- Auto-par from yardage: Par 3 <250y, Par 4 250-470y, Par 5 >470y.
- **DifficultyCalculator**: Per-hole rating (1-10) from length, hazards, slope, obstacles.
- **StrokeIndexCalculator**: Derives handicap allocation (1=hardest) from difficulty ratings. Front/back nine interleaving for 10+ holes. See [stroke-index docs](docs/algorithms/stroke-index.md).
- **CourseScorecardPanel**: Full course scorecard (hotkey `K`) showing all holes with par, yardage, stroke index, average scores, and course records. Adaptive layout for ≤9 vs 10+ holes.

### Tools
- **ElevationTool**: Three selector tools replace the old Rolling Hill / Hollow / Raise / Lower buttons — **Vertex** (one vertex ±1), **Flat Square** (raise only the brush's lowest vertices one level, or lower only its highest ones — once even, the whole brush steps together) and **Gradual Square** (move the middle vertex / middle 2×2, clamp nearby vertices to a 1-per-vertex slope). Right click raises, left click lowers. The Square tools share one Elevation Brush Size/Shape, separate from the terrain brush, and both controls ride in the notch between the Flat Square and Gradual Square tiles on the Elevation tab (the size stepper in the V above the point where those tiles meet, the shape toggle in the V below it) as half-size selector diamonds, the same way Open Hole is drawn on the Course Terrain tab; they stay usable even when neither Square tool is selected; sizes count **tiles**, so an S×S brush covers S² tiles and moves their (S+1)² corner vertices (1×1 = 1 tile = 4 vertices, 3×3 = 9 tiles = 16 vertices; the round shape clips corner tiles: 3×3 = 5 tiles = 12 vertices). See [elevation-tools docs](docs/algorithms/elevation-tools.md).
- **UndoManager**: 50-action stack with cost refunds.
- **IsometricCamera**: WASD pan, mouse wheel zoom, plus touch-gesture entry points `pan_screen_offset()` and `zoom_by_factor()` used by TouchInput. All zoom APIs (`set/get_zoom_level`, min/max clamps 0.5–2.0) work in **design units**; the rendered `zoom` additionally carries the responsive `_world_scale` factor set by `apply_world_scale()` (driven by the Screen adapter). Code that converts screen pixels to world units divides by the raw rendered `zoom`. View rotation lives on TerrainGrid, not the camera: **Q** / **Shift+Q** rotate the course counter-clockwise / clockwise, **I** toggles isometric ↔ top-down. Rotating re-projects terrain, overlays, entities and picking together, and preserves the grid point under the camera.

## Conventions

- **Class naming**: PascalCase for entities (`Golfer`, `Ball`) and systems (`WindSystem`, `CourseRatingSystem`). Inner data classes inside GameManager (`CourseData`, `HoleData`, `DailyStatistics`).
- **Enums**: Heavily used — `State`, `Club`, `TriggerType`, `Tier`, `WeatherType`, `Type` (terrain), etc.
- **Signals**: Past tense for completed events, present tense for state changes. Request/response pairs (`save_requested` / `save_completed`).
- **Safe access**: `.get("key", fallback)` for dictionary access. Null checks before operations. Signal connection safety checks.
- **Export vars**: `@export` for tunable gameplay constants (max_concurrent_golfers, spawn cooldowns, grid dimensions).
- **Performance**: Transaction history capped at 1000 entries. Object pooling for balls. Weather transitions smooth over time.

### Responsive Layout & Touch

The game is playable on desktop, tablet, phone and the web build. Rendering is **native window-pixel** (`window/stretch/mode="disabled"`): UI lays out in real pixels on every platform and the 1600x1000 design resolution is only a reference for scaling math.

- **Screen** (`scripts/autoload/screen_manager.gd`, autoload): turns the live window size into layout decisions. `world_scale = max(min(w/1600, h/1000), min(1, 900/w))` — large windows see the reference course area per inch; narrow windows (phones/tablets) keep 1:1 pixel scale so tiles stay tappable. `is_compact()` (w<900 or h<640) drives compact HUD variants; `available_panel_rect()` keeps popups clear of the bottom bar. Emits `changed` on resize/rotation; main.gd re-runs `_apply_responsive_layout()` from it.
- **Compact HUD** (applied via each component's `apply_screen()`): status column 210→150px and auto-collapsed, minimap 180→120px (its corner dock offsets are recomputed from its live size), pause menu uses tighter margins.
- **Title screen** (`scripts/ui/main_menu.gd`): four arrangements chosen by the window (`layout_mode_for()` - WIDE ≥1120x620, TABLET ≥700x620, LANDSCAPE for wide-but-short windows, PHONE). Every arrangement is built from the same cards (`_make_card`/`_make_tile`): actions are hero cards with a caption line, Continue carries the newest save, and the utilities (Load Game / Golfer Skins / Settings / Quit) stay together. Layout is container-driven inside a mode, so a live resize only rebuilds when the arrangement changes (or by >12%, `REPROPORTION_STEP`). The scenery is `MenuBackdrop` (sky, hills, fairway, green, flag, clouds - drawn in code, `green_anchor` moves the hole per arrangement) with the `MenuFlagMark` wordmark glyph beside the title. `tests/unit/test_main_menu_layout.gd` checks the breakpoints; `tests/harness/main_menu_layout_harness.tscn` drives the real screen through eight window sizes (seven actions at every one). The palette and card recipe (`CARD_BG*`, accents, `_paint_card`) are aliases of `MenuStyle` (`scripts/ui/components/menu_style.gd`), shared with the Start New Game screen.
- **Golfer Skins** (`scripts/systems/golfer_skin.gd`, `golfer_skin_layer.gd`, `golfer_skin_library.gd`, autoload `scripts/autoload/golfer_skins.gd`): what every golfer is drawn with. A skin is a sprite set (`assets/sprites/golfer/<set>/animations`, 8 directions x idle/walk/swing, diagonals falling back to the nearest cardinal) plus one **Re-color Layer** per sprite: a grid where every pixel belongs to one **Re-color Group** ("Shirt", "Pants", "Cap", "Hair", "Skin", or any group the player makes) or to no group at all. Grouped pixels are drawn in the group's colour with the artwork's own shading - the group's `shade` is the brightest grouped pixel of that sprite, so `pixel / shade * colour` keeps the folds and highlights - and ungrouped pixels are left exactly as the art ships. Groups are **per skin**: they can be created, renamed, re-coloured and deleted, and deleting one frees its pixels (a new group never inherits them, because group ids are never reused). **The skin owns the colours**: `GolferSkin` carries its groups' colours, `GolferSkins.frames_for_golfer(golfer)` draws `library.recolored_frames(skin)` of the skin the golfer wears, and `golfer.refresh_skin_sprites()` takes no profile - there is no per-golfer colour override left. `PlayerGolferProfile.COLORS` stays the polygon golfer's palette and the profile's record of the owner's choices: `GolferSkin.profile_key_for_group(name)` maps a group called Shirt/Pants/Cap/Hair/Skin onto its `appearance` field (`""` for a group of the player's own) and `GolferSkin.profile_color(profile, name)` reads it back, which is how the Edit Player page keeps the profile in step while the player re-colours a group.
  - **Files**: everything is editable text. A skin is a folder - `skin.txt` (a `golfer-skin 1` manifest: id, name, sprite set, size, the tiers that wear it and one `group <id> <symbol> <hex> <shade> <name>` line each) and `layers/<animation>/<direction>/frame_NNN.layer.txt` (a `golfer-skin-layer 2` header, an optional `size W H`, a `cells` line and then one character per pixel with `.` for "untouched", all preceded by a legend comment naming each group and a symbol; `#` lines are comments, and a file the parser cannot make sense of reports what it skipped instead of failing). A layer whose sprite the player has painted continues with an `art` line and one row of six-character pixel tokens per sprite row - `------` for a transparent pixel, `RRGGBB` otherwise - which is how the sprite's own pixels are stored (`GolferSkinLayer.has_art`/`begin_art`/`art_pixel`/`set_art_pixel`); from then on that layer *is* the sprite, and `GolferSkinLayer.recolor`/`source_maxima` read it instead of the PNG. The library reads them with `FileAccess`, so they can be edited by hand.
  - **Where they live**: skins shipped with the game are read from `res://data/golfer_skins/<id>/` (regenerate with `tools/generate_golfer_skin_layers.gd`) and the player's own from `user://golfer_skins/<id>/`, which shadows a shipped skin of the same id (`fallback_dir` remembers the original so Revert can throw the copy away). Only `beginner` and `casual` art ships, so Serious and Pro visitors wear the Casual skin unless the player dresses their tier in one of their own; a golfer with no skin at all keeps the polygon renderer, as it always did.
- **Edit Golfer Skins screen** (`scripts/ui/edit_golfer_skins_screen.gd`, `scripts/ui/components/golfer_skin_layer_canvas.gd`): the studio the title screen's Golfer Skins action opens. Three arrangements (`layout_mode_for()` - WIDE ≥1080x560, TABLET ≥760x560, PHONE otherwise, where the two lists drop under the studio and the header, studio controls and skin actions fold onto two lines). The canvas blows one animation sprite up to whole screen pixels (checkerboard behind it, grid, group washes, and the brush footprint drawn under the pointer; `cell_at()` is pure geometry so painting is testable without a mouse). Everything that changes is written through it: `set_artwork(raw, preview)` shows the sprite as the skin holds it (painted pixels included) and how the golfer is drawn with it, and the Re-coloured switch previews the latter. **Edit** switches the studio between **Pixels** - the sprite's own artwork: a `ColorPickerButton` and the brush size picker (`BrushSizePicker`, 1/3/5/7) paint pixels with `_paint_art`, right-click erases them (a transparent colour), alt-click is an eyedropper (`_pick_pixel_color`), and a painted pixel leaves whatever group owned it, because it is now the artwork's own colour - and **Groups** - the Re-color Groups: the same brush (`GolferSkinLayer.brush_cells`, a disc centred on the click: 1 pixel, a 2x2 block, a plus, then the classic 21-pixel disc) gives the pixels it covers to the selected group, Fill takes the whole run instead, right-click frees them, and the rows edit each group's Name, Colour and Delete. The mode switch sits above both and the canvas stays up in both; in Groups mode it drops the re-colour wash and a click selects the group under the pixel (`_on_cell_picked`), so the player can read the sprite off the groups. After an artwork edit the group's `shade` is re-read from the painted sprite (`GolferSkin.refresh_shades_from(..., true)`), so a colour the player picked is drawn exactly. Both Colour buttons are `ColorPickerButton`s (Godot's `ColorPicker` has no `popup()`). There is **no Sprite Set picker**: a skin names the artwork it was painted over (`sprite_id`, fixed when the skin is made). The studio edits a copy of the skin in memory: name, tiers, groups (create/rename/re-colour/delete) and every layer. **Save Skins** writes the lot as text (copying a shipped skin into `user://` the first time), **Wear This** dresses the player's own golfer (`GolferSkins.set_player_skin`), Duplicate copies a skin, Revert drops a player copy, Delete removes one of the player's own. Destructive actions ask the `ConfirmDialog` first (`confirm_callback` in tests). The header - Back and Save Skins included - is the first row of a `VBoxContainer` page column, never laid out in the same rect as the studio. `tests/unit/test_golfer_skin_editor.gd` covers the canvas geometry and the studio; `tests/harness/edit_golfer_skins_harness.tscn` drives the real screen at desktop/tablet/phone sizes, hit-tests Back/Save/the mode switch/the Colour picker the way a click would, works the group editor and paints, saves and goes back to the menu.
- **Golfer Skin controls on the Edit Player tab** (`PlayerRoundManager._build_skin_controls`, `scripts/managers/player_round_manager.gd`): while a round is running the tabs are rebuilt and locked, but the Edit Player page starts with a scaled animated golfer preview, keeps Player Name and the Golfer Skin picker together in the next column, then gives each Re-color Group of the worn skin a tall named color selector; the picker and group selectors are tagged with meta `editable_while_playing` so the lock loop steps over them. Choosing a skin calls `GolferSkins.set_player_skin`, re-colouring a group runs `library.ensure_editable` + `set_group_color` + `save_skin`, mirrors the colour into the profile field the group names (so the tab's own profile rows stay true) and emits `skins_changed`, which re-dresses the golfers on the course mid-round. The rows of `PlayerGolferProfile.COLORS` no group of the worn skin names stay as ordinary profile colours (`_standalone_profile_colors`). `tests/unit/test_player_round.gd` covers switching skin, re-colouring a group and the lock.
- **Start New Game screen** (`scripts/ui/start_new_game_screen.gd`): same backdrop and cards as the title screen, four arrangements of its own (`layout_mode_for()` — WIDE needs ≥1000x640 *and* landscape, so a 1024x768 tablet gets two panels; TABLET ≥700x760; LANDSCAPE wider-than-tall ≥600; else PHONE). WIDE: option sheet (difficulty/money/feature cards, hole segments) beside a "your company" rail with the live course plan, a summary and the gold Choose Location button. TABLET: one centred column, plan beside the hole picker, Choose Location pinned in a footer with a one-line summary. LANDSCAPE: two compact panels (segmented pickers, feature chips) with Choose Location always on screen; from 540px tall it adds the plan and captioned money cards. PHONE: one scrolling column, 2x2 money cards, plan beside its hint, pinned Choose Location. Sizes come from one scale `u` per build (`_measure`). Every wrapped label reserves the lines its longest possible text needs at its measured width (`_reserve_lines` → `MenuStyle.wrapped_lines`, which matches Label's word wrap), so the content height is known before layout: WIDE then rebuilds at the scale that fills `WIDE_FILL` (86%) of the height — capped by width — and LANDSCAPE shrinks until it fits (`_fit_to_window`); a WIDE window too short even at the smallest scale drops the difficulty descriptions (`Metrics.dense`). Breakpoint changes and >12% resizes rebuild at once, smaller ones after `SETTLE_DELAY` (the line budgets belong to the width they were measured at). `tests/unit/test_start_new_game_layout.gd` covers breakpoints, option copy, the course plan and the wrap estimate; `tests/harness/start_new_game_layout_harness.tscn` drives the real screen through 13 window sizes and plays it with real clicks.
- **CenteredPanel** (`scripts/ui/centered_panel.gd`): `show_centered()` clamps the panel to `Screen.available_panel_rect()` (never covers the bottom bar, never spills off a phone) and lazily wraps overflowing single-child content in a ScrollContainer so nothing is unreachable.
- **TouchInput** (`scripts/autoload/touch_input.gd`, autoload): the only touch path (`emulate_mouse_from_touch` is off). Tap → synthetic LMB click; one-finger drag → camera pan, or terrain painting while a tool is active (synthetic held LMB); two-finger → midpoint pan + pinch zoom anchored under the fingers; two-finger tap → synthetic RMB (cancel). Main menu backdrop drags don't pan the camera.
- **Web** (`web/custom_shell.html`): full-viewport shell; `maximum-scale=1.0, user-scalable=no` keep pinch for the in-game camera instead of page zoom.

### UI Patterns

- **CenteredPanel base class** (`scripts/ui/centered_panel.gd`): Extend this for panels that need to be centered on screen. Provides `show_centered()` (shows offscreen, waits for layout, then clamps to the responsive available area and centers — see "Responsive Layout & Touch" above) and `toggle()` methods. Handles Godot's layout timing issues where `get_combined_minimum_size()` returns wrong values before first frame.

- **AcceptDialog with hotkey toggle**: For popup selection menus (trees, rocks, buildings) that open via hotkey, implement toggle behavior so pressing the same key closes the dialog:
  1. Store dialog reference as instance variable (e.g., `var _tree_dialog: AcceptDialog = null`)
  2. Keep dialog modal (default `exclusive = true`) so it captures keyboard input
  3. Connect to `window_input` signal to detect the hotkey and close:
     ```gdscript
     _tree_dialog.window_input.connect(_on_tree_dialog_input)

     func _on_tree_dialog_input(event: InputEvent) -> void:
         if event is InputEventKey and event.pressed and not event.echo:
             if event.keycode == KEY_T:
                 _on_tree_dialog_closed()
     ```
  4. Connect `canceled` and `confirmed` signals to cleanup function that frees dialog and sets reference to null
  5. In selection callbacks, also free dialog and set reference to null

## MCP Servers

- **Godot MCP** (`.mcp.json`): Editor integration for scene/node manipulation, running the game, screenshots, etc.
- **PixelLab MCP** (`.mcp.json`): AI pixel art generation for isometric tilesets, characters, animations, and wang tilesets. API key (`PIXELLAB_SECRET`) is set in `~/.bashrc`.

## Build & Export

- **4 export targets** in `export_presets.cfg`: Windows, macOS, Linux, Web
- The Golfer Skin layers under `data/golfer_skins/` are read with `FileAccess`, and `.txt` is not a resource type, so every preset carries `include_filter="data/golfer_skins/*"` in `export_presets.cfg` to get them into the PCK.
- **CI/CD**: `.github/workflows/export-game.yml` — Godot 4.6 headless export on version tags, creates GitHub Release, deploys web build to Cloudflare Pages.

## Testing

Unit tests use **GUT** (Godot Unit Test) framework. Tests are in `tests/unit/`.

**Run tests:**
```bash
make test          # Using Makefile
./test.sh          # Using shell script
```

**GDScript warnings:** Godot prints them only while a debugger is attached, so
neither the tests nor any other headless run show them — they surface in the
editor's debugger only. `make warnings` (or `./check-warnings.sh`) force-reloads
every project script with `-d` through `tools/warning_scan.gd` and fails on
anything Godot reports. CI runs it next to the unit tests. Prefer a real fix
(rename the shadowing variable, use the parameter) over `@warning_ignore`; use
`@warning_ignore("code")` or `@warning_ignore_start`/`@warning_ignore_restore`
only where the construct is deliberate.

`./test.sh` resolves Godot automatically (bundled `Godot_v4.6-stable_linux.x86_64.zip`, `$GODOT`, or PATH) and imports the project on first run.

**Headless integration harnesses** (real main scene, quick-start course):
```bash
godot --headless --path . res://tests/harness/walking_path_harness.tscn
godot --headless --path . res://tests/harness/bulldozer_harness.tscn   # Bulldozer remit: demolishes improvements/buildings, never course terrain
godot --headless --path . res://tests/harness/speed_controls_harness.tscn  # Speed controls: one fast-forward button for Fast (3x) and Ultra (8x)
godot --headless --path . res://tests/harness/ready_golf_harness.tscn  # Pace: one foursome, three holes each, reports the dead time a group spends waiting on a walking partner
godot --headless --path . res://tests/harness/responsive_layout_harness.tscn  # Responsive: phone/tablet/desktop window sizes drive the real main scene through the Screen/HUD/panel/touch adapters (includes the World Map screen)
godot --headless --path . res://tests/harness/main_menu_layout_harness.tscn  # Title screen: the four arrangements, seven actions on screen and tappable at phone/tablet/rotated/desktop sizes, no tagline, drawn backdrop
godot --headless --path . res://tests/harness/edit_golfer_skins_harness.tscn  # Edit Golfer Skins: opens from the menu, paints a pixel at desktop/tablet/phone sizes (canvas >= 3 screen pixels per sprite pixel, nothing wider than a 390px window), saves, dresses the owner's golfer and goes back
godot --headless --path . res://tests/harness/start_new_game_layout_harness.tscn  # Start New Game: four arrangements at 13 sizes (targets >=44px, on screen, no overlaps, no cut text, no scrolling in WIDE/LANDSCAPE), then clicks through every option, live resizes keep the picks, Esc and Choose Location
godot --headless --path . -s tests/integration/world_map_flow.gd  # World map: menu → setup → globe/list → buy → play → switch → quick start
godot --headless --path . -s tests/harness/globe_preview.gd  # Writes tmp_preview/equirect.png + mask.png (the shader's own mask) + ortho.png so the globe's coastlines can be eyeballed
godot --headless --path . -s tests/harness/planet_preview.gd  # CPU port of the planet shader (palette parsed from its uniforms) -> tmp_preview/planet_view*.png, for looking at the globe without a GPU
```

**Test coverage:** GameManager, SaveManager, CourseRatingSystem, CourseRecords, DailyStatistics, GolferTier, WorldMap/WorldLocations (pricing, parcel layout, land coverage for a full generated course), Golfer Skins (layer grids, group lifetime, the text files, the frames golfers are drawn with, the studio and its canvas), plus the responsive adapters (Screen math, IsometricCamera world scale/pan/zoom, TouchInput gestures, CenteredPanel clamping, compact HUD pieces).

**Override Godot path:** `make test GODOT=/path/to/godot` or `GODOT=/path/to/godot ./test.sh`

**User preference:** Run Godot tests manually via the editor (faster execution than CLI).

## Playtesting

When running the game for playtesting via the Godot MCP tools:
1. Use **Quick Start** (main menu → World Map → buy a location → Play) to start a company with the default settings; the setup screen's Generated Holes option controls whether the first course is bare or comes with 3/6/9/18 generated holes
2. Click **Start Day** then click **>>** twice to reach **>>> (ULTRA, 8x speed)** — a full game day completes in ~90 seconds of real time
3. Speed tiers: `>` = Normal (1x), `>>` = Fast (3x), `>>>` = Ultra (8x). Fast and Ultra share one button: pressing it swaps between the two tiers (`GameManager.next_fast_forward_speed`). Speed uses `Engine.time_scale` so all systems (golfer movement, ball flight, tweens) scale uniformly.
4. Playtest findings should be logged in `playtest_findings.md` at the project root

**Detailed MCP playtesting guide** (node paths, gotchas, navigation tips) is in the auto-memory file `playtesting.md`. Consult it before starting a visual playtest session.

## Development Notes

- **SoundManager** (`scripts/autoload/sound_manager.gd`): Procedural audio system using `AudioStreamGenerator`. Synthesized swing, impact, ambient (wind, birds, rain), and UI sounds. Event-driven via EventBus signals. Master/SFX/ambient volume controls with mute toggle.
- Golfers are NOT saved/loaded (respawn naturally to avoid complex mid-action state serialization).
- Save format is versioned (SAVE_VERSION = 5) for forward compatibility; version 5 adds the company `world_map` block and per-site snapshots.
- **Additional systems**: TutorialSystem (interactive onboarding), MilestoneSystem (trackable objectives), SeasonSystem (seasonal calendar), DifficultyPresets (Easy/Normal/Hard), ColorblindMode (accessibility), PauseMenu (Escape key), SettingsMenu, GeneratedCourse (the layouts the World Map first course uses), QuickStartCourse (pre-built demo course, still used by PrebuiltCourseGenerator and the legacy direct-start path).
