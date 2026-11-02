class_name CardShop
extends Control
## KART PAZARI (0.0.328, konsept B "Pazar tezgâhı", bkz.
## konseptler/kart_magazasi_konseptleri.html): hamle alanındaki KART PAZARI
## düğmesiyle açılır. Çizgili tentenin altında ahşap tezgâh; ele giren kartlar
## hafif eğik dizilir, altlarında fiyat etiketi ve AL düğmesi. Üstüne gelince
## kart doğrulup kalkar; alınan kart küçülerek ele uçar. Altta parti kasası ve
## eldeki yerler. Kurallar CardManager'da (shop_cards / shop_price / buy_card).

signal closed
signal toast_requested(text: String)

const DESIGN := Vector2(1000, 540)
const CARD := Vector2(104, 152)
const TILTS := [-4.0, 3.0, -2.0, 4.0, -3.0, 2.0, -4.0]
const RED := Color("d93636")
const CREAM := Color("fff6e0")
const WOOD := Color("c9905c")
const WOOD_DARK := Color("a8693a")
const WOOD_EDGE := Color("7d4a26")

## Alınan kartın uçacağı yer (oyun ekranı verir).
var hand_rect: Callable = func() -> Rect2: return Rect2(Vector2(16, 560), Vector2(500, 130))

var _s := 1.0
var _stall: Control
var _row: HBoxContainer
var _purse: Label
var _slots: HBoxContainer
var _wares: Dictionary = {}   # card_type -> {"card", "price", "buy"}
var _key := ""
var _wait := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 120
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.08, 0.06, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close())
	var view := get_viewport_rect().size
	_s = clampf(minf(view.x / 1280.0, view.y / 720.0), 0.6, 2.0)
	_stall = Control.new()
	_stall.size = DESIGN * _s
	_stall.position = ((view - _stall.size) * 0.5 + Vector2(0, 16.0 * _s)).round()
	_stall.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_stall)
	_build()
	_rebuild_wares()
	# Açılış: hafifçe büyüyerek belirir (sade ve hızlı).
	_stall.pivot_offset = _stall.size * 0.5
	_stall.scale = Vector2(0.94, 0.94)
	_stall.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_stall, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_stall, "modulate:a", 1.0, 0.14)

func close() -> void:
	closed.emit()
	queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _px(v: float) -> float:
	return v * _s

