// flame.gdshader — мультяшное пламя спиртовки (S4.3) по референсам ref_burner_heating / ref_burner_flame_boil:
// 5 языков-капель из одного основания у фитиля; снизу маленькое бело-жёлтое ядро, дальше золотисто-жёлтый,
// оранжевый и красно-оранжевая кромка; боковые языки клонятся наружу, все качаются и вздрагивают.
// Рисуется на ColorRect (components/flame/flame.tscn): фитиль — середина прямоугольника на wick_up_px выше его низа
// (скруглённый низ пламени обнимает верх фитиля). Поле «жара» I = max по языкам (1 − (x/полуширина)²)·(1 − v)^core_falloff,
// v — доля высоты языка; полуширина — капля: полуэллипс от низа до «живота» belly, дальше сужение к кончику.
// Полосы цвета — пороги band_levels по I (мягкий край ≈ 1 px через fwidth); кромка чуть прозрачна — стекло видно.
// strength (0…1) задаёт Flame (flame.gd): 0 — погасло, 1 — языки во всю высоту base_height.
// numpy-копия: tools/art/flame_preview.py (поменял шейдер — поменяй там). Собственный код проекта.
shader_type canvas_item;

uniform vec2 rect_size = vec2(190.0, 150.0);
// Фитиль над низом прямоугольника, px: ниже него — только скруглённый низ пламени.
uniform float wick_up_px = 26.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
// Высота самого высокого языка и его полуширина при strength = 1, px; доля размера при strength → 0.
uniform float base_height = 92.0;
uniform float base_width = 44.0;
uniform float min_height = 0.4;
uniform float min_width = 0.65;
// Языки: смещение основания и кончика по x (доли base_width), высота и полуширина (доли), фаза качания.
uniform float tongue_x[5] = {0.0, -0.36, 0.38, -0.16, 0.18};
uniform float tongue_lean[5] = {0.0, -0.6, 0.65, -0.25, 0.3};
uniform float tongue_h[5] = {1.0, 0.6, 0.64, 0.82, 0.78};
uniform float tongue_w[5] = {1.0, 0.55, 0.52, 0.7, 0.68};
uniform float tongue_phase[5] = {0.0, 2.1, 4.0, 1.1, 5.2};
// Капля: «живот» (доля высоты, где язык шире всего), глубина скруглённого низа под фитилём (доля высоты),
// сужение к кончику (степень), наклон набирается к кончику (степень), спад жара к кончику.
uniform float belly = 0.28;
uniform float bottom_depth = 0.2;
uniform float tip_power = 0.9;
uniform float lean_power = 1.6;
uniform float core_falloff = 1.25;
// Качание: размах у кончика, px; скорость; волна вдоль языка. Вздрагивание высоты: доля и скорость.
uniform float sway_px = 7.0;
uniform float sway_speed = 3.1;
uniform float sway_wave = 2.4;
uniform float flicker = 0.07;
uniform float flicker_speed = 9.0;
// Полосы цвета снаружи внутрь: пороги I для кромки, середины, внутреннего слоя и ядра.
uniform vec4 band_levels = vec4(0.04, 0.2, 0.42, 0.76);
uniform vec4 outer_color : source_color = vec4(0.93, 0.3, 0.13, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.55, 0.14, 1.0);
uniform vec4 inner_color : source_color = vec4(1.0, 0.8, 0.25, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.97, 0.84, 1.0);
// Непрозрачность красной кромки (под ней видно стекло и дно колбы); внутренние полосы непрозрачны.
uniform float outer_alpha = 0.85;
uniform float edge_soft = 0.8;

float tongue(vec2 p, int i, float height, float width, float t) {
	float h = height * tongue_h[i] * (1.0 + flicker * sin(t * flicker_speed + tongue_phase[i] * 3.0));
	float v = p.y / h;
	float up = max(v, 0.0);
	float sway = sin(t * sway_speed + tongue_phase[i] + v * sway_wave) * sway_px * up * up * strength;
	float lean = tongue_lean[i] * base_width * pow(up, lean_power);
	float x = p.x - tongue_x[i] * base_width - lean - sway;
	float e = (belly - v) / (belly + bottom_depth);
	float bottom = sqrt(max(1.0 - e * e, 0.0));
	float top = pow(clamp((1.0 - v) / (1.0 - belly), 0.0, 1.0), tip_power);
	float hw = width * tongue_w[i] * mix(bottom, top, step(belly, v));
	float q = x / max(hw, 0.001);
	return (1.0 - q * q) * pow(clamp(1.0 - up, 0.0, 1.0), core_falloff);
}

void fragment() {
	// px от фитиля: x вправо, y вверх.
	vec2 p = vec2((UV.x - 0.5) * rect_size.x, (1.0 - UV.y) * rect_size.y - wick_up_px);
	float height = base_height * mix(min_height, 1.0, strength);
	float width = base_width * mix(min_width, 1.0, strength);
	float heat = -1.0;
	for (int i = 0; i < 5; i++) {
		heat = max(heat, tongue(p, i, height, width, TIME));
	}
	float e = max(fwidth(heat), 0.002) * edge_soft;
	float inner = smoothstep(band_levels.y - e, band_levels.y + e, heat);
	float alpha = smoothstep(band_levels.x - e, band_levels.x + e, heat) * mix(outer_alpha, 1.0, inner)
			* smoothstep(0.0, 0.08, strength);
	vec3 c = mix(outer_color.rgb, mid_color.rgb, inner);
	c = mix(c, inner_color.rgb, smoothstep(band_levels.z - e, band_levels.z + e, heat));
	c = mix(c, core_color.rgb, smoothstep(band_levels.w - e, band_levels.w + e, heat));
	COLOR = vec4(c, alpha) * COLOR;
}
