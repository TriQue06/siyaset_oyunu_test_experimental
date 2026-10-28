class_name UiSkin
extends RefCounted
## Arayüzün GÖRÜNEN her yüzeyini (panel, düğme, oyuk, çerçeve) üreten yardımcı.
##
## 0.0.265 · MASA OYUNU: her yüzey vektör (StyleBoxFlat); doku yok, her
## çözünürlükte keskin. Paneller krem karton ve altlarında karton kalınlığı,
## düğmeler tombul, altlarında koyu bir kalınlık şeridi; basınca gömülür.
# --- Temel yüzeyler (HTML konseptiyle birebir; ölçüler UiTheme.d ile) -------

## Yuvarlak köşeli düz yüzey.
static func flat(bg: Color, radius: int = UiTheme.RADIUS) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	box.corner_detail = 10
	return box

static func _bb(fill: Color, radius_px: float) -> BoardBox:
	var b := BoardBox.new()
	b.fill = fill
	b.set_radius(UiTheme.d(radius_px))
	return b

## ANA PANO (.panel): krem karton (yukarıdan aşağı #f7eed8 → #efe2c0), içte
## çift deniz yeşili çizgi, altta iki kat karton kalınlığı ve yumuşak gölge,
## sol üstte küçük basılı nokta.
static func board(bg: Color = UiTheme.PANEL, border: Color = UiTheme.TEAL, _thick: int = 0,
		_radius: int = 0) -> BoardBox:
	var b := _bb(bg, 18)
	if bg.is_equal_approx(UiTheme.PANEL):
		b.fill_bottom = Color("EFE2C0")
	b.rings = [[UiTheme.d(6), UiTheme.d(3), border], [UiTheme.d(11), UiTheme.d(1), border]]
	b.lips = [[UiTheme.d(8), UiTheme.EDGE], [UiTheme.d(10), UiTheme.EDGE_DARK]]
	b.shadow_color = Color(0, 0, 0, 0.45)
	b.shadow_offset = Vector2(0, UiTheme.d(18))
	b.shadow_size = UiTheme.d(14)
	b.dot_radius = UiTheme.d(3)
	b.dot_pos = Vector2(UiTheme.d(20), UiTheme.d(20))
	b.dot_color = border
	b.set_content_margin_all(UiTheme.d(22))
	return b

## BANT KUTUSU / KASA (.box): krem, içte tek deniz yeşili çizgi, kalınlık.
static func plate(bg: Color = UiTheme.PANEL, border: Color = UiTheme.TEAL) -> BoardBox:
	var b := _bb(bg, 14)
	b.rings = [[UiTheme.d(3), UiTheme.d(2), border]]
	b.lips = [[UiTheme.d(6), UiTheme.EDGE], [UiTheme.d(7), UiTheme.EDGE_DARK]]
	b.shadow_color = Color(0, 0, 0, 0.35)
	b.shadow_offset = Vector2(0, UiTheme.d(12))
	b.shadow_size = UiTheme.d(9)
	b.set_content_margin_all(UiTheme.d(10))
	return b

## İÇ KART (panel içindeki satır, meclis kutusu, hazine): beyazımsı, ince
## kenar ve ince kalınlık. edge: kenar; lip: kalınlık rengi.
static func card(bg: Color = UiTheme.PANEL_DARK, edge: Color = UiTheme.PANEL_LIGHT,
		lip: Color = UiTheme.CARD_LIP, lip_px: float = 4.0) -> BoardBox:
	var b := _bb(bg, 14)
	b.rings = [[0.0, UiTheme.d(2), edge]]
	b.lips = [[UiTheme.d(lip_px), lip]]
	b.set_content_margin_all(UiTheme.d(10))
	return b

## OYUK: yazı kutusu, çubuk yuvası (içe basık: üstte koyu gölge şeridi).
static func groove(bg: Color = UiTheme.SLOT) -> BoardBox:
	var b := _bb(bg, 8)
	b.highlight_size = UiTheme.d(3)
	b.highlight_color = Color(0, 0, 0, 0.08)
	b.set_content_margin_all(UiTheme.d(10))
	return b