func _build() -> void:
	# Tezgâh gövdesi (ahşap, alt kalınlık + gölge).
	var counter := Panel.new()
	var box := BoardBox.new()
	box.fill = WOOD
	box.fill_bottom = WOOD_DARK
	box.set_radius(_px(18))
	box.highlight_size = _px(4)
	box.highlight_color = Color(1, 1, 1, 0.18)
	box.lips = [[_px(10), WOOD_EDGE]]
	box.shadow_color = Color(0, 0, 0, 0.4)
	box.shadow_offset = Vector2(0, _px(20))
	box.shadow_size = _px(16)
	counter.add_theme_stylebox_override("panel", box)
	counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	counter.position = Vector2(0, _px(70))
	counter.size = Vector2(_stall.size.x, _stall.size.y - _px(70))
	_stall.add_child(counter)
	# Tente: kırmızı / krem çizgiler, altta dalgalı saçak.
	var awning := Control.new()
	awning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	awning.position = Vector2(-_px(14), 0)
	awning.size = Vector2(_stall.size.x + _px(28), _px(96))
	awning.draw.connect(func():
		var stripes := 11
		var w := awning.size.x / float(stripes)
		var h := _px(74)
		awning.draw_rect(Rect2(Vector2(0, h - _px(4)), Vector2(awning.size.x, _px(10))), Color(0, 0, 0, 0.18))
		for k in stripes:
			var c := RED if k % 2 == 0 else CREAM
			awning.draw_rect(Rect2(Vector2(k * w, 0), Vector2(w + 1.0, h)), c)
			awning.draw_circle(Vector2(k * w + w * 0.5, h), w * 0.5, c)
		awning.draw_rect(Rect2(Vector2.ZERO, Vector2(awning.size.x, _px(8))), Color(1, 1, 1, 0.25)))
	_stall.add_child(awning)
	# Tabela.
	var sign := PanelContainer.new()
	var sign_box := BoardBox.new()
	sign_box.fill = Color("b5743f")
	sign_box.fill_bottom = WOOD_DARK
	sign_box.set_radius(_px(12))
	sign_box.lips = [[_px(5), WOOD_EDGE]]
	sign_box.shadow_color = Color(0, 0, 0, 0.3)
	sign_box.shadow_offset = Vector2(0, _px(6))
	sign_box.shadow_size = _px(6)
	sign_box.content_margin_left = _px(26)
	sign_box.content_margin_right = _px(26)
	sign_box.content_margin_top = _px(8)
	sign_box.content_margin_bottom = _px(12)
	sign.add_theme_stylebox_override("panel", sign_box)
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sign.add_child(_label(L.t("KART PAZARI"), 30, CREAM, true))
	_stall.add_child(sign)
	sign.reset_size()
	sign.position = Vector2((_stall.size.x - sign.get_combined_minimum_size().x) * 0.5, -_px(30))
	# Kartlar.
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", int(_px(24)))
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.position = Vector2(_px(20), _px(126))
	_row.size = Vector2(_stall.size.x - _px(40), _px(290))
	_stall.add_child(_row)
	# Alt şerit: kasa ve el.
	var purse_box := PanelContainer.new()
	var purse_style := BoardBox.new()
	purse_style.fill = UiTheme.PANEL
	purse_style.set_radius(_px(14))
	purse_style.rings = [[0.0, _px(2), Color("e3d5b0")]]
	purse_style.lips = [[_px(4), Color("c9b689")]]
	purse_style.content_margin_left = _px(14)
	purse_style.content_margin_right = _px(16)
	purse_style.content_margin_top = _px(6)
	purse_style.content_margin_bottom = _px(8)
	purse_box.add_theme_stylebox_override("panel", purse_style)
	purse_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var purse_col := VBoxContainer.new()
	purse_col.add_theme_constant_override("separation", 0)
	purse_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	purse_box.add_child(purse_col)
	purse_col.add_child(_label(L.t("PARTİ KASASI"), 11, UiTheme.TEXT_MUTED, false))
	_purse = _label("", 24, UiTheme.GREEN_DARK, true)
	purse_col.add_child(_purse)
	_stall.add_child(purse_box)
	purse_box.reset_size()
	purse_box.position = Vector2(_px(28), _stall.size.y - _px(26) - purse_box.get_combined_minimum_size().y)
	var hand_box := HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", int(_px(8)))
	hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_box.add_child(_label(L.t("ELİN"), 13, CREAM, true))
	_slots = HBoxContainer.new()
	_slots.add_theme_constant_override("separation", int(_px(6)))
	_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_box.add_child(_slots)
	_stall.add_child(hand_box)
	hand_box.position = Vector2(_stall.size.x - _px(28) - _px(60) - CardManager.MAX_HAND_SIZE * _px(30), _stall.size.y - _px(64))
	# Kapat.
	var close_button := Button.new()
	close_button.text = "X"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(_px(44), _px(44))
	close_button.add_theme_font_override("font", UiTheme.mono(true))
	close_button.add_theme_font_size_override("font_size", int(_px(20)))
	UiSkin.skin_color_button(close_button, RED)
	close_button.add_theme_color_override("font_color", Color.WHITE)
	close_button.pressed.connect(close)
	_stall.add_child(close_button)
	close_button.position = Vector2(_stall.size.x - _px(30), _px(52))

func _label(text: String, size_px: float, color: Color, display: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.mono(true) if display else UiTheme.mono_regular())
	label.add_theme_font_size_override("font_size", int(_px(size_px)))
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Satılan kartlar değişince (popülizm başladı, ilk seçim yapıldı) dizilim yenilenir.
func _rebuild_wares() -> void:
	var me := multiplayer.get_unique_id()
	var cards := CardManager.shop_cards(me)
	for child in _row.get_children():
		child.queue_free()
	_wares.clear()
	for i in cards.size():
		_row.add_child(_ware(String(cards[i]), float(TILTS[i % TILTS.size()])))
	_key = ",".join(PackedStringArray(cards))
	_refresh()

