class_name CollectorCard
extends Control
## KOLEKSİYON KARTI (0.0.322, konsept D): görsel bütün kartı kaplar; çevresinde
## altın çerçeve, köşelerde kart türünün renginde taşlar, sağ üstte türün
## simge pulu, altta türün renginde kurdele üzerinde ad. Büyük boyda (ortaya
## gelen kart) kurdelenin altında etki metni de yazar. Eldeki kartlar ve tur
## başında açılan kart aynı bileşeni kullanır. Tamamen vektör + kart görseli.

const GOLD := Color("F2B632")
const GOLD_LIGHT := Color("FFE08A")
const GOLD_DARK := Color("B58312")
const GOLD_EDGE := Color("7A5608")

var card_type: String = ""
var description: String = ""

var _art_clip: Panel
var _art: TextureRect
var _shade: TextureRect
var _overlay: Control
var _title: Label
var _desc: Label

## size_px: kartın boyu; with_text: kurdelenin altına etki metni yazılır.
static func make(p_card_type: String, size_px: Vector2, with_text: bool = false) -> CollectorCard:
	var card := CollectorCard.new()
	card.card_type = p_card_type
	# Yalnız ilk paragraf (etki); "Seç, sonra ..." gibi kullanım satırları yazmaz.
	card.description = CardPresets.card_description(p_card_type).split(char(10))[0] if with_text else ""
	card.custom_minimum_size = size_px
	card.size = size_px
	return card

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	_art_clip = Panel.new()
	_art_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	add_child(_art_clip)
	_art = TextureRect.new()
	_art.texture = CardPresets.get_card_texture(card_type)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_clip.add_child(_art)
	# Alttan koyulaşan geçiş: kurdele ve metin görselin üstünde okunur.
	_shade = TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.08, 0.05, 0.02, 0.0))
	grad.set_color(1, Color(0.08, 0.05, 0.02, 0.9))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0.45)
	tex.fill_to = Vector2(0, 0.85)
	tex.width = 4
	tex.height = 64
	_shade.texture = tex
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_clip.add_child(_shade)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_title = Label.new()
	_title.text = CardPresets.card_short_title(card_type).replace("\n", " ")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.clip_text = true
	_title.add_theme_font_override("font", UiTheme.mono(true))
	_title.add_theme_color_override("font_color", Color.WHITE)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	_title.add_theme_constant_override("shadow_offset_y", 1)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_desc = Label.new()
	_desc.text = description
	_desc.visible = description != ""
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_color_override("font_color", Color("F3E6C8"))
	_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_desc)
	resized.connect(_layout)
	_layout()

func kind_color() -> Color:
	return CardFace.color_of(card_type)

## Çerçeve kalınlığı, kurdele yüksekliği vb. kart genişliğine orantılı.
func _frame() -> float:
	return maxf(4.0, size.x * 0.048)

func _ribbon_rect() -> Rect2:
	var h := maxf(16.0, size.x * 0.17)
	var bottom := size.y * (0.66 if description != "" else 0.9)
	return Rect2(-size.x * 0.04, bottom - h, size.x * 1.08, h)

func _layout() -> void:
	if _art_clip == null:
		return
	var f := _frame()
	_art_clip.position = Vector2(f, f)
	_art_clip.size = size - Vector2(f, f) * 2.0
	var clip_style := StyleBoxFlat.new()
	clip_style.bg_color = UiTheme.INK
	clip_style.set_corner_radius_all(int(size.x * 0.06))
	_art_clip.add_theme_stylebox_override("panel", clip_style)
	_art.position = Vector2.ZERO
	_art.size = _art_clip.size
	_shade.position = Vector2.ZERO
	_shade.size = _art_clip.size
	_overlay.position = Vector2.ZERO
	_overlay.size = size
	var ribbon := _ribbon_rect()
	_title.position = ribbon.position + Vector2(size.x * 0.1, 0)
	_title.size = Vector2(ribbon.size.x - size.x * 0.2, ribbon.size.y)
	_title.add_theme_font_size_override("font_size", _title_font_size(ribbon.size.x - size.x * 0.2, ribbon.size.y))
	_desc.position = Vector2(f + size.x * 0.05, ribbon.end.y + size.y * 0.025)
	_desc.size = Vector2(size.x - (f + size.x * 0.05) * 2.0, size.y - f - _desc.position.y)
	_desc.add_theme_font_size_override("font_size", maxi(9, int(size.x * 0.056)))
	queue_redraw()
	_overlay.queue_redraw()

