class_name ParliamentFlow
extends Control
## MECLİS AKIŞI SUNUMU (0.0.231): MECLİS düğmesiyle açılır, sıra
## GENSORU (uygunsa) → GRUP TOPLANTISI → YASA. Her aşama ortada
## büyük bir kartla gelir; oyuncu aşamanın hamlesini yapar ya da BU TUR GEÇ der.
## Hangi aşamada olunduğu ve neyin kapandığı CardManager'dan okunur (otorite
## orada): pencereyi kapatmak ("Haritaya dön") hakkı yenilemez, MECLİS düğmesi
## kalınan yerden açar. Oylama başlayınca pencere çekilir, oylama ve gerekirse
## hükümet kurma bitince kendiliğinden geri gelir.
## Yasa aşaması bir çalışma alanıdır: grup yasası / vergi / anayasa mevcut yasa
## tasarlama penceresinde açılır (law_tab_requested), erken seçim buradan sunulur.

signal law_tab_requested(tab: int)
signal toast_requested(text: String)

const WIDTH := 600.0
const STAGE_TITLES := {"censure": "GENSORU", "speech": "GRUP TOPLANTISI", "law": "YASA"}
const STAGE_SHORT := {"censure": "Gensoru", "speech": "Toplantı", "law": "Yasa"}
const STAGE_COLORS := {"censure": Color("A6325A"), "speech": Color("3FB586"), "law": Color("7647CC")}

## Oyuncu akışı açtı mı (oylama sonrası kendiliğinden geri gelsin diye).
var engaged := false
var _panel: PanelContainer
var _body: VBoxContainer
var _shown_stage := ""
var _shown_key := ""
var _dim: ColorRect

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 115
	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.02, 0.08, 0.4)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_body.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.add_child(_body)
	hide()

## MECLİS düğmesi: akışı kalınan aşamadan açar.
func open_flow() -> void:
	engaged = true
	_shown_key = ""
	refresh()

func close_flow() -> void:
	engaged = false
	hide()

## Durum değişti: açık aşama yeniden çizilir; oylama sırasında gizlenir.
func refresh() -> void:
	var me := multiplayer.get_unique_id()
	if not engaged:
		hide()
		return
	if not CardManager.can_act():
		# Oylama / hükümet kurma sürüyor ya da sıra bitti.
		hide()
		if CardManager.current_turn_peer_id() != me:
			engaged = false
		return
	var stage := CardManager.parliament_stage(me)
	if stage == "":
		engaged = false
		hide()
		toast_requested.emit(L.t("Meclis işleri bu tur için tamam."))
		return
	var key := "%s|%d|%s" % [stage, CardManager.round_number, ",".join(PackedStringArray(CardManager.parliament_closed_stages(me)))]
	key += "|%s|%s|%s" % [CardManager.can_propose_law(me), CardManager.can_propose_constitution(me), CardManager.can_early_election(me)]
	show()
	if key == _shown_key and visible:
		return
	var animate := stage != _shown_stage or _shown_key == ""
	_shown_key = key
	_shown_stage = stage
	_build(stage)
	if animate:
		# Yerleşimden (ertelenmiş _place) sonra: sarsıntı doğru konuma döner.
		_animate_in.call_deferred(stage)

