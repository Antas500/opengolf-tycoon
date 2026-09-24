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

// Terrain ids (TerrainTypes.Type) with looks of their own below.
const float T_ROCKS = 13.0;
const float T_FIRM_FAIRWAY = 14.0;
const float T_POT_BUNKER = 15.0;
const float T_STREAM = 16.0;
const float T_DEEP_ROUGH = 17.0;
const float T_WASTE_BUNKER = 18.0;
const float T_BRUSH = 19.0;
// Light direction on the ground plane, in grid units (screen upper left).
const vec2 GROUND_LIGHT = vec2(-0.83, -0.55);

vec2 tile_at(vec2 p) {
	vec4 data = texture(terrain_data, (clamp(p, vec2(0.0), grid_size - 1.0) + 0.5) / grid_size);
	float id = floor(data.r * 255.0 + 0.5);
	// Object tiles share the surrounding native turf; sprites supply the object.
	// Trees always do; a boulder does when it stands on other ground (A = 0),
	// while painted Rocks ground (A = 1) draws as stony ground.
	if (id == 11.0 || (id == T_ROCKS && data.a < 0.5)) { id = 1.0; }
	return vec2(id, data.g);
}

// Boundary class: a stream joins a pond without a shoreline between them.
float boundary_class(float id) {
	return id == T_STREAM ? 8.0 : id;
}

// 1 where two tiles need a material boundary between them.
float differs(float a, float b) {
	return step(0.5, abs(boundary_class(a) - boundary_class(b)));
}

// Grass surfaces that other terrain can sit on.
bool is_turf(float id) {
	return id == 1.0 || id == 2.0 || id == 3.0 || id == 4.0 || id == T_FIRM_FAIRWAY || id == T_DEEP_ROUGH;
}

// Terrain drawn as features (stones, shrubs, a pot, a channel, a sandy
// scrape) over whatever turf surrounds it, so a patch has a natural outline
// instead of a square one.
bool is_inset(float id) {
	return id == T_ROCKS || id == T_POT_BUNKER || id == T_STREAM || id == T_WASTE_BUNKER || id == T_BRUSH;
}

// Whether stones or shrubs on `id` can sit directly on neighbouring `ground`:
// any turf, and the sand of a waste bunker.
bool carries(float ground, float id) {
	return is_turf(ground) || (ground == T_WASTE_BUNKER && (id == T_ROCKS || id == T_BRUSH));
}

// Whether a tile of type `own` draws a boundary against its neighbour `other`.
// Turf runs straight into inset terrain, which draws its own margin over that
// turf (and a waste bunker's sand runs under neighbouring stones and shrubs).
float edge_between(float own, float other) {
	return (is_inset(other) && carries(own, other)) ? 0.0 : differs(own, other);
}

vec3 palette_color(float id) {
	// The palette holds one texel per terrain id; its width is the id count.
	float count = float(textureSize(palette, 0).x);
	return texture(palette, vec2((id + 0.5) / count, 0.5)).rgb;
}

// Polynomial smooth minimum: rounds the inside corner where two shapes meet.
float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Cellular noise over grid-space `x`. Returns vec4(distance to the nearest
// feature point, distance to the cell border (F2 - F1), random id of the
// nearest cell, 0); `to_point` is the offset from `x` to that feature point.
vec4 cells(vec2 x, out vec2 to_point) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	float f1 = 8.0;
	float f2 = 8.0;
	vec2 nearest = n;
	to_point = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 b = vec2(float(i), float(j));
			vec2 o = vec2(hash(n + b), hash(n + b + vec2(17.3, 5.1))) * 0.8 + 0.1;
			vec2 r = b + o - f;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				nearest = n + b;
				to_point = r;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec4(sqrt(f1), sqrt(f2) - sqrt(f1), hash(nearest + vec2(3.7, 9.2)), 0.0);
}

// Sparse round dots (pebbles, blossoms): `density` of cells get one dot.
float dots(vec2 x, float density, float radius) {
	vec2 n = floor(x);
	vec2 o = vec2(hash(n + vec2(41.0, 7.0)), hash(n + vec2(3.0, 59.0))) * 0.5 + 0.25;
	float d = length(fract(x) - o);
	return (1.0 - smoothstep(radius * 0.6, radius, d)) * step(1.0 - density, hash(n + vec2(11.0, 23.0)));
}

