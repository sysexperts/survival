shader_type canvas_item;

// Weisser Rand um ein Sprite: faerbt transparente Pixel ein, die direkt an
// eine undurchsichtige Stelle grenzen.
//
// Nur die vier Himmelsrichtungen werden abgetastet, keine Diagonalen. Mit
// Diagonalen bekommen die Treppenkanten der Pixelart an jeder Stufe Rand
// von zwei Seiten und wirken doppelt so dick.

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float thickness : hint_range(0.0, 3.0) = 1.0;
// 1.0 = Original plus Rand (Hover auf einem Baum).
// 0.0 = nur der Rand, Koerper durchsichtig - so sieht man durch ein Objekt
//       hindurch, wo die Figur steht.
uniform float fill_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * thickness;
	float a = 0.0;
	a = max(a, texture(TEXTURE, UV + vec2( px.x, 0.0 )).a);
	a = max(a, texture(TEXTURE, UV + vec2(-px.x, 0.0 )).a);
	a = max(a, texture(TEXTURE, UV + vec2( 0.0,  px.y)).a);
	a = max(a, texture(TEXTURE, UV + vec2( 0.0, -px.y)).a);

	vec4 edge = vec4(outline_color.rgb, outline_color.a * step(0.05, a));
	vec4 body = vec4(base.rgb, base.a * fill_alpha);
	// Undurchsichtige Pixel bleiben Koerper, transparente werden Rand.
	COLOR = mix(edge, body, step(0.05, base.a));
}
