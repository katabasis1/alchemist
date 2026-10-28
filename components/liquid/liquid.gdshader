// liquid.gdshader — жидкость в круглой колбе (S4.1): слои по плотности, узоры свойств, поверхность со светлой
// кромкой, светящиеся швы, муть отстаивания, наклон и раскачка. Стиль — docs/art/refs/ref_liquid_*.jpg.
// Рисуется на Sprite2D с текстурой колбы: TEXTURE — стекло, оно ложится поверх жидкости (одна отрисовка, одна
// картинка). Полость — круг (шар) + полоса (горло) в пикселях текстуры; финальная колба того же холста и формы
// встаёт без правок, иначе подстроить группу shape.
// Высота h — вдоль «вверх» от нижней точки шара: шар круглый, поэтому при наклоне слои стоят на тех же h.
// Данные слоёв — LiquidLayers.view через Liquid (liquid.gd), руками их не задают.
// Макет без Godot: tools/art/liquid_preview.py — копия строка в строку; правишь здесь — правь и там.
shader_type canvas_item;

const int MAX_LAYERS = 6;

group_uniforms shape;
uniform vec2 bulb_center = vec2(189.0, 355.0);
uniform float bulb_radius = 124.0;
uniform float neck_half_width = 40.0;
uniform float neck_top = 60.0;
// Высота столба полной колбы (уровень 1), пиксели от дна шара.
uniform float column_height = 212.0;

group_uniforms layers;
uniform int layer_count = 0;
// Без source_color: на массивах он переводит цвета неверно (godot#76135), а Compatibility он не нужен.
uniform vec4 layer_colors[6];
uniform int layer_patterns[6];
// Верх слоя в долях полной колбы, снизу вверх; последний — поверхность.
uniform float layer_tops[6];
uniform vec4 mixed_color = vec4(0.0);
// 1 — смесь взболтана (одна мутная заливка), 0 — отстоялась.
uniform float turbidity : hint_range(0.0, 1.0) = 0.0;

group_uniforms motion;
// Угол поверхности относительно колбы, радианы: −rotation колбы + запаздывание жидкости (Liquid).
uniform float surface_angle = 0.0;
// Волна от толчка: размах в пикселях и фаза.
uniform float slosh_px = 0.0;
uniform float slosh_phase = 0.0;

group_uniforms look;
// Сплющенность эллипса поверхности: насколько видно зеркало сверху.
uniform float surface_squash : hint_range(0.0, 0.5) = 0.2;
uniform float idle_wave_px = 1.6;
uniform float idle_wave_speed = 1.4;
uniform float seam_px = 3.5;
uniform float seam_glow : hint_range(0.0, 1.0) = 0.55;
uniform float edge_shade : hint_range(0.0, 1.0) = 0.85;
uniform float center_glow : hint_range(0.0, 1.0) = 0.22;
uniform float top_light : hint_range(0.0, 1.0) = 0.45;
uniform float rim_light : hint_range(0.0, 1.0) = 0.9;
uniform float meniscus_light : hint_range(0.0, 1.0) = 0.5;
uniform float caustic_light : hint_range(0.0, 1.0) = 0.4;
uniform float pattern_px = 46.0;
uniform float pattern_alpha : hint_range(0.0, 1.0) = 0.8;
uniform float pattern_speed = 0.1;
uniform float pattern_skip : hint_range(0.0, 1.0) = 0.15;
uniform float murk_swirl_px = 48.0;
// Насколько муть сводит цвета слоёв к общему: 1 — одна заливка, меньше — видны разводы цветов.
uniform float murk_blend : hint_range(0.0, 1.0) = 0.6;

varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

// hash12 — «Hash without Sine», Dave Hoskins, MIT: https://www.shadertoy.com/view/4djSRW (docs/THIRD_PARTY.md).
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x);
	float b = mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x);
	return mix(a, b, u.y);
}

mat2 rotation(float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return mat2(vec2(c, s), vec2(-s, c));
}

// Полуширина сечения полости на высоте h: шар, выше середины — не уже горла.
float chord(float h) {
	float dy = h - bulb_radius;
	float ball = sqrt(max(bulb_radius * bulb_radius - dy * dy, 0.0));
	return max(ball, neck_half_width * step(bulb_radius, h));
}

// Насколько ближний край сечения на высоте h опущен в точке s (сечение видно чуть сверху — эллипс).
float front_arc(float s, float h) {
	float w = max(chord(h), 1.0);
	float k = clamp(s / w, -1.0, 1.0);
	return surface_squash * w * sqrt(1.0 - k * k);
}

