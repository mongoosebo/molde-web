// What the sea, the lakes and the rivers share: the ripples that whatever goes through the water leaves
// (scripts/ripples.gd keeps them in a picture around the player), the foam, and the colour by depth.

global uniform sampler2D ripple_tex : filter_linear, repeat_disable;
global uniform vec2 ripple_origin;       // the corner of the rippled area in the world (x, z)
global uniform float ripple_size;        // its side, metres
global uniform float ripple_on;          // 0 when ripples are turned off

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

// The slope the ripples give the surface at a place (to add to the water's own), how far a crest stands up
// there, and how much foam lies on it. Nothing beyond the rippled area.
vec2 ripple_at(vec2 p, out float crest, out float foam) {
	crest = 0.0;
	foam = 0.0;
	vec2 uv = (p - ripple_origin) / ripple_size;
	if (ripple_on < 0.5 || uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return vec2(0.0);
	}
	float t = 1.0 / 256.0;
	vec4 c = texture(ripple_tex, uv);
	float hx = texture(ripple_tex, uv + vec2(t, 0.0)).r - texture(ripple_tex, uv - vec2(t, 0.0)).r;
	float hz = texture(ripple_tex, uv + vec2(0.0, t)).r - texture(ripple_tex, uv - vec2(0.0, t)).r;
	vec2 e = min(uv, 1.0 - uv);
	float fade = smoothstep(0.0, 0.08, min(e.x, e.y));
	crest = max(c.r - 0.5, 0.0) * fade;
	foam = c.b * fade;
	return vec2(hx, hz) * (fade * ripple_size * 2.0);       // (height is in metres: over two texels of ripple_size / 256)
}

// How much water lies between the surface at this pixel and what is seen through it, straight down, in metres.
float water_depth(vec2 screen_uv, vec3 vertex, mat4 inv_projection, mat4 inv_view) {
	float d = texture(depth_tex, screen_uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 far = inv_projection * vec4(screen_uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
#else
	vec4 far = inv_projection * vec4(screen_uv * 2.0 - 1.0, d, 1.0);
#endif
	far.xyz /= far.w;
	float along = max(length(far.xyz) - length(vertex), 0.0);
	vec3 dir = normalize((inv_view * vec4(normalize(vertex), 0.0)).xyz);
	return along * abs(dir.y);
}
