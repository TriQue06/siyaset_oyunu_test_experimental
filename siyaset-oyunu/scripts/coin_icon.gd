class_name CoinIcon
extends Control
## PARA SİMGESİ (0.0.239): MoneyIcon'un "paid" simgesi, verilen renkte.
## Parti kasası mavi (FundingSlider.PARTY_COLOR), devlet hazinesi altın
## (FundingSlider.STATE_COLOR).

var color: Color = UiTheme.BLUE

static func make(size_px: float, coin_color: Color = UiTheme.BLUE) -> CoinIcon:
	var icon := CoinIcon.new()
	icon.color = coin_color
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.custom_minimum_size = Vector2(size_px, size_px)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _draw() -> void:
	var side := minf(size.x, size.y)
	if side <= 0.0:
		return
	# 0.0.260: simge yerine düz "$" karakteri, aynı yerde ve renkte.
	var font := UiTheme.mono(true)
	var font_size := int(side * 0.95)
	var text_size := font.get_string_size(MoneyIcon.GLYPH, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := (size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	draw_string(font, Vector2((size.x - text_size.x) * 0.5, baseline), MoneyIcon.GLYPH, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
