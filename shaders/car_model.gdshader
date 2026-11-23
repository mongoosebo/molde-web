shader_type spatial;
// A car that came as a model with one picture wrapped over all of it (models/volvo.glb, see tools/car_model.py).
// The picture cannot say what is paint and what is glass, so a second picture, `mask`, does: R window glass,
// G headlamps, B tail lamps, A indicators. Paint gets a clear coat that mirrors the sky; glass is dark and
// mirrors it sharply; the lamps shine when the car's lights are on (scripts/car.gd sets `lamps`).
uniform sampler2D colour_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : filter_linear_mipmap_anisotropic, repeat_enable;        // G roughness, B metal
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mask_tex : filter_linear_mipmap, repeat_enable;
uniform float lamps = 0.0;             // 0 by day, towards 1 at night
uniform float braking = 0.0;
global uniform float wetness;

void fragment() {
	vec3 col = texture(colour_tex, UV).rgb;
	vec3 orm = texture(orm_tex, UV).rgb;
	vec4 m = texture(mask_tex, UV);
	float lum = dot(col, vec3(0.30, 0.59, 0.11));
	float sat = max(col.r, max(col.g, col.b)) - min(col.r, min(col.g, col.b));
	// paint: what is light and without colour. It is smooth under its lacquer whatever the picture says.
	float paint = smoothstep(0.45, 0.70, lum) * (1.0 - smoothstep(0.10, 0.22, sat)) * (1.0 - m.r);
	float rough = mix(clamp(orm.g, 0.25, 1.0), 0.38, paint);
	float metal = orm.b * (1.0 - paint) * 0.8;
	// glass: the inside of the car is painted on it; it is darkened to tinted glass, and the sky lies on it
	col = mix(col, col * 0.30 + vec3(0.004, 0.006, 0.008), m.r);
	rough = mix(rough, 0.04, m.r);
	metal = mix(metal, 0.0, m.r);
	float lens = max(m.g, max(m.b, m.a));
	rough = mix(rough, 0.12, lens);
	metal *= 1.0 - lens;
	ALBEDO = col * (1.0 - 0.12 * wetness);
	ROUGHNESS = mix(rough, min(rough, 0.2), wetness * 0.6);
	METALLIC = metal;
	SPECULAR = mix(0.5, 0.9, m.r);
	CLEARCOAT = max(paint, m.r * 0.6);
	CLEARCOAT_ROUGHNESS = 0.06;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.7 * (1.0 - m.r);                   // (glass is flat)
	EMISSION = texture(colour_tex, UV).rgb * (m.g * (0.25 + 5.0 * lamps) + m.b * (0.8 * lamps + 4.0 * braking) + m.a * 0.6 * lamps);
}
