// band_gauge.gdshader — шкала среза колбы-отстойника (S4.2): рамка, тёмное окно, заливка сверху (слитая часть
// столба), зелёные полосы чистого среза с обводкой, светлые риски границ слоёв, яркий бегунок на уровне среза.
// Рисуется на ColorRect (components/band_gauge/band_gauge.tscn) целиком; значения задаёт BandGauge (band_gauge.gd).
// 0 — верх окна, 1 — низ. Скругления и толщины линий — в пикселях: rect_size скрипт обновляет при изменении размера.
// Собственный код проекта (лицензия проекта), заимствований нет; рамка — как у zone_gauge.gdshader.
shader_type canvas_item;

// Границ между шестью слоями — пять (BandGauge.MAX_BANDS).
const int MAX_BANDS = 5;

uniform vec2 rect_size = vec2(30.0, 260.0);
uniform float value : hint_range(0.0, 1.0) = 0.0;
uniform int band_count = 0;
// (от, до) — доли столба сверху; лишние ячейки — (-1, -1).
uniform vec2 bands[5];
uniform float marks[5];
uniform vec4 fill_color : source_color = vec4(0.94, 0.63, 0.05, 1.0);
uniform vec4 back_color : source_color = vec4(0.26, 0.13, 0.05, 0.85);
uniform vec4 frame_color : source_color = vec4(0.26, 0.11, 0.05, 1.0);
uniform vec4 rim_color : source_color = vec4(0.75, 0.63, 0.39, 1.0);
uniform vec4 band_color : source_color = vec4(0.49, 0.85, 0.34, 1.0);
uniform vec4 mark_color : source_color = vec4(0.99, 0.95, 0.77, 1.0);
uniform vec4 slider_color : source_color = vec4(1.0, 1.0, 0.94, 1.0);
// Толщины, пиксели.
uniform float frame_px = 3.0;
uniform float rim_px = 3.0;
uniform float mark_px = 2.0;
uniform float slider_px = 4.0;
// Риска короче ширины окна: засечки от краёв на эту долю, середина свободна — риска не путается с обводкой полосы.
uniform float mark_reach : hint_range(0.0, 0.5) = 0.32;
// Подсветка полос: 0 — спокойная, 1 — мигает (обучение).
uniform float band_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_speed = 6.0;

float rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// 1 на линии толщиной width_px вокруг at, мягкий край в пиксель; px — доля шкалы в одном пикселе.
float line(float depth, float at, float width_px, float px) {
	float half_width = width_px * 0.5 * px;
	return 1.0 - smoothstep(half_width, half_width + px, abs(depth - at));
}

void fragment() {
	vec2 half_size = rect_size * 0.5;
	vec2 p = UV * rect_size - half_size;
	float d = rounded_box(p, half_size, half_size.x);
	float outer = 1.0 - smoothstep(-1.0, 0.0, d);
	float window = 1.0 - smoothstep(-1.0, 0.0, d + frame_px + rim_px);
	float rim = 1.0 - smoothstep(-1.0, 0.0, d + frame_px);

	float inset = frame_px + rim_px;
	float inner_h = max(rect_size.y - inset * 2.0, 1.0);
	float depth = clamp((UV.y * rect_size.y - inset) / inner_h, 0.0, 1.0);
	float px = 1.0 / inner_h;

	vec4 col = mix(frame_color, rim_color, rim);
	vec4 inside = back_color;
	if (depth <= value) {
		float shine = smoothstep(0.15, 0.0, abs(UV.x - 0.3)) * 0.25;
		inside = vec4(fill_color.rgb + vec3(shine), fill_color.a);
	}
	float in_band = 0.0;
	float edge = 0.0;
	float mark = 0.0;
	float center = step(abs(UV.x - 0.5), 0.5 - mark_reach);
	for (int i = 0; i < MAX_BANDS; i++) {
		if (i >= band_count) {
			break;
		}
		vec2 b = bands[i];
		in_band = max(in_band, step(b.x, depth) * step(depth, b.y));
		edge = max(edge, max(line(depth, b.x, 1.0, px), line(depth, b.y, 1.0, px)));
		mark = max(mark, line(depth, marks[i], mark_px, px) * (1.0 - center));
	}
	float pulse = band_pulse * (0.5 + 0.5 * sin(TIME * pulse_speed));
	inside.rgb = mix(inside.rgb, band_color.rgb, in_band * (0.28 + 0.4 * pulse));
	inside.rgb = mix(inside.rgb, band_color.rgb, edge * 0.9);
	inside.rgb = mix(inside.rgb, mark_color.rgb, mark);
	inside.rgb = mix(inside.rgb, slider_color.rgb, line(depth, value, slider_px, px));
	col = mix(col, inside, window);
	COLOR = vec4(col.rgb, col.a * outer) * COLOR;
}
