shader_type spatial;
render_mode cull_disabled;

// One 100 m cell of the 1 m terrain around the player. The mesh is a flat 1 m grid shared by all
// cells; heights come from the cell's own texture (103 x 103: the cell plus one metre all round).
// Vertices marked in UV2 are a skirt hanging down along the cell's edge, to close any crack
// against the coarser far terrain.
uniform sampler2D height_tex : filter_linear, repeat_disable;

#include "terrain_common.gdshaderinc"

varying vec3 wpos;
varying vec2 cpos;

float h_at(vec2 p) {            // p in metres from the cell's corner
	return textureLod(height_tex, (p + 1.5) / 103.0, 0.0).r;
}

vec3 n_at(vec2 p) {
	return normalize(vec3(h_at(p - vec2(1.0, 0.0)) - h_at(p + vec2(1.0, 0.0)), 2.0,
			h_at(p - vec2(0.0, 1.0)) - h_at(p + vec2(0.0, 1.0))));
}

void vertex() {
	cpos = VERTEX.xz + 50.0;
	VERTEX.y = h_at(cpos) - UV2.x * 4.0;
	NORMAL = n_at(cpos);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = n_at(cpos);
	float rough;
	ALBEDO = ground_colour(wpos, n, h_at(cpos), distance(wpos, CAMERA_POSITION_WORLD), rough);
	ROUGHNESS = rough;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
