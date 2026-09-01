shader_type canvas_item;

// Roter Rand-Puls (Schaden/Verhungern). `strength` wird per Tween gepulst.
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 1.35;
	float edge = smoothstep(0.35, 0.85, r);
	COLOR = vec4(0.75, 0.03, 0.03, edge * strength);
}
