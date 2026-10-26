class_name UiTheme
extends RefCounted
## ARAYÜZÜN TEK KAYNAĞI (0.0.266 · MASA OYUNU, HTML konseptiyle birebir).
##
## Renk, yazı boyutu, boşluk, kenar kalınlığı: hepsi burada. Hiçbir ekran kendi
## rengini ya da punto değerini uydurmaz; hepsi buradan okur. Tarzı değiştirmek
## için TEK dosya düzenlenir.
##
## TARZ: yeşil çuha masa üstünde kalın karton oyun tahtası. Paneller krem
## karton (altında karton kalınlığı), düğmeler tombul ve altlarında koyu bir
## "kalınlık" şeridi; basınca gömülür. Bant ve masa ahşap. Başlıklar Siyaset
## Display (Lilita One + Türkçe harfler), gövde Nunito. Her yüzey vektör
## (BoardBox / StyleBoxFlat). Ölçüler konseptin 1920 px'lik HTML'inden: d(px).

# --- RENKLER ---------------------------------------------------------------
## Ekran zemini: yeşil çuha masa.
const BG := Color("1D5A3D")
const FELT_LIGHT := Color("2E7A55")
const FELT_DARK := Color("0F3524")
## Mürekkep: koyu yazı, dış çizgi, koyu yazı zemini.
const INK := Color("2D2A26")
## Karton: panel dolgusu ve tonları.
const PANEL := Color("F7EED8")
## Pasif sekme / ikincil düğme / çip zemini.
const PANEL_LIGHT := Color("E3D5B0")
## Panel içindeki kart/satır zemini.
const PANEL_DARK := Color("FFFAF0")
## Oyuk (ilerleme çubuğu zemini, yazı kutusu).
const SLOT := Color("EADFC4")
## Karton kalınlığı (panellerin altındaki kenar).
const EDGE := Color("B79A68")
const EDGE_DARK := Color("8F744A")
## Panel çerçevesi (çift ince çizgi).
const TEAL := Color("1F6E70")
const TEAL_DARK := Color("16575A")
const TEAL_DEEP := Color("0D3A3C")
## İç kartların kalınlığı.
const CARD_LIP := Color("C9B689")
## Ahşap üstündeki yazının gölgesi.
const WOOD_SHADOW := Color("6A3B18")
## Kasa yeşili.
const MONEY := Color("1F8A4C")
## Kriz kırmızısı.
const CRISIS := Color("C42B2B")
const CRISIS_DARK := Color("7F1B1B")
## Ahşap (üst bant, alt masa).
const WOOD := Color("A8693A")
const WOOD_LIGHT := Color("C88A4D")
const WOOD_DARK := Color("8A5129")
const WOOD_TEXT := Color("FFF6E0")
const WOOD_TEXT_MUTED := Color("FFE3A8")

## Yazı (karton üstünde).
const TEXT := Color("2D2A26")
const TEXT_MUTED := Color("7A7166")
const TEXT_MUTED2 := Color("6A6258")
## Pasif sekme yazısı.
const TAB_TEXT := Color("5D6B6B")
const TEXT_DIM := Color("A39A8A")
const TEXT_ON_GOLD := Color("4A3203")
## Renkli düğme / koyu zemin üstündeki yazı.
const ON_COLOR := Color("FFFFFF")
## Başlık ve vurgu yazısı (karton üstünde okunur).
const HEAD := Color("1F6E70")

## Vurgular (dolgular).
const GOLD := Color("F2B632")
const GOLD_DIM := Color("B58312")
const GREEN := Color("2FA866")
const GREEN_DARK := Color("1F8A4C")
const RED := Color("D93636")
const RED_DARK := Color("A12424")
const BLUE := Color("2B6FD9")
const PURPLE := Color("7B4FD6")

## Anlam renkleri (puan, oy, uyarı).
const POSITIVE := GREEN_DARK
const NEGATIVE := RED
const NEUTRAL := TEXT_MUTED

