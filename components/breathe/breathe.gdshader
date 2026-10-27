// breathe.gdshader — тихое дыхание портрета (клиент ждёт у прилавка, сцена не замирает).
// На вдохе голова и плечи чуть поднимаются, грудь чуть шире; выдох длиннее вдоха, после него короткая пауза.
// Двигается выборка текстуры, а не узел: трансформ свободен для JuicePunch и твинов, модуляция работает как обычно.
// Всё выше линии плеч едет целиком — лицо не искажается. Низ портрета (его закрывает прилавок) стоит на месте,
// между ним и плечами торс плавно тянется. Подъём — в пикселях текстуры, расширение — в долях ширины.
// Сверху и по бокам портрету нужен прозрачный запас больше lift_px (cutout --pivot bottom --pad 8 его даёт).
// Собственный код проекта (лицензия проекта), заимствований нет.
shader_type canvas_item;

// Один вдох-выдох, секунды (спокойное дыхание — 4–5 с).
uniform float period_sec : hint_range(2.0, 8.0) = 4.6;
// Доля цикла на вдох.
uniform float inhale_part : hint_range(0.2, 0.6) = 0.38;
// Доля цикла на паузу после выдоха.
uniform float rest_part : hint_range(0.0, 0.4) = 0.14;
// Подъём головы и плеч на вдохе, px текстуры.
uniform float lift_px : hint_range(0.0, 16.0) = 4.0;
// Грудь шире на вдохе, доля ширины (0.01 — на 1 %).
uniform float widen : hint_range(0.0, 0.03) = 0.008;
// Линия плеч, доля высоты от верха: выше неё всё едет целиком.
uniform float shoulder_y : hint_range(0.0, 1.0) = 0.6;
// Нижняя линия, которая не двигается, доля высоты.
uniform float base_y : hint_range(0.0, 1.0) = 1.0;
// Середина фигуры по горизонтали, доля ширины.
uniform float center_x : hint_range(0.0, 1.0) = 0.5;
// Сдвиг фазы, доля цикла: соседние клиенты не дышат в такт.
uniform float phase : hint_range(0.0, 1.0) = 0.0;

varying vec4 tint;

void vertex() {
	// Цвет вершины — модуляция узла; во fragment COLOR уже умножен на текстуру по исходным UV.
	tint = COLOR;
}

// 0 — выдох, 1 — вдох; на стыках скорость нулевая, рывков нет.
float breath(float t) {
	float c = fract(t / period_sec + phase);
	if (c < inhale_part) {
		return smoothstep(0.0, inhale_part, c);
	}
	return 1.0 - smoothstep(inhale_part, 1.0 - rest_part, c);
}

void fragment() {
	float b = breath(TIME);
	// 1 — выше плеч (едет целиком), к низу плавно 0.
	float lift_w = 1.0 - smoothstep(shoulder_y, base_y, UV.y);
	// Расширение только на торсе: 0 на голове и у низа, максимум посередине между ними.
	float widen_w = 4.0 * lift_w * (1.0 - lift_w);
	vec2 uv = UV;
	uv.y += lift_px * TEXTURE_PIXEL_SIZE.y * b * lift_w;
	uv.x -= (UV.x - center_x) * widen * b * widen_w;
	COLOR = texture(TEXTURE, uv) * tint;
}
