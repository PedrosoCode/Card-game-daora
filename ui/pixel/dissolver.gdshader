shader_type canvas_item;
// Desfaz a carta em pixels de cima para baixo (pontilhado Bayer 4x4 + borda acesa):
// a morte em pixel art. cell = pixels de tela por pixel da arte (o padrão casa com
// a grade da arte); a altura da carta vem do vértice (filhos usam o material do pai).
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float cell = 1.0;
uniform float card_height = 192.0;
uniform vec4 edge_color : source_color = vec4(0.75, 1.0, 0.6, 1.0);

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
varying float vy;

void vertex() {
	vy = clamp(VERTEX.y / card_height, 0.0, 1.0);
}

void fragment() {
	vec4 c = COLOR;
	ivec2 p = ivec2(floor(FRAGCOORD.xy / max(cell, 1.0)));
	float t = (BAYER[(p.y % 4) * 4 + (p.x % 4)] + 0.5) / 16.0;
	float limiar = vy * 0.65 + t * 0.35;          // o topo some primeiro, com borda pontilhada
	float corte = progress * 1.05;
	if (limiar < corte) {
		c.a = 0.0;
	} else if (limiar < corte + 0.05 && progress > 0.0) {
		c.rgb = edge_color.rgb;
	}
	COLOR = c;
}
