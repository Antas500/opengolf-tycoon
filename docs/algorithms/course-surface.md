# Continuous course surface

## Plain English

The terrain is drawn as one connected landscape, with diagonal mower passes,
fine putting turf, green collars, recessed sand, and gently moving water. Pixel
art entities retain their existing assets. The simulation still uses the same
64 × 32 world grid: this is a surface renderer, not an isometric coordinate or
physics migration. Camera controls, saved courses, hazards, and shot logic keep
their existing coordinates. Small visual edge blends do not redefine a ball's lie.

Desktop and web use the same shader. A 128 × 128 RGBA8 data texture costs 64 KiB;
each pixel stores a terrain ID in red, bunker depth in green, normalized
base elevation in blue, and in alpha whether the tile is a boulder's footprint.
Theme colors live in a separate palette with one texel per terrain ID
(`CourseSurface.PALETTE_KEYS`, currently 20 × 1); the shader reads its width
with `textureSize`, so appending a terrain type only needs a palette key.
Trees, and boulders standing on other ground, use native grass underneath;
painted Rocks tiles render as stony ground (see *Terrain expansion* below).
The former per-tile turf, water, bunker, and path overlays are not instantiated,
so their rectangular patterns cannot cover the continuous surface.

## Algorithm

`CourseSurface` listens to local tile changes and coalesces GPU uploads to one
per frame. Quiet terrain generation explicitly rebuilds through
`TerrainGrid.refresh_all_overlays()`. Terrain/depth deserialization and successful
load events rebuild the data; theme changes replace only the palette.

For each fragment, sample the four surrounding tile centers. Add their bilinear
weights by material ID to obtain coverage `c`. Each sample's final weight is
`w × c^5`, normalized by the total. This preserves clear material boundaries
while softening connected corners. A low frequency coordinate perturbation of
at most 0.08 tiles breaks repeated stair steps. Tile centers retain their IDs.
Out-of-map sampling clamps to the nearest map texel.

Noise and mower passes use world pixels, so moving/zooming the camera does not
move the pattern. Water animation uses GPU time and requires no per-water-tile
script updates. Bunker coverage controls the shaded lip; depth increases its
shadow. Greens blend into the theme's fringe color at their edges.

Foliage uses one shared vertex shader, phased by each tree's world position.
Movement falls off quadratically toward the base. Cacti and dead trees are still.
EntityLayer sits at Z=2, keeping its existing relative shadow layers (-2/-1)
above the ground and below the sprites. Elevation lighting remains independent;
contour markings appear only while the elevation tool is active. Continuous
light and smoothly gated ambient occlusion avoid rectangular bands from the
low-resolution heightmap.

Quick Start cleanup preserves the freshly painted terrain before removing a
tree/rock and reapplies it afterward. Removal previously restored native ground,
leaving holes in fairways and greens. Water is now included in cleanup.

## Tuning levers

| Setting | Location | Value | Effect |
| --- | --- | --- | --- |
| Coverage exponent | `course_surface.gdshader` | 5 | Higher gives sharper edges |
| Contour perturbation | Same | 0.16 (±0.08 tiles) | Breaks mechanical outlines |
| Mower pass frequency | Same | 0.048 | Higher makes narrower passes |
| Bunker lip depth | Same | 0.23 + 0.19 × depth | Distinguishes deep bunkers |
| Breeze amplitude | `foliage_breeze.gdshader` | 1.15 pixels | Subtle canopy motion |
| Terrain light/shadow | `elevation_shader_controller.gd` | 0.28 / 0.28 | Retains turf color on slopes |

Validation covers normal painting, deep bunkers, quiet batches, deserialization,
all ten theme palettes, unchanged serialization, and tree/rock cleanup. Native
Compatibility rendering also exercises shader compilation; a browser-specific
performance/device test remains separate.

## September 2026 readability pass

Material mixing is restricted to a narrow 0.028 coverage interval around the dominant terrain type. This retains rounded tile connections without a wide translucent transition. Fairways have closer, lower-contrast mowing stripes and darker edges; greens have stronger fringe separation. Sand uses a warm bowl with a darker lip, water has turquoise shallows and pale banks, and relief shading is reduced to preserve terrain colors. Flags use taller white poles and larger cloth; tee labels use larger outlined text on a dark backing.

September visitor-experience pass: fairway/tee boundaries now combine a lighter 14% collar with a narrow additional 8% cut line (coverage 0.50–0.53), replacing the broad 28% dark edge. This keeps the boundary legible without making level fairways look recessed.

## Terrain expansion: Firm Fairway, Pot Bunker, Stream, Deep Rough, Waste Bunker, Rocks, Brush

