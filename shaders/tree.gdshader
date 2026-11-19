shader_type spatial;
render_mode world_vertex_coords;

// A tree in the wind (scripts/weather.gd sets `wind`: the way it blows, and how hard from 0 to 1). The trunk
// barely moves, the crown more, the leaves flutter; each tree is out of step with its neighbours. Nothing moves
// when it is calm. The colour is the mesh's own.
global uniform float snow;
global uniform vec3 wind;
global uniform float wetness;
uniform float leafy = 0.0;      // 1 for the trees that drop their leaves: bare twigs in winter

varying vec3 rel;

void vertex() {
	vec3 foot = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y - foot.y, 0.0);
	float step_ = foot.x * 0.37 + foot.z * 0.51;
	float gust = 0.6 * sin(TIME * 1.1 + step_) + 0.4 * sin(TIME * 2.3 + step_ * 1.7);
	float bend = wind.z * 0.011 * h * h * (0.55 + 0.45 * gust);
	float leaves = wind.z * 0.06 * smoothstep(2.0, 4.5, h) * sin(TIME * 6.5 + VERTEX.x * 3.1 + VERTEX.z * 2.7 + step_);
	rel = VERTEX - foot;
	VERTEX += vec3(wind.x, 0.0, wind.y) * bend + vec3(leaves, leaves * 0.3, -leaves);
}

void fragment() {
	vec3 own = pow(COLOR.rgb, vec3(2.2));
	float lay = snow * 0.45;
	// winter: where the leaves were, only twigs are left (thin lines running up and out round the crown)
	if (leafy > 0.5 && snow > 0.5 && COLOR.g > COLOR.r * 1.08 && COLOR.g > COLOR.b) {
		float a = atan(rel.z, rel.x);
		float up = rel.y / max(length(MODEL_MATRIX[1].xyz), 0.01);
		// boughs going up and out from the trunk, each a little crooked, and thinner twigs between them
		float t1 = abs(fract(a * 1.43 + 0.10 * sin(up * 2.3 + a * 3.0)) - 0.5);
		float t2 = abs(fract(a * 3.50 + 0.22 * sin(up * 3.1 + a * 5.0) + 0.37) - 0.5);
		if (t1 > 0.045 && t2 > 0.035) {
			discard;
		}
		own = vec3(0.045, 0.035, 0.03);
		lay = snow * 0.30;
	}
	ALBEDO = mix(own * (1.0 - 0.2 * wetness), vec3(0.84, 0.87, 0.92), lay);
	ROUGHNESS = 0.95;
}
