class_name PoliticianPortrait
extends Control
## SİYASETÇİ PORTRESİ: siyasetçinin "portrait" kimliği çözülürse (bkz.
## ContentPacks.portrait_texture) resmi kırparak doldurur; yoksa parti
## renginde zeminde baş harfler. Her yerde aynı bileşen kullanılır ki portre
## geldiğinde ekranlar değişmeden resmi göstersin.

var _data: Dictionary = {}
var _color: Color = UiTheme.PANEL_LIGHT
var _texture: Texture2D

static func make(data: Dictionary, color: Color, side: float) -> PoliticianPortrait:
	var portrait := PoliticianPortrait.new()
	portrait.custom_minimum_size = Vector2(side, side)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.set_politician(data, color)
	return portrait

func set_politician(data: Dictionary, color: Color) -> void:
	_data = data
	_color = color
	_texture = ContentPacks.portrait_texture(String(data.get("portrait", "")))
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if _texture != null:
		# Kare kırp (ortadan, üstten biraz yukarıda: yüz kadrajda kalsın).
		var tex_size := _texture.get_size()
		var side := minf(tex_size.x, tex_size.y)
		var src := Rect2((tex_size.x - side) * 0.5, (tex_size.y - side) * 0.25, side, side)
		draw_texture_rect_region(_texture, rect, src)
	else:
		draw_rect(rect, _color.darkened(0.25))
		draw_rect(rect.grow(-size.x * 0.06), _color)
		var font := UiTheme.mono(true)
		var text := PoliticianPresets.initials(_data)
		var font_size := int(size.y * 0.42)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var pos := Vector2((size.x - text_size.x) * 0.5, (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
		draw_string(font, pos + Vector2(2, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.35))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
	draw_rect(rect, UiTheme.INK, false, 2.0)
