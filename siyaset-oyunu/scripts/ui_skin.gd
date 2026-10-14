class_name UiSkin
extends RefCounted
## Arayüzün GÖRÜNEN her parçasını PNG'den besleyen yardımcı.
##
## KURAL: Prosedürel çizim (StyleBoxFlat, ColorRect, draw_rect ile panel/buton
## vb.) KULLANILMAZ. Her görsel öge assets/ui/ altındaki bir PNG'dir; böylece
## sanat yönü tamamen dosyaları düzenleyerek değiştirilebilir, koda dokunmadan.
## Placeholder'lar tools/make_placeholder_art.js ile üretilir.

const PANEL := "res://assets/ui/ui_panel.png"
const PANEL_DARK := "res://assets/ui/ui_panel_dark.png"
const SLOT := "res://assets/ui/ui_slot.png"
const BUTTON_NORMAL := "res://assets/ui/ui_button_normal.png"
const BUTTON_HOVER := "res://assets/ui/ui_button_hover.png"
const BUTTON_PRESSED := "res://assets/ui/ui_button_pressed.png"
const BUTTON_DISABLED := "res://assets/ui/ui_button_disabled.png"
## Düz beyaz dolgu ve ince çubuk yuvası (modulate ile renklendirilir).
const FILL := "res://assets/ui/ui_fill.png"
const TRACK := "res://assets/ui/ui_track.png"
## Renklendirilebilir buton dokuları (gri gövde + modulate).
const BUTTON_TINT_NORMAL := "res://assets/ui/ui_button_tint_normal.png"
const BUTTON_TINT_HOVER := "res://assets/ui/ui_button_tint_hover.png"
const BUTTON_TINT_PRESSED := "res://assets/ui/ui_button_tint_pressed.png"
## Sadece çerçeve (içi saydam): seçili/hedef vurgusu.
const TARGET := "res://assets/ui/target_highlight.png"

## 9-slice kenar payı: placeholder'lar 16x16 ve 1px çerçeveli üretiliyor,
## 5px pay köşeleri bozmadan her boyuta esnetir.
const SLICE_MARGIN := 5

static func _texture(path: String) -> Texture2D:
	return load(path) as Texture2D

## PNG'den 9-slice bir StyleBox üretir (panel/buton zeminleri için).
static func stylebox(path: String, margin: int = SLICE_MARGIN) -> StyleBoxTexture:
	if path == PANEL or path == PANEL_DARK or path == SLOT:
		var color := UiTheme.PANEL if path == PANEL else (UiTheme.PANEL_DARK if path == PANEL_DARK else UiTheme.INK)
		var shared := stylebox(BUTTON_TINT_NORMAL, margin)
		shared.modulate_color = color
		return shared
	var box := StyleBoxTexture.new()
	box.texture = _texture(path)
	box.texture_margin_left = margin
	box.texture_margin_right = margin
	box.texture_margin_top = margin
	box.texture_margin_bottom = margin
	# Pixel-art: kenarlar tam piksele otursun, bulanıklaşmasın.
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return box

## PNG zeminli, istenen renge boyanmış bir StyleBox. Prosedürel StyleBoxFlat
## yerine bunu kullanıyoruz: görünen şey yine bir PNG, rengi modulate ile
## geliyor (parti renkleri, çubuk dolguları).
static func color_box(color: Color, path: String = FILL, margin: int = SLICE_MARGIN) -> StyleBoxTexture:
	var box := stylebox(path, margin)
	box.modulate_color = color
	return box

## Bir Panel/PanelContainer'a PNG zemin uygular.
static func skin_panel(panel: Control, path: String = PANEL) -> void:
	panel.add_theme_stylebox_override("panel", stylebox(path))

## Bir Button'a dört durumun PNG zeminini uygular. Yazı font ile çizilir
## (metin kaçınılmaz olarak yazı tipinden gelir), zeminlerin hepsi PNG.
static func skin_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", stylebox(BUTTON_NORMAL))
	button.add_theme_stylebox_override("hover", stylebox(BUTTON_HOVER))
	button.add_theme_stylebox_override("pressed", stylebox(BUTTON_PRESSED))
	button.add_theme_stylebox_override("focus", stylebox(BUTTON_HOVER))
	button.add_theme_stylebox_override("disabled", stylebox(BUTTON_DISABLED))

## İSTENEN RENKTE buton (katıl, oy ver, hamle butonları). Doku gri tonlarında
## olduğu için modulate rengi doğrudan verir; koyu dış çizgi koyu kalır.
## HAMLE SİMGELERİ (assets/icons/actions/<ad>.svg, beyaz; yazı rengine boyanır).
const ACTION_ICON_PATH := "res://assets/icons/actions/%s.svg"

static func action_icon(icon_name: String) -> Texture2D:
	var path := ACTION_ICON_PATH % icon_name
	return load(path) if icon_name != "" and ResourceLoader.exists(path) else null

## Simge yazının üstünde, ortada (hamle ve oy düğmeleri).
static func set_top_icon(button: Button, icon_name: String, size: int) -> void:
	var tex := action_icon(icon_name)
	if tex == null:
		return
	button.icon = tex
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", size)
	button.add_theme_constant_override("h_separation", 1)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_tint_icon(button)

