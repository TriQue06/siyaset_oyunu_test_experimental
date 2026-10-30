class_name ParliamentFlow
extends Control
## MECLİS (0.0.246): MECLİS düğmesiyle açılan pencere. Üstte parti kurma
## ekranındaki adımlar gibi SEKMELER: GENSORU · YASA.
## Sıra yok: oyuncu istediği sekmeyi açar. Bir sekmenin hamlesi yapılınca o
## sekme bu sıra kapanır (✓, tıklanamaz). Kullanılamayan sekme sönük durur.
## Hangi sekmenin kapandığı CardManager'dan okunur (otorite orada): pencereyi
## kapatmak hakkı yenilemez. Oylama başlayınca pencere çekilir, oylama ve
## gerekirse hükümet kurma bitince kendiliğinden geri gelir.
## YASA sekmesi seçenekleri (grup yasası / vergi / anayasa) aynı pencerede
## açılır: yasa tasarlama alanı law_host'a gömülüdür (bkz. GameScreen),
## "Geri" meclis sekmelerine döndürür.

signal law_tab_requested(tab: int)
signal toast_requested(text: String)

const WIDTH := 640.0
const STAGE_TITLES := {"censure": "GENSORU", "law": "YASA"}
const STAGE_COLORS := {"censure": Color("A6325A"), "law": Color("7647CC")}

## Oyuncu pencereyi açtı mı (oylama sonrası kendiliğinden geri gelsin diye).
var engaged := false
var _panel: PanelContainer
var _body: VBoxContainer
var _tabs_row: HBoxContainer
var _content: VBoxContainer
## Yasa tasarlama alanının gömüldüğü kutu (GameScreen doldurur; hiç silinmez).
var law_host: VBoxContainer
var _tab := ""
var _law_page := false
var _shown_key := ""
var _dim: ColorRect
## 0.0.300: MECLİS düğmesi hiç sönmez. Yapılacak iş yokken (ya da sıra başkasındayken)
## pencere yine açılır; sekmeler ve seçenekler sönük, yalnız görüntülenir.
var _view_only := false

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
	# 0.0.260: düğmeler ve diğer paneller gibi konturlu panel.
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.PANEL_DARK
	style.set_content_margin_all(UiTheme.PAD_L)
	UiSkin.apply_style(_panel, "panel", style)
	add_child(_panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_body.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.add_child(_body)
	_tabs_row = HBoxContainer.new()
	_tabs_row.add_theme_constant_override("separation", 6)
	_body.add_child(_tabs_row)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_content)
	law_host = VBoxContainer.new()
	law_host.add_theme_constant_override("separation", 6)
	law_host.hide()
	_body.add_child(law_host)
	hide()

## MECLİS düğmesi: ilk kullanılabilir sekmeyle açılır.
func open_flow() -> void:
	engaged = true
	_tab = ""
	_law_page = false
	_view_only = not CardManager.can_act() or not _any_open(multiplayer.get_unique_id())
	_shown_key = ""
	refresh()

func close_flow() -> void:
	engaged = false
	_law_page = false
	hide()

## YASA sekmesinde bir seçenek (0 grup, 1 vergi, 2 anayasa) aynı pencerede açılır.
func open_law_page(tab: int) -> void:
	engaged = true
	_tab = "law"
	_law_page = true
	_shown_key = ""
	refresh()
	law_tab_requested.emit(tab)
	relayout()

## Yasa sayfasından meclis sekmelerine dönüş (geri ya da teklif sunuldu).
func leave_law_page() -> void:
	if not _law_page:
		return
	_law_page = false
	_shown_key = ""
	refresh()

## Gömülü yasa alanı boyut değiştirdi: pencere yeniden ortalanır.
func relayout() -> void:
	_place()
	_place.call_deferred()

## Durum değişti: açık sekme yeniden çizilir; oylama sırasında gizlenir.
func refresh() -> void:
	var me := multiplayer.get_unique_id()
	if not engaged:
		hide()
		return
	if CardManager.is_turn_blocked() or (not _view_only and not CardManager.can_act()):
		# Oylama / hükümet kurma sürüyor ya da sıra bitti.
		hide()
		_law_page = false
		if CardManager.current_turn_peer_id() != me:
			engaged = false
		return
	if CardManager.can_act() and _any_open(me):
		_view_only = false
	if not _view_only and not _any_open(me):
		engaged = false
		_law_page = false
		hide()
		toast_requested.emit(L.t("Meclis işleri bu tur için tamam."))
		return
	# Açık sekme kapandıysa (hamle yapıldı) ilk kullanılabilir sekmeye geçilir.
	if _view_only:
		_law_page = false
		_tab = "law"
	elif _tab == "" or not CardManager.parliament_stage_available(me, _tab):
		_law_page = false
		_tab = _first_open(me)
	var key := "%s|%s|%s|%d|%d|%s" % [_tab, _law_page, _view_only, CardManager.current_turn_peer_id(), CardManager.round_number,
		",".join(PackedStringArray(CardManager.parliament_closed_stages(me)))]
	key += "|%s|%s|%s" % [CardManager.can_propose_law(me), CardManager.can_propose_constitution(me), CardManager.can_early_election(me)]
	var was_visible := visible
	show()
	if key == _shown_key and was_visible:
		return
	_shown_key = key
	_build()
	if not was_visible:
		_animate_in.call_deferred(_tab)

