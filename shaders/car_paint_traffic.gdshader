shader_type spatial;
// The paint of a car in the traffic (scripts/traffic_car.gd): as shaders/car_paint.gdshader, the gaps round the
// doors, the bonnet and the boot lid and the door handles are drawn into the paint, but where they lie is given
// in numbers, so the one shader serves every model. The colour is given per car (many cars share one body).
// Positions are in the car's own frame: x across, y up, z along, nose at -z.

instance uniform vec3 paint : source_color = vec3(0.8, 0.8, 0.8);
uniform vec3 gap : source_color = vec3(0.10, 0.10, 0.10);
uniform vec3 doors = vec3(-0.8, 0.2, 1.2);      // z of the front edge of the front door, of the pillar between the doors, of the rear edge of the rear door
uniform float two_door = 0.0;                   // 1: no rear door (the line at the pillar is the door's rear edge)
uniform float sill_y = 0.30;                    // the lower edge of the doors
uniform vec4 belt = vec4(-1.0, 1.5, 0.95, 1.0); // cabin from z, to z; height of the window sills at its front, at its rear
uniform vec3 hood = vec3(0.76, -2.2, -1.0);     // half width of the bonnet, z of its front, z of its rear edge
uniform vec3 boot = vec3(0.76, 99.0, 99.0);     // the same for a boot lid (front z of 50 or more: there is none)
uniform float trim = 0.0;                       // a bright strip under the side windows: 0 none, 1 chrome
uniform float flap_z = 1.7;                     // the filler flap, on the right

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 d = b - a;
	float t = clamp(dot(p - a, d) / dot(d, d), 0.0, 1.0);
	float dist = length(p - a - d * t);
	float soft = max(fwidth(p.x) + fwidth(p.y), 0.0005);
	return 1.0 - smoothstep(w - soft, w + soft, dist);
}

float rect(vec2 p, vec2 c, vec2 h) {
	vec2 d = abs(p - c) - h;
	float dist = max(d.x, d.y);
	float soft = max(fwidth(p.x) + fwidth(p.y), 0.0005);
	return 1.0 - smoothstep(-soft, soft, dist);
}

void fragment() {
	float line = 0.0;
	float bright = 0.0;
	float dark = 0.0;
	float w = 0.004;
	float sill_at = mix(belt.z, belt.w, clamp((lp.z - belt.x) / (belt.y - belt.x), 0.0, 1.0));
	if (abs(ln.x) > 0.6 && lp.y < sill_at + 0.01) {
		vec2 p = lp.zy;
		float top = sill_at - 0.012;
		line = max(line, seg(p, vec2(doors.x, sill_y), vec2(doors.x, top), w));
		line = max(line, seg(p, vec2(doors.y, sill_y), vec2(doors.y, top), w));
		float end = mix(doors.z, doors.y, two_door);
		line = max(line, seg(p, vec2(doors.z, sill_y), vec2(doors.z, top), w) * (1.0 - two_door));
		line = max(line, seg(p, vec2(doors.x, sill_y), vec2(end, sill_y), w));
		// a handle on each door, near its rear edge: a bar in the body colour's shade with a dark recess under it
		for (int k = 0; k < 2; k++) {
			if (k == 1 && two_door > 0.5) {
				break;
			}
			float hz = (k == 0 ? doors.y : doors.z) - 0.17;
			float hy = mix(belt.z, belt.w, clamp((hz - belt.x) / (belt.y - belt.x), 0.0, 1.0)) - 0.105;
			bright = max(bright, rect(p, vec2(hz, hy), vec2(0.075, 0.011)) * 0.55);
			dark = max(dark, rect(p, vec2(hz, hy - 0.019), vec2(0.066, 0.007)));
		}
		bright = max(bright, rect(p, vec2((belt.x + belt.y) * 0.5 + 0.12, sill_at - 0.016), vec2((belt.y - belt.x) * 0.5 - 0.30, 0.006)) * trim);
		if (lp.x > 0.0) {
			line = max(line, seg(p, vec2(flap_z - 0.08, top - 0.21), vec2(flap_z + 0.08, top - 0.21), w));
			line = max(line, seg(p, vec2(flap_z - 0.08, top - 0.08), vec2(flap_z + 0.08, top - 0.08), w));
			line = max(line, seg(p, vec2(flap_z - 0.08, top - 0.21), vec2(flap_z - 0.08, top - 0.08), w));
			line = max(line, seg(p, vec2(flap_z + 0.08, top - 0.21), vec2(flap_z + 0.08, top - 0.08), w));
		}
	} else if (ln.y > 0.55 && lp.y < max(belt.z, belt.w) + 0.12) {
		vec2 p = vec2(abs(lp.x), lp.z);
		line = max(line, seg(p, vec2(hood.x, hood.y), vec2(hood.x, hood.z), w));
		line = max(line, seg(p, vec2(0.0, hood.z), vec2(hood.x, hood.z), w));
		if (boot.y < 50.0) {
			line = max(line, seg(p, vec2(boot.x, boot.y), vec2(boot.x, boot.z), w));
			line = max(line, seg(p, vec2(0.0, boot.y), vec2(boot.x, boot.y), w));
		}
	}
	vec3 col = mix(paint, gap, line * 0.9);
	col = mix(col, vec3(0.78, 0.79, 0.81), bright);
	col = mix(col, vec3(0.04, 0.04, 0.045), dark);
	ALBEDO = col;
	ROUGHNESS = mix(mix(mix(0.30, 0.8, line), 0.2, bright), 0.7, dark);
	METALLIC = mix(mix(0.25 * (1.0 - line), 0.9, bright), 0.0, dark);
}
