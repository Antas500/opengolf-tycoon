extends SceneTree
## Dev harness: renders the World Map planet to PNGs so the new globe can be
## looked at from a machine with no GPU (CI, a headless box). Not part of the
## test suite.
##
## This is a CPU port of shaders/globe_planet.gdshader: the palette and the
## tuning values are parsed straight out of the shader's uniform defaults and
## the fragment maths follows it line for line, so tuning the shader shows up
## here too. It is a *look preview*, never a verification — only a GPU
## compiles the real GLSL, so the shader's syntax and its interface with
## GlobeMap are covered by tests/unit/test_globe_map.gd instead.
##
## Writes three views into the git-ignored tmp_preview/ folder: the default
## atlas view, the north pole (ice cap) and the Pacific (open water).

const SHADER_PATH := "res://shaders/globe_planet.gdshader"

var _uniforms: Dictionary = {}
var _mask: Image
var _view_lon := -40.0
var _view_lat := 30.0

func _initialize() -> void:
	_parse_uniforms()
	_mask = GlobeMap.build_land_mask()
	_report_projection_round_trip()
	# The view GlobeMap opens on, plus a pole and an ocean view.
	_render(820, -40.0, 30.0, "planet_view.png")
	_render(600, 0.0, 78.0, "planet_view_pole.png")
	_render(600, -150.0, 10.0, "planet_view_pacific.png")
	print("wrote planet previews to res://tmp_preview")
	quit()

func _render(size: int, center_lon: float, center_lat: float, file: String) -> void:
	_view_lon = center_lon
	_view_lat = center_lat
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp_preview"))
	var started := Time.get_ticks_usec()
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var background := MenuStyle.SHEET_BG
	for y in range(size):
		for x in range(size):
			var color := _fragment(Vector2(float(x) + 0.5, float(y) + 0.5), Vector2(size, size))
			# Composite the globe (and its halo) over the screen's card colour.
			var alpha := color.a
			img.set_pixel(x, y, Color(
				color.r * alpha + background.r * (1.0 - alpha),
				color.g * alpha + background.g * (1.0 - alpha),
				color.b * alpha + background.b * (1.0 - alpha)))
	var pinned := _draw_pins(img, Vector2(size, size), center_lon, center_lat)
	print("%s %dx%d in %.0f ms, %d pins drawn" % [
		file, size, size, float(Time.get_ticks_usec() - started) / 1000.0, pinned])
	print("save: ", img.save_png("res://tmp_preview/" + file))

func _parse_uniforms() -> void:
	for line in FileAccess.get_file_as_string(SHADER_PATH).split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("uniform ") or not trimmed.contains("="):
			continue
		var body := trimmed.substr(8)
		var eq := body.find("=")
		var left := body.substr(0, eq)
		var right := body.substr(eq + 1).strip_edges().trim_suffix(";")
		left = left.split(":")[0].strip_edges()
		var parts := left.split(" ", false)
		if parts.size() < 2:
			continue
		var name := parts[1]
		if parts[0] == "vec4":
			var numbers := right.trim_prefix("vec4(").trim_suffix(")").split(",")
			_uniforms[name] = Color(float(numbers[0]), float(numbers[1]), float(numbers[2]), float(numbers[3]))
		elif parts[0] == "vec3":
			var numbers := right.trim_prefix("vec3(").trim_suffix(")").split(",")
			_uniforms[name] = Vector3(float(numbers[0]), float(numbers[1]), float(numbers[2]))
		elif parts[0] == "float":
			_uniforms[name] = float(right)
	print("parsed %d uniform defaults from the shader" % _uniforms.size())

func _u4(name: String) -> Color:
	return _uniforms[name]

func _u3(name: String) -> Vector3:
	return _uniforms[name]

func _uf(name: String) -> float:
	return float(_uniforms.get(name, 0.0))

# ── noise, ported from the shader ──────────────────────────────────────────
func _hash31(p: Vector3) -> float:
	var q := Vector3(fposmod(p.x * 0.1031, 1.0), fposmod(p.y * 0.1030, 1.0), fposmod(p.z * 0.0973, 1.0))
	var d := q.x * (q.x + 33.33) + q.y * (q.y + 33.33) + q.z * (q.z + 33.33)
	q = Vector3(fposmod(q.x + d, 1.0), fposmod(q.y + d, 1.0), fposmod(q.z + d, 1.0))
	return fposmod((q.x + q.y) * q.z, 1.0)

