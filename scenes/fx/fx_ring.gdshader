// fx_ring.gdshader — расходящееся кольцо света («идеально», позже — звёзды и открытия). Рисуется на ColorRect
// (scenes/fx/fx_ring.tscn): овал во весь прямоугольник, поэтому кольцо повторяет его пропорции (у ступки — край чаши).
// progress 0…1: кольцо растёт от start_radius до 1, тоньше и прозрачнее к концу. Значения задаёт FxRing (fx_ring.gd).
// Собственный код проекта (лицензия проекта), заимствований нет.
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ring_color : source_color = vec4(0.62, 1.0, 0.45, 1.0);
uniform float start_radius = 0.55;
uniform float width = 0.16;
uniform float glow = 0.5;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float radius = mix(start_radius, 0.92, progress);
	float w = width * (1.0 - 0.6 * progress);
	float band = 1.0 - smoothstep(0.0, w, abs(r - radius));
	float halo = (1.0 - smoothstep(0.0, w * 3.0, abs(r - radius))) * glow;
	float fade = 1.0 - progress * progress;
	COLOR = vec4(mix(ring_color.rgb, vec3(1.0), band * 0.5), clamp(band + halo, 0.0, 1.0) * fade * ring_color.a);
}
