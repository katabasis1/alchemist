// Своя реализация, лицензия проекта.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	COLOR = texture(TEXTURE, UV) * tint;
}