## Simge yazının solunda (geniş düğmeler).
static func set_side_icon(button: Button, icon_name: String, size: int) -> void:
	var tex := action_icon(icon_name)
	if tex == null:
		return
	button.icon = tex
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", size)
	button.add_theme_constant_override("h_separation", 6)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_tint_icon(button)

## Simge yazıyla aynı renkte görünsün (açık zeminde koyu, koyu zeminde açık).
static func _tint_icon(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		var font_key := "font_color" if state == "normal" else "font_%s_color" % state
		var c := button.get_theme_color(font_key) if button.has_theme_color_override(font_key) else button.get_theme_color("font_color")
		button.add_theme_color_override("icon_%s_color" % state, c)
	button.add_theme_color_override("icon_disabled_color", button.get_theme_color("font_disabled_color"))

static func skin_color_button(button: Button, color: Color) -> void:
	button.add_theme_stylebox_override("normal", color_box(color, BUTTON_TINT_NORMAL))
	button.add_theme_stylebox_override("hover", color_box(color, BUTTON_TINT_HOVER))
	button.add_theme_stylebox_override("focus", color_box(color, BUTTON_TINT_HOVER))
	button.add_theme_stylebox_override("pressed", color_box(color, BUTTON_TINT_PRESSED))
	button.add_theme_stylebox_override("disabled", color_box(color.darkened(0.55), BUTTON_TINT_NORMAL))
	var ink := color.get_luminance() > 0.55
	button.add_theme_color_override("font_color", UiTheme.INK if ink else UiTheme.TEXT)
	button.add_theme_color_override("font_hover_color", UiTheme.INK if ink else UiTheme.TEXT)
	button.add_theme_color_override("font_pressed_color", UiTheme.INK if ink else UiTheme.TEXT)
	button.add_theme_color_override("font_focus_color", UiTheme.INK if ink else UiTheme.TEXT)
	button.add_theme_color_override("font_disabled_color", UiTheme.TEXT_DIM)
	button.add_theme_font_override("font", UiTheme.mono())

## Renkli bir "yüzey" (parti rengi vb.) — ColorRect yerine BEYAZ bir PNG'yi
## modulate ederek renklendiriyoruz, böylece görünen şey yine bir PNG olur ve
## sen o PNG'ye doku/desen çizdiğinde her yerde otomatik uygulanır.
static func color_surface(color: Color, path: String = PANEL) -> NinePatchRect:
	var rect := NinePatchRect.new()
	rect.texture = _texture(path)
	rect.patch_margin_left = SLICE_MARGIN
	rect.patch_margin_right = SLICE_MARGIN
	rect.patch_margin_top = SLICE_MARGIN
	rect.patch_margin_bottom = SLICE_MARGIN
	rect.modulate = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return rect

## KONTURLU İKON: ikonun arkasına aynı ikonun koyu kopyaları kaydırılarak
## çizilir, böylece PNG'ye dokunmadan yeni tarzın kalın dış çizgisi olur.
## Büyük bir ikon küçük gösterilirken kenarlar kırılmasın diye mipmap'li
## LINEAR süzgeç kullanılır (simge dokuları).
static func outlined_icon(texture: Texture2D, size: float, outline: float = 2.0,
		tint: Color = Color.WHITE, outline_color: Color = UiTheme.INK) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(size, size)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var offsets: Array[Vector2] = [
		Vector2(-outline, 0), Vector2(outline, 0), Vector2(0, -outline), Vector2(0, outline),
		Vector2(-outline, -outline), Vector2(outline, -outline),
		Vector2(-outline, outline), Vector2(outline, outline)]
	for offset in offsets:
		wrap.add_child(_icon_layer(texture, offset, outline_color))
	wrap.add_child(_icon_layer(texture, Vector2.ZERO, tint))
	return wrap

static func _icon_layer(texture: Texture2D, offset: Vector2, color: Color) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.modulate = color
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.offset_left = offset.x
	rect.offset_right = offset.x
	rect.offset_top = offset.y
	rect.offset_bottom = offset.y
	return rect

## Ekrana yayılan 9-slice bir panel zemini (arka plan katmanı olarak eklenir).
static func panel_background(path: String = PANEL) -> NinePatchRect:
	var rect := color_surface(Color.WHITE, path)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	return rect

## Menü düğmesindeki 3px dış çizgi ve 2px pah, tüm dikdörtgen yüzeylerin
## ortak geometrisidir. Bilgi kutusu yalnız normal durumunu kullanır.
static func apply_style(control: Control, key: StringName, original: StyleBox) -> void:
	var shared: StyleBox = original
	if original is StyleBoxFlat:
		var flat := original as StyleBoxFlat
		# Saydam hedef halkaları ve yuvarlak simgeler yüzey değildir.
		if flat.bg_color.a > 0.0 and flat.corner_radius_top_left <= 8 and flat.corner_radius_top_right <= 8 and flat.corner_radius_bottom_left <= 8 and flat.corner_radius_bottom_right <= 8:
			var texture_path := BUTTON_TINT_NORMAL
			if key == &"pressed" or key == &"hover_pressed":
				texture_path = BUTTON_TINT_PRESSED
			elif key == &"hover" or key == &"focus":
				texture_path = BUTTON_TINT_HOVER
			var box := color_box(flat.bg_color, texture_path)
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				box.set_content_margin(side, maxf(3.0, flat.get_content_margin(side)))
			shared = box
	control.add_theme_stylebox_override(key, shared)
