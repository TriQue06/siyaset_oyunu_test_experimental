class_name PartyBadge
extends RefCounted
## Bir partinin "logosu": parti rengi + ikon. Oyun ekranındaki oyuncu panelinde
## (pixel-art çerçeveli) ve tur göstergesinde (prosedürel yuvarlak) kullanılır.
## game_screen.gd'den ayrıldı.

## Oyuncu panelindeki logoların pixel-art çerçevesi. Çerçevenin ortasındaki
## saydam delik, logonun görüneceği alandır; deliğin konumu/boyutu koda
## GÖMÜLMÜYOR, PNG taranarak bulunuyor (bkz. _ensure_frame_loaded) —
## çerçeveyi yeniden çizersen kod değişmeden uyar.
const FRAME_PATH := "res://assets/ui/party_profile_picture_frame.png"
## Çerçevenin büyütme katı. TAM SAYI olmalı, yoksa pixel-art bulanıklaşır.
const FRAME_SCALE := 2
const SHADOW_COLOR := Color(0, 0, 0, 0.38)

static var _frame_texture: Texture2D = null
static var _frame_interior := Rect2i()
static var _frame_loaded := false

## is_self=true ise kendi partin belirgin şekilde vurgulanır. use_frame=true
## ise prosedürel yuvarlak yerine pixel-art çerçeve kullanılır (çerçeve
## yüklenemezse prosedürel görünüme düşer).
static func build(party: Dictionary, size: Vector2, icon_pixel_size: int, is_self: bool = false, use_frame: bool = false) -> Control:
	if use_frame:
		_ensure_frame_loaded()
		if _frame_texture != null and _frame_interior.size.x > 0:
			return _build_framed(party, icon_pixel_size, is_self)
	var wrap := Control.new()
	wrap.custom_minimum_size = size
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP

	var circle := Panel.new()
	# Rozetin içindekiler tamamen DEKORATİF — fare girdisini yutmasınlar.
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circle.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = party.get("bg_color", Color(0.3, 0.3, 0.3))
	style.set_corner_radius_all(int(size.y / 2.0))
	if is_self:
		style.set_border_width_all(4)
		style.border_color = Color(1.0, 0.82, 0.15, 1.0)
		style.shadow_size = 10
		style.shadow_color = Color(1.0, 0.82, 0.15, 0.45)
		style.shadow_offset = Vector2.ZERO
	else:
		style.set_border_width_all(2)
		style.border_color = Color(1, 1, 1, 0.5)
		style.shadow_size = 6
		style.shadow_color = SHADOW_COLOR
		style.shadow_offset = Vector2(2, 3)
	circle.add_theme_stylebox_override("panel", style)
	wrap.add_child(circle)

	if party.has("icon_index"):
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = PartyPresets.get_icon_texture(party["icon_index"], icon_pixel_size)
		icon.modulate = party.get("icon_color", Color.WHITE)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		var margin := size.y * 0.22
		icon.offset_left = margin
		icon.offset_top = margin
		icon.offset_right = -margin
		icon.offset_bottom = -margin
		wrap.add_child(icon)

	return wrap

## Çerçeve PNG'sini yükler ve ORTASINDAKİ SAYDAM DELİĞİ bulur. Deliği
## "dışarıdan flood fill" ile buluyoruz: kenarlardan erişilebilen saydam
## pikseller DIŞARISI; geriye kalan saydam pikseller çerçevenin içindeki delik.
static func _ensure_frame_loaded() -> void:
	if _frame_loaded:
		return
	_frame_loaded = true
	_frame_texture = load(FRAME_PATH)
	if _frame_texture == null:
		push_warning("Parti çerçevesi bulunamadı: %s" % FRAME_PATH)
		return
	var image := _frame_texture.get_image()
	if image == null:
		return
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)

	var w := image.get_width()
	var h := image.get_height()
	var outside := {}
	var stack: Array[Vector2i] = []
	for x in w:
		stack.append(Vector2i(x, 0))
		stack.append(Vector2i(x, h - 1))
	for y in h:
		stack.append(Vector2i(0, y))
		stack.append(Vector2i(w - 1, y))
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		if outside.has(p):
			continue
		if image.get_pixel(p.x, p.y).a >= 0.04:
			continue
		outside[p] = true
		stack.append(Vector2i(p.x + 1, p.y))
		stack.append(Vector2i(p.x - 1, p.y))
		stack.append(Vector2i(p.x, p.y + 1))
		stack.append(Vector2i(p.x, p.y - 1))

	var min_p := Vector2i(w, h)
	var max_p := Vector2i(-1, -1)
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			if image.get_pixel(x, y).a >= 0.04 or outside.has(p):
				continue
			min_p = min_p.min(p)
			max_p = max_p.max(p)
	if max_p.x < min_p.x:
		push_warning("Parti çerçevesinde saydam iç boşluk bulunamadı: %s" % FRAME_PATH)
		return
	_frame_interior = Rect2i(min_p, max_p - min_p + Vector2i.ONE)

## Çizim sırası: parti rengi -> ikon -> ÇERÇEVE -> hedef vurgusu. Renk ve ikon
## deliğin sınır kutusunu doldurur; kutunun köşeleri çerçevenin opak halkasının
## altında kaldığı için dışarıdan tam daire görünür.
static func _build_framed(party: Dictionary, icon_pixel_size: int, is_self: bool) -> Control:
	var frame_size := Vector2(_frame_texture.get_size()) * FRAME_SCALE
	var interior_pos := Vector2(_frame_interior.position) * FRAME_SCALE
	var interior_size := Vector2(_frame_interior.size) * FRAME_SCALE

	var wrap := Control.new()
	wrap.custom_minimum_size = frame_size
	wrap.size = frame_size
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP

	var fill := ColorRect.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.color = party.get("bg_color", Color(0.3, 0.3, 0.3))
	fill.position = interior_pos
	fill.size = interior_size
	wrap.add_child(fill)

	if party.has("icon_index"):
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = PartyPresets.get_icon_texture(party["icon_index"], icon_pixel_size)
		icon.modulate = party.get("icon_color", Color.WHITE)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Delik yuvarlak; ikon köşelere taşıp kırpılmasın diye biraz içeri al.
		var inset := interior_size * 0.14
		icon.position = interior_pos + inset
		icon.size = interior_size - inset * 2.0
		wrap.add_child(icon)

	var frame := TextureRect.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.texture = _frame_texture
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.size = frame_size
	if is_self:
		frame.modulate = Color(1.35, 1.12, 0.55, 1.0)
	wrap.add_child(frame)

	# Hedef seçerken (vekil çalma / rakibe ideoloji kartı) yanan vurgu.
	var halo := TextureRect.new()
	halo.name = "TargetHalo"
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.texture = load("res://assets/ui/target_highlight.png")
	halo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.size = frame_size
	halo.hide()
	wrap.add_child(halo)

	return wrap
