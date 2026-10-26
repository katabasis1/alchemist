// zone_gauge.gdshader — вертикальная шкала с зоной «идеально» (помол ступки, позже — градусник горелки).
// Рисуется на ColorRect (components/zone_gauge/zone_gauge.tscn) целиком: рамка, тёмное окно, заливка снизу,
// полоса зоны с обводкой, риска на уровне заливки. Значения задаёт ZoneGauge (zone_gauge.gd).
// Скругления считаются в пикселях: rect_size скрипт обновляет при изменении размера.
// Собственный код проекта (лицензия проекта), заимствований нет.
shader_type canvas_item;

uniform vec2 rect_size = vec2(36.0, 240.0);
uniform float value : hint_range(0.0, 1.0) = 0.0;
uniform float zone_from : hint_range(0.0, 1.0) = 0.7;
uniform float zone_to : hint_range(0.0, 1.0) = 0.85;
uniform vec4 fill_color : source_color = vec4(0.94, 0.63, 0.05, 1.0);
uniform vec4 back_color : source_color = vec4(0.26, 0.13, 0.05, 0.85);
uniform vec4 frame_color : source_color = vec4(0.26, 0.11, 0.05, 1.0);
uniform vec4 rim_color : source_color = vec4(0.75, 0.63, 0.39, 1.0);
uniform vec4 zone_color : source_color = vec4(0.49, 0.85, 0.34, 1.0);
uniform vec4 tick_color : source_color = vec4(0.99, 0.95, 0.77, 1.0);
// Толщина контура и латунного ободка, пиксели.
uniform float frame_px = 3.0;
uniform float rim_px = 4.0;
uniform float tick_px = 3.0;
// Подсветка зоны: 0 — спокойная, 1 — мигает (обучение: «доведи до зелёного»).
uniform float zone_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_speed = 6.0;

// Расстояние со знаком до скруглённого прямоугольника (половина размера b, радиус r).
float rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 half_size = rect_size * 0.5;
	vec2 p = UV * rect_size - half_size;
	float radius = half_size.x;
	float d = rounded_box(p, half_size, radius);
	float aa = 1.0;
	float outer = 1.0 - smoothstep(-aa, 0.0, d);
	float inner_d = d + frame_px + rim_px;
	float window = 1.0 - smoothstep(-aa, 0.0, inner_d);
	float rim = 1.0 - smoothstep(-aa, 0.0, d + frame_px);

	// Высота внутри окна: 0 — низ, 1 — верх.
	float inset = frame_px + rim_px;
	float level = clamp((rect_size.y - inset - UV.y * rect_size.y) / max(rect_size.y - inset * 2.0, 1.0), 0.0, 1.0);

	vec4 col = frame_color;
	col = mix(col, rim_color, rim);
	vec4 inside = back_color;
	if (level <= value) {
		// Заливка с мягким бликом слева — объём «как в стекле».
		float shine = smoothstep(0.15, 0.0, abs(UV.x - 0.3)) * 0.25;
		inside = vec4(fill_color.rgb + vec3(shine), fill_color.a);
	}
	float in_zone = step(zone_from, level) * step(level, zone_to);
	float pulse = zone_pulse * (0.5 + 0.5 * sin(TIME * pulse_speed));
	float zone_alpha = 0.28 + 0.4 * pulse;
	inside.rgb = mix(inside.rgb, zone_color.rgb, in_zone * zone_alpha);
	// Обводка зоны: тонкие светлые линии на её границах.
	float px = 1.0 / max(rect_size.y - inset * 2.0, 1.0);
	float edge = max(1.0 - smoothstep(0.0, px * 1.5, abs(level - zone_from)),
			1.0 - smoothstep(0.0, px * 1.5, abs(level - zone_to)));
	inside.rgb = mix(inside.rgb, zone_color.rgb, edge * 0.9);
	// Риска на уровне заливки.
	float tick = (1.0 - smoothstep(0.0, px * tick_px, abs(level - value))) * step(0.001, value);
	inside.rgb = mix(inside.rgb, tick_color.rgb, tick);
	col = mix(col, inside, window);
	COLOR = vec4(col.rgb, col.a * outer) * COLOR;
}
