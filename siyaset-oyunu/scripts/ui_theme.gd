class_name UiTheme
extends RefCounted
## ARAYÜZÜN TEK KAYNAĞI (Konsept C — Piksel).
##
## Renk, yazı boyutu, boşluk, kenar kalınlığı: hepsi burada. Hiçbir ekran kendi
## rengini ya da punto değerini uydurmaz; hepsi buradan okur. Tarzı değiştirmek
## için TEK dosya düzenlenir.
##
## Dokular (panel/buton zeminleri) assets/ui/ altındaki PNG'lerdir ve
## tools/make_ui_art.py ile üretilir — oradaki palet buradakiyle aynıdır.
##
## TARZ: koyu mor-lacivert zemin, kalın koyu dış çizgi, pah (bevel) kenarlar,
## sert gölge, altın vurgu, monospace başlık ve rakamlar.

# --- RENKLER ---------------------------------------------------------------
## Ekran zemini (haritanın ve panellerin arkası).
const BG := Color("181430")
## Sert gölge / dış çizgi.
const INK := Color("100D22")
## Panel dolgusu ve pah renkleri.
const PANEL := Color("2B2352")
const PANEL_LIGHT := Color("4A3F7A")
const PANEL_DARK := Color("1C1738")
## Oyuk (kart yuvası, ilerleme çubuğu zemini).
const SLOT := Color("100D22")

## Yazı.
const TEXT := Color("F2EFFF")
const TEXT_MUTED := Color("A79BD6")
const TEXT_DIM := Color("6B62A0")
const TEXT_ON_GOLD := Color("100D22")

## Vurgular.
const GOLD := Color("FFC93C")
const GOLD_DIM := Color("B08A22")
const GREEN := Color("4BE08A")
const GREEN_DARK := Color("258F53")
const RED := Color("E8402A")
const RED_DARK := Color("8E2215")
const BLUE := Color("3A8DE0")
const PURPLE := Color("A56BE8")

## Anlam renkleri (puan, oy, uyarı).
const POSITIVE := GREEN
const NEGATIVE := RED
const NEUTRAL := TEXT_MUTED

# --- ÖLÇÜLER ---------------------------------------------------------------
## Dokulardaki dış çizgi kalınlığı (make_ui_art.py ile aynı).
const BORDER := 3
## 9-slice kenar payı: 16x16 dokuda kenarların esnemeden kalacağı pay.
const SLICE := 5
## Sert gölge kayması (panellerin altına/sağına).
const SHADOW := 6

## Boşluk basamakları — aralara elle sayı yazılmaz, bunlar kullanılır.
const GAP_XS := 4
const GAP_S := 8
const GAP_M := 14
const GAP_L := 20
const GAP_XL := 28

## İç kenar boşlukları.
const PAD_S := 8
const PAD_M := 14
const PAD_L := 18

## Dokunma hedefi alt sınırı (tablet).
const TOUCH_MIN := 44

# --- YAZI ------------------------------------------------------------------
## Monospace: başlıklar, rakamlar, butonlar. Gövde metni varsayılan yazı tipi.
const FONT_MONO := "res://assets/fonts/IBMPlexMono-SemiBold.ttf"
const FONT_MONO_BOLD := "res://assets/fonts/IBMPlexMono-Bold.ttf"
const FONT_MONO_REGULAR := "res://assets/fonts/IBMPlexMono-Regular.ttf"

## Punto basamakları.
const FS_HUGE := 42   # seçim gecesi rakamı, yıl
const FS_TITLE := 28  # ekran başlığı
const FS_HEAD := 20   # panel başlığı, buton
const FS_BODY := 16   # normal metin
const FS_SMALL := 14  # ikincil metin
const FS_TINY := 12   # etiket, ipucu

static func mono(bold: bool = false) -> FontFile:
	return load(FONT_MONO_BOLD if bold else FONT_MONO) as FontFile

static func mono_regular() -> FontFile:
	return load(FONT_MONO_REGULAR) as FontFile

# --- YARDIMCILAR -----------------------------------------------------------

## Panel başlığı: monospace, altın, büyük harf, "> " önekli.
## Monospace geniş olduğu için başlık paneli ZORLA GENİŞLETMEZ: sığmazsa
## satır kaydırır (sol panelin 260 piksellik genişliği sabit kalsın).
static func section_label(text: String, color: Color = GOLD) -> Label:
	var label := Label.new()
	label.text = "> " + text.to_upper()
	label.add_theme_font_override("font", mono())
	label.add_theme_font_size_override("font_size", FS_TINY + 3)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 1.0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

## Monospace etiket (rakamlar, başlıklar).
static func mono_label(text: String, size: int = FS_HEAD, color: Color = TEXT, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", mono(bold))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

## Gövde metni (varsayılan yazı tipi, okunaklı).
static func body_label(text: String, size: int = FS_BODY, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

## Kartın solunda parti renginde dikey şerit. PanelContainer çocuklarını
## kendi alanına yaydığı için şerit KUTUNUN İÇİNE, sabit genişlikte bir öge
## olarak eklenir (üste bindirilmez).
static func stripe(color: Color, width: int = 6) -> Control:
	var bar := UiSkin.color_surface(color, UiSkin.FILL)
	bar.custom_minimum_size.x = width
	bar.size_flags_vertical = Control.SIZE_FILL
	return bar

## İki nokta arasını ayıran 3 piksellik çizgi (HSeparator yerine).
static func rule(color: Color = PANEL_LIGHT) -> Control:
	var line := ColorRect.new()
	line.color = color
	line.custom_minimum_size.y = BORDER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line