func _build(stage: String) -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var color: Color = STAGE_COLORS.get(stage, UiTheme.GOLD)
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.PANEL_DARK
	style.border_color = color
	style.set_border_width_all(4)
	style.set_content_margin_all(UiTheme.PAD_L)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_offset = Vector2(6, 8)
	_panel.add_theme_stylebox_override("panel", style)
	_body.add_child(_progress(stage))
	var title := UiTheme.mono_label(L.t(STAGE_TITLES[stage]), 30, color.lightened(0.35), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(title)
	match stage:
		"censure":
			_build_censure()
		"speech":
			_build_speech()
		"law":
			_build_law()
	_body.add_child(UiTheme.rule())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	_body.add_child(footer)
	var away := Button.new()
	away.text = L.t("← Haritaya dön")
	away.tooltip_text = L.t("Akış yerinde kalır; MECLİS düğmesiyle kaldığın yerden devam edersin.")
	away.focus_mode = Control.FOCUS_NONE
	away.custom_minimum_size = Vector2(170, 46)
	UiSkin.skin_button(away)
	away.pressed.connect(close_flow)
	footer.add_child(away)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var me := multiplayer.get_unique_id()
	var law_used := stage == "law" and (CardManager.has_proposed_law_this_round(me) \
		or int(CardManager.early_requests.get(CardManager.party_of(me), -1)) == CardManager.round_number)
	var skip := Button.new()
	skip.text = L.t("BİTİR · SONRAKİ AŞAMA") if law_used else L.t("BU TUR GEÇ")
	skip.tooltip_text = L.t("Bu aşama bu tur kapanır, geri açılamaz.")
	skip.focus_mode = Control.FOCUS_NONE
	skip.custom_minimum_size = Vector2(230, 46)
	skip.add_theme_font_override("font", UiTheme.mono(true))
	skip.add_theme_font_size_override("font_size", 15)
	UiSkin.skin_color_button(skip, UiTheme.GREEN_DARK if law_used else UiTheme.RED_DARK)
	skip.pressed.connect(func(): CardManager.pass_parliament_stage(stage))
	footer.add_child(skip)
	var skip_note := PopupKit.note(L.t("Geçilen aşama bu tur yeniden açılmaz."), UiTheme.TEXT_DIM)
	skip_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_body.add_child(skip_note)
	_place()
	# Sarmalı yazıların yüksekliği bir kare sonra kesinleşir: yeniden yerleştir.
	_place.call_deferred()

## Küçük ilerleme şeridi: dört aşama, kapananlar ✓, açık olan renkli.
func _progress(current: String) -> Control:
	var me := multiplayer.get_unique_id()
	var closed := CardManager.parliament_closed_stages(me)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var reached := false
	for stage in CardManager.PARL_STAGES:
		var is_current := String(stage) == current
		reached = reached or is_current
		var text := L.t(STAGE_SHORT[stage])
		var tint := UiTheme.PANEL
		if is_current:
			tint = STAGE_COLORS[stage]
		elif closed.has(stage):
			text += " ✓"
			tint = UiTheme.GREEN_DARK
		elif not reached:
			text += " · " + L.t("yok")
		var chip := Label.new()
		chip.text = text
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.add_theme_font_override("font", UiTheme.mono(true))
		chip.add_theme_font_size_override("font_size", 12)
		chip.add_theme_color_override("font_color", UiTheme.TEXT if is_current or closed.has(stage) else UiTheme.TEXT_MUTED)
		var box := StyleBoxFlat.new()
		box.bg_color = tint
		box.set_content_margin_all(5)
		chip.add_theme_stylebox_override("normal", box)
		row.add_child(chip)
	return row

func _explain(text: String, color: Color = UiTheme.TEXT) -> void:
	var label := PopupKit.note(text, color, WIDTH)
	label.add_theme_font_size_override("font_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(label)

func _big_button(text: String, color: Color, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 56)
	button.add_theme_font_override("font", UiTheme.mono(true))
	button.add_theme_font_size_override("font_size", 17)
	UiSkin.skin_color_button(button, color)
	button.pressed.connect(action)
	return button

# --- Aşamalar ----------------------------------------------------------------------

func _build_censure() -> void:
	_explain(L.t("Hükümet meclisteki çoğunluğunu kaybetti. Hükümeti düşürmek için oylama isteyebilirsin."))
	_explain(L.t("Kabul edilirse hükümet düşer ve yeni hükümet kurulur; reddedilirse küçük bir itibar kaybı yaşarsın."), UiTheme.TEXT_MUTED)
	_body.add_child(_big_button(L.t("GENSORU VER · %s") % GameRules.cost_text(GameRules.CENSURE_FUNDS_COST), STAGE_COLORS["censure"], func():
		CardManager.censure()))

func _build_speech() -> void:
	_explain(L.t("Bir seçmen grubunun sorunlarını konuşarak o grubun desteğini kalıcı artırırsın. Karşıt grup biraz soğur."))
	var crisis := CardManager.crisis_group()
	if crisis != "":
		_explain(L.t("Gündemdeki kriz: %s. Bu grupla toplanmak ek ulusal destek getirir.") % VoterGroups.title(crisis), UiTheme.GOLD)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_body.add_child(grid)
	var me := multiplayer.get_unique_id()
	var core: Array = PartyManager.data_of(CardManager.party_of(me)).get("core", [])
	for group in VoterGroups.GROUP_IDS:
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 48)
		var tag := ""
		if core.has(group):
			tag = L.t("  ★ çekirdek")
		elif core.has(VoterGroups.opposite(group)):
			tag = L.t("  ⚠ karşıt")
		if group == crisis:
			tag += L.t("  · kriz")
		button.text = VoterGroups.title(group) + tag
		button.clip_text = true
		button.add_theme_font_size_override("font_size", 13)
		button.tooltip_text = L.t("%s ile toplan: %s") % [VoterGroups.title(group), String(VoterGroups.data(group).get("meeting", ""))]
		UiSkin.skin_color_button(button, VoterGroups.color(group).darkened(0.35))
		button.pressed.connect(func(): CardManager.make_speech(group))
		grid.add_child(button)

func _build_law() -> void:
	var me := multiplayer.get_unique_id()
	_explain(L.t("Meclise teklif getir. Her teklif oylanır; sonuç gelince bu ekrana dönersin. İşin bitince BİTİR'e bas."))
	var group_ok := CardManager.can_propose_law(me) and not CardManager.has_proposed_law_this_round(me, "group") and CardManager.has_seats(me)
	_body.add_child(_option(L.t("GRUP YASASI"), L.t("Bir seçmen grubu için yasa: o grup sana ısınır, karşıtı soğur. Geçerse puan."),
		CardManager.has_proposed_law_this_round(me, "group"), group_ok, func(): law_tab_requested.emit(0)))
	var tax_reason := CardManager.tax_law_block_reason(me)
	if CardManager.is_government_party(me):
		_body.add_child(_option(L.t("VERGİ YASASI"), L.t("Hükümet olarak vergi kademesini değiştir: hazineyi ve seçmenin ruh hâlini etkiler."),
			CardManager.has_proposed_law_this_round(me, "tax"), tax_reason == "", func(): law_tab_requested.emit(1)))
	_body.add_child(_option(L.t("ANAYASA DEĞİŞİKLİĞİ"), L.t("Baraj, seçim sıklığı, sayım yöntemi ve ittifak kuralı. Üçte iki çoğunluk gerekir."),
		CardManager.has_proposed_law_this_round(me, "constitution"), CardManager.can_propose_constitution(me), func(): law_tab_requested.emit(2)))
	var early_done := int(CardManager.early_requests.get(CardManager.party_of(me), -1)) == CardManager.round_number
	if not CardManager.is_government_party(me) or CardManager.can_early_election(me):
		_body.add_child(_option(L.t("ERKEN SEÇİM ÖNERGESİ"), L.t("Kabul edilirse bu dönemin sonunda sandık kurulur."),
			early_done, CardManager.can_early_election(me), func(): CardManager.early_election()))

## Yasa alanındaki bir seçenek: ad, günlük dille sonucu, durum.
func _option(title: String, text: String, done: bool, available: bool, action: Callable) -> Control:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 54)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = "%s%s\n%s" % [title, L.t("  ✓ sunuldu") if done else ("" if available else L.t("  · şu an yok")), text]
	button.add_theme_font_size_override("font_size", 12)
	button.disabled = done or not available
	UiSkin.skin_color_button(button, STAGE_COLORS["law"].darkened(0.2) if available and not done else UiTheme.PANEL)
	button.pressed.connect(action)
	return button