## Ad kurdeleye tek satırda sığana kadar küçülür.
func _title_font_size(room: float, height: float) -> int:
	var font := UiTheme.mono(true)
	var fsize := int(height * 0.62)
	while fsize > 6 and font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > room:
		fsize -= 1
	return fsize

## Altın çerçeve: koyu alt kalınlık + altın gövde + üstte açık parlama.
func _draw() -> void:
	var r := int(size.x * 0.1)
	var lip := StyleBoxFlat.new()
	lip.bg_color = GOLD_EDGE
	lip.set_corner_radius_all(r)
	lip.shadow_color = Color(0, 0, 0, 0.35)
	lip.shadow_size = int(maxf(3.0, size.x * 0.05))
	lip.shadow_offset = Vector2(0, size.x * 0.04)
	draw_style_box(lip, Rect2(Vector2(0, size.x * 0.035), size))
	var body := StyleBoxFlat.new()
	body.bg_color = GOLD
	body.set_corner_radius_all(r)
	body.border_color = GOLD_LIGHT
	body.border_width_top = int(maxf(1.0, size.x * 0.018))
	body.border_width_left = body.border_width_top
	body.border_width_bottom = int(maxf(1.0, size.x * 0.012))
	body.border_width_right = body.border_width_bottom
	draw_style_box(body, Rect2(Vector2.ZERO, size))

## Görselin üstündekiler: köşe taşları, simge pulu, kurdele.
func _draw_overlay() -> void:
	var color := kind_color()
	var f := _frame()
	# Köşe taşları (çerçevenin köşelerinde, türün renginde baklava).
	var g := maxf(4.0, size.x * 0.06)
	for corner in [Vector2(f * 0.6, f * 0.6), Vector2(size.x - f * 0.6, f * 0.6), Vector2(f * 0.6, size.y - f * 0.6), Vector2(size.x - f * 0.6, size.y - f * 0.6)]:
		var gem := PackedVector2Array([corner + Vector2(0, -g), corner + Vector2(g, 0), corner + Vector2(0, g), corner + Vector2(-g, 0)])
		var outline := PackedVector2Array([corner + Vector2(0, -g - 1.5), corner + Vector2(g + 1.5, 0), corner + Vector2(0, g + 1.5), corner + Vector2(-g - 1.5, 0)])
		_overlay.draw_colored_polygon(outline, GOLD_EDGE)
		_overlay.draw_colored_polygon(gem, color)
		_overlay.draw_colored_polygon(PackedVector2Array([corner + Vector2(0, -g), corner + Vector2(g * 0.5, -g * 0.5), corner + Vector2(0, 0), corner + Vector2(-g * 0.5, -g * 0.5)]), color.lightened(0.45))
	# Simge pulu (sağ üst).
	var pr := size.x * 0.11
	var pc := Vector2(size.x - f - pr - size.x * 0.03, f + pr + size.x * 0.03)
	_overlay.draw_circle(pc + Vector2(0, pr * 0.12), pr + 2.0, Color(0, 0, 0, 0.35))
	_overlay.draw_circle(pc, pr + maxf(1.5, size.x * 0.014), GOLD_LIGHT)
	_overlay.draw_circle(pc, pr, color)
	CardFace.draw_emblem(_overlay, card_type, pc, pr * 0.55, Color.WHITE)
	# Kurdele: iki ucu çentikli, altında koyu kalınlık.
	var rr := _ribbon_rect()
	var notch := rr.size.y * 0.35
	var drop := maxf(2.0, rr.size.y * 0.14)
	var shape := func(o: Vector2) -> PackedVector2Array:
		return PackedVector2Array([rr.position + o, Vector2(rr.end.x, rr.position.y) + o, Vector2(rr.end.x - notch, rr.position.y + rr.size.y * 0.5) + o,
			rr.end + o, Vector2(rr.position.x, rr.end.y) + o, Vector2(rr.position.x + notch, rr.position.y + rr.size.y * 0.5) + o])
	_overlay.draw_colored_polygon(shape.call(Vector2(0, drop)), color.darkened(0.45))
	_overlay.draw_colored_polygon(shape.call(Vector2.ZERO), color)
	_overlay.draw_line(rr.position + Vector2(notch, 1), Vector2(rr.end.x - notch, rr.position.y + 1), Color(1, 1, 1, 0.3), maxf(1.0, drop * 0.5))
