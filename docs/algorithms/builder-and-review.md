# Builder and Course Review

## Plain English

Fast terrain drags paint continuous strokes. Round brushes form softer contours; square brushes preserve straight edges. One stroke records terrain, cleared trees, and the actual amount charged. Undo restores cleared objects and cash; redo checks affordability before consuming the redo action. Releasing over UI or cancelling closes the stroke. Terrain painting protects decorations as well as buildings and respects ownership.

Course Review translates observable conditions into actions: repair a tee/cup surface, improve an under-turfed direct corridor, review a low value rating, locate a tee lacking nearby food, or investigate an operating loss. Locate buttons focus the affected hole; finance and decoration actions open their panels. The end-of-day summary repeats a suggested next step.

## Algorithm

`TerrainBrush.centers` samples and rounds a line with `max(abs(dx), abs(dy))` steps. Consecutive stamps differ by at most one tile per axis. Brush sizes run 1×1 through 9×9 (the same steps as the Elevation Brush). Odd sizes centre on the cursor tile; even sizes centre on the vertex at that tile's near corner, so an S×S stamp always covers S tiles per side. A square includes every offset in that block; a round brush keeps tiles whose centre lies within a circle of radius `S/2` around the middle of the block.

`CourseAdvisor.review` returns up to four suggestions. It checks tee/cup terrain, samples a three-tile corridor (flags short turf below 65%), flags value below 2.8/5, checks food service reach at tees from hole four onward, then operating loss and aesthetics below 2.5/5. Direct-corridor advice is a heuristic, not a routing solver; intentional doglegs and hazards require judgment.

Quick Start builds nine holes with gently curved, variable-width fairways and a central clubhouse garden. Fairway corridors replace generated water tiles so holes are never cut off by pre-existing ponds or lagoons. It includes four service buildings and an assortment of catalog decorations, with seating beside playing areas. Seating placement protects tee and green surfaces, including the cup's tile.

## Tuning levers

| Lever | Location | Value |
|---|---|---|
| Corridor coverage threshold | CourseAdvisor | 65% |
| Value warning | CourseAdvisor | 2.8/5 |
| Maximum suggestions | CourseAdvisor | 4 |
| Brush sizes | TerrainToolbar.BRUSH_SIZES | 1..9 | S×S tile stamps, matching the Elevation Brush |
| Round brush edge | TerrainBrush | tile centre within S/2 of the block middle |
| Starter fee | QuickStartCourse | $5/hole |

Course Review now leads with actual visitor complaint hotspots (name, hole and grid position available in records), warns when arrivals exceed completed rounds at closing, displays on-course amenity use and income, and compares completed-visit satisfaction and operating profit with the prior three days. The advice area scrolls. Quick Start also includes small layered groups of trees and low planting around the clubhouse entrance, while preserving tees, greens and existing entities.

Shortcut collision fixed: F opens Finance, and Shift+F selects flower beds. The finance shortcut no longer silently selects a terrain brush.
