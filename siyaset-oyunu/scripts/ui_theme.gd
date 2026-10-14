class_name UiTheme
extends RefCounted
## ARAYÜZÜN TEK KAYNAĞI (0.0.176: OYUN MASASI teması; eski "haber stüdyosu"
## paleti git dalı tema-haber-studyosu'nda).
##
## Renk, yazı boyutu, boşluk, kenar kalınlığı: hepsi burada. Hiçbir ekran kendi
## rengini ya da punto değerini uydurmaz; hepsi buradan okur. Tarzı değiştirmek
## için TEK dosya düzenlenir.
##
## Dokular (panel/buton zeminleri) assets/ui/ altındaki PNG'lerdir ve
## tools/make_board_art.py ile üretilir — oradaki palet buradakiyle aynıdır.
##
## TARZ: bordo keçe masa, ceviz ahşap paneller, krem kâğıt, pirinç vurgu,
## yuvarlak köşeler, monospace başlık ve rakamlar.

# --- RENKLER ---------------------------------------------------------------
## Ekran zemini (haritanın ve panellerin arkası).
const BG := Color("3A1A1F")
## Sert gölge / dış çizgi.
const INK := Color("1E120A")
## Panel dolgusu ve pah renkleri.
const PANEL := Color("3B2617")
const PANEL_LIGHT := Color("5A3C24")
const PANEL_DARK := Color("2A1A10")
## Oyuk (kart yuvası, ilerleme çubuğu zemini).
const SLOT := Color("1A0F09")

## Yazı.
const TEXT := Color("F5EAD2")
const TEXT_MUTED := Color("C9B48F")
const TEXT_DIM := Color("8A7358")
const TEXT_ON_GOLD := Color("2A1A10")

## Vurgular.
const GOLD := Color("E4B43C")
const GOLD_DIM := Color("9A7420")
const GREEN := Color("7BC86A")
const GREEN_DARK := Color("2F7A45")
const RED := Color("D9473A")
const RED_DARK := Color("7E231A")
const BLUE := Color("3F7FC8")
const PURPLE := Color("8E5BBF")

## Anlam renkleri (puan, oy, uyarı).
const POSITIVE := GREEN
const NEGATIVE := RED
const NEUTRAL := TEXT_MUTED

# --- ÖLÇÜLER ---------------------------------------------------------------
## Dokulardaki dış çizgi kalınlığı (make_ui_art.py ile aynı).
const BORDER := 3
## 9-slice kenar payı: 16x16 dokuda kenarların esnemeden kalacağı pay.
const SLICE := 10
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
