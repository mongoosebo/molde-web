shader_type spatial;
render_mode world_vertex_coords;

// A tree in the wind (scripts/weather.gd sets `wind`: the way it blows, and how hard from 0 to 1). The trunk
// barely moves, the crown more, the leaves flutter; each tree is out of step with its neighbours. Nothing moves
// when it is calm. The colour is the mesh's own.
global uniform vec3 wind;
global uniform float wetness;

void vertex() {
	vec3 foot = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y - foot.y, 0.0);
	float step_ = foot.x * 0.37 + foot.z * 0.51;
	float gust = 0.6 * sin(TIME * 1.1 + step_) + 0.4 * sin(TIME * 2.3 + step_ * 1.7);
	float bend = wind.z * 0.011 * h * h * (0.55 + 0.45 * gust);
	float leaves = wind.z * 0.06 * smoothstep(2.0, 4.5, h) * sin(TIME * 6.5 + VERTEX.x * 3.1 + VERTEX.z * 2.7 + step_);
	VERTEX += vec3(wind.x, 0.0, wind.y) * bend + vec3(leaves, leaves * 0.3, -leaves);
}

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * (1.0 - 0.2 * wetness);
	ROUGHNESS = 0.95;
}