# --- Yerleşim ve animasyon --------------------------------------------------------

func _place() -> void:
	_panel.size = Vector2.ZERO
	_panel.reset_size()
	var size := _panel.get_combined_minimum_size()
	_panel.size = size
	_panel.pivot_offset = size * 0.5
	_panel.position = (get_viewport_rect().size - size) * 0.5 - Vector2(0, 40)

func _animate_in(stage: String) -> void:
	_panel.pivot_offset = _panel.size * 0.5
	if stage == "censure":
		# Gensoru: diğerlerinden güçlü — kırmızı parlama, damga gibi iniş, sarsıntı.
		AudioManager.play("censure_open")
		var flash := ColorRect.new()
		flash.color = Color(0.85, 0.1, 0.15, 0.55)
		flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(flash)
		move_child(flash, 1)
		var ft := create_tween()
		ft.tween_property(flash, "color:a", 0.0, 0.7)
		ft.tween_callback(flash.queue_free)
		_panel.scale = Vector2(1.8, 1.8)
		_panel.modulate.a = 0.0
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(_panel, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_panel, "modulate:a", 1.0, 0.2)
		var base := _panel.position
		var shake := create_tween()
		shake.tween_interval(0.3)
		for i in 6:
			shake.tween_property(_panel, "position", base + Vector2(8.0 if i % 2 == 0 else -8.0, 0), 0.04)
		shake.tween_property(_panel, "position", base, 0.04)
		return
	_panel.scale = Vector2(0.9, 0.9)
	_panel.modulate.a = 0.0
	var tw2 := create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw2.tween_property(_panel, "modulate:a", 1.0, 0.15)
