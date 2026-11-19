shader_type spatial;

// The walls and roofs of buildings close up (scripts/facades.gd). The texture carries the material (boards,
// plaster, tiles, sheet: colour, normal and roughness, photographed); COLOR is the building's own colour.
// Walls are textured by where they are in the world (along the wall and up it); roofs by the mesh's own
// coordinates (along the eave and down the slope).
//
// And a little age, slight and steady (it comes from the place, so each house has its own and it never
// moves): streaks running down the walls, patches of grime, paint a little faded on walls that face south,
// a green cast on walls that face north, moss and lichen on roofs that face north. Rain darkens and shines.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float tile = 2.0;                // metres the texture covers
uniform float rough = 0.85;
uniform float metal = 0.0;
uniform bool by_mesh = false;            // a roof: textured by its own coordinates
uniform float moss = 0.0;                // how readily moss takes (roof tiles 1, sheet 0.3, walls 0)
uniform bool has_rough = false;
global uniform float snow;
global uniform float wetness;

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	// which way the texture runs: along a wall and up it; over a flat surface by east and south
	vec3 t_dir = abs(n.y) > 0.7 ? vec3(1.0, 0.0, 0.0) : normalize(vec3(-n.z, 0.0, n.x));
	vec3 b_dir = abs(n.y) > 0.7 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, -1.0, 0.0);
	vec2 uv = by_mesh ? UV / tile : vec2(dot(wpos, t_dir), dot(wpos, b_dir)) / tile;
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	vec3 col = texture(albedo_tex, uv).rgb * base;
	float r = rough * (has_rough ? texture(rough_tex, uv).r / 0.92 : 1.0);
	// age
	float along = dot(wpos, t_dir);
	float house = hash(floor(wpos.xz / 23.0));
	float streak = texture(noise_tex, vec2(along * 0.35, wpos.y * 0.012) + house).r;
	float grime = texture(noise_tex, wpos.xz * 0.05 + vec2(wpos.y * 0.04)).r;
	float is_wall = 1.0 - smoothstep(0.5, 0.8, abs(n.y));
	col *= 1.0 - is_wall * 0.07 * smoothstep(0.52, 0.75, streak);
	col *= mix(0.93, 1.05, grime) * mix(0.96, 1.04, house);
	float south = smoothstep(0.35, 0.8, n.z) * is_wall;                 // (south is +z)
	float north = smoothstep(0.35, 0.8, -n.z);
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(lum) * 1.06, 0.10 * south);
	col = mix(col, col * vec3(0.90, 1.0, 0.90), 0.5 * north * is_wall);
	float patchy = smoothstep(0.50, 0.72, texture(noise_tex, wpos.xz * 0.11 + 0.3).r * 0.7 + texture(noise_tex, wpos.xz * 0.9).r * 0.3);
	float mossy = moss * (1.0 - is_wall) * patchy * (0.25 + 0.75 * north) * (0.5 + 0.5 * house);
	col = mix(col, vec3(0.10, 0.14, 0.05) * (0.7 + 0.6 * grime), 0.55 * mossy);
	// rain
	float wet = wetness * mix(0.5, 1.0, 1.0 - is_wall);
	col *= 1.0 - 0.28 * wet;
	col = mix(col, vec3(0.84, 0.87, 0.92), snow * 0.85 * smoothstep(0.75, 0.95, n.y));      // winter: snow on what faces up
	ALBEDO = col;
	ROUGHNESS = mix(clamp(r, 0.05, 1.0), min(r, 0.4), wet);
	METALLIC = metal;
	TANGENT = normalize((VIEW_MATRIX * vec4(t_dir, 0.0)).xyz);
	BINORMAL = normalize((VIEW_MATRIX * vec4(b_dir, 0.0)).xyz);
	if (!by_mesh) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
	}
}