vec3 surface(float id, float cover, float depth, vec2 world, float grain, float patch) {
	vec3 base = palette_color(id);
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
	} else if (id == T_FIRM_FAIRWAY) {
		// Fast links turf: the fairway's mower passes, paler, with sun-dried
		// straw patches.
		float pass = sin((world.x + world.y * 1.7) * 0.078);
		float stripe = smoothstep(-0.15, 0.15, pass);
		base *= 0.965 + stripe * 0.05;
		float dry = smoothstep(0.52, 0.8, noise(world * 0.03 + vec2(11.0, 4.0)));
		base = mix(base, base * vec3(1.08, 1.04, 0.86), dry * 0.5);
		variation *= 0.55;
		float cut_line = 1.0 - smoothstep(0.50, 0.53, cover);
		base *= 1.0 - edge * 0.12 - cut_line * 0.07;
	} else if (id == T_POT_BUNKER) {
		// The pot's sand floor; inset_tile() adds the wall and the lip.
		variation = (grain - 0.5) * 0.05;
	} else if (id == T_STREAM) {
		// Stream banks: lush native grass; inset_tile() adds the water.
		base = palette_color(1.0) * vec3(0.94, 0.98, 0.94);
		variation += (noise(world * vec2(0.32, 0.65)) - 0.5) * 0.05;
	} else if (id == T_DEEP_ROUGH) {
		// Knee-high grass: long blades standing up the screen (grid x + y),
		// darker clumps, and pale seed heads.
		vec2 g = world / tile_size;
		float u = g.x - g.y;
		float v = g.x + g.y;
		float blades = noise(vec2(u * 26.0, v * 3.2 + noise(vec2(u * 3.0, v * 2.0)) * 1.6));
		float clump = noise(g * 2.2 + vec2(5.0, 1.0));
		base *= 0.80 + blades * 0.34 + (clump - 0.5) * 0.16;
		float heads = dots(vec2(u * 12.0, v * 7.0), 0.22, 0.28);
		base = mix(base, base * vec3(1.45, 1.38, 0.96), heads * 0.55);
		variation *= 0.45;
	} else if (id == T_WASTE_BUNKER) {
		// Coarse unraked sand with grit, pebbles, and a few wiregrass tufts;
		// inset_tile() breaks the edge up into the surrounding turf.
		vec2 g = world / tile_size;
		base *= 0.92 + hash(floor(g * 40.0)) * 0.1 + (noise(g * 3.0) - 0.5) * 0.08;
		float pebbles = dots(g * 11.0, 0.4, 0.3);
		base = mix(base, base * vec3(0.62, 0.6, 0.58), pebbles * 0.8);
		base = mix(base, base * vec3(1.12, 1.1, 1.06), dots(g * 17.0, 0.3, 0.25) * 0.6);
		float tuft = dots(g * 4.5 + vec2(3.0, 8.0), 0.22, 0.42 + noise(g * 9.0) * 0.12);
		base = mix(base, palette_color(1.0) * (0.62 + noise(g * 26.0) * 0.3), tuft * 0.9);
		variation = (grain - 0.5) * 0.04;
	} else if (id == T_ROCKS) {
		// Earth and gravel between the stones inset_tile() draws.
		vec2 g = world / tile_size;
		base = mix(base * 0.66, vec3(0.43, 0.37, 0.29), 0.45) * (0.9 + noise(g * 9.0) * 0.18);
		variation = (grain - 0.5) * 0.05;
	} else if (id == T_BRUSH) {
		// Shaded leaf litter under the shrubs inset_tile() draws.
		vec2 g = world / tile_size;
		base *= 0.58 + noise(g * 12.0) * 0.12;
		variation *= 0.3;
	}
	return clamp(base + vec3(variation * 0.78, variation, variation * 0.48), vec3(0.0), vec3(1.0));
}

float is_wet(float id) {
	return (id == 8.0 || id == T_STREAM) ? 1.0 : 0.0;
}

