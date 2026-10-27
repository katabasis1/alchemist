// fx_rays.gdshader — веер лучей света из чаши («идеально»). Рисуется на ColorRect над горлышком
// (scenes/fx/fx_rays.tscn): низ прямоугольника — поверхность порошка, лучи расходятся вверх веером из точки ниже
// прямоугольника, медленно колышутся (шум по углу) и гаснут к верху. progress 0…1 — общий с FxRing (fx_ring.gd):
// быстро разгораются и медленно гаснут. Смешивание — сложение.
// Приём «god rays» — идея с godotshaders.com (docs/THIRD_PARTY.md), код собственный.
shader_type canvas_item;
render_mode blend_add;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ring_color : source_color = vec4(1.0, 0.9, 0.55, 1.0);
uniform float ray_count = 9.0;
// Источник веера ниже прямоугольника (доля высоты) и ширина основания веера (доля ширины).
uniform float origin_below = 0.4;
uniform float base_width = 0.7;
uniform float intensity = 0.6;
uniform float speed = 0.6;
// Ширина затухания у боковых краёв прямоугольника (доля ширины).
uniform float side_fade = 0.18;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), f);
}

void fragment() {
	vec2 o = vec2(0.5, 1.0 + origin_below);
	vec2 d = UV - o;
	float ang = atan(d.x, -d.y);
	float h = 1.0 - UV.y;
	float a = ang * ray_count * 3.0;
	float rays = noise1(a + TIME * speed) * 0.6 + noise1(a * 2.3 - TIME * speed * 1.7) * 0.4;
	rays = smoothstep(0.35, 0.95, rays);
	float max_ang = atan(base_width * 0.5, origin_below);
	float fan = 1.0 - smoothstep(max_ang * 0.6, max_ang, abs(ang));
	float vfade = (1.0 - smoothstep(0.0, 1.0, h)) * smoothstep(0.0, 0.08, h);
	// Края прямоугольника гасятся, чтобы веер не обрезался по сторонам.
	float side = smoothstep(0.0, side_fade, UV.x) * smoothstep(0.0, side_fade, 1.0 - UV.x);
	float env = smoothstep(0.0, 0.12, progress) * (1.0 - smoothstep(0.3, 1.0, progress));
	float v = rays * fan * vfade * side * intensity * env;
	// У основания лучи белее: свет «из порошка».
	float hot = clamp(v * (1.0 - h) * 1.5, 0.0, 1.0);
	COLOR = vec4(mix(ring_color.rgb, vec3(1.0), hot), clamp(v, 0.0, 1.0) * ring_color.a);
}
