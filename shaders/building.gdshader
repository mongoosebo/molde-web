shader_type spatial;
render_mode cull_disabled;

// COLOR.rgb = wall or roof paint, COLOR.a = war damage 0..1
// UV = (metres along the wall, metres above the uphill ground)
// UV2.x = 1 for roofs and debris, UV2.y = 1 if the building has windows
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
global uniform float snow;
global uniform float wetness;            // 0 dry to 1 soaked (scripts/weather.gd)
global uniform float night;              // 0 by day, 1 in the dark (scripts/daytime.gd)
global uniform float lit_share;          // how many of the windows are lit: few by day, most in the evening

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
		} else if (r > 1.0 - lit_share && dmg < 0.25) {
			// someone is home: a warm window, each a little different, lit and put out one by one as the
			// evening goes (each window has its own number; the share that is lit moves past it)
			float warm = hash(id + 3.7);
			emi = mix(vec3(1.0, 0.62, 0.28), vec3(1.0, 0.80, 0.55), warm) * (0.5 + 1.6 * night) * (0.7 + 0.6 * hash(id + 9.1)) * w;
		} else {
			rough = mix(rough, 0.15, w);
		}
		col = mix(col, glass, w);
	}

	// A little age, slight and steady: darker at the foot of walls, streaks under the windows, paint a little
	// faded on south walls, a green cast on north walls, moss on roofs that face north (as shaders/wall.gdshader).
	vec3 wn = normalize(cross(dFdx(wpos), dFdy(wpos)));
	float house = hash(floor(wpos.xz / 23.0));
	if (UV2.x < 0.5) {
		col *= mix(0.86, 1.0, smoothstep(0.0, 0.9, UV.y));
		vec2 gw = vec2(UV.x / 2.4, (UV.y - 0.2) / 2.9);
		float under = step(0.22, fract(gw.x)) * step(fract(gw.x), 0.78) * smoothstep(0.30, 0.0, fract(gw.y)) * UV2.y;
		col *= 1.0 - 0.07 * under * step(0.3, n2);
		float lum = dot(col, vec3(0.3, 0.59, 0.11));
		col = mix(col, vec3(lum) * 1.06, 0.10 * smoothstep(0.35, 0.8, abs(wn.z)) * step(0.0, wn.z * sign(dot(wn, wpos - CAMERA_POSITION_WORLD)) * -1.0));
	} else {
		float patchy = smoothstep(0.50, 0.72, texture(noise_tex, wpos.xz * 0.11 + 0.3).r);
		col = mix(col, vec3(0.10, 0.14, 0.05), 0.30 * patchy * (0.5 + 0.5 * house));
	}
	col *= mix(0.96, 1.04, house);
	float soot = clamp(dmg * 1.5 - 0.25, 0.0, 1.0) * smoothstep(0.25, 0.75, n1 + dmg * 0.4);
	col = mix(col, vec3(0.012, 0.011, 0.010), soot * 0.9);

	// rain: roofs most of all get darker and shine
	float wet = wetness * mix(0.45, 1.0, step(0.5, UV2.x));
	col *= 1.0 - 0.3 * wet;
	rough = mix(rough, min(rough, 0.4), wet);
	// winter: snow lies on the roofs, a little thinner in patches
	col = mix(col, vec3(0.84, 0.87, 0.92), snow * step(0.5, UV2.x) * (0.80 + 0.18 * smoothstep(0.3, 0.6, n1)));
	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = emi;
}
