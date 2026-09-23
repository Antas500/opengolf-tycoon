shader_type canvas_item;
// Receive the same day/night CanvasModulate as course objects.

// Shared by desktop and WebGL 2. No screen reads or per-tile draw calls.
uniform sampler2D terrain_data : filter_nearest, repeat_disable;
uniform sampler2D vertex_elevation : filter_linear, repeat_disable;
uniform vec2 vertex_grid_size = vec2(129.0);
uniform vec2 relief_light = vec2(-0.6, -0.8);
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform vec2 grid_size = vec2(128.0);
uniform vec2 tile_size = vec2(64.0, 32.0);
uniform vec4 fringe_color : source_color = vec4(0.38, 0.65, 0.28, 1.0);

uniform float elevation_step_y = 10.0;
uniform bool is_isometric = true;

uniform vec2 grid_origin = vec2(0.0);
uniform vec2 grid_axis_x = vec2(64.0, 32.0);
uniform vec2 grid_axis_y = vec2(0.0, 32.0);
uniform vec2 surface_origin = vec2(0.0);
uniform vec2 surface_size = vec2(8192.0, 4096.0);

vec2 world_to_grid(vec2 world) {
	vec2 d = world - grid_origin;
	float det = grid_axis_x.x * grid_axis_y.y - grid_axis_y.x * grid_axis_x.y;
	if (abs(det) < 0.000001) {
		return vec2(-1.0);
	}
	return vec2(
		(d.x * grid_axis_y.y - grid_axis_y.x * d.y) / det,
		(grid_axis_x.x * d.y - grid_axis_x.y * d.x) / det);
}

float elevation_at_grid(vec2 g) {
	vec2 uv = (g + 0.5) / vertex_grid_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	return (texture(vertex_elevation, uv).r - 0.5) * 10.0;
}

float elevation_at(vec2 world) {
	vec2 g = world_to_grid(world);
	vec2 uv = (g + 0.5) / vertex_grid_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.5;
	}
	return texture(vertex_elevation, uv).r;
}

float hash(vec2 p) {
	// Keep intermediates small: large sin hashes form bands on mobile/GL drivers.
	vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), u.x), u.y);
}

vec2 tile_at(vec2 p) {
	vec2 data = texture(terrain_data, (clamp(p, vec2(0.0), grid_size - 1.0) + 0.5) / grid_size).rg;
	float id = floor(data.r * 255.0 + 0.5);
	// Object tiles share the surrounding native turf; sprites supply the object.
	if (id == 11.0 || id == 13.0) { id = 1.0; }
	return vec2(id, data.g);
}

vec3 surface(float id, float cover, float depth, vec2 world, float grain, float patch) {
	vec3 base = texture(palette, vec2((id + 0.5) / 14.0, 0.5)).rgb;
	float variation = (patch - 0.5) * 0.13 + (grain - 0.5) * 0.075;
	float edge = 1.0 - smoothstep(0.50, 0.68, cover);
	if (id == 2.0 || id == 6.0) {
		// Broad diagonal mower passes continue across every tile boundary.
		float pass = sin((world.x + world.y * 1.7) * 0.078);
		float stripe = smoothstep(-0.15, 0.15, pass);
		base *= 0.97 + stripe * 0.035;
		variation *= 0.55;
		float cut_line = 1.0 - smoothstep(0.50, 0.53, cover);
		base *= 1.0 - edge * 0.14 - cut_line * 0.08;
	} else if (id == 5.0) {
		float stripe = smoothstep(-0.2, 0.2, sin((world.x - world.y * 1.5) * 0.10));
		base *= 0.98 + stripe * 0.035;
		base = mix(base, fringe_color.rgb, edge * 0.92);
		variation *= 0.18;
	} else if (id == 7.0) {
		// Recessed sand with a grass lip, warm bowl, and fine rake marks.
		base = mix(base * 1.12, vec3(0.35, 0.40, 0.24), edge * 0.78);
		base *= 1.0 - depth * 0.12;
		float rake = sin(world.y * 1.15 + sin(world.x * 0.022) * 3.0);
		variation = (grain - 0.5) * 0.06 + rake * 0.012;
	} else if (id == 8.0) {
		// Calm deep water, pale shallows, and sparse moving reflected light.
		base *= 0.76 + patch * 0.10;
		base = mix(base, vec3(0.32, 0.66, 0.63), 0.48);
		base = mix(base, vec3(0.83, 0.81, 0.59), edge * 0.92);
		float wave = sin(world.y * 0.16 + sin(world.x * 0.024 + TIME * 0.3) * 2.3 + TIME * 0.8);
		float glint = smoothstep(0.95, 1.0, wave) * smoothstep(0.55, 0.78, noise(world * 0.04 + vec2(TIME * 0.07, 0.0)));
		base += vec3(0.30, 0.39, 0.33) * glint * 0.25;
		variation = 0.0;
	} else if (id == 9.0) {
		variation = (grain - 0.5) * 0.045;
		base *= 1.0 - edge * 0.13;
	} else if (id == 3.0 || id == 4.0 || id == 1.0) {
		// Small irregular tufts, with larger color masses at landscape scale.
		variation += (noise(world * vec2(0.32, 0.65)) - 0.5) * 0.045;
	}
	return clamp(base + vec3(variation * 0.78, variation, variation * 0.48), vec3(0.0), vec3(1.0));
}

