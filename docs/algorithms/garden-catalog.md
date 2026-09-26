# Garden and facility catalog

The catalog contains 28 decorations and 16 buildings. Sixteen new decorations use `GardenArt` for consistent miniature artwork: rose and lavender borders, hydrangeas, hedges, rose arches, pergolas, picnic and parasol tables, lanterns, walls, fences, planters, lily pools, rock gardens, clocks and viewing decks. Lily pools and decks are ornamental; they do not replace water hazards or bridges.

Eight new facilities use `CourseArchitecture`: coffee house, halfway house, tea pavilion, ice cream kiosk, locker room, garden spa, conservatory and golf academy. Each defines construction cost, daily operating cost and its golfer service. `needs_service` maps a facility to the existing needs rules; revenue is earned only on a golfer's normal interaction check.

The Improvements tab lists the decorations as isometric tiles (`DecorationTileButton` / `DecorationTileArt`), the same interlocking two-row shelf the Course Terrain and Buildings tabs use; pressing a tile starts placement straight away, with price, upkeep and unlock status in the hover tooltip. Tiles and placed objects share the same drawing routines. Garden ghosts tint red on invalid placement. Footprint validation is shared between the preview and placement click: all tiles must be on owned compatible ground and clear of buildings, decorations, trees and rocks. Buildings can sit on paths. Failure messages describe the obstruction.

Placement, bulldozing, undo, aesthetics and JSON saving use the existing entity machinery. New items are data-driven, and older saves need no migration.
