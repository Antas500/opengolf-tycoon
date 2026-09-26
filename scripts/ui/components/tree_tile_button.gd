extends TerrainTileButton
class_name TreeTileButton
## A catalogue choice in the Course Terrain tab drawn as an isometric diamond
## showing natural grass turf underneath a compact tree/vegetation sprite.

var tree_type: String = "oak"
var tree_data: Dictionary = {}
var _sprite: Sprite2D = null

func configure_tree(type: String, data: Dictionary) -> void:
	tree_type = type
	tree_data = data.duplicate(true)
	var t_name: String = str(data.get("name", type.capitalize()))
	var build_cost: int = int(data.get("cost", 20))
	var desc: String = "Adds beauty and obstacles. Places a %s. %s" % [t_name.to_lower(), TerrainTypes.REPLACES_ANY_COURSE_TILE]
	configure("tree_" + type, t_name, "", "", desc, build_cost, 0)
	tooltip_text = ""
	accessibility_description = "%s. Build $%d. %s" % [tool_name, build_cost, desc]

func _ready() -> void:
	super._ready()
	_build_tree_art()
	_update_visual_state()
	EventBus.season_changed.connect(_on_season_changed)

func _exit_tree() -> void:
	super._exit_tree()
	if EventBus.season_changed.is_connected(_on_season_changed):
		EventBus.season_changed.disconnect(_on_season_changed)

func _on_season_changed(_old_season: int, _new_season: int) -> void:
	_update_tree_sprite()

func _build_tree_art() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "TreeSprite"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = true
	_update_tree_sprite()
	add_child(_sprite)
	if _name_label:
		move_child(_sprite, _name_label.get_index())

func _update_tree_sprite() -> void:
	if _sprite == null:
		return
	var sprite_path := _get_sprite_path()
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		_sprite.texture = load(sprite_path)
		var tex_size := _sprite.texture.get_size()
		var target_height := 34.0 if tex_size.y > 45.0 else 22.0
		var s := target_height / maxf(1.0, tex_size.y)
		_sprite.scale = Vector2(s, s)
		var y_pos := 24.0 if tex_size.y > 45.0 else 30.0
		_sprite.position = Vector2(BUTTON_SIZE.x * 0.5, y_pos)

func _get_sprite_path() -> String:
	var day := 1
	if GameManager:
		day = GameManager.current_day
	var season := SeasonSystem.get_season(day)
	var season_name := SeasonSystem.get_season_name(season).to_lower()
	if tree_type in TreeEntity.DECIDUOUS_TYPES and season_name != "summer":
		var key := "%s_%s" % [tree_type, season_name]
		if key in TreeEntity.SEASONAL_SPRITE_PATHS and ResourceLoader.exists(TreeEntity.SEASONAL_SPRITE_PATHS[key]):
			return TreeEntity.SEASONAL_SPRITE_PATHS[key]
	if tree_type == "pine" and season_name == "winter":
		var current_theme: int = CourseTheme.Type.PARKLAND
		if GameManager:
			current_theme = GameManager.current_theme
		if current_theme in TreeEntity.SNOWY_THEMES:
			var key := "pine_winter"
			if key in TreeEntity.SEASONAL_SPRITE_PATHS and ResourceLoader.exists(TreeEntity.SEASONAL_SPRITE_PATHS[key]):
				return TreeEntity.SEASONAL_SPRITE_PATHS[key]
	return TreeEntity.SPRITE_PATHS.get(tree_type, "")
