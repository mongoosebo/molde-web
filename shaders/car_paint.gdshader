shader_type spatial;
// The paint of the car, with the gaps round its doors, bonnet, boot lid and filler flap drawn into it as
// thin dark lines. The lines are worked out from where on the body a point is (in the car's own frame:
// x across, y up, z along, nose at -z), so they are part of the surface, not pieces standing on it.

uniform vec3 paint : source_color = vec3(0.93, 0.93, 0.90);
uniform vec3 gap : source_color = vec3(0.16, 0.16, 0.16);

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

// how much of a line there is at p: a segment from a to b, a few millimetres wide, soft at the edges
float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 d = b - a;
	float t = clamp(dot(p - a, d) / dot(d, d), 0.0, 1.0);
	float dist = length(p - a - d * t);
	float soft = max(fwidth(p.x) + fwidth(p.y), 0.0005);
	return 1.0 - smoothstep(w - soft, w + soft, dist);
}

// how much of a rectangle there is at p (centre c, half-size h), soft at the edges
float rect(vec2 p, vec2 c, vec2 h) {
	vec2 d = abs(p - c) - h;
	float dist = max(d.x, d.y);
	float soft = max(fwidth(p.x) + fwidth(p.y), 0.0005);
	return 1.0 - smoothstep(-soft, soft, dist);
}

void fragment() {
	float line = 0.0;
	float bright = 0.0;       // chrome
	float dark = 0.0;         // black, drawn over the chrome
	float w = 0.0035;
	if (abs(ln.x) > 0.6 && lp.y < 1.03) {
		// the chrome strip under the side windows, following the line of the sills of the glass
		float belt = mix(0.965, 1.005, clamp((lp.z + 1.02) / 2.54, 0.0, 1.0));
		bright = max(bright, rect(lp.zy, vec2(0.25, belt - 0.016), vec2(0.97, 0.007)));
		// door handles: a chrome plate with the dark grip recess under it, and the lock beside it
		for (int k = 0; k < 2; k++) {
			float hz = k == 0 ? -0.02 : 1.02;
			bright = max(bright, rect(lp.zy, vec2(hz, 0.866), vec2(0.072, 0.012)));
			dark = max(dark, rect(lp.zy, vec2(hz, 0.846), vec2(0.060, 0.008)));
			float r = length(lp.zy - vec2(hz + 0.105, 0.822));
			float soft = max(fwidth(lp.z) + fwidth(lp.y), 0.0005);
			bright = max(bright, 1.0 - smoothstep(0.010 - soft, 0.010 + soft, r));
			dark = max(dark, 1.0 - smoothstep(0.003 - soft, 0.003 + soft, r));
		}
	}
	if (lp.y > 1.36 && lp.z > -0.39 && lp.z < 0.93) {
		// the gutter along the edge of the roof, over the doors
		bright = max(bright, rect(vec2(abs(lp.x), 0.0), vec2(0.681, 0.0), vec2(0.007, 1.0)));
	}
	if (abs(ln.x) > 0.6 && lp.y < 1.0) {
		// the flanks: seen from the side, (z, y)
		vec2 p = lp.zy;
		line = max(line, seg(p, vec2(-0.84, 0.31), vec2(-0.84, 0.975), w));
		line = max(line, seg(p, vec2(0.22, 0.31), vec2(0.22, 0.985), w));
		line = max(line, seg(p, vec2(1.22, 0.31), vec2(1.22, 0.995), w));
		line = max(line, seg(p, vec2(-0.84, 0.31), vec2(1.22, 0.31), w));
		if (lp.x > 0.0) {                      // the filler flap, on the right
			line = max(line, seg(p, vec2(1.72, 0.73), vec2(1.88, 0.73), w));
			line = max(line, seg(p, vec2(1.72, 0.87), vec2(1.88, 0.87), w));
			line = max(line, seg(p, vec2(1.72, 0.73), vec2(1.72, 0.87), w));
			line = max(line, seg(p, vec2(1.88, 0.73), vec2(1.88, 0.87), w));
		}
	} else if (ln.y > 0.6 && lp.y < 1.1) {
		// bonnet and boot lid: seen from above, (x, z)
		vec2 p = vec2(abs(lp.x), lp.z);
		line = max(line, seg(p, vec2(0.765, -2.30), vec2(0.765, -1.04), w));
		line = max(line, seg(p, vec2(0.0, -1.04), vec2(0.765, -1.04), w));
		line = max(line, seg(p, vec2(0.765, 1.535), vec2(0.765, 2.31), w));
		line = max(line, seg(p, vec2(0.0, 1.535), vec2(0.765, 1.535), w));
	}
	vec3 col = mix(paint, gap, line * 0.9);
	col = mix(col, vec3(0.78, 0.79, 0.81), bright);
	col = mix(col, vec3(0.04, 0.04, 0.045), dark);
	ALBEDO = col;
	ROUGHNESS = mix(mix(mix(0.32, 0.8, line), 0.2, bright), 0.7, dark);
	METALLIC = mix(mix(0.1 * (1.0 - line), 0.9, bright), 0.0, dark);
}
