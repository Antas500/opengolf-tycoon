extends SceneTree
## Dev harness: renders the GlobeMap land mask to PNGs so the continent
## outlines can be eyeballed without a GPU. Not part of the test suite.

## Writes into the project's tmp_preview/ folder (git-ignored).
const OUT_DIR := "res://tmp_preview"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_render_equirect()
	_render_ortho()
	print("wrote previews to ", OUT_DIR)
	quit()

func _render_equirect() -> void:
	var w := 720
	var h := 360
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color("16314a"))
	for y in range(h):
		var lat: float = 90.0 - (float(y) + 0.5) * (180.0 / float(h))
		for x in range(w):
			var lon: float = -180.0 + (float(x) + 0.5) * (360.0 / float(w))
			if GlobeMap.is_land(lon, lat):
				img.set_pixel(x, y, GlobeMap.LAND_COLOR)
	print("equirect save: ", img.save_png(OUT_DIR + "/equirect.png"))

func _render_ortho() -> void:
	var size := 600
	var radius := 280.0
	var center := Vector2(size * 0.5, size * 0.5)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_fill_circle(img, center, radius + 3.0, GlobeMap.OCEAN_RIM)
	_fill_circle(img, center, radius, GlobeMap.OCEAN_COLOR)
	var dot := radius * deg_to_rad(GlobeMap.LAND_STEP_DEG) * 0.68
	var lat := -88.0
	while lat <= 88.0:
		var lon := -180.0
		while lon < 180.0:
			if GlobeMap.is_land(lon, lat):
				var v := GlobeMap.project_point(lon, lat, -40.0, 30.0)
				if v.z > 0.0:
					var pos := center + Vector2(v.x, -v.y) * radius
					var lit := clampf(v.z * 1.6, 0.0, 1.0)
					_fill_circle(img, pos, dot * (0.75 + 0.25 * lit),
						GlobeMap.LAND_SHADE_COLOR.lerp(GlobeMap.LAND_COLOR, lit))
			lon += GlobeMap.LAND_STEP_DEG
		lat += GlobeMap.LAND_STEP_DEG
	print("ortho save: ", img.save_png(OUT_DIR + "/ortho.png"))

func _fill_circle(img: Image, center: Vector2, r: float, color: Color) -> void:
	var x0 := maxi(0, int(center.x - r))
	var x1 := mini(img.get_width() - 1, int(center.x + r))
	var y0 := maxi(0, int(center.y - r))
	var y1 := mini(img.get_height() - 1, int(center.y + r))
	var r2 := r * r
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - center.x
			var dy := float(y) + 0.5 - center.y
			if dx * dx + dy * dy <= r2:
				img.set_pixel(x, y, color)
