shader_type canvas_item;

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform vec2 heightmap_size = vec2(512.0, 512.0);
uniform vec2 grid_size = vec2(128.0, 128.0);
uniform vec2 tile_size = vec2(64.0, 32.0);

uniform vec2 light_direction = vec2(-0.7, -0.7);
uniform float light_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float shadow_intensity : hint_range(0.0, 1.0) = 0.4;

uniform bool contour_enabled = true;
uniform float contour_line_width = 1.5;
uniform float contour_opacity : hint_range(0.0, 1.0) = 0.3;

uniform vec2 grid_origin = vec2(0.0);
uniform vec2 grid_axis_x = vec2(64.0, 32.0);
uniform vec2 grid_axis_y = vec2(0.0, 32.0);
uniform vec2 surface_origin = vec2(0.0);
uniform float elevation_step_y = 10.0;
uniform bool is_isometric = true;

varying vec2 world_pos;

void vertex() {
	world_pos = VERTEX + surface_origin;
}

vec2 world_to_uv(vec2 wp) {
	vec2 d = wp - grid_origin;
	float det = grid_axis_x.x * grid_axis_y.y - grid_axis_y.x * grid_axis_x.y;
	if (abs(det) < 0.000001) {
		return vec2(-1.0);
	}
	vec2 g = vec2(
		(d.x * grid_axis_y.y - grid_axis_y.x * d.y) / det,
		(grid_axis_x.x * d.y - grid_axis_x.y * d.x) / det);

	if (is_isometric && elevation_step_y > 0.0) {
		for (int i = 0; i < 4; i++) {
			vec2 uv_samp = g / grid_size;
			float h = (texture(heightmap, clamp(uv_samp, vec2(0.0), vec2(1.0))).r - 0.5) * 10.0;
			vec2 d2 = (wp + vec2(0.0, h * elevation_step_y)) - grid_origin;
			g = vec2(
				(d2.x * grid_axis_y.y - grid_axis_y.x * d2.y) / det,
				(grid_axis_x.x * d2.y - grid_axis_y.x * d2.x) / det);
		}
	}
	return g / grid_size;
}

float sample_height(vec2 wp) {
	vec2 uv = world_to_uv(wp);
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 0.5;
	}
	return texture(heightmap, uv).r;
}

void fragment() {
	vec2 uv = world_to_uv(world_pos);
	float height = sample_height(world_pos);
	float rel_height = height - 0.5;
	bool in_bounds = uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;

	if (!in_bounds) {
		COLOR = vec4(0.0);
	} else {
		vec2 step_x = grid_axis_x * 0.25;
		vec2 step_y = grid_axis_y * 0.25;

		// Forward differences (2 samples for web perf) + extra 2 for AO
		float h_r = sample_height(world_pos + step_x);
		float h_d = sample_height(world_pos + step_y);
		float h_l = sample_height(world_pos - step_x);
		float h_u = sample_height(world_pos - step_y);

		float dx = (h_r - h_l) * 8.0;
		float dy = (h_d - h_u) * 8.0;
		float slope_mag = length(vec2(dx, dy));
		vec3 normal = normalize(vec3(-dx, -dy, 1.0));

		vec3 light_dir_3d = normalize(vec3(light_direction, 0.6));
		float ndotl = dot(normal, light_dir_3d) * 0.5 + 0.5;

		float lighting = ndotl;
		float shade = mix(1.0 - shadow_intensity, 1.0 + light_intensity, lighting);

		float alpha = 0.0;
		vec3 out_color = vec3(1.0);

		COLOR = vec4(out_color, clamp(alpha, 0.0, 0.75));
	}
}
