shader_type spatial;
render_mode fog_disabled;

// The landscape outside the map, seen from afar: one coarse grid of real terrain heights. It steps
// down and aside where the map itself is, and fades into the haze with distance.
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float size;
uniform float grid_n;
uniform vec4 map_rect;                  // min x, min z, max x, max z
uniform vec3 haze = vec3(0.36, 0.31, 0.27);

varying vec3 wpos;

float h_at(vec2 p) {
	vec2 uv = p / size + 0.5;
	return textureLod(height_tex, (uv * (grid_n - 1.0) + 0.5) / grid_n, 0.0).r;
}

float outside(vec2 p) {                 // metres outside the map; 0 inside it
	vec2 d = max(max(map_rect.xy - p, p - map_rect.zw), vec2(0.0));
	return length(d);
}

void vertex() {
	float h = h_at(VERTEX.xz);
	VERTEX.y = h - 25.0 * (1.0 - smoothstep(0.0, 600.0, outside(VERTEX.xz)));
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float h = h_at(wpos.xz);
	if (outside(wpos.xz) < 1.0 || h < 0.8) {
		discard;
	}
	float e = size / (grid_n - 1.0);
	vec3 n = normalize(vec3(h_at(wpos.xz - vec2(e, 0.0)) - h_at(wpos.xz + vec2(e, 0.0)), 2.0 * e,
			h_at(wpos.xz - vec2(0.0, e)) - h_at(wpos.xz + vec2(0.0, e))));
	float n1 = texture(noise_tex, wpos.xz * 0.0004).r;
	float n2 = texture(noise_tex, wpos.xz * 0.003).r;
	vec3 forest = vec3(0.05, 0.065, 0.04);
	vec3 heath = vec3(0.14, 0.12, 0.07);
	vec3 rock = vec3(0.17, 0.165, 0.16);
	vec3 snow = vec3(0.80, 0.82, 0.85);
	float slope = 1.0 - n.y;
	vec3 col = mix(forest, heath, smoothstep(380.0, 620.0, h + (n1 - 0.5) * 200.0));
	col = mix(col, rock, max(smoothstep(700.0, 1000.0, h + (n2 - 0.5) * 150.0), smoothstep(0.25, 0.5, slope)));
	col = mix(col, snow, smoothstep(950.0, 1250.0, h + (n2 - 0.5) * 300.0) * (1.0 - smoothstep(0.45, 0.7, slope)));
	float fade = 1.0 - exp(-distance(wpos, CAMERA_POSITION_WORLD) * 0.000045);
	ALBEDO = col * (1.0 - fade);
	EMISSION = haze * fade;
	ROUGHNESS = 0.95;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
