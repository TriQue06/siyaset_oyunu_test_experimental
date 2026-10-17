class_name TurnIntro
extends Control
## TUR BAŞI SUNUMU (0.0.231, yalnız kendi sıramda): ortada animasyonlu KART ÇEK
## → çekilen kart(lar) ortada açılır (ANINDA ETKİ: "uygulandı" parıltısı;
## SAKLANABİLİR: sol alttaki ele uçar; bonus kartın ek çekimleri sırayla) →
## afet sürüyorsa YARDIM sahnesi. Ekrana dokunmak animasyonu HIZLANDIRIR, karar
## değildir; yardımdan vazgeçmek ayrı düğmedir (BU TUR YARDIM YAPMA).
## Karar ve hak durumu CardManager.turn_flow'dan okunur: sahne kapanıp açılsa,
## oyuncu yeniden bağlansa da hak yenilenmez, bonus tekrar verilmez.

signal finished

const CARD_SIZE := Vector2(210, 280)
const REVEAL_IN := 0.35
const REVEAL_HOLD := 1.4
const REVEAL_OUT := 0.35

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
	_dim.color = Color(0.03, 0.02, 0.08, 0.62)
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
	# Kendi KART ÇEK basışımın cevabı gazeteyi beklemez.
	if mode != Mode.PROMPT and mode != Mode.WAIT and hold.call():
		_held_draws = draws.duplicate()
		_waiting = true
		return
	_queue = draws.duplicate()
	if _queue.is_empty():
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
	var note := PopupKit.note(L.t("Önce kartını çek. Kart ya hemen etki eder ya da eline gelir."), UiTheme.TEXT, 420)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_centered(note))
	var button := Button.new()
	button.text = L.t("🂠  KART ÇEK")
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(300, 92)
	button.add_theme_font_override("font", UiTheme.mono(true))
	button.add_theme_font_size_override("font_size", 28)
	UiSkin.skin_color_button(button, UiTheme.GOLD_DIM)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(key, UiTheme.TEXT)
	button.pressed.connect(func():
		button.disabled = true
		button.text = L.t("Çekiliyor…")
		CardManager.draw_turn_card())
	box.add_child(_centered(button))
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
	var face := _card_face(card, result, bool(entry.get("bonus", false)))
	_layer.add_child(face)
	var center := get_viewport_rect().size * 0.5 - CARD_SIZE * 0.5
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
	tw.chain().tween_interval(REVEAL_HOLD)
	if result == "hand":
		var target := hand_rect.call() as Rect2
		var dest := target.position + target.size * 0.5 - CARD_SIZE * 0.5
		tw.chain().tween_property(face, "position", dest, REVEAL_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(face, "scale", Vector2(0.4, 0.4), REVEAL_OUT)
		tw.parallel().tween_property(face, "modulate:a", 0.0, REVEAL_OUT)
	else:
		tw.chain().tween_property(face, "scale", Vector2(1.3, 1.3), REVEAL_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(face, "modulate:a", 0.0, REVEAL_OUT)
	var token := _reveal_token
	tw.chain().tween_callback(func():
		# Sahne bu arada temizlendiyse (yeni çekim, kapanış) eski zincir devam etmez.
		if token != _reveal_token:
			return
		if is_instance_valid(face):
			face.queue_free()
		_reveal_next())

## Ortada açılan kart: görsel, ad, ne olduğu (anında / saklanabilir) ve açıklama.
func _card_face(card: String, result: String, bonus: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = CARD_SIZE
	panel.size = CARD_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.PANEL_DARK
	style.border_color = UiTheme.GOLD if result == "instant" else UiTheme.PANEL_LIGHT
	style.set_border_width_all(4)
	style.set_content_margin_all(8)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_offset = Vector2(6, 8)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var tag_text := L.t("EL DOLU")
	var tag_color := UiTheme.TEXT_MUTED
	match result:
		"instant":
			tag_text = L.t("ANINDA ETKİ · UYGULANDI")
			tag_color = UiTheme.GOLD
		"hand":
			tag_text = L.t("SAKLANABİLİR · ELİNE EKLENDİ")
			tag_color = UiTheme.GREEN
	if bonus:
		tag_text = L.t("BONUS ÇEKİM · ") + tag_text
	box.add_child(PopupKit.chip(tag_text, tag_color))
	if card == "":
		box.add_child(UiTheme.mono_label(L.t("Elin dolu"), 18, UiTheme.TEXT, true))
		box.add_child(PopupKit.note(L.t("Elinde en fazla %d kart durabilir; bu tur kart çekilmedi. Kart bozdurarak yer açabilirsin.") % CardManager.MAX_HAND_SIZE,
			UiTheme.TEXT_MUTED, CARD_SIZE.x - 20.0))
		return panel
	var art := TextureRect.new()
	art.texture = CardPresets.get_card_texture(card)
	art.custom_minimum_size = Vector2(0, 108)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if CardPresets.has_full_art(card) else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.clip_contents = true
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(art)
	var title := UiTheme.mono_label(CardPresets.card_title(card), 15, UiTheme.TEXT, true)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var text := PopupKit.note(CardPresets.card_description(card), UiTheme.TEXT_MUTED, CARD_SIZE.x - 20.0)
	text.add_theme_font_size_override("font_size", 10)
	box.add_child(text)
	return panel

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
