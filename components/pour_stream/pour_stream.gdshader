// pour_stream.gdshader — струя из колбы в Приёмник (колба-отстойник S4.2). Рисуется на Line2D (PourStream,
// pour_stream.tscn) с texture_mode = Stretch: UV.x — вдоль струи (0 — носик колбы, 1 — поверхность в Приёмнике),
// UV.y — поперёк (0 и 1 — края). Ширину и сужение книзу задаёт сам Line2D (width, width_curve).
// По референсам docs/art/refs/ref_settler_pour.jpg и ref_settler_stream_closeup.jpg: цвет верхнего слоя, середина
// светлее и прозрачнее (струя — «трубка»), по стороне к свету — яркая белая полоса блика, по другой — тёмная кромка того
// же цвета (без коричневого контура), вдоль струи бегут светлые прожилки, внутри редкие искорки; концы мягко гаснут.
// head / reach — видимый отрезок: струя вырастает из носика (reach 0 → 1) и отрывается от него, когда слив кончился
// (head 0 → 1). Значения задаёт PourStream (pour_stream.gd). Собственный код проекта.
shader_type canvas_item;

uniform vec4 stream_color : source_color = vec4(0.98, 0.76, 0.2, 1.0);
// Видимый отрезок по длине: от head до reach (доли длины).
uniform float head : hint_range(0.0, 1.0) = 0.0;
uniform float reach : hint_range(0.0, 1.0) = 1.0;
// На какой доле длины концы гаснут.
uniform float end_soft = 0.04;
// Длина струи в пикселях (PourStream пересчитывает каждый кадр): прожилки и искры не растягиваются с длиной.
uniform float length_px = 300.0;
// Сторона блика: 0 — край UV.y = 0, 1 — край UV.y = 1 (PourStream выбирает сторону, обращённую к свету).
uniform float light_side : hint_range(0.0, 1.0) = 0.0;
// «Трубка»: кромка темнее и насыщеннее (как у стекла в liquid.gdshader), середина светлее.
uniform float edge_dark = 0.18;
uniform float edge_saturate = 1.0;
uniform float core_light = 0.3;
uniform float edge_alpha = 0.96;
uniform float core_alpha = 0.86;
// Полоса блика: где (0 — край, 1 — середина), ширина, сила.
uniform float highlight_at = 0.42;
uniform float highlight_width = 0.13;
uniform float highlight = 0.85;
// Прожилки: шаг в пикселях вдоль струи, скорость течения (пикселей в секунду), сила.
uniform float streak_px = 46.0;
uniform float flow_px = 420.0;
uniform float streak = 0.32;
// Искорки: размер ячейки в пикселях, доля занятых ячеек, сила.
uniform float sparkle_px = 18.0;
uniform float sparkle_density = 0.16;
uniform float sparkle = 0.9;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float u = UV.x;
	// Поперёк: −1 — сторона блика, +1 — тёмная сторона.
	float x = mix(UV.y, 1.0 - UV.y, light_side) * 2.0 - 1.0;
	float across = abs(x);
	float tube = sqrt(max(1.0 - across * across, 0.0));
	// Гладкий край без лесенки: ширина пикселя в долях поперечника.
	float aa = max(fwidth(UV.y) * 2.0, 1e-4);
	float edge = 1.0 - smoothstep(1.0 - aa * 2.0, 1.0, across);
	float shown = smoothstep(head, head + end_soft, u) * (1.0 - smoothstep(reach - end_soft, reach, u));

	vec3 base = stream_color.rgb;
	vec3 rim = base * mix(vec3(1.0), base, edge_saturate) * (1.0 - edge_dark);
	vec3 col = mix(rim, mix(base, vec3(1.0), core_light), pow(tube, 1.4));

	// Прожилки: три дорожки поперёк, каждая со своим шагом и фазой, бегут от носика вниз.
	float along = u * length_px - TIME * flow_px;
	float lane = floor((x * 0.5 + 0.5) * 3.0);
	float lane_x = fract((x * 0.5 + 0.5) * 3.0) * 2.0 - 1.0;
	float phase = hash12(vec2(lane, 7.0)) * 6.2832;
	float wave = 0.5 + 0.5 * sin(along / streak_px * 6.2832 * (0.8 + 0.4 * hash12(vec2(lane, 3.0))) + phase);
	float lines = pow(wave, 6.0) * (1.0 - smoothstep(0.2, 0.75, abs(lane_x))) * tube;
	col += vec3(streak * lines);

	// Блик: белая полоса у стороны к свету, слегка дрожит вдоль течения.
	float hx = -1.0 + highlight_at + 0.04 * sin(along / streak_px * 2.1);
	float shine = exp(-pow((x - hx) / highlight_width, 2.0));
	col = mix(col, vec3(1.0), clamp(shine * highlight, 0.0, 1.0));

	// Искорки: ячейки едут вместе с течением, в занятой — мерцающая точка-звёздочка.
	vec2 cell_p = vec2(along / sparkle_px, (x * 0.5 + 0.5) * 2.0);
	vec2 cell = floor(cell_p);
	float pick = hash12(cell + 11.0);
	vec2 local = fract(cell_p) - vec2(0.5);
	float star = max(1.0 - length(local) * 4.0, 0.0);
	star += max(1.0 - abs(local.x) * 14.0, 0.0) * max(1.0 - abs(local.y) * 3.0, 0.0) * 0.5;
	star += max(1.0 - abs(local.y) * 14.0, 0.0) * max(1.0 - abs(local.x) * 3.0, 0.0) * 0.5;
	float twinkle = 0.5 + 0.5 * sin(TIME * 9.0 + pick * 40.0);
	col += vec3(sparkle * step(1.0 - sparkle_density, pick) * star * twinkle * tube);

	float alpha = mix(edge_alpha, core_alpha, tube) + shine * highlight * 0.2;
	COLOR = vec4(clamp(col, 0.0, 1.0), clamp(alpha, 0.0, 1.0) * edge * shown * stream_color.a);
}
