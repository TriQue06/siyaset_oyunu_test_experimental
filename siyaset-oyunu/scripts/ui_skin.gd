class_name UiSkin
extends RefCounted
## Arayüzün GÖRÜNEN her yüzeyini (panel, düğme, oyuk, çerçeve) üreten yardımcı.
##
## 0.0.265 · MASA OYUNU: her yüzey vektör (StyleBoxFlat); doku yok, her
## çözünürlükte keskin. Paneller krem karton ve altlarında karton kalınlığı,
## düğmeler tombul, altlarında koyu bir kalınlık şeridi; basınca gömülür.
## Eski PNG yolu sabitleri yalnız "hangi tür yüzey" anahtarı olarak kalır.

const PANEL := "res://assets/ui/ui_panel.png"
const PANEL_DARK := "res://assets/ui/ui_panel_dark.png"
const SLOT := "res://assets/ui/ui_slot.png"
const BUTTON_NORMAL := "res://assets/ui/ui_button_normal.png"
const BUTTON_HOVER := "res://assets/ui/ui_button_hover.png"
const BUTTON_PRESSED := "res://assets/ui/ui_button_pressed.png"
const BUTTON_DISABLED := "res://assets/ui/ui_button_disabled.png"
## Düz dolgu ve ince çubuk yuvası (renk verilerek kullanılır).
const FILL := "res://assets/ui/ui_fill.png"
const TRACK := "res://assets/ui/ui_track.png"
## Renk verilen düğme yüzeyleri.
const BUTTON_TINT_NORMAL := "res://assets/ui/ui_button_tint_normal.png"
const BUTTON_TINT_HOVER := "res://assets/ui/ui_button_tint_hover.png"
const BUTTON_TINT_PRESSED := "res://assets/ui/ui_button_tint_pressed.png"
## Sadece çerçeve (içi boş): seçili/hedef vurgusu.
const TARGET := "res://assets/ui/target_highlight.png"

## Eski 9-slice payı (imza uyumu için; vektörde kullanılmaz).
const SLICE_MARGIN := 5

# --- Temel yüzeyler ----------------------------------------------------------

## Yuvarlak köşeli düz yüzey.
static func flat(bg: Color, radius: int = UiTheme.RADIUS) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	box.corner_detail = 10
	return box

## KARTON PANEL: krem zemin, deniz yeşili kenar, altında karton kalınlığı.
static func board(bg: Color = UiTheme.PANEL, border: Color = UiTheme.TEAL, thick: int = UiTheme.THICK_PANEL,
		radius: int = UiTheme.RADIUS_PANEL) -> StyleBoxFlat:
	var box := flat(bg, radius)
	box.border_color = border
	box.set_border_width_all(UiTheme.BORDER + 1)
	box.shadow_color = UiTheme.EDGE
	box.shadow_size = 1
	box.shadow_offset = Vector2(0, thick)
	box.set_content_margin_all(UiTheme.PAD_M)
	return box

## İç kart (panel içindeki satır/kutu): beyazımsı, ince kenar, ince kalınlık.
static func card(bg: Color = UiTheme.PANEL_DARK, edge: Color = UiTheme.PANEL_LIGHT) -> StyleBoxFlat:
	var box := flat(bg, UiTheme.RADIUS)
	box.border_color = edge
	box.set_border_width_all(UiTheme.BORDER)
	box.border_width_bottom = UiTheme.THICK_S + 1
	box.set_content_margin_all(UiTheme.PAD_S)
	return box

## OYUK: yazı kutusu, çubuk yuvası (üst kenarı koyu, içe basık görünür).
static func groove(bg: Color = UiTheme.SLOT) -> StyleBoxFlat:
	var box := flat(bg, UiTheme.RADIUS_S)
	box.border_color = bg.darkened(0.14)
	box.border_width_top = UiTheme.BORDER + 1
	box.set_content_margin_all(UiTheme.PAD_S)
	return box

## TOMBUL DÜĞME yüzeyi. state: "normal" | "hover" | "pressed" | "disabled".
static func button_box(color: Color, state: String = "normal") -> StyleBoxFlat:
	var body := color
	var lip := UiTheme.THICK
	match state:
		"hover":
			body = color.lightened(0.08)
		"pressed":
			body = color.darkened(0.04)
			lip = 2
		"disabled":
			body = color.lerp(UiTheme.PANEL_LIGHT, 0.55)
	var box := flat(body, UiTheme.RADIUS)
	box.border_color = color.darkened(0.36) if state != "disabled" else body.darkened(0.2)
	box.border_width_bottom = lip
	# Kalınlık düğmenin ALTINA taşar: yazı yalnız ana yüzün ortasına hizalanır.
	box.expand_margin_bottom = float(lip)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	if state == "pressed":
		# Gömülme: yüz kalınlık farkı kadar aşağı iner, yazı da onunla.
		var sink := float(UiTheme.THICK - lip)
		box.expand_margin_top = -sink
		box.expand_margin_bottom = float(UiTheme.THICK)
		box.content_margin_top = 6 + sink
		box.content_margin_bottom = 6 - sink
	return box

