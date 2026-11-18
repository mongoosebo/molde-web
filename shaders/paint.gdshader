shader_type spatial;

// Road paint, a little worn: broken up into flecks where it has been driven over for years, more in some
// places than others. What is worn away shows the asphalt under it. COLOR is the paint (white or yellow).
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
global uniform float wetness;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float place = texture(noise_tex, wpos.xz * 0.023).r;
	float fleck = texture(noise_tex, wpos.xz * 1.7).r * 0.65 + texture(noise_tex, wpos.xz * 5.3 + 0.5).r * 0.35;
	float worn = mix(0.16, 0.50, smoothstep(0.35, 0.75, place));
	if (fleck < worn) {
		discard;
	}
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * mix(0.72, 1.0, smoothstep(worn, worn + 0.25, fleck)) * (1.0 - 0.2 * wetness);
	ROUGHNESS = mix(0.7, 0.4, wetness);
}
