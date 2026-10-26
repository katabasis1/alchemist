// powder.gdshader — горка порошка на дне чаши ступки (S2.3). Рисуется на ColorRect (узел Visual/Powder в mortar.tscn)
// под ингредиентами: овал «поверхности» порошка во весь прямоугольник, растёт с fill (0 — пусто, 1 — полная чаша).
// Цвет — смесь свойств в ступке; dust 0…1 — перетёр: порошок светлеет и сереет в пыль. Зерно — хэш-шум, без текстур.
// Значения задаёт MortarJuice (scenes/stations/mortar/mortar_juice.gd). Собственный код проекта, заимствований нет.
shader_type canvas_item;

uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform vec4 powder_color : source_color = vec4(0.82, 0.72, 0.52, 1.0);
uniform vec4 dust_color : source_color = vec4(0.86, 0.83, 0.78, 1.0);
uniform float dust : hint_range(0.0, 1.0) = 0.0;
// Размер овала при fill → 0 (доля полного) и мягкость края.
uniform float min_radius = 0.35;
uniform float edge_soft = 0.08;
// Зерно: частота и сила; светлая макушка и тёмный край горки.
uniform float grain_scale = 90.0;
uniform float grain_amount = 0.12;
uniform float highlight = 0.18;
uniform float rim_shade = 0.22;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	if (fill <= 0.0) {
		discard;
	}
	// Центр горки чуть ниже середины: поверхность видна под углом.
	vec2 p = (UV - vec2(0.5, 0.55)) / vec2(0.5, 0.45);
	float radius = mix(min_radius, 1.0, fill);
	float r = length(p) / radius;
	float inside = 1.0 - smoothstep(1.0 - edge_soft, 1.0, r);
	vec3 base = mix(powder_color.rgb, dust_color.rgb, dust);
	// Макушка светлее (верх-центр), к краю — тень, сверху — зерно.
	float top = clamp(1.0 - length(p / radius - vec2(0.0, -0.25)), 0.0, 1.0);
	vec3 col = base * (1.0 - rim_shade * smoothstep(0.55, 1.0, r)) + vec3(highlight) * top * top;
	float grain = hash(floor(UV * grain_scale)) - 0.5;
	col += grain * grain_amount;
	COLOR = vec4(col, inside * smoothstep(0.0, 0.08, fill));
}