## Kaydırıcı topuzu: hardal yuvarlak piyon (vektörden üretilir, keskin).
static var _knob: ImageTexture

static func knob_texture() -> Texture2D:
	if _knob == null:
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="28" height="30"><circle cx="14" cy="16" r="12" fill="#%s"/><circle cx="14" cy="13" r="12" fill="#%s"/><circle cx="14" cy="13" r="12" fill="none" stroke="#%s" stroke-width="2.5"/></svg>' % [
			UiTheme.GOLD_DIM.to_html(false), UiTheme.GOLD.to_html(false), UiTheme.INK.to_html(false)]
		var image := Image.new()
		image.load_svg_from_string(svg, 1.0)
		_knob = ImageTexture.create_from_image(image)
	return _knob

## Hedef/seçim halkası: içi boş, kalın renkli kenar.
static func ring(color: Color, width: int = 3, radius: int = UiTheme.RADIUS) -> StyleBoxFlat:
	var box := flat(Color(0, 0, 0, 0), radius)
	box.draw_center = false
	box.border_color = color
	box.set_border_width_all(width)
	return box

# --- Eski arayüz (yol anahtarıyla yüzey türü) --------------------------------

## Yol anahtarına göre yüzey (panel, oyuk, düğme durumları, dolgu, çerçeve).
static func stylebox(path: String, _margin: int = SLICE_MARGIN) -> StyleBox:
	match path:
		PANEL:
			return board()
		PANEL_DARK:
			return board(UiTheme.PANEL, UiTheme.TEAL, UiTheme.THICK_PANEL)
		SLOT:
			return groove()
		BUTTON_NORMAL, BUTTON_TINT_NORMAL:
			return button_box(UiTheme.PANEL_LIGHT, "normal")
		BUTTON_HOVER, BUTTON_TINT_HOVER:
			return button_box(UiTheme.PANEL_LIGHT, "hover")
		BUTTON_PRESSED, BUTTON_TINT_PRESSED:
			return button_box(UiTheme.PANEL_LIGHT, "pressed")
		BUTTON_DISABLED:
			return button_box(UiTheme.PANEL_LIGHT, "disabled")
		TRACK:
			var track := groove()
			track.set_corner_radius_all(99)
			track.set_content_margin_all(2)
			return track
		TARGET:
			return ring(UiTheme.GOLD)
	return flat(UiTheme.PANEL, UiTheme.RADIUS_S)

## İstenen renkte yüzey: yol anahtarı türünü seçer (düğme, oyuk, dolgu...).
static func color_box(color: Color, path: String = FILL, _margin: int = SLICE_MARGIN) -> StyleBox:
	match path:
		BUTTON_TINT_NORMAL, BUTTON_NORMAL:
			return button_box(color, "normal")
		BUTTON_TINT_HOVER, BUTTON_HOVER:
			return button_box(color, "hover")
		BUTTON_TINT_PRESSED, BUTTON_PRESSED:
			return button_box(color, "pressed")
		BUTTON_DISABLED:
			return button_box(color, "disabled")
		SLOT:
			return groove(color)
		TARGET:
			return ring(color)
		PANEL, PANEL_DARK:
			return board(color)
		TRACK:
			var track := flat(color, 99)
			track.set_content_margin_all(2)
			return track
	return flat(color, UiTheme.RADIUS_S)

## Bir Panel/PanelContainer'a karton zemin uygular.
static func skin_panel(panel: Control, path: String = PANEL) -> void:
	panel.add_theme_stylebox_override("panel", stylebox(path))

## Nötr (krem) düğme: dört durum.
static func skin_button(button: Button) -> void:
	skin_color_button(button, UiTheme.PANEL_LIGHT)

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

