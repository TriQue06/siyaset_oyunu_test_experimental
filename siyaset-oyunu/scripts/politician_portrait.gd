class_name PoliticianPortrait
extends Control
## SİYASETÇİ PORTRESİ: siyasetçinin "portrait" kimliği çözülürse (bkz.
## ContentPacks.portrait_texture) resmi kırparak doldurur; yoksa parti
## renginde zeminde baş harfler. Her yerde aynı bileşen kullanılır ki portre
## geldiğinde ekranlar değişmeden resmi göstersin.

var _data: Dictionary = {}
var _color: Color = UiTheme.PANEL_LIGHT
var _texture: Texture2D
var _appearance: Dictionary = {}

static func make(data: Dictionary, color: Color, side: float) -> PoliticianPortrait:
	var portrait := PoliticianPortrait.new()
	portrait.custom_minimum_size = Vector2(side, side)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Kapsayıcı (ör. satır yüksekliği) portreyi esnetmesin: her zaman kare.
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.set_politician(data, color)
	return portrait

func set_politician(data: Dictionary, color: Color) -> void:
	_data = data
	var selected: Variant = data.get("appearance")
	_appearance = AvatarCatalog.clean(selected, String(data.get("gender", "m"))) if selected is Dictionary and not selected.is_empty() else {}
	_color = color
	_texture = ContentPacks.portrait_texture(String(data.get("portrait", "")))
	queue_redraw()

func _draw() -> void:
	# Boyut ne olursa olsun KARE çizilir (ortalanmış).
	var side_len := minf(size.x, size.y)
	var rect := Rect2((size - Vector2(side_len, side_len)) * 0.5, Vector2(side_len, side_len))
	if not _appearance.is_empty():
		AvatarPortrait.draw_portrait(self, _appearance, rect)
		return
	if _texture != null:
		# Kare kırp (ortadan, üstten biraz yukarıda: yüz kadrajda kalsın).
		var tex_size := _texture.get_size()
		var side := minf(tex_size.x, tex_size.y)
		var src := Rect2((tex_size.x - side) * 0.5, (tex_size.y - side) * 0.25, side, side)
		draw_texture_rect_region(_texture, rect, src)
	else:
		# 0.0.269: parti logosu gibi gölgeli 3B pul (kare yok).
		var disc := rect.grow(-side_len * 0.06)
		draw_style_box(VoterGroupIcon.pawn_style(_color, disc.size.x), disc)
		var font := UiTheme.mono(true)
		var text := PoliticianPresets.initials(_data)
		var font_size := int(side_len * 0.42)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var pos := rect.position + Vector2((side_len - text_size.x) * 0.5, (side_len + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
		draw_string(font, pos + Vector2(2, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.35))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
		return
	draw_rect(rect, UiTheme.INK, false, 2.0)
