shader_type canvas_item;
render_mode blend_disabled, unshaded;

// One step of the ripples around the player (scripts/ripples.gd). The picture holds the water's height in red
// and its height the step before in green (both about 0.5, so they can go either way), and foam in blue.
// Each step the wave equation moves the heights on; whatever goes through the water pushes the surface down
// where it is; everything fades slowly; and in a river the whole pattern is carried downstream.
uniform sampler2D prev : filter_linear, repeat_disable;
uniform sampler2D flow_tex : filter_linear, repeat_disable;   // red, green: flow east and south, 0.5 is still, 0 and 1 are 8 m/s
uniform vec2 shift = vec2(0.0);          // how far the area has moved since the last step, as a share of its size
uniform float texel = 0.00390625;
uniform float carry = 0.0;               // seconds a step, over the size of the area in metres
uniform vec4 push[12];                   // where (xy, as a share of the area), how wide, how hard
uniform float push_foam[12];
uniform int pushes = 0;

const float SPEED = 0.07;                // (waves cross a quarter of a texel a step)
const float FADE = 0.992;

void fragment() {
	vec2 flow = (texture(flow_tex, UV).rg - 0.5) * 16.0;
	vec2 uv = UV + shift - flow * carry;
	float h = 0.0, before = 0.0, foam = 0.0, around = 0.0;
	if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
		vec4 c = texture(prev, uv);
		h = c.r - 0.5;
		before = c.g - 0.5;
		foam = c.b;
		around = texture(prev, uv + vec2(texel, 0.0)).r + texture(prev, uv - vec2(texel, 0.0)).r
			+ texture(prev, uv + vec2(0.0, texel)).r + texture(prev, uv - vec2(0.0, texel)).r - 2.0;
	}
	float next = (2.0 * h - before + SPEED * (around - 4.0 * h)) * FADE;
	for (int i = 0; i < pushes; i++) {
		float d = distance(UV, push[i].xy) / max(push[i].z, 0.0001);
		float g = exp(-d * d * 2.5);
		next -= push[i].w * g;
		foam = max(foam, push_foam[i] * g);
	}
	// the rim of the area swallows what reaches it, so nothing comes back off an edge that is not there
	vec2 e = min(UV, 1.0 - UV);
	next *= smoothstep(0.0, 0.05, min(e.x, e.y));
	next = clamp(next, -0.45, 0.45);
	foam = max(foam * 0.985 - 0.002, 0.0);
	COLOR = vec4(next + 0.5, h + 0.5, foam, 1.0);
}
