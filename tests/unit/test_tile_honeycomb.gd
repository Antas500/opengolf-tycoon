extends GutTest
## TileHoneycomb: the interlocking tile grid shared by the Course Terrain,
## Improvements and Buildings tabs, and the notches it can nestle a control into.

const TILE := Vector2(120, 60)

func _honeycomb(columns: int) -> TileHoneycomb:
	var grid := TileHoneycomb.new()
	grid.tile_size = TILE
	grid.columns = columns
	grid.h_separation = 8
	grid.v_separation = 20
	grid.v_padding = 20
	add_child_autofree(grid)
	return grid

func _tile(tool_name: String) -> TerrainTileButton:
	var tile := TerrainTileButton.new()
	tile.configure(TerrainTypes.Type.FAIRWAY, tool_name, "", "", "test tile")
	return tile

## A nestled control: any Control with a minimum size, drawn in the notch.
func _nestled(size: Vector2) -> Control:
	var control := Control.new()
	control.custom_minimum_size = size
	return control

func test_notch_cell_is_half_a_tile_wide_and_tall() -> void:
	var grid := _honeycomb(2)
	# Half a column pitch (tile + gap) wide, half a tile tall: the child cell of
	# the same interlocking pattern, one row up.
	assert_eq(grid.notch_cell_size(), Vector2((TILE.x + grid.h_separation) * 0.5, TILE.y * 0.5))

func test_notch_sits_between_two_tiles_above_where_they_meet() -> void:
	var grid := _honeycomb(4)
	grid.add_child(_tile("Left"))
	grid.add_child(_tile("Right"))
	await wait_frames(2)

	var left: Control = grid.get_child(0)
	var right: Control = grid.get_child(1)
	var meet := Vector2((left.position.x + left.size.x + right.position.x) * 0.5,
		left.position.y + left.size.y * 0.5)
	assert_almost_eq((grid.notch_centre(0) - Vector2(meet.x, left.position.y + TILE.y * 0.25)).length(),
		0.0, 0.01, "The notch is centred on the point where the two tiles meet, a quarter tile up")

	var nestled := _nestled(Vector2(56, 28))
	grid.set_notch_child(nestled, 0)
	await wait_frames(2)
	assert_almost_eq((nestled.position + nestled.size * 0.5).distance_to(grid.notch_centre(0)),
		0.0, 0.01, "The nestled control is centred in the notch at its own size")
	assert_eq(nestled.size, Vector2(56, 28), "It keeps the size it asked for")
	assert_almost_eq(nestled.position.y + nestled.size.y * 0.5, grid.notch_centre(0).y, 0.01,
		"Its middle sits on the notch's centre line")
	assert_lt(nestled.position.y + nestled.size.y, meet.y + 0.01,
		"It sits above the meeting point of the two tiles")

func test_nestled_child_takes_no_slot_and_leaves_the_grid_alone() -> void:
	var grid := _honeycomb(4)
	var tiles: Array[Control] = []
	for i in 4:
		var tile := _tile("Tile %d" % i)
		grid.add_child(tile)
		tiles.append(tile)
	var min_size := grid.get_combined_minimum_size()
	var nestled := _nestled(Vector2(40, 20))
	grid.set_notch_child(nestled, 0)
	await wait_frames(2)

	assert_eq(grid.flow_children(), tiles, "The nestled child is not one of the flow tiles")
	assert_true(grid.is_notch_child(nestled))
	assert_eq(grid.get_combined_minimum_size(), min_size,
		"A nestled child sits inside the grid: it adds no size to the honeycomb")
	for i in tiles.size():
		assert_almost_eq(tiles[i].position.x, i * (TILE.x + grid.h_separation), 0.01,
			"Tile %d keeps its slot: nothing is pushed along the row" % i)
	assert_almost_eq(tiles[1].position.x - tiles[0].position.x, TILE.x + grid.h_separation, 0.01,
		"No extra column opens up between the two tiles the notch sits between")

func test_several_notches_can_nestle_different_controls() -> void:
	var grid := _honeycomb(4)
	for i in 4:
		grid.add_child(_tile("Tile %d" % i))
	var first := _nestled(Vector2(40, 20))
	var second := _nestled(Vector2(40, 20))
	grid.set_notch_child(first, 0)
	grid.set_notch_child(second, 2)
	await wait_frames(2)

	assert_almost_eq(first.position.x + first.size.x * 0.5, grid.notch_centre(0).x, 0.01,
		"The first control sits between tiles 0 and 1")
	assert_almost_eq(second.position.x + second.size.x * 0.5, grid.notch_centre(2).x, 0.01,
		"The second sits between tiles 2 and 3")
	assert_eq(grid.flow_children().size(), 4, "Neither of them takes a slot")

func test_notch_child_can_be_added_before_the_tiles_are() -> void:
	# set_notch_child() also parents the child, so a honeycomb can be given its
	# nestled control before the tiles are added around it.
	var grid := _honeycomb(4)
	var nestled := _nestled(Vector2(40, 20))
	grid.set_notch_child(nestled, 0)
	assert_eq(nestled.get_parent(), grid, "The honeycomb takes ownership of the control")
	for i in 4:
		grid.add_child(_tile("Tile %d" % i))
	await wait_frames(2)

	assert_eq(grid.flow_children().size(), 4, "The nestled control is still not a tile")
	for i in 4:
		assert_eq(grid.flow_children()[i].tool_name, "Tile %d" % i, "Tiles keep their reading order")
	assert_almost_eq((nestled.position + nestled.size * 0.5).distance_to(grid.notch_centre(0)),
		0.0, 0.01, "It fills the notch between the first two tiles")

func test_hidden_tiles_leave_the_nestled_child_in_its_notch() -> void:
	var grid := _honeycomb(4)
	for i in 4:
		grid.add_child(_tile("Tile %d" % i))
	var nestled := _nestled(Vector2(40, 20))
	grid.set_notch_child(nestled, 0)
	await wait_frames(2)
	var before := nestled.position

	# The honeycomb lays out only visible tiles: a hidden tile would move the
	# rows, and the notch moves with them.
	grid.get_child(3).visible = false
	await wait_frames(2)
	assert_almost_eq(nestled.position.distance_to(before), 0.0, 0.01,
		"The notch between tiles 0 and 1 has not moved")
	assert_eq(grid.flow_children().size(), 3, "A hidden tile takes no slot")
