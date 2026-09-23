extends RefCounted
class_name HolePathPlanner
## HolePathPlanner - Expected shot route for a hole that is not built yet.
##
## While a tee box waits, the Green tool previews the hole the hovered tile would
## make (HoleLayout.potential_hole()). That route has to match what HoleVisualizer
## draws once the hole opens, so it comes from the same ShotPathCalculator/ShotAI
## pipeline — which costs roughly 0.2 s for a par 4 and 0.4 s for a par 5, far too
## slow to run on the main thread for every tile the cursor crosses. So:
##
##   * Par 3 routes are just [tee, cup] and come back immediately.
##   * Par 4/5 routes are planned by a WorkerThreadPool task against a detached
##     copy of the terrain (TerrainGrid.create_analysis_copy()), never the live
##     grid, painted the way the course will look once the hole opens: the cup
##     tile green, plus any forward/middle tee tiles Open Hole adds (multi-tee).
##     One task runs at a time; while it runs only the most recent request is
##     remembered, so the route catches up as soon as the cursor settles.
##   * Finished routes are cached per (tee, cup, par, extra tees) until the terrain
##     changes (TerrainGrid.terrain_revision), so sweeping back over a tile is instant.
##   * Without thread support (the Web export) a route is planned on the main
##     thread, but only once the cursor has rested on the same tile for
##     inline_dwell_msec, so sweeping the cursor across the course never stalls.
##
## Call poll() every frame (route_for() does it too) and shutdown() before the
## owner goes away — a running task must finish before its terrain copy is freed.

const MAX_CACHED_ROUTES: int = 256

## False on platforms without threads (Web export): routes are planned inline.
var threaded: bool = OS.has_feature("threads")
## Without threads, how long the cursor must rest on a tile before planning it.
## ShotAI then blocks the frame for a moment, so only plan where the player is looking.
var inline_dwell_msec: int = 500

var _cache: Dictionary = {}  # [tee, cup, par, extra_tees] -> Array[Vector2i]
var _cache_revision: int = -1
var _cache_grid_id: int = 0

var _job: _RouteJob = null  # In-flight task, or null
var _task_id: int = -1
var _wanted: Dictionary = {}  # Latest request still waiting for a task: {grid, key}
var _snapshot: TerrainGrid = null  # Detached terrain the planning reads
var _snapshot_revision: int = -1

var _inline_key: Array = []  # Tile the cursor is resting on (no-thread fallback)
var _inline_since_msec: int = 0

## One route computation. Runs on a worker thread and touches nothing but its own
## fields and the detached terrain copy.
class _RouteJob:
	extends RefCounted
	var key: Array = []
	var revision: int = -1
	var grid: TerrainGrid = null
	var route: Array[Vector2i] = []

	func run() -> void:
		var tee: Vector2i = key[0]
		var cup: Vector2i = key[1]
		var par: int = key[2]
		var extra_tees: Array = key[3]
		# Plan the course as it will be once the hole opens: the cup tile is green
		# and Open Hole has painted the forward/middle tees.
		var painted: Dictionary = {cup: TerrainTypes.Type.GREEN}
		for extra_tee in extra_tees:
			painted[extra_tee] = TerrainTypes.Type.TEE_BOX
		var before: Dictionary = {}
		for pos in painted:
			before[pos] = grid.get_tile(pos)
			grid.set_analysis_tile(pos, painted[pos])
		route = ShotPathCalculator.calculate_route(tee, cup, par, -1, grid)
		for pos in before:
			grid.set_analysis_tile(pos, before[pos])

