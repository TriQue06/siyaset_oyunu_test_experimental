class_name TurnIntro
extends Control
## TUR BAŞI SUNUMU (0.0.231, yalnız kendi sıramda): ortada animasyonlu KART ÇEK
## (ya da ATLA: bu sıra kart yok) → ŞANS KARTI ortada açılır, ~1,5 sn görünüp kendiliğinden kapanır
## (düğme yok; ANINDA / OLUMSUZ: "uygulandı", SAKLANABİLİR: ele uçar) → afet
## sürüyorsa YARDIM sahnesi. Ekrana dokunmak açılış animasyonunu HIZLANDIRIR,
## karar değildir; yardımdan vazgeçmek ayrı düğmedir (BU TUR YARDIM YAPMA).
## Gazete oynarken sunum bekler (bkz. hold).
## Karar ve hak durumu CardManager.turn_flow'dan okunur: sahne kapanıp açılsa,
## oyuncu yeniden bağlansa da hak yenilenmez, bonus tekrar verilmez.

signal finished

const CARD_SIZE := Vector2(250, 380)
const REVEAL_IN := 0.35
const REVEAL_OUT := 0.35
## Kart açıldıktan sonra ekranda kalma süresi (giriş animasyonu dahil ~1,5 sn).
const CARD_HOLD := 1.15
## Tam ekran sunumların arka planı hafif kararır.
const DIM_ALPHA := 0.45

## WAIT: KART ÇEK'e basıldı, çekimin olayı bekleniyor (afet sahnesi karttan önce açılmasın).
enum Mode { NONE, PROMPT, REVEAL, AID, WAIT }

## Elin ekrandaki dikdörtgeni (saklanabilir kart oraya uçar).
var hand_rect: Callable = func() -> Rect2: return Rect2(Vector2(16, 560), Vector2(500, 130))
var mode: int = Mode.NONE
var _dim: ColorRect
var _layer: Control
var _queue: Array = []
var _speed := 1.0
var _aid_panel: AidPanel
var _aid_box: Control
var _shown_aid_for := -1
## Olay gazetesi oynarken sunum bekler (üst üste iki pencere açılmasın).
var hold: Callable = func() -> bool: return false
var _waiting := false
var _held_draws: Array = []
var _reveal_token := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 125
	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.02, 0.08, DIM_ALPHA)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_input)
	_dim.hide()
	add_child(_dim)
	_layer = Control.new()
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer)
	hide()

func is_busy() -> bool:
	return mode != Mode.NONE

func _process(_delta: float) -> void:
	# Gazete (seçim sonucu, hükümet) oynarken bekleyen sunum gizlenir; gazeteler
	# bitince açılır (üst üste binmez).
	if mode in [Mode.PROMPT, Mode.AID, Mode.WAIT]:
		visible = not hold.call()
	if _waiting and not hold.call():
		_waiting = false
		if not _held_draws.is_empty():
			var draws := _held_draws
			_held_draws = []
			present(draws)
		else:
			refresh()

## Durum değişti: hangi sahnenin görünmesi gerektiğine bakılır.
func refresh() -> void:
	if mode == Mode.REVEAL:
		return
	if mode == Mode.NONE and hold.call():
		_waiting = true
		return
	var me := multiplayer.get_unique_id()
	if CardManager.needs_turn_draw(me):
		if mode != Mode.PROMPT:
			_show_prompt()
		return
	if mode == Mode.PROMPT:
		# Kart çekildi; olay (present) birazdan gelir. Gelmezse (yeniden bağlanma) kısa süre sonra devam.
		mode = Mode.WAIT
		get_tree().create_timer(2.0).timeout.connect(func():
			if mode == Mode.WAIT:
				mode = Mode.NONE
				refresh())
		return
	if mode == Mode.WAIT:
		return
	if CardManager.aid_pending(me) and not CardManager.is_turn_blocked():
		var id := int(CardManager.active_disaster().get("id", 0))
		if mode != Mode.AID or _shown_aid_for != id:
			_show_aid(id)
		return
	if mode == Mode.AID:
		_close()

