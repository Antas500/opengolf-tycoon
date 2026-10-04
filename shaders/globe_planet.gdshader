shader_type canvas_item;
// The World Map planet: one quad draws the whole globe.
//
// GlobeMap rasterises its land polygons into an equirectangular coverage mask
// once (see GlobeMap.build_land_mask) and hands it to this shader, which turns
// it back into a shaded sphere:
//
//   * sea depth  — how far the nearest land is, so coasts get a lighter shelf
//   * land       — fbm relief, an arid band around the tropics, polar ice
//   * light      — a warm sun, a soft day/night terminator and a cool night
//                  side, plus a specular glint on open water
//   * atmosphere — a haze that thickens towards the limb and a soft halo
//                  outside the silhouette
//   * graticule  — 30° meridians and parallels that fade out near the poles
//
// Everything is analytic (a couple of mask taps and a handful of noise
// octaves per pixel), so the planet is one draw call with no texture assets
// beyond the mask. Uniforms are driven from GlobeMap; the palette defaults
// match the old land-dot drawing so the globe keeps its colours.
//
// The mask repeats in longitude (hint repeat_enable) so u wraps at the
// antimeridian; u = 0.5 + lon/360, v = 0.5 - lat/180.

// ── View, driven by GlobeMap ────────────────────────────────────────────────
uniform vec2 view_size = vec2(600.0, 600.0);
uniform float center_lon_deg = -40.0;
uniform float center_lat_deg = 30.0;
uniform float radius_scale = 1.0;
// Sphere radius as a share of the smaller side, matching GlobeMap._sphere_radius.
uniform float sphere_fill = 0.92;
// How far the halo reaches past the silhouette (1.0 = none).
uniform float halo_scale = 1.06;

// ── Baked land mask ─────────────────────────────────────────────────────────
uniform sampler2D land_mask : filter_linear_mipmap, repeat_enable;
uniform vec2 mask_size = vec2(2048.0, 1024.0);

// ── Light ───────────────────────────────────────────────────────────────────
// View space, i.e. the sun sits with the camera rather than in the world: spin
// the globe and the light stays put, so a destination the player is looking at
// never disappears into the night side. The terrain noise is anchored to the
// globe's own frame (see globe_normal) so it rides the continents as they turn.
uniform vec3 light_dir = vec3(-0.42, 0.52, 0.75);
uniform float ambient_floor : hint_range(0.0, 1.0) = 0.62;
uniform float terminator_softness : hint_range(0.01, 1.0) = 0.34;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.30;
uniform float specular_sharpness : hint_range(1.0, 200.0) = 110.0;

// ── Palette ─────────────────────────────────────────────────────────────────
uniform vec4 ocean_deep : source_color = vec4(0.106, 0.227, 0.345, 1.0);   // #1b3a58
uniform vec4 ocean_shallow : source_color = vec4(0.176, 0.408, 0.510, 1.0);
uniform vec4 ocean_mid : source_color = vec4(0.129, 0.318, 0.463, 1.0);
uniform vec4 shore_color : source_color = vec4(0.561, 0.702, 0.788, 1.0); // #8fb3c9
uniform vec4 land_low : source_color = vec4(0.247, 0.333, 0.188, 1.0);    // #3f5530
uniform vec4 land_mid : source_color = vec4(0.373, 0.490, 0.290, 1.0);    // #5f7d4a
uniform vec4 land_high : source_color = vec4(0.518, 0.612, 0.373, 1.0);
uniform vec4 land_dry : source_color = vec4(0.639, 0.573, 0.404, 1.0);    // #a39267
uniform vec4 land_beach : source_color = vec4(0.761, 0.694, 0.518, 1.0);  // MenuBackdrop sand
uniform vec4 ice_color : source_color = vec4(0.910, 0.945, 0.965, 1.0);
uniform vec4 atmosphere_color : source_color = vec4(0.545, 0.796, 0.867, 1.0);
uniform vec4 cloud_color : source_color = vec4(0.941, 0.965, 0.949, 1.0);
uniform vec4 day_tint : source_color = vec4(1.0, 0.976, 0.925, 1.0);      // cream
uniform vec4 night_tint : source_color = vec4(0.157, 0.208, 0.302, 1.0);

// ── Surface detail ──────────────────────────────────────────────────────────
uniform float relief_strength : hint_range(0.0, 1.0) = 0.70;
uniform float biome_strength : hint_range(0.0, 1.0) = 0.35;
uniform float ice_strength : hint_range(0.0, 1.0) = 0.85;
uniform float coast_glow : hint_range(0.0, 1.0) = 0.40;
uniform float cloud_amount : hint_range(0.0, 0.5) = 0.14;
uniform float atmosphere_strength : hint_range(0.0, 1.0) = 0.55;
uniform float limb_haze : hint_range(0.0, 1.0) = 0.35;

// ── Graticule ───────────────────────────────────────────────────────────────
uniform float graticule_alpha : hint_range(0.0, 1.0) = 0.10;
uniform float graticule_step_deg = 30.0;