func _value_noise(p: Vector3) -> float:
	var i := Vector3(floorf(p.x), floorf(p.y), floorf(p.z))
	var f := Vector3(p.x - i.x, p.y - i.y, p.z - i.z)
	f = Vector3(f.x * f.x * (3.0 - 2.0 * f.x), f.y * f.y * (3.0 - 2.0 * f.y), f.z * f.z * (3.0 - 2.0 * f.z))
	var n000 := _hash31(i)
	var n100 := _hash31(i + Vector3(1, 0, 0))
	var n010 := _hash31(i + Vector3(0, 1, 0))
	var n110 := _hash31(i + Vector3(1, 1, 0))
	var n001 := _hash31(i + Vector3(0, 0, 1))
	var n101 := _hash31(i + Vector3(1, 0, 1))
	var n011 := _hash31(i + Vector3(0, 1, 1))
	var n111 := _hash31(i + Vector3(1, 1, 1))
	return lerpf(
		lerpf(lerpf(n000, n100, f.x), lerpf(n010, n110, f.x), f.y),
		lerpf(lerpf(n001, n101, f.x), lerpf(n011, n111, f.x), f.y), f.z)

func _fbm(p: Vector3) -> float:
	var value := 0.0
	var amplitude := 0.5
	for i in range(4):
		value += amplitude * _value_noise(p)
		p = p * 2.03 + Vector3(11.7, 5.3, 7.9)
		amplitude *= 0.5
	return value

func _mask_at(uv: Vector2) -> float:
	var w := float(_mask.get_width())
	var h := float(_mask.get_height())
	# Bilinear with the sampler's wrap in u.
	var fx := uv.x * w - 0.5
	var fy := uv.y * h - 0.5
	var x0 := int(floorf(fx))
	var y0 := clampf(floorf(fy), 0.0, h - 1.0)
	var tx := fx - float(x0)
	var ty := fy - y0
	var y1 := minf(y0 + 1.0, h - 1.0)
	var c00 := _mask.get_pixel(posmod(x0, int(w)), int(y0)).r
	var c10 := _mask.get_pixel(posmod(x0 + 1, int(w)), int(y0)).r
	var c01 := _mask.get_pixel(posmod(x0, int(w)), int(y1)).r
	var c11 := _mask.get_pixel(posmod(x0 + 1, int(w)), int(y1)).r
	return lerpf(lerpf(c00, c10, tx), lerpf(c01, c11, tx), ty)