func _first_open(me: int) -> String:
	for stage in CardManager.PARL_STAGES:
		if CardManager.parliament_stage_available(me, String(stage)):
			return String(stage)
	return ""

func _any_open(me: int) -> bool:
	return _first_open(me) != ""

func _build() -> void:
	var me := multiplayer.get_unique_id()
	for child in _tabs_row.get_children():
		_tabs_row.remove_child(child)
		child.queue_free()
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	# SEKMELER (parti kurma ekranındaki adımlar gibi): seçili altın, kapanan
	# yeşil ✓ ve tıklanamaz, kullanılamayan sönük.
	var closed := CardManager.parliament_closed_stages(me)
	for stage in CardManager.PARL_STAGES:
		var id := String(stage)
		var done := closed.has(id)
		var available := CardManager.parliament_stage_available(me, id)
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 38)
		button.add_theme_font_override("font", UiTheme.mono(true))
		button.add_theme_font_size_override("font_size", 14)
		button.text = L.t(STAGE_TITLES[id]) + ("" if done else "")
		button.disabled = _view_only or done or not available
		var selected := id == _tab
		var color := UiTheme.GOLD if selected else (UiTheme.GREEN_DARK if done else UiTheme.PANEL_LIGHT)
		UiSkin.skin_color_button(button, color)
		var font_color := UiTheme.TEXT_ON_GOLD if selected else (UiTheme.TEXT if available or done else UiTheme.TEXT_DIM)
		for prop in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
			button.add_theme_color_override(prop, font_color)
		button.pressed.connect(func():
			_tab = id
			_law_page = false
			_shown_key = ""
			refresh())
		_tabs_row.add_child(button)
	law_host.visible = _law_page
	# Yasa sayfasında içerik üstte kalır, artan boşluk pencerenin dibinde.
	_content.size_flags_vertical = Control.SIZE_FILL if _law_page else Control.SIZE_EXPAND_FILL
	if _law_page:
		var back := Button.new()
		back.text = L.t("Geri")
		back.focus_mode = Control.FOCUS_NONE
		back.custom_minimum_size = Vector2(140, 40)
		UiSkin.skin_button(back)
		back.pressed.connect(leave_law_page)
		_content.add_child(back)
	else:
		var color: Color = STAGE_COLORS.get(_tab, UiTheme.GOLD)
		match _tab:
			"censure":
				_build_censure(color)
			"law":
				_build_law()
		# Alt düğme pencerenin dibinde: sekmeler arasında pencere boyu sabit.
		var filler := Control.new()
		filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
		filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(filler)
		_content.add_child(UiTheme.rule())
		var away := Button.new()
		away.text = L.t("Haritaya dön")
		away.focus_mode = Control.FOCUS_NONE
		away.custom_minimum_size = Vector2(170, 46)
		UiSkin.skin_button(away)
		away.pressed.connect(close_flow)
		_content.add_child(away)
	relayout()

func _explain(text: String, color: Color = UiTheme.TEXT) -> void:
	_content.add_child(explain_label(text, color))

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

# --- Sekmeler ----------------------------------------------------------------------

func _build_censure(color: Color) -> void:
	_explain(L.t("Hükümet meclisteki çoğunluğunu kaybetti. Hükümeti düşürmek için oylama isteyebilirsin."))
	_explain(L.t("Kabul edilirse hükümet düşer ve yeni hükümet kurulur; reddedilirse küçük bir itibar kaybı yaşarsın."), UiTheme.TEXT_MUTED)
	_content.add_child(_big_button(L.t("GENSORU VER · %s") % GameRules.cost_text(GameRules.CENSURE_FUNDS_COST), color, func():
		CardManager.censure()))

