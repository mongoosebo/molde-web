shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

// A flag on a flagpole: the Norwegian flag, waving the way the wind blows and harder the more it blows; in a
// calm it hangs down the pole. The mesh is a flat strip whose UV says where on the flag a point is (x along it
// from the pole, y down it); the shader puts it in the air.
global uniform vec3 wind;

const float LEN = 2.2;
const float HIGH = 1.6;

void vertex() {
	vec3 top = MODEL_MATRIX[3].xyz;                        // where the flag's upper corner is tied to the pole
	vec3 with_wind = normalize(vec3(wind.x, 0.0, wind.y));
	vec3 across = vec3(-with_wind.z, 0.0, with_wind.x);
	float lift = smoothstep(0.03, 0.35, wind.z);            // how far the wind holds it out
	float step_ = top.x * 0.9 + top.z * 1.3;
	// along the flag: out with the wind, sagging the less it blows
	float out_ = UV.x * LEN;
	vec3 along = normalize(with_wind * (0.15 + 0.85 * lift) + vec3(0.0, -1.0, 0.0) * (1.0 - 0.9 * lift));
	float wave = sin(out_ * 3.2 - TIME * (3.0 + 9.0 * wind.z) + step_) * 0.16 + sin(out_ * 7.1 - TIME * (5.0 + 14.0 * wind.z) + step_ * 2.0) * 0.05;
	wave *= UV.x * (0.25 + 0.75 * lift);
	VERTEX = top + along * out_ + vec3(0.0, -1.0, 0.0) * UV.y * HIGH * mix(0.55, 1.0, lift) + across * wave + vec3(0.0, wave * 0.3, 0.0);
	NORMAL = across;
}

void fragment() {
	// red, with a blue cross outlined in white, nearer the pole (22 by 16 parts)
	vec2 p = vec2(UV.x * 22.0, UV.y * 16.0);
	vec3 col = vec3(0.73, 0.05, 0.10);
	if ((p.x > 6.0 && p.x < 10.0) || (p.y > 6.0 && p.y < 10.0)) {
		col = vec3(0.93);
	}
	if ((p.x > 7.0 && p.x < 9.0) || (p.y > 7.0 && p.y < 9.0)) {
		col = vec3(0.0, 0.10, 0.36);
	}
	ALBEDO = col;
	ROUGHNESS = 0.8;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
