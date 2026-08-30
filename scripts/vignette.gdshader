shader_type canvas_item;

// Sanfte Vignette (dunklere Bildraender) - gibt der Szene Tiefe/Stimmung.
// Liest NICHT den Bildschirm (funktioniert auch im GL-Compatibility-Renderer),
// sondern legt nur eine transparente-zur-Mitte, dunkle-am-Rand Maske drueber.

uniform float strength : hint_range(0.0, 1.0) = 0.42;
uniform float start : hint_range(0.0, 1.5) = 0.58;   // ab hier faengt das Abdunkeln an
uniform vec4 tint : source_color = vec4(0.02, 0.02, 0.06, 1.0);

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 1.4142;          // 0 in der Mitte, ~1 in den Ecken
	float v = smoothstep(start, 1.0, r) * strength;
	COLOR = vec4(tint.rgb, v);
}
