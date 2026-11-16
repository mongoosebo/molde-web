shader_type spatial;

// The far terrain is one flat grid; heights come from the 10 m elevation texture.
// Around the player the 1 m cells (terrain_near.gdshader) take over, and this one steps aside there.
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec2 grid_size;
uniform float cell = 10.0;
uniform vec4 near_rect = vec4(1e9, 1e9, -1e9, -1e9);      // min x, min z, max x, max z

#include "terrain_common.gdshaderinc"

varying vec3 wpos;

float h_at(vec2 uv) {
	return textureLod(height_tex, (uv * (grid_size - 1.0) + 0.5) / grid_size, 0.0).r;
}

vec3 n_at(vec2 uv) {
	vec2 e = 1.0 / (grid_size - 1.0);
	float hl = h_at(uv - vec2(e.x, 0.0));
	float hr = h_at(uv + vec2(e.x, 0.0));
	float hu = h_at(uv - vec2(0.0, e.y));
	float hd = h_at(uv + vec2(0.0, e.y));
	return normalize(vec3(hl - hr, 2.0 * cell, hu - hd));
}

void vertex() {
	vec2 uv = (VERTEX.xz + world_size * 0.5) / world_size;
	VERTEX.y = h_at(uv);
	NORMAL = n_at(uv);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (wpos.x > near_rect.x && wpos.z > near_rect.y && wpos.x < near_rect.z && wpos.z < near_rect.w) {
		discard;
	}
	vec2 uv = (wpos.xz - world_origin) / world_size;
	vec3 n = n_at(uv);
	float rough;
	ALBEDO = ground_colour(wpos, n, h_at(uv), distance(wpos, CAMERA_POSITION_WORLD), rough);
	ROUGHNESS = rough;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
