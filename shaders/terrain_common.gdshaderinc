// Ground cover shared by the far terrain and the 1 m cells around the player.
// mask_tex:  R road, G footpath, B tree canopy, 1-A water.
// mask2_tex: R mown grass (parks, pitches, gardens), G fields, B bog, A bare rock and sand.
// Close to the camera the colour is broken up by a turf or stone texture, which also dents the surface.
uniform sampler2D mask_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D mask2_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D turf_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D turf_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform float wetness;            // 0 dry to 1 soaked (scripts/weather.gd)
uniform vec2 world_origin;
uniform vec2 world_size;

vec3 ground_colour(vec3 wpos, inout vec3 n, float h, float dist, out float rough) {
	vec2 uv = (wpos.xz - world_origin) / world_size;
	vec4 m = texture(mask_tex, uv);
	vec4 m2 = texture(mask2_tex, uv);
	float n1 = texture(noise_tex, wpos.xz * 0.02).r;
	float n2 = texture(noise_tex, wpos.xz * 0.31).r;
	float n3 = texture(noise_tex, wpos.xz * 0.0031).r;

	vec3 grass = mix(vec3(0.085, 0.105, 0.045), vec3(0.17, 0.15, 0.07), n3) * (0.75 + 0.5 * n2);
	vec3 lawn = mix(vec3(0.060, 0.115, 0.035), vec3(0.085, 0.135, 0.045), n1) * (0.9 + 0.2 * n2);
	vec3 field = mix(vec3(0.20, 0.175, 0.075), vec3(0.11, 0.15, 0.05), smoothstep(0.35, 0.65, n3)) * (0.85 + 0.3 * n2);
	vec3 bog = mix(vec3(0.085, 0.075, 0.035), vec3(0.15, 0.12, 0.05), n1) * (0.8 + 0.4 * n2);
	vec3 forest = vec3(0.045, 0.058, 0.035) * (0.8 + 0.4 * n1);
	vec3 rock = vec3(0.17, 0.165, 0.16) * (0.7 + 0.6 * n1);
	vec3 shore = vec3(0.20, 0.185, 0.16) * (0.7 + 0.6 * n2);
	vec3 gravel = vec3(0.20, 0.17, 0.13) * (0.75 + 0.5 * n2);
	vec3 asphalt = mix(vec3(0.04, 0.04, 0.045), vec3(0.075, 0.07, 0.065), n1) * (0.8 + 0.4 * n2);

	vec3 col = mix(grass, lawn, m2.r);
	col = mix(col, field, m2.g);
	col = mix(col, bog, m2.b);
	col = mix(col, forest, m.b * (1.0 - 0.6 * m2.r));
	float slope = 1.0 - n.y;
	float stony = smoothstep(0.22, 0.42, slope + (n1 - 0.5) * 0.1);
	stony = max(stony, m2.a);
	col = mix(col, rock, stony);
	float beach = 1.0 - smoothstep(0.6, 2.2, h + (n1 - 0.5));
	col = mix(col, shore, beach);
	stony = max(stony, beach);
	col = mix(col, vec3(0.03, 0.05, 0.05), 1.0 - smoothstep(-3.0, 0.0, h));
	float path = smoothstep(0.3, 0.6, m.g) * 0.85;
	col = mix(col, gravel, path);
	stony = max(stony, path);
	// m.r is 1 where the ground itself is the road (gravel, runway) and about 0.5 where asphalt has been laid on
	// it: that is tinted only from afar, where the laid asphalt is not built
	float road = mix(smoothstep(0.68, 0.86, m.r), smoothstep(0.17, 0.3, m.r), smoothstep(110.0, 165.0, dist));
	col = mix(col, asphalt, road);
	float lake = smoothstep(0.4, 0.6, 1.0 - m.a);
	col = mix(col, vec3(0.02, 0.05, 0.07), lake);

	float near = (1.0 - smoothstep(25.0, 130.0, dist)) * (1.0 - lake) * (1.0 - road);
	if (near > 0.01) {
		vec3 dt = mix(texture(turf_tex, wpos.xz * 0.5).rgb, texture(stone_tex, wpos.xz * 0.33).rgb, stony);
		vec3 dn = mix(texture(turf_nrm, wpos.xz * 0.5).xyz, texture(stone_nrm, wpos.xz * 0.33).xyz, stony) * 2.0 - 1.0;
		col *= mix(vec3(1.0), dt * 2.0, near * 0.85);
		n = normalize(n + vec3(dn.x, 0.0, dn.y) * 0.55 * near);
	}
	rough = mix(0.95, 0.12, lake);
	// rain: everything darker, and stone, gravel and asphalt shine
	col *= 1.0 - 0.28 * wetness;
	rough = mix(rough, min(rough, mix(0.8, 0.35, max(stony, road))), wetness);
	return col;
}
