shader_type canvas_item;

void fragment() {
    // 取得當前像素顏色
    vec4 color = texture(TEXTURE, UV);

    if (color.r < 0.01 && color.g < 0.01 && color.b < 0.01) {
        color.a = 0.0;
    }
    COLOR = color;
}