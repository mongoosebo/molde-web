shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

// Grass and small plants close to the player (scripts/grass.gd): tufts of a few blades, each drawn many times.
// They bend in waves that run across a field with the wind, thin out to nothing by `far` metres, and take
// their colour from the tuft (darker at the foot). UV.y is 0 at the foot of a blade and 1 at its tip.
// Further off fewer tufts are drawn (all of them to 22 m, a quarter at the far end), and those that are left
// are wider, so the ground looks as covered for far fewer triangles.
global uniform vec3 wind;
global uniform float wetness;
uniform float far = 60.0;

varying float tip;

void vertex() {
	vec3 foot = MODEL_MATRIX[3].xyz;
	tip = UV.y;
	float dist = distance(foot, CAMERA_POSITION_WORLD);
	float keep = 1.0 - smoothstep(far * 0.6, far, dist);
	float share = mix(1.0, 0.25, smoothstep(22.0, far * 0.75, dist));       // how many of the tufts are drawn at this distance
	float pick = fract(sin(dot(floor(foot.xz * 8.0), vec2(12.9898, 78.233))) * 43758.5453);
	keep *= step(pick, share);                                              // (the others are folded up into a point)
	float spread = min(1.0 / sqrt(share), 1.7);
	vec3 with_wind = vec3(wind.x, 0.0, wind.y);
	float run = sin(dot(foot.xz, wind.xy) * 0.42 - TIME * (1.2 + 2.2 * wind.z)) * 0.6 + sin(foot.x * 1.7 + foot.z * 2.3 + TIME * 3.1) * 0.4;
	float bend = (0.04 + 0.34 * wind.z) * (0.55 + 0.45 * run) * UV.y * UV.y;
	VERTEX = foot + (VERTEX - foot) * vec3(spread, 1.0, spread) * keep + with_wind * bend * keep;
	VERTEX.y -= bend * 0.35 * keep;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * mix(0.45, 1.05, tip) * (1.0 - 0.25 * wetness);
	ROUGHNESS = 0.9;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);      // lit as the ground is, whichever way a blade faces
}
