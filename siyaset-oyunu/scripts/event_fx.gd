class_name EventFx
extends Control
## OLAY GAZETESİ (0.0.179): büyük siyasi olaylardan sonra ekrana bir gazete
## ön sayfası fırlatılır, masaya çarpar, manşeti ve küçük bir resmi gösterir,
## sonra ekrandan çıkar (~2,8 sn). Oyunun imza efekti.
##
## YALNIZ SUNUMDUR: oyun sonucu önceden host'ta hesaplanıp uygulanmıştır; bu
## düğüm hiçbir oyun verisini değiştirmez, ağ mesajı göndermez, girdi
## kilitlemez (sadece gazetenin kendisi tıklanabilir: tıklamak geçer).
##   - present(anahtar, veri): aynı anahtar ikinci kez gösterilmez (anahtarlar
##     sahne değişse de hatırlanır: seçim gecesinden dönünce tekrar oynamaz).
##   - Kuyruk: aynı anda tek gazete; bütün haberler korunur, birikince
##     sıradakiler daha hızlı oynar.
##   - Geçme: gazeteye tıkla ya da Boşluk / Esc. skip_all() hepsini temizler.
##   - Ayarlar → "Olay Animasyonları" kapalıysa hiçbir şey oynamaz.
##
## veri: {"headline", "subtitle", "art": Texture2D, "party": peer_id,
##  "accent": Color, "status": kısa sonuç etiketi, "stamp": damga yazısı,
##  "style": "plain" | "scandal" | "conflict", "sound": damga anındaki ses}

const PAPER_SIZE := Vector2(560, 300)
const PAPER := Color("F1EAD8")
const INK := Color("1C1A2E")
const INK_SOFT := Color(0.11, 0.10, 0.18, 0.78)
const LINE := Color(0.11, 0.10, 0.18, 0.18)
## Süreler (sn). Toplam ≈ IN + SETTLE + REVEAL + HOLD + OUT ≈ 2,8.
const IN_TIME := 0.34
const SETTLE_TIME := 0.16
const REVEAL_TIME := 0.22
const HOLD_TIME := 1.75
const OUT_TIME := 0.3
signal drained
## Kuyrukta bekleyen varken oynatma hızı (birikmesin).
const CATCH_UP_SPEED := 1.7

static var _seen: Array = []

var speed := 1.0
var _queue: Array = []
var _active := false
var _holder: Control
var _shadow: Control
var _parts: Array = []        # sayfanın parçaları (bölünme için iki yarı)
var _reveal_nodes: Array = []
var _reveal_tween: Tween
var _tween: Tween
var _current: Dictionary = {}

func _ready() -> void:
	top_level = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 90

## Olayı kuyruğa koyar. Gösterilecekse true (anahtar daha önce görüldüyse,
## animasyonlar kapalıysa false).
func present(key: String, data: Dictionary) -> bool:
	if key != "":
		if _seen.has(key):
			return false
		_seen.append(key)
		while _seen.size() > 128:
			_seen.pop_front()
	if not GameSettings.event_fx:
		return false
	_queue.append(data)
	if not _active:
		_next()
	return true

func is_playing() -> bool:
	return _active

## Oynayan gazeteyi hemen kaldırır (sonraki varsa o başlar).
func skip() -> void:
	if not _active:
		return
	_clear_current()
	_active = false
	_next()

## Hepsini temizler (sahne değişirken, oyun biterken).
func skip_all() -> void:
	_queue.clear()
	_clear_current()
	_active = false

func _input(event: InputEvent) -> void:
	if not _active:
		return
	var advance: bool = event is InputEventKey and event.pressed and event.keycode in [KEY_SPACE, KEY_ESCAPE]
	advance = advance or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	advance = advance or (event is InputEventScreenTouch and event.pressed)
	if advance:
		skip()
		get_viewport().set_input_as_handled()

