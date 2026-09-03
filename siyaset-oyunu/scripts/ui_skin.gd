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

## 9-slice kenar payı: placeholder'lar 16x16 ve 1px çerçeveli üretiliyor,
## 5px pay köşeleri bozmadan her boyuta esnetir.
const SLICE_MARGIN := 5

static func _texture(path: String) -> Texture2D:
	return load(path) as Texture2D

## PNG'den 9-slice bir StyleBox üretir (panel/buton zeminleri için).
static func stylebox(path: String, margin: int = SLICE_MARGIN) -> StyleBoxTexture:
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

## Ekrana yayılan 9-slice bir panel zemini (arka plan katmanı olarak eklenir).
static func panel_background(path: String = PANEL) -> NinePatchRect:
	var rect := color_surface(Color.WHITE, path)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	return rect
