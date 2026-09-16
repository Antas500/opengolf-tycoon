shader_type canvas_item;

// --- Heightmap input ---
uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform vec2 heightmap_size = vec2(512.0, 512.0);
uniform vec2 grid_size = vec2(128.0, 128.0);

// --- Isometric grid geometry ---
uniform vec2 tile_size = vec2(64.0, 32.0);

// --- Lighting ---
uniform vec2 light_direction = vec2(-0.7, -0.7);  // NW, normalized
uniform float light_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float shadow_intensity : hint_range(0.0, 1.0) = 0.4;

// --- Debug ---
uniform bool debug_heightmap = false;  // Set true to visualize raw heightmap data

// --- Contour lines ---
uniform bool contour_enabled = true;
uniform float contour_line_width = 1.5;  // In world pixels
uniform float contour_opacity : hint_range(0.0, 1.0) = 0.3;
uniform vec3 contour_color_high = vec3(0.45, 0.35, 0.25);  // Warm brown
uniform vec3 contour_color_low = vec3(0.25, 0.30, 0.40);   // Cool blue-gray

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

// Convert world position to heightmap UV
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
		return 0.5;  // Sea level for out-of-bounds
	}
	return texture(heightmap, uv).r;
}

// Compute pseudo-normal from heightmap gradient using central differences
vec3 compute_normal(vec2 wp, out float slope_mag) {
	vec2 step_x = grid_axis_x * 0.25;
	vec2 step_y = grid_axis_y * 0.25;

	float h_l = sample_height(wp - step_x);
	float h_r = sample_height(wp + step_x);
	float h_u = sample_height(wp - step_y);
	float h_d = sample_height(wp + step_y);

	// Scale for visible slopes — more = steeper perceived hills
	float height_scale = 8.0;
	float dx = (h_r - h_l) * height_scale;
	float dy = (h_d - h_u) * height_scale;

	slope_mag = length(vec2(dx, dy));
	return normalize(vec3(-dx, -dy, 1.0));
}

// Compute ambient occlusion from heightmap curvature (Laplacian)
// Concavities (valleys) return positive values, convexities (ridges) return negative
float compute_ao(vec2 wp, float center_height) {
	vec2 step_x = grid_axis_x * 0.25;
	vec2 step_y = grid_axis_y * 0.25;

	float h_l = sample_height(wp - step_x);
	float h_r = sample_height(wp + step_x);
	float h_u = sample_height(wp - step_y);
	float h_d = sample_height(wp + step_y);

	// Laplacian: sum of neighbors minus 4x center
	// Positive = valley (concave), negative = ridge (convex)
	float laplacian = (h_l + h_r + h_u + h_d) - 4.0 * center_height;
	return laplacian * 40.0;  // Scale for visibility
}

void fragment() {
	vec2 uv = world_to_uv(world_pos);
	float height = sample_height(world_pos);
	float rel_height = height - 0.5;

	bool in_bounds = uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;

	if (!in_bounds) {
		COLOR = vec4(0.0);
	} else if (debug_heightmap) {
		if (abs(rel_height) > 0.005) {
			if (rel_height > 0.0) {
				COLOR = vec4(1.0, 0.0, 1.0, 0.6);
			} else {
				COLOR = vec4(0.0, 1.0, 1.0, 0.6);
			}
		} else {
			float grid_line = step(0.98, fract(uv.x * grid_size.x)) + step(0.98, fract(uv.y * grid_size.y));
			COLOR = vec4(0.0, 1.0, 0.0, grid_line * 0.15);
		}
	} else {
		// --- Continuous directional lighting ---
		float slope_mag = 0.0;
		vec3 normal = compute_normal(world_pos, slope_mag);
		vec3 light_dir_3d = normalize(vec3(light_direction, 0.6));
		float ndotl = dot(normal, light_dir_3d);
		float lighting = ndotl * 0.5 + 0.5;

		// Shade range: shadow_intensity below neutral, light_intensity above
		float shade = mix(1.0 - shadow_intensity, 1.0 + light_intensity, lighting);

		float alpha = 0.0;
		vec3 out_color = vec3(1.0);


		// Cap alpha to keep terrain readable underneath
		COLOR = vec4(out_color, clamp(alpha, 0.0, 0.75));
	}
}