// Distance from `q` (tile-local, 0..1) to the skeleton joining the tile
// center to each linked edge (e/s/w/n = 1 when linked). A corner with one
// horizontal and one vertical link is a quarter arc, so stepped lines of
// tiles read as smooth curves. `along_y` is 1 where the local run is
// north-south. An unlinked tile is a single round spot.
float link_distance(vec2 q, float e, float s, float w, float n, out float along_y) {
	float links = e + s + w + n;
	along_y = 0.0;
	if (links < 0.5) {
		return length(q - vec2(0.5));
	}
	if (links > 1.5 && links < 2.5 && e + w > 0.5 && e + w < 1.5) {
		vec2 corner = vec2(e, s);
		along_y = step(abs(q.y - corner.y), abs(q.x - corner.x));
		return abs(length(q - corner) - 0.5);
	}
	float run_x = 9.0;
	float run_y = 9.0;
	if (e > 0.5) { run_x = min(run_x, segment_distance(q, vec2(0.5), vec2(1.0, 0.5))); }
	if (w > 0.5) { run_x = min(run_x, segment_distance(q, vec2(0.5), vec2(0.0, 0.5))); }
	if (s > 0.5) { run_y = min(run_y, segment_distance(q, vec2(0.5), vec2(0.5, 1.0))); }
	if (n > 0.5) { run_y = min(run_y, segment_distance(q, vec2(0.5), vec2(0.5, 0.0))); }
	along_y = step(run_y, run_x);
	return smin(run_x, run_y, 0.12);
}

// 1 when the quadrant of the tile holding `q` belongs to a 2x2 block of linked
// tiles, which fills solid instead of showing a gap between the runs.
float corner_filled(vec2 q, vec2 cell, float e, float s, float w, float n, float self_id) {
	vec2 quadrant = step(vec2(0.5), q);
	float side_x = quadrant.x > 0.5 ? e : w;
	float side_y = quadrant.y > 0.5 ? s : n;
	if (side_x * side_y < 0.5) {
		return 0.0;
	}
	float diagonal = tile_at(cell + quadrant * 2.0 - 1.0).x;
	float linked = self_id == T_STREAM ? is_wet(diagonal) : step(abs(diagonal - self_id), 0.5);
	return linked;
}

// Distance from `q` to the nearest edge flagged in `open_edges` (e, s, w, n).
float edge_room(vec2 q, vec4 open_edges) {
	float room = 9.0;
	if (open_edges.x > 0.5) { room = min(room, 1.0 - q.x); }
	if (open_edges.y > 0.5) { room = min(room, 1.0 - q.y); }
	if (open_edges.z > 0.5) { room = min(room, q.x); }
	if (open_edges.w > 0.5) { room = min(room, q.y); }
	return room;
}