## The planned route [tee, landing..., cup], or [] while it is still being planned
## — draw the direct tee-to-cup line meanwhile. `extra_tees` are the forward/middle
## tee tiles Open Hole will paint (HoleLayout.potential_hole().extra_tees).
func route_for(grid: TerrainGrid, tee: Vector2i, cup: Vector2i, par: int,
		extra_tees: Array = []) -> Array[Vector2i]:
	if par <= 3:
		# ShotPathCalculator doesn't consult ShotAI for par 3s: one shot to the cup.
		return [tee, cup]
	if not is_instance_valid(grid):
		return []
	_sync_cache(grid)
	poll()
	var sorted_tees := extra_tees.duplicate()
	sorted_tees.sort()
	var key: Array = [tee, cup, par, sorted_tees]
	if _cache.has(key):
		_wanted = {}  # The newest request is answered; anything older is moot.
		return _cache[key]
	if not threaded:
		return _route_inline(grid, key)
	if _job and _job.key == key and _job.revision == grid.terrain_revision:
		_wanted = {}  # Already being planned.
		return []
	_wanted = {"grid": grid, "key": key}
	if _job == null:
		_start_wanted()
	return []

## Collect a finished task and start the newest pending request.
func poll() -> void:
	if _job == null or not WorkerThreadPool.is_task_completed(_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	var job := _job
	_job = null
	_task_id = -1
	# A route planned on terrain that has changed since is stale — drop it.
	if job.revision == _cache_revision:
		_store(job.key, job.route)
	if not _wanted.is_empty():
		_start_wanted()

## True while a route is being planned or waiting for its turn.
func is_planning() -> bool:
	return _job != null or not _wanted.is_empty()

## Forget the pending request (the preview was hidden). A running task still
## finishes and its route is cached.
func cancel_pending() -> void:
	_wanted = {}
	_inline_key = []

## Wait for the running task, then release the terrain copy and the cache.
func shutdown() -> void:
	if _job:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_job = null
		_task_id = -1
	_wanted = {}
	_inline_key = []
	_free_snapshot()
	_cache.clear()
	_cache_revision = -1

func _notification(what: int) -> void:
	# Safety net for owners that never called shutdown(). A RefCounted being freed
	# can't dispatch calls on itself, so the cleanup is inlined here.
	if what == NOTIFICATION_PREDELETE:
		if _job:
			WorkerThreadPool.wait_for_task_completion(_task_id)
		if _snapshot and is_instance_valid(_snapshot):
			_snapshot.free()

func _sync_cache(grid: TerrainGrid) -> void:
	var grid_id := grid.get_instance_id()
	if grid.terrain_revision == _cache_revision and grid_id == _cache_grid_id:
		return
	_cache.clear()
	_cache_revision = grid.terrain_revision
	_cache_grid_id = grid_id

func _store(key: Array, route: Array[Vector2i]) -> void:
	if _cache.size() >= MAX_CACHED_ROUTES:
		_cache.erase(_cache.keys()[0])  # Oldest first (dictionaries keep insertion order).
	_cache[key] = route

## No worker threads: plan on the main thread once the cursor rests on the tile.
func _route_inline(grid: TerrainGrid, key: Array) -> Array[Vector2i]:
	if _job:
		return []  # A task from before `threaded` was switched off still owns the copy.
	var now := Time.get_ticks_msec()
	if key != _inline_key:
		_inline_key = key
		_inline_since_msec = now
	if now - _inline_since_msec < inline_dwell_msec:
		return []
	var job := _make_job(grid, key)
	job.run()
	_store(key, job.route)
	return job.route

func _start_wanted() -> void:
	var grid: TerrainGrid = _wanted.get("grid")
	var key: Array = _wanted.get("key", [])
	_wanted = {}
	if not is_instance_valid(grid) or key.is_empty():
		return
	_job = _make_job(grid, key)
	_task_id = WorkerThreadPool.add_task(_job.run, false, "Potential hole path")

## Only called while no task is running, so the terrain copy can be replaced.
func _make_job(grid: TerrainGrid, key: Array) -> _RouteJob:
	if _snapshot == null or _snapshot_revision != grid.terrain_revision:
		_free_snapshot()
		_snapshot = grid.create_analysis_copy()
		_snapshot_revision = grid.terrain_revision
	var job := _RouteJob.new()
	job.key = key
	job.revision = _snapshot_revision
	job.grid = _snapshot
	return job

func _free_snapshot() -> void:
	if _snapshot and is_instance_valid(_snapshot):
		_snapshot.free()
	_snapshot = null
	_snapshot_revision = -1
