extends GutTest
## EventFeedManager feed-content regressions.
##
## The "Course rating updated" line was dropped from the feed: the rating is
## recalculated every time the day closes (plus quick start, save load and
## tournament completion), so the line repeated almost verbatim every day and
## buried the events worth reading. The HUD star readout, the Course Rating
## panel and milestone_manager remain the consumers of course_rating_changed.
##
## Control cases below assert that the rest of the feed still records events, so
## a green run here means the rating line was removed rather than the feed.

## A realistic payload: exactly the Dictionary CourseRatingSystem returns.
const RATING: Dictionary = {
	"condition": 3.6,
	"design": 3.2,
	"value": 3.1,
	"pace": 3.7,
	"aesthetics": 2.8,
	"overall": 3.4,
	"stars": 3,
}

var _saved_mode: int
var _saved_speed: int
var _saved_day: int
var _saved_green_fee: int
var _saved_terrain_grid: TerrainGrid
var _saved_course
var _saved_rating: Dictionary


func before_each() -> void:
	_saved_mode = GameManager.current_mode
	_saved_speed = GameManager.current_speed
	_saved_day = GameManager.current_day
	_saved_green_fee = GameManager.green_fee
	_saved_terrain_grid = GameManager.terrain_grid
	_saved_course = GameManager.current_course
	_saved_rating = GameManager.course_rating.duplicate(true)

	# add_event() drops everything while in the main menu, so simulate a live game.
	GameManager.current_mode = GameManager.GameMode.SIMULATING
	GameManager.current_speed = GameManager.GameSpeed.NORMAL
	EventFeedManager.clear_events()


func after_each() -> void:
	GameManager.current_mode = _saved_mode as GameManager.GameMode
	GameManager.current_speed = _saved_speed as GameManager.GameSpeed
	GameManager.current_day = _saved_day
	# hole_created triggers GameManager's green fee clamp; keep it from leaking.
	GameManager.green_fee = _saved_green_fee
	GameManager.terrain_grid = _saved_terrain_grid
	GameManager.current_course = _saved_course
	GameManager.course_rating = _saved_rating
	EventFeedManager.clear_events()


# --- Course rating changes produce no feed entries ---

func test_course_rating_changed_adds_no_feed_event() -> void:
	watch_signals(EventFeedManager)

	EventBus.course_rating_changed.emit(RATING)

	assert_eq(EventFeedManager.events.size(), 0,
		"A course rating change must not add a feed entry")
	assert_signal_not_emitted(EventFeedManager, "event_added",
		"No toast should fire for a course rating change")


func test_repeated_course_rating_changes_stay_silent() -> void:
	# The day-close recalculation is what spammed the feed: fire it several times.
	for _i in 5:
		EventBus.course_rating_changed.emit(RATING)

	assert_eq(EventFeedManager.events.size(), 0,
		"Repeated rating recalculations must all stay out of the feed")


func test_star_upgrade_adds_no_feed_event() -> void:
	# Even a rating that crosses a star boundary stays out of the feed.
	var upgraded: Dictionary = RATING.duplicate(true)
	upgraded["overall"] = 4.2
	upgraded["stars"] = 4

	EventBus.course_rating_changed.emit(upgraded)

	assert_eq(EventFeedManager.events.size(), 0,
		"Crossing a star boundary must not add a feed entry either")


func test_no_feed_message_mentions_course_rating() -> void:
	EventBus.course_rating_changed.emit(RATING)
	# Another event lands alongside the rating recalculation on day close, so the
	# feed is provably live while the rating stays silent. (Unrelated autoloads may
	# record their own lines here, so only the wording is asserted.)
	EventBus.hole_created.emit(4, 4, 380)
	EventBus.course_rating_changed.emit(RATING)

	assert_gt(EventFeedManager.events.size(), 0,
		"The feed should be live and have recorded the hole creation")
	for entry in EventFeedManager.events:
		assert_false(entry.message.to_lower().contains("course rating"),
			"No feed message should mention the course rating, got: " + entry.message)


func test_update_course_rating_notifies_without_feed_entry() -> void:
	# End to end through the caller that runs on every day close.
	var grid := TerrainGrid.new()
	grid.grid_width = 32
	grid.grid_height = 32
	add_child_autofree(grid)

	GameManager.terrain_grid = grid
	GameManager.current_course = _make_course()
	watch_signals(EventBus)

	GameManager.update_course_rating()

	assert_signal_emitted(EventBus, "course_rating_changed",
		"Recalculating the rating must still notify other listeners")
	assert_gt(GameManager.course_rating.get("overall", 0.0), 0.0,
		"Sanity check: the recalculation actually produced a rating")
	assert_eq(EventFeedManager.events.size(), 0,
		"update_course_rating() must not add a feed entry")


func test_event_feed_manager_not_connected_to_course_rating_signal() -> void:
	var feed_listeners: Array[String] = []
	for connection in EventBus.course_rating_changed.get_connections():
		var callable: Callable = connection["callable"]
		if callable.get_object() == EventFeedManager:
			feed_listeners.append(str(callable))

	assert_true(feed_listeners.is_empty(),
		"EventFeedManager must not listen to course_rating_changed, found: "
		+ str(feed_listeners))


func test_course_rating_feed_handler_removed() -> void:
	assert_false(EventFeedManager.has_method("_on_course_rating_changed"),
		"The rating feed handler should be gone, not merely disconnected")


# --- Control cases: the rest of the feed still works ---

func test_hole_created_still_feeds_course_category() -> void:
	EventBus.hole_created.emit(4, 4, 380)

	# GameManager clamps the green fee when holes change and records its own
	# ECONOMY line first, so pick out the COURSE entry this test is about.
	var course_entries: Array = _events_in_category(EventFeedManager.Category.COURSE)

	assert_eq(course_entries.size(), 1,
		"Hole creation should still be recorded in the COURSE category")
	var entry: EventFeedManager.EventEntry = course_entries[0]
	assert_true(entry.message.contains("Hole #4"),
		"Hole creation message should name the hole, got: " + entry.message)


func test_building_placed_still_feeds_course_category() -> void:
	EventBus.building_placed.emit("pro_shop", Vector2i(12, 30))

	var course_entries: Array = _events_in_category(EventFeedManager.Category.COURSE)
	assert_eq(course_entries.size(), 1,
		"Building placement should still be recorded in the COURSE category")


func test_green_fee_change_still_feeds_economy_category() -> void:
	EventBus.green_fee_changed.emit(35, 40)

	assert_eq(EventFeedManager.events.size(), 1,
		"Green fee changes should still be recorded")
	assert_eq(EventFeedManager.events[0].category, EventFeedManager.Category.ECONOMY,
		"Green fee changes belong to the ECONOMY category")


# --- Helpers ---

## Feed entries of one category, so control cases don't depend on where unrelated
## autoloads happen to record their own lines.
func _events_in_category(category: int) -> Array:
	var matches: Array = []
	for entry in EventFeedManager.events:
		if entry.category == category:
			matches.append(entry)
	return matches


func _make_course() -> GameManager.CourseData:
	var course := GameManager.CourseData.new()
	for i in range(1, 4):
		var hole := GameManager.HoleData.new()
		hole.hole_number = i
		hole.par = 4
		hole.is_open = true
		hole.difficulty_rating = 5.0
		course.add_hole(hole)
	return course