Seven paintable course tiles (IDs 14–19, plus the existing Rocks ID 13) have
looks of their own in `surface()`. Two of them are plain turf patterns:

- **Firm Fairway** reuses the fairway's mower passes, paler, with sun-dried
  straw patches (`noise(world * 0.03)`), so a firm landing zone reads as
  faster, drier turf inside a normal fairway.
- **Deep Rough** stretches noise along the screen-vertical grid axis
  (`u = x − y` fine, `v = x + y` coarse) to draw long standing blades, with
  darker clumps and pale seed-head dots.

The other five are **inset terrain** (`is_inset()`): features drawn over
whatever turf surrounds them, so a patch has a natural outline instead of a
square one.

- *Asymmetric boundaries.* `edge_between(self, other)` is 0 when `self` is turf
  (grass, fairways, roughs) and `other` is inset: the turf draws no boundary
  band, collar or cut line against it. The inset tile shows that turf near each
  open edge instead (`surface(neighbour, 1.0)`, weighted by
  `smoothstep(-0.5, 0, d)` from the edge), and native grass toward anything
  that isn't turf. `neighbour_surface()` mirrors this inside the boundary band,
  so both sides of every edge agree. A waste bunker's sand also runs under
  neighbouring rocks and brush (`carries()`).
- *Rocks and Brush* scatter stones or shrubs on cellular noise (`cells()`,
  2.9 / 3.1 cells per tile). Each feature is kept or dropped per cell: it must
  clear every open edge by its radius (`edge_room()` at the feature point), so
  no stone or shrub is ever cut by a tile edge. Features are dome-shaded from
  the upper left (`GROUND_LIGHT`) with a contact shadow cast away from the light;
  brush adds sparse blossoms.
- *Waste Bunker* is coarse sand with pebbles and wiregrass tufts; within about
  0.2 tiles of an open edge it breaks up raggedly into the surrounding turf.
- *Pot Bunker* and *Stream* use `link_distance()`: the distance to a skeleton
  joining the tile centre to each linked edge (same-type neighbours for pots,
  stream or pond neighbours for streams). A tile with one horizontal and one
  vertical link becomes a quarter arc about their shared corner, so stepped
  lines of tiles read as smooth curves. Runs meet with a smooth minimum
  (k = 0.12). Quadrants inside a 2×2 block fill solid (`corner_filled()`), and
  a lone tile is a round spot.
  - A pot is a turf lip, a stacked-turf wall, and a sand floor offset toward the
    viewer (grid +x +y). The offset exposes the far wall's face; the floor is
    shaded near the light-side wall.
  - A stream is a channel of half-width 0.25 ± 0.045 tiles with a muddy, pebbled
    margin. Soft crests drift downstream along the local run axis (`TIME`). Where
    it meets a pond the channel opens across the whole shared edge and blends
    into the pond's own water. `boundary_class()` treats Stream as Water, so
    there is no shoreline between them. The Stream tool paints 4-connected strokes
    (`TerrainBrush.centers_4_connected()`), because channels only join
    edge-adjacent tiles.

Boulders stamp Rocks terrain for gameplay. When one stands on other ground,
`TerrainGrid.set_object_footprint()` marks the tile (alpha 0 in the data
texture), and `tile_at()` draws native grass there exactly as before. Any
`set_tile()` clears the mark, loading rebuilds it from the entity layer, and
painting Rocks over a boulder's spot merges it into the rocky ground.

Neighbour materials only contribute inside their boundary band, so the shader
now skips `surface()` for zero-weight neighbours: most pixels evaluate one
surface instead of five. The output is unchanged; this pays for the costlier
inset looks, which only run on their own tiles.

| Setting | Location | Value | Effect |
| --- | --- | --- | --- |
| Stream half-width | `inset_tile()` | 0.25 ± 0.045 tiles | Wider or narrower channel |
| Inset edge blend | `fragment()` | `smoothstep(-0.5, 0, d)` | How far surrounding turf reaches in |
| Stone size | `inset_tile()` | 0.075 + id² × 0.1 tiles | Mostly pebbles with the odd boulder |
| Shrub size / density | `inset_tile()` | 0.13–0.17 tiles, 92% of cells | Denser or sparser brush |
| Pot rim / floor radius | `inset_tile()` | 0.38–0.41 / 0.27–0.30 | Pot size and wall thickness |
| Waste margin | `inset_tile()` | 0.06–0.2 tiles + noise | Raggedness of the sand edge |
| Firm fairway dry patches | `surface()` | 0.52–0.8 noise, 50% tint | Straw patch coverage |
