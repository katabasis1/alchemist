// powder.gdshader — порошок в полости ступки (S2.3a). Назначение: горка истолчённой смеси, которая лежит
// В чаше: поверхность находится лучом по полости, а не рисуется овалом поверх неё.
// Узел: ColorRect ровно по габариту горлышка (эллипс полуосей a×b); передний край прячет BowlFront.
// Геометрия: горлышко — окружность радиуса 1 на высоте y = 0, полость — полуэллипсоид глубины depth,
// камера смотрит сверху под углом θ, sin θ = b / a (sin_tilt). Порошок — поле высот: уровень + горка + бугры.
// Стиль — по docs/art/refs/ref_mortar_powder_heap.jpg: тёплый свет слева сверху, холодная тень, тёмный контур,
// зерно, кусочки трав, на стенках налёт, в порошке мерцают искры; при glow — внутренний свет («идеально»).
// Приёмы: glitter (мерцание по ячейкам), sun pulse glow — godotshaders.com (идеи, код свой; docs/THIRD_PARTY.md).
// Хэш без синуса — Dave Hoskins (MIT). Копия для макета: tools/art/mortar_preview.py (shade_powder).
// Параметры задаёт MortarJuice через set_shader_parameter.
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 powder_color : source_color = vec4(0.62, 0.74, 0.42, 1.0);
uniform vec4 fleck_color : source_color = vec4(0.27, 0.46, 0.2, 1.0);
uniform float flecks : hint_range(0.0, 1.0) = 0.0;
uniform float coat : hint_range(0.0, 1.0) = 0.0;
uniform float glow : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.86, 0.45, 1.0);
uniform float sparkle : hint_range(0.0, 1.0) = 0.6;
uniform float spin = 0.0;
uniform float sin_tilt = 0.461;
uniform float depth = 0.8;
uniform float level_low = -0.68;
uniform float level_high = -0.46;
uniform float heap_low = 0.06;
uniform float heap_high = 0.4;
uniform float heap_width = 0.52;
uniform vec2 heap_center = vec2(0.0, 0.08);
uniform vec4 outline_color : source_color = vec4(0.24, 0.13, 0.07, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.62, 0.6, 0.76, 1.0);
uniform vec4 light_tint : source_color = vec4(1.0, 0.95, 0.82, 1.0);
uniform vec3 light_dir = vec3(-0.5, 0.8, -0.35);
uniform float outline_width = 0.022;

const int STEPS = 40;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 w = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

// Закрутка: зерно и бугры поворачиваются вслед за пестиком (жёстко, без растяжения) + постоянная спираль.
vec2 swirl(vec2 xz) {
	float ang = spin * 0.5 + 0.6 * length(xz);
	float c = cos(ang);
	float s = sin(ang);
	return vec2(c * xz.x - s * xz.y, s * xz.x + c * xz.y);
}

float level_now() {
	return mix(level_low, level_high, amount);
}

float heap_now() {
	return mix(heap_low, heap_high, amount) * smoothstep(0.0, 0.3, amount);
}

float bump(vec2 xz) {
	vec2 d = (xz - heap_center) / heap_width;
	return exp(-dot(d, d) * 1.6);
}

float height(vec2 xz) {
	vec2 sw = swirl(xz);
	float lumps = (vnoise(sw * 5.0) - 0.5) * 0.05 + (vnoise(sw * 11.0) - 0.5) * 0.018;
	return level_now() + heap_now() * bump(xz) + lumps * smoothstep(0.0, 0.15, amount);
}

float wall_radius(float y) {
	float k = y / depth;
	return sqrt(max(0.0, 1.0 - k * k));
}

