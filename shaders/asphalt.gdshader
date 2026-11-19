shader_type spatial;

// Asphalt that looks used: not one even sheet. The colour varies slowly (worn lighter stretches, darker ones),
// here and there lies a patch of newer, blacker asphalt with straight edges, and fine cracks run through the
// older parts. All of it is placed by where the asphalt is in the world, so nothing repeats in a pattern.
// Rain darkens it and makes it shine (scripts/weather.gd sets `wetness`). COLOR is the mesh's own tint (the
// carriageway, a path, the shoulder).
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
global uniform float snow;
global uniform float wetness;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * 0.5;
	vec3 col = texture(albedo_tex, uv).rgb * pow(COLOR.rgb, vec3(2.2));
	float big = texture(noise_tex, wpos.xz * 0.009).r;
	float mid = texture(noise_tex, wpos.xz * 0.061 + 0.37).r;
	float fine = texture(noise_tex, wpos.xz * 0.43).r;
	// worn and fresh stretches
	col *= mix(0.84, 1.16, smoothstep(0.30, 0.72, big));
	// patches of newer asphalt: now and then a rectangle a few metres across, a little wobbly at the edge
	vec2 g = wpos.xz / vec2(6.0, 9.0) + vec2(big * 1.3, mid * 0.4);
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float size = 0.18 + 0.22 * hash(cell + 5.1);
	float inside = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) - size + (fine - 0.5) * 0.03;
	float patch = step(0.88, hash(cell)) * smoothstep(0.0, 0.015, inside);
	col *= mix(1.0, 0.70, patch);
	// fine cracks in the old asphalt, where the slow noise crosses its middle
	float crack = (1.0 - smoothstep(0.0, 0.006, abs(mid - 0.5))) * smoothstep(0.45, 0.6, big) * (1.0 - patch);
	col *= 1.0 - 0.55 * crack;
	// rain
	col *= 1.0 - 0.32 * wetness;
	// winter: ploughed and gritted, grey slush in drifts and trodden snow where the noise is high
	col = mix(col, vec3(0.62, 0.65, 0.69), snow * (0.16 + 0.55 * smoothstep(0.42, 0.70, mid * 0.6 + big * 0.4)));
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.92, 0.8, patch), 0.36, wetness);
	TANGENT = normalize((VIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	BINORMAL = normalize((VIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = mix(1.0, 0.5, patch);
}