# ── the fragment function, line for line ───────────────────────────────────
func _fragment(px_pos: Vector2, view_size: Vector2) -> Color:
	var center_lon := _view_lon
	var center_lat := _view_lat
	var radius_scale := _uf("radius_scale")
	var sphere_fill := _uf("sphere_fill")
	var halo_scale := _uf("halo_scale")

	var p := px_pos - view_size * 0.5
	var radius := maxf(minf(view_size.x, view_size.y) * 0.5 * sphere_fill * radius_scale, 1.0)
	var r := p.length() / radius
	var px := 1.0 / radius
	var body := 1.0 - smoothstep(1.0 - px * 1.5, 1.0 + px * 1.5, r)

	# Mirror of the shader: screen +y is down, the globe's +y is up (see the
	# surface-normal comment in shaders/globe_planet.gdshader).
	var n := Vector3(p.x / radius, -p.y / radius, sqrt(maxf(0.0, 1.0 - r * r))).normalized()
	var phi0 := deg_to_rad(center_lat)
	var sin_phi := clampf(n.y * cos(phi0) + n.z * sin(phi0), -1.0, 1.0)
	var phi := asin(sin_phi)
	var lam := atan2(n.x, n.z * cos(phi0) - n.y * sin(phi0))
	var lat_deg := rad_to_deg(phi)
	var lon_deg := rad_to_deg(lam) + center_lon

	var mask_size := Vector2(_mask.get_width(), _mask.get_height())
	var half_row := 0.5 / mask_size.y
	var mask_uv := Vector2((lon_deg + 180.0) / 360.0, clampf(0.5 - lat_deg / 180.0, half_row, 1.0 - half_row))
	var land := _mask_at(mask_uv)
	# One raster pixel is about one screen pixel here, so the analytic coast
	# width comes from the view instead of fwidth().
	var texel := maxf(2.0 / mask_size.x, 2.0 * px * 57.29578 / 360.0)
	var coast_aa := clampf(texel * 0.8, 1.0 / mask_size.x, 0.35)
	var land_a := smoothstep(0.5 - coast_aa, 0.5 + coast_aa, land)
	var px_deg := px * 57.29578
	var probe := maxf(texel * 2.0, px_deg / 360.0 * 3.0)
	var probe_lat_lo := clampf(mask_uv.y - probe, half_row, 1.0 - half_row)
	var probe_lat_hi := clampf(mask_uv.y + probe, half_row, 1.0 - half_row)
	var sample_east := _mask_at(Vector2(mask_uv.x + probe, mask_uv.y))
	var sample_west := _mask_at(Vector2(mask_uv.x - probe, mask_uv.y))
	var sample_north := _mask_at(Vector2(mask_uv.x, probe_lat_hi))
	var sample_south := _mask_at(Vector2(mask_uv.x, probe_lat_lo))
	var near_land := maxf(maxf(sample_east, sample_west), maxf(sample_north, sample_south))
	var near_water := 1.0 - minf(minf(sample_east, sample_west), minf(sample_north, sample_south))
	var shelf := clampf((near_land - land_a) * (1.0 - land_a), 0.0, 1.0)

	var rel_freq := 5.5
	var cloud_freq := 8.0
	var lam_abs := deg_to_rad(lon_deg)
	var phi_abs := deg_to_rad(lat_deg)
	var globe_normal := Vector3(cos(phi_abs) * sin(lam_abs), sin(phi_abs), cos(phi_abs) * cos(lam_abs))
	var relief := clampf(_fbm(globe_normal * rel_freq) * 1.30 - 0.15, 0.0, 1.0)
	var depth := clampf(1.0 - near_land, 0.0, 1.0)
	var ocean := _u4("ocean_shallow").lerp(_u4("ocean_deep"), smoothstep(0.0, 0.5, depth))
	ocean = ocean.lerp(_u4("ocean_mid"), 0.35)
	ocean = ocean.lerp(_u4("shore_color"), _uf("coast_glow") * shelf)

	var land_rgb := _u4("land_low").lerp(_u4("land_mid"), 0.45 + 0.55 * relief)
	land_rgb = land_rgb.lerp(_u4("land_high"), smoothstep(0.55, 0.95, relief) * _uf("relief_strength") * 0.8)
	var abs_lat := absf(lat_deg)
	var arid_band := smoothstep(10.0, 19.0, abs_lat) * (1.0 - smoothstep(27.0, 38.0, abs_lat))
	var arid := clampf(arid_band * (relief * 1.6 - 0.25), 0.0, 1.0) * _uf("biome_strength")
	land_rgb = land_rgb.lerp(_u4("land_dry"), arid)
	land_rgb = land_rgb.lerp(_u4("land_beach"), clampf(near_water * land_a, 0.0, 1.0) * 0.35)
	var ice := smoothstep(67.0, 78.0, abs_lat + (relief - 0.5) * 8.0) * _uf("ice_strength")
	land_rgb = land_rgb.lerp(_u4("ice_color"), clampf(ice, 0.0, 1.0))
	var albedo := ocean.lerp(land_rgb, land_a)

	var light := _u3("light_dir").normalized()
	var ndl := n.dot(light)
	var day := smoothstep(-_uf("terminator_softness"), _uf("terminator_softness"), ndl)
	var luminance := _uf("ambient_floor") + (1.0 - _uf("ambient_floor")) * clampf(ndl, 0.0, 1.0)
	var planet := Color(albedo.r * luminance, albedo.g * luminance, albedo.b * luminance)
	var tint := _u4("night_tint").lerp(_u4("day_tint"), day)
	planet = Color(planet.r * tint.r, planet.g * tint.g, planet.b * tint.b)
	var half_vector := (light + Vector3(0, 0, 1)).normalized()
	var specular := pow(maxf(n.dot(half_vector), 0.0), _uf("specular_sharpness")) \
		* _uf("specular_strength") * day * (1.0 - land_a)
	planet = Color(planet.r + specular, planet.g + specular, planet.b + specular)

	var limb := pow(1.0 - clampf(n.z, 0.0, 1.0), 3.0)
	planet = planet.lerp(_u4("atmosphere_color"), limb * _uf("limb_haze"))

	var cloud := _fbm(globe_normal * cloud_freq + Vector3(31.0, 17.0, 5.0))
	var cover := smoothstep(0.54, 0.80, cloud) * _uf("cloud_amount") * (1.0 - ice * 0.6)
	var cloud_rgb := _u4("cloud_color")
	var cloud_scale := (0.45 + 0.55 * luminance) * lerpf(0.5, 1.0, day)
	planet = planet.lerp(Color(cloud_rgb.r * cloud_scale, cloud_rgb.g * cloud_scale, cloud_rgb.b * cloud_scale),
		clampf(cover, 0.0, 1.0))

	var graticule_alpha := _uf("graticule_alpha")
	if graticule_alpha > 0.0:
		var step := _uf("graticule_step_deg")
		var gx := absf(fposmod(lon_deg / step + 0.5, 1.0) - 0.5) * step
		var gy := absf(fposmod(lat_deg / step + 0.5, 1.0) - 0.5) * step
		var line_width := maxf(0.7 * maxf(rad_to_deg(px), rad_to_deg(px)), 0.02)
		var lines := 1.0 - smoothstep(0.0, line_width, minf(gx, gy))
		lines *= 1.0 - smoothstep(80.0, 88.0, abs_lat)
		planet = planet.lerp(Color(1, 1, 1), lines * graticule_alpha * (0.3 + 0.7 * day))

	var rim_normal := Vector3(p.x, -p.y, 0.0) / maxf(p.length(), 0.0001)
	var rim_light := 0.45 + 0.55 * smoothstep(-0.35, 0.45, rim_normal.dot(light))
	var glow := pow(clampf(1.0 - (r - 1.0) / maxf(halo_scale - 1.0, 0.001), 0.0, 1.0), 2.6)
	var halo := _u4("atmosphere_color")
	halo = Color(halo.r * (1.0 + 0.25 * rim_light), halo.g * (1.0 + 0.25 * rim_light), halo.b * (1.0 + 0.25 * rim_light))
	var out_color := halo.lerp(planet, body)
	var out_alpha := clampf(lerpf(glow * _uf("atmosphere_strength") * rim_light, 1.0, body), 0.0, 1.0)
	return Color(out_color.r, out_color.g, out_color.b, out_alpha)