## Kendi çekimimin olayı geldi: kartlar sırayla açılır.
func present(draws: Array) -> void:
	# Gazete oynuyorsa önce o biter, şans kartı sonra açılır.
	if hold.call():
		_held_draws = draws.duplicate()
		_waiting = true
		return
	_queue = draws.duplicate()
	if _queue.is_empty():
		# ATLA ile çekim yapılmadı: KART ÇEK ekranı kapanır, sıradaki sahneye geçilir.
		if mode in [Mode.PROMPT, Mode.WAIT]:
			_reveal_next()
		else:
			refresh()
		return
	_clear_layer()
	mode = Mode.REVEAL
	_speed = 1.0
	show()
	_dim.show()
	_reveal_next()

func _close() -> void:
	mode = Mode.NONE
	_shown_aid_for = -1
	_clear_layer()
	_dim.hide()
	hide()
	finished.emit()

func _clear_layer() -> void:
	_reveal_token += 1
	for child in _layer.get_children():
		child.queue_free()
	if _aid_panel != null and is_instance_valid(_aid_panel):
		_aid_panel.queue_free()
	_aid_panel = null
	_aid_box = null

## Dokunmak animasyonu hızlandırır (karar değildir).
func _on_dim_input(event: InputEvent) -> void:
	if mode == Mode.REVEAL and (event is InputEventMouseButton or event is InputEventScreenTouch) and event.is_pressed():
		_speed = 4.0
		for tween in get_tree().get_processed_tweens():
			if tween.is_valid() and tween.has_meta("intro"):
				tween.set_speed_scale(_speed)

func _tween() -> Tween:
	var tween := create_tween()
	tween.set_meta("intro", true)
	tween.set_speed_scale(_speed)
	return tween

# --- KART ÇEK --------------------------------------------------------------------

func _show_prompt() -> void:
	_clear_layer()
	mode = Mode.PROMPT
	show()
	_dim.show()
	var frame := PanelContainer.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = UiTheme.PANEL_DARK
	frame_style.border_color = UiTheme.GOLD
	frame_style.set_border_width_all(3)
	frame_style.set_content_margin_all(UiTheme.PAD_L)
	frame_style.shadow_color = Color(0, 0, 0, 0.5)
	frame_style.shadow_offset = Vector2(6, 8)
	frame.add_theme_stylebox_override("panel", frame_style)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(frame)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(box)
	box.add_child(_centered(UiTheme.mono_label(L.t("SIRA SENDE"), 30, UiTheme.GOLD, true)))
	var note := PopupKit.note(L.t("Rastgele bir kart çek ya da bu sıra atla. Kart ya hemen etki eder ya da eline gelir."), UiTheme.TEXT, 420)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_centered(note))
	var button := Button.new()
	# 0.0.246: kart simgesi Material "playing_cards" (yazının solunda, yazı renginde).
	button.text = L.t("KART ÇEK")
	button.icon = cards_icon()
	button.add_theme_constant_override("h_separation", 14)
	button.add_theme_constant_override("icon_max_width", 48)
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(300, 92)
	button.add_theme_font_override("font", UiTheme.mono(true))
	button.add_theme_font_size_override("font_size", 28)
	UiSkin.skin_color_button(button, UiTheme.GOLD_DIM)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(key, UiTheme.TEXT)
	for key in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(key, UiTheme.TEXT)
	var skip := Button.new()
	skip.text = L.t("ATLA  ▸")
	skip.focus_mode = Control.FOCUS_NONE
	skip.custom_minimum_size = Vector2(150, 56)
	skip.add_theme_font_override("font", UiTheme.mono(true))
	skip.add_theme_font_size_override("font_size", 18)
	UiSkin.skin_color_button(skip, UiTheme.GOLD_DIM)
	button.pressed.connect(func():
		button.disabled = true
		skip.disabled = true
		button.text = L.t("Çekiliyor…")
		CardManager.draw_turn_card())
	skip.pressed.connect(func():
		button.disabled = true
		skip.disabled = true
		CardManager.skip_turn_draw())
	box.add_child(_centered(button))
	box.add_child(_centered(skip))
	var timer_note := PopupKit.note(L.t("Bu ekran tur süreni harcamaz; bir süre basmazsan kart kendiliğinden çekilir."), UiTheme.TEXT_MUTED, 420)
	timer_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_centered(timer_note))
	frame.reset_size()
	frame.position = (get_viewport_rect().size - frame.get_combined_minimum_size()) * 0.5
	# Nabız: okunaklı ama ekranı sallamayan büyüme / parlama.
	button.pivot_offset = button.custom_minimum_size * 0.5
	var pulse := create_tween().set_loops()
	pulse.tween_property(button, "scale", Vector2(1.07, 1.07), 0.55).set_trans(Tween.TRANS_SINE)
	pulse.parallel().tween_property(button, "modulate", Color(1.25, 1.15, 0.8), 0.55).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(button, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_SINE)
	pulse.parallel().tween_property(button, "modulate", Color.WHITE, 0.55).set_trans(Tween.TRANS_SINE)
	button.tree_exiting.connect(pulse.kill)
	frame.modulate.a = 0.0
	var appear := create_tween()
	appear.tween_property(frame, "modulate:a", 1.0, 0.25)