void fragment() {
	vec2 q = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	vec4 outc = vec4(0.0);
	if (dot(q, q) < 1.0 && amount > 0.001) {
		float st = sin_tilt;
		float ct = sqrt(1.0 - st * st);
		// Луч: p(s) = (q.x, -s·st, q.y + s·ct); выход из полуэллипсоида — корень квадратного уравнения.
		float qa = ct * ct + (st * st) / (depth * depth);
		float qb = 2.0 * q.y * ct;
		float qc = dot(q, q) - 1.0;
		float s_exit = (-qb + sqrt(max(qb * qb - 4.0 * qa * qc, 0.0))) / (2.0 * qa);
		float ds = s_exit / float(STEPS);
		float prev_gap = 1.0;
		float s_hit = -1.0;
		float min_clear = 10.0;
		for (int i = 1; i <= STEPS; i++) {
			float s = ds * float(i);
			vec3 p = vec3(q.x, -s * st, q.y + s * ct);
			float gap = p.y - height(p.xz);
			if (gap < 0.0) {
				s_hit = s - ds * gap / (gap - prev_gap);
				break;
			}
			min_clear = min(min_clear, gap);
			prev_gap = gap;
		}
		vec3 L = normalize(light_dir);
		float pulse = 0.6 + 0.4 * sin(TIME * 3.2);
		float lev = level_now();
		if (s_hit > 0.0) {
			vec3 p = vec3(q.x, -s_hit * st, q.y + s_hit * ct);
			float e = 0.02;
			float hx = height(p.xz + vec2(e, 0.0)) - height(p.xz - vec2(e, 0.0));
			float hz = height(p.xz + vec2(0.0, e)) - height(p.xz - vec2(0.0, e));
			vec3 n = normalize(vec3(-hx, 2.0 * e, -hz));
			float ndl = dot(n, L);
			// Три тона, как в рисованной графике: тень, основной, свет.
			float band = 0.5 * smoothstep(0.6, 0.67, ndl) + 0.5 * smoothstep(0.87, 0.93, ndl);
			vec3 base = powder_color.rgb;
			vec3 shade = base * shadow_tint.rgb;
			vec3 lit = mix(base * 1.12, light_tint.rgb, 0.3);
			vec3 col = band < 0.5 ? mix(shade, base, band * 2.0) : mix(base, lit, band * 2.0 - 1.0);
			vec2 sw = swirl(p.xz);
			// Зерно и тёмные крупинки.
			float grain = vnoise(sw * vec2(26.0, 26.0));
			col *= 0.9 + 0.2 * grain;
			col = mix(col, shade * 0.8, step(0.9, vnoise(sw * 30.0 + 3.1)) * 0.5);
			// Кусочки трав, пока помол не закончен.
			float fl = vnoise(sw * vec2(17.0, 17.0) + 7.3);
			float fmask = smoothstep(1.0 - flecks * 0.3, 1.03 - flecks * 0.3, fl);
			col = mix(col, fleck_color.rgb * (0.75 + 0.35 * band), fmask);
			// Тень у стенок и контур стыка порошка со стенкой.
			float gap_w = wall_radius(p.y) - length(p.xz);
			col *= mix(0.55, 1.0, smoothstep(0.0, 0.2, gap_w));
			float line = 1.0 - smoothstep(outline_width * 0.4, outline_width, gap_w);
			// Внутренний свет «идеально»: верх горки светится и дышит.
			float top = smoothstep(lev, lev + heap_now() + 0.02, p.y);
			col = mix(col, col * 1.25 + glow_color.rgb * 0.35, glow * pulse * (0.35 + 0.65 * top));
			col = mix(col, outline_color.rgb, line);
			outc = vec4(col, 1.0);
			// Искры: звёздочки в ячейках поверхности, мерцают каждая в свой такт.
			float spark = 0.0;
			vec2 cell_uv = sw * 7.0;
			vec2 cid = floor(cell_uv);
			for (int j = -1; j <= 1; j++) {
				for (int k = -1; k <= 1; k++) {
					vec2 c = cid + vec2(float(j), float(k));
					float rnd = hash12(c * 1.37 + 11.0);
					if (rnd < 0.55) {
						vec2 jit = vec2(hash12(c + 3.7), hash12(c + 9.1));
						vec2 cw = (c + jit) / 7.0;
						// центр звезды обратно из закрученных координат
						float ang = -(spin * 0.5 + 0.6 * length(cw));
						vec2 cxz = vec2(cos(ang) * cw.x - sin(ang) * cw.y, sin(ang) * cw.x + cos(ang) * cw.y);
						float cy = height(cxz);
						vec2 cs = vec2(cxz.x, cy * ct + cxz.y * st);
						vec2 d = (vec2(q.x, q.y * st) - cs) * 24.0;
						float tw = pow(max(0.0, sin(TIME * (1.5 + 2.5 * rnd) + rnd * 40.0)), 10.0);
						float star = exp(-dot(d, d) * 1.4) + 0.7 * exp(-abs(d.x) * 1.1 - d.y * d.y * 9.0) + 0.7 * exp(-abs(d.y) * 1.1 - d.x * d.x * 9.0);
						spark += star * tw;
					}
				}
			}
			spark *= sparkle * (1.0 - line) * (0.6 + 0.4 * band + glow);
			outc.rgb += mix(light_tint.rgb, glow_color.rgb, 0.5 + 0.5 * glow) * spark;
		} else {
			// Луч ушёл в стенку: налёт пыли на стенках + свет от светящейся горки.
			vec3 p = vec3(q.x, -s_exit * st, q.y + s_exit * ct);
			float above = max(p.y - lev, 0.0);
			float ang = atan(p.z, p.x);
			float speck = vnoise(vec2(ang * 70.0, p.y * 110.0) + 5.0);
			float film = coat * 0.35 * exp(-above * 9.0);
			float dots = coat * smoothstep(0.95 - 0.22 * coat * exp(-above * 4.5), 0.99 - 0.22 * coat * exp(-above * 4.5), speck) * 0.8;
			float a = clamp(film + dots, 0.0, 0.95);
			vec3 col = mix(powder_color.rgb, light_tint.rgb, 0.25) * (0.85 + 0.2 * speck);
			outc = vec4(col * a, a);
			// Контур силуэта горки: луч прошёл впритирку к порошку.
			float line = 1.0 - smoothstep(outline_width * 0.45, outline_width, min_clear);
			outc = mix(outc, vec4(outline_color.rgb, 1.0), line);
			// Отсвет на стенках.
			outc.rgb += glow_color.rgb * glow * pulse * 0.35 * exp(-above * 3.5);
		}
	}
	COLOR = outc;
}