// ── Noise (3D value noise + fbm, hash based) ────────────────────────────────
// Sampled on the sphere's own normal, not on lon/lat, so the pattern has no
// poles to converge at: no smearing or radial streaks, and no uneven cell
// sizes between the equator and the caps.
float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * value_noise(p);
		p = p * 2.03 + vec3(11.7, 5.3, 7.9);
		amplitude *= 0.5;
	}
	return value;
}

// One frequency in sphere space: roughly 57 degrees across per unit.
const float RELIEF_FREQ = 5.5;
const float CLOUD_FREQ = 8.0;

// lon/lat of the point under this pixel, for a globe centred on
// (center_lon_deg, center_lat_deg) — the same orthographic projection as
// GlobeMap.project_point, run backwards.
void lon_lat_for(vec3 n, float phi0, out float lon_deg, out float lat_deg) {
	float sin_phi = clamp(n.y * cos(phi0) + n.z * sin(phi0), -1.0, 1.0);
	float phi = asin(sin_phi);
	float lam = atan(n.x, n.z * cos(phi0) - n.y * sin(phi0));
	lat_deg = degrees(phi);
	lon_deg = degrees(lam) + center_lon_deg;
}

// Land coverage at a mask UV, with the mask's own linear filtering and the
// wraparound in longitude handled by the sampler.
float mask_at(vec2 uv) {
	return texture(land_mask, uv).r;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * view_size;
	float radius = max(min(view_size.x, view_size.y) * 0.5 * sphere_fill * radius_scale, 1.0);
	float r = length(p) / radius;
	float px = 1.0 / radius;                       // one screen pixel in r units

	// Body / halo split, softened over about a pixel so the silhouette is smooth.
	float body = 1.0 - smoothstep(1.0 - px * 1.5, 1.0 + px * 1.5, r);

	// The surface normal at this pixel, in the globe's own frame: screen +y
	// grows downwards but the globe's +y grows up, so the vertical component
	// is negated. `lon_lat_for` below is the exact inverse of
	// GlobeMap.project_point, and the pins are drawn with that projection —
	// get this sign wrong and the mask renders mirrored while the pins slide
	// off their destinations as the globe turns.
	vec3 n = vec3(p.x / radius, -p.y / radius, sqrt(max(0.0, 1.0 - r * r)));
	n = normalize(n);
	float phi0 = radians(center_lat_deg);
	float lon_deg;
	float lat_deg;
	lon_lat_for(n, phi0, lon_deg, lat_deg);

	// ── Land mask, with a coastal shelf measured from it ────────────────────
	vec2 mask_uv = vec2((lon_deg + 180.0) / 360.0,
			clamp(0.5 - lat_deg / 180.0, 0.5 / mask_size.y, 1.0 - 0.5 / mask_size.y));
	float land = mask_at(mask_uv);
	vec2 texel = max(fwidth(mask_uv), vec2(1.0 / mask_size.x, 1.0 / mask_size.y));
	float coast_aa = clamp(max(texel.x, texel.y) * 0.8, 1.0 / mask_size.x, 0.35);
	float land_a = smoothstep(0.5 - coast_aa, 0.5 + coast_aa, land);

	// Probe about three pixels out (or two mask texels, whichever is further)
	// so the shelf keeps a visible width however big the globe is drawn.
	// One screen pixel is `px` radians of the sphere's surface, i.e.
	// degrees(px) of latitude in mask v units.
	float px_deg = px * 57.29578;
	vec2 px_uv = vec2(px_deg / 360.0, px_deg / 180.0);
	vec2 probe = max(texel * 2.0, px_uv * 3.0);
	// Longitude wraps in the sampler (the antimeridian) but latitude must be
	// kept inside the mask, or a probe off the top of the map would wrap
	// round to the Antarctic land and light up the Arctic with shelf water.
	float half_texel_y = 0.5 / mask_size.y;
	float probe_lat_lo = clamp(mask_uv.y - probe.y, half_texel_y, 1.0 - half_texel_y);
	float probe_lat_hi = clamp(mask_uv.y + probe.y, half_texel_y, 1.0 - half_texel_y);
	float sample_east = mask_at(vec2(mask_uv.x + probe.x, mask_uv.y));
	float sample_west = mask_at(vec2(mask_uv.x - probe.x, mask_uv.y));
	float sample_north = mask_at(vec2(mask_uv.x, probe_lat_hi));
	float sample_south = mask_at(vec2(mask_uv.x, probe_lat_lo));
	float near_land = max(max(sample_east, sample_west), max(sample_north, sample_south));
	// ...and the other way round: is there sea beside this pixel? Used for the
	// beach rim, which must stay on the coastline instead of washing the
	// whole landmass sand-coloured.
	float near_water = 1.0 - min(min(sample_east, sample_west), min(sample_north, sample_south));
	float shelf = clamp((near_land - land_a) * (1.0 - land_a), 0.0, 1.0);

	// ── Surface colour ──────────────────────────────────────────────────────
	// Relief is noise on the globe's own normal, so it is fixed to the
	// surface: the continents carry their terrain round with them instead of
	// swimming through a pattern pinned to the screen.
	float lam_abs = radians(lon_deg);
	float phi_abs = radians(lat_deg);
	vec3 globe_normal = vec3(cos(phi_abs) * sin(lam_abs), sin(phi_abs), cos(phi_abs) * cos(lam_abs));
	float relief = clamp(fbm(globe_normal * RELIEF_FREQ) * 1.30 - 0.15, 0.0, 1.0);

	float depth = clamp(1.0 - near_land, 0.0, 1.0);
	vec3 ocean = mix(ocean_shallow.rgb, ocean_deep.rgb, smoothstep(0.0, 0.5, depth));
	ocean = mix(ocean, ocean_mid.rgb, 0.35);
	ocean = mix(ocean, shore_color.rgb, coast_glow * shelf);

	// Land reads as one green with gentle terrain on it: the noise never
	// swings far enough to look like weather sitting on the continent.
	vec3 land_rgb = mix(land_low.rgb, land_mid.rgb, 0.45 + 0.55 * relief);
	float highland = smoothstep(0.55, 0.95, relief) * relief_strength * 0.8;
	land_rgb = mix(land_rgb, land_high.rgb, highland);
	float abs_lat = abs(lat_deg);
	float arid_band = smoothstep(10.0, 19.0, abs_lat) * (1.0 - smoothstep(27.0, 38.0, abs_lat));
	float arid = clamp(arid_band * (relief * 1.6 - 0.25), 0.0, 1.0) * biome_strength;
	land_rgb = mix(land_rgb, land_dry.rgb, arid);
	land_rgb = mix(land_rgb, land_beach.rgb, clamp(near_water * land_a, 0.0, 1.0) * 0.35);
	float ice = smoothstep(67.0, 78.0, abs_lat + (relief - 0.5) * 8.0) * ice_strength;
	land_rgb = mix(land_rgb, ice_color.rgb, clamp(ice, 0.0, 1.0));

	vec3 albedo = mix(ocean, land_rgb, land_a);

	// ── Light ───────────────────────────────────────────────────────────────
	vec3 light = normalize(light_dir);
	float ndl = dot(n, light);
	float day = smoothstep(-terminator_softness, terminator_softness, ndl);
	float luminance = ambient_floor + (1.0 - ambient_floor) * clamp(ndl, 0.0, 1.0);
	vec3 planet = albedo * luminance * mix(night_tint.rgb, day_tint.rgb, day);

	vec3 half_vector = normalize(light + vec3(0.0, 0.0, 1.0));
	float specular = pow(max(dot(n, half_vector), 0.0), specular_sharpness)
			* specular_strength * day * (1.0 - land_a);
	planet += vec3(specular);

	// Haze that thickens towards the limb — the air the player looks through.
	float limb = pow(1.0 - clamp(n.z, 0.0, 1.0), 3.0);
	planet = mix(planet, atmosphere_color.rgb, limb * limb_haze);

	// ── Clouds (faint, so markers and coastlines stay readable) ─────────────
	if (cloud_amount > 0.0) {
		float cloud = fbm(globe_normal * CLOUD_FREQ + vec3(31.0, 17.0, 5.0));
		float cover = smoothstep(0.54, 0.80, cloud) * cloud_amount * (1.0 - ice * 0.6);
		vec3 cloud_rgb = cloud_color.rgb * (0.45 + 0.55 * luminance) * mix(0.5, 1.0, day);
		planet = mix(planet, cloud_rgb, clamp(cover, 0.0, 1.0));
	}

	// ── Graticule ───────────────────────────────────────────────────────────
	if (graticule_alpha > 0.0) {
		vec2 grid = vec2(lon_deg, lat_deg) / graticule_step_deg;
		vec2 distance_deg = abs(fract(grid + 0.5) - 0.5) * graticule_step_deg;
		float line_width = max(0.7 * max(fwidth(lon_deg), fwidth(lat_deg)), 0.02);
		float lines = 1.0 - smoothstep(0.0, line_width, min(distance_deg.x, distance_deg.y));
		lines *= 1.0 - smoothstep(80.0, 88.0, abs_lat);
		planet = mix(planet, vec3(1.0), lines * graticule_alpha * (0.3 + 0.7 * day));
	}

	// ── Atmosphere halo outside the silhouette ──────────────────────────────
	// The rim direction is normalised by hand: at the exact centre of the quad
	// `normalize()` would be handed a zero vector, which is undefined (and
	// shows up as a NaN speck on real drivers). Same vertical flip as n above.
	vec3 rim_normal = vec3(p.x, -p.y, 0.0) / max(length(p), 0.0001);
	float rim_light = 0.45 + 0.55 * smoothstep(-0.35, 0.45, dot(rim_normal, light));
	float glow = pow(clamp(1.0 - (r - 1.0) / max(halo_scale - 1.0, 0.001), 0.0, 1.0), 2.6);
	vec3 halo = atmosphere_color.rgb * (1.0 + 0.25 * rim_light);

	COLOR = vec4(mix(halo, planet, body), clamp(mix(glow * atmosphere_strength * rim_light, 1.0, body), 0.0, 1.0));
}