float boundary_wave(float s, float index, float t) {
	return idle_wave_px * sin(s * 0.045 + t * idle_wave_speed + index * 1.7);
}

float surface_wave(float s, float w, float t) {
	float k = clamp(s / max(w, 1.0), -1.0, 1.0);
	float idle = idle_wave_px * sin(s * 0.05 - t * idle_wave_speed * 1.3);
	float slosh = slosh_px * (k * cos(slosh_phase) + 0.35 * sin(k * 6.2832 - slosh_phase * 1.3));
	return idle + slosh;
}

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Узор свойства (PropertyData.Pattern): 0 пузыри, 1 волны, 2 листья, 3 снежинки, 4 луны, 5 искры. 0…1 — покрытие.
float pattern_mask(int pattern, vec2 d, float t) {
	vec2 q = d / pattern_px;
	float aa = 1.2 / pattern_px;
	if (pattern == 1) {
		q.x -= t * pattern_speed * 2.0;
		float line = abs(fract(q.y * 1.4 + 0.12 * sin(q.x * 6.2832)) - 0.5) / 1.4 - 0.035;
		return 1.0 - smoothstep(-aa, aa, line);
	}
	if (pattern == 0) {
		q.y += t * pattern_speed * 2.5;
	} else if (pattern == 2) {
		q += vec2(-0.4, -1.0) * t * pattern_speed;
	} else if (pattern == 3) {
		q.y -= t * pattern_speed;
	} else if (pattern == 4) {
		q.x += t * pattern_speed * 0.6;
	} else {
		q.y += t * pattern_speed * 0.6;
	}
	q.x += 0.5 * mod(floor(q.y), 2.0);
	vec2 cell = floor(q);
	float rnd = hash12(cell);
	float rnd2 = hash12(cell + vec2(17.3, 5.1));
	if (hash12(cell + vec2(3.7, 11.9)) < pattern_skip) {
		return 0.0;
	}
	vec2 f = fract(q) - 0.5 - (vec2(rnd, rnd2) - 0.5) * 0.3;
	float size = mix(0.75, 1.15, rnd2);
	float dist = 1.0;
	if (pattern == 0) {
		float ring = abs(length(f) - 0.17 * size) - 0.03;
		float glint = length(f - vec2(-0.07, -0.07) * size) - 0.035 * size;
		float small = abs(length(f - vec2(0.2, 0.17)) - 0.06 * size) - 0.022;
		dist = min(min(ring, glint), small);
	} else if (pattern == 2) {
		vec2 g = rotation(rnd * 6.2832 + sin(t * 0.8 + rnd * 6.0) * 0.35) * f;
		float lens = max(length(g - vec2(0.15, 0.0) * size), length(g + vec2(0.15, 0.0) * size)) - 0.27 * size;
		float vein = abs(g.x) - 0.012;
		dist = max(lens, -vein);
		dist = min(dist, segment(g, vec2(0.0, 0.18 * size), vec2(0.0, 0.27 * size)) - 0.016);
	} else if (pattern == 3) {
		vec2 g = rotation(rnd + t * 0.25) * f;
		float angle = mod(atan(g.y, g.x) + PI / 6.0, PI / 3.0) - PI / 6.0;
		vec2 k = length(g) * vec2(cos(angle), abs(sin(angle)));
		float r = 0.21 * size;
		float arm = segment(k, vec2(0.0), vec2(r, 0.0)) - 0.022;
		float branch = segment(k, vec2(0.5 * r, 0.0), vec2(0.78 * r, 0.17 * r)) - 0.018;
		dist = min(arm, branch);
	} else if (pattern == 4) {
		vec2 g = rotation(rnd * 0.8 - 0.4) * f;
		dist = max(length(g) - 0.17 * size, -(length(g - vec2(0.085, -0.055) * size) - 0.145 * size));
	} else {
		float twinkle = 0.7 + 0.3 * sin(t * 3.0 + rnd * 6.2832);
		float r = 0.27 * size * twinkle;
		vec2 g = abs(f) / r;
		dist = (sqrt(g.x) + sqrt(g.y) - 1.0) * r * 0.5;
		dist = min(dist, length(f - vec2(0.22, -0.18)) - 0.025 * twinkle);
	}
	return 1.0 - smoothstep(-aa, aa, dist);
}

