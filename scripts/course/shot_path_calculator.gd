extends RefCounted
class_name ShotPathCalculator
## ShotPathCalculator - Calculates expected shot path for hole visualization
##
## Uses ShotAI to show where an average golfer would aim their drive and
## approach shots. This helps course designers understand how golfers will
## play each hole.
##
## Creates a lightweight GolferData with average CASUAL tier skills to run
## through ShotAI's decision pipeline without needing a real Golfer node.

## Average CASUAL golfer skills (midpoint of CASUAL tier [0.5, 0.7]):
const AVG_SKILL: float = 0.6
const AVG_AGGRESSION: float = 0.45
const AVG_PATIENCE: float = 0.55

## Calculate shot path waypoints from tee to flag.
## Returns array of grid positions: [tee, landing1, ..., flag]
## Par 3: [tee, flag] (direct shot)
## Par 4: [tee, drive_landing, flag]
## Par 5: [tee, drive_landing, second_landing, flag]
static func calculate_waypoints(hole_data: GameManager.HoleData, terrain_grid: TerrainGrid = null) -> Array[Vector2i]:
	return calculate_route(hole_data.tee_position, hole_data.hole_position, hole_data.par,
			hole_data.hole_number - 1, terrain_grid)

## Expected shot route for a tee -> cup pair that need not be a hole yet.
## `hole_index` is the 0-based index into the course's holes that ShotAI's
## green-centre bias reads; pass -1 for a pair that is not a hole (the Green
## tool's potential-hole preview). `terrain_grid` defaults to
## GameManager.terrain_grid — pass a detached copy
## (TerrainGrid.create_analysis_copy()) to plan off the main thread.
static func calculate_route(tee: Vector2i, cup: Vector2i, par: int, hole_index: int = -1,
		terrain_grid: TerrainGrid = null) -> Array[Vector2i]:
	var grid: TerrainGrid = terrain_grid if terrain_grid else GameManager.terrain_grid
	var waypoints: Array[Vector2i] = [tee]

	# Shots to reach the green = par - 2 putts
	var shots_to_green: int = par - 2
	var num_intermediate: int = shots_to_green - 1
	if num_intermediate <= 0:
		waypoints.append(cup)
		return waypoints

	# Create lightweight golfer data for visualization (no scene tree needed)
	var gd: ShotAI.GolferData = _create_avg_golfer_data(tee, hole_index)

	for i in range(num_intermediate):
		# Use ShotAI to decide the shot from this position
		var decision: ShotAI.ShotDecision = ShotAI.decide_shot_for(gd, cup, true, grid)
		var landing: Vector2i = decision.target

		# Safety: don't add same position or positions that don't advance
		if landing == gd.ball_position:
			break

		# If landing reached the green area, stop adding intermediates
		if grid and grid.get_tile(landing) == TerrainTypes.Type.GREEN:
			break

		waypoints.append(landing)

		# Move phantom to the new position for next shot
		gd.ball_position = landing
		gd.ball_position_precise = Vector2(landing)

	waypoints.append(cup)
	return waypoints

## Create a GolferData with average CASUAL tier skills for visualization.
## hole_index -1 means the route is not for a hole in the course yet.
static func _create_avg_golfer_data(tee_pos: Vector2i, hole_index: int = 0) -> ShotAI.GolferData:
	var gd: ShotAI.GolferData = ShotAI.GolferData.new()
	gd.ball_position = tee_pos
	gd.ball_position_precise = Vector2(tee_pos)
	gd.driving_skill = AVG_SKILL
	gd.accuracy_skill = AVG_SKILL
	gd.putting_skill = AVG_SKILL
	gd.recovery_skill = AVG_SKILL
	gd.miss_tendency = 0.0
	gd.aggression = AVG_AGGRESSION
	gd.patience = AVG_PATIENCE
	gd.current_hole = hole_index
	gd.total_strokes = 0
	gd.total_par = 0
	return gd
