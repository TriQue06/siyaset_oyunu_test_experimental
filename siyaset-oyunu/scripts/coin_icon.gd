class_name CoinIcon
extends Control
## PARA SİMGESİ: üstünde ₺ yazan yuvarlak sikke (vektörle çizilir, dosyaya
## bağlı değil). Parti kasası mavi (FundingSlider.PARTY_COLOR), devlet
## hazinesi altın (FundingSlider.STATE_COLOR) sikkeyle gösterilir.

var color: Color = UiTheme.BLUE

static func make(size_px: float, coin_color: Color = UiTheme.BLUE) -> CoinIcon:
	var icon := CoinIcon.new()
	icon.color = coin_color
	icon.custom_minimum_size = Vector2(size_px, size_px)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _draw() -> void:
	var side := minf(size.x, size.y)
	if side <= 0.0:
		return
	var c := size * 0.5
	var r := side * 0.5
	draw_circle(c, r, UiTheme.INK)
	draw_circle(c, r - maxf(1.0, r * 0.12), color.darkened(0.25))
	draw_circle(c, r - maxf(2.0, r * 0.24), color)
	draw_arc(c, r * 0.62, PI * 1.1, PI * 1.6, 12, Color(1, 1, 1, 0.35), maxf(1.0, r * 0.1), true)
	var font := UiTheme.mono(true)
	var font_size := int(roundf(side * 0.62))
	var glyph := "₺"
	var text_size := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := Vector2(c.x - text_size.x * 0.5, c.y + font.get_ascent(font_size) * 0.5 - font.get_descent(font_size) * 0.35)
	draw_string(font, pos, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiTheme.INK.lerp(color, 0.15))