// Цвет жидкости в точке: d — от центра шара, h — высота над дном шара вдоль «вверх», s — вдоль поверхности.
vec4 shade_liquid(vec2 d, float h, float s, float t) {
	int n = min(layer_count, MAX_LAYERS);
	float surface0 = layer_tops[n - 1] * column_height;
	float w = chord(surface0);
	float surface = surface0 + surface_wave(s, w, t);
	float arc = front_arc(s, surface);
	float alpha = 1.0 - smoothstep(-0.8, 0.8, h - (surface + arc));
	if (alpha <= 0.0) {
		return vec4(0.0);
	}
	float murk = turbidity;
	vec2 sq = vec2(s * 0.45 + sin(h * 0.04 + t * 1.1) * 26.0, h) / murk_swirl_px;
	float swirl = value_noise(sq + vec2(t * 0.15, -t * 0.5)) - 0.5;
	swirl += 0.5 * (value_noise(sq * 2.3 + vec2(-t * 0.3, t * 0.2)) - 0.5);
	float hm = h + swirl * murk * column_height * 0.55;
	int index = 0;
	float seam = 100000.0;
	for (int i = 0; i < MAX_LAYERS - 1; i++) {
		if (i < n - 1) {
			float hb = layer_tops[i] * column_height;
			float edge = hb - front_arc(s, hb) + boundary_wave(s, float(i), t);
			seam = min(seam, abs(hm - edge));
			index += int(hm >= edge);
		}
	}
	vec3 base = mix(layer_colors[index].rgb, mixed_color.rgb, smoothstep(0.0, 1.0, murk) * murk_blend);
	vec3 light = mix(base, vec3(1.0), center_glow);
	vec3 deep = base * base;
	float r = length(d) / bulb_radius;
	vec3 col = mix(light, deep, smoothstep(0.3, 1.05, r) * edge_shade);
	float clear = 1.0 - murk;
	float pattern = pattern_mask(layer_patterns[index], d, t) * pattern_alpha * clear;
	pattern *= smoothstep(seam_px, seam_px * 2.5, seam);
	col = mix(col, mix(base, vec3(1.0), 0.6), pattern);
	float glow = (1.0 - smoothstep(0.0, seam_px, seam)) * seam_glow * clear;
	col = mix(col, mix(base, vec3(1.0), 0.75), glow);
	float caustic = exp(-pow(d.x / (0.42 * bulb_radius), 2.0) - pow((d.y - 0.8 * bulb_radius) / (0.09 * bulb_radius), 2.0));
	col = mix(col, light, caustic * caustic_light);
	float front = surface - arc;
	if (h > front) {
		float across = clamp((h - front) / max(2.0 * arc, 1.0), 0.0, 1.0);
		col = mix(mix(base, vec3(1.0), top_light), mix(base, vec3(1.0), top_light * 0.6), across);
	}
	float rim = 1.0 - smoothstep(0.6, 2.4, abs(h - front));
	col = mix(col, vec3(1.0), rim * rim_light);
	float side = smoothstep(0.8, 1.0, abs(s) / max(w, 1.0)) * (1.0 - smoothstep(0.0, 9.0, abs(h - surface)));
	col = mix(col, vec3(1.0), side * meniscus_light);
	return vec4(col, alpha);
}

void fragment() {
	vec4 glass = texture(TEXTURE, UV);
	vec2 p = UV / TEXTURE_PIXEL_SIZE;
	vec2 up = vec2(sin(surface_angle), -cos(surface_angle));
	vec2 along = vec2(-up.y, up.x);
	vec2 d = p - bulb_center;
	float h = dot(d, up) + bulb_radius;
	float s = dot(d, along);
	float in_bulb = 1.0 - smoothstep(bulb_radius - 1.0, bulb_radius + 1.0, length(d));
	float in_neck = (1.0 - smoothstep(neck_half_width - 1.0, neck_half_width + 1.0, abs(d.x)))
			* step(neck_top, p.y) * step(p.y, bulb_center.y);
	float cavity = max(in_bulb, in_neck);
	vec4 liquid = vec4(0.0);
	if (layer_count > 0 && cavity > 0.0) {
		liquid = shade_liquid(d, h, s, TIME);
		liquid.a *= cavity;
	}
	float a = glass.a + liquid.a * (1.0 - glass.a);
	vec3 rgb = (glass.rgb * glass.a + liquid.rgb * liquid.a * (1.0 - glass.a)) / max(a, 0.0001);
	COLOR = vec4(rgb, a) * modulate;
}
