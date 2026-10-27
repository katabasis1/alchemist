// ingredient.gdshader — материал ингредиента: вспышка (компонент Flash) + распад при помоле (S2.3, S2.3a).
// Вспышка: те же параметры, что у components/flash/flash.gdshader (flash_color, flash_amount), поэтому Flash работает
// с этим материалом без изменений.
// Распад (crumble 0…1), по референсу docs/art/refs/ref_mortar_herbs_crushed.jpg: предмет трескается на неровные
// куски (ячейки Вороного), трещины растут, куски чуть расходятся и оседают вниз (в порошок, за передний край
// чаши), каждый кусок в свой момент крошится от краёв внутрь. По краю разлома — пудра цвета смеси и искристая
// каёмка (glint), весь предмет понемногу «пылится». crumble = 1 — ничего не осталось.
// Значения задаёт IngredientItem.set_crumble() (scenes/ingredient/ingredient_item.gd), цвет — смесь в ступке.
// Приём «dissolve with glowing burn edge» — godotshaders.com (идея, код свой; docs/THIRD_PARTY.md).
// Хэш без синуса — Dave Hoskins (MIT). Копия для макета: tools/art/mortar_preview.py (shade_crumble).
shader_type canvas_item;

uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform float crumble : hint_range(0.0, 1.0) = 0.0;
uniform vec4 crumb_color : source_color = vec4(0.82, 0.72, 0.52, 1.0);
uniform vec4 glint_color : source_color = vec4(1.0, 0.93, 0.7, 1.0);
// Кусков по стороне картинки; ширина трещин и пудряной каёмки — в долях ячейки.
uniform float cells = 6.0;
uniform float crack_width = 0.06;
uniform float edge_width = 0.14;
// Рваный край кусков: сила и частота шума.
uniform float ragged = 0.14;
uniform float ragged_scale = 26.0;
// Насколько куски расходятся и оседают к концу (в долях картинки), насколько предмет пылится.
uniform float spread = 0.06;
uniform float sink = 0.32;
uniform float dust_tint = 0.4;

varying vec4 vertex_color;

void vertex() {
	vertex_color = COLOR;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 w = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), w.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), w.x), w.y);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.103, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

void fragment() {
	vec4 c = COLOR;
	if (crumble > 0.0) {
		vec2 g = UV * cells;
		vec2 gi = floor(g);
		vec2 gf = g - gi;
		float f1 = 8.0;
		float f2 = 8.0;
		vec2 id1 = gi;
		vec2 seed1 = vec2(0.5);
		for (int j = -1; j <= 1; j++) {
			for (int k = -1; k <= 1; k++) {
				vec2 o = vec2(float(j), float(k));
				vec2 sp = o + 0.1 + 0.8 * hash22(gi + o);
				float d = length(sp - gf);
				if (d < f1) {
					f2 = f1;
					f1 = d;
					id1 = gi + o;
					seed1 = (gi + sp) / cells;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
		float edge_d = 0.5 * (f2 - f1) + (vnoise(UV * ragged_scale) - 0.5) * ragged;
		// Каждый кусок крошится в своё время: начало start, длительность 0.45.
		float start = hash12(id1 * 1.7 + 4.0) * 0.55;
		float e = clamp((crumble - start) / 0.45, 0.0, 1.0);
		float cut = max(crack_width * smoothstep(0.0, 0.3, crumble), e * 0.6);
		// Куски расходятся от центра и оседают вниз.
		vec2 shift = (seed1 - vec2(0.5, 0.55)) * spread * crumble + vec2(0.0, sink * pow(crumble, 1.3));
		vec2 suv = UV - shift;
		vec4 tc = texture(TEXTURE, suv) * vertex_color;
		float inside = step(0.0, suv.x) * step(suv.x, 1.0) * step(0.0, suv.y) * step(suv.y, 1.0);
		float vis = smoothstep(cut, cut + 0.03, edge_d) * inside;
		float band = 1.0 - smoothstep(cut, cut + edge_width, edge_d);
		tc.rgb = mix(tc.rgb, crumb_color.rgb, clamp(crumble * dust_tint + band * 0.75, 0.0, 1.0));
		float glint = (1.0 - smoothstep(cut, cut + 0.05, edge_d)) * step(0.001, e);
		tc.rgb += glint_color.rgb * glint * 0.55;
		c = vec4(tc.rgb, tc.a * vis);
	}
	// Альфу вспышка не трогает, чтобы вспыхивал только силуэт.
	c.rgb = mix(c.rgb, flash_color.rgb, flash_amount * flash_color.a);
	COLOR = c;
}
