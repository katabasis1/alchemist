// ingredient.gdshader — материал ингредиента: вспышка (компонент Flash) + распад при помоле (S2.3).
// Вспышка: те же параметры, что у components/flash/flash.gdshader (flash_color, flash_amount), поэтому Flash работает
// с этим материалом без изменений. Распад: crumble 0…1 — силуэт крошится кусочками (клетки + мягкий шум), по краю
// разлома — каёмка цвета крошки, весь предмет понемногу «пылится» этим цветом. crumble = 1 — ничего не осталось.
// Значения задаёт IngredientItem.set_crumble() (scenes/ingredient/ingredient_item.gd), цвет — смесь в ступке.
// Шум считается в шейдере (хэш), без текстур. Собственный код проекта (лицензия проекта), заимствований нет.
shader_type canvas_item;

uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform float crumble : hint_range(0.0, 1.0) = 0.0;
uniform vec4 crumb_color : source_color = vec4(0.82, 0.72, 0.52, 1.0);
// Сколько «кусочков» по стороне картинки и насколько мелкий шум по краю разлома.
uniform float cells = 7.0;
uniform float noise_scale = 22.0;
// Ширина каёмки по краю разлома (в долях порога) и насколько предмет «пылится» к концу.
uniform float edge_width = 0.12;
uniform float dust_tint = 0.35;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	// COLOR здесь — уже текстура × modulate; альфу вспышка не трогает, чтобы вспыхивал только силуэт.
	COLOR.rgb = mix(COLOR.rgb, flash_color.rgb, flash_amount * flash_color.a);
	if (crumble > 0.0) {
		// Кусочки: у каждой клетки свой порог, мягкий шум ломает прямые края клеток.
		float piece = hash(floor(UV * cells));
		float n = mix(piece, value_noise(UV * noise_scale), 0.45);
		float t = crumble * (1.0 + edge_width);
		float cut = n - t + edge_width;
		float edge = 1.0 - smoothstep(0.0, edge_width, cut);
		COLOR.rgb = mix(COLOR.rgb, crumb_color.rgb, clamp(crumble * dust_tint + edge * 0.85, 0.0, 1.0));
		COLOR.a *= step(0.0, cut);
	}
}