## Simge yazıyla aynı renkte görünsün.
static func _tint_icon(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		var font_key := "font_color" if state == "normal" else "font_%s_color" % state
		var c := button.get_theme_color(font_key) if button.has_theme_color_override(font_key) else button.get_theme_color("font_color")
		button.add_theme_color_override("icon_%s_color" % state, c)
	button.add_theme_color_override("icon_disabled_color", button.get_theme_color("font_disabled_color"))

## Açık renkli zeminde koyu, koyu zeminde beyaz yazı.
static func text_on(color: Color) -> Color:
	if color.get_luminance() > 0.62:
		return UiTheme.TEXT_ON_GOLD if color.s > 0.45 else UiTheme.TEXT
	return UiTheme.ON_COLOR

## İSTENEN RENKTE tombul düğme (katıl, oy ver, hamle düğmeleri).
static func skin_color_button(button: Button, color: Color) -> void:
	button.add_theme_stylebox_override("normal", button_box(color, "normal"))
	button.add_theme_stylebox_override("hover", button_box(color, "hover"))
	button.add_theme_stylebox_override("focus", button_box(color, "hover"))
	button.add_theme_stylebox_override("pressed", button_box(color, "pressed"))
	button.add_theme_stylebox_override("hover_pressed", button_box(color, "pressed"))
	button.add_theme_stylebox_override("disabled", button_box(color, "disabled"))
	var ink := text_on(color)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(key, ink)
	button.add_theme_color_override("font_disabled_color", UiTheme.TEXT_DIM)
	button.add_theme_font_override("font", UiTheme.mono(true))

## Küçük düğme (çip boyu): ince kalınlık, dar iç boşluk, küçük köşe. Tombul
## düğme yüzeyi kurulduktan sonra çağrılır (skin_color_button vb.).
static func compact(button: Button, pad_x: int = 6, lip: int = 3) -> void:
	for state in ["normal", "hover", "focus", "pressed", "hover_pressed", "disabled"]:
		if not button.has_theme_stylebox_override(state):
			continue
		var box := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		if box == null:
			continue
		var pressed: bool = state == "pressed" or state == "hover_pressed"
		box.set_corner_radius_all(UiTheme.RADIUS_S - 2)
		box.border_width_bottom = 1 if pressed else lip
		box.expand_margin_top = -float(lip - 1) if pressed else 0.0
		box.expand_margin_bottom = float(lip)
		box.content_margin_left = pad_x
		box.content_margin_right = pad_x
		box.content_margin_top = 1 + (lip - 1 if pressed else 0)
		box.content_margin_bottom = 1 - (lip - 1 if pressed else 0)
		button.add_theme_stylebox_override(state, box)

## Renkli bir "yüzey" (parti rengi, çizgi, dolgu): yuvarlak köşeli düz panel.
static func color_surface(color: Color, path: String = PANEL) -> Panel:
	var rect := Panel.new()
	var radius := UiTheme.RADIUS_S if path != FILL else 3
	var style: StyleBox
	if path == TARGET:
		style = ring(color)
	elif path == PANEL or path == PANEL_DARK:
		style = board(color)
	else:
		style = flat(color, radius)
	rect.add_theme_stylebox_override("panel", style)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

## KONTURLU İKON: ikonun arkasına aynı ikonun koyu kopyaları kaydırılarak
## çizilir (kalın dış çizgi). Mipmap'li LINEAR süzgeç.
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

## Ekrana yayılan karton panel zemini (arka plan katmanı olarak eklenir).
static func panel_background(path: String = PANEL) -> Panel:
	var rect := Panel.new()
	rect.add_theme_stylebox_override("panel", stylebox(path))
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	return rect

## Ekranlardaki elle yazılmış StyleBoxFlat'ler bu kapıdan geçer: hepsi masa
## oyunu diline çevrilir (yuvarlak köşe, mürekkep kenar yerine deniz yeşili,
## sert gölge yerine karton kalınlığı, düğme durumlarında gömülme).
static func apply_style(control: Control, key: StringName, original: StyleBox) -> void:
	var shared: StyleBox = original
	if original is StyleBoxFlat:
		var flat_in := original as StyleBoxFlat
		var box := flat_in.duplicate() as StyleBoxFlat
		box.anti_aliasing = true
		box.corner_detail = 10
		var round_corners := flat_in.corner_radius_top_left < 40 and flat_in.corner_radius_bottom_right < 40
		if round_corners:
			var r := UiTheme.RADIUS_S if minf(control.custom_minimum_size.y, 999.0) < 30.0 else UiTheme.RADIUS
			box.corner_radius_top_left = maxi(flat_in.corner_radius_top_left, r)
			box.corner_radius_top_right = maxi(flat_in.corner_radius_top_right, r)
			box.corner_radius_bottom_left = maxi(flat_in.corner_radius_bottom_left, r)
			box.corner_radius_bottom_right = maxi(flat_in.corner_radius_bottom_right, r)
		if box.border_color.is_equal_approx(UiTheme.INK) and box.bg_color.get_luminance() > 0.5:
			box.border_color = UiTheme.TEAL
		# Sert gölge (boyutsuz, kaydırılmış) karton kalınlığına dönüşür.
		if flat_in.shadow_size == 0 and flat_in.shadow_offset != Vector2.ZERO:
			box.shadow_size = 1
			box.shadow_color = UiTheme.EDGE
			box.shadow_offset = Vector2(0, maxf(flat_in.shadow_offset.y, 4.0))
		if flat_in.draw_center and flat_in.bg_color.a > 0.0 and (key == &"pressed" or key == &"hover_pressed"):
			box.bg_color = flat_in.bg_color.darkened(0.05)
		elif flat_in.draw_center and flat_in.bg_color.a > 0.0 and (key == &"hover" or key == &"focus"):
			box.bg_color = flat_in.bg_color.lightened(0.07)
		shared = box
	control.add_theme_stylebox_override(key, shared)

## Pasif hamleler de kalınlığını korur; yalnız gövde ve yazı söner.
## Button.disabled kullanılmaz: basınca engelin nedeni açıklanabilir.
static func skin_action_button(button: Button, color: Color, available: bool) -> void:
	skin_color_button(button, color if available else color.lerp(UiTheme.PANEL_LIGHT, 0.6))
	if not available:
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(key, UiTheme.TEXT_DIM)
	_tint_icon(button)
