shader_type spatial;
render_mode fog_disabled;

// The landscape outside the map, seen from afar: one coarse grid of real terrain heights. It steps
// down and aside where the map itself is, and fades into the haze with distance.
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float size;
uniform float grid_n;
uniform vec4 map_rect;                  // min x, min z, max x, max z
uniform vec3 haze = vec3(0.36, 0.31, 0.27);      // the colour of the air (scripts/daytime.gd sets it by the hour)
uniform float thick = 1.0;                       // how thick the air is: under 1 on a clear day, when the mountains stand out
global uniform float cloud_down;                 // low cloud: how far it has come down on the mountains, 0 to 1
global uniform float night;

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
	// Green below and snow on the tops, as the Romsdal alps are seen from Molde (note of 18 Nov): dark spruce and
	// pine by the fjord, lighter birch and meadow above, heath and bare rock over the tree line, and snow from
	// about 850 m, lying longest in the hollows and thin on what is steep. Three sizes of mottling give it grain.
	float n3 = texture(noise_tex, wpos.xz * 0.011).r;
	vec3 forest = vec3(0.060, 0.125, 0.055);
	vec3 birch = vec3(0.150, 0.235, 0.085);
	vec3 heath = vec3(0.215, 0.205, 0.115);
	vec3 rock = vec3(0.290, 0.285, 0.280);
	vec3 snow = vec3(0.900, 0.925, 0.960);
	float slope = 1.0 - n.y;
	float hh = h + (n1 - 0.5) * 220.0 + (n2 - 0.5) * 90.0;
	vec3 col = mix(forest, birch, smoothstep(140.0, 420.0, hh));
	col = mix(col, forest * 0.8, smoothstep(0.55, 0.75, n2) * (1.0 - smoothstep(300.0, 500.0, hh)));      // stands of darker wood
	col = mix(col, heath, smoothstep(480.0, 700.0, hh));
	col = mix(col, rock, max(smoothstep(720.0, 980.0, hh), smoothstep(0.22, 0.45, slope) * smoothstep(250.0, 500.0, h)));
	col *= 0.78 + 0.30 * n3 + 0.14 * n2;
	float white = smoothstep(820.0, 1080.0, h + (n2 - 0.5) * 340.0 + (n3 - 0.5) * 120.0) * (1.0 - 0.75 * smoothstep(0.40, 0.68, slope));
	col = mix(col, snow * (0.93 + 0.07 * n3), clamp(white, 0.0, 1.0));
	float fade = 1.0 - exp(-distance(wpos, CAMERA_POSITION_WORLD) * 0.000030 * thick);
	// a band of cloud hanging on the mountains: everything above its ragged underside is in it
	float base = mix(1500.0, 260.0, cloud_down);
	float in_cloud = smoothstep(base - 90.0, base + 70.0, wpos.y + (n1 - 0.5) * 260.0 + (n2 - 0.5) * 90.0) * step(0.02, cloud_down);
	fade = max(fade, in_cloud * 0.97);
	ALBEDO = col * (1.0 - fade);
	EMISSION = haze * fade * mix(1.0, 1.25, in_cloud);
	ROUGHNESS = 0.95;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
