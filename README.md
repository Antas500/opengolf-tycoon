# OpenGolf Tycoon

An open source golf course builder and management game inspired by Sid Meier's SimGolf, built with Godot 4.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Godot](https://img.shields.io/badge/Godot-4.6+-blue.svg)
![Status](https://img.shields.io/badge/status-alpha-orange.svg)
![Version](https://img.shields.io/badge/version-0.1.0-green.svg)

## About

OpenGolf Tycoon is a spiritual successor to the classic SimGolf (2002). Design and build your own golf courses, manage your country club, attract golfers, and compete to create the ultimate golfing destination.

## Current Features

### Locations & the World Map

A company grows by buying golf course locations around the world — **27 destinations** from Monterey and San Diego to Scotland, Spain, Jamaica, Dubai, Japan and Australia — each with its own theme, land size, globe position and price. A location's land comes partly unlocked; the amount is rolled per world and raises the price, so **Reset World** gives a fresh set of deals. Every location is a separate site with its own terrain, buildings, staff and holes, while money, reputation, the calendar and milestones belong to the company, so players can switch between the courses they own without starting over.

### Course Themes

Choose from 10 distinct course environments, each with unique terrain colors, gameplay modifiers, and visual style:

- **Parkland** — Classic lush green grass, deciduous trees, balanced gameplay
- **Desert** — Sandy tan terrain, oasis-green fairways, cacti and rocky outcroppings
- **Links** — Coastal Scottish-style with golden-brown fescue, strong persistent wind (+20%)
- **Mountain** — Deep alpine greens, pine forests, +5% shot distance (thinner air)
- **City/Municipal** — Muted urban greens, lower maintenance costs
- **Resort** — Vibrant tropical colors, turquoise water, white sand bunkers, premium pricing
- **Heathland** — Sandy inland soil with heather, gorse, and scattered pines
- **Woodland** — Dense tree-lined fairways with dappled light
- **Tropical** — Lush palms, vibrant greens, warm tones
- **Marshland** — Wetland terrain with cattails, soft ground, and water features

Theme selection happens on the main menu before starting a new game. Themes affect terrain colors, water/grass overlay rendering, gameplay modifiers (wind strength, shot distance, maintenance costs, green fee baseline), and available vegetation types.

### Course Designer

- **Terrain painting** — 14 paintable course tiles: fairway, firm fairway, rough, deep rough, green, tee box, waste bunker, brush, bunker, pot bunker, water, stream, rocks, and out of bounds — plus paths, flower beds, trees and boulders
- **Elevation system** — Three selector tools (Vertex, Flat Square, Gradual Square) reshape the elevation field across levels 0 to 10 (flat ground starts at 5): right click raises the selected terrain, left click lowers it. The Square tools share one Elevation Brush size/shape, separate from the terrain brush, counted in tiles: a 1×1 brush is one tile (4 vertices), a 2×2 brush four tiles (9 vertices), a 3×3 brush nine tiles (16 vertices), and the round shape clips the corners (3×3 keeps 5 tiles / 12 vertices). Slope affects shots and ball roll; gradient hillshade visualization with contour lines
- **Hole creation** — 3-step flow (tee box → green → flag); auto-calculates par based on yardage; holes numbered and renameable
- **Tee aim arrows** — Every tee tile is painted with an arrow and a red tee marker either side of it, aimed at the hole's cup; doglegs get a curved arrow
- **Object placement** — Theme-specific vegetation (oaks, pines, palms, cacti, fescue, heather, and more), 3 rock sizes, decorative flower beds
- **Building placement** — 8 building types (Clubhouse, Pro Shop, Restaurant, Snack Bar, Driving Range, Cart Shed, Restroom, Bench) with proximity-based revenue/satisfaction effects and placement validation. Every building is drawn as an isometric solid that fills its own grid square and turns with the course view
- **Undo/redo** — 50-action stack covering terrain changes and entity placement, with cost refunds on undo
- **OB markers** — Automatic white-stake placement at out-of-bounds boundaries

### Golfer Simulation

- **AI golfers** — Skill-tiered (Beginner / Casual / Serious / Pro) with animated walking and swing cycles
- **Shot AI** — Structured decision pipeline with multi-shot planning, wind compensation, recovery mode, and Monte Carlo risk analysis
- **Shot physics** — Angular dispersion model with gaussian miss distribution, persistent hook/slice tendencies per golfer, rare shank events, and club-specific accuracy
- **Ball physics** — 5-state machine (AT_REST, IN_FLIGHT, ROLLING, IN_WATER, OUT_OF_BOUNDS) with parabolic arc trajectories and terrain-based rollout
- **Golfer needs** — Energy, comfort, hunger, and pace needs that decay over time; buildings restore specific needs; low needs trigger mood penalties and thought bubbles
- **Pathfinding** — Terrain-aware, prefers cart paths, avoids water/OB, deadlock-safe group spacing
- **Group play** — Groups of 1–4; turn order follows "away" rule; par-3 hold until preceding group clears; double-par pickup prevents infinite loops
- **Hazard rules** — Water penalty (1 stroke + lateral drop), OB (stroke + distance)
- **Personality traits** — Aggression (0.0–1.0) affects risk/reward club selection and target choice
- **Green reading** — Putts account for slope break with skill-based accuracy
- **Score tracking** — Per-hole scores, running total, displayed on course
- **Golfer skins** — Looks to meet on the course: hand-made pixel-art golfers (Weekend Beginner and Club Casual), each with idle, walk and swing animations in eight facings, a part layer that records what every pixel was drawn as, and every part re-colourable
- **Play the Course** — Play your own round alongside the management sim, in a group with AI pros, with persistent skills, shot shapes (fade/draw/backspin/punch) and an aim guide that draws the intended flight arc and the roll that follows it

### Economy & Management

- **Green fees** — Configurable ($10–$200); fee level affects group-size distribution (low fee → singles, high fee → foursomes)
- **Building revenue** — Proximity-based income per golfer (Pro Shop, Restaurant, Snack Bar, Clubhouse bonuses)
- **Clubhouse upgrades** — 3 tiers (Basic → Pro Shop → Full Service), each unlocking higher revenue and satisfaction bonuses
- **Terrain costs** — Placement and per-day maintenance costs vary by terrain type
- **Operating costs** — Base daily cost scales with hole count and staff
- **Staff management** — Hire and fire groundskeepers, marshals, cart operators, and pro shop staff from the Staff toolbar tab; monitor course condition, payroll, and staff effects
- **Budget tracking** — Real-time balance, deductions on placement, refunds on undo, daily cost settlement
- **Difficulty presets** — Easy, Normal, and Hard modes with different starting conditions

### Ratings & Satisfaction

- **Course rating** — 1–5 stars computed from four sub-ratings: Condition, Design, Value, and Pace
- **Golfer feedback** — 17 trigger types (hole-in-one, birdie, bogey, bunker, water, pricing, needs, and more); thought bubbles with sentiment-coded colors
- **Reputation** — Gains/losses daily based on aggregate golfer satisfaction
- **Milestones** — Trackable objectives (star ratings, tournament hosting, revenue goals, and more)
- **Course records** — Lowest round, hole-in-one counter, best score per hole; gold particle burst celebration

### Weather & Time

- **Day/night cycle** — Visual tinting from 6 AM to 8 PM course hours; golfers finish current hole and exit at closing
- **Weather system** — 6 states (sunny → heavy rain); modifies golfer spawn rates and accuracy; animated rain overlay with sky tinting
- **Wind system** — Per-day direction and speed (0–30 mph); affects all clubs except putters; AI compensates based on skill level; HUD compass indicator with color-coded speed
- **Seasons** — Seasonal calendar affecting weather patterns, golfer traffic, and maintenance costs

### Tournaments

- **4 tiers** — Local, Regional, National, Championship — each with minimum hole count, star rating, difficulty, and yardage requirements
- **Scheduling** — 3-day lead time, 7-day cooldown between events
- **Results** — Generated winner names and scores; prize money awarded; leaderboard display

### Audio

- **Procedural sound** — Synthesized swing, impact, and UI sounds generated at runtime (no audio files needed)
- **Ambient audio** — Wind, birdsong, and rain audio that responds to weather conditions
- **Volume controls** — Master, SFX, and ambient volume sliders with mute toggle

### UI & Controls

- **Isometric view** — 2:1 diamond terrain with SimGolf-style rotation: **Q** / **Shift+Q** rotate the course, **I** toggles isometric / top-down, plus W/A/S/D pan and mouse-wheel zoom
- **Main menu** — seven entries only: **Start New Game**, **Quick Start**, **Continue**, **Load Game**, **Customise Golfer Skins**, **Settings**, **Quit**. The screen is laid out by weight rather than listed: Start New Game and Quick Start are hero cards, Continue is a card showing the newest save's course, day and slot, and the four utilities sit together at the quiet end. Behind it, a golf hole is drawn in code (sky, hills, fairway, green, flag and drifting clouds) — no texture assets
- **Start New Game** — company name (or roll the die for a random one), difficulty (Easy/Normal/Hard, each card spelling out what it changes: upkeep, golfer numbers, building costs, reputation decay), starting money ($100K / $150K / $200K / Unlimited), generated holes for the first course (0/3/6/9/18, with the par for each) and the Weather / Wind / Seasons game features. A live plan of the course that will be generated redraws as you pick a hole count, a summary follows every choice, and **Choose Location** opens the World Map (Back or Esc returns to the title screen)
- **Quick Start** — jumps straight to the World Map with defaults (random company name, Normal, $100,000, no generated holes, all features on)
- **World Map** — a globe with a marker per destination, a list giving every location's name, theme, size and cost, Buy/Play actions, and **Reset World** to re-roll each location's unlocked land (and therefore its price); return from the pause menu at any time to buy more locations or swap the one you are playing
- **Pause menu** — Escape key opens pause overlay with Resume, Settings, Save, and Quit options
- **Camera while paused** — the game freezes but the camera stays controllable: pan with W/A/S/D or middle-mouse drag, zoom with the scroll wheel (also works from behind the pause and settings overlays)
- **Customise Golfer Skins** — Paint the pixels and pick the colours of every golfer skin, frame by frame and facing by facing, with an eraser, zoom, an eyedropper and a live preview; **New Skin** forks the selected skin into one of your own to name, paint, wear and delete, and **Revert** puts an edited skin back to the shipped art. Changes save as they are made
- **Settings menu** — Display, audio, and gameplay options
- **Tool palette** — Terrain tools, object placement, hole creation, elevation tools
- **Speed controls** — Pause / Play / Fast-forward; the single fast-forward button toggles between Fast (3x) and Ultra (8x), and Space pauses or resumes
- **Mini-map** — Course overview with terrain colors, hole markers, buildings, golfers; click to navigate (toggle with the map-icon button in the minimap's bottom-left corner, or Tab)
- **Inspect** — Toggle the **Inspect** button below **Menu**, then hover over a tile to see its Terrain, Improvements, and Buildings. Includes paths and multi-tile objects; does not modify the course. Toggle off, press Esc/right-click, or select another tool to exit.
- **Financial dashboard** — Click money display to open; shows daily and yesterday income/expense breakdown
- **Hole stats panel** — Per-hole averages, best scores, score distributions
- **Building info panel** — Stats, upgrade options, costs
- **End-of-day summary** — Daily revenue, costs, golfer feedback summary, day transition
- **Tournament panel** — Schedule tournaments, view requirements and results (toggle with T)
- **Milestones panel** — Track course objectives and achievements
- **Hotkey reference** — F1 opens keyboard shortcut panel
- **Save/load panel** — Named save slots with save/load UI
- **Colorblind mode** — Alternative color palette for accessibility
- **Touch controls** — On phones/tablets (and the web build): tap to click, one-finger drag to pan the course (or paint terrain while a tool is active), two-finger drag to pan + pinch to zoom, two-finger tap to cancel/close menus

### Save / Load

Saved state includes: the company world map (settings, owned locations, unlocked land, the active location and a snapshot per owned site), terrain tiles, elevation, entity positions, hole configurations, economy state (money, reputation, green fee), day/hour, wind, weather, seasons, course theme, and course records. Company-level state (money, reputation, calendar, milestones) is shared across every location; course-level state is kept per site. Auto-saves at day end (with indicator); manual save with named slots. Quit to Menu option available from pause menu.

### Platforms

Playable on **desktop (Windows/macOS/Linux), tablets, phones, and in the browser** (Web build, including the Cloudflare Pages deployment).

The title screen has four arrangements, picked from the window size: a **wide** split (title and hero cards left, a Continue rail right) on desktop, a **centred column** on tablets, a **side-by-side compact** layout for wide-but-short windows (rotated phone, squat browser window) so nothing has to be scrolled, and a **single scrollable column** on phones with every target at least 46 px tall.

The Start New Game screen does the same with its own four arrangements: on desktops and landscape tablets the options sit on a sheet of cards beside a "your company" rail with the course plan, a summary and the Choose Location button, scaled to fill the window without scrolling; portrait tablets get one centred column with the plan beside the hole picker and Choose Location pinned to the bottom; rotated phones get two compact panels that fit without scrolling; and phones get one scrolling column of thumb-sized pickers over a pinned Choose Location button.

The game renders at the window's native resolution and adapts to the screen: the course view keeps the reference physical size on large desktops while staying 1:1 (tiles never shrink) on phones and tablets; the HUD switches to a compact layout on narrow windows (narrower stats column, smaller minimap); popup panels clamp to the available space and scroll instead of spilling off small screens. Desktop behavior at 1600x1000 is unchanged from the original fixed-viewport layout.

---

## Getting Started

### Prerequisites

- [Godot Engine 4.6+](https://godotengine.org/download) (standard version, not .NET)

### Installation

No build steps or setup scripts required — all assets are procedurally generated at runtime.

1. Clone the repository:
   ```bash
   git clone https://github.com/sneeosh/simgolf-godot.git
   ```
2. Open Godot Engine
3. Click **Import** and navigate to `project.godot`
4. Click **Import & Edit**
5. Press **F5** to run

Godot will automatically import all assets on first load.

---

## Project Structure

```
simgolf-godot/
├── assets/
│   ├── sprites/            # Buildings, golfers, trees, rocks, and decorations
│   │                       #   golfer art: frame_NNN.png + frame_NNN.layer.bin beside it
│   └── themes/             # Shared UI theme resources
├── data/
│   ├── buildings.json      # Building types, costs, revenue, upgrade tiers
│   ├── terrain_types.json  # Terrain type definitions and properties
│   ├── golfer_traits.json  # Golfer archetypes, spawn weights, skill ranges
│   └── golfer_skins.json   # Skin catalogue: parts, palettes, tiers, frame layout
├── docs/
│   └── algorithms/         # Detailed algorithm documentation with tuning levers
├── scenes/
│   ├── main/main.tscn      # Primary game scene
│   └── entities/golfer.tscn
├── scripts/
│   ├── autoload/           # Singletons: GameManager, EventBus, WorldMap, SaveManager,
│   │                       #   FeedbackManager, SoundManager, ShadowSystem
│   ├── course/             # HoleVisualizer, DifficultyCalculator, EntityLayer
│   ├── effects/            # RainOverlay, HoleInOneCelebration, SandSprayEffect
│   ├── entities/           # Golfer, Ball, Building, Tree, Rock, Flag
│   ├── managers/           # GolferManager, BallManager, HoleManager, PlacementManager,
│   │                       #   BuildingRegistry, TournamentManager
│   ├── systems/            # WindSystem, WeatherSystem, DayNightSystem, CourseRatingSystem,
│   │                       #   CourseTheme, WorldLocations, GeneratedCourse, ShotAI, GolferNeeds,
│   │                       #   SeasonSystem, MilestoneSystem, TutorialSystem, and more
│   ├── terrain/            # TerrainGrid, TerrainTypes, TerrainPalette, overlays
│   ├── tools/              # HoleCreationTool, ElevationTool, UndoManager
│   ├── ui/                 # UI components: MainMenu, StartNewGameScreen, WorldMapScreen,
│   │                       #   GlobeMap, PauseMenu, SettingsMenu, MiniMap, FinancialPanel,
│   │                       #   MilestonesPanel, and more
│   └── utils/              # IsometricCamera
├── tests/
│   └── unit/               # GUT framework unit tests
└── project.godot
```

---

## Documentation

- **[Algorithm docs](docs/algorithms/)** — Detailed documentation for all simulation algorithms with plain-English explanations, formulas, and tuning levers. See the [algorithm index](docs/algorithms/README.md).
- **[Development milestones](DEVELOPMENT_MILESTONES.md)** — Full development history and roadmap
- **[Game critique](GAME_CRITIQUE.md)** — Honest critical analysis of the game's strengths and weaknesses
- **[Beta readiness analysis](BETA_READINESS.md)** — Gap analysis for reaching public beta
- **[Launch evaluation](LAUNCH_EVALUATION.md)** — Current state assessment and ratings
- **[Tycoon genre review](docs/tycoon-genre-review.md)** — Feature comparison against genre staples

---

## Planned / Not Yet Implemented

- **Animated tiles** — Waving flags, animated water
- **Bridges** — Path over water hazards
- **Simulated tournaments** — AI golfers playing real rounds instead of generated results
- **Spectator tools** — Follow a golfer with the camera, live scorecards, shot replays
- **Player-controlled golfer mode** — Play your own course as a golfer
- **Performance optimization** — Object pooling, occlusion for large courses
- **Career mode** — Progression, unlockables, achievements
- **More locations & prebuilt sites** — Additional destinations and turnkey courses
- **Course sharing** — Export/import course layouts
- **Seasonal visuals** — Spring/summer/fall/winter terrain appearance changes

---

## Testing

Unit tests use the [GUT](https://github.com/bitwes/Gut) (Godot Unit Test) framework. Tests are in `tests/unit/`.

```bash
make test          # Using Makefile
./test.sh          # Using shell script
```

`./test.sh` (and `make test`) resolve Godot automatically: they use `$GODOT` if set, a `godot` on `PATH`, or the bundled `Godot_v4.6-stable_linux.x86_64.zip` in the project root (extracted on first run, then imported). Subsequent runs skip that setup. Override with `GODOT=/path/to/godot ./test.sh`.

---

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Areas Needing Help

- **Art** — Isometric sprites for terrain, buildings, golfers; animated tiles
- **Audio** — Composed music tracks, improved sound design
- **Code** — Simulated tournaments, spectator camera, performance optimization
- **Documentation** — Wiki pages, gameplay guides

---

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgments

- Sid Meier and Firaxis for the original SimGolf
- The Godot Engine community

---

*This is a fan project and is not affiliated with Firaxis Games.*