func _clear_current() -> void:
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_reveal_tween = null
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()
	_holder = null
	_shadow = null
	_parts.clear()
	_reveal_nodes.clear()

func _next() -> void:
	if _active or not is_inside_tree():
		return
	if _queue.is_empty():
		drained.emit()
		return
	_active = true
	_current = _queue.pop_front()
	var rate := speed * (CATCH_UP_SPEED if not _queue.is_empty() else 1.0)
	_build(_current)
	_play(rate)

# --- Zaman çizelgesi ----------------------------------------------------------

func _play(rate: float) -> void:
	var view := get_viewport_rect().size
	var final_pos := Vector2(round((view.x - PAPER_SIZE.x) * 0.5), round(view.y * 0.44 - PAPER_SIZE.y * 0.5))
	# A) Fırlatma: sol alttan, hafif dönük ve büyük (kameraya yakın) gelir.
	_holder.position = Vector2(-PAPER_SIZE.x * 0.8, view.y + 30.0)
	_holder.rotation = deg_to_rad(-22.0)
	_holder.scale = Vector2(1.32, 1.32)
	_shadow.position = Vector2(26, 30)
	_tween = create_tween()
	_tween.set_speed_scale(rate)
	_tween.tween_property(_holder, "position", final_pos, IN_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_holder, "rotation", deg_to_rad(-2.5), IN_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_holder, "scale", Vector2.ONE, IN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# B) Çarpma: ses tam bu anda; kısa sekme, gölge kâğıda yapışır.
	_tween.tween_callback(func(): AudioManager.play("paper_slap"))
	_tween.tween_property(_holder, "scale", Vector2(0.965, 0.965), SETTLE_TIME * 0.35).set_trans(Tween.TRANS_SINE)
	_tween.parallel().tween_property(_shadow, "position", Vector2(6, 8), SETTLE_TIME * 0.35)
	_tween.tween_property(_holder, "scale", Vector2.ONE, SETTLE_TIME * 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# C) Manşet: soldan sağa açılır, damga / şerit düşer.
	_tween.tween_callback(_reveal.bind(rate))
	_tween.tween_interval(REVEAL_TIME + HOLD_TIME)
	# D) Çıkış.
	_tween.tween_callback(_exit.bind(rate))

func _reveal(rate: float) -> void:
	var t := create_tween().set_speed_scale(rate).set_parallel(true)
	_reveal_tween = t
	for node in _reveal_nodes:
		var item := node as CanvasItem
		var c := node as Control
		match String(item.get_meta("reveal", "fade")):
			"wipe":
				var full := c.size.x
				c.size.x = 0.0
				c.modulate.a = 1.0
				t.tween_property(c, "size:x", full, REVEAL_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			"stamp":
				c.scale = Vector2(2.2, 2.2)
				t.tween_property(c, "modulate:a", 1.0, REVEAL_TIME * 0.6)
				t.tween_property(c, "scale", Vector2.ONE, REVEAL_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			"ribbon":
				var to := c.position
				c.position.x = -c.size.x - 40.0
				c.modulate.a = 1.0
				t.tween_property(c, "position", to, REVEAL_TIME * 1.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			_:
				t.tween_property(item, "modulate:a", 1.0, REVEAL_TIME)
	var sound := String(_current.get("sound", ""))
	if sound != "":
		AudioManager.play(sound)

func _exit(rate: float) -> void:
	if _holder == null:
		return
	var view := get_viewport_rect().size
	var t := create_tween().set_speed_scale(rate)
	_tween = t
	if String(_current.get("style", "")) == "conflict" and _parts.size() == 2:
		# BÖLÜNME: sayfa ortadan çatlar, iki yarı ters yönlere ayrılır.
		var left := _parts[0] as Control
		var right := _parts[1] as Control
		left.pivot_offset = Vector2(PAPER_SIZE.x * 0.5, PAPER_SIZE.y * 0.5)
		right.pivot_offset = Vector2(0, PAPER_SIZE.y * 0.5)
		t.set_parallel(true)
		t.tween_property(left, "position", left.position + Vector2(-90, 40), OUT_TIME * 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(left, "rotation", deg_to_rad(-9.0), OUT_TIME * 1.6)
		t.tween_property(right, "position", right.position + Vector2(90, 40), OUT_TIME * 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(right, "rotation", deg_to_rad(9.0), OUT_TIME * 1.6)
		t.tween_property(_holder, "modulate:a", 0.0, OUT_TIME * 1.6).set_delay(OUT_TIME * 0.4)
		t.set_parallel(false)
	else:
		t.tween_property(_holder, "position", Vector2(view.x + 40.0, _holder.position.y + 120.0), OUT_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(_holder, "rotation", deg_to_rad(12.0), OUT_TIME)
	t.tween_callback(func():
		_clear_current()
		_active = false
		_next())

# --- Sayfa ----------------------------------------------------------------------

func _build(data: Dictionary) -> void:
	_holder = Control.new()
	_holder.size = PAPER_SIZE
	_holder.pivot_offset = PAPER_SIZE * 0.5
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	_shadow = _rect(Vector2.ZERO, PAPER_SIZE, Color(0, 0, 0, 0.45))
	_holder.add_child(_shadow)
	if String(data.get("style", "")) == "conflict":
		# İki yarı: aynı sayfa iki kez kurulur, her biri yarısını kırparak gösterir.
		for half in 2:
			var clip := Control.new()
			clip.clip_contents = true
			clip.position = Vector2(PAPER_SIZE.x * 0.5 * half, 0)
			clip.size = Vector2(PAPER_SIZE.x * 0.5, PAPER_SIZE.y)
			clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_holder.add_child(clip)
			var sheet := _sheet(data, half == 0)
			sheet.position = Vector2(-PAPER_SIZE.x * 0.5 * half, 0)
			clip.add_child(sheet)
			_parts.append(clip)
		var crack := Line2D.new()
		crack.width = 2.0
		crack.default_color = Color(INK, 0.55)
		var x := PAPER_SIZE.x * 0.5
		var y := 0.0
		var flip := 1.0
		while y < PAPER_SIZE.y:
			crack.add_point(Vector2(x + 7.0 * flip, y))
			flip = -flip
			y += 22.0
		crack.add_point(Vector2(x, PAPER_SIZE.y))
		crack.modulate.a = 0.0
		crack.set_meta("reveal", "fade")
		_holder.add_child(crack)
		_reveal_nodes.append(crack)
	else:
		var sheet := _sheet(data, true)
		_holder.add_child(sheet)
		_parts.append(sheet)
	var hint := Label.new()
	hint.text = L.t("Tıkla ya da Boşluk: geç")
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	hint.add_theme_color_override("font_outline_color", UiTheme.INK)
	hint.add_theme_constant_override("outline_size", 4)
	hint.position = Vector2(PAPER_SIZE.x - 170.0, PAPER_SIZE.y + 8.0)
	hint.size = Vector2(170, 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(hint)

## Sayfanın kendisi (bölünmede iki kopya kurulur; açılış ikisinde de oynar).
func _sheet(data: Dictionary, _primary: bool) -> Control:
	var accent: Color = data.get("accent", UiTheme.GOLD)
	var sheet := Control.new()
	sheet.size = PAPER_SIZE
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			skip())
	sheet.add_child(_rect(Vector2.ZERO, PAPER_SIZE, INK))
	sheet.add_child(_rect(Vector2(2, 2), PAPER_SIZE - Vector2(4, 4), PAPER))

	# Künye: gazete adı, dönem, çift çizgi, olay renginde ince şerit.
	var mast := _label(L.t("SİYASET GÜNDEMİ"), 18, INK, true)
	mast.position = Vector2(16, 8)
	sheet.add_child(mast)
	var issue := _label(L.t("%s · ÖZEL BASKI") % GameRules.period_label(CardManager.round_number), 11, INK_SOFT, false)
	issue.position = Vector2(PAPER_SIZE.x - 316, 13)
	issue.size = Vector2(300, 16)
	issue.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sheet.add_child(issue)
	sheet.add_child(_rect(Vector2(12, 34), Vector2(PAPER_SIZE.x - 24, 2), INK))
	sheet.add_child(_rect(Vector2(12, 38), Vector2(PAPER_SIZE.x - 24, 1), INK))
	sheet.add_child(_rect(Vector2(12, 42), Vector2(PAPER_SIZE.x - 24, 4), accent))

	# Resim: olayın kart resmi ya da büyük parti rozeti.
	var art_rect := Rect2(16, 56, 168, 228)
	sheet.add_child(_rect(art_rect.position - Vector2(2, 2), art_rect.size + Vector2(4, 4), INK))
	var art: Texture2D = data.get("art", null)
	var party := int(data.get("party", -1))
	if art != null:
		var pic := TextureRect.new()
		pic.texture = art
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		pic.position = art_rect.position
		pic.size = art_rect.size
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sheet.add_child(pic)
	else:
		# Rozet zemini koyu: aynı renkteki damga üstünde okunsun.
		sheet.add_child(_rect(art_rect.position, art_rect.size, accent.darkened(0.6)))
		if PartyManager.parties.has(party):
			var big := PartyBadge.build(PartyManager.data_of(party), Vector2(120, 120), 96)
			big.position = art_rect.position + (art_rect.size - Vector2(120, 120)) * 0.5
			big.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sheet.add_child(big)

	# Sağ sütun: parti satırı, manşet, alt başlık, süs çizgileri, sonuç etiketi.
	var col_x := 200.0
	var col_w := PAPER_SIZE.x - col_x - 18.0
	var y := 56.0
	if PartyManager.parties.has(party):
		var badge := PartyBadge.build(PartyManager.data_of(party), Vector2(28, 28), 22)
		badge.position = Vector2(col_x, y)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sheet.add_child(badge)
		var name_label := _label(String(PartyManager.data_of(party).get("name", "")), 15, INK, true)
		name_label.position = Vector2(col_x + 36, y + 4)
		name_label.size = Vector2(col_w - 36, 20)
		name_label.clip_text = true
		sheet.add_child(name_label)
		y += 36.0
	var headline := _label(String(data.get("headline", "")), 30, INK, true)
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	headline.add_theme_constant_override("line_spacing", -4)
	var head_h := 112.0
	headline.add_theme_font_size_override("font_size", _fit(headline.text, UiTheme.mono(true), col_w, head_h, 30, 16))
	headline.position = Vector2(col_x, y)
	headline.size = Vector2(col_w, head_h)
	headline.clip_contents = true
	sheet.add_child(headline)
	# Manşet soldan sağa açılır (kırpan kutu genişler).
	var wipe := Control.new()
	wipe.clip_contents = true
	wipe.position = headline.position
	wipe.size = headline.size
	wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.remove_child(headline)
	headline.position = Vector2.ZERO
	wipe.add_child(headline)
	sheet.add_child(wipe)
	wipe.set_meta("reveal", "wipe")
	wipe.modulate.a = 0.0
	_reveal_nodes.append(wipe)
	y += head_h + 4.0
	var subtitle := String(data.get("subtitle", ""))
	if subtitle != "":
		var sub := Label.new()
		sub.text = subtitle
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.max_lines_visible = 3
		sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sub.add_theme_font_size_override("font_size", 12)
		sub.add_theme_color_override("font_color", INK_SOFT)
		sub.position = Vector2(col_x, y)
		sub.size = Vector2(col_w, 54)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sub.modulate.a = 0.0
		sub.set_meta("reveal", "fade")
		sheet.add_child(sub)
		_reveal_nodes.append(sub)
	# İkincil gazete içeriği: okunmaz soyut satırlar (sahte metin yok).
	var lines_y := PAPER_SIZE.y - 48.0
	for i in 3:
		var w := col_w * (0.55 + 0.15 * float((i * 7) % 3))
		sheet.add_child(_rect(Vector2(col_x, lines_y + i * 9.0), Vector2(w * 0.6, 3), LINE))
	var status := String(data.get("status", ""))
	if status != "":
		var chip := PanelContainer.new()
		UiSkin.apply_style(chip, "panel", UiSkin.color_box(accent))
		var chip_label := _label(status, 12, Color.WHITE if accent.get_luminance() < 0.6 else INK, true)
		chip.add_child(chip_label)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sheet.add_child(chip)
		chip.reset_size()
		var chip_size := chip.get_combined_minimum_size()
		chip.position = Vector2(PAPER_SIZE.x - 18.0 - chip_size.x, PAPER_SIZE.y - 18.0 - chip_size.y)
		chip.modulate.a = 0.0
		chip.set_meta("reveal", "fade")
		_reveal_nodes.append(chip)
	# Damga: sonuç (KAZANDI, DÜŞTÜ ...) resmin üstüne eğik basılır.
	var stamp_text := String(data.get("stamp", ""))
	if stamp_text != "":
		var stamp := PanelContainer.new()
		UiSkin.apply_style(stamp, "panel", UiSkin.color_box(accent, UiSkin.TARGET))
		var stamp_label := _label(stamp_text, 20, accent, true)
		stamp_label.add_theme_color_override("font_outline_color", PAPER)
		stamp_label.add_theme_constant_override("outline_size", 6)
		stamp.add_child(stamp_label)
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sheet.add_child(stamp)
		stamp.reset_size()
		var stamp_size := stamp.get_combined_minimum_size()
		stamp.position = art_rect.position + Vector2((art_rect.size.x - stamp_size.x) * 0.5, art_rect.size.y - stamp_size.y - 16.0)
		stamp.pivot_offset = stamp_size * 0.5
		stamp.rotation = deg_to_rad(-8.0)
		stamp.modulate.a = 0.0
		stamp.set_meta("reveal", "stamp")
		_reveal_nodes.append(stamp)
	# Skandal şeridi: resmin üstünden kayarak geçen kırmızı "SON DAKİKA".
	if String(data.get("style", "")) == "scandal":
		var ribbon := PanelContainer.new()
		UiSkin.apply_style(ribbon, "panel", UiSkin.color_box(accent))
		ribbon.add_child(_label(L.t("SON DAKİKA"), 14, Color.WHITE, true))
		ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sheet.add_child(ribbon)
		ribbon.reset_size()
		ribbon.position = Vector2(4, 64)
		ribbon.rotation = deg_to_rad(-6.0)
		ribbon.modulate.a = 0.0
		ribbon.set_meta("reveal", "ribbon")
		_reveal_nodes.append(ribbon)
	return sheet

func _label(text: String, size: int, color: Color, mono: bool) -> Label:
	var label := Label.new()
	label.text = text
	if mono:
		label.add_theme_font_override("font", UiTheme.mono(true))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Düz renk alan (çizgi, çerçeve, kâğıt): ince çizgiler 9-slice dokuyla
## çizilemediği için ColorRect.
func _rect(pos: Vector2, rect_size: Vector2, color: Color) -> Control:
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = pos
	r.size = rect_size
	return r

## Manşet kutuya sığana kadar küçülür (sözcük kısaltılmaz).
static func _fit(text: String, font: Font, width: float, height: float, largest: int, smallest: int) -> int:
	for size in range(largest, smallest - 1, -1):
		var longest := 0.0
		for word in text.split(" "):
			longest = maxf(longest, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
		if longest > width:
			continue
		if font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, size).y <= height:
			return size
	return smallest
