// flash.gdshader — подмешивает цвет к спрайту: вспышка попадания, «принято», «нельзя».
// Управляет компонент Flash (components/flash/flash.gd) через flash_amount.
// Собственный код проекта (лицензия проекта), заимствований нет.
shader_type canvas_item;

uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// COLOR здесь — уже текстура × modulate; альфу не трогаем, чтобы вспыхивал только силуэт.
	COLOR.rgb = mix(COLOR.rgb, flash_color.rgb, flash_amount * flash_color.a);
}