## The shader's screen -> lon/lat inverse has to be the exact inverse of the
## projection GlobeMap draws its pins with: if the two disagree, the mask
## renders mirrored and the pins slide off their destinations as the globe
## turns. The shader's own vertical sign is read out of the shader source, so
## this checks the shader rather than a copy of it.
func _report_projection_round_trip() -> void:
	var y_sign := _shader_vertical_sign()
	if y_sign == 0.0:
		print("PROJECTION: FAIL - could not find the shader's surface-normal line")
		return
	var radius := 400.0
	var checked := 0
	var worst := 0.0
	for view in [[-40.0, 30.0], [-40.0, 0.0], [120.0, -40.0], [0.0, 78.0], [0.0, -78.0]]:
		for def in WorldLocations.get_all():
			var v := GlobeMap.project_point(float(def["lon"]), float(def["lat"]), view[0], view[1])
			if v.z <= 0.0:
				continue
			# Where the pin is drawn, and what the shader reads back at that
			# pixel (through the same normal the shader builds).
			var offset := Vector2(v.x, -v.y) * radius
			var z := sqrt(maxf(0.0, 1.0 - offset.length_squared() / (radius * radius)))
			var recovered := _recover_lon_lat(
				Vector3(offset.x / radius, y_sign * offset.y / radius, z), view[0], view[1])
			var lon_error := absf(fposmod(recovered.x - float(def["lon"]) + 180.0, 360.0) - 180.0)
			var lat_error := absf(recovered.y - float(def["lat"]))
			worst = maxf(worst, maxf(lon_error, lat_error))
			checked += 1
	print("PROJECTION: %s - %d destinations round-trip, worst error %.4f deg" % [
		"PASS" if worst < 0.01 else "FAIL", checked, worst])

## The sign the shader gives the screen-space vertical axis when it builds the
## surface normal.
func _shader_vertical_sign() -> float:
	for line in FileAccess.get_file_as_string(SHADER_PATH).split("\n"):
		if line.contains("vec3 n = vec3(p.x / radius,"):
			return -1.0 if line.contains("-p.y / radius") else 1.0
	return 0.0

## The shader's lon_lat_for(), as GDScript.
func _recover_lon_lat(n: Vector3, center_lon: float, center_lat: float) -> Vector2:
	n = n.normalized()
	var phi0 := deg_to_rad(center_lat)
	var sin_phi := clampf(n.y * cos(phi0) + n.z * sin(phi0), -1.0, 1.0)
	var lam := atan2(n.x, n.z * cos(phi0) - n.y * sin(phi0))
	return Vector2(rad_to_deg(lam) + center_lon, rad_to_deg(asin(sin_phi)))

## Draw every destination GlobeMap would pin, at the position its own
## projection puts it: the quickest way to see whether the mask and the pins
## agree. A few landmarks get a gold ring so they are easy to find.
func _draw_pins(img: Image, view_size: Vector2, center_lon: float, center_lat: float) -> int:
	var landmarks := ["scotland", "japan", "australia", "monterey", "south_africa"]
	var radius := maxf(minf(view_size.x, view_size.y) * 0.5 * _uf("sphere_fill") * _uf("radius_scale"), 1.0)
	var center := view_size * 0.5
	var drawn := 0
	for def in WorldLocations.get_all():
		var v := GlobeMap.project_point(float(def["lon"]), float(def["lat"]), center_lon, center_lat)
		if v.z <= 0.02:
			continue
		var pos := center + Vector2(v.x, -v.y) * radius
		if landmarks.has(str(def["id"])):
			_fill_circle(img, pos, 9.0, Color(0.90, 0.77, 0.49))
			print("  gold pin %-13s at %s" % [def["id"], pos])
		_fill_circle(img, pos, 6.0, Color(0.03, 0.05, 0.04, 0.85))
		_fill_circle(img, pos, 4.0, Color(0.97, 0.96, 0.92))
		drawn += 1
	return drawn

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