## SEKİZ SEÇMEN GRUBU DÜĞMESİ (iki sütun): grup yasası ekranı. Düğmeye
## basmak yasayı sunar.
static func group_grid(on_pick: Callable, available: Callable = func(_group: String) -> bool: return true) -> GridContainer:
	var crisis := CardManager.crisis_group()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for group in VoterGroups.GROUP_IDS:
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 48)
		button.disabled = not bool(available.call(group))
		UiSkin.skin_color_button(button, VoterGroups.color(group).darkened(0.35))
		# Simge + grup adı (gündemdeki krizse "· kriz").
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 10
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(row)
		var icon := VoterGroupIcon.make(group, 26.0)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		var label := Label.new()
		label.text = VoterGroups.title(group) + (L.t("  · kriz") if group == crisis else "")
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		label.add_theme_font_override("font", UiTheme.mono(true))
		label.add_theme_font_size_override("font_size", 14)
		# Renkli düğmelerdeki gibi beyaz yazı, altında sert gölge.
		label.add_theme_color_override("font_color", UiTheme.ON_COLOR)
		UiSkin._text_shadow(label, true)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)
		button.pressed.connect(func(): on_pick.call(group))
		grid.add_child(button)
	return grid

## Meclis penceresindeki açıklama satırı (yasa sayfası da kullanır).
static func explain_label(text: String, color: Color = UiTheme.TEXT) -> Label:
	var label := PopupKit.note(text, color, WIDTH)
	label.add_theme_font_size_override("font_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _build_law() -> void:
	var me := multiplayer.get_unique_id()
	_explain(L.t("Meclise bir teklif getir; teklif oylanır. Her yasa türü turda bir kez sunulur."))
	var group_ok := not _view_only and CardManager.can_propose_law(me) and not CardManager.has_proposed_law_this_round(me, "group") and CardManager.has_seats(me)
	_content.add_child(_option(L.t("GRUP YASASI"), L.t("Bir seçmen grubu için yasa: o grup sana ısınır, karşıtı soğur. Geçerse puan."),
		group_ok, func(): open_law_page(0)))
	_content.add_child(_option(L.t("VERGİ YASASI"), L.t("Vergi kademesini değiştir: hazineyi ve seçmenin ruh hâlini etkiler."),
		not _view_only and CardManager.tax_law_block_reason(me) == "", func(): open_law_page(1)))
	_content.add_child(_option(L.t("ANAYASA DEĞİŞİKLİĞİ"), L.t("Baraj, seçim sıklığı, sayım yöntemi ve ittifak kuralı. Üçte iki çoğunluk gerekir."),
		not _view_only and CardManager.can_propose_constitution(me), func(): open_law_page(2)))
	if not CardManager.is_government_party(me) or CardManager.can_early_election(me):
		_content.add_child(_option(L.t("ERKEN SEÇİM ÖNERGESİ"), L.t("Kabul edilirse bu dönemin sonunda sandık kurulur."),
			not _view_only and CardManager.can_early_election(me), func(): CardManager.early_election()))

## Yasa sekmesindeki bir seçenek: ad ve günlük dille sonucu.
func _option(title: String, text: String, available: bool, action: Callable) -> Control:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 54)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = "%s%s\n%s" % [title, "" if available else L.t("  · şu an yok"), text]
	button.add_theme_font_size_override("font_size", 12)
	button.disabled = not available
	UiSkin.skin_color_button(button, STAGE_COLORS["law"].darkened(0.2) if available else UiTheme.PANEL_LIGHT)
	button.pressed.connect(action)
	return button

# --- Yerleşim ve animasyon --------------------------------------------------------

## SABİT BOY (0.0.260): sekmeler ve yasa sayfaları arasında pencere boyu
## değişmez. Boy, en büyük sayfaya göre bir kez ölçülür (FIXED_SIZE) ve
## ekrandan büyükse ekrana sığdırılır; içerik ondan büyükse pencere büyür.
const FIXED_SIZE := Vector2(676, 525)
var fixed_size := FIXED_SIZE

func _place() -> void:
	_panel.size = Vector2.ZERO
	_panel.reset_size()
	var view := get_viewport_rect().size
	var size := _panel.get_combined_minimum_size()
	size = Vector2(maxf(size.x, minf(fixed_size.x, view.x - 16.0)), maxf(size.y, minf(fixed_size.y, view.y - 16.0)))
	_panel.size = size
	_panel.pivot_offset = size * 0.5
	_panel.position = Vector2((view.x - size.x) * 0.5, clampf((view.y - size.y) * 0.5 - 40.0, 8.0, maxf(8.0, view.y - size.y - 8.0)))

func _animate_in(stage: String) -> void:
	_panel.pivot_offset = _panel.size * 0.5
	if stage == "censure":
		# Gensoru: diğerlerinden güçlü — kırmızı parlama, damga gibi iniş.
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
		return
	_panel.scale = Vector2(0.9, 0.9)
	_panel.modulate.a = 0.0
	var tw2 := create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw2.tween_property(_panel, "modulate:a", 1.0, 0.15)