## SEKME (.tab): üst köşeler yuvarlak; pasif krem, seçili hardal.
static func tab_box(active: bool, state: String = "normal") -> BoardBox:
	var b := _bb(UiTheme.GOLD if active else UiTheme.PANEL_LIGHT, 12)
	b.radius_bl = UiTheme.d(6)
	b.radius_br = UiTheme.d(6)
	if active:
		b.highlight_size = UiTheme.d(2)
		b.highlight_color = Color(1, 1, 1, 0.4)
		b.lips = [[UiTheme.d(4), UiTheme.GOLD_DIM]]
		b.shadow_color = Color(0, 0, 0, 0.2)
		b.shadow_offset = Vector2(0, UiTheme.d(6))
		b.shadow_size = UiTheme.d(5)
	else:
		b.shade_size = UiTheme.d(3)
		b.shade_color = Color(0, 0, 0, 0.08)
		b.lips = [[UiTheme.d(3), UiTheme.CARD_LIP]]
	if state == "hover" and not active:
		b.offset_y = -UiTheme.d(2)
	b.content_margin_left = UiTheme.d(10)
	b.content_margin_right = UiTheme.d(10)
	b.content_margin_top = UiTheme.d(4)
	b.content_margin_bottom = UiTheme.d(4)
	return b

## TOMBUL DÜĞME (.act): üstte parlama, altta iç koyuluk, iki kat koyu kalınlık
## ve yumuşak gölge. Kalınlık düğmenin ALTINA taşar: yazı ana yüzün ortasında.
## Üstüne gelince 2 px kalkar; basınca kalınlığına gömülür (yazı da iner).
static func button_box(color: Color, state: String = "normal") -> BoardBox:
	var face := color
	if state == "disabled":
		face = color.lerp(UiTheme.PANEL_LIGHT, 0.55)
	var b := _bb(face, 16)
	b.highlight_size = UiTheme.d(3)
	b.highlight_color = Color(1, 1, 1, 0.35)
	b.shade_size = UiTheme.d(4)
	b.shade_color = Color(0, 0, 0, 0.12)
	var lip1 := face.lerp(Color.BLACK, 0.38)
	var lip2 := face.lerp(Color.BLACK, 0.6)
	b.lips = [[UiTheme.d(8), lip1], [UiTheme.d(9), lip2]]
	b.shadow_color = Color(0, 0, 0, 0.4)
	b.shadow_offset = Vector2(0, UiTheme.d(16))
	b.shadow_size = UiTheme.d(10)
	var pad := UiTheme.d(9)
	b.content_margin_left = UiTheme.d(18)
	b.content_margin_right = UiTheme.d(18)
	b.content_margin_top = pad
	b.content_margin_bottom = pad
	match state:
		"hover":
			b.offset_y = -UiTheme.d(2)
			b.lips = [[UiTheme.d(10), lip1], [UiTheme.d(11), lip2]]
			b.content_margin_top = pad - UiTheme.d(2)
			b.content_margin_bottom = pad + UiTheme.d(2)
		"pressed":
			var sink := UiTheme.d(7)
			b.offset_y = sink
			b.lips = [[UiTheme.d(1), lip1], [UiTheme.d(2), lip2]]
			b.shadow_offset = Vector2(0, UiTheme.d(4))
			b.shadow_size = UiTheme.d(4)
			b.content_margin_top = pad + sink
			b.content_margin_bottom = maxf(0.0, pad - sink)
	return b

