shader_type spatial;
// A car seen from afar: everything on it but the paint, as one surface. Each part's colour, roughness, metal and
// glow ride in the texture coordinates (scripts/lod.gd, Bag), so that a hundred parked cars are two draws a model
// and not fourteen.
varying vec3 tint;
varying float rough;
varying float metal;
varying float glow;

void vertex() {
	glow = step(1.5, UV2.x);
	tint = vec3(UV.x, UV.y, UV2.x - 2.0 * glow);
	metal = floor(UV2.y) / 10.0;
	rough = fract(UV2.y) / 0.99;
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = tint * glow * 0.4;
}
