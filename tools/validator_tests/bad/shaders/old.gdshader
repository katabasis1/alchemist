shader_type canvas_item;
uniform vec4 c : hint_color;
void fragment() {
	COLOR = texture(SCREEN_TEXTURE, SCREEN_UV);