void fragment() {
	vec2 world = surface_origin + UV * surface_size;
	vec2 p = world_to_grid(world);
	if (is_isometric && elevation_step_y > 0.0) {
		for (int iter = 0; iter < 4; iter++) {
			float h = elevation_at_grid(p);
			p = world_to_grid(world + vec2(0.0, h * elevation_step_y));
		}
	}
	if (p.x < 0.0 || p.y < 0.0 || p.x > grid_size.x || p.y > grid_size.y) {
		COLOR = vec4(0.0);
	} else {
		vec2 tile_world = p * tile_size;
		// A restrained contour perturbation breaks stair steps without moving tile centers.
		vec2 warp = vec2(noise(p * 0.72), noise(p * 0.72 + 37.0)) - 0.5;
		vec2 sample_pos = p + warp * 0.08;
		vec2 cell = floor(sample_pos);
		vec2 f = fract(sample_pos);
		vec2 a = tile_at(cell);
		vec2 t_e = tile_at(cell + vec2(1.0, 0.0));
		vec2 t_s = tile_at(cell + vec2(0.0, 1.0));
		vec2 t_w = tile_at(cell + vec2(-1.0, 0.0));
		vec2 t_n = tile_at(cell + vec2(0.0, -1.0));

		// Material boundaries sit on the shared tile edges inside a narrow
		// anti-aliased band. The old bilinear coverage field made the boundary
		// of an isolated tile bulge outward into a rounded blob; edge-aligned
		// bands keep every tile's full square footprint.
		const float AA = 0.04;     // Half width of the anti-aliased boundary.
		const float FRINGE = 0.30; // Half width of the edge-treatment band.
		float d_e = f.x - 1.0;
		float d_w = -f.x;
		float d_s = f.y - 1.0;
		float d_n = -f.y;
		float m_e = step(0.5, abs(a.x - t_e.x)) * smoothstep(-AA, AA, d_e);
		float m_w = step(0.5, abs(a.x - t_w.x)) * smoothstep(-AA, AA, d_w);
		float m_s = step(0.5, abs(a.x - t_s.x)) * smoothstep(-AA, AA, d_s);
		float m_n = step(0.5, abs(a.x - t_n.x)) * smoothstep(-AA, AA, d_n);

		float w_c = (1.0 - m_e) * (1.0 - m_w) * (1.0 - m_s) * (1.0 - m_n);
		float w_e = m_e * (1.0 - m_w) * (1.0 - m_s) * (1.0 - m_n);
		float w_s = m_s * (1.0 - m_w) * (1.0 - m_e) * (1.0 - m_n);
		float w_w = m_w * (1.0 - m_e) * (1.0 - m_s) * (1.0 - m_n);
		float w_n = m_n * (1.0 - m_w) * (1.0 - m_s) * (1.0 - m_e);

		// Coverage for edge treatments (fringe, lip, shoreline): 1 well inside
		// the tile, fading across the boundary band. Square, like the boundary.
		float c_e = step(0.5, abs(a.x - t_e.x)) * smoothstep(-FRINGE, FRINGE, d_e);
		float c_w = step(0.5, abs(a.x - t_w.x)) * smoothstep(-FRINGE, FRINGE, d_w);
		float c_s = step(0.5, abs(a.x - t_s.x)) * smoothstep(-FRINGE, FRINGE, d_s);
		float c_n = step(0.5, abs(a.x - t_n.x)) * smoothstep(-FRINGE, FRINGE, d_n);
		float cov_c = (1.0 - c_e) * (1.0 - c_w) * (1.0 - c_s) * (1.0 - c_n);
		float cov_e = 1.0 - step(0.5, abs(a.x - t_e.x)) * (1.0 - smoothstep(-FRINGE, FRINGE, d_e));
		float cov_s = 1.0 - step(0.5, abs(a.x - t_s.x)) * (1.0 - smoothstep(-FRINGE, FRINGE, d_s));
		float cov_w = 1.0 - step(0.5, abs(a.x - t_w.x)) * (1.0 - smoothstep(-FRINGE, FRINGE, d_w));
		float cov_n = 1.0 - step(0.5, abs(a.x - t_n.x)) * (1.0 - smoothstep(-FRINGE, FRINGE, d_n));

		float grain = hash(floor(tile_world));
		float patch = noise(tile_world * 0.009) * 0.65 + noise(tile_world * 0.035) * 0.35;
		float w_sum = w_c + w_e + w_s + w_w + w_n;
		vec3 color = (surface(a.x, cov_c, a.y, tile_world, grain, patch) * w_c
			+ surface(t_e.x, cov_e, t_e.y, tile_world, grain, patch) * w_e
			+ surface(t_s.x, cov_s, t_s.y, tile_world, grain, patch) * w_s
			+ surface(t_w.x, cov_w, t_w.y, tile_world, grain, patch) * w_w
			+ surface(t_n.x, cov_n, t_n.y, tile_world, grain, patch) * w_n)
			/ max(w_sum, 0.0001);
		// Elevation slopes & 3D relief normal
		float left_h = elevation_at_grid(p - vec2(0.6, 0.0));
		float right_h = elevation_at_grid(p + vec2(0.6, 0.0));
		float up_h = elevation_at_grid(p - vec2(0.0, 0.6));
		float down_h = elevation_at_grid(p + vec2(0.0, 0.6));
		float dh_x = (right_h - left_h) * (elevation_step_y * 0.8);
		float dh_y = (down_h - up_h) * (elevation_step_y * 0.8);
		float det = grid_axis_x.x * grid_axis_y.y - grid_axis_y.x * grid_axis_x.y;
		vec3 normal = vec3(
			(grid_axis_x.y * dh_y - grid_axis_y.y * dh_x) / det,
			(grid_axis_y.x * dh_x - grid_axis_x.x * dh_y) / det,
			1.0
		);
		normal = normalize(normal);
		vec3 sunlight = normalize(vec3(relief_light, 1.3));
		float ndotl = dot(normal, sunlight);
		float relief = clamp(1.0 + (dot(normal, sunlight) - sunlight.z) * 0.28, 0.84, 1.08);

		COLOR = vec4(color * relief, 1.0);
	}
}
