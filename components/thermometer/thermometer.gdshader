// thermometer.gdshader — термометр Горелки (S4.3): столбик и цветные зоны за стеклом prop_thermometer.png.
// Рисуется на Sprite2D с текстурой термометра (components/thermometer/thermometer.tscn). Внутри полости (трубка +
// шарик) — фон зон снизу вверх: кремовый до первой зоны, дальше бледный цвет зоны; границы — тёмные риски; поверх —
// красно-оранжевый столбик со скруглённой макушкой и бликом, шарик залит целиком. Затем сверху — сама текстура
// (стекло, латунь, планка) со своей прозрачностью; короткие риски границ продолжаются на планке справа от трубки.
// Зона, в которой сейчас макушка столбика, чуть ярче (где мы сейчас). Значения задаёт Thermometer (thermometer.gd).
// Геометрия — px холста текстуры (128×512, ASSET_REGISTRY: prop_thermometer).
// numpy-копия: tools/art/thermometer_preview.py (поменял шейдер — поменяй там). Собственный код проекта.
shader_type canvas_item;

// Полость: внутренние края трубки по x, верх трубки, шарик.
uniform vec2 tube_x = vec2(55.5, 72.5);
uniform float tube_top = 90.0;
uniform vec2 bulb_center = vec2(64.5, 398.0);
uniform float bulb_radius = 35.0;
// Шкала: значение 0 — у шарика (scale_bottom), 1 — у верха трубки (scale_top).
uniform float scale_bottom = 362.0;
uniform float scale_top = 104.0;
uniform float value : hint_range(0.0, 1.0) = 0.0;
// Зоны: начало каждой в долях шкалы (по возрастанию) и цвет; до первой — base_color.
uniform int zone_count = 0;
uniform float zone_from[8];
uniform vec4 zone_colors[8];
uniform vec4 base_color : source_color = vec4(0.97, 0.91, 0.76, 1.0);
// Насколько фон зоны берёт её цвет (остальное — base_color) и насколько ярче зона под макушкой столбика.
uniform float zone_tint : hint_range(0.0, 1.0) = 0.8;
uniform float active_glow : hint_range(0.0, 1.0) = 0.3;
// Тень по краям трубки (объём цилиндра).
uniform float tube_shade : hint_range(0.0, 1.0) = 0.22;
// Столбик: полуширина в трубке, зазор до стекла в шарике, цвет и блик.
uniform float column_half_px = 5.5;
uniform float bulb_gap_px = 5.0;
uniform vec4 column_color : source_color = vec4(0.9, 0.24, 0.12, 1.0);
uniform vec4 column_light : source_color = vec4(1.0, 0.66, 0.46, 1.0);
uniform float column_edge_shade : hint_range(0.0, 1.0) = 0.35;
// Риски границ зон: цвет, толщина; на планке — от x до x.
uniform vec4 tick_color : source_color = vec4(0.33, 0.14, 0.06, 1.0);
uniform float tick_px = 1.6;
uniform float tick_alpha : hint_range(0.0, 1.0) = 0.7;
uniform vec2 plank_tick_x = vec2(75.0, 83.0);

float scale_y(float s) {
	return mix(scale_bottom, scale_top, s);
}

float tick_line(float py, float y) {
	return 1.0 - smoothstep(tick_px * 0.5, tick_px * 0.5 + 1.0, abs(py - y));
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 p = UV / TEXTURE_PIXEL_SIZE;
	float cx = (tube_x.x + tube_x.y) * 0.5;
	float half_w = (tube_x.y - tube_x.x) * 0.5;
	// Полость: трубка открыта вниз, в шарик.
	float d_tube = max(abs(p.x - cx) - half_w, tube_top - p.y);
	d_tube = max(d_tube, p.y - bulb_center.y);
	float d_bulb = length(p - bulb_center) - bulb_radius;
	float cavity = 1.0 - smoothstep(-0.5, 0.5, min(d_tube, d_bulb));

	// Фон зон.
	float s = (scale_bottom - p.y) / (scale_bottom - scale_top);
	vec3 back = base_color.rgb;
	int here = -1;
	int active = -1;
	for (int i = 0; i < 8; i++) {
		if (i >= zone_count) {
			break;
		}
		if (s >= zone_from[i]) {
			here = i;
		}
		if (value >= zone_from[i]) {
			active = i;
		}
	}
	if (here >= 0) {
		back = mix(base_color.rgb, zone_colors[here].rgb, zone_tint);
		if (here == active) {
			back = mix(back, zone_colors[here].rgb, active_glow);
		}
	}
	float u = clamp((p.x - cx) / half_w, -1.0, 1.0);
	back *= 1.0 - tube_shade * u * u * step(p.y, scale_bottom);
	float ticks = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= zone_count) {
			break;
		}
		ticks = max(ticks, tick_line(p.y, scale_y(zone_from[i])));
	}
	back = mix(back, tick_color.rgb, ticks * tick_alpha * step(p.y, scale_bottom));

	// Столбик: капсула в трубке (макушка скруглена) + шарик.
	float top_y = scale_y(value);
	float dx = abs(p.x - cx);
	float d_col_tube = p.y < top_y ? length(vec2(dx, p.y - top_y)) - column_half_px : dx - column_half_px;
	d_col_tube = max(d_col_tube, p.y - bulb_center.y);
	float d_col_bulb = length(p - bulb_center) - (bulb_radius - bulb_gap_px);
	float d_col = min(d_col_tube, d_col_bulb);
	float column = 1.0 - smoothstep(-0.5, 0.5, d_col);
	vec3 col = column_color.rgb;
	float stripe = 1.0 - smoothstep(0.0, 0.45, abs((p.x - cx) / column_half_px + 0.4));
	float in_bulb = 1.0 - smoothstep(-0.5, 0.5, d_col_bulb);
	vec2 glint_c = bulb_center + vec2(-0.38, -0.38) * (bulb_radius - bulb_gap_px);
	float glint = 1.0 - smoothstep(0.0, (bulb_radius - bulb_gap_px) * 0.42, length(p - glint_c));
	col = mix(col, column_light.rgb, max(stripe * (1.0 - in_bulb), glint * in_bulb) * 0.85);
	col *= mix(1.0 - column_edge_shade, 1.0, smoothstep(0.0, 2.5, -d_col));
	vec3 inner = mix(back, col, column);

	vec3 rgb = mix(tex.rgb, mix(inner, tex.rgb, tex.a), cavity);
	float alpha = max(cavity, tex.a);
	// Риски на планке справа от трубки.
	float on_plank = step(plank_tick_x.x, p.x) * step(p.x, plank_tick_x.y);
	rgb = mix(rgb, tick_color.rgb, ticks * on_plank * tex.a);
	COLOR = vec4(rgb, alpha) * COLOR;
}
