// drop_glow.gdshader — мягкое пульсирующее пятно света под целью переноса (подсветка DropTarget).
// Рисуется на ColorRect (components/drop_target/drop_glow.tscn): овал во весь прямоугольник, края растворяются.
// Яркость задаёт DropTarget через modulate (доступна / под пальцем), пульс идёт сам от TIME.
// Собственный код проекта (лицензия проекта), заимствований нет.
shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 0.85, 0.45, 0.9);
// Доля радиуса, на которой свет гаснет к краю (0 — резкий край, 1 — гаснет от самого центра).
uniform float softness : hint_range(0.01, 1.0) = 0.6;
// Пустая середина: 0 — сплошное пятно, ближе к 1 — кольцо.
uniform float hollow : hint_range(0.0, 0.95) = 0.0;
uniform float pulse_speed : hint_range(0.0, 20.0) = 4.0;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	float d = length(UV * 2.0 - vec2(1.0));
	float outer = 1.0 - smoothstep(1.0 - softness, 1.0, d);
	float inner = hollow > 0.0 ? smoothstep(hollow - softness * 0.5, hollow, d) : 1.0;
	float pulse = 1.0 - pulse_amount * (0.5 + 0.5 * sin(TIME * pulse_speed));
	// COLOR на входе — цвет ColorRect × modulate: так DropTarget управляет яркостью.
	COLOR = vec4(glow_color.rgb, glow_color.a * outer * inner * pulse) * COLOR;
}