// Features of inset terrain for the tile being drawn. `own` is the tile's
// interior ground, `outside` the turf around it (shown near `open_edges`, the
// edges shared with other materials, weighted by `edge_mix`); `q` is the
// position inside the tile and e/s/w/n the neighbouring terrain ids.
vec3 inset_tile(float id, vec3 own, vec3 outside, float edge_mix, vec4 open_edges, vec2 q,
		vec2 cell, float e, float s, float w, float n, vec2 world, float grain, float patch) {
	vec2 g = world / tile_size;
	if (id == T_STREAM) {
		// Running water in a channel joining every neighbouring stream or pond.
		float ee = is_wet(e);
		float ss = is_wet(s);
		float ww = is_wet(w);
		float nn = is_wet(n);
		float along_y;
		float d = link_distance(q, ee, ss, ww, nn, along_y);
		if (ee + ss + ww + nn < 0.5) { d += 0.06; }  // A lone tile is a small spring pool
		// Where it meets a pond the channel opens out across the whole edge.
		float pond = 0.0;
		if (e == 8.0) { d = smin(d, (1.0 - q.x) * 1.5, 0.1); pond = max(pond, smoothstep(0.72, 1.0, q.x)); }
		if (w == 8.0) { d = smin(d, q.x * 1.5, 0.1); pond = max(pond, smoothstep(0.72, 1.0, 1.0 - q.x)); }
		if (s == 8.0) { d = smin(d, (1.0 - q.y) * 1.5, 0.1); pond = max(pond, smoothstep(0.72, 1.0, q.y)); }
		if (n == 8.0) { d = smin(d, q.y * 1.5, 0.1); pond = max(pond, smoothstep(0.72, 1.0, 1.0 - q.y)); }
		if (corner_filled(q, cell, ee, ss, ww, nn, T_STREAM) > 0.5) { d = -1.0; }
		float half_width = 0.25 + (noise(g * 1.7 + vec2(7.0, 3.0)) - 0.5) * 0.09;
		float water_mask = 1.0 - smoothstep(half_width - 0.025, half_width + 0.025, d);
		float mud_mask = 1.0 - smoothstep(half_width + 0.02, half_width + 0.11, d);

		float deep = 1.0 - smoothstep(0.0, half_width, max(d, 0.0));
		vec3 water = palette_color(T_STREAM) * (0.84 + (1.0 - deep) * 0.2 + (patch - 0.5) * 0.06);
		water = mix(water, vec3(0.80, 0.78, 0.62), smoothstep(half_width * 0.55, half_width, d) * 0.3);
		// Current: soft crests drifting downstream, broken up by moving noise.
		float along = mix(g.x, g.y, along_y);
		float across = mix(g.y, g.x, along_y);
		float crest = sin(along * 6.0 - TIME * 2.0 + noise(vec2(along * 1.4, across * 3.0)) * 4.0);
		float current = smoothstep(0.55, 1.0, crest)
			* smoothstep(0.4, 0.75, noise(vec2(along * 1.6 - TIME * 0.45, across * 4.0)));
		water += vec3(0.14, 0.2, 0.2) * current * deep * 0.6;
		float glint = smoothstep(0.93, 1.0, crest) * smoothstep(0.65, 0.85, noise(g * 3.0 + vec2(TIME * 0.2, 0.0)));
		water += vec3(0.3, 0.35, 0.3) * glint * 0.35;
		water = mix(water, surface(8.0, 1.0, 0.0, world, grain, patch), pond);

		vec3 bank = mix(own, outside, edge_mix);
		vec3 mud = mix(palette_color(1.0) * 0.5, vec3(0.36, 0.31, 0.24), 0.6);
		mud = mix(mud, vec3(0.64, 0.62, 0.57), dots(g * 21.0, 0.3, 0.3) * 0.7);
		return mix(mix(bank, mud, mud_mask), clamp(water, vec3(0.0), vec3(1.0)), water_mask);
	} else if (id == T_POT_BUNKER) {
		// A small round pit: the turf lip, a stacked-turf wall whose far face
		// shows above the floor, and a shaded sand floor.
		float ee = step(abs(e - id), 0.5);
		float ss = step(abs(s - id), 0.5);
		float ww = step(abs(w - id), 0.5);
		float nn = step(abs(n - id), 0.5);
		float along_y;
		float fill = corner_filled(q, cell, ee, ss, ww, nn, id);
		float rim = fill > 0.5 ? -1.0 : link_distance(q, ee, ss, ww, nn, along_y);
		// The floor sits nearer the viewer (screen down = grid +x +y), which
		// exposes the far wall's face.
		vec2 fq = q - vec2(0.07);
		float floor_d = fill > 0.5 ? -1.0 : link_distance(fq, ee, ss, ww, nn, along_y);
		float wobble = (noise(g * 5.0) - 0.5) * 0.04;
		float in_rim = 1.0 - smoothstep(0.38 + wobble, 0.41 + wobble, rim);
		float on_floor = 1.0 - smoothstep(0.27 + wobble, 0.30 + wobble, floor_d);
		float courses = smoothstep(0.2, 0.8, abs(fract((g.x + g.y) * 7.0 + noise(g * 8.0) * 0.4) - 0.5) * 2.0);
		vec3 face = mix(vec3(0.30, 0.25, 0.16), palette_color(3.0) * 0.72, courses * 0.8);
		face *= 0.8 + 0.2 * noise(g * 20.0);
		float floor_light = smoothstep(0.0, 0.22, 0.27 - floor_d);
		float wall_shadow = smoothstep(0.1, 0.34, link_distance(q + GROUND_LIGHT * 0.12, ee, ss, ww, nn, along_y)) * (1.0 - fill);
		vec3 sand = own * (0.7 + floor_light * 0.3) * (1.0 - wall_shadow * 0.18);
		vec3 lip = outside * (1.0 - (1.0 - smoothstep(0.41, 0.48, rim)) * 0.22);  // a shadowed rim edge
		return mix(lip, mix(face, sand, on_floor), in_rim);
	} else if (id == T_WASTE_BUNKER) {
		// Sand breaking up raggedly into the surrounding turf.
		float room = edge_room(q, open_edges) + (noise(g * 3.4) - 0.5) * 0.2 + (noise(g * 11.0) - 0.5) * 0.08;
		float margin = 1.0 - smoothstep(0.06, 0.2, room);
		return mix(own, outside, margin);
	} else if (id == T_ROCKS || id == T_BRUSH) {
		// Stones or shrubs scattered on cells; each keeps clear of edges
		// shared with other materials, so none is cut off at a tile edge.
		bool rocks = id == T_ROCKS;
		float scale = rocks ? 2.9 : 3.1;
		vec2 to_point;
		vec4 c = cells(g * scale, to_point);
		vec2 feature_q = g + to_point / scale - cell;
		float room = edge_room(feature_q, open_edges);
		// Mostly small stones with the odd larger boulder; shrubs vary less.
		float radius = rocks ? 0.075 + c.z * c.z * 0.1 : 0.13 + c.z * 0.04;
		float present = step(rocks ? 0.22 : 0.08, c.z) * step(radius + 0.03, room);
		vec2 from_center = -to_point / scale;  // Pixel relative to the feature, grid units
		float r = length(from_center);
		float outline = rocks ? (noise(g * 13.0) - 0.5) * 0.05 : (noise(g * 21.0) - 0.5) * 0.07;
		float body = (1.0 - smoothstep(radius - 0.012, radius + 0.012, r + outline)) * present;
		float lit = clamp(0.5 + dot(from_center / radius, GROUND_LIGHT) * 0.55, 0.0, 1.0);
		vec3 ground = mix(own, outside, edge_mix);
		// Contact shadow on the ground, cast away from the light.
		float shade = (1.0 - smoothstep(radius * 0.9, radius * 1.6, length(from_center + GROUND_LIGHT * radius * 0.45))) * present;
		ground *= 1.0 - shade * 0.3;
		vec3 feature;
		if (rocks) {
			feature = palette_color(T_ROCKS) * (0.64 + lit * 0.52) * (0.88 + c.z * 0.24);
			feature *= 0.93 + noise(g * 34.0) * 0.12;
			ground = mix(ground, ground * 1.25, dots(g * 19.0, 0.25, 0.28) * 0.6);  // Grit
		} else {
			feature = palette_color(T_BRUSH) * (0.62 + lit * 0.56) * (0.86 + noise(g * 26.0) * 0.26);
			float blossom = dots(g * 16.0, 0.05, 0.32) * step(0.5, lit);
			feature = mix(feature, vec3(0.94, 0.84, 0.36), blossom * 0.8);
		}
		return mix(ground, feature, body);
	}
	return own;
}

