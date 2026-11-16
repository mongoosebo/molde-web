shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// Running water: a ribbon along a river or stream. UV.x runs across it (0 to 1), UV.y along it in
// units of 3 m, downstream. COLOR.r says how steeply it falls there: steeper water runs faster and whiter.
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying float steep;

void vertex() {
	steep = COLOR.r;
}

void fragment() {
	float speed = 0.35 + steep * 1.6;
	vec2 uv = vec2(UV.x * 0.7, UV.y - TIME * speed);
	vec3 a = texture(normal_tex, uv * vec2(1.0, 0.35)).rgb;
	vec3 b = texture(normal_tex, uv * vec2(2.3, 0.8) + vec2(0.37, TIME * 0.05)).rgb;
	NORMAL_MAP = mix(a, b, 0.5);
	NORMAL_MAP_DEPTH = 0.35 + steep * 1.2;
	float streak = texture(noise_tex, vec2(UV.x * 0.8, (UV.y - TIME * speed * 1.3) * 0.22)).r;
	float fine = texture(noise_tex, vec2(UV.x * 2.9, (UV.y - TIME * speed * 1.6) * 0.9)).r;
	float foam = smoothstep(0.60 - steep * 0.5, 0.78 - steep * 0.4, streak * 0.7 + fine * 0.3) * (0.30 + steep * 2.2);
	float edge = smoothstep(0.0, 0.16, UV.x) * smoothstep(1.0, 0.84, UV.x);
	foam = clamp(foam, 0.0, 1.0);
	// the sky seen in the water at a low angle
	float glance = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 water = mix(vec3(0.02, 0.07, 0.085), vec3(0.30, 0.36, 0.40), glance * 0.7);
	ALBEDO = mix(water, vec3(0.78, 0.83, 0.85), foam);
	ROUGHNESS = mix(0.04, 0.55, foam);
	SPECULAR = 0.7;
	ALPHA = edge * mix(0.88, 1.0, foam);
}