## MENÜ DÜĞMESİ (deniz yeşili, bantta): .menu
static func menu_box(state: String = "normal") -> BoardBox:
	var b := _bb(UiTheme.TEAL, 14)
	b.highlight_size = UiTheme.d(2)
	b.highlight_color = Color(1, 1, 1, 0.3)
	b.lips = [[UiTheme.d(6), UiTheme.TEAL_DARK], [UiTheme.d(7), UiTheme.TEAL_DEEP]]
	b.shadow_color = Color(0, 0, 0, 0.35)
	b.shadow_offset = Vector2(0, UiTheme.d(12))
	b.shadow_size = UiTheme.d(9)
	var pad := UiTheme.d(6)
	b.set_content_margin_all(pad)
	if state == "pressed":
		b.offset_y = UiTheme.d(5)
		b.lips = [[UiTheme.d(1), UiTheme.TEAL_DARK], [UiTheme.d(2), UiTheme.TEAL_DEEP]]
		b.shadow_offset = Vector2(0, UiTheme.d(4))
		b.shadow_size = UiTheme.d(4)
		b.content_margin_top = pad + UiTheme.d(5)
		b.content_margin_bottom = maxf(0.0, pad - UiTheme.d(5))
	elif state == "hover":
		b.fill = UiTheme.TEAL.lightened(0.06)
	return b

## KÜÇÜK DÜĞME (vergi kademesi vb.): ince kalınlık, gölgesiz.
static func chip_box(color: Color, state: String = "normal") -> BoardBox:
	var b := _bb(color, 8)
	var lip := UiTheme.CARD_LIP if color.is_equal_approx(UiTheme.SLOT) or color.is_equal_approx(UiTheme.PANEL_LIGHT) 		else color.lerp(Color.BLACK, 0.3)
	b.lips = [[UiTheme.d(2), lip]]
	if state == "hover":
		b.fill = color.lightened(0.06)
	elif state == "pressed":
		b.offset_y = UiTheme.d(1)
		b.lips = [[UiTheme.d(1), lip]]
	b.content_margin_left = UiTheme.d(8)
	b.content_margin_right = UiTheme.d(8)
	b.content_margin_top = UiTheme.d(2)
	b.content_margin_bottom = UiTheme.d(2)
	return b

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

## İnce çubuk yuvası.
static func track_box() -> BoardBox:
	var track := groove()
	track.set_radius(UiTheme.d(6))
	track.set_content_margin_all(2)
	return track

## Bir Panel/PanelContainer'a karton zemin uygular.
static func skin_panel(panel: Control) -> void:
	panel.add_theme_stylebox_override("panel", board())

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

## İSTENEN RENKTE tombul düğme (katıl, oy ver, hamle düğmeleri). Krem / açık
## renkli düğmelerde koyu yazı; renkli düğmelerde beyaz yazı ve altında sert
## yazı gölgesi (HTML: text-shadow 0 3px 0 rgba(0,0,0,.22)).
static func skin_color_button(button: Button, color: Color) -> void:
	button.set_meta("skin_color", color)
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, button_box(color, state))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover_pressed", button_box(color, "pressed"))
	var ink := text_on(color)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(key, ink)
	button.add_theme_color_override("font_disabled_color", UiTheme.TEXT_DIM)
	button.add_theme_font_override("font", UiTheme.mono(true))
	_text_shadow(button, ink == UiTheme.ON_COLOR)

## Renkli zemindeki beyaz yazının sert gölgesi.
static func _text_shadow(control: Control, on: bool, alpha: float = 0.22, px: float = 3.0) -> void:
	if on:
		control.add_theme_color_override("font_shadow_color", Color(0, 0, 0, alpha))
		control.add_theme_constant_override("shadow_offset_x", 0)
		control.add_theme_constant_override("shadow_offset_y", maxi(1, int(round(UiTheme.d(px)))))
		control.add_theme_constant_override("shadow_outline_size", 0)
	else:
		control.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))

## Küçük düğme (vergi kademesi, çip boyu): ince kalınlık, gölgesiz. Renk
## skin_color_button'da verilen renktir.
static func compact(button: Button, pad_x: int = 6, _lip: int = 3) -> void:
	var color: Color = button.get_meta("skin_color", UiTheme.PANEL_LIGHT)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := chip_box(color, state)
		box.content_margin_left = pad_x
		box.content_margin_right = pad_x
		button.add_theme_stylebox_override(state, box)
	button.add_theme_stylebox_override("hover_pressed", chip_box(color, "pressed"))
	_text_shadow(button, false)