// A neighbouring tile's material inside the boundary band around tile
// `self_id`. Inset terrain shows native grass along edges it shares with
// anything it can't sit on (which never draw a band against it), so that is
// what it contributes — except the sand a waste bunker runs under stones and
// shrubs.
vec3 neighbour_surface(vec2 tile, float cover, float self_id, vec2 world, float grain, float patch) {
	if (is_inset(tile.x) && !carries(tile.x, self_id)) {
		return surface(1.0, 1.0, 0.0, world, grain, patch);
	}
	return surface(tile.x, cover, tile.y, world, grain, patch);
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
		vec4 open_edges = vec4(edge_between(a.x, t_e.x), edge_between(a.x, t_s.x),
			edge_between(a.x, t_w.x), edge_between(a.x, t_n.x));
		float m_e = open_edges.x * smoothstep(-AA, AA, d_e);
		float m_w = open_edges.z * smoothstep(-AA, AA, d_w);
		float m_s = open_edges.y * smoothstep(-AA, AA, d_s);
		float m_n = open_edges.w * smoothstep(-AA, AA, d_n);

		float w_c = (1.0 - m_e) * (1.0 - m_w) * (1.0 - m_s) * (1.0 - m_n);
		float w_e = m_e * (1.0 - m_w) * (1.0 - m_s) * (1.0 - m_n);
		float w_s = m_s * (1.0 - m_w) * (1.0 - m_e) * (1.0 - m_n);
		float w_w = m_w * (1.0 - m_e) * (1.0 - m_s) * (1.0 - m_n);
		float w_n = m_n * (1.0 - m_w) * (1.0 - m_s) * (1.0 - m_e);

		// Coverage for edge treatments (fringe, lip, shoreline): 1 well inside
		// the tile, fading across the boundary band. Square, like the boundary.
		float c_e = open_edges.x * smoothstep(-FRINGE, FRINGE, d_e);
		float c_w = open_edges.z * smoothstep(-FRINGE, FRINGE, d_w);
		float c_s = open_edges.y * smoothstep(-FRINGE, FRINGE, d_s);
		float c_n = open_edges.w * smoothstep(-FRINGE, FRINGE, d_n);
		float cov_c = (1.0 - c_e) * (1.0 - c_w) * (1.0 - c_s) * (1.0 - c_n);
		// A neighbour's own edge treatment, as that tile sees this one.
		float cov_e = 1.0 - edge_between(t_e.x, a.x) * (1.0 - smoothstep(-FRINGE, FRINGE, d_e));
		float cov_s = 1.0 - edge_between(t_s.x, a.x) * (1.0 - smoothstep(-FRINGE, FRINGE, d_s));
		float cov_w = 1.0 - edge_between(t_w.x, a.x) * (1.0 - smoothstep(-FRINGE, FRINGE, d_w));
		float cov_n = 1.0 - edge_between(t_n.x, a.x) * (1.0 - smoothstep(-FRINGE, FRINGE, d_n));

		float grain = hash(floor(tile_world));
		float patch = noise(tile_world * 0.009) * 0.65 + noise(tile_world * 0.035) * 0.35;
		float w_sum = w_c + w_e + w_s + w_w + w_n;
		// Neighbour materials only contribute inside their boundary band, so
		// skip them elsewhere: most pixels evaluate a single surface.
		vec3 color = vec3(0.0);
		if (w_c > 0.0) {
			vec3 own = surface(a.x, cov_c, a.y, tile_world, grain, patch);
			if (is_inset(a.x)) {
				vec3 native = surface(1.0, 1.0, 0.0, tile_world, grain, patch);
				// The turf around the patch, blended toward each open edge.
				float e_e = open_edges.x * smoothstep(-0.5, 0.0, d_e);
				float e_s = open_edges.y * smoothstep(-0.5, 0.0, d_s);
				float e_w = open_edges.z * smoothstep(-0.5, 0.0, d_w);
				float e_n = open_edges.w * smoothstep(-0.5, 0.0, d_n);
				vec3 around = vec3(0.0);
				if (e_e > 0.0) { around += (carries(t_e.x, a.x) ? surface(t_e.x, 1.0, t_e.y, tile_world, grain, patch) : native) * e_e; }
				if (e_s > 0.0) { around += (carries(t_s.x, a.x) ? surface(t_s.x, 1.0, t_s.y, tile_world, grain, patch) : native) * e_s; }
				if (e_w > 0.0) { around += (carries(t_w.x, a.x) ? surface(t_w.x, 1.0, t_w.y, tile_world, grain, patch) : native) * e_w; }
				if (e_n > 0.0) { around += (carries(t_n.x, a.x) ? surface(t_n.x, 1.0, t_n.y, tile_world, grain, patch) : native) * e_n; }
				float around_w = e_e + e_s + e_w + e_n;
				vec3 outside = around_w > 0.0 ? around / around_w : native;
				float edge_mix = clamp(max(max(e_e, e_s), max(e_w, e_n)), 0.0, 1.0);
				own = inset_tile(a.x, own, outside, edge_mix, open_edges, f, cell,
					t_e.x, t_s.x, t_w.x, t_n.x, tile_world, grain, patch);
			}
			color += own * w_c;
		}
		if (w_e > 0.0) { color += neighbour_surface(t_e, cov_e, a.x, tile_world, grain, patch) * w_e; }
		if (w_s > 0.0) { color += neighbour_surface(t_s, cov_s, a.x, tile_world, grain, patch) * w_s; }
		if (w_w > 0.0) { color += neighbour_surface(t_w, cov_w, a.x, tile_world, grain, patch) * w_w; }
		if (w_n > 0.0) { color += neighbour_surface(t_n, cov_n, a.x, tile_world, grain, patch) * w_n; }
		color /= max(w_sum, 0.0001);
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
