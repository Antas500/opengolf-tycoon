extends RefCounted
class_name PlayerGolferProfile
## Persistent owner golfer. Percentages are bonuses, not AI's normalized skills.
const SKILLS = ["Power Hitter", "Long Driver", "Accurate Driver", "Accurate Irons",
	"Accurate Putter", "Draw Shot (R to L)", "Fade Shot (L to R)",
	"High Backspin Shot", "Recovery Skills", "Luck"]
const COLORS = ["shirt_color", "pants_color", "cap_color", "hair_color", "skin_tone"]
var golfer_name: String = "Course Owner"
var appearance: Dictionary = {"shirt_color": "e65959", "pants_color": "404059",
	"cap_color": "3366b3", "hair_color": "4d331a", "skin_tone": "f2cca6"}
var points: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
var initialized: bool = false

func remaining() -> int:
	var spent := 0
	for value in points:
		spent += value
	return maxi(0, 10 - spent)

func allocate(index: int, change: int) -> bool:
	if initialized or index < 0 or index >= points.size() or abs(change) != 1:
		return false
	if points[index] + change < 0 or points[index] + change > 99:
		return false
	if change > 0 and remaining() == 0:
		return false
	points[index] += change
	return true

func bonus(index: int) -> float:
	return points[index] * 0.1

func normalized_skill(index: int) -> float:
	return 1.0 - 0.5 / (1.0 + bonus(index))

func serialize() -> Dictionary:
	return {"name": golfer_name, "appearance": appearance.duplicate(),
		"points": points.duplicate(), "initialized": initialized}

static func from_data(data: Dictionary) -> PlayerGolferProfile:
	var profile := PlayerGolferProfile.new()
	profile.golfer_name = str(data.get("name", "Course Owner")).strip_edges().left(32)
	if profile.golfer_name.is_empty():
		profile.golfer_name = "Course Owner"
	var colors = data.get("appearance", {})
	if colors is Dictionary:
		for key in COLORS:
			profile.appearance[key] = Color.from_string(str(colors.get(key, profile.appearance[key])), Color(profile.appearance[key])).to_html(false)
	var saved = data.get("points", [])
	if saved is Array and saved.size() == SKILLS.size():
		for i in SKILLS.size():
			profile.points[i] = clampi(int(saved[i]), 0, 99)
	profile.initialized = bool(data.get("initialized", false))
	if not profile.initialized:
		var budget := 10
		for i in profile.points.size():
			profile.points[i] = mini(profile.points[i], budget)
			budget -= profile.points[i]
	return profile