func _centered(control: Control) -> Control:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(control)
	return center

# --- KART AÇILIŞI ------------------------------------------------------------------

func _reveal_next() -> void:
	if _queue.is_empty():
		mode = Mode.NONE
		_clear_layer()
		_dim.hide()
		hide()
		refresh()  # sırada afet kararı olabilir
		if mode == Mode.NONE:
			finished.emit()
		return
	var entry: Dictionary = _queue.pop_front()
	var card := String(entry.get("card", ""))
	var result := String(entry.get("result", ""))
	var face := _card_face(entry)
	_layer.add_child(face)
	# Kart 1,5 sn görünür, sonra kendiliğinden kapanır (düğme yok).
	var skip := Control.new()
	skip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(skip)
	var view := get_viewport_rect().size
	var center := Vector2((view.x - CARD_SIZE.x) * 0.5 - 60.0, (view.y - CARD_SIZE.y) * 0.5)
	skip.position = center + Vector2(CARD_SIZE.x + 24.0, CARD_SIZE.y * 0.5 - 28.0)
	skip.modulate.a = 0.0
	face.position = center + Vector2(0, 60)
	face.pivot_offset = CARD_SIZE * 0.5
	face.scale = Vector2(0.35, 0.35)
	face.rotation = -0.25
	face.modulate.a = 0.0
	AudioManager.play("card_drawn")
	var tw := _tween()
	tw.set_parallel(true)
	tw.tween_property(face, "position", center, REVEAL_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(face, "scale", Vector2.ONE, REVEAL_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(face, "rotation", 0.0, REVEAL_IN)
	tw.tween_property(face, "modulate:a", 1.0, REVEAL_IN * 0.6)
	tw.tween_property(skip, "modulate:a", 1.0, REVEAL_IN)
	var token := _reveal_token
	tw.chain().tween_interval(CARD_HOLD)
	tw.chain().tween_callback(func():
		if token != _reveal_token:
			return
		_dismiss_card(face, skip, result, token))

## Kartı kapatır: saklanabilir kart ele uçar, anında kart parlayıp kaybolur.
func _dismiss_card(face: Control, skip: Control, result: String, token: int) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(skip, "modulate:a", 0.0, REVEAL_OUT * 0.5)
	if result == "hand":
		var target := hand_rect.call() as Rect2
		var dest := target.position + target.size * 0.5 - CARD_SIZE * 0.5
		tw.tween_property(face, "position", dest, REVEAL_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(face, "scale", Vector2(0.35, 0.35), REVEAL_OUT)
		tw.tween_property(face, "modulate:a", 0.0, REVEAL_OUT)
	else:
		tw.tween_property(face, "scale", Vector2(1.25, 1.25), REVEAL_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(face, "modulate:a", 0.0, REVEAL_OUT)
	tw.chain().tween_callback(func():
		# Sahne bu arada temizlendiyse (yeni çekim, kapanış) eski zincir devam etmez.
		if token != _reveal_token:
			return
		if is_instance_valid(face):
			face.queue_free()
		if is_instance_valid(skip):
			skip.queue_free()
		_reveal_next())

## Kart türünün sunum rengi ve üst şerit yazısı.
func _card_style(card: String, result: String) -> Array:
	if card == "":
		return [UiTheme.TEXT_MUTED, L.t("EL DOLU")]
	if result == "hand":
		return [UiTheme.GREEN, L.t("SAKLANABİLİR · ELİNE EKLENDİ")]
	if CardManager.is_negative_card(card):
		return [UiTheme.RED, L.t("OLUMSUZ · HEMEN UYGULANDI")]
	return [UiTheme.GOLD, L.t("ANINDA ETKİ · UYGULANDI")]

## Ortada açılan şans kartı: renkli üst şerit (türü), görsel, ad, etkisi bir
## çerçevede, varsa sonucu (ör. ceza tutarı).
func _card_face(entry: Dictionary) -> Control:
	var card := String(entry.get("card", ""))
	var result := String(entry.get("result", ""))
	var style_info := _card_style(card, result)
	var accent: Color = style_info[0]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = CARD_SIZE
	panel.size = CARD_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.PANEL_DARK
	style.border_color = accent
	style.set_border_width_all(4)
	style.set_corner_radius_all(0)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 12
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 10
	style.shadow_offset = Vector2(4, 8)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	# Üst şerit: "ŞANS KARTI" ve türü.
	var ribbon := PanelContainer.new()
	var ribbon_style := StyleBoxFlat.new()
	ribbon_style.bg_color = accent.darkened(0.25)
	ribbon_style.corner_radius_top_left = 0
	ribbon_style.corner_radius_top_right = 0
	ribbon_style.set_content_margin_all(6)
	ribbon.add_theme_stylebox_override("panel", ribbon_style)
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ribbon)
	var ribbon_box := VBoxContainer.new()
	ribbon_box.add_theme_constant_override("separation", 0)
	ribbon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.add_child(ribbon_box)
	ribbon_box.add_child(_centered_label(L.t("ŞANS KARTI"), 11, UiTheme.INK if accent == UiTheme.GOLD else UiTheme.TEXT))
	ribbon_box.add_child(_centered_label(String(style_info[1]), 10, UiTheme.INK if accent == UiTheme.GOLD else UiTheme.TEXT))
	if card == "":
		box.add_child(_centered_label(L.t("Elin dolu"), 22, UiTheme.TEXT))
		box.add_child(_framed_text(L.t("Elinde en fazla %d kart durabilir; bu tur kart çekilmedi. Elindeki kartları oynayarak yer açabilirsin.") % CardManager.MAX_HAND_SIZE, accent))
		return panel
	# Görsel: kenarlardan içeride, çerçeveli.
	var art_frame := PanelContainer.new()
	var art_style := StyleBoxFlat.new()
	art_style.bg_color = UiTheme.INK
	art_style.border_color = accent.darkened(0.3)
	art_style.set_border_width_all(2)
	art_style.set_corner_radius_all(0)
	art_frame.add_theme_stylebox_override("panel", art_style)
	art_frame.custom_minimum_size = Vector2(CARD_SIZE.x - 32.0, 132)
	art_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	art_frame.clip_contents = true
	art_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(art_frame)
	var art := TextureRect.new()
	art.texture = CardPresets.get_card_texture(card)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if CardPresets.has_full_art(card) else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_frame.add_child(art)
	var title := _centered_label(CardPresets.card_title(card).to_upper(), 19, UiTheme.TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = CARD_SIZE.x - 24.0
	box.add_child(title)
	box.add_child(_framed_text(CardPresets.card_description(card), accent))
	if entry.has("amount"):
		box.add_child(_centered_label(L.t("Silinen: %s") % GameRules.cost_text(float(entry["amount"])), 14, UiTheme.RED.lightened(0.2)))
	return panel

func _centered_label(text: String, size: int, color: Color) -> Label:
	var label := UiTheme.mono_label(text, size, color, true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Kartın etki metni: hafif açık zeminli, kenarlıklı bir çerçevede.
func _framed_text(text: String, accent: Color) -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := PanelContainer.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(accent, 0.1)
	frame_style.border_color = Color(accent, 0.45)
	frame_style.set_border_width_all(1)
	frame_style.set_corner_radius_all(0)
	frame_style.set_content_margin_all(8)
	frame.add_theme_stylebox_override("panel", frame_style)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(frame)
	var label := PopupKit.note(text, UiTheme.TEXT, CARD_SIZE.x - 48.0)
	label.add_theme_font_size_override("font_size", 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	frame.add_child(label)
	return margin

# --- AFET YARDIM SAHNESİ ----------------------------------------------------------

func _show_aid(disaster_id: int) -> void:
	_clear_layer()
	mode = Mode.AID
	_shown_aid_for = disaster_id
	show()
	_dim.show()
	var me := multiplayer.get_unique_id()
	var active := CardManager.active_disaster()
	var kind := String(active.get("kind", ""))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(box)
	_aid_box = box
	var head := PanelContainer.new()
	var head_style := StyleBoxFlat.new()
	head_style.bg_color = Disaster.color(kind).darkened(0.55)
	head_style.border_color = Disaster.color(kind)
	head_style.set_border_width_all(3)
	head_style.set_content_margin_all(10)
	head.add_theme_stylebox_override("panel", head_style)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(row)
	var art := TextureRect.new()
	art.texture = Disaster.art(kind)
	art.custom_minimum_size = Vector2(120, 80)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.clip_contents = true
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(art)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	texts.add_child(UiTheme.mono_label(L.t("AFET: %s") % Disaster.title(kind).to_upper(), 22, UiTheme.TEXT, true))
	var names: Array = []
	for province_id in active.get("provinces", []):
		names.append(ElectionNightSim.province_name(String(province_id)))
	texts.add_child(PopupKit.note(L.t("Etkilenen iller: %s") % ", ".join(PackedStringArray(names)), UiTheme.TEXT, 300))
	texts.add_child(PopupKit.note(L.t("Bölgeye yardım götürürsen oradaki seçmen seni hatırlar."), UiTheme.TEXT_MUTED, 300))
	_aid_panel = AidPanel.new()
	_aid_panel.z_index = 0
	box.add_child(_aid_panel)
	_aid_panel.open(me)
	_aid_panel.set_cancel_text(L.t("BU TUR YARDIM YAPMA"))
	_aid_panel.confirmed.connect(func(party_m: float, state_m: float):
		if CardManager.can_aid(me, party_m, state_m):
			CardManager.aid(party_m, state_m)
			_close())
	_aid_panel.cancelled.connect(func():
		CardManager.skip_aid()
		_close())
	texts.add_child(PopupKit.note(L.t("Yardım yapmazsan bu tur bu ekran yeniden açılmaz. Afet sürerse sonraki sıranda yeniden karar verirsin."),
		UiTheme.GOLD, 300))
	box.reset_size()
	var size := box.get_combined_minimum_size()
	var final_pos := (get_viewport_rect().size - size) * 0.5
	box.position = final_pos + Vector2(0, 40)
	box.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(box, "position", final_pos, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "modulate:a", 1.0, 0.25)
	AudioManager.play("paper_slap")

## KART ÇEK simgesi (Material "playing_cards", beyaz; düğmede yazı rengine boyanır).
const CARDS_SVG := '<svg xmlns="http://www.w3.org/2000/svg" height="96" viewBox="0 -960 960 960" width="96" fill="#ffffff"><path d="m608-368 46-166-142-98-46 166 142 98ZM160-207l-33-16q-31-13-42-44.5t3-62.5l72-156v279Zm160 87q-33 0-56.5-24T240-201v-239l107 294q3 7 5 13.5t7 12.5h-39Zm206-5q-31 11-62-3t-42-45L245-662q-11-31 3-61.5t45-41.5l301-110q31-11 61.5 3t41.5 45l178 489q11 31-3 61.5T827-235L526-125Zm-28-75 302-110-179-490-301 110 178 490Zm62-300Z"/></svg>'
static var _cards_icon: Texture2D

static func cards_icon() -> Texture2D:
	if _cards_icon == null:
		var image := Image.new()
		image.load_svg_from_string(CARDS_SVG, 0.5)
		_cards_icon = ImageTexture.create_from_image(image)
	return _cards_icon