## SEKME düğmesi (VEKİL / PUAN, harita katmanları, sağ sütun sekmeleri):
## HTML .tab — pasif krem, seçili hardal; yazı Siyaset Display.
static func skin_tab(button: Button, active: bool, dim: bool = false) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, tab_box(active, state))
	button.add_theme_stylebox_override("hover_pressed", tab_box(active, "pressed"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := UiTheme.TEXT_ON_GOLD if active else UiTheme.TAB_TEXT
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(key, ink)
	button.add_theme_color_override("font_disabled_color", Color(UiTheme.TAB_TEXT, 0.45))
	button.add_theme_font_override("font", UiTheme.mono(true))
	button.modulate.a = 0.45 if dim else 1.0
	_text_shadow(button, false)

## MENÜ düğmesi (deniz yeşili).
static func skin_menu_button(button: Button) -> void:
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, menu_box(state))
	button.add_theme_stylebox_override("hover_pressed", menu_box("pressed"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(key, UiTheme.ON_COLOR)
	button.add_theme_font_override("font", UiTheme.mono(true))
	_text_shadow(button, true, 0.25, 2.0)

## Renkli bir "yüzey" (parti rengi, çizgi, dolgu): yuvarlak köşeli düz panel.
static func color_surface(color: Color) -> Panel:
	var rect := Panel.new()
	rect.add_theme_stylebox_override("panel", flat(color, 3))
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
static func panel_background() -> Panel:
	var rect := Panel.new()
	rect.add_theme_stylebox_override("panel", board())
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
	# Reapplying identical styles reallocates BoardBoxes and invalidates layout.
	var skin_key := [color, available]
	if button.get_meta("action_skin_key", []) == skin_key:
		return
	button.set_meta("action_skin_key", skin_key)
	# Pasif hamle: HTML'deki YARDIM gibi gri gövde, açık yazı.
	skin_color_button(button, color if available else UiTheme.TEXT_DIM)
	if not available:
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(key, Color("E9E3D6"))
	_tint_icon(button)

## ORTAK TEMA (main_theme.tres) açılışta masa oyunu yüzeyleriyle doldurulur:
## sahnelerin hepsi aynı tema kaynağını kullandığı için tek yerden değişir.
static var _theme_installed := false

static func install_theme() -> void:
	if _theme_installed:
		return
	_theme_installed = true
	var theme := load("res://assets/ui/main_theme.tres") as Theme
	if theme == null:
		return
	for state in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(state, "Button", button_box(UiTheme.PANEL_LIGHT, state))
	theme.set_stylebox("hover_pressed", "Button", button_box(UiTheme.PANEL_LIGHT, "pressed"))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_font("font", "Button", UiTheme.mono(true))
	theme.set_stylebox("panel", "Panel", board())
	theme.set_stylebox("panel", "PanelContainer", board())
	var field := groove()
	field.content_margin_left = UiTheme.d(16)
	field.content_margin_right = UiTheme.d(16)
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("read_only", "LineEdit", field)
	var focus := field.copy()
	focus.rings = [[0.0, UiTheme.d(3), UiTheme.TEAL]]
	theme.set_stylebox("focus", "LineEdit", focus)
	var track := groove()
	track.set_radius(UiTheme.d(6))
	track.set_content_margin_all(UiTheme.d(5))
	for cls in ["HScrollBar", "VScrollBar"]:
		theme.set_stylebox("scroll", cls, track)
		for key in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var grab := _bb(UiTheme.EDGE if key == "grabber" else UiTheme.TEAL, 6)
			theme.set_stylebox(key, cls, grab)
	theme.set_stylebox("slider", "HSlider", track)
	var fill_area := _bb(UiTheme.GOLD, 6)
	theme.set_stylebox("grabber_area", "HSlider", fill_area)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill_area)
	for key in ["grabber", "grabber_highlight", "grabber_disabled"]:
		theme.set_icon(key, "HSlider", knob_texture())
