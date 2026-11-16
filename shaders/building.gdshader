shader_type spatial;
render_mode cull_disabled;

// COLOR.rgb = wall or roof paint, COLOR.a = war damage 0..1
// UV = (metres along the wall, metres above the uphill ground)
// UV2.x = 1 for roofs and debris, UV2.y = 1 if the building has windows
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	float dmg = COLOR.a;
	float n1 = texture(noise_tex, UV * 0.12 + wpos.xz * 0.01).r;
	float n2 = texture(noise_tex, wpos.xz * 0.21 + vec2(wpos.y * 0.17)).r;
	vec3 col = base * (0.82 + 0.36 * n2);
	float rough = 0.9;
	vec3 emi = vec3(0.0);

	if (UV2.x < 0.5 && UV2.y > 0.5 && UV.y > 0.2) {
		vec2 g = vec2(UV.x / 2.4, (UV.y - 0.2) / 2.9);
		vec2 f = fract(g);
		vec2 id = floor(g) + floor(wpos.xz / 40.0) * 7.0;
		float w = step(0.22, f.x) * step(f.x, 0.78) * step(0.30, f.y) * step(f.y, 0.80);
		float r = hash(id);
		vec3 glass = vec3(0.02, 0.025, 0.03);
		if (r < dmg * 1.4 + 0.08) {
			glass = vec3(0.004);                         // blown out
		} else if (r > 0.985 && dmg < 0.25) {
			emi = vec3(1.0, 0.62, 0.28) * 1.6 * w;      // someone still lives here
		} else {
			rough = mix(rough, 0.15, w);
		}
		col = mix(col, glass, w);
	}

	float soot = clamp(dmg * 1.5 - 0.25, 0.0, 1.0) * smoothstep(0.25, 0.75, n1 + dmg * 0.4);
	col = mix(col, vec3(0.012, 0.011, 0.010), soot * 0.9);

	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = emi;
}
