shader_type spatial;
render_mode blend_mix, depth_draw_opaque;

// The sea and the lakes. `calm` is 0 for the sea and 1 for a lake, which lies nearly still.
#include "water_common.gdshaderinc"

uniform float calm = 0.0;
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_normal;

// The sea is one huge sheet, so the place in the world is worked out per pixel from the view (steady),
// not carried across the sheet from its far corners (which shakes).
//
// The surface is a handful of wave trains that all travel roughly the same way, down the fjord with the
// wind, each at the speed water waves of its length really move. Waves that travel read as moving water;
// patterns sliding against each other only shimmer. Short waves fade out with distance, before they get
// smaller than a pixel and start to flicker.

const vec2 WIND = vec2(0.94, 0.34);        // toward the east-south-east

vec2 wave(vec2 p, float turn, float len, float steep, float t, float fade) {
	float c = cos(turn), s = sin(turn);
	vec2 d = vec2(WIND.x * c - WIND.y * s, WIND.x * s + WIND.y * c);
	float k = 6.2832 / len;
	float w = sqrt(9.81 * k);                 // deep water: longer waves run faster
	return d * (steep * fade * cos(k * dot(d, p) - w * t));
}

void fragment() {
	vec2 p = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	float dist = length(VERTEX);
	// The size of a pixel on the water, in metres. Looking along the surface a pixel covers a long strip of
	// it, far longer than it is wide; waves shorter than that strip would flicker, so they are faded by its length.
	vec3 view_dir = normalize((INV_VIEW_MATRIX * vec4(normalize(VERTEX), 0.0)).xyz);
	float px = dist * 0.0012 / max(abs(view_dir.y), 0.06) * 0.5;
	float t = TIME * calm;                                  // the sea lies still (note of 17 Nov): a fixed, mirroring surface
	vec2 slope = vec2(0.0);
	slope += wave(p, 0.00, 43.0, 0.030, t, 1.0 - smoothstep(0.04, 0.16, px / 43.0));
	slope += wave(p, 0.47, 27.0, 0.032, t, 1.0 - smoothstep(0.04, 0.16, px / 27.0));
	slope += wave(p, -0.61, 17.3, 0.034, t, 1.0 - smoothstep(0.04, 0.16, px / 17.3));
	slope += wave(p, 1.05, 10.1, 0.034, t, 1.0 - smoothstep(0.04, 0.16, px / 10.1));
	slope += wave(p, -1.20, 6.7, 0.032, t, 1.0 - smoothstep(0.04, 0.16, px / 6.7));
	slope += wave(p, 0.25, 4.1, 0.030, t, 1.0 - smoothstep(0.04, 0.16, px / 4.1));
	slope += wave(p, -0.33, 2.3, 0.028, t, 1.0 - smoothstep(0.04, 0.16, px / 2.3));
	slope += wave(p, 0.85, 1.3, 0.024, t, 1.0 - smoothstep(0.04, 0.16, px / 1.3));
	// the surface is never as even as a few wave trains: a slow, large unevenness carried along with them
	vec3 swell = texture(normal_tex, (p - WIND * t * 2.2) * 0.011).rgb * 2.0 - 1.0;
	slope += swell.xy * 0.07 * (1.0 - smoothstep(300.0, 1600.0, dist));
	// small ripples carried along with the wind
	float near = 1.0 - smoothstep(40.0, 260.0, dist);
	vec3 rip = texture(normal_tex, (p - WIND * t * 0.9) * 0.06).rgb * 2.0 - 1.0;
	slope += rip.xy * 0.10 * near;
	slope *= mix(1.0, 0.12, calm);
	// what goes through the water near the player: its ripples bend the surface, their crests are a little
	// lighter, and fast things leave foam
	float crest, foam;
	slope += ripple_at(p, crest, foam) * calm;              // nothing moves on the sea: no rings, wakes or foam
	foam *= calm;
	vec3 n_world = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	// The colour by depth: the ground shows through shallow water, deep water is dark.
	float depth = water_depth(SCREEN_UV, VERTEX, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	float thick = 1.0 - exp(-depth * 1.3);
	vec3 water = mix(vec3(0.05, 0.11, 0.10), vec3(0.012, 0.03, 0.04), smoothstep(0.0, 3.5, depth));
	water += vec3(0.05, 0.07, 0.07) * min(crest * 6.0, 1.0);
	foam = smoothstep(0.10, 0.75, foam * (0.45 + 1.1 * texture(normal_tex, p * 0.31).g));      // broken up, not a flat sheet
	ALBEDO = mix(water, vec3(0.80, 0.85, 0.86), foam);
	ROUGHNESS = mix(mix(0.10, 0.30, smoothstep(40.0, 600.0, dist)), 0.6, foam);
	SPECULAR = 0.6;
	ALPHA = clamp(max(mix(0.25, 1.0, thick), foam), 0.0, 1.0) * smoothstep(0.0, 0.05, depth + 0.02);
}
