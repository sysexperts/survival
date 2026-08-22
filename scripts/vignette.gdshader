shader_type canvas_item;

// Weiche Abdunklung zum Bildrand hin. Zieht den Blick zur Bildmitte und
// nimmt dem Pixelart-Raster die harte Kante am Bildschirmrand.

uniform float strength : hint_range(0.0, 1.0) = 0.30;
uniform float softness : hint_range(0.05, 1.5) = 0.85;
uniform vec3 tint : source_color = vec3(0.04, 0.05, 0.10);

void fragment() {
	float d = length(SCREEN_UV - vec2(0.5)) * 1.4142;
	COLOR = vec4(tint, smoothstep(1.0 - softness, 1.0, d) * strength);
}
