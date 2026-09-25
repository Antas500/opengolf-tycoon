extends TerrainTileButton
class_name BoulderTileButton
## A catalogue choice in the Course Terrain tab drawn as an isometric diamond
## showing natural grass turf underneath a compact boulder sprite.

var rock_size: String = "medium"
var rock_data: Dictionary = {}
var _sprite: Sprite2D = null

func configure_boulder(p_size: String, data: Dictionary) -> void:
	rock_size = p_size
	rock_data = data.duplicate(true)
	var r_name: String = str(data.get("name", "Boulders"))
	var boulder_cost: int = int(data.get("cost", 15))
	var desc: String = "Decorative boulder obstacle. Places a %s." % r_name.to_lower()
	var tool_id := "rock" if p_size == "medium" else ("boulder_" + p_size)
	configure(tool_id, r_name, "", "", desc, boulder_cost, 0)
	tooltip_text = ""
	accessibility_description = "%s. Build $%d. %s" % [tool_name, boulder_cost, desc]

func _ready() -> void:
	super._ready()
	_build_boulder_art()
	_update_visual_state()

func _build_boulder_art() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "BoulderSprite"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = true
	var sprite_path: String = Rock.SPRITE_PATHS.get(rock_size, "")
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		_sprite.texture = load(sprite_path)
		var tex_size := _sprite.texture.get_size()
		var target_height := 18.0
		if rock_size == "medium":
			target_height = 25.0
		elif rock_size == "large":
			target_height = 32.0
		var s := target_height / maxf(1.0, tex_size.y)
		_sprite.scale = Vector2(s, s)
		_sprite.position = Vector2(BUTTON_SIZE.x * 0.5, 30.0)
	add_child(_sprite)
	if _name_label:
		move_child(_sprite, _name_label.get_index())
