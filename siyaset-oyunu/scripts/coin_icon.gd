class_name CoinIcon
extends Control
## PARA SİMGESİ (0.0.239): MoneyIcon'un "paid" simgesi, verilen renkte.
## Parti kasası mavi (FundingSlider.PARTY_COLOR), devlet hazinesi altın
## (FundingSlider.STATE_COLOR).

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
	var rect := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	draw_texture_rect(MoneyIcon.texture(), rect, false, color)