func _ware(card_type: String, tilt: float) -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", int(_px(10)))
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	var holder := Control.new()
	holder.custom_minimum_size = CARD * _s
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(holder)
	var card := CollectorCard.make(card_type, CARD * _s)
	card.pivot_offset = CARD * _s * Vector2(0.5, 1.0)
	card.rotation_degrees = tilt
	holder.add_child(card)
	holder.mouse_entered.connect(func(): _lift(card, true, tilt))
	holder.mouse_exited.connect(func(): _lift(card, false, tilt))
	holder.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_buy(card_type, card))
	# Fiyat etiketi (krem, solda ip deliği).
	var tag := PanelContainer.new()
	var tag_style := StyleBoxFlat.new()
	tag_style.bg_color = CREAM
	tag_style.set_corner_radius_all(int(_px(8)))
	tag_style.shadow_color = Color(0, 0, 0, 0.2)
	tag_style.shadow_offset = Vector2(0, _px(3))
	tag_style.content_margin_left = _px(16)
	tag_style.content_margin_right = _px(10)
	tag_style.content_margin_top = _px(4)
	tag_style.content_margin_bottom = _px(5)
	tag.add_theme_stylebox_override("panel", tag_style)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var price := _label("", 17, UiTheme.INK, true)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_child(price)
	tag.draw.connect(func(): tag.draw_circle(Vector2(_px(8), tag.size.y * 0.5), _px(3), WOOD_EDGE))
	col.add_child(tag)
	var buy := Button.new()
	buy.focus_mode = Control.FOCUS_NONE
	buy.custom_minimum_size = Vector2(CARD.x * _s, _px(36))
	buy.add_theme_font_override("font", UiTheme.mono(true))
	buy.add_theme_font_size_override("font_size", int(_px(15)))
	buy.pressed.connect(func(): _buy(card_type, card))
	col.add_child(buy)
	_wares[card_type] = {"card": card, "price": price, "buy": buy}
	return col

func _lift(card: Control, up: bool, tilt: float) -> void:
	var tw := card.create_tween().set_parallel(true)
	tw.tween_property(card, "position:y", -_px(10) if up else 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "rotation_degrees", 0.0 if up else tilt, 0.12)
	tw.tween_property(card, "scale", Vector2(1.06, 1.06) if up else Vector2.ONE, 0.12)

func _buy(card_type: String, card: Control) -> void:
	var me := multiplayer.get_unique_id()
	var reason := CardManager.buy_block_reason(me, card_type)
	if reason != "":
		toast_requested.emit(reason)
		return
	_fly(card)
	CardManager.buy_card(card_type)
	_refresh()

## Alınan kartın kopyası küçülerek ele uçar (0,3 sn).
func _fly(card: Control) -> void:
	var ghost := CollectorCard.make(String(card.get("card_type")), CARD * _s)
	ghost.z_index = 5
	add_child(ghost)
	ghost.global_position = card.global_position
	ghost.pivot_offset = Vector2.ZERO
	var target := hand_rect.call() as Rect2
	var dest := target.position + target.size * 0.5 - CARD * _s * 0.25
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_property(ghost, "global_position", dest, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(ghost, "scale", Vector2(0.5, 0.5), 0.3)
	tw.tween_property(ghost, "modulate:a", 0.0, 0.3).set_delay(0.12)
	tw.chain().tween_callback(ghost.queue_free)

func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 0.2
	var key := ",".join(PackedStringArray(CardManager.shop_cards(multiplayer.get_unique_id())))
	if key != _key:
		_rebuild_wares()
	else:
		_refresh()

func _refresh() -> void:
	var me := multiplayer.get_unique_id()
	_purse.text = Economy.money_full(CardManager.funds_of(me))
	var hand := CardManager.my_inventory().size()
	if _slots.get_child_count() != CardManager.MAX_HAND_SIZE:
		for child in _slots.get_children():
			child.queue_free()
		for k in CardManager.MAX_HAND_SIZE:
			var slot := Panel.new()
			slot.custom_minimum_size = Vector2(_px(22), _px(30))
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_slots.add_child(slot)
	for k in _slots.get_child_count():
		var slot := _slots.get_child(k) as Panel
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(int(_px(5)))
		if k < hand:
			style.bg_color = UiTheme.GOLD
		else:
			style.bg_color = Color(0, 0, 0, 0.12)
			style.border_color = Color(CREAM, 0.55)
			style.set_border_width_all(int(maxf(1.0, _px(2))))
		slot.add_theme_stylebox_override("panel", style)
	var full := hand >= CardManager.MAX_HAND_SIZE
	for card_type in _wares.keys():
		var ware: Dictionary = _wares[card_type]
		var price := CardManager.shop_price(String(card_type))
		(ware["price"] as Label).text = Economy.money_full(price)
		var buy := ware["buy"] as Button
		var ok := CardManager.can_buy_card(me, String(card_type))
		buy.text = L.t("EL DOLU") if full else L.t("AL · %s") % Economy.money_full(price)
		UiSkin.skin_color_button(buy, UiTheme.GREEN_DARK if ok else UiTheme.PANEL_DARK)
		var font := Color.WHITE if ok else UiTheme.TEXT_MUTED
		for prop in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			buy.add_theme_color_override(prop, font)
		(ware["card"] as Control).modulate = Color.WHITE if CardManager.funds_of(me) + 0.001 >= price else Color(0.72, 0.72, 0.72)