# --- ÖLÇÜLER ---------------------------------------------------------------
## Çerçeve çizgisi kalınlığı.
const BORDER := 2
## Köşe yuvarlaklığı: panel / düğme / küçük parça.
const RADIUS_PANEL := 16
const RADIUS := 12
const RADIUS_S := 8
## Karton kalınlığı: panel ve düğmelerin altındaki koyu şerit.
const THICK_PANEL := 7
const THICK := 6
const THICK_S := 3
## Eski adlar (9-slice dönemi): bazı yerler hâlâ okur.
const SLICE := 5
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
## Başlık yazısı (Nunito, çok kalın): başlıklar, rakamlar, düğmeler. Gövde (Nunito):
## varsayılan yazı tipi. İkisi de Türkçe harflerin tamamını içerir.
const FONT_MONO := "res://assets/fonts/display.tres"
const FONT_MONO_BOLD := "res://assets/fonts/display_bold.tres"
const FONT_MONO_REGULAR := "res://assets/fonts/body_bold.tres"
const FONT_BODY := "res://assets/fonts/body.tres"

## Punto basamakları.
const FS_HUGE := 42   # seçim gecesi rakamı, yıl
const FS_TITLE := 28  # ekran başlığı
const FS_HEAD := 20   # panel başlığı, buton
const FS_BODY := 16   # normal metin
const FS_SMALL := 14  # ikincil metin
const FS_TINY := 12   # etiket, ipucu

## Başlık yazı tipi (adı eski: önceden monospace idi).
static func mono(bold: bool = false) -> Font:
	return load(FONT_MONO_BOLD if bold else FONT_MONO) as Font

static func mono_regular() -> Font:
	return load(FONT_MONO_REGULAR) as Font

static func body() -> Font:
	return load(FONT_BODY) as Font

## Nunito 900 (konseptteki en kalın gövde yazısı: süre, kasa etiketi).
static func body_black() -> Font:
	return load("res://assets/fonts/body_black.tres") as Font

# --- YARDIMCILAR -----------------------------------------------------------

## Konseptin HTML pikselini (1920 genişlik) tasarım birimine çevirir.
static func d(html_px: float) -> float:
	return html_px / 1.5

## Konsept puntosu (HTML px) -> oyun puntosu.
static func fs(html_px: float) -> int:
	return int(round(html_px / 1.5))

## Panel başlığı: başlık yazısı, deniz yeşili, büyük harf.
## Başlık paneli ZORLA GENİŞLETMEZ: sığmazsa satır kaydırır.
static func section_label(text: String, color: Color = HEAD) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", mono(true))
	label.add_theme_font_size_override("font_size", fs(19))
	label.add_theme_color_override("font_color", color)
	# Konsept .sech: solda 14 px hardal nokta, altında koyu hardal gölge.
	var dot := BoardBox.new()
	dot.draw_fill = false
	dot.dot_radius = d(7)
	dot.dot_pos = Vector2(d(7), d(13))
	dot.dot_color = GOLD
	dot.dot_lip = d(2)
	dot.dot_lip_color = GOLD_DIM
	dot.content_margin_left = d(22)
	label.add_theme_stylebox_override("normal", dot)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 1.0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

## Başlık yazısıyla etiket (rakamlar, başlıklar).
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

## Kartın solunda parti renginde dikey şerit (yuvarlak uçlu). PanelContainer
## çocuklarını kendi alanına yaydığı için şerit KUTUNUN İÇİNE eklenir.
static func stripe(color: Color, width: int = 6) -> Control:
	var bar := UiSkin.color_surface(color, UiSkin.FILL)
	bar.custom_minimum_size.x = width
	bar.size_flags_vertical = Control.SIZE_FILL
	return bar

## İki bölümü ayıran ince, yuvarlak uçlu çizgi (HSeparator yerine).
static func rule(color: Color = PANEL_LIGHT) -> Control:
	var line := UiSkin.color_surface(color, UiSkin.FILL)
	line.custom_minimum_size.y = BORDER
	return line
