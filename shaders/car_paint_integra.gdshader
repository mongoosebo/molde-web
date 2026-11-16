shader_type spatial;
// The paint of the Integra, with the gaps round its two long doors, the bonnet, the tailgate and the filler
// flap drawn into it, the door handles, and the black rubber along the sills of the side windows.
// Worked out from where on the body a point is (x across, y up, z along, nose at -z).

uniform vec3 paint : source_color = vec3(0.74, 0.035, 0.045);
uniform vec3 gap : source_color = vec3(0.10, 0.02, 0.02);

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
	float dark = 0.0;
	float w = 0.0035;
	if (abs(ln.x) > 0.6 && lp.y < 0.97) {
		vec2 p = lp.zy;
		float belt = mix(0.865, 0.935, clamp((lp.z + 1.08) / 2.86, 0.0, 1.0));
		dark = max(dark, rect(p, vec2(0.36, belt - 0.014), vec2(1.10, 0.008)));          // rubber under the glass
		line = max(line, seg(p, vec2(-0.80, 0.25), vec2(-0.80, 0.865), w));                // one long door a side
		line = max(line, seg(p, vec2(0.36, 0.25), vec2(0.36, 0.885), w));
		line = max(line, seg(p, vec2(-0.80, 0.25), vec2(0.36, 0.25), w));
		// the handle: a flap in the body colour, shown by the line round it and the shadow under it
		line = max(line, seg(p, vec2(0.17, 0.765), vec2(0.29, 0.765), 0.002));
		line = max(line, seg(p, vec2(0.17, 0.725), vec2(0.29, 0.725), 0.004));
		line = max(line, seg(p, vec2(0.17, 0.725), vec2(0.17, 0.765), 0.002));
		line = max(line, seg(p, vec2(0.29, 0.725), vec2(0.29, 0.765), 0.002));
		if (lp.x < 0.0) {                                                                  // the filler flap, on the left
			line = max(line, seg(p, vec2(1.30, 0.62), vec2(1.44, 0.62), w));
			line = max(line, seg(p, vec2(1.30, 0.74), vec2(1.44, 0.74), w));
			line = max(line, seg(p, vec2(1.30, 0.62), vec2(1.30, 0.74), w));
			line = max(line, seg(p, vec2(1.44, 0.62), vec2(1.44, 0.74), w));
		}
	} else if (ln.y > 0.5 && lp.y < 1.0) {
		vec2 p = vec2(abs(lp.x), lp.z);
		line = max(line, seg(p, vec2(0.70, -1.95), vec2(0.735, -1.12), w));                // bonnet: its sides, its rear edge,
		line = max(line, seg(p, vec2(0.0, -1.12), vec2(0.735, -1.12), w));
		line = max(line, seg(p, vec2(0.0, -2.06), vec2(0.45, -2.04), w));                  // and its curved leading edge over the lamps
		line = max(line, seg(p, vec2(0.45, -2.04), vec2(0.70, -1.95), w));
		line = max(line, seg(p, vec2(0.72, 1.74), vec2(0.72, 2.10), w));                   // the tailgate below its glass
		line = max(line, seg(p, vec2(0.0, 2.10), vec2(0.72, 2.10), w));
	}
	vec3 col = mix(paint, gap, line * 0.9);
	col = mix(col, vec3(0.04, 0.04, 0.045), dark);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.22, 0.7, line), 0.75, dark);
	METALLIC = 0.0;
	CLEARCOAT = 0.6 * (1.0 - line) * (1.0 - dark);
	CLEARCOAT_ROUGHNESS = 0.15;
}
