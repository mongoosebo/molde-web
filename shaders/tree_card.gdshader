shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// A far tree: a picture of the tree (taken from its model when the game starts) on a flat card that turns
// toward the camera about its upright axis. It leans a little with the wind, like the near trees.
uniform sampler2D card : filter_linear_mipmap, repeat_disable;
global uniform vec3 wind;
global uniform float wetness;

void vertex() {
	vec3 foot = MODEL_MATRIX[3].xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - foot;
	vec3 side = normalize(vec3(to_cam.z, 0.0, -to_cam.x));
	float tall = length(MODEL_MATRIX[1].xyz);
	float wide = length(MODEL_MATRIX[0].xyz);
	float h = VERTEX.y * tall;
	float step_ = foot.x * 0.37 + foot.z * 0.51;
	float bend = wind.z * 0.011 * h * h * (0.55 + 0.45 * sin(TIME * 1.1 + step_));
	vec3 world_pos = foot + side * (VERTEX.x * wide) + vec3(0.0, h, 0.0) + vec3(wind.x, 0.0, wind.y) * bend;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world_pos, 1.0)).xyz;
	NORMAL = normalize((inverse(MODEL_MATRIX) * vec4(normalize(vec3(to_cam.x, 0.6 * length(to_cam.xz), to_cam.z)), 0.0)).xyz);
}

void fragment() {
	vec4 c = texture(card, UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * (1.0 - 0.2 * wetness);
	ROUGHNESS = 0.95;
}
