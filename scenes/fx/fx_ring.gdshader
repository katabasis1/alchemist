// fx_ring.gdshader — волна света по краю чаши («идеально», позже — звёзды и открытия). Рисуется на ColorRect
// (scenes/fx/fx_ring.tscn): эллипс во весь прямоугольник, поэтому волна повторяет его пропорции (у ступки — горлышко).
// progress 0…1: фронт бежит от start_radius к end_radius с замедлением; белое ядро, цветной ореол, светлый след
// внутрь, рябь по радиусу, мерцающие искры на фронте и вспышка внутри в первые доли секунды. Смешивание — сложение.
// Значения задаёт FxRing (fx_ring.gd). Приёмы «shockwave ring» и «glitter» — идеи с godotshaders.com
// (docs/THIRD_PARTY.md), код собственный.
shader_type canvas_item;
render_mode blend_add;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ring_color : source_color = vec4(0.62, 1.0, 0.45, 1.0);
// Радиусы — доля полуосей прямоугольника: старт на внутреннем крае горлышка.
uniform float start_radius = 0.62;
uniform float end_radius = 0.9;
uniform float width = 0.08;
uniform float glow = 0.6;
// Рябь радиуса фронта (доля полуоси).
uniform float wobble = 0.02;
uniform float glitter = 1.0;
uniform float glitter_count = 30.0;
uniform float fill_flash = 0.45;
// С какого радиуса (доля полуоси) волна гаснет к краю прямоугольника — ореол не обрезается по его сторонам.
uniform float edge_fade = 0.84;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float e = 1.0 - pow(1.0 - progress, 3.0);
	float radius = mix(start_radius, end_radius, e);
	radius += wobble * (sin(ang * 5.0 + TIME * 6.0) * 0.6 + sin(ang * 9.0 - TIME * 9.0) * 0.4);
	float w = width * (1.0 - 0.5 * progress);
	float d = abs(r - radius);
	float core = exp(-pow(d / (w * 0.35), 2.0));
	float halo = exp(-pow(d / (w * 1.8), 2.0)) * glow;
	float trail = smoothstep(radius - 0.22, radius, r) * step(r, radius) * 0.35 * (1.0 - progress);
	float turns = (ang / 6.2831853 + 0.5) * glitter_count;
	float cell = floor(turns);
	float local = fract(turns) - 0.5;
	float h = hash11(cell + 7.0);
	float twinkle = 0.5 + 0.5 * sin(TIME * (8.0 + h * 10.0) + h * 6.2831853);
	float spark = exp(-pow(local / 0.12, 2.0)) * exp(-pow(d / (w * 0.7), 2.0)) * step(0.45, h) * twinkle * glitter;
	float flash = exp(-pow(r / 0.85, 2.0)) * fill_flash * (1.0 - smoothstep(0.0, 0.35, progress));
	float fade = (1.0 - smoothstep(0.55, 1.0, progress)) * (1.0 - smoothstep(edge_fade, 1.0, r));
	float hot = clamp(core * 0.8 + spark, 0.0, 1.0);
	COLOR = vec4(mix(ring_color.rgb, vec3(1.0), hot), clamp(core + halo + trail + flash + spark, 0.0, 1.0) * fade * ring_color.a);
}
